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
  buildAccountMatchIdentifiers,
  buildAccountMessageSourceHints,
  accountBalance,
  convertMoneyForDisplay,
  createAccount,
  createFutureGenerationRule,
  createMessageCategoryRule,
  createTransaction,
  cycleDisplayCurrency,
  displayCurrency,
  emptyState,
  exchangeRateIsStale,
  exchangeRatePairIsStale,
  forecastFutureRuleOccurrences,
  futureRuleOccurrenceDates,
  generateFutureTransactionsFromRecurringSchedules,
  generateFutureTransactionsFromRules,
  KVStore,
  LEDGER_STATE_VERSION,
  mergeAcceptedMessageAccountHints,
  messageHintSuggestionsForAccount,
  messageHintSuggestionsFromCapturePayload,
  parseTransactionMessage,
  processTransactionMessageCapture,
  shouldProcessTransactionMessage,
  plannedPaymentKindForRule,
  plannedPaymentPostModeForRule,
  plannedPaymentRuleStats,
  postedAmountFromOriginal,
  postDueFutureRuleTransactions,
  projectedBalanceForAccountsThroughDate,
  seedDefaultCategories,
  setDisplayCurrency,
  setRate,
  rateRecordForPair,
  skipFutureRuleOccurrence,
  totalBalance,
  totalBalanceForAccounts,
} = require('../src/index.ts');

const state = emptyState('test-user', 'INR');
seedDefaultCategories(state);

const hdfcCard = createAccount(state, {
  name: 'HDFC MoneyBack Credit Card',
  type: 'credit_card',
  currency: 'INR',
  openingBalanceMinor: 0,
  institution: 'HDFC Bank',
  matchIdentifiers: buildAccountMatchIdentifiers({ accountType: 'credit_card', lastFour: '1234' }),
  messageSourceHints: buildAccountMessageSourceHints({ smsSenderIds: ['HDFCBK'] }),
});

const monzoCard = createAccount(state, {
  name: 'Monzo Flex',
  type: 'debit_card',
  currency: 'GBP',
  openingBalanceMinor: 0,
  institution: 'Monzo',
  matchIdentifiers: buildAccountMatchIdentifiers({ accountType: 'debit_card', lastFour: '9876' }),
  messageSourceHints: buildAccountMessageSourceHints({ emailDomains: ['monzo.com'] }),
});

const hdfcBank = createAccount(state, {
  name: 'HDFC Salary Account',
  type: 'bank',
  currency: 'INR',
  openingBalanceMinor: 0,
  institution: 'HDFC Bank',
  matchIdentifiers: buildAccountMatchIdentifiers({ accountType: 'bank', lastFour: '5555' }),
  messageSourceHints: buildAccountMessageSourceHints({ smsSenderIds: ['HDFCBK'] }),
});

const indiaDebit = parseTransactionMessage(state, {
  source: 'sms',
  sender: 'HDFCBK',
  receivedAt: '2026-05-25T09:00:00.000Z',
  body: 'Rs. 1,234.50 debited from HDFC Bank Credit Card XX1234 at SWIGGY on 25-May-26 UPI Ref 123456789012. Avl bal Rs. 5,000.00',
});

const foodDeliveryCategory = state.categories.find((category) => category.name === 'Food delivery');
assert.ok(foodDeliveryCategory);

assert.equal(indiaDebit.recognized, true);
assert.equal(indiaDebit.amountMinor, 123450);
assert.equal(indiaDebit.currency, 'INR');
assert.equal(indiaDebit.suggestedType, 'expense');
assert.equal(indiaDebit.merchant, 'SWIGGY');
assert.equal(indiaDebit.categoryMatch.categoryId, foodDeliveryCategory.id);
assert.equal(indiaDebit.candidateInput.suggestedCategoryId, foodDeliveryCategory.id);
assert.equal(indiaDebit.match.accountId, hdfcCard.id);
assert.equal(indiaDebit.reference, '123456789012');

const ukSpend = parseTransactionMessage(state, {
  source: 'email',
  sender: 'alerts@monzo.com',
  subject: 'Card transaction',
  receivedAt: '2026-05-25T10:30:00.000Z',
  body: 'You spent \u00A312.34 at TESCO on card ending 9876 on 25/05/2026. Ref ABCD1234.',
});

assert.equal(ukSpend.recognized, true);
assert.equal(ukSpend.amountMinor, 1234);
assert.equal(ukSpend.currency, 'GBP');
assert.equal(ukSpend.suggestedType, 'expense');
assert.equal(ukSpend.merchant, 'TESCO');
assert.equal(ukSpend.categoryMatch.categoryName, 'Groceries');
assert.equal(ukSpend.match.accountId, monzoCard.id);
assert.equal(ukSpend.reference, 'ABCD1234');

const tuitionCategory = state.categories.find((category) => category.name === 'Tuition');
assert.ok(tuitionCategory);
createMessageCategoryRule(state, {
  name: 'School fee alerts',
  keywords: ['Bright Kids School'],
  categoryId: tuitionCategory.id,
});
const customCategorySpend = parseTransactionMessage(state, {
  source: 'sms',
  sender: 'HDFCBK',
  receivedAt: '2026-05-25T10:45:00.000Z',
  body: 'INR 3,000.00 debited from HDFC account ending 5555 at BRIGHT KIDS SCHOOL on 25-May-26. Txn SCH998877.',
});
assert.equal(customCategorySpend.recognized, true);
assert.equal(customCategorySpend.categoryMatch.categoryId, tuitionCategory.id);
assert.ok(customCategorySpend.categoryMatch.matchedBy.includes('custom:Bright Kids School'));

