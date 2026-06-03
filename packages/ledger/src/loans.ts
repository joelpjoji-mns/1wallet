import type { Money } from '@1wallet/domain/money';
import type {
    Account,
    AccountLoanDetails,
    LoanInterestRatePeriod,
    RecurrenceFrequency,
    UUID,
} from '@1wallet/domain/types';
import type { CreateFutureGenerationRuleInput } from './rules/futureGeneration';
import { accountBalance, convertMoneyForDisplay } from './services/index';
import type { FutureGenerationRule, LedgerState } from './store/types';

export type LoanForecastRow = {
  installment: number;
  dueAt: string;
  payment: Money;
  interest: Money;
  principal: Money;
  balanceAfter: Money;
};

export type LoanForecast = {
  outstanding: Money;
  rows: LoanForecastRow[];
  totalInterest: Money;
  totalPayment: Money;
  closesOn?: string;
  scheduleClosesOn?: string;
  nextDueOn?: string;
  completedInstallments: number;
  totalInstallments?: number;
  remainingInstallments?: number;
  finalBalance: Money;
  progress: number;
};

export type LoanScheduleSummary = {
  startsOn: string;
  trackingStartsOn: string;
  completedInstallments: number;
  totalInstallments?: number;
  remainingInstallments?: number;
  nextDueOn?: string;
  closesOn?: string;
  outstanding: Money;
  progress: number;
};

export type LoanPayoffStrategy = 'equal' | 'avalanche' | 'snowball';

export type LoanPayoffLoanPlan = {
  account: Account;
  outstanding: Money;
  baseOutstanding: Money;
  monthlyPayment: Money;
  extraMonthlyPayment: Money;
  normalForecast: LoanForecast;
  acceleratedForecast: LoanForecast;
  normalClosesOn?: string;
  acceleratedClosesOn?: string;
  normalMonthsToClose?: number;
  acceleratedMonthsToClose?: number;
  totalInterest: Money;
  acceleratedTotalInterest: Money;
  interestSaved: Money;
};

export type LoanPayoffProjection = {
  strategy: LoanPayoffStrategy;
  currency: string;
  selectedLoanIds: UUID[];
  loans: LoanPayoffLoanPlan[];
  outstanding: Money;
  monthlyPayment: Money;
  extraMonthlyPayment: Money;
  totalInterest: Money;
  acceleratedTotalInterest: Money;
  interestSaved: Money;
  normalClosesOn?: string;
  acceleratedClosesOn?: string;
  normalMonthsToClose?: number;
  acceleratedMonthsToClose?: number;
  monthsSaved?: number;
};

export type BuildLoanPayoffProjectionInput = {
  loanIds?: UUID[];
  extraMonthlyPaymentMinor?: number;
  strategy?: LoanPayoffStrategy;
  currentBalances?: Record<UUID, Money | undefined>;
};

export type DeriveLoanOutstandingPrincipalOptions = {
  asOf?: string | Date;
  paidInstallments?: number;
};

export type LoanRuleOccurrenceAmounts = {
  amountMinor: number;
  currency: string;
  principalAmountMinor: number;
  principalCurrency: string;
  interestAmountMinor: number;
  interestCurrency: string;
  loanAccountId: UUID;
  loanIsLent: boolean;
  counterAmountMinor?: number;
  counterCurrency?: string;
};

export const LOAN_RULE_TAG_PREFIX = 'loan-rule-v1';
export const LEGACY_LOAN_PLAN_REF_PREFIX = 'loan-plan-v1';

const LOAN_ACCOUNT_TYPES = new Set<Account['type']>(['loan', 'overdraft', 'lent']);

export function isLoanAccountType(type: Account['type']): boolean {
  return LOAN_ACCOUNT_TYPES.has(type);
}

export function isLoanAccount(account?: Account): account is Account {
  return Boolean(account && isLoanAccountType(account.type));
}

export function loanRuleTag(loanAccountId: UUID): string {
  return `${LOAN_RULE_TAG_PREFIX}:${loanAccountId}`;
}

export function legacyLoanPlanRefPrefix(loanAccountId: UUID): string {
  return `${LEGACY_LOAN_PLAN_REF_PREFIX}:${loanAccountId}`;
}

export function findLinkedLoanRule(
  state: LedgerState,
  loanAccountId: UUID,
): FutureGenerationRule | undefined {
  const loan = state.accounts.find((account) => account.id === loanAccountId);
  if (!isLoanAccount(loan)) return undefined;
  const rules = state.preferences.futureGenerationRules ?? [];
  const details = loan.loanDetails;
  if (details?.linkedPlannedPaymentRuleId) {
    const linked = rules.find((rule) => rule.id === details.linkedPlannedPaymentRuleId);
    if (linked) return linked;
  }

  const tag = loanRuleTag(loan.id);
  return (
    rules.find((rule) => rule.tags?.includes(tag)) ??
    rules.find(
      (rule) =>
        rule.type === 'loan_repayment' &&
        (loan.type === 'lent' ? rule.accountId === loan.id : rule.counterAccountId === loan.id),
    )
  );
}

