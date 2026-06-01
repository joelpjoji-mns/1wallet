import type { Account, AccountType } from '@1wallet/domain/types';
import { ACCOUNT_COLOR_SWATCHES, DEFAULT_ACCOUNT_COLOR } from './colorPalettes';
import type { OptionListItem } from './components/OptionListOverlay';
import {
    iconTextColorForBackground,
    resolveAppIconName,
    solidIconSurfaceForColor,
    type AppIconName,
} from './iconSystem';

export { DEFAULT_ACCOUNT_COLOR, iconTextColorForBackground as readableTextColorForBackground };

export const ACCOUNT_TYPE_OPTIONS: OptionListItem<AccountType>[] = [
  { value: 'cash', label: 'Cash', description: 'Physical cash kept on hand', icon: 'cash' },
  {
    value: 'bank',
    label: 'Bank',
    description: 'Savings, current, or checking account',
    icon: 'bank-outline',
  },
  {
    value: 'credit_card',
    label: 'Credit card',
    description: 'Statement balance and repayments',
    icon: 'credit-card-outline',
  },
  {
    value: 'debit_card',
    label: 'Debit card',
    description: 'Card linked to a bank account',
    icon: 'credit-card-chip-outline',
  },
  {
    value: 'wallet',
    label: 'Wallet',
    description: 'Digital wallet or prepaid app balance',
    icon: 'wallet-outline',
  },
  {
    value: 'prepaid',
    label: 'Prepaid',
    description: 'Stored-value or forex card',
    icon: 'card-account-details-outline',
  },
  {
    value: 'loan',
    label: 'Loan',
    description: 'Borrowed money with repayments',
    icon: 'bank-transfer-out',
  },
  {
    value: 'lent',
    label: 'Lent',
    description: 'Money owed back to you',
    icon: 'account-cash-outline',
  },
  {
    value: 'investment',
    label: 'Investment',
    description: 'Brokerage, fund, or long-term asset',
    icon: 'chart-line',
  },
  {
    value: 'savings_goal',
    label: 'Savings goal',
    description: 'Money reserved for a target',
    icon: 'piggy-bank-outline',
  },
  {
    value: 'overdraft',
    label: 'Overdraft',
    description: 'Credit line attached to an account',
    icon: 'alert-circle-outline',
  },
  { value: 'crypto', label: 'Crypto', description: 'Digital assets', icon: 'bitcoin' },
  {
    value: 'other',
    label: 'Other',
    description: 'Anything that does not fit the defaults',
    icon: 'dots-horizontal-circle-outline',
  },
];

export const ACCOUNT_ICON_OPTIONS: OptionListItem<AppIconName>[] = [
  { value: 'wallet-outline', label: 'Wallet', icon: 'wallet-outline' },
  { value: 'bank-outline', label: 'Bank', icon: 'bank-outline' },
  { value: 'credit-card-outline', label: 'Credit card', icon: 'credit-card-outline' },
  { value: 'credit-card-chip-outline', label: 'Debit card', icon: 'credit-card-chip-outline' },
  { value: 'cash-multiple', label: 'Cash', icon: 'cash-multiple' },
  { value: 'piggy-bank-outline', label: 'Savings', icon: 'piggy-bank-outline' },
  { value: 'card-account-details-outline', label: 'Prepaid', icon: 'card-account-details-outline' },
  { value: 'bank-transfer-out', label: 'Loan', icon: 'bank-transfer-out' },
  { value: 'hand-coin-outline', label: 'Debt', icon: 'hand-coin-outline' },
  { value: 'account-cash-outline', label: 'Lent', icon: 'account-cash-outline' },
  { value: 'chart-line', label: 'Investment', icon: 'chart-line' },
  { value: 'bitcoin', label: 'Crypto', icon: 'bitcoin' },
  { value: 'currency-gbp', label: 'Forex', icon: 'currency-gbp' },
  { value: 'safe-square-outline', label: 'Safe', icon: 'safe-square-outline' },
  { value: 'home-city-outline', label: 'Property', icon: 'home-city-outline' },
  { value: 'briefcase-outline', label: 'Business', icon: 'briefcase-outline' },
  {
    value: 'dots-horizontal-circle-outline',
    label: 'Other',
    icon: 'dots-horizontal-circle-outline',
  },
];

export const ACCOUNT_COLOR_OPTIONS = ACCOUNT_COLOR_SWATCHES;

export type AccountIconSource = Pick<Account, 'type'> & Partial<Pick<Account, 'icon' | 'color'>>;

export type AccountIconVisual = {
  icon: AppIconName;
  iconLabel: string;
  backgroundColor: string;
  iconColor: string;
};

export function accountTypeLabel(type: AccountType): string {
  return ACCOUNT_TYPE_OPTIONS.find((option) => option.value === type)?.label ?? type;
}

export function accountIconForType(type: AccountType): AppIconName {
  return ACCOUNT_TYPE_OPTIONS.find((option) => option.value === type)?.icon ?? 'wallet-outline';
}

export function accountIconLabel(icon?: string | null): string {
  const resolvedIcon = resolveAppIconName(icon, 'wallet-outline');
  return (
    ACCOUNT_ICON_OPTIONS.find((option) => option.value === resolvedIcon)?.label ??
    readableIconName(resolvedIcon)
  );
}

export function resolveAccountIconVisual(
  account?: AccountIconSource | null,
  fallbackColor = DEFAULT_ACCOUNT_COLOR,
): AccountIconVisual {
  const icon = account
    ? resolveAppIconName(account.icon, accountIconForType(account.type))
    : 'wallet-outline';
  const iconSurface = solidIconSurfaceForColor(account?.color, fallbackColor);
  return {
    icon,
    iconLabel: accountIconLabel(icon),
    backgroundColor: iconSurface.backgroundColor,
    iconColor: iconSurface.iconColor,
  };
}

function readableIconName(icon: AppIconName) {
  return icon
    .replace(/-outline$/u, '')
    .replace(/-/gu, ' ')
    .replace(/\b\w/gu, (letter) => letter.toUpperCase());
}