tuitionCategory.isArchived = true;
const archivedCustomCategorySpend = parseTransactionMessage(state, {
  source: 'sms',
  sender: 'HDFCBK',
  receivedAt: '2026-05-25T10:46:00.000Z',
  body: 'INR 3,100.00 debited from HDFC account ending 5555 at BRIGHT KIDS SCHOOL UNIQUE EDGE on 25-May-26. Txn SCH998878.',
});
assert.equal(archivedCustomCategorySpend.recognized, true);
assert.equal(archivedCustomCategorySpend.categoryMatch.categoryId, undefined);
assert.ok(archivedCustomCategorySpend.warnings.includes('category needs review'));
tuitionCategory.isArchived = false;

const uncategorizedSpend = parseTransactionMessage(state, {
  source: 'sms',
  sender: 'HDFCBK',
  receivedAt: '2026-05-25T10:50:00.000Z',
  body: 'INR 90.00 debited from HDFC account ending 5555 at MYSTERY STALL on 25-May-26. Txn MYS998877.',
});
assert.equal(uncategorizedSpend.recognized, true);
assert.equal(uncategorizedSpend.categoryMatch.categoryId, undefined);
assert.ok(uncategorizedSpend.warnings.includes('category needs review'));

const foodParentCategory = state.categories.find((category) => category.name === 'Food & dining');
assert.ok(foodParentCategory);
const genericFoodSpend = parseTransactionMessage(state, {
  source: 'sms',
  sender: 'HDFCBK',
  receivedAt: '2026-05-25T10:52:00.000Z',
  body: 'INR 320.00 debited from HDFC account ending 5555 at FRESH FOODS on 25-May-26. Txn FOOD998877.',
});
assert.equal(genericFoodSpend.recognized, true);
assert.equal(genericFoodSpend.categoryMatch.categoryId, foodParentCategory.id);
assert.ok(genericFoodSpend.categoryMatch.matchedBy.includes('fallback:foods'));

const grocerySpend = parseTransactionMessage(state, {
  source: 'sms',
  sender: 'HDFCBK',
  receivedAt: '2026-05-25T10:53:00.000Z',
  body: 'INR 740.00 debited from HDFC account ending 5555 at NEIGHBORHOOD GROCERY on 25-May-26. Txn GRO998877.',
});
assert.equal(grocerySpend.categoryMatch.categoryName, 'Groceries');
assert.ok(grocerySpend.categoryMatch.matchedBy.includes('default:grocery'));

const diningSpend = parseTransactionMessage(state, {
  source: 'sms',
  sender: 'HDFCBK',
  receivedAt: '2026-05-25T10:54:00.000Z',
  body: 'INR 420.00 debited from HDFC account ending 5555 at CORNER CAFE on 25-May-26. Txn CAF998877.',
});
assert.equal(diningSpend.categoryMatch.categoryName, 'Dining out');

const deliveryPhraseSpend = parseTransactionMessage(state, {
  source: 'sms',
  sender: 'HDFCBK',
  receivedAt: '2026-05-25T10:55:00.000Z',
  body: 'INR 510.00 debited from HDFC account ending 5555 at FAST FOOD DELIVERY on 25-May-26. Txn DEL998877.',
});
assert.equal(deliveryPhraseSpend.categoryMatch.categoryName, 'Food delivery');

const lastFourEdgeCases = [
  {
    label: 'A/c XX format',
    body: 'INR 500 debited from A/c XX1234 at STORE on 25-May-26. Txn EDGE123401.',
    kind: 'account_last4',
    value: '1234',
  },
  {
    label: 'acct no ending',
    body: 'INR 500 debited from acct no ending 5678 at STORE on 25-May-26. Txn EDGE567801.',
    kind: 'account_last4',
    value: '5678',
  },
  {
    label: 'card no masked',
    body: 'GBP 50.00 charged to card no. XXXX7890 at TESCO on 25-May-26. Txn EDGE789001.',
    kind: 'card_last4',
    value: '7890',
  },
  {
    label: 'account number',
    body: 'INR 100 debited from account number 2345 at STORE on 25-May-26. Txn EDGE234501.',
    kind: 'account_last4',
    value: '2345',
  },
  {
    label: 'UK card ending',
    body: 'You spent GBP 19.99 at TESCO on card ending 4321 on 25/05/2026. Ref EDGE432101.',
    kind: 'card_last4',
    value: '4321',
  },
];
for (const item of lastFourEdgeCases) {
  const result = parseTransactionMessage(state, {
    source: 'sms',
    sender: 'BANK',
    receivedAt: '2026-05-25T10:56:00.000Z',
    body: item.body,
  });
  assert.ok(
    result.fragments.some(
      (fragment) => fragment.kind === item.kind && fragment.value === item.value,
    ),
    `Expected ${item.label} to extract ${item.kind}:${item.value}`,
  );
}