export function findLoanAccountForRule(
  state: LedgerState,
  rule: FutureGenerationRule,
): Account | undefined {
  const endpointLoan = endpointLoanAccountForRule(state, rule);
  if (endpointLoan) return endpointLoan;

  const linkedLoan = state.accounts.find(
    (account) =>
      isLoanAccount(account) && account.loanDetails?.linkedPlannedPaymentRuleId === rule.id,
  );
  if (linkedLoan) return linkedLoan;

  const taggedLoanId = loanAccountIdFromRuleTags(rule);
  return taggedLoanId
    ? state.accounts.find((account) => account.id === taggedLoanId && isLoanAccount(account))
    : undefined;
}

export function syncLoanDetailsFromRule(
  state: LedgerState,
  rule: FutureGenerationRule,
): Account | undefined {
  if ((rule.kind as string | undefined) !== 'loan_emi' && rule.type !== 'loan_repayment') {
    return undefined;
  }
  const loan = findLoanAccountForRule(state, rule);
  if (!loan) return undefined;

  const repaymentSourceAccountId = loan.type === 'lent' ? rule.counterAccountId : rule.accountId;
  if (!repaymentSourceAccountId) return undefined;

  const existingDetails = loan.loanDetails ?? {};
  const syncedTrackingStartsOn =
    existingDetails.paidInstallmentsBeforeTracking !== undefined
      ? (existingDetails.trackingStartsOn ?? firstActiveRuleOccurrenceOn(rule) ?? rule.startsOn)
      : (firstActiveRuleOccurrenceOn(rule) ?? rule.startsOn);
  const repaymentAmount = convertMoneyForDisplay(
    state,
    { amountMinor: rule.amountMinor, currency: rule.currency },
    loan.currency,
  );
  const nextDetails: AccountLoanDetails = {
    ...existingDetails,
    repaymentSourceAccountId,
    repaymentAmount,
    repaymentFrequency: rule.frequency,
    repaymentInterval: rule.interval,
    repaymentDayOfMonth: rule.dayOfMonth,
    repaymentCount: rule.occurrences,
    repaymentEndsOn: rule.endsOn,
    autoCreateScheduledRecords: rule.enabled,
    trackingStartsOn: syncedTrackingStartsOn,
    repaymentStartsOn: rule.startsOn,
    linkedPlannedPaymentRuleId: rule.id,
    notes: rule.notes ?? existingDetails.notes,
  };

  loan.loanDetails = nextDetails;
  loan.updatedAt = new Date().toISOString();
  rule.tags = uniqueTags([
    ...(rule.tags ?? []).filter((tag) => !tag.startsWith(`${LOAN_RULE_TAG_PREFIX}:`)),
    loanRuleTag(loan.id),
    'loan_emi',
  ]);

  for (const account of state.accounts) {
    if (account.id === loan.id || !isLoanAccount(account)) continue;
    if (account.loanDetails?.linkedPlannedPaymentRuleId !== rule.id) continue;
    account.loanDetails = { ...account.loanDetails, linkedPlannedPaymentRuleId: undefined };
    account.updatedAt = new Date().toISOString();
  }

  return loan;
}

function firstActiveRuleOccurrenceOn(rule: FutureGenerationRule): string | undefined {
  const skipped = new Set(rule.skippedOccurrences ?? []);
  const occurrenceLimit = rule.occurrences ?? 1200;
  for (let index = 0; index < occurrenceLimit; index += 1) {
    const dueOn = toDateOnly(
      dueDateForInstallment(rule.startsOn, rule.frequency, rule.interval, index, rule.dayOfMonth),
    );
    if (!skipped.has(dueOn)) return dueOn;
  }
  return undefined;
}

