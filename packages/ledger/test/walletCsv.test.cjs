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
  createAccount,
  createCaptureCandidate,
  approveCaptureCandidate,
} = require('../src/services/index.ts');
const { createFutureGenerationRule } = require('../src/rules/futureGeneration.ts');
const { seedDefaultCategories } = require('../src/seed.ts');
const { emptyState } = require('../src/store/types.ts');
const {
  analyzeWalletCsvImport,
  isWalletCsvProposalQueueable,
  provisionWalletCsvEntities,
  walletCsvProposalsToCaptureInputs,
} = require('../src/import/walletCsv.ts');

const header =
  'account;category;currency;amount;ref_currency_amount;type;payment_type;note;date;transfer;payee;labels';
const content = [
  header,
  'Cash;Transfer, withdraw;INR;32299.74;32299.74;Income;Cash;;2026-05-28T11:30:21.754Z;true;;',
  'Axis Forex Card;Transfer, withdraw;GBP;250;32299.74;Expense;Cash;;2026-05-28T11:30:21.754Z;true;;',
  'Axis Forex Card;Groceries;GBP;8.48;1095.61;Expense;Cash;Morrisons;2026-05-28T11:31:03.490Z;false;;',
  'Cash;Subscriptions;INR;499;499;Expense;UPI;Netflix;2026-01-05T09:00:00.000Z;false;Netflix;streaming',
  'Cash;Subscriptions;INR;499;499;Expense;UPI;Netflix;2026-02-05T09:00:00.000Z;false;Netflix;streaming',
  'Cash;Subscriptions;INR;499;499;Expense;UPI;Netflix;2026-03-05T09:00:00.000Z;false;Netflix;streaming',
].join('\n');

const state = emptyState('wallet-csv-test', 'INR');
const file = { fileName: 'wallet_records.csv', content };
const provision = provisionWalletCsvEntities(state, [file]);
assert.equal(provision.accountsCreated, 2);

const analysis = analyzeWalletCsvImport(state, [file]);
assert.equal(analysis.summary.transferPairs, 1);
assert.equal(analysis.summary.unpairedTransfers, 0);
assert.equal(analysis.summary.queueable, 5);
assert.equal(analysis.summary.plannedPayments, 1);

const plannedPayment = analysis.plannedPayments[0];
assert.equal(plannedPayment.name, 'Netflix');
assert.equal(plannedPayment.kind, 'expense');
assert.equal(plannedPayment.type, 'expense');
assert.equal(plannedPayment.amountMinor, 49900);
assert.equal(plannedPayment.currency, 'INR');
assert.equal(plannedPayment.frequency, 'monthly');
assert.equal(plannedPayment.interval, 1);
assert.equal(plannedPayment.dayOfMonth, 5);
assert.equal(plannedPayment.startsOn, '2026-01-05');
assert.equal(plannedPayment.lastSeenOn, '2026-03-05');
assert.equal(plannedPayment.nextDueOn, '2026-04-05');
assert.equal(plannedPayment.occurrences, 3);
assert.ok(plannedPayment.confidence >= 90);

const transferProposal = analysis.proposals.find(
  (proposal) => proposal.suggestedType === 'transfer',
);
assert.ok(transferProposal);
assert.equal(transferProposal.sourceRow.accountName, 'Axis Forex Card');
assert.equal(transferProposal.pairedRow.accountName, 'Cash');
assert.equal(transferProposal.currency, 'GBP');
assert.equal(transferProposal.amountMinor, 25000);
assert.equal(transferProposal.parsedCounterCurrency, 'INR');
assert.equal(transferProposal.parsedCounterAmountMinor, 3229974);
assert.ok(transferProposal.parsedFxRate > 129);
assert.ok(transferProposal.parsedCounterFxRate > 129);
assert.equal(isWalletCsvProposalQueueable(transferProposal), true);

const groceryProposal = analysis.proposals.find(
  (proposal) => proposal.sourceRow.categoryName === 'Groceries',
);
assert.ok(groceryProposal);
assert.equal(groceryProposal.currency, 'GBP');
assert.equal(groceryProposal.amountMinor, 848);
assert.ok(groceryProposal.parsedFxRate > 129);
assert.equal(groceryProposal.parsedOriginalAmountMinor, undefined);
assert.equal(groceryProposal.parsedOriginalCurrency, undefined);
assert.equal(isWalletCsvProposalQueueable(groceryProposal), true);