const fullAccountNumber = parseTransactionMessage(state, {
  source: 'sms',
  sender: 'BANK',
  body: 'Your account 12345678901234 full display is available in netbanking.',
});
assert.equal(
  fullAccountNumber.fragments.some((fragment) => fragment.value === '3456'),
  false,
);
assert.equal(
  fullAccountNumber.fragments.some((fragment) => fragment.value === '1234'),
  false,
);

const usdSpend = parseTransactionMessage(state, {
  source: 'sms',
  sender: 'HDFCBK',
  receivedAt: '2026-05-25T11:00:00.000Z',
  body: 'USD 12.34 debited from HDFC Bank Credit Card XX1234 at AMAZON on 25-May-26. Txn USD998877.',
});

assert.equal(usdSpend.recognized, true);
assert.equal(usdSpend.amountMinor, 1234);
assert.equal(usdSpend.currency, 'USD');
assert.equal(usdSpend.suggestedType, 'expense');

const rupeeTrigger = shouldProcessTransactionMessage({
  source: 'sms',
  sender: 'HDFCBK',
  body: '₹500 debited from card ending 1234 at CAFE.',
});
assert.equal(rupeeTrigger.matched, true);
assert.ok(rupeeTrigger.matchedKeywords.includes('₹'));

const ignoredSenderTrigger = shouldProcessTransactionMessage(
  {
    source: 'sms',
    sender: 'VM-PROMO',
    body: 'INR 99 debited at promo store.',
  },
  { ignoredSenderIds: ['VM-PROMO'] },
);
assert.equal(ignoredSenderTrigger.matched, false);
assert.equal(ignoredSenderTrigger.ignoredReason, 'ignored_sender');

const emiDebit = parseTransactionMessage(state, {
  source: 'sms',
  sender: 'HDFCBK',
  receivedAt: '2026-05-25T08:00:00.000Z',
  body: 'Auto debit of INR 28,500.00 from HDFC account ending 5555 towards HDFC Home Loan EMI on 25-May-26. Txn EMI998877.',
});

assert.equal(emiDebit.recognized, true);
assert.equal(emiDebit.amountMinor, 2850000);
assert.equal(emiDebit.currency, 'INR');
assert.equal(emiDebit.suggestedType, 'loan_repayment');
assert.equal(emiDebit.paymentMethod, 'Auto debit');
assert.equal(emiDebit.match.accountId, hdfcBank.id);
assert.equal(emiDebit.reference, 'EMI998877');

const cardBillPayment = parseTransactionMessage(state, {
  source: 'sms',
  sender: 'HDFCBK',
  receivedAt: '2026-05-25T08:30:00.000Z',
  body: 'Rs. 12,000 debited from HDFC account ending 5555 towards OneCard credit card payment on 25-May-26. Payment ref CARD778899.',
});

assert.equal(cardBillPayment.recognized, true);
assert.equal(cardBillPayment.amountMinor, 1200000);
assert.equal(cardBillPayment.currency, 'INR');
assert.equal(cardBillPayment.suggestedType, 'card_payment');
assert.equal(cardBillPayment.match.accountId, hdfcBank.id);
assert.equal(cardBillPayment.reference, 'CARD778899');

const existingHints = messageHintSuggestionsForAccount(
  hdfcCard,
  {
    source: 'sms',
    sender: 'HDFCBK',
    body: 'Rs. 1,234.50 debited from HDFC Bank Credit Card XX1234 at SWIGGY.',
  },
  indiaDebit,
);
assert.equal(existingHints.find((hint) => hint.kind === 'sms_sender_id')?.existing, true);
assert.equal(existingHints.find((hint) => hint.kind === 'card_last4')?.existing, true);

const learnState = emptyState('learn-user', 'INR');
const kotak = createAccount(learnState, {
  name: 'Kotak Savings',
  type: 'bank',
  currency: 'INR',
  openingBalanceMinor: 0,
  institution: 'Kotak',
});
const kotakInput = {
  source: 'sms',
  sender: 'KOTAKB',
  receivedAt: '2026-05-25T09:00:00.000Z',
  body: 'INR 250.00 debited from Kotak account ending 4444 at BIGBASKET on 25-May-26. Txn 654321987654.',
};
const kotakResult = parseTransactionMessage(learnState, kotakInput);
const suggestions = messageHintSuggestionsForAccount(kotak, kotakInput, kotakResult).filter(
  (hint) => !hint.existing,
);
assert.ok(suggestions.some((hint) => hint.kind === 'sms_sender_id' && hint.value === 'KOTAKB'));
assert.ok(suggestions.some((hint) => hint.kind === 'account_last4' && hint.value === '4444'));

const payloadSuggestions = messageHintSuggestionsFromCapturePayload(
  kotak,
  kotakResult.candidateInput.rawPayload,
).filter((hint) => !hint.existing);
assert.deepEqual(
  payloadSuggestions.map((hint) => hint.id).sort(),
  suggestions.map((hint) => hint.id).sort(),
);

mergeAcceptedMessageAccountHints(learnState, kotak.id, suggestions);
mergeAcceptedMessageAccountHints(learnState, kotak.id, suggestions);
assert.deepEqual(kotak.messageSourceHints.smsSenderIds, ['KOTAKB']);
assert.equal(
  kotak.matchIdentifiers.filter(
    (identifier) => identifier.kind === 'account_last4' && identifier.value === '4444',
  ).length,
  1,
);

