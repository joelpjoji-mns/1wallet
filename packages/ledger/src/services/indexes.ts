import type { Money } from '@1wallet/domain/money';
import { fromMinor, normalizeCurrencyCode, toMinor } from '@1wallet/domain/money';
import type {
    Account,
    Category,
    Transaction,
    TransactionSplit,
    TransactionType,
    UUID,
} from '@1wallet/domain/types';
import type { LedgerState } from '../store/types';
import { rateBetween } from './index';

export interface LedgerIndexes {
  accountsById: Map<UUID, Account>;
  categoriesById: Map<UUID, Category>;
  balancesByAccountId: Map<UUID, Money>;
  allTransactionsSorted: Transaction[];
  transactionsByAccountId: Map<UUID, Transaction[]>;
  transactionsByCategoryId: Map<UUID, Transaction[]>;
  scheduledTransactions: Transaction[];
  scheduledTransactionsByAccountId: Map<UUID, Transaction[]>;
  splitsByTransactionId: Map<UUID, TransactionSplit[]>;
}

const INFLOW_TYPES = new Set<TransactionType>([
  'income',
  'refund',
  'interest_in',
  'cashback',
  'borrowed',
  'investment_sell',
]);
const OUTFLOW_TYPES = new Set<TransactionType>([
  'expense',
  'fee',
  'interest_out',
  'lent',
  'investment_buy',
]);
const TRANSFER_TYPES = new Set<TransactionType>(['transfer', 'card_payment', 'loan_repayment']);

export function buildLedgerIndexes(state: LedgerState): LedgerIndexes {
  const accountsById = new Map(state.accounts.map((account) => [account.id, account]));
  const categoriesById = new Map(state.categories.map((category) => [category.id, category]));
  const balancesByAccountId = new Map<UUID, Money>();
  const transactionsByAccountId = new Map<UUID, Transaction[]>();
  const transactionsByCategoryId = new Map<UUID, Transaction[]>();
  const scheduledTransactions: Transaction[] = [];
  const scheduledTransactionsByAccountId = new Map<UUID, Transaction[]>();
  const splitsByTransactionId = new Map<UUID, TransactionSplit[]>();

  for (const account of state.accounts) {
    balancesByAccountId.set(account.id, {
      amountMinor: account.openingBalance.amountMinor,
      currency: account.currency,
    });
  }

  const allTransactionsSorted = [...state.transactions].sort(compareTransactionsDescending);

  for (const transaction of allTransactionsSorted) {
    pushMapItem(transactionsByAccountId, transaction.accountId, transaction);
    if (transaction.counterAccountId && transaction.counterAccountId !== transaction.accountId) {
      pushMapItem(transactionsByAccountId, transaction.counterAccountId, transaction);
    }
    if (transaction.categoryId)
      pushMapItem(transactionsByCategoryId, transaction.categoryId, transaction);
    if (transaction.status === 'scheduled') scheduledTransactions.push(transaction);
    applyTransactionToBalances(state, accountsById, balancesByAccountId, transaction);
  }

  scheduledTransactions.sort(compareTransactionsAscending);

  for (const transaction of scheduledTransactions) {
    pushMapItem(scheduledTransactionsByAccountId, transaction.accountId, transaction);
    if (transaction.counterAccountId && transaction.counterAccountId !== transaction.accountId) {
      pushMapItem(scheduledTransactionsByAccountId, transaction.counterAccountId, transaction);
    }
  }

  for (const split of state.transactionSplits)
    pushMapItem(splitsByTransactionId, split.transactionId, split);
  for (const splits of splitsByTransactionId.values()) {
    splits.sort(
      (left, right) => left.sortOrder - right.sortOrder || left.id.localeCompare(right.id),
    );
  }

  return {
    accountsById,
    categoriesById,
    balancesByAccountId,
    allTransactionsSorted,
    transactionsByAccountId,
    transactionsByCategoryId,
    scheduledTransactions,
    scheduledTransactionsByAccountId,
    splitsByTransactionId,
  };
}

export function indexedAccountBalance(indexes: LedgerIndexes, account: Account): Money {
  return (
    indexes.balancesByAccountId.get(account.id) ?? { amountMinor: 0, currency: account.currency }
  );
}

function applyTransactionToBalances(
  state: LedgerState,
  accountsById: Map<UUID, Account>,
  balancesByAccountId: Map<UUID, Money>,
  transaction: Transaction,
) {
  if (transaction.status === 'scheduled' || transaction.status === 'void') return;

  const sourceAccount = accountsById.get(transaction.accountId);
  if (sourceAccount) {
    const current = balancesByAccountId.get(sourceAccount.id) ?? {
      amountMinor: 0,
      currency: sourceAccount.currency,
    };
    const amountMinor = amountInCurrency(state, transaction.amount, sourceAccount.currency);
    let nextAmountMinor = current.amountMinor;
    if (INFLOW_TYPES.has(transaction.type)) nextAmountMinor += amountMinor;
    else if (OUTFLOW_TYPES.has(transaction.type)) nextAmountMinor -= amountMinor;
    else if (TRANSFER_TYPES.has(transaction.type)) nextAmountMinor -= amountMinor;
    else if (transaction.type === 'adjustment') nextAmountMinor += amountMinor;
    balancesByAccountId.set(sourceAccount.id, {
      amountMinor: nextAmountMinor,
      currency: sourceAccount.currency,
    });
  }

  if (!TRANSFER_TYPES.has(transaction.type) || !transaction.counterAccountId) return;
  const counterAccount = accountsById.get(transaction.counterAccountId);
  if (!counterAccount) return;
  const current = balancesByAccountId.get(counterAccount.id) ?? {
    amountMinor: 0,
    currency: counterAccount.currency,
  };
  balancesByAccountId.set(counterAccount.id, {
    amountMinor:
      current.amountMinor + transferCounterAmountMinor(state, transaction, counterAccount.currency),
    currency: counterAccount.currency,
  });
}

function amountInCurrency(state: LedgerState, money: Money, currency: string): number {
  const normalizedCurrency = normalizeCurrencyCode(currency);
  if (normalizeCurrencyCode(money.currency) === normalizedCurrency) return money.amountMinor;
  return convertMinor(
    money.amountMinor,
    money.currency,
    normalizedCurrency,
    rateBetween(state, money.currency, normalizedCurrency),
  );
}

function transferCounterAmountMinor(
  state: LedgerState,
  transaction: Transaction,
  accountCurrency: string,
): number {
  if (transaction.counterAmount)
    return amountInCurrency(state, transaction.counterAmount, accountCurrency);
  return amountInCurrency(state, transaction.amount, accountCurrency);
}

function convertMinor(
  amountMinor: number,
  fromCurrency: string,
  toCurrency: string,
  rate: number,
): number {
  const normalizedFrom = normalizeCurrencyCode(fromCurrency);
  const normalizedTo = normalizeCurrencyCode(toCurrency);
  if (normalizedFrom === normalizedTo) return amountMinor;
  return toMinor(fromMinor(amountMinor, normalizedFrom) * rate, normalizedTo);
}

function compareTransactionsDescending(left: Transaction, right: Transaction): number {
  return left.occurredAt < right.occurredAt ? 1 : left.occurredAt > right.occurredAt ? -1 : 0;
}

function compareTransactionsAscending(left: Transaction, right: Transaction): number {
  return left.occurredAt.localeCompare(right.occurredAt);
}

function pushMapItem<TKey, TValue>(map: Map<TKey, TValue[]>, key: TKey, value: TValue): void {
  const items = map.get(key);
  if (items) items.push(value);
  else map.set(key, [value]);
}
