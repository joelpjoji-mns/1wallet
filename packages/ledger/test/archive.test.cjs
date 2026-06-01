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
  exportOneWalletArchive,
  ledgerStateFromOneWalletArchive,
  parseOneWalletArchive,
  validateOneWalletArchive,
} = require('../src/archive/onewalletArchive.ts');
const { createFutureGenerationRule } = require('../src/rules/futureGeneration.ts');
const {
  createAccount,
  approveCaptureCandidate,
  createCategory,
  createCaptureCandidate,
  createImportBatch,
  createTransaction,
  setRate,
  updateAccount,
  accountBalance,
} = require('../src/services/index.ts');
const { emptyState } = require('../src/store/types.ts');

const state = emptyState('archive-test-user', 'INR');
state.preferences.displayCurrency = 'INR';
state.preferences.enabledCurrencies = ['INR', 'GBP', 'USD'];
state.preferences.homeWidgets = {
  order: ['accounts', 'planned-payments', 'cash-flow', 'currency-rates'],
  hidden: [],
  sizes: { accounts: 'wide', 'planned-payments': 'medium', 'cash-flow': 'medium' },
  filters: { 'cash-flow': 'thisMonth' },
};
setRate(state, 'GBP', 'INR', 106.5, '2026-05-30', {
  provider: 'test-fx',
  source: 'manual',
  updatedAt: '2026-05-30T08:00:00.000Z',
});

const cash = createAccount(state, {
  name: 'Cash',
  type: 'cash',
  currency: 'INR',
  openingBalanceMinor: 50000,
  openingDate: '2025-01-01',
});
const bank = createAccount(state, {
  name: 'Union Bank',
  type: 'bank',
  currency: 'INR',
  openingBalanceMinor: 200000,
  openingDate: '2025-01-01',
});
const forex = createAccount(state, {
  name: 'Axis Forex Card',
  type: 'prepaid',
  currency: 'GBP',
  openingBalanceMinor: 125000,
  openingDate: '2025-01-01',
});
const loan = createAccount(state, {
  name: 'Education Loan',
  type: 'loan',
  currency: 'INR',
  openingBalanceMinor: -5000000,
  openingDate: '2024-01-01',
  includeInBudgets: false,
  loanDetails: {
    loanKind: 'education',
    principal: { amountMinor: 5000000, currency: 'INR' },
    disbursedOn: '2024-01-01',
    interestRatePercent: 9.2,
    interestRatePeriod: 'annual',
    interestMethod: 'reducing_balance',
    repaymentSourceAccountId: bank.id,
    repaymentAmount: { amountMinor: 421000, currency: 'INR' },
    repaymentStartsOn: '2026-04-05',
    repaymentFrequency: 'monthly',
    repaymentInterval: 1,
    repaymentDayOfMonth: 5,
    repaymentCount: 180,
    trackingStartsOn: '2026-04-05',
    paidInstallmentsBeforeTracking: 2,
    setupMode: 'backfill_paid',
  },
});
const expectedAccountOrder = ['Cash', 'Union Bank', 'Axis Forex Card', 'Education Loan'];
[cash, bank, forex, loan].forEach((account, index) => {
  updateAccount(state, account.id, { sortOrder: index + 1 });
});

const rentCategory = createCategory(state, {
  name: 'Rent',
  kind: 'expense',
  icon: 'home-outline',
});
const gymCategory = createCategory(state, {
  name: 'Gym',
  kind: 'expense',
  icon: 'dumbbell',
});
const salaryCategory = createCategory(state, {
  name: 'Salary',
  kind: 'income',
  icon: 'briefcase-outline',
});
const travelCategory = createCategory(state, {
  name: 'Travel',
  kind: 'expense',
  icon: 'airplane',
});
const loanCategory = createCategory(state, {
  name: 'Loan EMI',
  kind: 'expense',
  icon: 'bank-transfer-out',
});

const gymRule = createFutureGenerationRule(state, {
  name: 'Gym',
  kind: 'expense',
  type: 'expense',
  accountId: bank.id,
  categoryId: gymCategory.id,
  amountMinor: 150000,
  currency: 'INR',
  frequency: 'monthly',
  interval: 1,
  dayOfMonth: 12,
  startsOn: '2026-05-12',
  paymentMethod: 'UPI autopay',
});
const loanRule = createFutureGenerationRule(state, {
  name: 'Education Loan EMI',
  kind: 'transfer',
  type: 'loan_repayment',
  accountId: bank.id,
  counterAccountId: loan.id,
  categoryId: loanCategory.id,
  amountMinor: 421000,
  currency: 'INR',
  frequency: 'monthly',
  interval: 1,
  dayOfMonth: 5,
  startsOn: '2026-04-05',
  occurrences: 180,
  paymentMethod: 'Auto debit',
  tags: [`loan-rule-v1:${loan.id}`, 'loan_emi'],
});
updateAccount(state, loan.id, {
  loanDetails: { ...loan.loanDetails, linkedPlannedPaymentRuleId: loanRule.id },
});