const otp = parseTransactionMessage(state, {
  source: 'sms',
  sender: 'HDFCBK',
  body: 'OTP 123456 for HDFC Bank login. Do not share this code with anyone.',
});

assert.equal(otp.recognized, false);
assert.ok(otp.warnings.includes('security message ignored'));

const otpTrigger = shouldProcessTransactionMessage({
  source: 'sms',
  sender: 'HDFCBK',
  body: 'OTP 123456 for HDFC Bank login. Do not share this code with anyone.',
});
assert.equal(otpTrigger.matched, false);
assert.equal(otpTrigger.ignoredReason, 'security');

const ignoredCapture = processTransactionMessageCapture(state, {
  source: 'sms',
  sender: 'HDFCBK',
  body: 'OTP 123456 for HDFC Bank login. Do not share this code with anyone.',
});
assert.equal(ignoredCapture.outcome, 'ignored');
assert.equal(ignoredCapture.trigger.ignoredReason, 'security');

const autoCaptureState = emptyState('auto-capture-user', 'INR');
assert.equal(autoCaptureState.preferences.autoCapture.sms.backgroundEnabled, true);
seedDefaultCategories(autoCaptureState);
createAccount(autoCaptureState, {
  name: 'HDFC MoneyBack Credit Card',
  type: 'credit_card',
  currency: 'INR',
  openingBalanceMinor: 0,
  institution: 'HDFC Bank',
  matchIdentifiers: buildAccountMatchIdentifiers({ accountType: 'credit_card', lastFour: '1234' }),
  messageSourceHints: buildAccountMessageSourceHints({ smsSenderIds: ['HDFCBK'] }),
});
const postedCapture = processTransactionMessageCapture(
  autoCaptureState,
  {
    source: 'sms',
    sender: 'HDFCBK',
    receivedAt: '2026-05-25T09:00:00.000Z',
    body: 'Rs. 456.00 debited from HDFC Bank Credit Card XX1234 at SWIGGY on 25-May-26 UPI Ref AUTO123456.',
  },
  { autoPost: true, autoPostConfidence: 82 },
);
assert.equal(postedCapture.outcome, 'posted');
assert.equal(autoCaptureState.transactions.length, 1);
assert.equal(autoCaptureState.captureCandidates[0].status, 'approved');

const duplicateCapture = processTransactionMessageCapture(
  autoCaptureState,
  {
    source: 'sms',
    sender: 'HDFCBK',
    receivedAt: '2026-05-25T09:00:00.000Z',
    body: 'Rs. 456.00 debited from HDFC Bank Credit Card XX1234 at SWIGGY on 25-May-26 UPI Ref AUTO123456.',
  },
  { autoPost: true, autoPostConfidence: 82 },
);
assert.equal(duplicateCapture.outcome, 'duplicate');
assert.equal(autoCaptureState.transactions.length, 1);

const queuedCaptureState = emptyState('queued-capture-user', 'INR');
seedDefaultCategories(queuedCaptureState);
const queuedCapture = processTransactionMessageCapture(
  queuedCaptureState,
  {
    source: 'sms',
    sender: 'UNKNOWN',
    receivedAt: '2026-05-25T09:00:00.000Z',
    body: 'INR 90.00 debited at MYSTERY STALL on 25-May-26. Txn QUEUE123456.',
  },
  { autoPost: true, autoPostConfidence: 82 },
);
assert.equal(queuedCapture.outcome, 'queued');
assert.equal(queuedCaptureState.transactions.length, 0);
assert.equal(queuedCaptureState.captureCandidates.length, 1);

const fxState = emptyState('fx-user', 'INR');
const inrCard = createAccount(fxState, {
  name: 'INR Card',
  type: 'credit_card',
  currency: 'INR',
  openingBalanceMinor: 0,
});
const gbpWallet = createAccount(fxState, {
  name: 'GBP Wallet',
  type: 'bank',
  currency: 'GBP',
  openingBalanceMinor: 0,
});
setRate(fxState, 'GBP', 'INR', 100, '2026-05-25', {
  source: 'manual',
  provider: 'test',
  updatedAt: '2026-05-25T10:00:00.000Z',
});
const gbpInrRate = rateRecordForPair(fxState, 'GBP', 'INR');
assert.equal(exchangeRateIsStale(gbpInrRate, new Date('2026-05-25T10:59:59.000Z')), false);
assert.equal(exchangeRateIsStale(gbpInrRate, new Date('2026-05-25T11:00:01.000Z')), true);
assert.equal(
  exchangeRatePairIsStale(fxState, 'GBP', 'INR', new Date('2026-05-25T10:30:00.000Z')),
  false,
);
assert.equal(
  exchangeRatePairIsStale(fxState, 'GBP', 'USD', new Date('2026-05-25T10:30:00.000Z')),
  true,
);
assert.deepEqual(postedAmountFromOriginal({ amountMinor: 5200, currency: 'GBP' }, 'INR', 100), {
  amountMinor: 520000,
  currency: 'INR',
});
const foreignSpend = createTransaction(fxState, {
  type: 'expense',
  accountId: inrCard.id,
  amountMinor: 10000,
  currency: 'INR',
  originalAmountMinor: 100,
  originalCurrency: 'GBP',
  originalFxRate: 100,
});
assert.equal(foreignSpend.amount.currency, 'INR');
assert.equal(foreignSpend.originalAmount.currency, 'GBP');
assert.equal(accountBalance(fxState, inrCard.id).amountMinor, -10000);

