import { normalizeCurrencyCode } from '@1wallet/domain/money';
import type { Transaction, TransactionStatus, TransactionType, UUID } from '@1wallet/domain/types';
import { nowIso, uid } from '../id';
import { loanRuleOccurrenceAmounts } from '../loans';
import { createTransaction, updateTransaction } from '../services/index';
import type {
    FutureGenerationFrequency,
    FutureGenerationRule,
    LedgerState,
    PlannedPaymentKind,
    PlannedPaymentPostMode,
} from '../store/types';

export const FUTURE_RULE_REF_PREFIX = 'future-rule-v1';
export const RECURRING_SCHEDULE_REF_PREFIX = 'recurring-schedule-v1';

export type CreateFutureGenerationRuleInput = {
  name: string;
  kind?: PlannedPaymentKind;
  postMode?: PlannedPaymentPostMode;
  type: TransactionType;
  accountId: UUID;
  counterAccountId?: UUID;
  categoryId?: UUID;
  amountMinor: number;
  currency?: string;
  frequency?: FutureGenerationFrequency;
  interval?: number;
  dayOfMonth?: number;
  daysOfWeek?: number[];
  startsOn?: string;
  endsOn?: string;
  occurrences?: number;
  skippedOccurrences?: string[];
  paymentMethod?: string;
  notes?: string;
  tags?: string[];
  enabled?: boolean;
};

export type UpdateFutureGenerationRuleInput = Partial<
  Omit<CreateFutureGenerationRuleInput, 'currency'>
> & {
  currency?: string;
};

export type GenerateFutureTransactionsOptions = {
  horizonMonths?: number;
  maxOccurrencesPerRule?: number;
  ruleIds?: string[];
  now?: Date;
};

export type GenerateFutureTransactionsSummary = {
  rules: number;
  generated: number;
  skipped: number;
  invalid: number;
};

export type PlannedPaymentRuleStats = {
  scheduled: number;
  posted: number;
  voided: number;
  nextDueAt?: string;
  lastPostedAt?: string;
};

export type FutureRuleOccurrence = {
  ruleId: UUID;
  dueOn: string;
  occurredAt: string;
  externalRef: string;
  type: TransactionType;
  accountId: UUID;
  counterAccountId?: UUID;
  categoryId?: UUID;
  amountMinor: number;
  currency: string;
  principalAmountMinor?: number;
  principalCurrency?: string;
  interestAmountMinor?: number;
  interestCurrency?: string;
  loanAccountId?: UUID;
  loanIsLent?: boolean;
  counterAmountMinor?: number;
  counterCurrency?: string;
  paymentMethod?: string;
  notes?: string;
  tags?: string[];
};

export type PostFutureRuleOccurrenceOverrides = {
  status?: TransactionStatus;
  accountId?: UUID;
  counterAccountId?: UUID;
  categoryId?: UUID | null;
  amountMinor?: number;
  currency?: string;
  occurredAt?: string;
  paymentMethod?: string | null;
  notes?: string | null;
  tags?: string[] | null;
};

export type FutureRuleOccurrenceDateOptions = {
  now?: Date;
  horizonEnd?: Date;
  maxOccurrences?: number;
  includeSkipped?: boolean;
};

export type ForecastFutureRuleOccurrencesOptions = {
  from?: Date;
  to?: Date;
  now?: Date;
  maxOccurrencesPerRule?: number;
  ruleIds?: string[];
};

const DEFAULT_HORIZON_MONTHS = 3;
const DEFAULT_MAX_OCCURRENCES_PER_RULE = 24;
const TRANSFER_TYPES = new Set<TransactionType>(['transfer', 'card_payment', 'loan_repayment']);

export function futureGenerationRules(state: LedgerState): FutureGenerationRule[] {
  return state.preferences.futureGenerationRules ?? [];
}

export function createFutureGenerationRule(
  state: LedgerState,
  input: CreateFutureGenerationRuleInput,
): FutureGenerationRule {
  const now = nowIso();
  const account = state.accounts.find((item) => item.id === input.accountId);
  if (!account) throw new Error('createFutureGenerationRule: account not found');
  if (input.amountMinor <= 0)
    throw new Error('createFutureGenerationRule: amount must be positive');
  if (TRANSFER_TYPES.has(input.type) && !input.counterAccountId) {
    throw new Error('createFutureGenerationRule: counter account required for transfers');
  }

  const rule: FutureGenerationRule = {
    id: uid(),
    name: input.name.trim() || 'Future rule',
    enabled: input.enabled ?? true,
    kind: normalizePlannedPaymentKind(input.kind, input.type),
    postMode: input.postMode ?? 'manual',
    type: input.type,
    accountId: input.accountId,
    counterAccountId: input.counterAccountId,
    categoryId: input.categoryId,
    amountMinor: input.amountMinor,
    currency: normalizeCurrencyCode(input.currency ?? account.currency),
    frequency: input.frequency ?? 'monthly',
    interval: normalizeInterval(input.interval),
    dayOfMonth: normalizeDayOfMonth(input.dayOfMonth),
    daysOfWeek: normalizeDaysOfWeek(input.daysOfWeek),
    startsOn: input.startsOn ?? todayIso(),
    endsOn: input.endsOn,
    occurrences: normalizeOccurrences(input.occurrences),
    skippedOccurrences: normalizeSkippedOccurrences(input.skippedOccurrences),
    paymentMethod: cleanOptional(input.paymentMethod),
    notes: cleanOptional(input.notes),
    tags: input.tags?.filter(Boolean),
    createdAt: now,
    updatedAt: now,
  };

  ensureRuleStore(state).push(rule);
  return rule;
}