const inputs = walletCsvProposalsToCaptureInputs(
  analysis.proposals,
  '00000000-0000-0000-0000-000000000001',
);
const transferInput = inputs.find((input) => input.suggestedType === 'transfer');
assert.ok(transferInput.parsedFxRate > 129);
assert.equal(transferInput.parsedCounterCurrency, 'INR');
assert.equal(transferInput.parsedCounterAmountMinor, 3229974);
const groceryInput = inputs.find(
  (input) => input.suggestedCategoryId === groceryProposal.suggestedCategoryId,
);
assert.equal(groceryInput.parsedCurrency, 'GBP');
assert.equal(groceryInput.parsedAmountMinor, 848);
assert.ok(groceryInput.parsedFxRate > 129);

const candidate = createCaptureCandidate(state, transferInput);
const transaction = approveCaptureCandidate(state, candidate.id);
assert.equal(transaction.amount.currency, 'GBP');
assert.equal(transaction.amount.amountMinor, 25000);
assert.equal(transaction.baseAmount.currency, 'INR');
assert.equal(transaction.baseAmount.amountMinor, 3229974);
assert.equal(transaction.counterAmount.currency, 'INR');
assert.equal(transaction.counterAmount.amountMinor, 3229974);

const groceryCandidate = createCaptureCandidate(state, groceryInput);
const groceryTransaction = approveCaptureCandidate(state, groceryCandidate.id);
assert.equal(groceryTransaction.amount.currency, 'GBP');
assert.equal(groceryTransaction.amount.amountMinor, 848);
assert.equal(groceryTransaction.baseAmount.currency, 'INR');
assert.equal(groceryTransaction.baseAmount.amountMinor, 109561);
assert.equal(groceryTransaction.originalAmount, undefined);

const recurringContent = [
  header,
  'Cash;Health;INR;100;100;Expense;UPI;Gym;2026-01-10T09:00:00.000Z;false;Gym;fitness',
  'Cash;Health;INR;120;120;Expense;UPI;Gym;2026-02-10T09:00:00.000Z;false;Gym;fitness',
  'Cash;Health;INR;150;150;Expense;UPI;Gym;2026-03-10T09:00:00.000Z;false;Gym;fitness',
  'Cash;EMI;INR;2500;2500;Expense;UPI;Old EMI;2025-01-15T09:00:00.000Z;false;Old EMI;loan',
  'Cash;EMI;INR;2500;2500;Expense;UPI;Old EMI;2025-02-15T09:00:00.000Z;false;Old EMI;loan',
  'Cash;EMI;INR;2500;2500;Expense;UPI;Old EMI;2025-03-15T09:00:00.000Z;false;Old EMI;loan',
  'Cash;Software, apps, games;INR;1499;1499;Expense;Card;Annual app;2023-02-02T09:00:00.000Z;false;Annual app;software',
  'Cash;Software, apps, games;INR;1499;1499;Expense;Card;Annual app;2024-02-02T09:00:00.000Z;false;Annual app;software',
  'Cash;Software, apps, games;INR;1999;1999;Expense;Card;Annual app;2025-02-02T09:00:00.000Z;false;Annual app;software',
].join('\n');

const recurringState = emptyState('wallet-csv-recurring-test', 'INR');
const recurringFile = { fileName: 'wallet_recurring.csv', content: recurringContent };
provisionWalletCsvEntities(recurringState, [recurringFile]);
const recurringAnalysis = analyzeWalletCsvImport(recurringState, [recurringFile], {
  now: new Date('2026-05-30T00:00:00.000Z'),
});

const gymPlan = recurringAnalysis.plannedPayments.find((item) => item.name === 'Gym');
assert.ok(gymPlan);
assert.equal(gymPlan.activity, 'active');
assert.equal(gymPlan.amountMinMinor, 10000);
assert.equal(gymPlan.amountMaxMinor, 15000);
assert.equal(gymPlan.latestAmountMinor, 15000);
assert.equal(gymPlan.warnings.includes('amount changed over time'), true);

