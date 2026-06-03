import { fromMinor, toMinor, type Money } from '@1wallet/domain/money';
import type {
  Account,
  AccountLoanDetails,
  LoanInterestMethod,
  LoanInterestRatePeriod,
  LoanKind,
  RecurrenceFrequency,
  Transaction,
} from '@1wallet/domain/types';
import {
  buildLoanForecast,
  findLinkedLoanRule,
  isLoanAccountType,
  loanScheduleSummary,
  type LoanForecast,
} from '@1wallet/ledger/loans';
import {
  forecastFutureRuleOccurrences,
  futureRuleInterestExternalRef,
  type FutureRuleOccurrence,
} from '@1wallet/ledger/rules/futureGeneration';
import { indexedAccountBalance, type LedgerIndexes } from '@1wallet/ledger/services/indexes';
import type { FutureGenerationRule, LedgerState } from '@1wallet/ledger/store/types';
import { accountIconForType, accountTypeLabel } from '../accountOptions';
import type { AppIconName } from '../components/AppKit';
import type { OptionListItem } from '../components/OptionListOverlay';
import {
  nearestActionableOccurrence,
  PLAN_DETAIL_OCCURRENCE_LOOKUP_OPTIONS,
} from '../plannedPayments/ruleActions';

export const LOAN_ACCOUNT_TYPES = new Set<Account['type']>(['loan', 'overdraft', 'lent']);

export const LOAN_KIND_OPTIONS: OptionListItem<LoanKind>[] = [
  {
    value: 'personal',
    label: 'Personal loan',
    description: 'General borrowed money',
    icon: 'account-cash-outline',
  },
  {
    value: 'home',
    label: 'Home loan',
    description: 'Mortgage or home finance',
    icon: 'home-outline',
  },
  {
    value: 'vehicle',
    label: 'Vehicle loan',
    description: 'Car, bike, or vehicle finance',
    icon: 'car-clock',
  },
  {
    value: 'education',
    label: 'Education loan',
    description: 'Study or course finance',
    icon: 'school-outline',
  },
  {
    value: 'business',
    label: 'Business loan',
    description: 'Business working capital',
    icon: 'briefcase-outline',
  },
  { value: 'gold', label: 'Gold loan', description: 'Loan against gold', icon: 'gold' },
  {
    value: 'bnpl',
    label: 'BNPL / EMI card',
    description: 'Buy-now-pay-later instalments',
    icon: 'credit-card-clock-outline',
  },
  {
    value: 'overdraft',
    label: 'Overdraft',
    description: 'Credit line or OD account',
    icon: 'alert-circle-outline',
  },
  {
    value: 'lent',
    label: 'Money lent',
    description: 'Someone repays you over time',
    icon: 'hand-coin-outline',
  },
  {
    value: 'other',
    label: 'Other loan',
    description: 'Anything custom',
    icon: 'dots-horizontal-circle-outline',
  },
];

export const FREQUENCY_OPTIONS: OptionListItem<RecurrenceFrequency>[] = [
  { value: 'daily', label: 'Daily', description: 'Every N days', icon: 'calendar-outline' },
  {
    value: 'weekly',
    label: 'Weekly',
    description: 'Every N weeks',
    icon: 'calendar-weekend-outline',
  },
  {
    value: 'monthly',
    label: 'Monthly',
    description: 'Every N months',
    icon: 'calendar-month-outline',
  },
  {
    value: 'yearly',
    label: 'Yearly',
    description: 'Every N years',
    icon: 'calendar-range-outline',
  },
];

export const RATE_PERIOD_OPTIONS: OptionListItem<LoanInterestRatePeriod>[] = [
  {
    value: 'annual',
    label: 'Annual rate',
    description: 'APR style interest rate',
    icon: 'percent-outline',
  },
  {
    value: 'monthly',
    label: 'Monthly rate',
    description: 'Interest percent applied each month',
    icon: 'calendar-month-outline',
  },
];

export const INTEREST_METHOD_OPTIONS: OptionListItem<LoanInterestMethod>[] = [
  {
    value: 'reducing_balance',
    label: 'Reducing balance',
    description: 'Interest is charged on what is still left',
    icon: 'chart-timeline-variant',
  },
  {
    value: 'flat',
    label: 'Flat interest',
    description: 'Interest is based on original principal',
    icon: 'chart-line-variant',
  },
  {
    value: 'interest_only',
    label: 'Interest first',
    description: 'Shows interest before principal payoff',
    icon: 'bank-minus',
  },
];