export function updateFutureGenerationRule(
  state: LedgerState,
  id: UUID,
  patch: UpdateFutureGenerationRuleInput,
): FutureGenerationRule | undefined {
  const rule = ensureRuleStore(state).find((item) => item.id === id);
  if (!rule) return undefined;
  const hasPatch = (key: keyof UpdateFutureGenerationRuleInput) =>
    Object.prototype.hasOwnProperty.call(patch, key);
  if (patch.name !== undefined) rule.name = patch.name.trim() || rule.name;
  if (patch.enabled !== undefined) rule.enabled = patch.enabled;
  if (patch.kind !== undefined) {
    rule.kind = normalizePlannedPaymentKind(patch.kind, patch.type ?? rule.type);
  }
  if (patch.postMode !== undefined) rule.postMode = patch.postMode;
  if (patch.type !== undefined) rule.type = patch.type;
  if (patch.accountId !== undefined) rule.accountId = patch.accountId;
  if (hasPatch('counterAccountId')) rule.counterAccountId = patch.counterAccountId;
  if (hasPatch('categoryId')) rule.categoryId = patch.categoryId;
  if (patch.amountMinor !== undefined && patch.amountMinor > 0)
    rule.amountMinor = patch.amountMinor;
  if (patch.currency !== undefined) rule.currency = normalizeCurrencyCode(patch.currency);
  if (patch.frequency !== undefined) rule.frequency = patch.frequency;
  if (patch.interval !== undefined) rule.interval = normalizeInterval(patch.interval);
  if (hasPatch('dayOfMonth')) rule.dayOfMonth = normalizeDayOfMonth(patch.dayOfMonth);
  if (hasPatch('daysOfWeek')) rule.daysOfWeek = normalizeDaysOfWeek(patch.daysOfWeek);
  if (patch.startsOn !== undefined) rule.startsOn = patch.startsOn;
  if (hasPatch('endsOn')) rule.endsOn = patch.endsOn;
  if (hasPatch('occurrences')) rule.occurrences = normalizeOccurrences(patch.occurrences);
  if (hasPatch('skippedOccurrences')) {
    rule.skippedOccurrences = normalizeSkippedOccurrences(patch.skippedOccurrences);
  }
  if (hasPatch('paymentMethod')) rule.paymentMethod = cleanOptional(patch.paymentMethod);
  if (hasPatch('notes')) rule.notes = cleanOptional(patch.notes);
  if (patch.tags !== undefined) rule.tags = patch.tags.filter(Boolean);
  rule.updatedAt = nowIso();
  return rule;
}

export function deleteFutureGenerationRule(state: LedgerState, id: UUID): boolean {
  const rules = ensureRuleStore(state);
  const before = rules.length;
  state.preferences.futureGenerationRules = rules.filter((rule) => rule.id !== id);
  return state.preferences.futureGenerationRules.length < before;
}

export function generateFutureTransactionsFromRules(
  state: LedgerState,
  options: GenerateFutureTransactionsOptions = {},
): GenerateFutureTransactionsSummary {
  const ruleIdFilter = options.ruleIds ? new Set(options.ruleIds) : undefined;
  const now = options.now ?? new Date();
  const horizonEnd = addMonths(startOfDay(now), options.horizonMonths ?? DEFAULT_HORIZON_MONTHS);
  const maxOccurrences = options.maxOccurrencesPerRule ?? DEFAULT_MAX_OCCURRENCES_PER_RULE;
  const summary: GenerateFutureTransactionsSummary = {
    rules: 0,
    generated: 0,
    skipped: 0,
    invalid: 0,
  };

  for (const rule of futureGenerationRules(state)) {
    if (!rule.enabled) continue;
    if (ruleIdFilter && !ruleIdFilter.has(rule.id)) continue;
    summary.rules += 1;
    if (!canGenerateRule(state, rule)) {
      summary.invalid += 1;
      continue;
    }

    for (const dueOn of futureRuleOccurrenceDates(rule, { now, horizonEnd, maxOccurrences })) {
      const externalRef = futureRuleExternalRef(rule.id, dueOn);
      if (state.transactions.some((transaction) => transaction.externalRef === externalRef)) {
        summary.skipped += 1;
        continue;
      }
      const loanAmounts = loanRuleOccurrenceAmounts(state, rule, dueOn);
      createTransaction(state, {
        type: rule.type,
        status: 'scheduled',
        source: 'rule',
        accountId: rule.accountId,
        counterAccountId: rule.counterAccountId,
        amountMinor: loanAmounts?.amountMinor ?? rule.amountMinor,
        currency: loanAmounts?.currency ?? rule.currency,
        counterAmountMinor: loanAmounts?.counterAmountMinor,
        counterCurrency: loanAmounts?.counterCurrency,
        categoryId: rule.categoryId,
        occurredAt: withHour(dueOn, 8),
        paymentMethod: rule.paymentMethod,
        notes: rule.notes ?? `${rule.name} generated by rule`,
        tags: rule.tags,
        recurringTemplateId: rule.id,
        externalRef,
      });
      summary.generated += 1;
    }
  }

  return summary;
}

export function generateFutureTransactionsFromRecurringSchedules(
  state: LedgerState,
  options: GenerateFutureTransactionsOptions = {},
): GenerateFutureTransactionsSummary {
  const now = options.now ?? new Date();
  const horizonEnd = addMonths(startOfDay(now), options.horizonMonths ?? DEFAULT_HORIZON_MONTHS);
  const maxOccurrences = options.maxOccurrencesPerRule ?? DEFAULT_MAX_OCCURRENCES_PER_RULE;
  const summary: GenerateFutureTransactionsSummary = {
    rules: 0,
    generated: 0,
    skipped: 0,
    invalid: 0,
  };

  for (const template of recurringScheduleTemplates(state)) {
    summary.rules += 1;
    if (!canGenerateFromRecurringTemplate(state, template)) {
      summary.invalid += 1;
      continue;
    }

    const signature = recurringTemplateSignature(template);
    const seriesId = recurringTemplateSeriesId(template, signature);
    const templateStart = startOfDay(new Date(template.occurredAt));
    const templateDayOfMonth = templateStart.getDate();
    const today = startOfDay(now);
    for (let index = 1; index <= maxOccurrences; index += 1) {
      const cursor = addMonths(templateStart, index, templateDayOfMonth);
      if (cursor > horizonEnd) break;
      if (cursor >= today) {
        const dueOn = toDateOnly(cursor);
        const externalRef = recurringScheduleExternalRef(seriesId, dueOn);
        if (hasRecurringScheduleOccurrence(state, signature, dueOn, externalRef)) {
          summary.skipped += 1;
        } else {
          createRecurringScheduledTransaction(state, template, externalRef, dueOn);
          summary.generated += 1;
        }
      }
    }
  }

  return summary;
}

