import type { TransactionType } from '@1wallet/domain/types';
import type { AppIconName } from './components/AppKit';
import type { IconSurfaceTone } from './iconSystem';

export type TransactionTypeBucket = 'expense' | 'income' | 'transfer' | 'adjustment';

export type TransactionTypeBucketOption = {
  value: TransactionTypeBucket;
  label: string;
  description: string;
  icon: AppIconName;
  iconTone: IconSurfaceTone;
};

export type TransactionTypeOption = {
  value: TransactionType;
  label: string;
  description: string;
  icon: AppIconName;
  iconTone: IconSurfaceTone;
};

export const INCOME_TRANSACTION_TYPES = new Set<TransactionType>([
  'income',
  'refund',
  'interest_in',
  'cashback',
  'borrowed',
  'investment_sell',
]);

export const EXPENSE_TRANSACTION_TYPES = new Set<TransactionType>([
  'expense',
  'fee',
  'interest_out',
  'lent',
  'investment_buy',
]);

export const TRANSFER_TRANSACTION_TYPES = new Set<TransactionType>([
  'transfer',
  'card_payment',
  'loan_repayment',
]);

export const TRANSACTION_TYPE_BUCKET_OPTIONS: TransactionTypeBucketOption[] = [
  {
    value: 'expense',
    label: 'Expense',
    description: 'Spending, fees, lent money',
    icon: 'arrow-up-circle-outline',
    iconTone: 'expense',
  },
  {
    value: 'income',
    label: 'Income',
    description: 'Income, refunds, cashback',
    icon: 'arrow-down-circle-outline',
    iconTone: 'income',
  },
  {
    value: 'transfer',
    label: 'Transfer',
    description: 'Transfers, cards, loans',
    icon: 'swap-horizontal',
    iconTone: 'transfer',
  },
  {
    value: 'adjustment',
    label: 'Adjustment',
    description: 'Balance correction',
    icon: 'tune-variant',
    iconTone: 'adjustment',
  },
];

export const TRANSACTION_TYPE_OPTIONS: TransactionTypeOption[] = [
  {
    value: 'expense',
    label: 'Expense',
    description: 'Spending, purchases, bills, and daily outflow',
    icon: 'arrow-up-circle-outline',
    iconTone: 'expense',
  },
  {
    value: 'income',
    label: 'Income',
    description: 'Salary, freelance income, and other inflow',
    icon: 'arrow-down-circle-outline',
    iconTone: 'income',
  },
  {
    value: 'transfer',
    label: 'Transfer',
    description: 'Move money between your own accounts',
    icon: 'swap-horizontal',
    iconTone: 'transfer',
  },
  {
    value: 'refund',
    label: 'Refund',
    description: 'Returned money from a previous spend',
    icon: 'cash-refund',
    iconTone: 'income',
  },
  {
    value: 'adjustment',
    label: 'Adjustment',
    description: 'Balance correction',
    icon: 'tune-variant',
    iconTone: 'adjustment',
  },
  {
    value: 'card_payment',
    label: 'Card payment',
    description: 'Pay a credit card bill from bank or wallet',
    icon: 'credit-card-check-outline',
    iconTone: 'transfer',
  },
  {
    value: 'loan_repayment',
    label: 'Loan EMI',
    description: 'Loan installment, EMI, or debt repayment',
    icon: 'bank-transfer-out',
    iconTone: 'loan',
  },
  {
    value: 'lent',
    label: 'Lent out',
    description: 'Money you gave someone to return later',
    icon: 'hand-coin-outline',
    iconTone: 'expense',
  },
  {
    value: 'borrowed',
    label: 'Borrowed',
    description: 'Money borrowed from someone else',
    icon: 'hand-coin',
    iconTone: 'income',
  },
  {
    value: 'investment_buy',
    label: 'Investment buy',
    description: 'Investment purchase or contribution',
    icon: 'chart-line',
    iconTone: 'expense',
  },
  {
    value: 'investment_sell',
    label: 'Investment sell',
    description: 'Investment sale, redemption, or withdrawal',
    icon: 'chart-line-variant',
    iconTone: 'income',
  },
  {
    value: 'fee',
    label: 'Fee',
    description: 'Bank, card, platform, or service fee',
    icon: 'receipt',
    iconTone: 'expense',
  },
  {
    value: 'interest_in',
    label: 'Interest earned',
    description: 'Interest credited to an account',
    icon: 'bank-plus',
    iconTone: 'income',
  },
  {
    value: 'interest_out',
    label: 'Interest paid',
    description: 'Loan, card, or overdraft interest',
    icon: 'bank-minus',
    iconTone: 'expense',
  },
  {
    value: 'cashback',
    label: 'Cashback',
    description: 'Card, wallet, or merchant cashback',
    icon: 'sale',
    iconTone: 'income',
  },
];

export const TRANSFER_PURPOSE_OPTIONS: TransactionTypeOption[] = TRANSACTION_TYPE_OPTIONS.filter(
  (option) => TRANSFER_TRANSACTION_TYPES.has(option.value),
);

export function transactionTypeBucket(type: TransactionType): TransactionTypeBucket {
  if (type === 'adjustment') return 'adjustment';
  if (TRANSFER_TRANSACTION_TYPES.has(type)) return 'transfer';
  if (INCOME_TRANSACTION_TYPES.has(type)) return 'income';
  return 'expense';
}

export function transactionTypeForBucket(bucket: TransactionTypeBucket): TransactionType {
  return bucket;
}

export function transactionTypeBucketOptionFor(
  bucket: TransactionTypeBucket,
): TransactionTypeBucketOption {
  return (
    TRANSACTION_TYPE_BUCKET_OPTIONS.find((option) => option.value === bucket) ??
    TRANSACTION_TYPE_BUCKET_OPTIONS[0]!
  );
}

export function transactionTypeOptionFor(type: TransactionType): TransactionTypeBucketOption {
  return transactionTypeBucketOptionFor(transactionTypeBucket(type));
}

export function transactionTypeLabel(type: TransactionType): string {
  return TRANSACTION_TYPE_OPTIONS.find((option) => option.value === type)?.label ?? type;
}

export function transactionTypeIcon(type: TransactionType): AppIconName {
  return (
    TRANSACTION_TYPE_OPTIONS.find((option) => option.value === type)?.icon ??
    transactionTypeOptionFor(type).icon
  );
}

export function transactionTypeIconTone(type: TransactionType): IconSurfaceTone {
  return (
    TRANSACTION_TYPE_OPTIONS.find((option) => option.value === type)?.iconTone ??
    transactionTypeOptionFor(type).iconTone
  );
}

export function isIncomeTransactionType(type: TransactionType): boolean {
  return INCOME_TRANSACTION_TYPES.has(type);
}

export function isExpenseTransactionType(type: TransactionType): boolean {
  return EXPENSE_TRANSACTION_TYPES.has(type);
}

export function isTransferTransactionType(type: TransactionType): boolean {
  return TRANSFER_TRANSACTION_TYPES.has(type);
}

export function categoryKindForTransactionType(type: TransactionType): 'expense' | 'income' {
  return isIncomeTransactionType(type) ? 'income' : 'expense';
}