export type LoanDraftFields = {
  loanKind: LoanKind;
  sourceAccountId: string;
  principal: string;
  payment: string;
  rate: string;
  ratePeriod: LoanInterestRatePeriod;
  interestMethod: LoanInterestMethod;
  disbursedOn: string;
  startsOn: string;
  frequency: RecurrenceFrequency;
  interval: string;
  dayOfMonth: string;
  installments: string;
  paidInstallments?: string;
  trackingStartsOn?: string;
  endsOn: string;
  autoCreate: boolean;
};

export type LoanListItem = {
  loan: Account;
  forecast: LoanForecast;
  balance: Money;
  paidOff: boolean;
  linkedRule?: FutureGenerationRule;
  linkedRuleName?: string;
  nextDue?: FutureRuleOccurrence;
  transactions: Transaction[];
};

export type LoanListItemsOptions = {
  includePaidOff?: boolean;
};

export type LoanRecordItem = {
  key: string;
  kind: 'transaction' | 'forecast';
  occurredAt: string;
  status: Transaction['status'] | 'forecast';
  total: Money;
  principal?: Money;
  interest?: Money;
  transaction?: Transaction;
  interestTransaction?: Transaction;
  occurrence?: FutureRuleOccurrence;
};

export type LoanPrincipalProgress = {
  paid: Money;
  total: Money;
  progress: number;
};

export function activeLoanAccounts(state: LedgerState): Account[] {
  return state.accounts
    .filter((account) => !account.isArchived && isLoanAccountType(account.type))
    .sort((left, right) => left.sortOrder - right.sortOrder || left.name.localeCompare(right.name));
}

export function repaymentSourceAccounts(accounts: Account[], loan?: Account): Account[] {
  return accounts
    .filter((account) => !account.isArchived)
    .filter((account) => account.id !== loan?.id)
    .filter((account) => !isLoanAccountType(account.type))
    .filter((account) => !loan || account.currency === loan.currency)
    .sort((left, right) => left.sortOrder - right.sortOrder || left.name.localeCompare(right.name));
}

export function buildDraftLoanDetails(loan: Account, input: LoanDraftFields): AccountLoanDetails {
  const principalAmount = Math.max(0, parseAmount(input.principal));
  const paymentAmount = Math.max(0, parseAmount(input.payment));
  const interval = clampInt(input.interval, 1, 365, 1);
  const dayOfMonth = clampInt(input.dayOfMonth, 1, 31, new Date().getDate());
  const repaymentCount = input.installments.trim()
    ? clampInt(input.installments, 1, 1200, 12)
    : undefined;
  const paidInstallments = input.paidInstallments?.trim()
    ? clampInt(input.paidInstallments, 0, 1200, 0)
    : undefined;

  return {
    loanKind: input.loanKind,
    principal: { amountMinor: toMinor(principalAmount, loan.currency), currency: loan.currency },
    disbursedOn: input.disbursedOn.trim() || input.startsOn.trim() || todayIso(),
    interestRatePercent: Math.max(0, Number(input.rate) || 0),
    interestRatePeriod: input.ratePeriod,
    interestMethod: input.interestMethod,
    repaymentSourceAccountId: input.sourceAccountId || undefined,
    repaymentAmount: {
      amountMinor: toMinor(paymentAmount, loan.currency),
      currency: loan.currency,
    },
    repaymentStartsOn: input.startsOn.trim() || input.disbursedOn.trim() || todayIso(),
    repaymentFrequency: input.frequency,
    repaymentInterval: interval,
    repaymentDayOfMonth: dayOfMonth,
    repaymentCount,
    repaymentEndsOn: input.endsOn.trim() || undefined,
    autoCreateScheduledRecords: input.autoCreate,
    trackingStartsOn: input.trackingStartsOn?.trim() || undefined,
    paidInstallmentsBeforeTracking: paidInstallments,
  };
}

