const Module = require('node:module');
const path = require('node:path');

const originalResolveFilename = Module._resolveFilename;
Module._resolveFilename = function resolveWorkspaceSources(request, parent, isMain, options) {
  const workspaceSource = {
    '@1wallet/domain': '../../domain/src/index.ts',
    '@1wallet/domain/money': '../../domain/src/money.ts',
    '@1wallet/domain/types': '../../domain/src/types.ts',
    '@1wallet/validation': '../../validation/src/index.ts',
  }[request];
  if (workspaceSource) return path.resolve(__dirname, workspaceSource);
  return originalResolveFilename.call(this, request, parent, isMain, options);
};

require('sucrase/register');

const assert = require('node:assert/strict');
const {
  accountBalance,
  buildLoanPayoffProjection,
  buildLoanForecast,
  buildLoanPlannedPaymentInput,
  completedLoanInstallmentCount,
  createAccount,
  createFutureGenerationRule,
  deriveLoanOutstandingPrincipal,
  dueDateForInstallment,
  emptyState,
  findLinkedLoanRule,
  forecastFutureRuleOccurrences,
  futureRuleInterestExternalRef,
  loanOpeningBalanceMinorForOutstanding,
  loanRuleOccurrenceAmounts,
  loanScheduleSummary,
  loanRuleTag,
  plannedPaymentRuleStats,
  postDueFutureRuleTransactions,
  syncLoanDetailsFromRule,
  updateAccount,
  updateFutureGenerationRule,
} = require('../src/index.ts');

const state = emptyState('loan-user', 'INR');
const bank = createAccount(state, {
  name: 'Salary Bank',
  type: 'bank',
  currency: 'INR',
  openingBalanceMinor: 5000000,
});
const loanDetails = {
  loanKind: 'personal',
  principal: { amountMinor: 10000000, currency: 'INR' },
  disbursedOn: '2026-05-05',
  interestRatePercent: 12,
  interestRatePeriod: 'annual',
  interestMethod: 'reducing_balance',
  repaymentSourceAccountId: bank.id,
  repaymentAmount: { amountMinor: 1000000, currency: 'INR' },
  repaymentStartsOn: '2026-05-05',
  repaymentFrequency: 'monthly',
  repaymentInterval: 1,
  repaymentDayOfMonth: 5,
  repaymentCount: 12,
  autoCreateScheduledRecords: true,
  trackingStartsOn: '2026-06-05',
  setupMode: 'track_from_next',
};
const loan = createAccount(state, {
  name: 'Personal Loan',
  type: 'loan',
  currency: 'INR',
  openingBalanceMinor: -9000000,
  loanDetails,
  includeInBudgets: false,
});

const ruleInput = buildLoanPlannedPaymentInput(loan, loanDetails);
assert.ok(ruleInput);
assert.equal(ruleInput.kind, 'transfer');
assert.equal(ruleInput.type, 'loan_repayment');
assert.equal(ruleInput.accountId, bank.id);
assert.equal(ruleInput.counterAccountId, loan.id);
assert.ok(ruleInput.tags.includes(loanRuleTag(loan.id)));
assert.deepEqual(ruleInput.skippedOccurrences, ['2026-05-05']);

const rule = createFutureGenerationRule(state, ruleInput);
updateAccount(state, loan.id, {
  loanDetails: { ...loanDetails, linkedPlannedPaymentRuleId: rule.id },
});

assert.equal(findLinkedLoanRule(state, loan.id)?.id, rule.id);

const forecast = buildLoanForecast(state, loan, loan.loanDetails);
assert.equal(forecast.rows[0].dueAt, '2026-06-05');
assert.equal(forecast.rows[0].payment.amountMinor, 1090000);
assert.equal(forecast.rows[0].interest.amountMinor, 90000);
assert.equal(forecast.rows[0].principal.amountMinor, 1000000);
assert.equal(forecast.rows[0].balanceAfter.amountMinor, 8000000);
assert.equal(completedLoanInstallmentCount(loanDetails, '2026-06-05'), 1);
assert.equal(
  deriveLoanOutstandingPrincipal(loanDetails, 'INR', { asOf: '2026-06-05' }).amountMinor,
  9000000,
);
assert.equal(
  deriveLoanOutstandingPrincipal(loanDetails, 'INR', { paidInstallments: 3 }).amountMinor,
  7000000,
);

