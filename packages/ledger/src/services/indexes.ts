import type { Money } from '@1wallet/domain/money';
import { fromMinor, normalizeCurrencyCode, toMinor } from '@1wallet/domain/money';
import type {
  Account,
  CaptureCandidateStatus,
  Category,
  Transaction,
  TransactionSplit,
  TransactionSource,
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
  transactionsByExternalRef: Map<string, Transaction>;
  transactionsByAccountId: Map<UUID, Transaction[]>;
  transactionsByCategoryId: Map<UUID, Transaction[]>;
  scheduledTransactions: Transaction[];
  scheduledTransactionsByAccountId: Map<UUID, Transaction[]>;
  splitsByTransactionId: Map<UUID, TransactionSplit[]>;
  splitTotalsByTransactionId: Map<UUID, Money>;
  captureCandidatesByStatus: Map<CaptureCandidateStatus, LedgerState['captureCandidates']>;
  captureCandidatesBySource: Map<TransactionSource, LedgerState['captureCandidates']>;
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
  const splitTotalsByTransactionId = new Map<UUID, Money>();
  const captureCandidatesByStatus = new Map<
    CaptureCandidateStatus,
    LedgerState['captureCandidates']
  >();
  const captureCandidatesBySource = new Map<TransactionSource, LedgerState['captureCandidates']>();

  for (const account of state.accounts) {
    balancesByAccountId.set(account.id, {
      amountMinor: account.openingBalance.amountMinor,
      currency: account.currency,
    });
  }

  const allTransactionsSorted = [...state.transactions].sort(compareTransactionsDescending);
  const transactionsByExternalRef = new Map<string, Transaction>();

  for (const transaction of allTransactionsSorted) {
    if (transaction.externalRef)
      transactionsByExternalRef.set(transaction.externalRef, transaction);
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

  for (const split of state.transactionSplits) {
    pushMapItem(splitsByTransactionId, split.transactionId, split);
    const current = splitTotalsByTransactionId.get(split.transactionId);
    splitTotalsByTransactionId.set(split.transactionId, {
      amountMinor:
        current && current.currency === split.amount.currency
          ? current.amountMinor + split.amount.amountMinor
          : split.amount.amountMinor,
      currency: current?.currency ?? split.amount.currency,
    });
  }
  for (const splits of splitsByTransactionId.values()) {
    splits.sort(
      (left, right) => left.sortOrder - right.sortOrder || left.id.localeCompare(right.id),
    );
  }

  const captureCandidatesSorted = [...state.captureCandidates].sort(
    compareCaptureCandidatesDescending,
  );
  for (const candidate of captureCandidatesSorted) {
    pushMapItem(captureCandidatesByStatus, candidate.status, candidate);
    pushMapItem(captureCandidatesBySource, candidate.source, candidate);
  }

  return {
    accountsById,
    categoriesById,
    balancesByAccountId,
    allTransactionsSorted,
    transactionsByExternalRef,
    transactionsByAccountId,
    transactionsByCategoryId,
    scheduledTransactions,
    scheduledTransactionsByAccountId,
    splitsByTransactionId,
    splitTotalsByTransactionId,
    captureCandidatesByStatus,
    captureCandidatesBySource,
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

function compareCaptureCandidatesDescending(
  left: LedgerState['captureCandidates'][number],
  right: LedgerState['captureCandidates'][number],
): number {
  return left.createdAt < right.createdAt ? 1 : left.createdAt > right.createdAt ? -1 : 0;
}

function pushMapItem<TKey, TValue>(map: Map<TKey, TValue[]>, key: TKey, value: TValue): void {
  const items = map.get(key);
  if (items) items.push(value);
  else map.set(key, [value]);
}
