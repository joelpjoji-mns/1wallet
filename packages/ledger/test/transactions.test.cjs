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
  createAccount,
  createCategory,
  createTransaction,
  deleteTransaction,
  queryTransactions,
  setRate,
  updateTransaction,
} = require('../src/services/index.ts');
const { buildLedgerIndexes, indexedAccountBalance } = require('../src/services/indexes.ts');
const { emptyState } = require('../src/store/types.ts');

const INFLOW_TYPES = ['income', 'refund', 'interest_in', 'cashback', 'borrowed', 'investment_sell'];
const OUTFLOW_TYPES = ['expense', 'fee', 'interest_out', 'lent', 'investment_buy'];

for (const type of [...INFLOW_TYPES, ...OUTFLOW_TYPES]) {
  const direction = INFLOW_TYPES.includes(type) ? 1 : -1;
  const state = emptyState(`transaction-lifecycle-${type}`, 'INR');
  const account = createAccount(state, {
    name: 'Main Bank',
    type: 'bank',
    currency: 'INR',
    openingBalanceMinor: 100000,
  });
  const category = createCategory(state, { name: `${type} category`, kind: direction > 0 ? 'income' : 'expense' });

  const transaction = createTransaction(state, {
    type,
    accountId: account.id,
    categoryId: category.id,
    amountMinor: 1000,
    currency: 'INR',
    occurredAt: '2026-06-09T10:00:00.000Z',
    source: 'manual',
    paymentMethod: 'UPI',
    notes: 'initial record',
    tags: ['initial'],
  });
  assertAccountBalance(state, account, 100000 + direction * 1000, `${type} create`);

  const initialUpdatedAt = transaction.updatedAt;
  const updated = updateTransaction(state, transaction.id, {
    amountMinor: 2500,
    occurredAt: '2026-06-10T11:15:00.000Z',
    paymentMethod: 'Card',
    notes: 'edited record row text',
    tags: ['edited', type],
  });
  assert.ok(updated);
  assert.ok(updated.updatedAt > initialUpdatedAt, `${type} updatedAt should advance for row memo refresh`);
  assertAccountBalance(state, account, 100000 + direction * 2500, `${type} edit`);
  assert.equal(queryTransactions(state, { text: 'edited record row text' }).length, 1);
  assert.equal(queryTransactions(state, { type }).length, 1);
  assert.equal(buildLedgerIndexes(state).allTransactionsSorted[0].notes, 'edited record row text');

  updateTransaction(state, transaction.id, { status: 'scheduled' });
  assertAccountBalance(state, account, 100000, `${type} scheduled does not affect balance`);
  assert.equal(buildLedgerIndexes(state).scheduledTransactions.length, 1);

  updateTransaction(state, transaction.id, { status: 'cleared' });
  assertAccountBalance(state, account, 100000 + direction * 2500, `${type} re-cleared affects balance`);

  assert.equal(deleteTransaction(state, transaction.id), true);
  assertAccountBalance(state, account, 100000, `${type} delete`);
  assert.equal(queryTransactions(state, { text: 'edited record row text' }).length, 0);
  assert.equal(buildLedgerIndexes(state).allTransactionsSorted.length, 0);
}

{
  const state = emptyState('transaction-lifecycle-adjustment', 'INR');
  const account = createAccount(state, {
    name: 'Cash',
    type: 'cash',
    currency: 'INR',
    openingBalanceMinor: 100000,
  });
  const adjustment = createTransaction(state, {
    type: 'adjustment',
    accountId: account.id,
    amountMinor: 500,
    currency: 'INR',
    occurredAt: '2026-06-09T10:00:00.000Z',
    source: 'manual',
    notes: 'cash count correction',
  });
  assertAccountBalance(state, account, 100500, 'adjustment create');
  const firstUpdatedAt = adjustment.updatedAt;
  updateTransaction(state, adjustment.id, { amountMinor: -1250, notes: 'cash shortage correction' });
  assert.ok(state.transactions[0].updatedAt > firstUpdatedAt, 'adjustment updatedAt should advance');
  assertAccountBalance(state, account, 98750, 'adjustment edit negative');
  assert.equal(queryTransactions(state, { text: 'cash shortage' }).length, 1);
  deleteTransaction(state, adjustment.id);
  assertAccountBalance(state, account, 100000, 'adjustment delete');
}