assert.deepEqual(loanRuleOccurrenceAmounts(state, rule, '2026-06-05'), {
  amountMinor: 1090000,
  currency: 'INR',
  principalAmountMinor: 1000000,
  principalCurrency: 'INR',
  interestAmountMinor: 90000,
  interestCurrency: 'INR',
  loanAccountId: loan.id,
  loanIsLent: false,
  counterAmountMinor: 1000000,
  counterCurrency: 'INR',
});

const occurrences = forecastFutureRuleOccurrences(state, {
  from: new Date('2026-05-01T00:00:00.000Z'),
  to: new Date('2026-07-01T00:00:00.000Z'),
  now: new Date('2026-05-01T00:00:00.000Z'),
  ruleIds: [rule.id],
});
assert.equal(occurrences.length, 1);
assert.equal(occurrences[0].externalRef, `future-rule-v1:${rule.id}:2026-06-05`);
assert.equal(occurrences[0].type, 'loan_repayment');
assert.equal(occurrences[0].amountMinor, 1090000);
assert.equal(occurrences[0].principalAmountMinor, 1000000);
assert.equal(occurrences[0].interestAmountMinor, 90000);
assert.equal(occurrences[0].counterAmountMinor, 1000000);
assert.equal(state.transactions.length, 0);
assert.equal(accountBalance(state, bank.id).amountMinor, 5000000);
assert.equal(accountBalance(state, loan.id).amountMinor, -9000000);

assert.equal(
  postDueFutureRuleTransactions(state, {
    now: new Date('2026-06-06T00:00:00.000Z'),
    ruleIds: [rule.id],
  }),
  1,
);
const emi = state.transactions.find(
  (transaction) => transaction.externalRef === `future-rule-v1:${rule.id}:2026-06-05`,
);
assert.ok(emi);
assert.equal(emi.status, 'cleared');
assert.equal(emi.type, 'loan_repayment');
assert.equal(emi.amount.amountMinor, 1000000);
assert.equal(emi.counterAmount.amountMinor, 1000000);
const interest = state.transactions.find(
  (transaction) =>
    transaction.externalRef ===
    futureRuleInterestExternalRef(`future-rule-v1:${rule.id}:2026-06-05`),
);
assert.ok(interest);
assert.equal(interest.status, 'cleared');
assert.equal(interest.type, 'interest_out');
assert.equal(interest.accountId, bank.id);
assert.equal(interest.amount.amountMinor, 90000);
assert.equal(interest.originalTransactionId, emi.id);
assert.equal(accountBalance(state, bank.id).amountMinor, 3910000);
assert.equal(accountBalance(state, loan.id).amountMinor, -8000000);
assert.equal(plannedPaymentRuleStats(state, rule, new Date('2026-06-06T00:00:00.000Z')).posted, 1);
assert.equal(
  postDueFutureRuleTransactions(state, {
    now: new Date('2026-06-06T00:00:00.000Z'),
    ruleIds: [rule.id],
  }),
  0,
);
assert.equal(
  state.transactions.filter((transaction) => transaction.recurringTemplateId === rule.id).length,
  2,
);
const correctedLoanOpening = loanOpeningBalanceMinorForOutstanding(state, loan, {
  amountMinor: 8500000,
  currency: 'INR',
});
updateAccount(state, loan.id, { openingBalanceMinor: correctedLoanOpening });
assert.equal(accountBalance(state, loan.id).amountMinor, -8500000);