export function buildLoanPlannedPaymentInput(
  loan: Account,
  details: AccountLoanDetails,
  existingTags: string[] = [],
): CreateFutureGenerationRuleInput | undefined {
  if (!isLoanAccount(loan)) return undefined;
  const repaymentSourceAccountId = details.repaymentSourceAccountId;
  const repaymentAmountMinor = details.repaymentAmount?.amountMinor ?? 0;
  if (!repaymentSourceAccountId || repaymentAmountMinor <= 0) return undefined;

  const loanIsLent = loan.type === 'lent';
  return {
    name: `${loan.name} EMI`,
    kind: 'transfer',
    postMode: 'manual',
    type: 'loan_repayment',
    accountId: loanIsLent ? loan.id : repaymentSourceAccountId,
    counterAccountId: loanIsLent ? repaymentSourceAccountId : loan.id,
    amountMinor: repaymentAmountMinor,
    currency: loan.currency,
    frequency: details.repaymentFrequency ?? 'monthly',
    interval: details.repaymentInterval ?? 1,
    dayOfMonth: details.repaymentDayOfMonth,
    startsOn: loanRepaymentStartsOn(details),
    endsOn: details.repaymentEndsOn,
    occurrences: details.repaymentCount,
    skippedOccurrences: completedLoanOccurrenceDates(details),
    paymentMethod: loanIsLent ? 'Repayment received' : 'Auto debit',
    notes: details.notes ?? `${loan.name} repayment plan`,
    tags: uniqueTags([...existingTags, loanRuleTag(loan.id), 'loan_emi']),
    enabled: details.autoCreateScheduledRecords ?? true,
  };
}

export function buildLoanForecast(
  state: LedgerState,
  loan: Account,
  details: AccountLoanDetails,
  currentBalance?: Money,
): LoanForecast {
  const principalMinor = Math.abs(details.principal?.amountMinor ?? 0);
  const balanceMinor = Math.abs((currentBalance ?? accountBalance(state, loan.id)).amountMinor);
  const principalPaymentMinor = Math.max(0, details.repaymentAmount?.amountMinor ?? 0);
  const frequency = details.repaymentFrequency ?? 'monthly';
  const interval = Math.max(1, details.repaymentInterval ?? 1);
  const rate = Math.max(0, details.interestRatePercent ?? 0);
  const ratePerPayment = rateForFrequency(
    rate,
    details.interestRatePeriod ?? 'annual',
    frequency,
    interval,
  );
  const totalInstallments = loanTotalInstallmentCount(details);
  const countLimit = totalInstallments ?? 600;
  const end = details.repaymentEndsOn ? parseDateOnly(details.repaymentEndsOn) : undefined;
  const scheduleStartsOn = loanRepaymentStartsOn(details);
  const startsOn = loanForecastStartsOn(details);
  const completedInstallments = totalInstallments
    ? Math.min(completedLoanInstallmentCount(details, startsOn), totalInstallments)
    : completedLoanInstallmentCount(details, startsOn);
  const remainingInstallments = totalInstallments
    ? Math.max(0, totalInstallments - completedInstallments)
    : undefined;
  const calculatedOutstanding =
    principalMinor > 0 && principalPaymentMinor > 0
      ? deriveLoanOutstandingPrincipal(details, loan.currency, {
          paidInstallments: completedInstallments,
        }).amountMinor
      : undefined;
  const startingBalance = calculatedOutstanding ?? (balanceMinor || principalMinor);
  const scheduleClosesOn = loanScheduleCloseDate(details);
  const nextDueOn = nextLoanInstallmentDueOn(details, startsOn);
  const rows: LoanForecastRow[] = [];
  let balance = startingBalance;
  let totalInterest = 0;
  let totalPayment = 0;
  let closesOn: string | undefined;

  if (
    principalPaymentMinor <= 0 ||
    !isValidDateOnly(startsOn) ||
    !isValidDateOnly(scheduleStartsOn)
  ) {
    return emptyForecast(startingBalance, loan.currency, {
      completedInstallments,
      totalInstallments,
      remainingInstallments,
      scheduleClosesOn,
      nextDueOn,
    });
  }

  const rowsLimit = totalInstallments
    ? Math.max(0, countLimit - completedInstallments)
    : countLimit;
  for (let index = 0; index < rowsLimit && balance > 0; index += 1) {
    const installmentIndex = completedInstallments + index;
    const due = dueDateForInstallment(
      scheduleStartsOn,
      frequency,
      interval,
      installmentIndex,
      details.repaymentDayOfMonth,
    );
    if (end && due > end) break;
    const interestBase = details.interestMethod === 'flat' ? principalMinor : balance;
    const interestPeriods = interestPeriodsForInstallment(
      details,
      installmentIndex,
      due,
      frequency,
      interval,
    );
    const interest = Math.max(0, Math.round(interestBase * ratePerPayment * interestPeriods));
    const principalPaid = Math.max(0, Math.min(principalPaymentMinor, balance));
    const payment = principalPaid + interest;
    balance = Math.max(0, balance - principalPaid);
    totalInterest += interest;
    totalPayment += payment;
    const dueIso = toDateOnly(due);
    rows.push({
      installment: installmentIndex + 1,
      dueAt: dueIso,
      payment: { amountMinor: payment, currency: loan.currency },
      interest: { amountMinor: interest, currency: loan.currency },
      principal: { amountMinor: principalPaid, currency: loan.currency },
      balanceAfter: { amountMinor: balance, currency: loan.currency },
    });
    if (balance <= 0) closesOn = dueIso;
  }

  return {
    outstanding: { amountMinor: startingBalance, currency: loan.currency },
    rows,
    totalInterest: { amountMinor: totalInterest, currency: loan.currency },
    totalPayment: { amountMinor: totalPayment, currency: loan.currency },
    closesOn,
    scheduleClosesOn,
    nextDueOn,
    completedInstallments,
    totalInstallments,
    remainingInstallments,
    finalBalance: { amountMinor: balance, currency: loan.currency },
    progress: totalInstallments
      ? Math.max(0, Math.min(1, completedInstallments / totalInstallments))
      : startingBalance > 0
        ? 1 - balance / startingBalance
        : 0,
  };
}

