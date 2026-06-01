import { fromMinor, toMinor } from '@1wallet/domain/money';
import type { Account, TransactionType } from '@1wallet/domain/types';
import type { WalletCsvPlannedPaymentCandidate } from '@1wallet/ledger/import/walletCsv';
import type { CreateFutureGenerationRuleInput } from '@1wallet/ledger/rules/futureGeneration';
import {
    plannedPaymentKindForRule,
    plannedPaymentPostModeForRule,
} from '@1wallet/ledger/rules/futureGeneration';
import type {
    FutureGenerationFrequency,
    FutureGenerationRule,
    LedgerState,
    PlannedPaymentKind,
    PlannedPaymentPostMode,
} from '@1wallet/ledger/store/types';
import { accountTypeLabel, resolveAccountIconVisual } from '../accountOptions';
import type { OptionListItem } from '../components/OptionListOverlay';
import {
    categoryApplies,
    categoryKindForPlanKind,
    requiresCounterAccount,
    transactionTypeForPlannedKind,
} from './display';

export type PlanPickerMode =
  | 'kind'
  | 'account'
  | 'counterAccount'
  | 'category'
  | 'frequency'
  | 'endMode'
  | 'postMode'
  | null;
export type PlannedPaymentEndMode = 'forever' | 'three' | 'untilDate' | 'events';
export type PlannedPaymentDraft = {
  id?: string;
  name: string;
  kind: PlannedPaymentKind;
  transactionType?: TransactionType;
  accountId?: string;
  counterAccountId?: string;
  categoryId?: string;
  amountText: string;
  frequency: FutureGenerationFrequency;
  intervalText: string;
  dayOfMonthText: string;
  daysOfWeek: number[];
  startsOn: string;
  endMode: PlannedPaymentEndMode;
  endsOn: string;
  occurrencesText: string;
  paymentMethod: string;
  notes: string;
  postMode: PlannedPaymentPostMode;
  enabled: boolean;
};

export const PLANNED_KIND_OPTIONS: OptionListItem<PlannedPaymentKind>[] = [
  {
    value: 'income',
    label: 'Income',
    description: 'Salary, refunds, interest, cashback, and planned inflows',
    icon: 'arrow-down-circle-outline',
  },
  {
    value: 'expense',
    label: 'Expense',
    description: 'Bills, subscriptions, fees, and planned spending',
    icon: 'arrow-up-circle-outline',
  },
  {
    value: 'transfer',
    label: 'Transfer',
    description: 'Move money between accounts, cards, loans, or goals',
    icon: 'swap-horizontal',
  },
  {
    value: 'adjustment',
    label: 'Adjustment',
    description: 'Balance corrections and account adjustments',
    icon: 'tune-variant',
  },
];

export const FREQUENCY_OPTIONS: OptionListItem<FutureGenerationFrequency>[] = [
  {
    value: 'daily',
    label: 'Daily',
    description: 'Repeats every selected number of days',
    icon: 'calendar-today',
  },
  {
    value: 'weekly',
    label: 'Weekly',
    description: 'Repeats every selected number of weeks',
    icon: 'calendar-week',
  },
  {
    value: 'monthly',
    label: 'Monthly',
    description: 'Repeats on the selected day of month',
    icon: 'calendar-month-outline',
  },
  {
    value: 'yearly',
    label: 'Yearly',
    description: 'Repeats once every selected number of years',
    icon: 'calendar-star',
  },
];

export const POST_MODE_OPTIONS: OptionListItem<PlannedPaymentPostMode>[] = [
  {
    value: 'manual',
    label: 'Manual approval',
    description: 'Generate forecast occurrences, then confirm them yourself',
    icon: 'account-check-outline',
  },
  {
    value: 'automatic',
    label: 'Automatic posting',
    description: 'Due generated records can post automatically when the app runs',
    icon: 'calendar-check-outline',
  },
];