export function futureRuleExternalRef(ruleId: UUID, dueOn: string): string {
  return `${FUTURE_RULE_REF_PREFIX}:${ruleId}:${dueOn}`;
}

export function futureRuleInterestExternalRef(externalRef: string): string {
  return `${externalRef}:interest`;
}

export function futureRuleOccurrenceDates(
  rule: FutureGenerationRule,
  options: FutureRuleOccurrenceDateOptions = {},
): string[] {
  const now = options.now ?? new Date();
  const horizonEnd = options.horizonEnd ?? addMonths(startOfDay(now), DEFAULT_HORIZON_MONTHS);
  const maxOccurrences = options.maxOccurrences ?? DEFAULT_MAX_OCCURRENCES_PER_RULE;
  const dates = occurrenceDates(rule, now, horizonEnd, maxOccurrences);
  if (options.includeSkipped) return dates;
  const skipped = new Set(rule.skippedOccurrences ?? []);
  return dates.filter((date) => !skipped.has(date));
}

export function forecastFutureRuleOccurrences(
  state: LedgerState,
  options: ForecastFutureRuleOccurrencesOptions = {},
): FutureRuleOccurrence[] {
  const from = startOfDay(options.from ?? options.now ?? new Date());
  const to = options.to ?? addMonths(from, DEFAULT_HORIZON_MONTHS);
  const ruleIdFilter = options.ruleIds ? new Set(options.ruleIds) : undefined;
  const occurrences: FutureRuleOccurrence[] = [];

  for (const rule of futureGenerationRules(state)) {
    if (!rule.enabled) continue;
    if (ruleIdFilter && !ruleIdFilter.has(rule.id)) continue;
    if (!canGenerateRule(state, rule)) continue;

    for (const dueOn of futureRuleOccurrenceDates(rule, {
      now: options.now,
      horizonEnd: to,
      maxOccurrences: options.maxOccurrencesPerRule ?? DEFAULT_MAX_OCCURRENCES_PER_RULE,
    })) {
      const dueDate = parseLocalDate(dueOn);
      if (!dueDate || dueDate < from || dueDate >= to) continue;
      occurrences.push(
        futureRuleOccurrence(rule, dueOn, loanRuleOccurrenceAmounts(state, rule, dueOn)),
      );
    }
  }

  return occurrences.sort((left, right) => left.occurredAt.localeCompare(right.occurredAt));
}

export function nextFutureRuleOccurrence(
  state: LedgerState,
  rule: FutureGenerationRule,
  now = new Date(),
): FutureRuleOccurrence | undefined {
  if (!rule.enabled || !canGenerateRule(state, rule)) return undefined;
  const dueOn = futureRuleOccurrenceDates(rule, {
    now,
    horizonEnd: addMonths(startOfDay(now), 24),
    maxOccurrences: DEFAULT_MAX_OCCURRENCES_PER_RULE,
  })[0];
  return dueOn
    ? futureRuleOccurrence(rule, dueOn, loanRuleOccurrenceAmounts(state, rule, dueOn))
    : undefined;
}

export function skipFutureRuleOccurrence(
  state: LedgerState,
  ruleId: UUID,
  dueOn: string,
): FutureGenerationRule | undefined {
  const rule = ensureRuleStore(state).find((item) => item.id === ruleId);
  if (!rule) return undefined;
  const skipped = new Set(rule.skippedOccurrences ?? []);
  skipped.add(dueOn);
  rule.skippedOccurrences = Array.from(skipped).sort();
  rule.updatedAt = nowIso();
  return rule;
}

export function recurringScheduleExternalRef(seriesId: string, dueOn: string): string {
  return `${RECURRING_SCHEDULE_REF_PREFIX}:${seriesId}:${dueOn}`;
}

export function recurringScheduleTemplates(state: LedgerState): Transaction[] {
  const templatesBySignature = new Map<string, Transaction>();

  for (const transaction of state.transactions) {
    if (!isRecurringScheduleTemplate(transaction)) continue;
    const signature = recurringTemplateSignature(transaction);
    const current = templatesBySignature.get(signature);
    if (!current || current.occurredAt < transaction.occurredAt) {
      templatesBySignature.set(signature, transaction);
    }
  }

  return Array.from(templatesBySignature.values()).sort((left, right) =>
    left.occurredAt.localeCompare(right.occurredAt),
  );
}

export function isRecurringScheduleTemplate(transaction: Transaction): boolean {
  return (
    transaction.source === 'recurring' &&
    transaction.status !== 'void' &&
    !transaction.externalRef?.startsWith(`${RECURRING_SCHEDULE_REF_PREFIX}:`)
  );
}

export function nextFutureRuleDueOn(
  rule: FutureGenerationRule,
  now = new Date(),
): string | undefined {
  return futureRuleOccurrenceDates(rule, {
    now,
    horizonEnd: addMonths(startOfDay(now), 24),
    maxOccurrences: DEFAULT_MAX_OCCURRENCES_PER_RULE,
  })[0];
}

export function plannedPaymentKindForRule(rule: FutureGenerationRule): PlannedPaymentKind {
  return normalizePlannedPaymentKind(rule.kind, rule.type);
}

export function plannedPaymentPostModeForRule(rule: FutureGenerationRule): PlannedPaymentPostMode {
  return rule.postMode ?? 'manual';
}