setRate(fxState, 'INR', 'GBP', 0.01, '2026-05-25', { source: 'manual', provider: 'test' });
const crossCurrencyTransfer = createTransaction(fxState, {
  type: 'transfer',
  accountId: inrCard.id,
  counterAccountId: gbpWallet.id,
  amountMinor: 10000,
  currency: 'INR',
  counterFxRate: 0.01,
});
assert.equal(crossCurrencyTransfer.counterAmount.currency, 'GBP');
assert.equal(crossCurrencyTransfer.counterAmount.amountMinor, 100);
assert.equal(accountBalance(fxState, inrCard.id).amountMinor, -20000);
assert.equal(accountBalance(fxState, gbpWallet.id).amountMinor, 100);

const storedBaseAmount = foreignSpend.baseAmount.amountMinor;
const storedFxRate = foreignSpend.fxRate;
setDisplayCurrency(fxState, 'GBP');
assert.equal(displayCurrency(fxState), 'GBP');
assert.equal(fxState.preferences.baseCurrency, 'INR');
assert.equal(foreignSpend.baseAmount.amountMinor, storedBaseAmount);
assert.equal(foreignSpend.fxRate, storedFxRate);
assert.equal(totalBalance(fxState).currency, 'INR');
assert.equal(totalBalance(fxState, displayCurrency(fxState)).currency, 'GBP');
assert.equal(totalBalance(fxState, displayCurrency(fxState)).amountMinor, -100);
assert.deepEqual(convertMoneyForDisplay(fxState, { amountMinor: 10000, currency: 'INR' }), {
  amountMinor: 100,
  currency: 'GBP',
});
setRate(fxState, 'INR', 'USD', 0.012, '2026-05-25', { source: 'manual', provider: 'test' });
assert.deepEqual(convertMoneyForDisplay(fxState, { amountMinor: 10000, currency: 'GBP' }, 'USD'), {
  amountMinor: 12000,
  currency: 'USD',
});
assert.equal(totalBalance(fxState, 'USD').amountMinor, -120);
cycleDisplayCurrency(fxState);
assert.notEqual(displayCurrency(fxState), 'GBP');
assert.equal(fxState.preferences.baseCurrency, 'INR');

const selectedAccountBalanceState = emptyState('selected-account-balance-user', 'INR');
const selectedBank = createAccount(selectedAccountBalanceState, {
  name: 'Selected Bank',
  type: 'bank',
  currency: 'INR',
  openingBalanceMinor: 0,
});
const unselectedLoan = createAccount(selectedAccountBalanceState, {
  name: 'Hidden Loan',
  type: 'loan',
  currency: 'INR',
  openingBalanceMinor: -500000,
});
createTransaction(selectedAccountBalanceState, {
  type: 'income',
  status: 'scheduled',
  accountId: selectedBank.id,
  amountMinor: 2000,
  currency: 'INR',
  occurredAt: '2026-05-28T08:00:00.000Z',
});
createTransaction(selectedAccountBalanceState, {
  type: 'expense',
  status: 'scheduled',
  accountId: selectedBank.id,
  amountMinor: 1000,
  currency: 'INR',
  occurredAt: '2026-05-29T08:00:00.000Z',
});
createTransaction(selectedAccountBalanceState, {
  type: 'income',
  status: 'scheduled',
  accountId: selectedBank.id,
  amountMinor: 2000,
  currency: 'INR',
  occurredAt: '2026-06-28T08:00:00.000Z',
});
createTransaction(selectedAccountBalanceState, {
  type: 'expense',
  status: 'scheduled',
  accountId: selectedBank.id,
  amountMinor: 1000,
  currency: 'INR',
  occurredAt: '2026-06-29T08:00:00.000Z',
});
createTransaction(selectedAccountBalanceState, {
  type: 'expense',
  status: 'scheduled',
  accountId: unselectedLoan.id,
  amountMinor: 50000,
  currency: 'INR',
  occurredAt: '2026-05-29T08:00:00.000Z',
});
assert.equal(
  totalBalanceForAccounts(selectedAccountBalanceState, [selectedBank.id]).amountMinor,
  0,
);
assert.equal(
  totalBalanceForAccounts(selectedAccountBalanceState, [selectedBank.id, unselectedLoan.id])
    .amountMinor,
  -500000,
);
assert.equal(
  projectedBalanceForAccountsThroughDate(
    selectedAccountBalanceState,
    [selectedBank.id],
    new Date('2026-06-01T00:00:00.000Z'),
  ).amountMinor,
  1000,
);
assert.equal(
  projectedBalanceForAccountsThroughDate(
    selectedAccountBalanceState,
    [selectedBank.id],
    new Date('2026-07-01T00:00:00.000Z'),
  ).amountMinor,
  2000,
);
assert.equal(
  projectedBalanceForAccountsThroughDate(
    selectedAccountBalanceState,
    [selectedBank.id, unselectedLoan.id],
    new Date('2026-06-01T00:00:00.000Z'),
  ).amountMinor,
  -549000,
);