createTransaction(state, {
  type: 'income',
  accountId: bank.id,
  categoryId: salaryCategory.id,
  amountMinor: 12000000,
  currency: 'INR',
  occurredAt: '2026-05-01T08:00:00.000Z',
  source: 'manual',
  notes: 'May salary',
});
const gymPayment = createTransaction(state, {
  type: 'expense',
  accountId: bank.id,
  categoryId: gymCategory.id,
  amountMinor: 150000,
  currency: 'INR',
  occurredAt: '2026-05-12T08:00:00.000Z',
  source: 'recurring',
  recurringTemplateId: gymRule.id,
  notes: 'Confirmed gym planned payment',
});
createTransaction(state, {
  type: 'expense',
  accountId: bank.id,
  categoryId: rentCategory.id,
  amountMinor: 25000,
  currency: 'INR',
  occurredAt: '2026-05-01T08:00:00.000Z',
  source: 'manual',
  notes: 'May rent',
});
createTransaction(state, {
  type: 'expense',
  accountId: forex.id,
  categoryId: travelCategory.id,
  amountMinor: 3000,
  currency: 'GBP',
  fxRate: 106.5,
  occurredAt: '2026-05-14T18:00:00.000Z',
  source: 'manual',
  notes: 'London transit top-up',
});
const firstLoanPayment = createTransaction(state, {
  type: 'loan_repayment',
  accountId: bank.id,
  counterAccountId: loan.id,
  amountMinor: 421000,
  currency: 'INR',
  occurredAt: '2026-04-05T08:00:00.000Z',
  source: 'recurring',
  recurringTemplateId: loanRule.id,
  notes: 'Loan EMI paid before import',
});
const importBatch = createImportBatch(state, {
  source: 'wallet_csv',
  status: 'posted',
  name: 'Wallet CSV with loan records',
  fileNames: ['wallet-loan-history.csv'],
  rowCount: 1,
  candidateCount: 1,
  warningCount: 0,
});
const loanCandidate = createCaptureCandidate(state, {
  source: 'import',
  rawHash: 'wallet-csv-loan-emi-2026-05',
  rawPayload: { row: 42, account: 'Union Bank', description: 'Education Loan EMI' },
  parsedAmountMinor: 421000,
  parsedCurrency: 'INR',
  parsedOccurredAt: '2026-05-05T08:00:00.000Z',
  parsedNotes: 'Imported May EMI',
  suggestedAccountId: bank.id,
  suggestedCounterAccountId: loan.id,
  suggestedCategoryId: loanCategory.id,
  suggestedType: 'loan_repayment',
  suggestedRecurringTemplateId: loanRule.id,
  importBatchId: importBatch.id,
  confidence: 0.97,
  externalRef: 'wallet-csv:loan-emi:2026-05',
});
const importedLoanPayment = approveCaptureCandidate(state, loanCandidate.id);
state.goals.push({
  id: 'goal-pay-off-education-loan',
  userId: state.userId,
  name: 'Close education loan early',
  kind: 'pay_off',
  targetAmount: { amountMinor: 5000000, currency: 'INR' },
  priority: 'high',
  linkedCategoryId: loanCategory.id,
  isPaused: false,
  isCompleted: false,
});

const archive = exportOneWalletArchive(state, {
  exportedAt: '2026-05-30T12:00:00.000Z',
  source: 'test',
});
assert.equal(archive.format, 'onewallet.ledger.archive');
assert.equal(archive.summary.accounts, 4);
assert.equal(archive.summary.transactions, 6);
assert.equal(archive.summary.captureCandidates, 1);
assert.equal(archive.summary.importBatches, 1);
assert.equal(archive.summary.plannedPayments, 2);
assert.equal(archive.summary.loanAccounts, 1);
assert.deepEqual(archive.summary.currencies, ['GBP', 'INR', 'USD']);
assert.deepEqual(archive.summary.dateRange, { start: '2026-04-05', end: '2026-05-14' });

const parsed = parseOneWalletArchive(JSON.stringify(archive));
const validation = validateOneWalletArchive(parsed);
assert.equal(validation.ok, true);
assert.deepEqual(validation.errors, []);