export function plannedPaymentKindForTransactionType(type: TransactionType): PlannedPaymentKind {
  if (type === 'income' || type === 'refund' || type === 'interest_in' || type === 'cashback') {
    return 'income';
  }
  if (type === 'transfer' || type === 'card_payment' || type === 'loan_repayment') {
    return 'transfer';
  }
  if (type === 'adjustment') return 'adjustment';
  if (type === 'investment_buy' || type === 'investment_sell') return 'transfer';
  if (type === 'expense' || type === 'fee' || type === 'interest_out') return 'expense';
  return 'expense';
}

export function normalizePlannedPaymentKind(
  kind: unknown,
  fallbackType?: TransactionType,
): PlannedPaymentKind {
  if (kind === 'income' || kind === 'expense' || kind === 'transfer' || kind === 'adjustment') {
    return kind;
  }
  if (
    kind === 'card_payment' ||
    kind === 'loan_emi' ||
    kind === 'savings_transfer' ||
    fallbackType === 'transfer' ||
    fallbackType === 'card_payment' ||
    fallbackType === 'loan_repayment' ||
    fallbackType === 'investment_buy' ||
    fallbackType === 'investment_sell'
  ) {
    return 'transfer';
  }
  if (fallbackType) return plannedPaymentKindForTransactionType(fallbackType);
  return 'expense';
}

export function plannedPaymentRuleStats(
  state: LedgerState,
  rule: FutureGenerationRule,
  now = new Date(),
): PlannedPaymentRuleStats {
  const generated = generatedTransactionsForFutureRule(state, rule);
  const posted = generated
    .filter((transaction) => transaction.status === 'cleared' || transaction.status === 'pending')
    .sort((left, right) => left.occurredAt.localeCompare(right.occurredAt));
  const voided = generated.filter((transaction) => transaction.status === 'void');
  const blockedDueDates = new Set(
    [...posted, ...voided].map((transaction) => dueOnForFutureRuleTransaction(rule, transaction)),
  );
  const forecastDueOns = canGenerateRule(state, rule)
    ? futureRuleOccurrenceDates(rule, {
        now,
        horizonEnd: addMonths(startOfDay(now), 24),
        maxOccurrences: DEFAULT_MAX_OCCURRENCES_PER_RULE,
      }).filter((dueOn) => !blockedDueDates.has(dueOn))
    : [];
  const nextForecastDueOn = forecastDueOns[0];
  const lastPosted = posted[posted.length - 1];
  return {
    scheduled: forecastDueOns.length,
    posted: posted.length,
    voided: voided.length,
    nextDueAt: nextForecastDueOn ? withHour(nextForecastDueOn, 8) : undefined,
    lastPostedAt: lastPosted?.occurredAt,
  };
}

export function postDueFutureRuleTransactions(
  state: LedgerState,
  options: { ruleIds?: string[]; automaticOnly?: boolean; now?: Date } = {},
): number {
  const ruleIdFilter = options.ruleIds ? new Set(options.ruleIds) : undefined;
  const now = options.now ?? new Date();
  const endOfToday = startOfDay(now);
  endOfToday.setDate(endOfToday.getDate() + 1);
  let posted = 0;

  for (const rule of futureGenerationRules(state)) {
    if (!rule.enabled) continue;
    if (ruleIdFilter && !ruleIdFilter.has(rule.id)) continue;
    if (options.automaticOnly && plannedPaymentPostModeForRule(rule) !== 'automatic') continue;
    if (!canGenerateRule(state, rule)) continue;

    const occurrenceStart = parseLocalDate(rule.startsOn) ?? startOfDay(now);
    const dueOns = futureRuleOccurrenceDates(rule, {
      now: occurrenceStart,
      horizonEnd: endOfToday,
      maxOccurrences: 1200,
    });

    for (const dueOn of dueOns) {
      const dueDate = parseLocalDate(dueOn);
      if (!dueDate || dueDate >= endOfToday) continue;
      const occurrence = futureRuleOccurrence(
        rule,
        dueOn,
        loanRuleOccurrenceAmounts(state, rule, dueOn),
      );
      const existing = transactionForFutureRuleOccurrence(state, rule, dueOn);

      if (existing && existing.status !== 'scheduled') continue;
      if (existing?.status === 'scheduled') {
        const scheduledDate = parseLocalDate(toDateOnly(new Date(existing.occurredAt)));
        if (scheduledDate && scheduledDate >= endOfToday) continue;
      }
      postFutureRuleOccurrence(state, rule, occurrence, {
        ...(existing?.status === 'scheduled'
          ? overridesFromScheduledTransaction(state, existing)
          : {}),
        notes: rule.notes ?? `${rule.name} posted from plan`,
      });
      posted += 1;
    }
  }

  return posted;
}

export function postFutureRuleOccurrence(
  state: LedgerState,
  rule: FutureGenerationRule,
  occurrence: FutureRuleOccurrence,
  overrides: PostFutureRuleOccurrenceOverrides = {},
): Transaction {
  const accountId = overrides.accountId ?? occurrence.accountId;
  const counterAccountId = overrides.counterAccountId ?? occurrence.counterAccountId;
  const amountMinor = Math.max(0, Math.round(overrides.amountMinor ?? occurrence.amountMinor));
  const currency = normalizeCurrencyCode(overrides.currency ?? occurrence.currency);
  const occurredAt = overrides.occurredAt ?? occurrence.occurredAt;
  const status = overrides.status ?? 'cleared';
  const paymentMethod = overrides.paymentMethod ?? occurrence.paymentMethod;
  const notes = overrides.notes ?? occurrence.notes ?? `${rule.name} confirmed from plan`;
  const tags = overrides.tags ?? occurrence.tags;
  const categoryId =
    overrides.categoryId === undefined ? occurrence.categoryId : overrides.categoryId;

  if (amountMinor <= 0) {
    throw new Error('postFutureRuleOccurrence: amount must be positive');
  }

  if (
    occurrence.type === 'loan_repayment' &&
    counterAccountId &&
    occurrence.principalAmountMinor !== undefined
  ) {
    return postLoanRuleOccurrence(state, rule, occurrence, {
      accountId,
      counterAccountId,
      amountMinor,
      currency,
      occurredAt,
      status,
      paymentMethod,
      notes,
      tags,
    });
  }

  return upsertFutureRuleTransaction(state, rule, occurrence, {
    type: occurrence.type,
    status,
    source: 'rule',
    accountId,
    counterAccountId,
    amountMinor,
    currency,
    counterAmountMinor: occurrence.counterAmountMinor,
    counterCurrency: occurrence.counterCurrency,
    categoryId: categoryId ?? undefined,
    occurredAt,
    paymentMethod: paymentMethod ?? undefined,
    notes: notes ?? undefined,
    tags: tags ?? undefined,
    recurringTemplateId: rule.id,
    externalRef: occurrence.externalRef,
  });
}