const lentState = emptyState('lent-loan-user', 'INR');
const lentBank = createAccount(lentState, {
  name: 'Receipts Bank',
  type: 'bank',
  currency: 'INR',
  openingBalanceMinor: 0,
});
const lentDetails = {
  ...loanDetails,
  repaymentSourceAccountId: lentBank.id,
};
const lentLoan = createAccount(lentState, {
  name: 'Friend Loan',
  type: 'lent',
  currency: 'INR',
  openingBalanceMinor: 9000000,
  loanDetails: lentDetails,
});
const lentRuleInput = buildLoanPlannedPaymentInput(lentLoan, lentDetails);
assert.ok(lentRuleInput);
assert.equal(lentRuleInput.accountId, lentLoan.id);
assert.equal(lentRuleInput.counterAccountId, lentBank.id);
const lentRule = createFutureGenerationRule(lentState, lentRuleInput);
assert.equal(
  postDueFutureRuleTransactions(lentState, {
    now: new Date('2026-06-06T00:00:00.000Z'),
    ruleIds: [lentRule.id],
  }),
  1,
);
const lentEmi = lentState.transactions.find(
  (transaction) => transaction.externalRef === `future-rule-v1:${lentRule.id}:2026-06-05`,
);
assert.ok(lentEmi);
assert.equal(lentEmi.amount.amountMinor, 1000000);
assert.equal(lentEmi.counterAmount.amountMinor, 1000000);
const lentInterest = lentState.transactions.find(
  (transaction) =>
    transaction.externalRef ===
    futureRuleInterestExternalRef(`future-rule-v1:${lentRule.id}:2026-06-05`),
);
assert.ok(lentInterest);
assert.equal(lentInterest.type, 'interest_in');
assert.equal(lentInterest.accountId, lentBank.id);
assert.equal(lentInterest.amount.amountMinor, 90000);
assert.equal(lentInterest.originalTransactionId, lentEmi.id);
assert.equal(accountBalance(lentState, lentLoan.id).amountMinor, 8000000);
assert.equal(accountBalance(lentState, lentBank.id).amountMinor, 1090000);
const editedLentRule = updateFutureGenerationRule(lentState, lentRule.id, {
  amountMinor: 700000,
  startsOn: '2026-07-05',
});
assert.ok(editedLentRule);
const syncedLentLoan = syncLoanDetailsFromRule(lentState, editedLentRule);
assert.equal(syncedLentLoan.id, lentLoan.id);
assert.equal(lentLoan.loanDetails.repaymentSourceAccountId, lentBank.id);
assert.equal(lentLoan.loanDetails.repaymentAmount.amountMinor, 700000);
assert.equal(lentLoan.loanDetails.trackingStartsOn, '2026-07-05');

assert.deepEqual(
  [0, 1, 2].map((index) =>
    localDateKey(dueDateForInstallment('2026-01-31', 'monthly', 1, index, 31)),
  ),
  ['2026-01-31', '2026-02-28', '2026-03-31'],
);

const educationState = emptyState('education-loan-user', 'INR');
const educationBank = createAccount(educationState, {
  name: 'Education Bank',
  type: 'bank',
  currency: 'INR',
  openingBalanceMinor: 0,
});
const educationDetails = {
  loanKind: 'education',
  principal: { amountMinor: 18000000, currency: 'INR' },
  interestRatePercent: 0,
  interestRatePeriod: 'annual',
  interestMethod: 'reducing_balance',
  repaymentSourceAccountId: educationBank.id,
  repaymentAmount: { amountMinor: 100000, currency: 'INR' },
  repaymentStartsOn: '2023-04-05',
  repaymentFrequency: 'monthly',
  repaymentInterval: 1,
  repaymentDayOfMonth: 5,
  repaymentCount: 180,
};
const educationSummary = loanScheduleSummary(educationDetails, 'INR', '2026-05-31');
assert.equal(educationSummary.completedInstallments, 38);
assert.equal(educationSummary.remainingInstallments, 142);
assert.equal(educationSummary.nextDueOn, '2026-06-05');
assert.equal(educationSummary.closesOn, '2038-03-05');
assert.equal(educationSummary.outstanding.amountMinor, 14200000);
assert.equal(educationSummary.progress, 38 / 180);

const educationTrackedDetails = {
  ...educationDetails,
  trackingStartsOn: '2026-06-05',
  paidInstallmentsBeforeTracking: 38,
};
const educationLoan = createAccount(educationState, {
  name: 'Education Loan',
  type: 'loan',
  currency: 'INR',
  openingBalanceMinor: -14200000,
  loanDetails: educationTrackedDetails,
});
const educationForecast = buildLoanForecast(educationState, educationLoan, educationTrackedDetails);
assert.equal(educationForecast.completedInstallments, 38);
assert.equal(educationForecast.remainingInstallments, 142);
assert.equal(educationForecast.rows[0].dueAt, '2026-06-05');
assert.equal(educationForecast.scheduleClosesOn, '2038-03-05');
assert.equal(educationForecast.outstanding.amountMinor, 14200000);

const partialState = emptyState('loan-partial-user', 'INR');
const partialLoan = createAccount(partialState, {
  name: 'Partial Final Loan',
  type: 'loan',
  currency: 'INR',
  openingBalanceMinor: -2500000,
  loanDetails: {
    principal: { amountMinor: 2500000, currency: 'INR' },
    repaymentAmount: { amountMinor: 1000000, currency: 'INR' },
    repaymentStartsOn: '2026-01-01',
    repaymentFrequency: 'monthly',
    repaymentInterval: 1,
    repaymentDayOfMonth: 1,
    repaymentCount: 12,
    interestRatePercent: 0,
  },
});
const partialForecast = buildLoanForecast(partialState, partialLoan, partialLoan.loanDetails);
assert.equal(partialForecast.rows.length, 3);
assert.equal(partialForecast.rows[2].principal.amountMinor, 500000);
assert.equal(partialForecast.rows[2].payment.amountMinor, 500000);
assert.equal(partialForecast.finalBalance.amountMinor, 0);