export const END_MODE_OPTIONS: OptionListItem<PlannedPaymentEndMode>[] = [
  {
    value: 'forever',
    label: 'Forever',
    description: 'Keep forecasting this plan with no end date',
    icon: 'infinity',
  },
  {
    value: 'three',
    label: 'Next 3 times',
    description: 'Forecast three occurrences, then stop',
    icon: 'numeric-3-circle-outline',
  },
  {
    value: 'untilDate',
    label: 'Until a date',
    description: 'Stop after the selected end date',
    icon: 'calendar-outline',
  },
  {
    value: 'events',
    label: 'Number of events',
    description: 'Stop after a custom number of occurrences',
    icon: 'counter',
  },
];

export function createDefaultPlanDraft(state: LedgerState): PlannedPaymentDraft {
  const account = activeAccounts(state)[0];
  const today = dateOnly(new Date());
  return {
    name: 'Monthly expense',
    kind: 'expense',
    accountId: account?.id,
    amountText: '',
    frequency: 'monthly',
    intervalText: '1',
    dayOfMonthText: String(new Date().getDate()),
    daysOfWeek: [dayOfWeekFromDate(today)],
    startsOn: today,
    endMode: 'forever',
    endsOn: '',
    occurrencesText: '',
    paymentMethod: '',
    notes: '',
    postMode: 'manual',
    enabled: true,
  };
}

export function draftFromRule(rule: FutureGenerationRule): PlannedPaymentDraft {
  const endMode = endModeFromRule(rule);
  return {
    id: rule.id,
    name: rule.name,
    kind: plannedPaymentKindForRule(rule),
    transactionType: rule.type,
    accountId: rule.accountId,
    counterAccountId: rule.counterAccountId,
    categoryId: rule.categoryId,
    amountText: String(rule.amountMinor / 100),
    frequency: rule.frequency,
    intervalText: String(rule.interval),
    dayOfMonthText: rule.dayOfMonth ? String(rule.dayOfMonth) : '',
    daysOfWeek: normalizeDraftDaysOfWeek(rule.daysOfWeek, rule.startsOn),
    startsOn: rule.startsOn,
    endMode,
    endsOn: rule.endsOn ?? '',
    occurrencesText: rule.occurrences ? String(rule.occurrences) : '',
    paymentMethod: rule.paymentMethod ?? '',
    notes: rule.notes ?? '',
    postMode: plannedPaymentPostModeForRule(rule),
    enabled: rule.enabled,
  };
}

export function draftFromWalletCsvPlannedPayment(
  state: LedgerState,
  candidate: WalletCsvPlannedPaymentCandidate,
  now = new Date(),
): PlannedPaymentDraft {
  const startsOn = nextCandidateStartDate(candidate, dateOnly(now));
  return {
    name: candidate.name,
    kind: candidate.kind,
    transactionType: candidate.type,
    accountId: candidate.accountId,
    counterAccountId: candidate.counterAccountId,
    categoryId: compatibleCategoryId(state, candidate.categoryId, candidate.kind),
    amountText: trimDraftAmount(fromMinor(candidate.latestAmountMinor, candidate.currency)),
    frequency: candidate.frequency,
    intervalText: String(candidate.interval),
    dayOfMonthText: candidate.dayOfMonth
      ? String(candidate.dayOfMonth)
      : dayOfMonthText(startsOn, ''),
    daysOfWeek: [dayOfWeekFromDate(startsOn)],
    startsOn,
    endMode: 'forever',
    endsOn: '',
    occurrencesText: '',
    paymentMethod: candidate.paymentMethod ?? '',
    notes: walletCsvPlannedPaymentNotes(candidate),
    postMode: 'manual',
    enabled: true,
  };
}