export function loanScheduleSummary(
  details: AccountLoanDetails,
  currency: string,
  asOf: string | Date = new Date(),
): LoanScheduleSummary {
  const startsOn = loanRepaymentStartsOn(details);
  const trackingStartsOn = loanForecastStartsOn(details);
  const totalInstallments = loanTotalInstallmentCount(details);
  const completedInstallments = totalInstallments
    ? Math.min(completedLoanInstallmentCount(details, asOf), totalInstallments)
    : completedLoanInstallmentCount(details, asOf);
  const remainingInstallments = totalInstallments
    ? Math.max(0, totalInstallments - completedInstallments)
    : undefined;
  return {
    startsOn,
    trackingStartsOn,
    completedInstallments,
    totalInstallments,
    remainingInstallments,
    nextDueOn: nextLoanInstallmentDueOn(details, asOf),
    closesOn: loanScheduleCloseDate(details),
    outstanding: deriveLoanOutstandingPrincipal(details, currency, {
      paidInstallments: completedInstallments,
    }),
    progress: totalInstallments
      ? Math.max(0, Math.min(1, completedInstallments / totalInstallments))
      : 0,
  };
}

export function deriveLoanOutstandingPrincipal(
  details: AccountLoanDetails,
  currency: string,
  options: DeriveLoanOutstandingPrincipalOptions = {},
): Money {
  const principalMinor = Math.abs(details.principal?.amountMinor ?? 0);
  const principalPaymentMinor = Math.max(0, details.repaymentAmount?.amountMinor ?? 0);
  const paidInstallments =
    options.paidInstallments !== undefined
      ? normalizeInstallmentCount(options.paidInstallments)
      : completedLoanInstallmentCount(details, options.asOf ?? loanForecastStartsOn(details));

  return {
    amountMinor: Math.max(0, principalMinor - principalPaymentMinor * paidInstallments),
    currency: details.principal?.currency ?? details.repaymentAmount?.currency ?? currency,
  };
}

export function completedLoanInstallmentCount(
  details: AccountLoanDetails,
  asOf: string | Date = loanForecastStartsOn(details),
): number {
  const existingPaid =
    details.paidInstallmentsBeforeTracking === undefined
      ? undefined
      : normalizeInstallmentCount(details.paidInstallmentsBeforeTracking);
  const startsOn = loanRepaymentStartsOn(details);
  const asOfDate = parseDateInput(asOf);
  if (!isValidDateOnly(startsOn) || !asOfDate) return existingPaid ?? 0;

  const frequency = details.repaymentFrequency ?? 'monthly';
  const interval = Math.max(1, details.repaymentInterval ?? 1);
  const countLimit = loanTotalInstallmentCount(details) ?? 1200;
  const scheduledCompleted = countInstallmentsBefore(
    startsOn,
    asOfDate,
    countLimit,
    frequency,
    interval,
    details.repaymentDayOfMonth,
  );
  if (existingPaid !== undefined) {
    const trackingStartsOn = loanForecastStartsOn(details);
    const trackingStartDate = parseDateOnly(trackingStartsOn);
    if (!trackingStartDate || !isValidDateOnly(trackingStartsOn)) {
      return Math.min(countLimit, Math.max(existingPaid, scheduledCompleted));
    }
    const elapsedSinceTracking = countInstallmentsBefore(
      trackingStartsOn,
      asOfDate,
      Math.max(0, countLimit - existingPaid),
      frequency,
      interval,
      details.repaymentDayOfMonth,
    );
    return Math.min(countLimit, Math.max(scheduledCompleted, existingPaid + elapsedSinceTracking));
  }

  return scheduledCompleted;
}

export function loanScheduleStartsOn(details: AccountLoanDetails): string {
  return loanRepaymentStartsOn(details);
}

export function loanRepaymentStartsOn(details: AccountLoanDetails): string {
  if (
    details.paidInstallmentsBeforeTracking !== undefined &&
    details.disbursedOn &&
    details.repaymentStartsOn &&
    details.trackingStartsOn &&
    isValidDateOnly(details.disbursedOn) &&
    isValidDateOnly(details.repaymentStartsOn) &&
    isValidDateOnly(details.trackingStartsOn) &&
    details.disbursedOn < details.repaymentStartsOn &&
    details.repaymentStartsOn >= details.trackingStartsOn
  ) {
    return details.disbursedOn;
  }

  return details.repaymentStartsOn ?? details.disbursedOn ?? details.trackingStartsOn ?? todayIso();
}