export function loanListItems(
  state: LedgerState,
  indexes: LedgerIndexes,
  horizonMonths = 12,
  options: LoanListItemsOptions = {},
): LoanListItem[] {
  return activeLoanAccounts(state)
    .map((loan) => {
      const details = loan.loanDetails ?? fallbackLoanDetails(loan, indexes);
      const balance = indexedAccountBalance(indexes, loan);
      const forecast = buildLoanForecast(state, loan, details, balance);
      const linkedRule = findLinkedLoanRule(state, loan.id);
      const item = {
        loan,
        forecast,
        balance,
        paidOff: false,
        linkedRule,
        linkedRuleName: linkedRule?.name,
        nextDue: linkedRule
          ? (nearestActionableOccurrence(
              state,
              linkedRule,
              PLAN_DETAIL_OCCURRENCE_LOOKUP_OPTIONS,
            ) ?? loanForecastOccurrences(state, loan, horizonMonths)[0])
          : undefined,
        transactions: loanRepaymentTransactions(state, loan.id),
      };
      return { ...item, paidOff: isPaidOffLoanItem(item) };
    })
    .filter((item) => options.includePaidOff || !item.paidOff);
}

function isPaidOffLoanItem(item: LoanListItem): boolean {
  const progress = loanPrincipalProgress(item.loan, item.balance);
  return (
    progress.total.amountMinor > 0 &&
    progress.progress >= 1 &&
    item.forecast.outstanding.amountMinor === 0
  );
}

export function fallbackLoanDetails(loan: Account, indexes: LedgerIndexes): AccountLoanDetails {
  const balance = indexedAccountBalance(indexes, loan);
  return {
    loanKind: defaultLoanKind(loan),
    principal: { amountMinor: Math.abs(balance.amountMinor), currency: loan.currency },
    repaymentAmount: { amountMinor: 0, currency: loan.currency },
    repaymentStartsOn: todayIso(),
    repaymentFrequency: 'monthly',
    repaymentInterval: 1,
    repaymentDayOfMonth: new Date().getDate(),
    repaymentCount: 12,
    interestRatePercent: 0,
    interestRatePeriod: 'annual',
    interestMethod: 'reducing_balance',
    autoCreateScheduledRecords: false,
  };
}

export function loanForecastOccurrences(
  state: LedgerState,
  loan: Account,
  horizonMonths: number,
  now = new Date(),
): FutureRuleOccurrence[] {
  const linkedRule = findLinkedLoanRule(state, loan.id);
  if (!linkedRule) return [];
  const from = startOfDay(now);
  const to = addMonthsKeepingDay(from, horizonMonths);
  return forecastFutureRuleOccurrences(state, {
    from,
    to,
    now: from,
    maxOccurrencesPerRule: Math.max(24, horizonMonths * 4),
    ruleIds: [linkedRule.id],
  }).filter(
    (occurrence) =>
      occurrence.type === 'loan_repayment' &&
      (occurrence.accountId === loan.id || occurrence.counterAccountId === loan.id),
  );
}

export function loanRepaymentTransactions(state: LedgerState, loanId: string): Transaction[] {
  return state.transactions
    .filter(
      (transaction) =>
        transaction.type === 'loan_repayment' &&
        transaction.status !== 'void' &&
        (transaction.accountId === loanId || transaction.counterAccountId === loanId),
    )
    .sort((left, right) => right.occurredAt.localeCompare(left.occurredAt));
}

export function linkedLoanInterestTransaction(
  state: LedgerState,
  repayment: Transaction,
): Transaction | undefined {
  const expectedRef = repayment.externalRef
    ? futureRuleInterestExternalRef(repayment.externalRef)
    : undefined;
  return state.transactions.find((transaction) => {
    if (transaction.status === 'void') return false;
    if (expectedRef && transaction.externalRef === expectedRef) return true;
    return (
      transaction.originalTransactionId === repayment.id &&
      (transaction.type === 'interest_in' || transaction.type === 'interest_out')
    );
  });
}

