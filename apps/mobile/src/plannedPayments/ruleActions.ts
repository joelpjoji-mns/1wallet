import { normalizeCurrencyCode } from '@1wallet/domain/money';
import type { Transaction } from '@1wallet/domain/types';
import { loanRuleOccurrenceAmounts, syncLoanDetailsFromRule } from '@1wallet/ledger/loans';
import type { FutureRuleOccurrence } from '@1wallet/ledger/rules/futureGeneration';
import {
    createFutureGenerationRule,
    futureRuleExternalRef,
    futureRuleInterestExternalRef,
    futureRuleOccurrenceDates,
    postFutureRuleOccurrence,
    type PostFutureRuleOccurrenceOverrides,
    skipFutureRuleOccurrence,
} from '@1wallet/ledger/rules/futureGeneration';
import type { FutureGenerationRule, LedgerState } from '@1wallet/ledger/store/types';

const ACTIONABLE_LOOKAHEAD_MONTHS = 24;
const ACTIONABLE_MAX_OCCURRENCES_PER_RULE = 60;
const PLAN_DETAIL_LOOKAHEAD_MONTHS = 1200;
const PLAN_DETAIL_MAX_OCCURRENCES_PER_RULE = 1200;
const ACTIONABLE_TRANSFER_TYPES = new Set(['transfer', 'card_payment', 'loan_repayment']);

export type NearestActionableOccurrenceOptions = {
  includePaused?: boolean;
  includePastUnfinished?: boolean;
  lookaheadMonths?: number;
  maxOccurrencesPerRule?: number;
};

export const PLAN_DETAIL_OCCURRENCE_LOOKUP_OPTIONS = {
  includePaused: true,
  includePastUnfinished: true,
  lookaheadMonths: PLAN_DETAIL_LOOKAHEAD_MONTHS,
  maxOccurrencesPerRule: PLAN_DETAIL_MAX_OCCURRENCES_PER_RULE,
} as const satisfies NearestActionableOccurrenceOptions;

export function transactionForRuleOccurrence(
  state: LedgerState,
  rule: FutureGenerationRule,
  dueOn: string,
): Transaction | undefined {
  const prefix = `future-rule-v1:${rule.id}:`;
  const externalRef = `${prefix}${dueOn}`;
  return state.transactions.find((transaction) => {
    if (transaction.externalRef === externalRef) return true;
    if (transaction.recurringTemplateId !== rule.id) return false;
    if (transaction.type !== rule.type) return false;
    return dateOnlyFromIso(transaction.occurredAt) === dueOn;
  });
}

export function confirmedTransactionsForRule(
  state: LedgerState,
  rule: FutureGenerationRule,
): Transaction[] {
  const prefix = `future-rule-v1:${rule.id}:`;
  return state.transactions
    .filter((transaction) => {
      const belongsToRule =
        transaction.recurringTemplateId === rule.id || transaction.externalRef?.startsWith(prefix);
      return (
        belongsToRule &&
        transaction.type === rule.type &&
        (transaction.status === 'cleared' || transaction.status === 'pending')
      );
    })
    .sort((left, right) => right.occurredAt.localeCompare(left.occurredAt));
}

export function nearestActionableOccurrence(
  state: LedgerState,
  rule: FutureGenerationRule,
  options: NearestActionableOccurrenceOptions = {},
): FutureRuleOccurrence | undefined {
  if (!options.includePaused && !rule.enabled) return undefined;
  if (!canBuildActionableOccurrence(state, rule)) return undefined;

  const now = new Date();
  const horizonEnd = addMonths(
    startOfLocalDay(now),
    options.lookaheadMonths ?? ACTIONABLE_LOOKAHEAD_MONTHS,
  );
  const maxOccurrences = options.maxOccurrencesPerRule ?? ACTIONABLE_MAX_OCCURRENCES_PER_RULE;
  for (const dueOn of futureRuleOccurrenceDates(rule, {
    now,
    horizonEnd,
    maxOccurrences,
  })) {
    const occurrence = occurrenceForDueOn(state, rule, dueOn);
    const existing = transactionForRuleOccurrence(state, rule, occurrence.dueOn);
    if (!existing) return occurrence;
    if (existing.status === 'scheduled') {
      return occurrenceFromScheduledTransaction(state, occurrence, existing);
    }
  }
  if (!options.includePastUnfinished) return undefined;

  const occurrenceStart = localDateFromDateOnly(rule.startsOn) ?? startOfLocalDay(now);
  const historicalMaxOccurrences = Math.max(maxOccurrences, rule.occurrences ?? 0);
  for (const dueOn of futureRuleOccurrenceDates(rule, {
    now: occurrenceStart,
    horizonEnd,
    maxOccurrences: historicalMaxOccurrences,
  })) {
    const occurrence = occurrenceForDueOn(state, rule, dueOn);
    const existing = transactionForRuleOccurrence(state, rule, occurrence.dueOn);
    if (!existing) return occurrence;
    if (existing.status === 'scheduled') {
      return occurrenceFromScheduledTransaction(state, occurrence, existing);
    }
  }
  return undefined;
}