const oldEmiPlan = recurringAnalysis.plannedPayments.find((item) => item.name === 'Old EMI');
assert.ok(oldEmiPlan);
assert.equal(oldEmiPlan.activity, 'historical');

const annualPlan = recurringAnalysis.plannedPayments.find((item) => item.name === 'Annual app');
assert.ok(annualPlan);
assert.equal(annualPlan.activity, 'needs_review');
assert.equal(annualPlan.frequency, 'yearly');

const linkedRule = createFutureGenerationRule(recurringState, {
  name: gymPlan.name,
  kind: gymPlan.kind,
  type: gymPlan.type,
  accountId: gymPlan.accountId,
  categoryId: gymPlan.categoryId,
  amountMinor: gymPlan.latestAmountMinor,
  currency: gymPlan.currency,
  frequency: gymPlan.frequency,
  interval: gymPlan.interval,
  dayOfMonth: gymPlan.dayOfMonth,
  startsOn: gymPlan.nextDueOn,
});
const suppressedAnalysis = analyzeWalletCsvImport(recurringState, [recurringFile], {
  now: new Date('2026-05-30T00:00:00.000Z'),
});
const suppressedGymPlan = suppressedAnalysis.plannedPayments.find((item) => item.name === 'Gym');
assert.ok(suppressedGymPlan);
assert.equal(suppressedGymPlan.activity, 'already_created');
assert.equal(suppressedGymPlan.matchingRuleId, linkedRule.id);
const linkedInputs = walletCsvProposalsToCaptureInputs(
  recurringAnalysis.proposals,
  '00000000-0000-0000-0000-000000000002',
  {
    plannedPayments: [gymPlan],
    ruleIdsByPlannedPaymentKey: { [gymPlan.key]: linkedRule.id },
  },
);
const linkedGymInput = linkedInputs.find((input) => input.suggestedRecurringTemplateId);
assert.ok(linkedGymInput);
assert.equal(linkedGymInput.suggestedRecurringTemplateId, linkedRule.id);
const linkedCandidate = createCaptureCandidate(recurringState, linkedGymInput);
const linkedTransaction = approveCaptureCandidate(recurringState, linkedCandidate.id);
assert.equal(linkedTransaction.recurringTemplateId, linkedRule.id);