export function loanRepaymentBreakdown(
  loan: Account,
  transaction: Transaction,
  interestTransaction?: Transaction,
): { total: Money; principal: Money; interest?: Money } {
  const linkedInterest = interestTransaction?.amount;
  const usesLoanInterestAccount = Boolean(
    interestTransaction && interestTransaction.accountId === loan.id,
  );
  if (usesLoanInterestAccount) {
    const interestMinor = Math.max(0, linkedInterest?.amountMinor ?? 0);
    return {
      total: transaction.amount,
      principal: {
        amountMinor: Math.max(0, transaction.amount.amountMinor - interestMinor),
        currency: transaction.amount.currency,
      },
      interest: linkedInterest,
    };
  }

  const principal = transaction.counterAmount ?? transaction.amount;
  const impliedInterestMinor = Math.max(
    0,
    transaction.amount.amountMinor -
      (transaction.counterAmount?.amountMinor ?? transaction.amount.amountMinor),
  );
  const interest =
    linkedInterest ??
    (impliedInterestMinor > 0
      ? { amountMinor: impliedInterestMinor, currency: transaction.amount.currency }
      : undefined);
  const total = interest
    ? {
        amountMinor: transaction.amount.amountMinor + interest.amountMinor,
        currency: transaction.amount.currency,
      }
    : transaction.amount;

  return { total, principal, interest };
}

export function loanRecordItems(
  state: LedgerState,
  loan: Account,
  horizonMonths = 12,
): LoanRecordItem[] {
  const transactions = loanRepaymentTransactions(state, loan.id);
  const postedTransactions = transactions.filter(
    (transaction) => transaction.status === 'cleared' || transaction.status === 'pending',
  );
  const transactionItems = postedTransactions.map((transaction): LoanRecordItem => {
    const interestTransaction = linkedLoanInterestTransaction(state, transaction);
    const breakdown = loanRepaymentBreakdown(loan, transaction, interestTransaction);

    return {
      key: transaction.id,
      kind: 'transaction',
      occurredAt: transaction.occurredAt,
      status: transaction.status,
      total: breakdown.total,
      principal: breakdown.principal,
      interest: breakdown.interest,
      transaction,
      interestTransaction,
    };
  });

  const existingOccurrenceRefs = new Set<string>();
  const existingOccurrenceDates = new Set<string>();
  for (const transaction of transactions) {
    if (transaction.externalRef) existingOccurrenceRefs.add(transaction.externalRef);
    existingOccurrenceDates.add(dateOnly(transaction.occurredAt));
  }
  const forecastItems = loanForecastOccurrences(state, loan, horizonMonths)
    .filter(
      (occurrence) =>
        !existingOccurrenceRefs.has(occurrence.externalRef) &&
        !existingOccurrenceDates.has(occurrence.dueOn),
    )
    .map((occurrence): LoanRecordItem => {
      const principalMinor = Math.max(
        0,
        occurrence.principalAmountMinor ?? occurrence.counterAmountMinor ?? occurrence.amountMinor,
      );
      const interestMinor = Math.max(0, occurrence.amountMinor - principalMinor);
      return {
        key: occurrence.externalRef,
        kind: 'forecast',
        occurredAt: occurrence.occurredAt,
        status: 'forecast',
        total: { amountMinor: occurrence.amountMinor, currency: occurrence.currency },
        principal: { amountMinor: principalMinor, currency: occurrence.currency },
        interest:
          interestMinor > 0
            ? { amountMinor: interestMinor, currency: occurrence.currency }
            : undefined,
        occurrence,
      };
    });

  return [...transactionItems, ...forecastItems].sort((left, right) =>
    right.occurredAt.localeCompare(left.occurredAt),
  );
}

export function loanPrincipalProgress(loan: Account, balance: Money): LoanPrincipalProgress {
  const details = loan.loanDetails;
  if (details?.repaymentCount) {
    const summary = loanScheduleSummary(details, loan.currency);
    const principalMinor = Math.max(0, Math.abs(details.principal?.amountMinor ?? 0));
    const principalPaymentMinor = Math.max(0, details.repaymentAmount?.amountMinor ?? 0);
    const paidMinor = Math.max(
      0,
      Math.min(principalMinor, principalPaymentMinor * summary.completedInstallments),
    );

    return {
      paid: { amountMinor: paidMinor, currency: loan.currency },
      total: {
        amountMinor: principalMinor || Math.abs(balance.amountMinor),
        currency: loan.currency,
      },
      progress: summary.progress,
    };
  }

  const totalMinor = Math.max(
    0,
    Math.abs(loan.loanDetails?.principal?.amountMinor ?? 0) || Math.abs(balance.amountMinor),
  );
  const outstandingMinor = Math.max(0, Math.abs(balance.amountMinor));
  const paidMinor =
    totalMinor > 0 ? Math.max(0, Math.min(totalMinor, totalMinor - outstandingMinor)) : 0;

  return {
    paid: { amountMinor: paidMinor, currency: loan.currency },
    total: { amountMinor: totalMinor, currency: loan.currency },
    progress: totalMinor > 0 ? paidMinor / totalMinor : 0,
  };
}