function canBuildActionableOccurrence(state: LedgerState, rule: FutureGenerationRule): boolean {
  const account = state.accounts.find((item) => item.id === rule.accountId && !item.isArchived);
  if (!account) return false;
  if (normalizeCurrencyCode(account.currency) !== normalizeCurrencyCode(rule.currency)) {
    return false;
  }
  if (rule.amountMinor <= 0) return false;
  if (ACTIONABLE_TRANSFER_TYPES.has(rule.type)) {
    return Boolean(
      rule.counterAccountId &&
      state.accounts.some((item) => item.id === rule.counterAccountId && !item.isArchived),
    );
  }
  return true;
}

function occurrenceForDueOn(
  state: LedgerState,
  rule: FutureGenerationRule,
  dueOn: string,
): FutureRuleOccurrence {
  const loanAmounts = loanRuleOccurrenceAmounts(state, rule, dueOn);
  return {
    ruleId: rule.id,
    dueOn,
    occurredAt: withHour(dueOn, 8),
    externalRef: futureRuleExternalRef(rule.id, dueOn),
    type: rule.type,
    accountId: rule.accountId,
    counterAccountId: rule.counterAccountId,
    categoryId: rule.categoryId,
    amountMinor: loanAmounts?.amountMinor ?? rule.amountMinor,
    currency: loanAmounts?.currency ?? rule.currency,
    principalAmountMinor: loanAmounts?.principalAmountMinor,
    principalCurrency: loanAmounts?.principalCurrency,
    interestAmountMinor: loanAmounts?.interestAmountMinor,
    interestCurrency: loanAmounts?.interestCurrency,
    loanAccountId: loanAmounts?.loanAccountId,
    loanIsLent: loanAmounts?.loanIsLent,
    counterAmountMinor: loanAmounts?.counterAmountMinor,
    counterCurrency: loanAmounts?.counterCurrency,
    paymentMethod: rule.paymentMethod,
    notes: rule.notes,
    tags: rule.tags,
  };
}

export function confirmFutureRuleOccurrence(
  state: LedgerState,
  rule: FutureGenerationRule,
  occurrence: FutureRuleOccurrence,
  overrides: PostFutureRuleOccurrenceOverrides = {},
): Transaction {
  return postFutureRuleOccurrence(state, rule, occurrence, overrides);
}

export function postponeFutureRuleOccurrence(
  state: LedgerState,
  rule: FutureGenerationRule,
  occurrence: FutureRuleOccurrence,
  overrides: PostFutureRuleOccurrenceOverrides = {},
): Transaction {
  return postFutureRuleOccurrence(state, rule, occurrence, { ...overrides, status: 'scheduled' });
}

export function dismissFutureRuleOccurrence(
  state: LedgerState,
  rule: FutureGenerationRule,
  dueOn: string,
): void {
  skipFutureRuleOccurrence(state, rule.id, dueOn);
  const matching = transactionForRuleOccurrence(state, rule, dueOn);
  if (matching?.status === 'scheduled') {
    const interestRef = matching.externalRef
      ? futureRuleInterestExternalRef(matching.externalRef)
      : undefined;
    state.transactions = state.transactions.filter(
      (transaction) => transaction.id !== matching.id && transaction.externalRef !== interestRef,
    );
  }
}

export function restartFutureRulePlan(
  state: LedgerState,
  rule: FutureGenerationRule,
  startsOn = todayDateOnly(),
): FutureGenerationRule {
  const restarted = createFutureGenerationRule(state, {
    name: restartPlanName(rule.name),
    kind: rule.kind,
    postMode: rule.postMode,
    type: rule.type,
    accountId: rule.accountId,
    counterAccountId: rule.counterAccountId,
    categoryId: rule.categoryId,
    amountMinor: rule.amountMinor,
    currency: rule.currency,
    frequency: rule.frequency,
    interval: rule.interval,
    dayOfMonth: rule.dayOfMonth,
    daysOfWeek: rule.daysOfWeek,
    startsOn,
    endsOn: shiftedRestartEndDate(rule, startsOn),
    occurrences: rule.occurrences,
    skippedOccurrences: [],
    paymentMethod: rule.paymentMethod,
    notes: rule.notes,
    tags: rule.tags,
    enabled: true,
  });
  syncLoanDetailsFromRule(state, restarted);
  return restarted;
}