const recurringState = emptyState('future-user', 'INR');
const recurringAccount = createAccount(recurringState, {
  name: 'Salary Account',
  type: 'bank',
  currency: 'INR',
  openingBalanceMinor: 0,
});
const salaryRule = createFutureGenerationRule(recurringState, {
  name: 'Salary forecast',
  type: 'income',
  accountId: recurringAccount.id,
  amountMinor: 7500000,
  currency: 'INR',
  frequency: 'monthly',
  dayOfMonth: 1,
  startsOn: '2026-06-01',
  paymentMethod: 'Salary',
  notes: 'Salary forecast rule',
});
const rentRule = createFutureGenerationRule(recurringState, {
  name: 'Rent forecast',
  kind: 'expense',
  postMode: 'automatic',
  type: 'expense',
  accountId: recurringAccount.id,
  amountMinor: 3000000,
  currency: 'INR',
  frequency: 'monthly',
  dayOfMonth: 5,
  startsOn: '2026-06-05',
  paymentMethod: 'Autopay',
  notes: 'Rent forecast rule',
});
assert.equal(plannedPaymentKindForRule(salaryRule), 'income');
assert.equal(plannedPaymentPostModeForRule(salaryRule), 'manual');
assert.equal(plannedPaymentKindForRule(rentRule), 'expense');
assert.equal(plannedPaymentPostModeForRule(rentRule), 'automatic');
const generationNow = new Date('2026-05-26T00:00:00.000Z');
const generationSummary = generateFutureTransactionsFromRules(recurringState, {
  horizonMonths: 2,
  now: generationNow,
});
assert.deepEqual(generationSummary, { rules: 2, generated: 4, skipped: 0, invalid: 0 });

const salaryJune = recurringState.transactions.find(
  (transaction) => transaction.externalRef === `future-rule-v1:${salaryRule.id}:2026-06-01`,
);
const rentJune = recurringState.transactions.find(
  (transaction) => transaction.externalRef === `future-rule-v1:${rentRule.id}:2026-06-05`,
);
assert.ok(salaryJune);
assert.equal(salaryJune.status, 'scheduled');
assert.equal(salaryJune.source, 'rule');
assert.equal(salaryJune.recurringTemplateId, salaryRule.id);
assert.equal(salaryJune.amount.amountMinor, 7500000);
assert.equal(salaryJune.type, 'income');
assert.equal(localDateKey(salaryJune.occurredAt), '2026-06-01');
assert.ok(rentJune);
assert.equal(rentJune.status, 'scheduled');
assert.equal(rentJune.source, 'rule');
assert.equal(rentJune.recurringTemplateId, rentRule.id);
assert.equal(rentJune.amount.amountMinor, 3000000);
assert.equal(rentJune.type, 'expense');
assert.equal(localDateKey(rentJune.occurredAt), '2026-06-05');
assert.deepEqual(plannedPaymentRuleStats(recurringState, salaryRule, generationNow), {
  scheduled: 24,
  posted: 0,
  voided: 0,
  nextDueAt: salaryJune.occurredAt,
  lastPostedAt: undefined,
});
assert.equal(
  postDueFutureRuleTransactions(recurringState, {
    automaticOnly: true,
    now: new Date('2026-06-06T10:00:00.000Z'),
  }),
  1,
);
assert.equal(salaryJune.status, 'scheduled');
assert.equal(rentJune.status, 'cleared');
assert.equal(plannedPaymentRuleStats(recurringState, rentRule, generationNow).posted, 1);
assert.equal(
  postDueFutureRuleTransactions(recurringState, { now: new Date('2026-06-06T10:00:00.000Z') }),
  1,
);
assert.equal(salaryJune.status, 'cleared');

const duplicateSummary = generateFutureTransactionsFromRules(recurringState, {
  horizonMonths: 2,
  now: generationNow,
});
assert.deepEqual(duplicateSummary, { rules: 2, generated: 0, skipped: 4, invalid: 0 });
assert.equal(recurringState.transactions.length, 4);
assert.equal(
  localDateKey(
    plannedPaymentRuleStats(recurringState, salaryRule, new Date('2026-06-06T00:00:00.000Z'))
      .nextDueAt,
  ),
  '2026-07-01',
);

const forecastState = emptyState('forecast-user', 'INR');
const forecastAccount = createAccount(forecastState, {
  name: 'Forecast Account',
  type: 'bank',
  currency: 'INR',
  openingBalanceMinor: 0,
});
const clampedRule = createFutureGenerationRule(forecastState, {
  name: 'Month-end EMI',
  kind: 'transfer',
  type: 'expense',
  accountId: forecastAccount.id,
  amountMinor: 100000,
  currency: 'INR',
  frequency: 'monthly',
  dayOfMonth: 31,
  startsOn: '2026-01-31',
});
assert.deepEqual(
  futureRuleOccurrenceDates(clampedRule, {
    now: new Date('2026-01-01T00:00:00.000Z'),
    horizonEnd: new Date('2026-04-02T00:00:00.000Z'),
    maxOccurrences: 4,
  }),
  ['2026-01-31', '2026-02-28', '2026-03-31'],
);
skipFutureRuleOccurrence(forecastState, clampedRule.id, '2026-02-28');
assert.deepEqual(
  futureRuleOccurrenceDates(clampedRule, {
    now: new Date('2026-01-01T00:00:00.000Z'),
    horizonEnd: new Date('2026-04-02T00:00:00.000Z'),
    maxOccurrences: 4,
  }),
  ['2026-01-31', '2026-03-31'],
);
assert.deepEqual(
  forecastFutureRuleOccurrences(forecastState, {
    from: new Date('2026-02-01T00:00:00.000Z'),
    to: new Date('2026-04-02T00:00:00.000Z'),
    now: new Date('2026-01-01T00:00:00.000Z'),
  }).map((occurrence) => occurrence.dueOn),
  ['2026-03-31'],
);