export function loanIcon(loan: Account): AppIconName {
  return accountIconForType(loan.type);
}

export function loanSubtitle(loan: Account): string {
  return `${accountTypeLabel(loan.type)} · ${loan.currency}`;
}

export function defaultLoanKind(account: Account): LoanKind {
  if (account.type === 'overdraft') return 'overdraft';
  if (account.type === 'lent') return 'lent';
  const haystack = `${account.name} ${account.institution ?? ''}`.toLowerCase();
  if (haystack.includes('home') || haystack.includes('mortgage')) return 'home';
  if (haystack.includes('car') || haystack.includes('bike') || haystack.includes('vehicle')) {
    return 'vehicle';
  }
  if (haystack.includes('education') || haystack.includes('student')) return 'education';
  if (haystack.includes('gold')) return 'gold';
  if (haystack.includes('emi') || haystack.includes('bnpl')) return 'bnpl';
  return 'personal';
}

export function loanKindLabel(kind?: LoanKind): string {
  return optionLabel(LOAN_KIND_OPTIONS, kind ?? 'personal');
}

export function interestMethodLabel(method?: LoanInterestMethod): string {
  return optionLabel(INTEREST_METHOD_OPTIONS, method ?? 'reducing_balance');
}

export function frequencyLabel(frequency?: RecurrenceFrequency): string {
  return optionLabel(FREQUENCY_OPTIONS, frequency ?? 'monthly');
}

export function loanScheduleCloseLabel(
  closesOn: string | undefined,
  locale: string,
  now = new Date(),
): string {
  if (!closesOn) return 'Needs EMI setup';
  const duration = calendarDurationLabel(now, closesOn);
  const closeDate = dateLabel(closesOn, locale);
  return duration ? `${duration} · ${closeDate}` : closeDate;
}

export function loanCadenceLabel(details?: AccountLoanDetails | null, locale = 'en-IN'): string {
  if (!details) return 'Not set';
  const frequency = details.repaymentFrequency ?? 'monthly';
  const interval = Math.max(1, details.repaymentInterval ?? 1);
  const cadence = recurrenceCadenceLabel(
    frequency,
    interval,
    details.repaymentStartsOn,
    details.repaymentDayOfMonth,
    locale,
  );
  const end = details.repaymentCount
    ? emiTotalLabel(details.repaymentCount)
    : details.repaymentEndsOn
      ? `until ${dateLabel(details.repaymentEndsOn, locale)}`
      : '';
  return end ? `${cadence} · ${end}` : cadence;
}

export function emiTotalLabel(count: number): string {
  return `${count} ${count === 1 ? 'EMI' : 'EMIs'} total`;
}

export function emiRemainingLabel(count: number): string {
  return `${count} ${count === 1 ? 'EMI' : 'EMIs'} left`;
}

export function recurrenceCadenceLabel(
  frequency: RecurrenceFrequency = 'monthly',
  interval = 1,
  startsOn?: string,
  dayOfMonth?: number,
  locale = 'en-IN',
): string {
  const normalizedInterval = Math.max(1, interval || 1);
  if (frequency === 'daily') {
    return normalizedInterval === 1 ? 'Daily' : `Every ${normalizedInterval} days`;
  }
  if (frequency === 'weekly') {
    const weekday = weekdayLabel(startsOn, locale);
    return normalizedInterval === 1
      ? `Weekly on ${weekday}`
      : `Every ${normalizedInterval} weeks on ${weekday}`;
  }
  if (frequency === 'yearly') {
    const date = monthDayLabel(startsOn, locale);
    return normalizedInterval === 1
      ? `Yearly on ${date}`
      : `Every ${normalizedInterval} years on ${date}`;
  }
  const day = dayOfMonth ?? dateDay(startsOn) ?? 1;
  return normalizedInterval === 1
    ? `Monthly on ${ordinal(day)}`
    : `Every ${normalizedInterval} months on ${ordinal(day)}`;
}

export function ordinal(value: number): string {
  const normalized = Math.max(1, Math.trunc(value));
  const suffix =
    normalized % 100 >= 11 && normalized % 100 <= 13
      ? 'th'
      : (['th', 'st', 'nd', 'rd'][normalized % 10] ?? 'th');
  return `${normalized}${suffix}`;
}