const categoryMatchState = emptyState('wallet-csv-category-match-test', 'INR');
seedDefaultCategories(categoryMatchState);
const seededCategoryCount = categoryMatchState.categories.length;
const categoryMatchContent = [
  header,
  'Cash;Gym;INR;100;100;Expense;UPI;Gym;2026-05-01T09:00:00.000Z;false;Gym;fitness',
  'Cash;Software, apps, games;INR;200;200;Expense;Card;Tool;2026-05-02T09:00:00.000Z;false;Tool;software',
  'Cash;Restaurants;INR;300;300;Expense;Card;Dinner;2026-05-03T09:00:00.000Z;false;Dinner;food',
  'Cash;Office Lunch;INR;110;110;Income;UPI;Lunch refund;2026-05-04T09:00:00.000Z;false;Lunch refund;food',
  'Cash;Business trips;INR;120;120;Expense;Card;Client visit;2026-05-05T09:00:00.000Z;false;Client;work',
  'Cash;KudumbaSree Loan;INR;130;130;Expense;UPI;Loan payment;2026-05-06T09:00:00.000Z;false;Loan;loan',
  'Cash;Lending;INR;140;140;Income;UPI;Paid back;2026-05-07T09:00:00.000Z;false;Friend;lending',
  'Cash;Splitwise;INR;150;150;Income;UPI;Splitwise settle;2026-05-08T09:00:00.000Z;false;Splitwise;shared',
  'Cash;Pets, animals;INR;160;160;Expense;Card;Pet food;2026-05-09T09:00:00.000Z;false;Pet shop;pets',
  'Cash;Missing;INR;170;170;Expense;Cash;Unknown;2026-05-10T09:00:00.000Z;false;;',
  'Cash;Jewels, accessories;INR;180;180;Expense;Card;Accessory;2026-05-11T09:00:00.000Z;false;Shop;shopping',
  'Cash;Allowance;INR;190;190;Income;UPI;Allowance;2026-05-12T09:00:00.000Z;false;Family;support',
  'Cash;Advisory;INR;200;200;Expense;Card;Consulting;2026-05-13T09:00:00.000Z;false;Advisor;work',
].join('\n');
const categoryMatchFile = { fileName: 'wallet_categories.csv', content: categoryMatchContent };
const categoryProvision = provisionWalletCsvEntities(categoryMatchState, [categoryMatchFile]);
assert.equal(categoryProvision.accountsCreated, 1);
assert.equal(categoryProvision.categoriesCreated, 0);
assert.equal(categoryMatchState.categories.length, seededCategoryCount);
const categoryMatchAnalysis = analyzeWalletCsvImport(categoryMatchState, [categoryMatchFile]);
assert.equal(categoryMatchAnalysis.summary.unknownCategories, 0);
const fitnessCategory = categoryMatchState.categories.find((item) => item.name === 'Fitness');
const softwareCategory = categoryMatchState.categories.find((item) => item.name === 'Software');
const diningCategory = categoryMatchState.categories.find((item) => item.name === 'Dining out');
const lunchCategory = categoryMatchState.categories.find((item) => item.name === 'Lunch');
const businessTravelCategory = categoryMatchState.categories.find(
  (item) => item.name === 'Business travel',
);
const emiCategory = categoryMatchState.categories.find((item) => item.name === 'EMI');
const lendingCategory = categoryMatchState.categories.find((item) => item.name === 'Lending');
const sharedCategory = categoryMatchState.categories.find(
  (item) => item.name === 'Shared expenses',
);
const petsCategory = categoryMatchState.categories.find((item) => item.name === 'Pets');
const missingCategory = categoryMatchState.categories.find(
  (item) => item.name === 'Uncategorized imports',
);
const jewelleryCategory = categoryMatchState.categories.find(
  (item) => item.name === 'Jewellery & accessories',
);
const allowanceCategory = categoryMatchState.categories.find(
  (item) => item.name === 'Family support',
);
const advisoryCategory = categoryMatchState.categories.find(
  (item) => item.name === 'Professional services',
);
assert.ok(fitnessCategory);
assert.ok(softwareCategory);
assert.ok(diningCategory);
assert.ok(lunchCategory);
assert.ok(businessTravelCategory);
assert.ok(emiCategory);
assert.ok(lendingCategory);
assert.ok(sharedCategory);
assert.ok(petsCategory);
assert.ok(missingCategory);
assert.ok(jewelleryCategory);
assert.ok(allowanceCategory);
assert.ok(advisoryCategory);
assert.equal(
  categoryMatchAnalysis.proposals.find((proposal) => proposal.sourceRow.categoryName === 'Gym')
    .suggestedCategoryId,
  fitnessCategory.id,
);
assert.equal(
  categoryMatchAnalysis.proposals.find(
    (proposal) => proposal.sourceRow.categoryName === 'Software, apps, games',
  ).suggestedCategoryId,
  softwareCategory.id,
);
assert.equal(
  categoryMatchAnalysis.proposals.find(
    (proposal) => proposal.sourceRow.categoryName === 'Restaurants',
  ).suggestedCategoryId,
  diningCategory.id,
);
assert.equal(
  categoryMatchAnalysis.proposals.find(
    (proposal) => proposal.sourceRow.categoryName === 'Office Lunch',
  ).suggestedCategoryId,
  lunchCategory.id,
);
assert.equal(
  categoryMatchAnalysis.proposals.find(
    (proposal) => proposal.sourceRow.categoryName === 'Business trips',
  ).suggestedCategoryId,
  businessTravelCategory.id,
);
assert.equal(
  categoryMatchAnalysis.proposals.find(
    (proposal) => proposal.sourceRow.categoryName === 'KudumbaSree Loan',
  ).suggestedCategoryId,
  emiCategory.id,
);
assert.equal(
  categoryMatchAnalysis.proposals.find((proposal) => proposal.sourceRow.categoryName === 'Lending')
    .suggestedCategoryId,
  lendingCategory.id,
);
assert.equal(
  categoryMatchAnalysis.proposals.find(
    (proposal) => proposal.sourceRow.categoryName === 'Splitwise',
  ).suggestedCategoryId,
  sharedCategory.id,
);
assert.equal(
  categoryMatchAnalysis.proposals.find(
    (proposal) => proposal.sourceRow.categoryName === 'Pets, animals',
  ).suggestedCategoryId,
  petsCategory.id,
);
assert.equal(
  categoryMatchAnalysis.proposals.find((proposal) => proposal.sourceRow.categoryName === 'Missing')
    .suggestedCategoryId,
  missingCategory.id,
);
assert.equal(
  categoryMatchAnalysis.proposals.find(
    (proposal) => proposal.sourceRow.categoryName === 'Jewels, accessories',
  ).suggestedCategoryId,
  jewelleryCategory.id,
);
assert.equal(
  categoryMatchAnalysis.proposals.find(
    (proposal) => proposal.sourceRow.categoryName === 'Allowance',
  ).suggestedCategoryId,
  allowanceCategory.id,
);
assert.equal(
  categoryMatchAnalysis.proposals.find((proposal) => proposal.sourceRow.categoryName === 'Advisory')
    .suggestedCategoryId,
  advisoryCategory.id,
);