const flatState = emptyState('loan-flat-user', 'INR');
const flatLoan = createAccount(flatState, {
  name: 'Flat Interest Loan',
  type: 'loan',
  currency: 'INR',
  openingBalanceMinor: -1000000,
  loanDetails: {
    principal: { amountMinor: 1000000, currency: 'INR' },
    repaymentAmount: { amountMinor: 500000, currency: 'INR' },
    repaymentStartsOn: '2026-01-01',
    repaymentFrequency: 'monthly',
    repaymentInterval: 1,
    repaymentDayOfMonth: 1,
    repaymentCount: 12,
    interestRatePercent: 12,
    interestRatePeriod: 'annual',
    interestMethod: 'flat',
  },
});
const flatForecast = buildLoanForecast(flatState, flatLoan, flatLoan.loanDetails);
assert.equal(flatForecast.rows[0].interest.amountMinor, 10000);
assert.equal(flatForecast.rows[0].payment.amountMinor, 510000);
assert.equal(flatForecast.rows[1].interest.amountMinor, 10000);
assert.equal(flatForecast.rows[1].principal.amountMinor, 500000);

const syncState = emptyState('loan-rule-sync-user', 'INR');
const syncBank = createAccount(syncState, {
  name: 'Sync Bank',
  type: 'bank',
  currency: 'INR',
  openingBalanceMinor: 10000000,
});
const syncLoanDetails = {
  loanKind: 'vehicle',
  principal: { amountMinor: 15000000, currency: 'INR' },
  interestRatePercent: 9,
  interestRatePeriod: 'annual',
  interestMethod: 'reducing_balance',
  repaymentSourceAccountId: syncBank.id,
  repaymentAmount: { amountMinor: 1000000, currency: 'INR' },
  repaymentStartsOn: '2026-06-10',
  repaymentFrequency: 'monthly',
  repaymentInterval: 1,
  repaymentDayOfMonth: 10,
  repaymentCount: 24,
  trackingStartsOn: '2026-06-10',
  autoCreateScheduledRecords: true,
};
const syncLoan = createAccount(syncState, {
  name: 'Sync Vehicle Loan',
  type: 'loan',
  currency: 'INR',
  openingBalanceMinor: -15000000,
  loanDetails: syncLoanDetails,
});
const syncRule = createFutureGenerationRule(
  syncState,
  buildLoanPlannedPaymentInput(syncLoan, syncLoanDetails),
);
updateAccount(syncState, syncLoan.id, {
  loanDetails: { ...syncLoanDetails, linkedPlannedPaymentRuleId: syncRule.id },
});
const editedSyncRule = updateFutureGenerationRule(syncState, syncRule.id, {
  amountMinor: 1250000,
  frequency: 'monthly',
  interval: 2,
  dayOfMonth: 12,
  startsOn: '2026-07-12',
  occurrences: 18,
  endsOn: '2029-05-12',
  enabled: false,
  notes: 'Edited from planned payments',
});
assert.ok(editedSyncRule);
const syncedLoan = syncLoanDetailsFromRule(syncState, editedSyncRule);
assert.equal(syncedLoan.id, syncLoan.id);
assert.equal(syncLoan.loanDetails.repaymentAmount.amountMinor, 1250000);
assert.equal(syncLoan.loanDetails.repaymentSourceAccountId, syncBank.id);
assert.equal(syncLoan.loanDetails.repaymentInterval, 2);
assert.equal(syncLoan.loanDetails.repaymentDayOfMonth, 12);
assert.equal(syncLoan.loanDetails.trackingStartsOn, '2026-07-12');
assert.equal(syncLoan.loanDetails.repaymentCount, 18);
assert.equal(syncLoan.loanDetails.repaymentEndsOn, '2029-05-12');
assert.equal(syncLoan.loanDetails.autoCreateScheduledRecords, false);
assert.equal(syncLoan.loanDetails.linkedPlannedPaymentRuleId, syncRule.id);
assert.equal(syncLoan.loanDetails.notes, 'Edited from planned payments');
assert.equal(editedSyncRule.tags.includes(loanRuleTag(syncLoan.id)), true);