export function optionLabel<TValue extends string>(
  options: readonly OptionListItem<TValue>[],
  value: TValue,
): string {
  return options.find((option) => option.value === value)?.label ?? value;
}

export function formatInputAmount(money: Money): string {
  return String(fromMinor(Math.abs(money.amountMinor), money.currency));
}

export function parseAmount(value: string): number {
  return Number(value.replace(/,/g, '').trim()) || 0;
}

export function clampInt(value: string, min: number, max: number, fallback: number): number {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

export function isValidIsoDate(value?: string): value is string {
  if (!value) return false;
  return /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(new Date(value).getTime());
}

export function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

function dateOnly(value: string): string {
  return value.slice(0, 10);
}

export function dueLabel(iso: string, now = new Date()): string {
  const due = startOfDay(parseLocalDateValue(iso));
  const today = startOfDay(now);
  const days = Math.round((due.getTime() - today.getTime()) / 86_400_000);
  if (days < 0) return `Overdue by ${dayCountLabel(Math.abs(days))}`;
  if (days === 0) return 'Due today';
  if (days === 1) return 'Due tomorrow';
  return `Due in ${dayCountLabel(days)}`;
}

function dayCountLabel(days: number): string {
  return `${days} ${days === 1 ? 'day' : 'days'}`;
}

export function dateLabel(iso: string, locale: string): string {
  const date = parseLocalDateValue(iso);
  if (Number.isNaN(date.getTime())) return iso;
  return date.toLocaleDateString(locale, { month: 'short', day: 'numeric', year: 'numeric' });
}

export function monthsLabel(months?: number): string {
  if (months === undefined) return 'Needs EMI';
  if (months === 0) return 'Closed';
  if (months < 12) return `${months} mo`;
  const years = Math.floor(months / 12);
  const rest = months % 12;
  return rest === 0 ? `${years} yr` : `${years} yr ${rest} mo`;
}

export function calendarDurationLabel(from: Date | string, to: Date | string): string {
  const fromDate = startOfDay(typeof from === 'string' ? parseLocalDateValue(from) : from);
  const toDate = startOfDay(typeof to === 'string' ? parseLocalDateValue(to) : to);
  if (Number.isNaN(fromDate.getTime()) || Number.isNaN(toDate.getTime())) return '';
  if (toDate.getTime() < fromDate.getTime()) return 'Closed';

  let months =
    (toDate.getFullYear() - fromDate.getFullYear()) * 12 +
    (toDate.getMonth() - fromDate.getMonth());
  const anchor = addMonthsKeepingDay(fromDate, months);
  if (anchor.getTime() > toDate.getTime()) months -= 1;
  if (months <= 0) return 'Closes this month';
  return monthsLabel(months);
}

function dateDay(value?: string): number | undefined {
  if (!value) return undefined;
  const date = parseLocalDateValue(value);
  return Number.isNaN(date.getTime()) ? undefined : date.getDate();
}

function weekdayLabel(value: string | undefined, locale: string): string {
  if (!value) return 'start day';
  const date = parseLocalDateValue(value);
  if (Number.isNaN(date.getTime())) return 'start day';
  return date.toLocaleDateString(locale, { weekday: 'short' });
}

function monthDayLabel(value: string | undefined, locale: string): string {
  if (!value) return 'start date';
  const date = parseLocalDateValue(value);
  if (Number.isNaN(date.getTime())) return 'start date';
  return date.toLocaleDateString(locale, { month: 'short', day: 'numeric' });
}

function parseLocalDateValue(value: string): Date {
  const match = /^(\d{4})-(\d{2})-(\d{2})(?:$|T)/.exec(value);
  if (!match) return new Date(value);
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (!year || !month || !day) return new Date(value);
  const timeIndex = value.indexOf('T');
  if (timeIndex >= 0) {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? new Date(year, month - 1, day) : parsed;
  }
  return new Date(year, month - 1, day);
}

export function addMonthsKeepingDay(value: Date, months: number): Date {
  return new Date(value.getFullYear(), value.getMonth() + months, value.getDate());
}

export function startOfDay(date: Date): Date {
  const next = new Date(date);
  next.setHours(0, 0, 0, 0);
  return next;
}