{
  const state = emptyState('transaction-lifecycle-transfer', 'INR');
  const bank = createAccount(state, {
    name: 'Main Bank',
    type: 'bank',
    currency: 'INR',
    openingBalanceMinor: 100000,
  });
  const cash = createAccount(state, {
    name: 'Cash',
    type: 'cash',
    currency: 'INR',
    openingBalanceMinor: 10000,
  });

  const transfer = createTransaction(state, {
    type: 'transfer',
    accountId: bank.id,
    counterAccountId: cash.id,
    amountMinor: 1000,
    currency: 'INR',
    occurredAt: '2026-06-09T10:00:00.000Z',
    source: 'manual',
    notes: 'atm withdrawal',
  });
  assertAccountBalance(state, bank, 99000, 'transfer source create');
  assertAccountBalance(state, cash, 11000, 'transfer destination create');
  assertIndexesIncludeAccountRows(state, bank.id, cash.id, transfer.id);

  const transferUpdatedAt = transfer.updatedAt;
  updateTransaction(state, transfer.id, {
    amountMinor: 2500,
    paymentMethod: 'ATM',
    notes: 'edited atm withdrawal',
  });
  assert.ok(state.transactions[0].updatedAt > transferUpdatedAt, 'transfer updatedAt should advance');
  assertAccountBalance(state, bank, 97500, 'transfer source amount edit');
  assertAccountBalance(state, cash, 12500, 'transfer destination amount edit');
  assert.equal(queryTransactions(state, { text: 'edited atm' }).length, 1);

  updateTransaction(state, transfer.id, {
    accountId: cash.id,
    counterAccountId: bank.id,
    amountMinor: 500,
    notes: 'cash deposit',
  });
  assertAccountBalance(state, bank, 100500, 'transfer moved source bank');
  assertAccountBalance(state, cash, 9500, 'transfer moved source cash');
  assertIndexesIncludeAccountRows(state, cash.id, bank.id, transfer.id);

  assert.throws(
    () => updateTransaction(state, transfer.id, { counterAccountId: 'missing-account' }),
    /counter account not found/,
  );

  deleteTransaction(state, transfer.id);
  assertAccountBalance(state, bank, 100000, 'transfer delete source');
  assertAccountBalance(state, cash, 10000, 'transfer delete destination');
}

{
  const state = emptyState('transaction-lifecycle-card-loan', 'INR');
  const bank = createAccount(state, {
    name: 'Salary Bank',
    type: 'bank',
    currency: 'INR',
    openingBalanceMinor: 100000,
  });
  const card = createAccount(state, {
    name: 'Credit Card',
    type: 'credit_card',
    currency: 'INR',
    openingBalanceMinor: -20000,
  });
  const loan = createAccount(state, {
    name: 'Personal Loan',
    type: 'loan',
    currency: 'INR',
    openingBalanceMinor: -50000,
  });

  const cardPayment = createTransaction(state, {
    type: 'card_payment',
    accountId: bank.id,
    counterAccountId: card.id,
    amountMinor: 4000,
    currency: 'INR',
    occurredAt: '2026-06-09T10:00:00.000Z',
    source: 'manual',
  });
  assertAccountBalance(state, bank, 96000, 'card payment source create');
  assertAccountBalance(state, card, -16000, 'card payment destination create');
  updateTransaction(state, cardPayment.id, { amountMinor: 5000 });
  assertAccountBalance(state, bank, 95000, 'card payment source edit');
  assertAccountBalance(state, card, -15000, 'card payment destination edit');
  deleteTransaction(state, cardPayment.id);
  assertAccountBalance(state, bank, 100000, 'card payment source delete');
  assertAccountBalance(state, card, -20000, 'card payment destination delete');

  const loanPayment = createTransaction(state, {
    type: 'loan_repayment',
    accountId: bank.id,
    counterAccountId: loan.id,
    amountMinor: 6000,
    currency: 'INR',
    occurredAt: '2026-06-09T10:00:00.000Z',
    source: 'manual',
  });
  assertAccountBalance(state, bank, 94000, 'loan repayment source create');
  assertAccountBalance(state, loan, -44000, 'loan repayment destination create');
  updateTransaction(state, loanPayment.id, { amountMinor: 7000 });
  assertAccountBalance(state, bank, 93000, 'loan repayment source edit');
  assertAccountBalance(state, loan, -43000, 'loan repayment destination edit');
  deleteTransaction(state, loanPayment.id);
  assertAccountBalance(state, bank, 100000, 'loan repayment source delete');
  assertAccountBalance(state, loan, -50000, 'loan repayment destination delete');
}