export function loanAccrualStartsOn(details: AccountLoanDetails): string {
  return details.disbursedOn ?? loanRepaymentStartsOn(details);
}

export function loanTotalInstallmentCount(details: AccountLoanDetails): number | undefined {
  return details.repaymentCount === undefined
    ? undefined
    : Math.max(1, normalizeInstallmentCount(details.repaymentCount));
}

export function loanScheduleCloseDate(details: AccountLoanDetails): string | undefined {
  const totalInstallments = loanTotalInstallmentCount(details);
  const startsOn = loanRepaymentStartsOn(details);
  if (!totalInstallments || !isValidDateOnly(startsOn)) return details.repaymentEndsOn;
  return toDateOnly(
    dueDateForInstallment(
      startsOn,
      details.repaymentFrequency ?? 'monthly',
      Math.max(1, details.repaymentInterval ?? 1),
      totalInstallments - 1,
      details.repaymentDayOfMonth,
    ),
  );
}

function completedLoanOccurrenceDates(details: AccountLoanDetails): string[] | undefined {
  const completedInstallments = completedLoanInstallmentCount(
    details,
    loanForecastStartsOn(details),
  );
  if (completedInstallments <= 0) return undefined;
  const startsOn = loanRepaymentStartsOn(details);
  if (!isValidDateOnly(startsOn)) return undefined;
  const frequency = details.repaymentFrequency ?? 'monthly';
  const interval = Math.max(1, details.repaymentInterval ?? 1);
  return Array.from({ length: completedInstallments }, (_value, index) =>
    toDateOnly(
      dueDateForInstallment(startsOn, frequency, interval, index, details.repaymentDayOfMonth),
    ),
  );
}

export function nextLoanInstallmentDueOn(
  details: AccountLoanDetails,
  asOf: string | Date = new Date(),
): string | undefined {
  const startsOn = loanRepaymentStartsOn(details);
  const asOfDate = parseDateInput(asOf);
  if (!isValidDateOnly(startsOn) || !asOfDate) return undefined;
  const totalInstallments = loanTotalInstallmentCount(details);
  const completed = totalInstallments
    ? Math.min(completedLoanInstallmentCount(details, asOfDate), totalInstallments)
    : completedLoanInstallmentCount(details, asOfDate);
  if (totalInstallments !== undefined && completed >= totalInstallments) return undefined;
  return toDateOnly(
    dueDateForInstallment(
      startsOn,
      details.repaymentFrequency ?? 'monthly',
      Math.max(1, details.repaymentInterval ?? 1),
      completed,
      details.repaymentDayOfMonth,
    ),
  );
}

function countInstallmentsBefore(
  startsOn: string,
  asOfDate: Date,
  countLimit: number,
  frequency: RecurrenceFrequency,
  interval: number,
  dayOfMonth?: number,
): number {
  const startDate = parseDateOnly(startsOn);
  if (!startDate) return 0;
  let completed = 0;
  for (let index = 0; index < countLimit; index += 1) {
    const due = dueDateForInstallment(startsOn, frequency, interval, index, dayOfMonth);
    if (due < startDate) continue;
    if (due >= asOfDate) break;
    completed += 1;
  }

  return completed;
}

export function signedLoanBalanceMinorForOutstanding(
  loan: Account,
  outstandingMinor: number,
): number {
  const normalizedOutstanding = Math.max(0, Math.round(Math.abs(outstandingMinor)));
  return loan.type === 'lent' ? normalizedOutstanding : -normalizedOutstanding;
}

export function loanOpeningBalanceMinorForOutstanding(
  state: LedgerState,
  loan: Account,
  outstanding: Money,
): number {
  const targetBalanceMinor = signedLoanBalanceMinorForOutstanding(loan, outstanding.amountMinor);
  const currentBalance = accountBalance(state, loan.id);
  return loan.openingBalance.amountMinor + targetBalanceMinor - currentBalance.amountMinor;
}