export function removeUnpostedFutureScheduledRecordsForRule(
  state: LedgerState,
  ruleId: string,
  now = new Date(),
): void {
  const today = startOfLocalDay(now);
  const prefix = `future-rule-v1:${ruleId}:`;
  state.transactions = state.transactions.filter((transaction) => {
    const belongsToRule =
      transaction.recurringTemplateId === ruleId || transaction.externalRef?.startsWith(prefix);
    if (!belongsToRule || transaction.status !== 'scheduled') return true;
    const occurredAt = new Date(transaction.occurredAt);
    return Number.isNaN(occurredAt.getTime()) || occurredAt < today;
  });
}

export function dateOnlyFromIso(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value.slice(0, 10);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function occurrenceFromScheduledTransaction(
  state: LedgerState,
  occurrence: FutureRuleOccurrence,
  transaction: Transaction,
): FutureRuleOccurrence {
  const interestTransaction = linkedScheduledInterestTransaction(state, transaction);
  const includeLegacyInterest = Boolean(
    interestTransaction &&
      occurrence.loanAccountId &&
      interestTransaction.accountId !== occurrence.loanAccountId,
  );
  const interestAmountMinor =
    interestTransaction?.amount.amountMinor ?? occurrence.interestAmountMinor;
  const principalAmountMinor =
    occurrence.type === 'loan_repayment' && occurrence.principalAmountMinor !== undefined
      ? occurrence.principalAmountMinor
      : (transaction.counterAmount?.amountMinor ?? occurrence.principalAmountMinor);
  return {
    ...occurrence,
    occurredAt: transaction.occurredAt,
    accountId: transaction.accountId,
    counterAccountId: transaction.counterAccountId,
    categoryId: transaction.categoryId,
    amountMinor:
      transaction.amount.amountMinor +
      (includeLegacyInterest ? (interestTransaction?.amount.amountMinor ?? 0) : 0),
    currency: transaction.amount.currency,
    principalAmountMinor,
    principalCurrency: transaction.counterAmount?.currency ?? occurrence.principalCurrency,
    interestAmountMinor,
    interestCurrency: interestTransaction?.amount.currency ?? occurrence.interestCurrency,
    counterAmountMinor: transaction.counterAmount?.amountMinor ?? occurrence.counterAmountMinor,
    counterCurrency: transaction.counterAmount?.currency ?? occurrence.counterCurrency,
    paymentMethod: transaction.paymentMethod ?? occurrence.paymentMethod,
    notes: transaction.notes ?? occurrence.notes,
    tags: transaction.tags ?? occurrence.tags,
  };
}

function linkedScheduledInterestTransaction(
  state: LedgerState,
  repayment: Transaction,
): Transaction | undefined {
  if (!repayment.externalRef) return undefined;
  const interestRef = futureRuleInterestExternalRef(repayment.externalRef);
  return state.transactions.find(
    (transaction) => transaction.status === 'scheduled' && transaction.externalRef === interestRef,
  );
}

function startOfLocalDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function addMonths(date: Date, months: number): Date {
  return new Date(date.getFullYear(), date.getMonth() + months, date.getDate());
}

function restartPlanName(name: string): string {
  return /\brestart\b/i.test(name) ? name : `${name} restart`;
}

function shiftedRestartEndDate(rule: FutureGenerationRule, startsOn: string): string | undefined {
  if (!rule.endsOn) return undefined;
  const previousStart = localDateFromDateOnly(rule.startsOn);
  const previousEnd = localDateFromDateOnly(rule.endsOn);
  const nextStart = localDateFromDateOnly(startsOn);
  if (!previousStart || !previousEnd || !nextStart || previousEnd < previousStart) return undefined;
  const daySpan = Math.round((previousEnd.getTime() - previousStart.getTime()) / 86_400_000);
  const nextEnd = new Date(nextStart);
  nextEnd.setDate(nextEnd.getDate() + daySpan);
  return dateOnlyFromLocalDate(nextEnd);
}

function todayDateOnly(): string {
  return dateOnlyFromLocalDate(new Date());
}

function dateOnlyFromLocalDate(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function withHour(dateIso: string, hour: number): string {
  const date = localDateFromDateOnly(dateIso) ?? new Date();
  date.setHours(hour, 0, 0, 0);
  return date.toISOString();
}

function localDateFromDateOnly(value: string): Date | undefined {
  const [year, month, day] = value.split('-').map((part) => Number(part));
  return year && month && day ? new Date(year, month - 1, day) : undefined;
}
