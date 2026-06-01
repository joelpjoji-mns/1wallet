import { formatMoney, normalizeCurrencyCode } from '@1wallet/domain/money';
import type { Money } from '@1wallet/domain/money';
import type { Transaction } from '@1wallet/domain/types';
import { convertMoneyForDisplay, displayCurrency } from '@1wallet/ledger/services';
import type { LedgerState } from '@1wallet/ledger/store/types';
import {
    EXPENSE_TRANSACTION_TYPES,
    INCOME_TRANSACTION_TYPES,
    TRANSFER_TRANSACTION_TYPES,
} from './transactionTypes';

export type TransactionAmountRowSide = 'single' | 'transferOut' | 'transferIn';

export interface TransactionAmountDisplay {
  primary: string;
  secondary: string[];
  primaryMoney: Money;
}

interface SecondaryMoney {
  label: string;
  money: Money;
  approximate: boolean;
}

export function transactionAmountDisplay(
  transaction: Transaction,
  side: TransactionAmountRowSide,
  state: LedgerState,
  locale: string,
): TransactionAmountDisplay {
  const primaryMoney = primaryMoneyForRow(transaction, side);
  const secondary = secondaryMoneyForRow(transaction, side, primaryMoney, state);
  const showLabels = secondary.length > 1;

  return {
    primary: formatSignedMoney(primaryMoney, locale),
    secondary: secondary.map((item) =>
      formatSignedMoney(item.money, locale, {
        approximate: item.approximate,
        label: showLabels ? item.label : undefined,
      }),
    ),
    primaryMoney,
  };
}

export function signedTransactionAmount(transaction: Transaction): number {
  if (INCOME_TRANSACTION_TYPES.has(transaction.type)) return transaction.amount.amountMinor;
  if (EXPENSE_TRANSACTION_TYPES.has(transaction.type)) return -transaction.amount.amountMinor;
  if (transaction.type === 'adjustment') return transaction.amount.amountMinor;
  return transaction.amount.amountMinor;
}

function primaryMoneyForRow(transaction: Transaction, side: TransactionAmountRowSide): Money {
  if (side === 'transferOut') {
    return {
      amountMinor: -Math.abs(transaction.amount.amountMinor),
      currency: transaction.amount.currency,
    };
  }

  if (side === 'transferIn') {
    const money = transaction.counterAmount ?? transaction.amount;
    return { amountMinor: Math.abs(money.amountMinor), currency: money.currency };
  }

  if (
    !TRANSFER_TRANSACTION_TYPES.has(transaction.type) &&
    transaction.originalAmount &&
    differentCurrency(transaction.originalAmount.currency, transaction.amount.currency)
  ) {
    return signedCopy(transaction.originalAmount, transactionDirection(transaction));
  }

  return {
    amountMinor: signedTransactionAmount(transaction),
    currency: transaction.amount.currency,
  };
}

function secondaryMoneyForRow(
  transaction: Transaction,
  side: TransactionAmountRowSide,
  primaryMoney: Money,
  state: LedgerState,
): SecondaryMoney[] {
  const seenCurrencies = new Set([normalizeCurrencyCode(primaryMoney.currency)]);
  const items: SecondaryMoney[] = [];
  const add = (label: string, money: Money | undefined, approximate: boolean) => {
    if (!money || money.amountMinor === 0) return;
    const currency = normalizeCurrencyCode(money.currency);
    if (seenCurrencies.has(currency)) return;
    seenCurrencies.add(currency);
    items.push({ label, money: { amountMinor: money.amountMinor, currency }, approximate });
  };

  if (side === 'transferOut') {
    add('To', transaction.counterAmount, false);
  } else if (side === 'transferIn') {
    add(
      'From',
      {
        amountMinor: -Math.abs(transaction.amount.amountMinor),
        currency: transaction.amount.currency,
      },
      false,
    );
  } else if (
    transaction.originalAmount &&
    differentCurrency(transaction.originalAmount.currency, transaction.amount.currency)
  ) {
    add('Account', signedCopy(transaction.amount, transactionDirection(transaction)), false);
  }

  const defaultCurrency = displayCurrency(state);
  if (!seenCurrencies.has(normalizeCurrencyCode(defaultCurrency))) {
    const defaultMoney = defaultMoneyForTransaction(
      transaction,
      primaryMoney,
      state,
      defaultCurrency,
    );
    add('Default', defaultMoney, true);
  }

  return items;
}

function defaultMoneyForTransaction(
  transaction: Transaction,
  primaryMoney: Money,
  state: LedgerState,
  currency: string,
): Money {
  const normalizedCurrency = normalizeCurrencyCode(currency);
  const direction = primaryMoney.amountMinor < 0 ? -1 : primaryMoney.amountMinor > 0 ? 1 : 0;

  if (sameCurrency(transaction.baseAmount.currency, normalizedCurrency)) {
    return signedCopy(transaction.baseAmount, direction || transactionDirection(transaction));
  }

  const converted = convertMoneyForDisplay(
    state,
    {
      amountMinor: Math.abs(primaryMoney.amountMinor),
      currency: primaryMoney.currency,
    },
    normalizedCurrency,
  );
  return signedCopy(converted, direction);
}

function transactionDirection(transaction: Transaction): -1 | 0 | 1 {
  const amountMinor = signedTransactionAmount(transaction);
  if (amountMinor < 0) return -1;
  if (amountMinor > 0) return 1;
  return 0;
}

function signedCopy(money: Money, direction: -1 | 0 | 1): Money {
  return {
    amountMinor: direction === 0 ? 0 : Math.abs(money.amountMinor) * direction,
    currency: money.currency,
  };
}

function formatSignedMoney(
  money: Money,
  locale: string,
  options: { approximate?: boolean; label?: string } = {},
): string {
  const sign = money.amountMinor > 0 ? '+' : money.amountMinor < 0 ? '-' : '';
  const formatted = `${sign}${formatMoney(
    { amountMinor: Math.abs(money.amountMinor), currency: money.currency },
    locale,
  )}`;
  const amount = options.approximate ? `≈ ${formatted}` : formatted;
  return options.label ? `${options.label} ${amount}` : amount;
}

function sameCurrency(first: string, second: string): boolean {
  return normalizeCurrencyCode(first) === normalizeCurrencyCode(second);
}

function differentCurrency(first: string, second: string): boolean {
  return !sameCurrency(first, second);
}