const restored = ledgerStateFromOneWalletArchive(parsed);
assert.equal(restored.accounts.length, state.accounts.length);
assert.equal(restored.transactions.length, state.transactions.length);
assert.deepEqual(
  restored.accounts
    .slice()
    .sort((left, right) => left.sortOrder - right.sortOrder)
    .map((account) => account.name),
  expectedAccountOrder,
);
assert.equal(restored.preferences.displayCurrency, 'INR');
assert.deepEqual(restored.preferences.enabledCurrencies, ['INR', 'GBP', 'USD']);
assert.equal(restored.preferences.futureGenerationRules?.length, 2);
assert.equal(
  restored.preferences.futureGenerationRules?.find((rule) => rule.name === 'Gym')?.id,
  gymRule.id,
);
assert.equal(
  restored.preferences.futureGenerationRules?.find((rule) => rule.name === 'Education Loan EMI')
    ?.id,
  loanRule.id,
);
assert.equal(
  restored.accounts.find((account) => account.id === loan.id)?.loanDetails
    ?.linkedPlannedPaymentRuleId,
  loanRule.id,
);
assert.equal(
  restored.accounts.find((account) => account.id === loan.id)?.loanDetails
    ?.paidInstallmentsBeforeTracking,
  2,
);
assert.equal(
  restored.transactions.find((transaction) => transaction.id === gymPayment.id)
    ?.recurringTemplateId,
  gymRule.id,
);
assert.equal(
  restored.transactions.find((transaction) => transaction.id === firstLoanPayment.id)
    ?.recurringTemplateId,
  loanRule.id,
);
assert.equal(
  restored.transactions.find((transaction) => transaction.id === importedLoanPayment.id)
    ?.recurringTemplateId,
  loanRule.id,
);
assert.equal(
  restored.captureCandidates.find((candidate) => candidate.id === loanCandidate.id)
    ?.postedTransactionId,
  importedLoanPayment.id,
);
assert.equal(
  restored.captureCandidates.find((candidate) => candidate.id === loanCandidate.id)
    ?.suggestedRecurringTemplateId,
  loanRule.id,
);
assert.equal(
  restored.importBatches.find((batch) => batch.id === importBatch.id)?.candidateCount,
  1,
);
assert.equal(restored.exchangeRates[0]?.base, 'GBP');
assert.equal(restored.exchangeRates[0]?.quote, 'INR');
assert.equal(
  accountBalance(restored, bank.id).amountMinor,
  accountBalance(state, bank.id).amountMinor,
);
assert.equal(
  accountBalance(restored, loan.id).amountMinor,
  accountBalance(state, loan.id).amountMinor,
);

const brokenArchive = JSON.parse(JSON.stringify(archive));
brokenArchive.ledger.transactions[0].accountId = 'missing-account';
const brokenValidation = validateOneWalletArchive(brokenArchive);
assert.equal(brokenValidation.ok, false);
assert.ok(brokenValidation.errors.some((error) => error.includes('missing account')));
assert.throws(() => ledgerStateFromOneWalletArchive(brokenArchive), /cannot be restored/i);

const brokenCandidateArchive = JSON.parse(JSON.stringify(archive));
brokenCandidateArchive.ledger.captureCandidates[0].suggestedAccountId = 'missing-account';
const brokenCandidateValidation = validateOneWalletArchive(brokenCandidateArchive);
assert.equal(brokenCandidateValidation.ok, false);
assert.ok(brokenCandidateValidation.errors.some((error) => error.includes('missing account')));

const missingChecksumArchive = JSON.parse(JSON.stringify(archive));
delete missingChecksumArchive.checksum;
const missingChecksumValidation = validateOneWalletArchive(missingChecksumArchive);
assert.equal(missingChecksumValidation.ok, false);
assert.ok(missingChecksumValidation.errors.some((error) => error.includes('checksum is missing')));

const mismatchedChecksumArchive = JSON.parse(JSON.stringify(archive));
mismatchedChecksumArchive.ledger.accounts[0].name = 'Tampered account';
const mismatchedChecksumValidation = validateOneWalletArchive(mismatchedChecksumArchive);
assert.equal(mismatchedChecksumValidation.ok, false);
assert.ok(
  mismatchedChecksumValidation.errors.some((error) => error.includes('checksum does not match')),
);

const newerVersionArchive = JSON.parse(JSON.stringify(archive));
newerVersionArchive.ledgerStateVersion = 9999;
const newerVersionValidation = validateOneWalletArchive(newerVersionArchive);
assert.equal(newerVersionValidation.ok, false);
assert.ok(newerVersionValidation.errors.some((error) => error.includes('newer 1wallet version')));

assert.throws(() => parseOneWalletArchive('{not json'), /not valid JSON/);
assert.throws(
  () => parseOneWalletArchive(JSON.stringify({ format: 'other', archiveVersion: 1 })),
  /not a 1wallet backup/i,
);

console.log('onewallet archive fixtures passed');