export function removeGeneratedScheduledTransactions(state: LedgerState): number {
  const before = state.transactions.length;
  state.transactions = state.transactions.filter((transaction) => {
    if (transaction.status !== 'scheduled') return true;
    if (transaction.source === 'rule') return false;
    if (transaction.externalRef?.startsWith(`${FUTURE_RULE_REF_PREFIX}:`)) return false;
    if (transaction.externalRef?.startsWith(`${RECURRING_SCHEDULE_REF_PREFIX}:`)) return false;
    return true;
  });
  return before - state.transactions.length;
}

function dueOnForFutureRuleTransaction(
  rule: FutureGenerationRule,
  transaction: Transaction,
): string {
  const refPrefix = `${FUTURE_RULE_REF_PREFIX}:${rule.id}:`;
  if (transaction.externalRef?.startsWith(refPrefix)) {
    return (
      transaction.externalRef.slice(refPrefix.length).split(':')[0] ??
      toDateOnly(new Date(transaction.occurredAt))
    );
  }
  return toDateOnly(new Date(transaction.occurredAt));
}

function overridesFromScheduledTransaction(
  state: LedgerState,
  transaction: Transaction,
): PostFutureRuleOccurrenceOverrides {
  const interestTransaction = scheduledLoanInterestTransaction(state, transaction);
  const loanAccountId = loanAccountIdForTransaction(state, transaction);
  const includeLegacyInterest = Boolean(
    interestTransaction && loanAccountId && interestTransaction.accountId !== loanAccountId,
  );
  return {
    accountId: transaction.accountId,
    counterAccountId: transaction.counterAccountId,
    amountMinor:
      transaction.amount.amountMinor +
      (includeLegacyInterest ? (interestTransaction?.amount.amountMinor ?? 0) : 0),
    currency: transaction.amount.currency,
    occurredAt: transaction.occurredAt,
    paymentMethod: transaction.paymentMethod ?? null,
    notes: transaction.notes ?? null,
    tags: transaction.tags ?? null,
  };
}

function scheduledLoanInterestTransaction(
  state: LedgerState,
  repayment: Transaction,
): Transaction | undefined {
  if (!repayment.externalRef) return undefined;
  const interestRef = futureRuleInterestExternalRef(repayment.externalRef);
  return state.transactions.find(
    (transaction) => transaction.status === 'scheduled' && transaction.externalRef === interestRef,
  );
}

function loanAccountIdForTransaction(
  state: LedgerState,
  transaction: Transaction,
): UUID | undefined {
  const account = state.accounts.find((item) => item.id === transaction.accountId);
  if (account && isLoanAccountTypeForRule(account.type)) return account.id;
  const counterAccount = transaction.counterAccountId
    ? state.accounts.find((item) => item.id === transaction.counterAccountId)
    : undefined;
  return counterAccount && isLoanAccountTypeForRule(counterAccount.type)
    ? counterAccount.id
    : undefined;
}

function isLoanAccountTypeForRule(type: string): boolean {
  return type === 'loan' || type === 'overdraft' || type === 'lent';
}

function ensureRuleStore(state: LedgerState): FutureGenerationRule[] {
  if (!state.preferences.futureGenerationRules) state.preferences.futureGenerationRules = [];
  return state.preferences.futureGenerationRules;
}

function generatedTransactionsForFutureRule(
  state: LedgerState,
  rule: FutureGenerationRule,
): Transaction[] {
  const prefix = `${FUTURE_RULE_REF_PREFIX}:${rule.id}:`;
  return state.transactions.filter(
    (transaction) =>
      transaction.type === rule.type &&
      (transaction.recurringTemplateId === rule.id || transaction.externalRef?.startsWith(prefix)),
  );
}

function transactionForFutureRuleOccurrence(
  state: LedgerState,
  rule: FutureGenerationRule,
  dueOn: string,
): Transaction | undefined {
  const externalRef = futureRuleExternalRef(rule.id, dueOn);
  return state.transactions.find((transaction) => {
    if (transaction.externalRef === externalRef) return true;
    if (transaction.recurringTemplateId !== rule.id) return false;
    if (transaction.type !== rule.type) return false;
    return toDateOnly(new Date(transaction.occurredAt)) === dueOn;
  });
}