{
  const state = emptyState('transaction-lifecycle-cross-currency', 'INR');
  setRate(state, 'USD', 'INR', 80, '2026-06-09', { updatedAt: '2026-06-09T00:00:00.000Z' });
  setRate(state, 'INR', 'USD', 0.0125, '2026-06-09', { updatedAt: '2026-06-09T00:00:00.000Z' });
  const bank = createAccount(state, {
    name: 'Main Bank',
    type: 'bank',
    currency: 'INR',
    openingBalanceMinor: 100000,
  });
  const usdWallet = createAccount(state, {
    name: 'USD Wallet',
    type: 'wallet',
    currency: 'USD',
    openingBalanceMinor: 10000,
  });

  const fxTransfer = createTransaction(state, {
    type: 'transfer',
    accountId: bank.id,
    counterAccountId: usdWallet.id,
    amountMinor: 8000,
    currency: 'INR',
    counterAmountMinor: 100,
    counterCurrency: 'USD',
    counterFxRate: 0.0125,
    fxRate: 1,
    occurredAt: '2026-06-09T10:00:00.000Z',
    source: 'manual',
  });
  assertAccountBalance(state, bank, 92000, 'fx transfer source create');
  assertAccountBalance(state, usdWallet, 10100, 'fx transfer destination create');
  updateTransaction(state, fxTransfer.id, {
    amountMinor: 16000,
    counterAmountMinor: 200,
    counterCurrency: 'USD',
    counterFxRate: 0.0125,
  });
  assertAccountBalance(state, bank, 84000, 'fx transfer source edit');
  assertAccountBalance(state, usdWallet, 10200, 'fx transfer destination edit');
  updateTransaction(state, fxTransfer.id, { status: 'void' });
  assertAccountBalance(state, bank, 100000, 'fx transfer void source');
  assertAccountBalance(state, usdWallet, 10000, 'fx transfer void destination');
}

function assertAccountBalance(state, account, expectedAmountMinor, label) {
  const balance = accountBalance(state, account.id);
  assert.equal(balance.amountMinor, expectedAmountMinor, label);
  assert.equal(balance.currency, account.currency, `${label} currency`);
  const indexed = indexedAccountBalance(buildLedgerIndexes(state), account);
  assert.deepEqual(indexed, balance, `${label} indexed balance`);
}

function assertIndexesIncludeAccountRows(state, sourceAccountId, counterAccountId, transactionId) {
  const indexes = buildLedgerIndexes(state);
  assert.ok(
    indexes.transactionsByAccountId.get(sourceAccountId)?.some((item) => item.id === transactionId),
    'source account index should include transaction',
  );
  assert.ok(
    indexes.transactionsByAccountId.get(counterAccountId)?.some((item) => item.id === transactionId),
    'counter account index should include transaction',
  );
}

console.log('transaction lifecycle tests passed');
