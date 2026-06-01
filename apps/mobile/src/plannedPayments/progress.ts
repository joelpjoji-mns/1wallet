import {
    futureRuleOccurrenceDates,
    plannedPaymentRuleStats,
    type PlannedPaymentRuleStats,
} from '@1wallet/ledger/rules/futureGeneration';
import type { FutureGenerationRule, LedgerState } from '@1wallet/ledger/store/types';

export type PlannedRuleProgressSummary = {
  completedOccurrences: number;
  totalOccurrences?: number;
  remainingOccurrences?: number;
  remainingAmount?: { amountMinor: number; currency: string };
  progress?: number;
  complete: boolean;
};

export function plannedRuleProgressSummary(
  state: LedgerState,
  rule: FutureGenerationRule,
  stats: PlannedPaymentRuleStats = plannedPaymentRuleStats(state, rule),
): PlannedRuleProgressSummary {
  const actualCompletedOccurrences = Math.max(
    0,
    stats.posted + stats.voided + (rule.skippedOccurrences?.length ?? 0),
  );
  const completedOccurrences = Math.max(
    actualCompletedOccurrences,
    elapsedRuleOccurrenceCount(rule, new Date()),
  );
  const totalOccurrences = plannedRuleTotalOccurrences(rule, completedOccurrences);
  const cappedCompleted =
    totalOccurrences !== undefined
      ? Math.min(completedOccurrences, totalOccurrences)
      : completedOccurrences;
  const remainingOccurrences =
    totalOccurrences !== undefined ? Math.max(0, totalOccurrences - cappedCompleted) : undefined;
  const complete = plannedRuleIsComplete(rule, stats, remainingOccurrences);

  return {
    completedOccurrences: cappedCompleted,
    totalOccurrences,
    remainingOccurrences,
    remainingAmount:
      remainingOccurrences === undefined
        ? undefined
        : {
            amountMinor: Math.max(0, remainingOccurrences * rule.amountMinor),
            currency: rule.currency,
          },
    progress: totalOccurrences
      ? Math.max(0, Math.min(1, cappedCompleted / totalOccurrences))
      : undefined,
    complete,
  };
}

function plannedRuleTotalOccurrences(
  rule: FutureGenerationRule,
  completedOccurrences: number,
): number | undefined {
  if (rule.occurrences !== undefined) {
    return Math.max(completedOccurrences, Math.max(0, rule.occurrences));
  }
  if (rule.endsOn) {
    return Math.max(completedOccurrences, boundedRuleOccurrenceCount(rule));
  }
  return undefined;
}

function plannedRuleIsComplete(
  rule: FutureGenerationRule,
  stats: PlannedPaymentRuleStats,
  remainingOccurrences: number | undefined,
): boolean {
  if (rule.occurrences !== undefined) return remainingOccurrences === 0;
  if (rule.endsOn && hasRuleEnded(rule.endsOn)) return remainingOccurrences === 0;
  if (rule.endsOn) return stats.scheduled === 0 && remainingOccurrences === 0;
  return false;
}

function hasRuleEnded(endsOn: string): boolean {
  const [year, month, day] = endsOn.split('-').map((part) => Number(part));
  if (!year || !month || !day) return false;
  const tomorrowAfterEnd = new Date(year, month - 1, day + 1);
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  return tomorrowAfterEnd <= today;
}

function elapsedRuleOccurrenceCount(rule: FutureGenerationRule, now: Date): number {
  const startsOn = localDateFromDateOnly(rule.startsOn);
  if (!startsOn) return 0;
  const today = startOfLocalDay(now);
  if (startsOn >= today) return 0;
  const endsOn = rule.endsOn ? localDateFromDateOnly(rule.endsOn) : undefined;
  const yesterday = addLocalDays(today, -1);
  const horizonEnd = endsOn && endsOn < yesterday ? endsOn : yesterday;
  if (horizonEnd < startsOn) return 0;
  return futureRuleOccurrenceDates(rule, {
    now: startsOn,
    horizonEnd,
    includeSkipped: true,
    maxOccurrences: Math.max(rule.occurrences ?? 0, 1200),
  }).length;
}

function boundedRuleOccurrenceCount(rule: FutureGenerationRule): number {
  if (!rule.endsOn) return 0;
  const startsOn = localDateFromDateOnly(rule.startsOn);
  const endsOn = localDateFromDateOnly(rule.endsOn);
  if (!startsOn || !endsOn || endsOn < startsOn) return 0;
  return futureRuleOccurrenceDates(rule, {
    now: startsOn,
    horizonEnd: endsOn,
    includeSkipped: true,
    maxOccurrences: Math.max(rule.occurrences ?? 0, 1200),
  }).length;
}

function startOfLocalDay(value: Date): Date {
  return new Date(value.getFullYear(), value.getMonth(), value.getDate());
}

function addLocalDays(value: Date, days: number): Date {
  const next = new Date(value);
  next.setDate(next.getDate() + days);
  return startOfLocalDay(next);
}

function localDateFromDateOnly(value: string): Date | undefined {
  const [year, month, day] = value.split('-').map((part) => Number(part));
  return year && month && day ? new Date(year, month - 1, day) : undefined;
}