function futureRuleOccurrence(
  rule: FutureGenerationRule,
  dueOn: string,
  loanAmounts?: ReturnType<typeof loanRuleOccurrenceAmounts>,
): FutureRuleOccurrence {
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

function postLoanRuleOccurrence(
  state: LedgerState,
  rule: FutureGenerationRule,
  occurrence: FutureRuleOccurrence,
  input: {
    accountId: UUID;
    counterAccountId: UUID;
    amountMinor: number;
    currency: string;
    occurredAt: string;
    status: TransactionStatus;
    paymentMethod?: string | null;
    notes?: string | null;
    tags?: string[] | null;
  },
): Transaction {
  const forecastPrincipalMinor = Math.max(0, Math.round(occurrence.principalAmountMinor ?? 0));
  const forecastInterestMinor = Math.max(
    0,
    Math.round(
      occurrence.interestAmountMinor ??
        occurrence.amountMinor - (forecastPrincipalMinor || (occurrence.counterAmountMinor ?? 0)),
    ),
  );
  const interestMinor = Math.min(input.amountMinor, forecastInterestMinor);
  const totalMinor = input.amountMinor;
  const loanAccountId =
    occurrence.loanAccountId ?? (occurrence.loanIsLent ? input.accountId : input.counterAccountId);

  const primary = upsertFutureRuleTransaction(state, rule, occurrence, {
    type: 'loan_repayment',
    status: input.status,
    source: 'rule',
    accountId: input.accountId,
    counterAccountId: input.counterAccountId,
    amountMinor: totalMinor,
    currency: input.currency,
    counterAmountMinor: totalMinor,
    counterCurrency: occurrence.counterCurrency ?? input.currency,
    categoryId: undefined,
    occurredAt: input.occurredAt,
    paymentMethod: input.paymentMethod ?? undefined,
    notes: input.notes ?? undefined,
    tags: input.tags ?? undefined,
    recurringTemplateId: rule.id,
    externalRef: occurrence.externalRef,
  });

  upsertLoanInterestTransaction(state, rule, occurrence, primary, {
    amountMinor: interestMinor,
    currency: occurrence.interestCurrency ?? input.currency,
    occurredAt: input.occurredAt,
    status: input.status,
    accountId: loanAccountId,
    type: occurrence.loanIsLent ? 'interest_in' : 'interest_out',
    notes: `${rule.name} interest`,
    tags: input.tags ?? undefined,
    paymentMethod: input.paymentMethod ?? undefined,
  });

  return primary;
}

function upsertFutureRuleTransaction(
  state: LedgerState,
  rule: FutureGenerationRule,
  occurrence: FutureRuleOccurrence,
  input: Parameters<typeof createTransaction>[1],
): Transaction {
  const existing = transactionForFutureRuleOccurrence(state, rule, occurrence.dueOn);
  if (existing) {
    const updated = updateTransaction(state, existing.id, {
      type: input.type,
      status: input.status,
      source: input.source,
      accountId: input.accountId,
      counterAccountId: input.counterAccountId ?? null,
      amountMinor: input.amountMinor,
      currency: input.currency,
      counterAmountMinor: input.counterAmountMinor ?? null,
      counterCurrency: input.counterCurrency ?? null,
      counterFxRate: input.counterFxRate ?? null,
      categoryId: input.categoryId ?? null,
      merchantId: input.merchantId ?? null,
      occurredAt: input.occurredAt,
      locationLabel: input.locationLabel ?? null,
      paymentMethod: input.paymentMethod ?? null,
      notes: input.notes ?? null,
      attachments: input.attachments ?? null,
      tags: input.tags ?? null,
      isReimbursable: input.isReimbursable,
      isTaxDeductible: input.isTaxDeductible,
      isExcludedFromReports: input.isExcludedFromReports,
      originalTransactionId: input.originalTransactionId ?? null,
      recurringTemplateId: input.recurringTemplateId ?? null,
      externalRef: input.externalRef ?? null,
    });
    if (updated) return updated;
  }
  return createTransaction(state, input);
}

function upsertLoanInterestTransaction(
  state: LedgerState,
  rule: FutureGenerationRule,
  occurrence: FutureRuleOccurrence,
  primary: Transaction,
  input: {
    type: 'interest_in' | 'interest_out';
    status: TransactionStatus;
    accountId: UUID;
    amountMinor: number;
    currency: string;
    occurredAt: string;
    paymentMethod?: string;
    notes?: string;
    tags?: string[];
  },
): Transaction | undefined {
  const externalRef = futureRuleInterestExternalRef(occurrence.externalRef);
  const existing = state.transactions.find(
    (transaction) =>
      transaction.externalRef === externalRef ||
      (transaction.originalTransactionId === primary.id &&
        (transaction.type === 'interest_in' || transaction.type === 'interest_out')),
  );

  if (input.amountMinor <= 0) {
    if (existing && existing.status === 'scheduled') {
      state.transactions = state.transactions.filter(
        (transaction) => transaction.id !== existing.id,
      );
    }
    return existing;
  }

  if (existing) {
    return updateTransaction(state, existing.id, {
      type: input.type,
      status: input.status,
      source: 'rule',
      accountId: input.accountId,
      counterAccountId: null,
      amountMinor: input.amountMinor,
      currency: input.currency,
      categoryId: null,
      occurredAt: input.occurredAt,
      paymentMethod: input.paymentMethod ?? null,
      notes: input.notes ?? null,
      tags: input.tags ?? null,
      originalTransactionId: primary.id,
      recurringTemplateId: rule.id,
      externalRef,
    });
  }

  return createTransaction(state, {
    type: input.type,
    status: input.status,
    source: 'rule',
    accountId: input.accountId,
    amountMinor: input.amountMinor,
    currency: input.currency,
    categoryId: undefined,
    occurredAt: input.occurredAt,
    paymentMethod: input.paymentMethod,
    notes: input.notes,
    tags: input.tags,
    originalTransactionId: primary.id,
    recurringTemplateId: rule.id,
    externalRef,
  });
}

function canGenerateRule(state: LedgerState, rule: FutureGenerationRule): boolean {
  const account = state.accounts.find((item) => item.id === rule.accountId && !item.isArchived);
  if (!account) return false;
  if (normalizeCurrencyCode(account.currency) !== normalizeCurrencyCode(rule.currency))
    return false;
  if (rule.amountMinor <= 0) return false;
  if (TRANSFER_TYPES.has(rule.type)) {
    return Boolean(
      rule.counterAccountId &&
      state.accounts.some((item) => item.id === rule.counterAccountId && !item.isArchived),
    );
  }
  return true;
}

function canGenerateFromRecurringTemplate(state: LedgerState, template: Transaction): boolean {
  const account = state.accounts.find((item) => item.id === template.accountId && !item.isArchived);
  if (!account) return false;
  if (normalizeCurrencyCode(account.currency) !== normalizeCurrencyCode(template.amount.currency)) {
    return false;
  }
  if (template.amount.amountMinor <= 0) return false;
  if (TRANSFER_TYPES.has(template.type)) {
    return Boolean(
      template.counterAccountId &&
      state.accounts.some((item) => item.id === template.counterAccountId && !item.isArchived),
    );
  }
  return true;
}

function createRecurringScheduledTransaction(
  state: LedgerState,
  template: Transaction,
  externalRef: string,
  dueOn: string,
): void {
  const dueAt = withHour(dueOn, new Date(template.occurredAt).getHours() || 8);
  createTransaction(state, {
    type: template.type,
    status: 'scheduled',
    source: 'recurring',
    accountId: template.accountId,
    counterAccountId: template.counterAccountId,
    amountMinor: template.amount.amountMinor,
    currency: template.amount.currency,
    originalAmountMinor: template.originalAmount?.amountMinor,
    originalCurrency: template.originalAmount?.currency,
    originalFxRate: template.originalFxRate,
    counterAmountMinor: template.counterAmount?.amountMinor,
    counterCurrency: template.counterAmount?.currency,
    counterFxRate: template.counterFxRate,
    categoryId: template.categoryId,
    merchantId: template.merchantId,
    occurredAt: dueAt,
    locationLabel: template.locationLabel,
    paymentMethod: template.paymentMethod,
    notes: template.notes,
    attachments: template.attachments,
    tags: template.tags,
    isReimbursable: template.isReimbursable,
    isTaxDeductible: template.isTaxDeductible,
    isExcludedFromReports: template.isExcludedFromReports,
    originalTransactionId: template.originalTransactionId ?? template.id,
    recurringTemplateId: template.recurringTemplateId ?? template.id,
    externalRef,
  });
}

function hasRecurringScheduleOccurrence(
  state: LedgerState,
  signature: string,
  dueOn: string,
  externalRef: string,
): boolean {
  return state.transactions.some((transaction) => {
    if (transaction.status === 'void') return false;
    if (transaction.externalRef === externalRef) return true;
    if (toDateOnly(new Date(transaction.occurredAt)) !== dueOn) return false;
    return recurringTemplateSignature(transaction) === signature;
  });
}

function recurringTemplateSeriesId(template: Transaction, signature: string): string {
  return template.recurringTemplateId ?? stableHash(signature);
}

function recurringTemplateSignature(transaction: Transaction): string {
  return [
    transaction.type,
    transaction.accountId,
    transaction.counterAccountId ?? '',
    transaction.categoryId ?? '',
    transaction.amount.amountMinor,
    transaction.amount.currency,
    transaction.counterAmount?.amountMinor ?? '',
    transaction.counterAmount?.currency ?? '',
    transaction.paymentMethod ?? '',
    transaction.notes ?? '',
  ].join('|');
}

function stableHash(value: string): string {
  let hash = 0;
  for (let index = 0; index < value.length; index += 1) {
    hash = (hash * 31 + value.charCodeAt(index)) >>> 0;
  }
  return hash.toString(36);
}

function occurrenceDates(
  rule: FutureGenerationRule,
  now: Date,
  horizonEnd: Date,
  maxOccurrences: number,
): string[] {
  const startsOn = parseLocalDate(rule.startsOn) ?? startOfDay(now);
  const endsOn = rule.endsOn ? parseLocalDate(rule.endsOn) : undefined;
  const absoluteEnd = endsOn && endsOn < horizonEnd ? endsOn : horizonEnd;
  const today = startOfDay(now);
  const dates: string[] = [];
  if (rule.frequency === 'weekly') {
    return weeklyOccurrenceDates(rule, startsOn, today, absoluteEnd, maxOccurrences);
  }

  const monthlyDayOfMonth =
    rule.frequency === 'monthly' ? (rule.dayOfMonth ?? startsOn.getDate()) : rule.dayOfMonth;
  const totalLimit = rule.occurrences ?? Number.POSITIVE_INFINITY;
  const firstOccurrence = alignFirstOccurrence(startsOn, rule, monthlyDayOfMonth);
  let { cursor, totalOccurrences } = advanceOccurrenceCursor(
    firstOccurrence,
    rule,
    monthlyDayOfMonth,
    today,
    totalLimit,
  );

  while (totalOccurrences < totalLimit && dates.length < maxOccurrences && cursor <= absoluteEnd) {
    if (cursor >= today) dates.push(toDateOnly(cursor));
    totalOccurrences += 1;
    cursor = addFrequency(cursor, rule.frequency, rule.interval, monthlyDayOfMonth);
  }

  return dates;
}

function weeklyOccurrenceDates(
  rule: FutureGenerationRule,
  startsOn: Date,
  today: Date,
  absoluteEnd: Date,
  maxOccurrences: number,
): string[] {
  const weekdays = ruleDaysOfWeek(rule, startsOn);
  const firstOccurrence = firstWeeklyOccurrenceOnOrAfter(startsOn, weekdays);
  const interval = Math.max(1, rule.interval);
  const totalLimit = rule.occurrences ?? Number.POSITIVE_INFINITY;
  const dates: string[] = [];
  let totalOccurrences = 0;
  let weekStart = startOfWeek(firstOccurrence);

  while (
    totalOccurrences < totalLimit &&
    dates.length < maxOccurrences &&
    weekStart <= absoluteEnd
  ) {
    for (const weekday of weekdays) {
      const occurrence = addDays(weekStart, weekdayOffset(weekday));
      if (occurrence < firstOccurrence) continue;
      if (occurrence > absoluteEnd) break;
      if (totalOccurrences >= totalLimit) break;
      if (occurrence >= today) dates.push(toDateOnly(occurrence));
      totalOccurrences += 1;
      if (dates.length >= maxOccurrences) break;
    }
    weekStart = addDays(weekStart, interval * 7);
  }

  return dates;
}

function firstWeeklyOccurrenceOnOrAfter(startsOn: Date, weekdays: number[]): Date {
  const weekStart = startOfWeek(startsOn);
  let first: Date | undefined;
  for (const weekday of weekdays) {
    let candidate = addDays(weekStart, weekdayOffset(weekday));
    if (candidate < startsOn) candidate = addDays(candidate, 7);
    if (!first || candidate < first) first = candidate;
  }
  return first ?? startOfDay(startsOn);
}

function ruleDaysOfWeek(rule: FutureGenerationRule, startsOn: Date): number[] {
  return normalizeDaysOfWeek(rule.daysOfWeek) ?? [startsOn.getDay()];
}

function startOfWeek(date: Date): Date {
  return addDays(startOfDay(date), -weekdayOffset(date.getDay()));
}

function weekdayOffset(day: number): number {
  return (day + 6) % 7;
}

function advanceOccurrenceCursor(
  firstOccurrence: Date,
  rule: FutureGenerationRule,
  dayOfMonth: number | undefined,
  target: Date,
  totalLimit: number,
): { cursor: Date; totalOccurrences: number } {
  let cursor = startOfDay(firstOccurrence);
  if (cursor >= target) return { cursor, totalOccurrences: 0 };

  const interval = Math.max(1, rule.interval);
  let skipped = 0;

  if (rule.frequency === 'daily') {
    skipped = Math.ceil(daysBetween(cursor, target) / interval);
    cursor = addDays(cursor, skipped * interval);
  } else if (rule.frequency === 'weekly') {
    skipped = Math.ceil(daysBetween(cursor, target) / (interval * 7));
    cursor = addDays(cursor, skipped * interval * 7);
  } else if (rule.frequency === 'monthly') {
    const monthDistance = Math.max(0, monthsBetween(cursor, target));
    skipped = Math.floor(monthDistance / interval);
    cursor = addMonths(cursor, skipped * interval, dayOfMonth ?? cursor.getDate());
    if (cursor < target) {
      skipped += 1;
      cursor = addMonths(
        firstOccurrence,
        skipped * interval,
        dayOfMonth ?? firstOccurrence.getDate(),
      );
    }
  } else {
    while (skipped < totalLimit && cursor < target) {
      skipped += 1;
      cursor = addFrequency(cursor, rule.frequency, interval, dayOfMonth);
    }
  }

  if (skipped >= totalLimit) {
    return { cursor, totalOccurrences: totalLimit };
  }

  return { cursor: startOfDay(cursor), totalOccurrences: skipped };
}

function alignFirstOccurrence(
  startsOn: Date,
  rule: FutureGenerationRule,
  dayOfMonth?: number,
): Date {
  if (rule.frequency !== 'monthly' || !dayOfMonth) return startOfDay(startsOn);
  const aligned = new Date(
    startsOn.getFullYear(),
    startsOn.getMonth(),
    safeMonthDay(startsOn, dayOfMonth),
  );
  return aligned < startsOn ? addFrequency(aligned, 'monthly', rule.interval, dayOfMonth) : aligned;
}

function addFrequency(
  date: Date,
  frequency: FutureGenerationFrequency,
  interval: number,
  dayOfMonth?: number,
): Date {
  const next = new Date(date);
  if (frequency === 'daily') next.setDate(next.getDate() + interval);
  else if (frequency === 'weekly') next.setDate(next.getDate() + interval * 7);
  else if (frequency === 'yearly') next.setFullYear(next.getFullYear() + interval);
  else {
    return addMonths(date, interval, dayOfMonth ?? date.getDate());
  }
  return startOfDay(next);
}

function safeMonthDay(date: Date, dayOfMonth: number): number {
  return Math.min(dayOfMonth, new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate());
}

function parseLocalDate(value: string): Date | undefined {
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value);
  if (!match) return undefined;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (!year || !month || !day) return undefined;
  return new Date(year, month - 1, day);
}

function startOfDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function addMonths(date: Date, months: number, dayOfMonth = date.getDate()): Date {
  const next = new Date(date);
  next.setDate(1);
  next.setMonth(next.getMonth() + months);
  next.setDate(safeMonthDay(next, dayOfMonth));
  return startOfDay(next);
}

function addDays(date: Date, days: number): Date {
  const next = new Date(date);
  next.setDate(next.getDate() + days);
  return startOfDay(next);
}

function daysBetween(left: Date, right: Date): number {
  return localDayOrdinal(right) - localDayOrdinal(left);
}

function localDayOrdinal(date: Date): number {
  return Math.floor(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / 86400000);
}

function monthsBetween(left: Date, right: Date): number {
  return (right.getFullYear() - left.getFullYear()) * 12 + right.getMonth() - left.getMonth();
}

function toDateOnly(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function withHour(dateIso: string, hour: number): string {
  const date = parseLocalDate(dateIso) ?? new Date();
  date.setHours(hour, 0, 0, 0);
  return date.toISOString();
}

function todayIso(): string {
  return toDateOnly(new Date());
}

function normalizeInterval(value?: number): number {
  return Math.max(1, Math.floor(value ?? 1));
}

function normalizeDayOfMonth(value?: number): number | undefined {
  if (value === undefined) return undefined;
  return Math.min(31, Math.max(1, Math.floor(value)));
}

function normalizeDaysOfWeek(values?: number[]): number[] | undefined {
  const normalized = Array.from(
    new Set(
      (values ?? []).map((value) => Math.floor(value)).filter((value) => value >= 0 && value <= 6),
    ),
  ).sort((left, right) => weekdayOffset(left) - weekdayOffset(right));
  return normalized.length > 0 ? normalized : undefined;
}

function normalizeOccurrences(value?: number): number | undefined {
  if (value === undefined) return undefined;
  return Math.max(1, Math.floor(value));
}

function normalizeSkippedOccurrences(values?: string[]): string[] | undefined {
  const normalized = Array.from(
    new Set((values ?? []).filter((value) => /^\d{4}-\d{2}-\d{2}$/.test(value))),
  ).sort();
  return normalized.length > 0 ? normalized : undefined;
}

function cleanOptional(value?: string): string | undefined {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
}