export function buildLoanPayoffProjection(
  state: LedgerState,
  input: BuildLoanPayoffProjectionInput = {},
): LoanPayoffProjection {
  const strategy = input.strategy ?? 'equal';
  const currency = state.preferences.baseCurrency;
  const requestedLoanIds = input.loanIds ? new Set(input.loanIds) : undefined;
  const loans = state.accounts
    .filter((account) => isLoanAccount(account) && !account.isArchived && account.loanDetails)
    .filter((account) => !requestedLoanIds || requestedLoanIds.has(account.id))
    .sort((left, right) => left.sortOrder - right.sortOrder || left.name.localeCompare(right.name));
  const extraMonthlyBaseMinor = Math.max(0, Math.round(input.extraMonthlyPaymentMinor ?? 0));
  const extraAllocations = allocateExtraMonthlyPayment(
    state,
    loans,
    extraMonthlyBaseMinor,
    strategy,
  );
  const plans = loans.map((loan) => {
    const details = loan.loanDetails as AccountLoanDetails;
    const currentBalance = input.currentBalances?.[loan.id] ?? accountBalance(state, loan.id);
    const normalForecast = buildLoanForecast(state, loan, details, currentBalance);
    const extraBaseMinor = extraAllocations.get(loan.id) ?? 0;
    const extraMonthlyPayment = convertMoneyForDisplay(
      state,
      { amountMinor: extraBaseMinor, currency },
      loan.currency,
    );
    const paymentMinor = Math.max(0, details.repaymentAmount?.amountMinor ?? 0);
    const acceleratedDetails: AccountLoanDetails = {
      ...details,
      repaymentAmount: {
        amountMinor: paymentMinor + extraMonthlyPayment.amountMinor,
        currency: loan.currency,
      },
    };
    const acceleratedForecast = buildLoanForecast(state, loan, acceleratedDetails, currentBalance);
    const totalInterestBase = convertMoneyForDisplay(state, normalForecast.totalInterest, currency);
    const acceleratedInterestBase = convertMoneyForDisplay(
      state,
      acceleratedForecast.totalInterest,
      currency,
    );
    const interestSavedBase = {
      amountMinor: Math.max(0, totalInterestBase.amountMinor - acceleratedInterestBase.amountMinor),
      currency,
    };
    const monthlyPayment = details.repaymentAmount ?? { amountMinor: 0, currency: loan.currency };

    return {
      account: loan,
      outstanding: normalForecast.outstanding,
      baseOutstanding: convertMoneyForDisplay(state, normalForecast.outstanding, currency),
      monthlyPayment,
      extraMonthlyPayment,
      normalForecast,
      acceleratedForecast,
      normalClosesOn: normalForecast.closesOn,
      acceleratedClosesOn: acceleratedForecast.closesOn,
      normalMonthsToClose: monthsToClose(normalForecast),
      acceleratedMonthsToClose: monthsToClose(acceleratedForecast),
      totalInterest: normalForecast.totalInterest,
      acceleratedTotalInterest: acceleratedForecast.totalInterest,
      interestSaved: convertMoneyForDisplay(state, interestSavedBase, loan.currency),
    };
  });

  const outstanding = sumBaseMoney(
    plans.map((plan) => plan.baseOutstanding),
    currency,
  );
  const monthlyPayment = sumBaseMoney(
    plans.map((plan) => convertMoneyForDisplay(state, plan.monthlyPayment, currency)),
    currency,
  );
  const totalInterest = sumBaseMoney(
    plans.map((plan) => convertMoneyForDisplay(state, plan.totalInterest, currency)),
    currency,
  );
  const acceleratedTotalInterest = sumBaseMoney(
    plans.map((plan) => convertMoneyForDisplay(state, plan.acceleratedTotalInterest, currency)),
    currency,
  );
  const normalMonthsToClose = maxDefined(plans.map((plan) => plan.normalMonthsToClose));
  const acceleratedMonthsToClose = maxDefined(plans.map((plan) => plan.acceleratedMonthsToClose));

  return {
    strategy,
    currency,
    selectedLoanIds: plans.map((plan) => plan.account.id),
    loans: plans,
    outstanding,
    monthlyPayment,
    extraMonthlyPayment: { amountMinor: extraMonthlyBaseMinor, currency },
    totalInterest,
    acceleratedTotalInterest,
    interestSaved: {
      amountMinor: Math.max(0, totalInterest.amountMinor - acceleratedTotalInterest.amountMinor),
      currency,
    },
    normalClosesOn: maxDateOnly(plans.map((plan) => plan.normalClosesOn)),
    acceleratedClosesOn: maxDateOnly(plans.map((plan) => plan.acceleratedClosesOn)),
    normalMonthsToClose,
    acceleratedMonthsToClose,
    monthsSaved:
      normalMonthsToClose !== undefined && acceleratedMonthsToClose !== undefined
        ? Math.max(0, normalMonthsToClose - acceleratedMonthsToClose)
        : undefined,
  };
}