const loanImportState = emptyState('wallet-csv-loan-import-test', 'INR');
const loanContent = [
  header,
  'Cash;EMI;INR;2500;2500;Expense;UPI;Car Loan EMI;2026-01-15T09:00:00.000Z;false;Car Loan;loan',
  'Cash;EMI;INR;2500;2500;Expense;UPI;Car Loan EMI;2026-02-15T09:00:00.000Z;false;Car Loan;loan',
  'Cash;EMI;INR;2500;2500;Expense;UPI;Car Loan EMI;2026-03-15T09:00:00.000Z;false;Car Loan;loan',
].join('\n');
const loanFile = { fileName: 'wallet_loans.csv', content: loanContent };
provisionWalletCsvEntities(loanImportState, [loanFile]);
const loanAnalysis = analyzeWalletCsvImport(loanImportState, [loanFile], {
  now: new Date('2026-05-30T00:00:00.000Z'),
});
const loanPlan = loanAnalysis.plannedPayments.find((item) => item.name === 'Car Loan');
assert.ok(loanPlan);
assert.equal(loanPlan.kind, 'transfer');
const cashAccount = loanImportState.accounts.find((account) => account.name === 'Cash');
assert.ok(cashAccount);
const loanAccount = createAccount(loanImportState, {
  name: 'Car Loan',
  type: 'loan',
  currency: 'INR',
  openingBalanceMinor: -15000000,
});
const loanRule = createFutureGenerationRule(loanImportState, {
  name: 'Car Loan EMI',
  kind: 'transfer',
  type: 'loan_repayment',
  accountId: cashAccount.id,
  counterAccountId: loanAccount.id,
  amountMinor: loanPlan.latestAmountMinor,
  currency: loanPlan.currency,
  frequency: loanPlan.frequency,
  interval: loanPlan.interval,
  dayOfMonth: loanPlan.dayOfMonth,
  startsOn: loanPlan.nextDueOn,
});
const loanLinkedInputs = walletCsvProposalsToCaptureInputs(
  loanAnalysis.proposals,
  '00000000-0000-0000-0000-000000000003',
  {
    plannedPayments: [loanPlan],
    ruleIdsByPlannedPaymentKey: { [loanPlan.key]: loanRule.id },
    loanAccountIdsByPlannedPaymentKey: { [loanPlan.key]: loanAccount.id },
  },
);
assert.equal(loanLinkedInputs.length, 3);
for (const input of loanLinkedInputs) {
  assert.equal(input.suggestedType, 'loan_repayment');
  assert.equal(input.suggestedAccountId, cashAccount.id);
  assert.equal(input.suggestedCounterAccountId, loanAccount.id);
  assert.equal(input.suggestedCategoryId, undefined);
  assert.equal(input.suggestedRecurringTemplateId, loanRule.id);
}
const loanCandidate = createCaptureCandidate(loanImportState, loanLinkedInputs[0]);
const loanTransaction = approveCaptureCandidate(loanImportState, loanCandidate.id);
assert.equal(loanTransaction.type, 'loan_repayment');
assert.equal(loanTransaction.counterAccountId, loanAccount.id);
assert.equal(loanTransaction.recurringTemplateId, loanRule.id);

console.log('walletCsv import tests passed');
