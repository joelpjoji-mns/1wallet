// Mirrors the balance/aggregation rules in lib/src/ledger/ledger_selectors.dart
// so the PWA computes exactly the same real balances the Flutter app shows —
// no fabricated numbers.

import type { Account, Money, TransactionRecord } from './ledgerTypes';

export const INCOME_TYPES = new Set([
  'income',
  'refund',
  'interest_in',
  'cashback',
  'borrowed',
  'investment_sell',
]);

export const EXPENSE_TYPES = new Set([
  'expense',
  'fee',
  'interest_out',
  'lent',
  'investment_buy',
  'card_payment',
  'loan_repayment',
]);

export const TRANSFER_TYPES = new Set(['transfer']);

const INACTIVE_STATUSES = new Set(['scheduled', 'paused', 'void']);

export function sourceDelta(t: TransactionRecord): number {
  if (INCOME_TYPES.has(t.type)) return t.amount.amountMinor;
  if (EXPENSE_TYPES.has(t.type) || TRANSFER_TYPES.has(t.type)) {
    return -Math.abs(t.amount.amountMinor);
  }
  if (t.type === 'adjustment') return t.amount.amountMinor;
  return 0;
}

export function counterDelta(t: TransactionRecord): number {
  if (TRANSFER_TYPES.has(t.type)) {
    const counterAmt = t.counterAmount ?? t.amount;
    if (counterAmt.amountMinor === 0 && t.amount.amountMinor !== 0) {
      if (t.counterAmount?.currency.toUpperCase() === t.amount.currency.toUpperCase()) {
        return Math.abs(t.amount.amountMinor);
      }
    }
    return Math.abs(counterAmt.amountMinor);
  }
  if (t.type === 'card_payment' || t.type === 'loan_repayment') {
    return Math.abs(t.amount.amountMinor);
  }
  return 0;
}

/** Current balance for every account, in the account's own currency. */
export function accountBalanceMap(
  accounts: Account[],
  transactions: TransactionRecord[],
): Map<string, Money> {
  const balances = new Map<string, Money>();
  for (const account of accounts) {
    balances.set(account.id, {
      amountMinor: account.openingBalance.amountMinor,
      currency: account.currency,
    });
  }

  for (const t of transactions) {
    if (INACTIVE_STATUSES.has(t.status)) continue;

    const source = balances.get(t.accountId);
    if (source) {
      balances.set(t.accountId, { ...source, amountMinor: source.amountMinor + sourceDelta(t) });
    }

    if (t.counterAccountId) {
      const counter = balances.get(t.counterAccountId);
      if (counter) {
        balances.set(t.counterAccountId, {
          ...counter,
          amountMinor: counter.amountMinor + counterDelta(t),
        });
      }
    }
  }

  return balances;
}

export function accountBalance(
  balances: Map<string, Money>,
  account: Account,
): Money {
  return balances.get(account.id) ?? {
    amountMinor: account.openingBalance.amountMinor,
    currency: account.currency,
  };
}

export function formatMoney(money: Money, locale = 'en-US'): string {
  try {
    return new Intl.NumberFormat(locale.replace('_', '-'), {
      style: 'currency',
      currency: money.currency || 'USD',
      currencyDisplay: 'narrowSymbol',
    }).format(money.amountMinor / 100);
  } catch {
    return `${(money.amountMinor / 100).toFixed(2)} ${money.currency}`;
  }
}

export function transactionsForAccount(
  transactions: TransactionRecord[],
  accountId: string,
): TransactionRecord[] {
  return transactions.filter(
    (t) => t.accountId === accountId || t.counterAccountId === accountId,
  );
}

export function sortedTransactions(
  transactions: TransactionRecord[],
  { includeScheduled = true }: { includeScheduled?: boolean } = {},
): TransactionRecord[] {
  const items = transactions.filter(
    (t) => includeScheduled || (t.status !== 'scheduled' && t.status !== 'paused'),
  );
  return [...items].sort((a, b) => Date.parse(b.occurredAt) - Date.parse(a.occurredAt));
}

/** Net cashflow (income - expense, transfers excluded) per ISO date (yyyy-MM-dd). */
export function dailyCashflow(
  transactions: TransactionRecord[],
): Map<string, { incomeMinor: number; expenseMinor: number; currency: string }> {
  const byDate = new Map<string, { incomeMinor: number; expenseMinor: number; currency: string }>();
  for (const t of transactions) {
    if (INACTIVE_STATUSES.has(t.status) || TRANSFER_TYPES.has(t.type)) continue;
    const dateKey = t.occurredAt.slice(0, 10);
    const bucket = byDate.get(dateKey) ?? {
      incomeMinor: 0,
      expenseMinor: 0,
      currency: t.amount.currency,
    };
    if (INCOME_TYPES.has(t.type)) {
      bucket.incomeMinor += t.amount.amountMinor;
    } else if (EXPENSE_TYPES.has(t.type)) {
      bucket.expenseMinor += Math.abs(t.amount.amountMinor);
    }
    byDate.set(dateKey, bucket);
  }
  return byDate;
}

/** Scheduled (future/recurring) transactions occurring within `days` days of `fromIso`. */
export function upcomingTransactions(
  transactions: TransactionRecord[],
  fromIso: string,
  days: number,
): TransactionRecord[] {
  const from = new Date(fromIso).getTime();
  const to = from + days * 86_400_000;
  return transactions
    .filter((t) => t.status === 'scheduled')
    .filter((t) => {
      const time = new Date(t.occurredAt).getTime();
      return time >= from && time <= to;
    })
    .sort((a, b) => Date.parse(a.occurredAt) - Date.parse(b.occurredAt));
}