export function loanRuleOccurrenceAmounts(
  state: LedgerState,
  rule: FutureGenerationRule,
  dueOn: string,
): LoanRuleOccurrenceAmounts | undefined {
  if (rule.type !== 'loan_repayment' && (rule.kind as string | undefined) !== 'loan_emi') {
    return undefined;
  }
  const loan = endpointLoanAccountForRule(state, rule);
  if (!loan?.loanDetails) return undefined;
  const row = buildLoanForecast(state, loan, loan.loanDetails).rows.find(
    (item) => item.dueAt === dueOn,
  );
  if (!row) return undefined;

  const principalAmountMinor = Math.max(0, row.principal.amountMinor);
  const interestAmountMinor = Math.max(0, row.interest.amountMinor);
  const result: LoanRuleOccurrenceAmounts = {
    amountMinor: row.payment.amountMinor,
    currency: row.payment.currency,
    principalAmountMinor,
    principalCurrency: row.principal.currency,
    interestAmountMinor,
    interestCurrency: row.interest.currency,
    loanAccountId: loan.id,
    loanIsLent: loan.type === 'lent',
  };
  if (row.payment.amountMinor > 0) {
    result.counterAmountMinor = row.payment.amountMinor;
    result.counterCurrency = loan.currency;
  }
  return result;
}

export function loanForecastStartsOn(details: AccountLoanDetails): string {
  return details.trackingStartsOn ?? loanRepaymentStartsOn(details);
}

function interestPeriodsForInstallment(
  details: AccountLoanDetails,
  installmentIndex: number,
  due: Date,
  frequency: RecurrenceFrequency,
  interval: number,
): number {
  if (installmentIndex > 0) return 1;

  const accrualStart = parseDateOnly(loanAccrualStartsOn(details));
  const repaymentStart = parseDateOnly(loanRepaymentStartsOn(details));
  if (!accrualStart || !repaymentStart || accrualStart >= repaymentStart) return 1;

  const elapsedDays = Math.max(0, daysBetween(accrualStart, due));
  if (elapsedDays <= 0) return 1;

  return elapsedDays / interestPeriodDays(frequency, interval);
}

function interestPeriodDays(frequency: RecurrenceFrequency, interval: number): number {
  const normalizedInterval = Math.max(1, interval || 1);
  if (frequency === 'daily') return normalizedInterval;
  if (frequency === 'weekly') return normalizedInterval * 7;
  if (frequency === 'yearly') return normalizedInterval * 365;
  return normalizedInterval * 30;
}

export function dueDateForInstallment(
  startIso: string,
  frequency: RecurrenceFrequency,
  interval: number,
  index: number,
  preferredDay?: number,
): Date {
  const start = parseDateOnly(startIso) ?? startOfDay(new Date());
  const normalizedInterval = Math.max(1, interval || 1);
  if (frequency === 'daily') {
    return addDays(start, index * normalizedInterval);
  }
  if (frequency === 'weekly') {
    return addDays(start, index * normalizedInterval * 7);
  }
  if (frequency === 'yearly') {
    return addMonthsClamped(
      start,
      index * normalizedInterval * 12,
      preferredDay ?? start.getDate(),
    );
  }
  return addMonthsClamped(start, index * normalizedInterval, preferredDay ?? start.getDate());
}

export function rateForFrequency(
  ratePercent: number,
  period: LoanInterestRatePeriod,
  frequency: RecurrenceFrequency,
  interval: number,
): number {
  const monthlyRate = period === 'monthly' ? ratePercent / 100 : ratePercent / 100 / 12;
  const perPeriod =
    frequency === 'daily'
      ? monthlyRate / 30
      : frequency === 'weekly'
        ? monthlyRate / 4.345
        : frequency === 'yearly'
          ? monthlyRate * 12
          : monthlyRate;
  return perPeriod * Math.max(1, interval || 1);
}

function endpointLoanAccountForRule(
  state: LedgerState,
  rule: FutureGenerationRule,
): Account | undefined {
  const account = state.accounts.find((item) => item.id === rule.accountId);
  const counterAccount = rule.counterAccountId
    ? state.accounts.find((item) => item.id === rule.counterAccountId)
    : undefined;
  if (isLoanAccount(counterAccount)) return counterAccount;
  if (isLoanAccount(account)) return account;
  return undefined;
}

function loanAccountIdFromRuleTags(rule: FutureGenerationRule): UUID | undefined {
  const prefix = `${LOAN_RULE_TAG_PREFIX}:`;
  return rule.tags?.find((tag) => tag.startsWith(prefix))?.slice(prefix.length);
}