const payoffState = emptyState('loan-payoff-user', 'INR');
const payoffBank = createAccount(payoffState, {
  name: 'Payoff Bank',
  type: 'bank',
  currency: 'INR',
  openingBalanceMinor: 10000000,
});
const highRateLoan = createAccount(payoffState, {
  name: 'High Rate Loan',
  type: 'loan',
  currency: 'INR',
  openingBalanceMinor: -10000000,
  loanDetails: {
    loanKind: 'personal',
    principal: { amountMinor: 10000000, currency: 'INR' },
    interestRatePercent: 12,
    interestRatePeriod: 'annual',
    interestMethod: 'reducing_balance',
    repaymentSourceAccountId: payoffBank.id,
    repaymentAmount: { amountMinor: 1000000, currency: 'INR' },
    repaymentStartsOn: '2026-06-05',
    repaymentFrequency: 'monthly',
    repaymentInterval: 1,
    repaymentDayOfMonth: 5,
    repaymentCount: 24,
  },
});
const lowRateLoan = createAccount(payoffState, {
  name: 'Low Rate Loan',
  type: 'loan',
  currency: 'INR',
  openingBalanceMinor: -5000000,
  loanDetails: {
    loanKind: 'vehicle',
    principal: { amountMinor: 5000000, currency: 'INR' },
    interestRatePercent: 6,
    interestRatePeriod: 'annual',
    interestMethod: 'reducing_balance',
    repaymentSourceAccountId: payoffBank.id,
    repaymentAmount: { amountMinor: 500000, currency: 'INR' },
    repaymentStartsOn: '2026-06-10',
    repaymentFrequency: 'monthly',
    repaymentInterval: 1,
    repaymentDayOfMonth: 10,
    repaymentCount: 24,
  },
});

const equalProjection = buildLoanPayoffProjection(payoffState, {
  extraMonthlyPaymentMinor: 300000,
  strategy: 'equal',
});
assert.equal(equalProjection.loans.length, 2);
assert.equal(equalProjection.selectedLoanIds.length, 2);
assert.equal(equalProjection.extraMonthlyPayment.amountMinor, 300000);
assert.ok(equalProjection.interestSaved.amountMinor > 0);
assert.ok(equalProjection.acceleratedMonthsToClose < equalProjection.normalMonthsToClose);
assert.equal(equalProjection.loans[0].extraMonthlyPayment.amountMinor, 150000);
assert.equal(equalProjection.loans[1].extraMonthlyPayment.amountMinor, 150000);

const avalancheProjection = buildLoanPayoffProjection(payoffState, {
  extraMonthlyPaymentMinor: 300000,
  strategy: 'avalanche',
});
assert.equal(
  avalancheProjection.loans.find((plan) => plan.account.id === highRateLoan.id).extraMonthlyPayment
    .amountMinor,
  300000,
);
assert.equal(
  avalancheProjection.loans.find((plan) => plan.account.id === lowRateLoan.id).extraMonthlyPayment
    .amountMinor,
  0,
);

const selectedProjection = buildLoanPayoffProjection(payoffState, {
  loanIds: [lowRateLoan.id],
  extraMonthlyPaymentMinor: 100000,
});
assert.deepEqual(selectedProjection.selectedLoanIds, [lowRateLoan.id]);
assert.equal(selectedProjection.loans[0].extraMonthlyPayment.amountMinor, 100000);

const stuckState = emptyState('loan-stuck-user', 'INR');
const stuckBank = createAccount(stuckState, {
  name: 'Stuck Bank',
  type: 'bank',
  currency: 'INR',
  openingBalanceMinor: 1000000,
});
createAccount(stuckState, {
  name: 'Too Low EMI Loan',
  type: 'loan',
  currency: 'INR',
  openingBalanceMinor: -10000000,
  loanDetails: {
    loanKind: 'personal',
    principal: { amountMinor: 10000000, currency: 'INR' },
    interestRatePercent: 120,
    interestRatePeriod: 'annual',
    interestMethod: 'reducing_balance',
    repaymentSourceAccountId: stuckBank.id,
    repaymentAmount: { amountMinor: 10000, currency: 'INR' },
    repaymentStartsOn: '2026-06-05',
    repaymentFrequency: 'monthly',
    repaymentInterval: 1,
    repaymentDayOfMonth: 5,
    repaymentCount: 12,
  },
});
const stuckProjection = buildLoanPayoffProjection(stuckState);
assert.equal(stuckProjection.normalMonthsToClose, undefined);
assert.equal(stuckProjection.acceleratedMonthsToClose, undefined);

console.log('loan EMI fixtures passed');

function localDateKey(value) {
  const date = new Date(value);
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${date.getFullYear()}-${month}-${day}`;
}