const longRunningRule = createFutureGenerationRule(forecastState, {
  name: 'Old monthly plan',
  type: 'expense',
  accountId: forecastAccount.id,
  amountMinor: 50000,
  currency: 'INR',
  frequency: 'monthly',
  dayOfMonth: 10,
  startsOn: '2020-01-10',
});
assert.deepEqual(
  futureRuleOccurrenceDates(longRunningRule, {
    now: new Date('2026-05-01T00:00:00.000Z'),
    horizonEnd: new Date('2026-08-01T00:00:00.000Z'),
    maxOccurrences: 3,
  }),
  ['2026-05-10', '2026-06-10', '2026-07-10'],
);

const finiteOldRule = createFutureGenerationRule(forecastState, {
  name: 'Old finite monthly plan',
  type: 'expense',
  accountId: forecastAccount.id,
  amountMinor: 50000,
  currency: 'INR',
  frequency: 'monthly',
  dayOfMonth: 10,
  startsOn: '2020-01-10',
  occurrences: 3,
});
assert.deepEqual(
  futureRuleOccurrenceDates(finiteOldRule, {
    now: new Date('2026-05-01T00:00:00.000Z'),
    horizonEnd: new Date('2026-08-01T00:00:00.000Z'),
    maxOccurrences: 3,
  }),
  [],
);

const finiteClampedRule = createFutureGenerationRule(forecastState, {
  name: 'Finite clamped monthly plan',
  type: 'expense',
  accountId: forecastAccount.id,
  amountMinor: 50000,
  currency: 'INR',
  frequency: 'monthly',
  dayOfMonth: 31,
  startsOn: '2026-01-31',
  occurrences: 3,
});
assert.deepEqual(
  futureRuleOccurrenceDates(finiteClampedRule, {
    now: new Date('2026-02-01T00:00:00.000Z'),
    horizonEnd: new Date('2026-05-01T00:00:00.000Z'),
    maxOccurrences: 4,
  }),
  ['2026-02-28', '2026-03-31'],
);

const recurringTemplateState = emptyState('recurring-template-user', 'INR');
const recurringTemplateAccount = createAccount(recurringTemplateState, {
  name: 'Recurring Account',
  type: 'bank',
  currency: 'INR',
  openingBalanceMinor: 0,
});
const recurringSalary = createTransaction(recurringTemplateState, {
  type: 'income',
  status: 'scheduled',
  source: 'recurring',
  accountId: recurringTemplateAccount.id,
  amountMinor: 15000000,
  currency: 'INR',
  occurredAt: '2026-05-28T08:00:00.000Z',
  paymentMethod: 'Salary',
  notes: 'Monthly salary',
  externalRef: 'recurring-fixture:salary',
});
const recurringRent = createTransaction(recurringTemplateState, {
  type: 'expense',
  status: 'scheduled',
  source: 'recurring',
  accountId: recurringTemplateAccount.id,
  amountMinor: 3000000,
  currency: 'INR',
  occurredAt: '2026-05-30T09:00:00.000Z',
  paymentMethod: 'Autopay',
  notes: 'Monthly rent',
  externalRef: 'recurring-fixture:rent',
});
const recurringTemplateSummary = generateFutureTransactionsFromRecurringSchedules(
  recurringTemplateState,
  {
    horizonMonths: 3,
    now: generationNow,
  },
);
assert.deepEqual(recurringTemplateSummary, { rules: 2, generated: 4, skipped: 0, invalid: 0 });

const salaryJuneTemplate = recurringTemplateState.transactions.find(
  (transaction) =>
    transaction.status === 'scheduled' &&
    transaction.source === 'recurring' &&
    transaction.recurringTemplateId === recurringSalary.id &&
    localDateKey(transaction.occurredAt) === '2026-06-28',
);
const rentJuneTemplate = recurringTemplateState.transactions.find(
  (transaction) =>
    transaction.status === 'scheduled' &&
    transaction.source === 'recurring' &&
    transaction.recurringTemplateId === recurringRent.id &&
    localDateKey(transaction.occurredAt) === '2026-06-30',
);
assert.ok(salaryJuneTemplate);
assert.equal(salaryJuneTemplate.originalTransactionId, recurringSalary.id);
assert.equal(salaryJuneTemplate.amount.amountMinor, 15000000);
assert.match(salaryJuneTemplate.externalRef, /^recurring-schedule-v1:/);
assert.ok(rentJuneTemplate);
assert.equal(rentJuneTemplate.originalTransactionId, recurringRent.id);
assert.equal(rentJuneTemplate.amount.amountMinor, 3000000);
assert.match(rentJuneTemplate.externalRef, /^recurring-schedule-v1:/);