function allocateExtraMonthlyPayment(
  state: LedgerState,
  loans: Account[],
  extraMonthlyBaseMinor: number,
  strategy: LoanPayoffStrategy,
): Map<UUID, number> {
  const allocations = new Map<UUID, number>();
  if (extraMonthlyBaseMinor <= 0 || loans.length === 0) return allocations;

  if (strategy === 'equal') {
    const perLoan = Math.floor(extraMonthlyBaseMinor / loans.length);
    let remainder = extraMonthlyBaseMinor - perLoan * loans.length;
    for (const loan of loans) {
      const extra = perLoan + (remainder > 0 ? 1 : 0);
      allocations.set(loan.id, extra);
      remainder -= remainder > 0 ? 1 : 0;
    }
    return allocations;
  }

  const target = [...loans].sort((left, right) => {
    if (strategy === 'avalanche') {
      const leftRate = left.loanDetails?.interestRatePercent ?? 0;
      const rightRate = right.loanDetails?.interestRatePercent ?? 0;
      return rightRate - leftRate || outstandingSort(state, right, left);
    }
    return outstandingSort(state, left, right);
  })[0];
  if (target) allocations.set(target.id, extraMonthlyBaseMinor);
  return allocations;
}

function outstandingSort(state: LedgerState, left: Account, right: Account): number {
  const currency = state.preferences.baseCurrency;
  const leftBalance = Math.abs(
    convertMoneyForDisplay(state, accountBalance(state, left.id), currency).amountMinor,
  );
  const rightBalance = Math.abs(
    convertMoneyForDisplay(state, accountBalance(state, right.id), currency).amountMinor,
  );
  return leftBalance - rightBalance;
}

function monthsToClose(forecast: LoanForecast): number | undefined {
  if (forecast.outstanding.amountMinor <= 0) return 0;
  if (!forecast.closesOn) return undefined;
  return forecast.rows.length;
}

function sumBaseMoney(values: Money[], currency: string): Money {
  return {
    amountMinor: values.reduce((sum, value) => sum + value.amountMinor, 0),
    currency,
  };
}

function maxDefined(values: Array<number | undefined>): number | undefined {
  const defined = values.filter((value): value is number => value !== undefined);
  return defined.length ? Math.max(...defined) : undefined;
}

function maxDateOnly(values: Array<string | undefined>): string | undefined {
  const defined = values.filter((value): value is string => Boolean(value));
  return defined.length ? defined.sort((left, right) => right.localeCompare(left))[0] : undefined;
}

function emptyForecast(
  balance: number,
  currency: string,
  schedule: Pick<
    LoanForecast,
    | 'completedInstallments'
    | 'totalInstallments'
    | 'remainingInstallments'
    | 'scheduleClosesOn'
    | 'nextDueOn'
  > = {
    completedInstallments: 0,
    totalInstallments: undefined,
    remainingInstallments: undefined,
    scheduleClosesOn: undefined,
    nextDueOn: undefined,
  },
): LoanForecast {
  return {
    outstanding: { amountMinor: balance, currency },
    rows: [],
    totalInterest: { amountMinor: 0, currency },
    totalPayment: { amountMinor: 0, currency },
    scheduleClosesOn: schedule.scheduleClosesOn,
    nextDueOn: schedule.nextDueOn,
    completedInstallments: schedule.completedInstallments,
    totalInstallments: schedule.totalInstallments,
    remainingInstallments: schedule.remainingInstallments,
    finalBalance: { amountMinor: balance, currency },
    progress: schedule.totalInstallments
      ? Math.max(0, Math.min(1, schedule.completedInstallments / schedule.totalInstallments))
      : 0,
  };
}

function uniqueTags(tags: string[]): string[] {
  return Array.from(new Set(tags.map((tag) => tag.trim()).filter(Boolean)));
}

function isValidDateOnly(value?: string): value is string {
  return Boolean(value && /^\d{4}-\d{2}-\d{2}$/.test(value) && parseDateOnly(value));
}

function normalizeInstallmentCount(value: number): number {
  return Math.max(0, Math.min(1200, Math.floor(Number.isFinite(value) ? value : 0)));
}

function parseDateInput(value: string | Date): Date | undefined {
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? undefined : startOfDay(value);
  }
  return parseDateOnly(value);
}

function parseDateOnly(value: string): Date | undefined {
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value);
  if (!match) return undefined;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  if (!year || !month || !day) return undefined;
  return new Date(year, month - 1, day);
}

function addDays(date: Date, days: number): Date {
  return startOfDay(new Date(date.getFullYear(), date.getMonth(), date.getDate() + days));
}

function addMonthsClamped(date: Date, months: number, dayOfMonth: number): Date {
  const next = new Date(date.getFullYear(), date.getMonth() + months, 1);
  next.setDate(Math.min(dayOfMonth, daysInMonth(next)));
  return startOfDay(next);
}

function daysInMonth(date: Date): number {
  return new Date(date.getFullYear(), date.getMonth() + 1, 0).getDate();
}

function daysBetween(left: Date, right: Date): number {
  return localDayOrdinal(right) - localDayOrdinal(left);
}

function localDayOrdinal(date: Date): number {
  return Math.floor(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) / 86400000);
}

function startOfDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function toDateOnly(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function todayIso(): string {
  return toDateOnly(new Date());
}