export function futureRuleInputFromDraft(
  state: LedgerState,
  draft: PlannedPaymentDraft,
): { ok: true; input: CreateFutureGenerationRuleInput } | { ok: false; message: string } {
  const validation = validatePlanDraft(state, draft);
  if (!validation.ok) return validation;

  const account = state.accounts.find((item) => item.id === draft.accountId && !item.isArchived);
  const amountMinor = account ? amountMinorFromText(draft.amountText, account.currency) : undefined;
  if (!account || !amountMinor) return { ok: false, message: 'Enter a positive amount' };

  return {
    ok: true,
    input: {
      name: draft.name.trim(),
      kind: draft.kind,
      postMode: draft.postMode,
      type: transactionTypeForPlannedKind(draft.kind, draft.transactionType),
      accountId: account.id,
      counterAccountId: requiresCounterAccount(draft.kind) ? draft.counterAccountId : undefined,
      categoryId: categoryApplies(draft.kind) ? draft.categoryId : undefined,
      amountMinor,
      currency: account.currency,
      frequency: draft.frequency,
      interval: integerFromText(draft.intervalText, 1),
      dayOfMonth:
        draft.frequency === 'monthly'
          ? integerFromText(draft.dayOfMonthText, dateDayFromValue(draft.startsOn) ?? 1)
          : undefined,
      daysOfWeek:
        draft.frequency === 'weekly'
          ? normalizeDraftDaysOfWeek(draft.daysOfWeek, draft.startsOn)
          : undefined,
      startsOn: draft.startsOn,
      endsOn: draft.endMode === 'untilDate' ? cleanDraftText(draft.endsOn) : undefined,
      occurrences:
        draft.endMode === 'three'
          ? 3
          : draft.endMode === 'events'
            ? integerFromText(draft.occurrencesText, undefined)
            : undefined,
      paymentMethod: cleanDraftText(draft.paymentMethod),
      notes: cleanDraftText(draft.notes),
      enabled: draft.enabled,
    },
  };
}

export function validatePlanDraft(
  state: LedgerState,
  draft: PlannedPaymentDraft,
): { ok: true } | { ok: false; message: string } {
  if (!draft.name.trim()) return { ok: false, message: 'Name the plan' };
  const account = state.accounts.find((item) => item.id === draft.accountId && !item.isArchived);
  if (!account) return { ok: false, message: 'Choose an account' };
  if (!amountMinorFromText(draft.amountText, account.currency)) {
    return { ok: false, message: 'Enter a positive amount' };
  }
  if (requiresCounterAccount(draft.kind)) {
    const counterAccount = state.accounts.find(
      (item) => item.id === draft.counterAccountId && !item.isArchived,
    );
    if (!draft.counterAccountId) return { ok: false, message: 'Choose the destination account' };
    if (draft.counterAccountId === draft.accountId) {
      return { ok: false, message: 'Destination must differ from the source account' };
    }
    if (!counterAccount) return { ok: false, message: 'Choose the destination account' };
  }
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(draft.startsOn) ||
    Number.isNaN(new Date(draft.startsOn).getTime())
  ) {
    return { ok: false, message: 'Enter a valid start date' };
  }
  const interval = integerFromText(draft.intervalText, 1);
  if (!interval || interval < 1)
    return { ok: false, message: 'Repeat interval must be at least 1' };
  const dayOfMonth = integerFromText(draft.dayOfMonthText, 1);
  if (draft.frequency === 'monthly' && (!dayOfMonth || dayOfMonth < 1 || dayOfMonth > 31)) {
    return { ok: false, message: 'Day of month must be between 1 and 31' };
  }
  if (draft.frequency === 'weekly' && normalizeDraftDaysOfWeek(draft.daysOfWeek).length === 0) {
    return { ok: false, message: 'Choose at least one weekday' };
  }
  if (
    draft.endMode === 'untilDate' &&
    (!draft.endsOn ||
      !/^\d{4}-\d{2}-\d{2}$/.test(draft.endsOn) ||
      Number.isNaN(new Date(draft.endsOn).getTime()))
  ) {
    return { ok: false, message: 'Enter a valid end date' };
  }
  if (
    draft.endMode === 'untilDate' &&
    new Date(draft.endsOn).getTime() < new Date(draft.startsOn).getTime()
  ) {
    return { ok: false, message: 'End date must be after the start date' };
  }
  if (
    draft.endMode !== 'untilDate' &&
    draft.endsOn &&
    (!/^\d{4}-\d{2}-\d{2}$/.test(draft.endsOn) || Number.isNaN(new Date(draft.endsOn).getTime()))
  ) {
    return { ok: false, message: 'Enter a valid end date or leave it blank' };
  }
  if (draft.endMode === 'events' && !integerFromText(draft.occurrencesText, undefined)) {
    return { ok: false, message: 'Enter the number of events' };
  }
  return { ok: true };
}