const recurringTemplateDuplicateSummary = generateFutureTransactionsFromRecurringSchedules(
  recurringTemplateState,
  {
    horizonMonths: 3,
    now: generationNow,
  },
);
assert.deepEqual(recurringTemplateDuplicateSummary, {
  rules: 2,
  generated: 0,
  skipped: 4,
  invalid: 0,
});
assert.equal(recurringTemplateState.transactions.length, 6);

const monthEndRecurringState = emptyState('month-end-recurring-user', 'INR');
const monthEndRecurringAccount = createAccount(monthEndRecurringState, {
  name: 'Month End Account',
  type: 'bank',
  currency: 'INR',
  openingBalanceMinor: 0,
});
const monthEndTemplate = createTransaction(monthEndRecurringState, {
  type: 'expense',
  status: 'scheduled',
  source: 'recurring',
  accountId: monthEndRecurringAccount.id,
  amountMinor: 500000,
  currency: 'INR',
  occurredAt: '2026-01-31T08:00:00.000Z',
  paymentMethod: 'Autopay',
  notes: 'Month-end recurring expense',
  externalRef: 'recurring-fixture:month-end',
});
const monthEndSummary = generateFutureTransactionsFromRecurringSchedules(monthEndRecurringState, {
  horizonMonths: 4,
  now: new Date('2026-01-01T00:00:00.000Z'),
});
assert.deepEqual(monthEndSummary, { rules: 1, generated: 3, skipped: 0, invalid: 0 });
assert.deepEqual(
  monthEndRecurringState.transactions
    .filter((transaction) => transaction.recurringTemplateId === monthEndTemplate.id)
    .map((transaction) => localDateKey(transaction.occurredAt))
    .sort(),
  ['2026-02-28', '2026-03-31', '2026-04-30'],
);

async function runMigrationFixture() {
  const oldState = emptyState('repair-user', 'INR');
  const repairCard = createAccount(oldState, {
    name: 'Repair INR Card',
    type: 'credit_card',
    currency: 'INR',
    openingBalanceMinor: 0,
  });
  const brokenForeignSpend = createTransaction(oldState, {
    type: 'expense',
    accountId: repairCard.id,
    amountMinor: 5200,
    currency: 'INR',
    originalAmountMinor: 5200,
    originalCurrency: 'GBP',
    originalFxRate: 100,
  });
  oldState.exchangeRates.push({
    base: 'GBP',
    quote: 'INR',
    rate: 106,
    asOfDate: '2026-05-25',
    source: 'seed',
    provider: 'QA seed',
  });
  oldState.preferences.fx = { provider: 'manual', autoRefresh: false };
  oldState.version = 6;

  const adapter = {
    value: JSON.stringify(oldState),
    getItem() {
      return this.value;
    },
    setItem(_key, value) {
      this.value = value;
    },
    removeItem() {
      this.value = null;
    },
  };
  const migrated = await new KVStore(adapter, 'test').load();
  const repaired = migrated.transactions.find(
    (transaction) => transaction.id === brokenForeignSpend.id,
  );
  assert.equal(migrated.version, LEDGER_STATE_VERSION);
  assert.equal(repaired.amount.amountMinor, 520000);
  assert.equal(repaired.amount.currency, 'INR');
  assert.equal(repaired.originalAmount.amountMinor, 5200);
  assert.equal(repaired.originalAmount.currency, 'GBP');
  assert.equal(repaired.baseAmount.amountMinor, 520000);
  assert.equal(repaired.baseAmount.currency, 'INR');
  assert.equal(
    migrated.exchangeRates.some((rate) => rate.source === 'seed'),
    false,
  );
  assert.equal(migrated.preferences.fx.provider, 'frankfurter.app');
  assert.equal(migrated.preferences.fx.autoRefresh, true);

  const forexOldState = emptyState('forex-user', 'INR');
  const axisForex = createAccount(forexOldState, {
    name: 'Axis Forex Card',
    type: 'prepaid',
    currency: 'GBP',
    openingBalanceMinor: 597590,
    institution: 'Axis Bank',
    includeInTotals: false,
    includeInNetWorth: false,
    notes:
      'Kept outside INR totals until a real GBP to INR rate is configured.\nCreated from wallet-snapshot-2026-05-24',
  });
  forexOldState.version = 8;
  const forexAdapter = {
    value: JSON.stringify(forexOldState),
    getItem() {
      return this.value;
    },
    setItem(_key, value) {
      this.value = value;
    },
    removeItem() {
      this.value = null;
    },
  };
  const forexMigrated = await new KVStore(forexAdapter, 'test').load();
  const migratedAxisForex = forexMigrated.accounts.find((account) => account.id === axisForex.id);
  assert.equal(migratedAxisForex.includeInTotals, true);
  assert.equal(migratedAxisForex.includeInNetWorth, true);
  assert.match(migratedAxisForex.notes, /Included in INR totals/);
}

function localDateKey(value) {
  const date = new Date(value);
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${date.getFullYear()}-${month}-${day}`;
}

runMigrationFixture()
  .then(() => {
    console.log('message parser fixtures passed');
  })
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