export function activeAccounts(state: LedgerState): Account[] {
  return state.accounts
    .filter((account) => !account.isArchived)
    .sort((left, right) => left.sortOrder - right.sortOrder || left.name.localeCompare(right.name));
}

export function accountOption(account: Account): OptionListItem<string> {
  const visual = resolveAccountIconVisual(account);
  return {
    value: account.id,
    label: account.name,
    description: `${accountTypeLabel(account.type)} · ${account.currency}`,
    icon: visual.icon,
    iconBackgroundColor: visual.backgroundColor,
    iconColor: visual.iconColor,
  };
}

export function endModeOptionFor(
  mode: PlannedPaymentEndMode,
): OptionListItem<PlannedPaymentEndMode> {
  return (
    END_MODE_OPTIONS.find((option) => option.value === mode) ?? {
      value: 'forever',
      label: 'Forever',
      icon: 'infinity',
    }
  );
}

export function endModeLabel(draft: PlannedPaymentDraft): string {
  if (draft.endMode === 'three') return 'Next 3 times';
  if (draft.endMode === 'untilDate') return draft.endsOn ? `Until ${draft.endsOn}` : 'Until a date';
  if (draft.endMode === 'events') {
    return draft.occurrencesText ? `${draft.occurrencesText} events` : 'Number of events';
  }
  return 'Forever';
}

export function endModePatch(
  draft: PlannedPaymentDraft,
  endMode: PlannedPaymentEndMode,
): Partial<PlannedPaymentDraft> {
  if (endMode === 'forever') return { endMode, endsOn: '', occurrencesText: '' };
  if (endMode === 'three') return { endMode, endsOn: '', occurrencesText: '3' };
  if (endMode === 'untilDate') return { endMode, occurrencesText: '' };
  return {
    endMode,
    endsOn: '',
    occurrencesText:
      draft.occurrencesText && draft.occurrencesText !== '3' ? draft.occurrencesText : '12',
  };
}

export function compatibleCategoryId(
  state: LedgerState,
  categoryId: string | undefined,
  kind: PlannedPaymentKind,
): string | undefined {
  if (!categoryApplies(kind)) return undefined;
  const category = state.categories.find((item) => item.id === categoryId && !item.isArchived);
  return category?.kind === categoryKindForPlanKind(kind) ? category.id : undefined;
}

export function amountMinorFromText(value: string, currency: string): number | undefined {
  const amount = Number(value.replace(/,/g, '').trim());
  if (!Number.isFinite(amount) || amount <= 0) return undefined;
  return toMinor(amount, currency);
}

export function integerFromText(value: string, fallback: number): number;
export function integerFromText(value: string, fallback: undefined): number | undefined;
export function integerFromText(value: string, fallback: number | undefined): number | undefined {
  const parsed = Number.parseInt(value.trim(), 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

export function cleanDraftText(value: string): string | undefined {
  const cleaned = value.trim();
  return cleaned.length > 0 ? cleaned : undefined;
}

export function dayOfMonthText(value: string, fallback: string): string {
  const day = dateDayFromValue(value);
  return day ? String(day) : fallback;
}

export function normalizeDraftDaysOfWeek(values?: number[], startsOn?: string): number[] {
  const normalized = Array.from(
    new Set(
      (values ?? []).map((value) => Math.floor(value)).filter((value) => value >= 0 && value <= 6),
    ),
  ).sort((left, right) => weekdaySortIndex(left) - weekdaySortIndex(right));
  return normalized.length > 0 ? normalized : startsOn ? [dayOfWeekFromDate(startsOn)] : [];
}

export function dayOfWeekFromDate(value: string): number {
  return parseDateOnly(value)?.getDay() ?? new Date().getDay();
}

function dateDayFromValue(value: string): number | undefined {
  return parseDateOnly(value)?.getDate();
}

function weekdaySortIndex(day: number): number {
  return (day + 6) % 7;
}

function parseDateOnly(value: string): Date | undefined {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return undefined;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (!year || !month || !day) return undefined;
  const date = new Date(year, month - 1, day);
  return Number.isNaN(date.getTime()) ? undefined : date;
}

export function dateOnly(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function nextCandidateStartDate(
  candidate: WalletCsvPlannedPaymentCandidate,
  today: string,
): string {
  let cursor = candidate.nextDueOn || today;
  let guard = 0;
  while (cursor < today && guard < 48) {
    cursor = advanceCandidateDate(cursor, candidate);
    guard += 1;
  }
  return cursor;
}

function advanceCandidateDate(
  dateValue: string,
  candidate: WalletCsvPlannedPaymentCandidate,
): string {
  const date = new Date(`${dateValue}T00:00:00.000Z`);
  if (Number.isNaN(date.getTime())) return dateOnly(new Date());
  if (candidate.frequency === 'weekly') date.setUTCDate(date.getUTCDate() + 7 * candidate.interval);
  else if (candidate.frequency === 'monthly') {
    const targetMonth = date.getUTCMonth() + candidate.interval;
    const targetYear = date.getUTCFullYear() + Math.floor(targetMonth / 12);
    const normalizedMonth = ((targetMonth % 12) + 12) % 12;
    const day = candidate.dayOfMonth ?? date.getUTCDate();
    const maxDay = new Date(Date.UTC(targetYear, normalizedMonth + 1, 0)).getUTCDate();
    date.setUTCFullYear(targetYear, normalizedMonth, Math.min(day, maxDay));
  } else if (candidate.frequency === 'yearly') {
    date.setUTCFullYear(date.getUTCFullYear() + candidate.interval);
  } else {
    date.setUTCDate(date.getUTCDate() + candidate.interval);
  }
  return date.toISOString().slice(0, 10);
}

function walletCsvPlannedPaymentNotes(candidate: WalletCsvPlannedPaymentCandidate): string {
  const amountRange =
    candidate.amountMinMinor !== candidate.amountMaxMinor
      ? `Amount varied from ${trimDraftAmount(fromMinor(candidate.amountMinMinor, candidate.currency))} to ${trimDraftAmount(fromMinor(candidate.amountMaxMinor, candidate.currency))} ${candidate.currency}.`
      : undefined;
  return [
    'Created from Wallet CSV planned-payment review.',
    `Evidence: ${candidate.occurrences} rows from ${candidate.startsOn} to ${candidate.lastSeenOn}.`,
    `Activity: ${candidate.activityReason}.`,
    amountRange,
  ]
    .filter(Boolean)
    .join('\n');
}

function trimDraftAmount(value: number): string {
  if (!Number.isFinite(value)) return '';
  return String(Math.round(value * 100) / 100);
}

function endModeFromRule(rule: FutureGenerationRule): PlannedPaymentEndMode {
  if (rule.endsOn) return 'untilDate';
  if (rule.occurrences === 3) return 'three';
  if (rule.occurrences) return 'events';
  return 'forever';
}
