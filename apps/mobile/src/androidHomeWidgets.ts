import { formatMoney } from '@1wallet/domain/money';
import type { Transaction } from '@1wallet/domain/types';
import {
    cashflow,
    convertMoneyForDisplay,
    displayCurrency,
    totalBalance,
} from '@1wallet/ledger/services';
import type { LedgerState } from '@1wallet/ledger/store/types';
import { NativeModules, Platform } from 'react-native';
import { transactionTypeLabel } from './transactionTypes';

type AndroidHomeWidgetPayload = {
  balance: string;
  subtitle: string;
  upcoming: string;
  review: string;
  rules: string;
  updatedAt: string;
};

type OneWalletWidgetModule = {
  hasWidgets?: () => Promise<boolean>;
  update?: (payload: AndroidHomeWidgetPayload) => Promise<void> | void;
};

export function isAndroidHomeWidgetSyncAvailable(): boolean {
  return Platform.OS === 'android' && Boolean(widgetModule()?.update);
}

export async function syncAndroidHomeWidgets(state: LedgerState): Promise<void> {
  const module = widgetModule();
  if (Platform.OS !== 'android' || !module?.update) return;
  if (module.hasWidgets && !(await module.hasWidgets())) return;

  const viewCurrency = displayCurrency(state);
  const total = totalBalance(state, viewCurrency);
  const monthFlow = cashflow(state);
  const net = convertMoneyForDisplay(state, monthFlow.net, viewCurrency);
  const nextScheduled = nextPlannedTransaction(state);
  const pendingReview = state.captureCandidates.filter(
    (candidate) => candidate.status === 'pending',
  ).length;
  const activeRules = (state.preferences.futureGenerationRules ?? []).filter(
    (rule) => rule.enabled,
  ).length;

  await module.update({
    balance: formatMoney(total, state.preferences.locale),
    subtitle: `${formatMoney(net, state.preferences.locale)} net this month`,
    upcoming: nextScheduled ? upcomingLabel(state, nextScheduled) : 'No planned payments',
    review: pendingReview
      ? `${pendingReview} capture${pendingReview === 1 ? '' : 's'} need review`
      : 'Review queue clear',
    rules: activeRules
      ? `${activeRules} active future rule${activeRules === 1 ? '' : 's'}`
      : 'No active rules',
    updatedAt: updatedAtLabel(),
  });
}

function widgetModule(): OneWalletWidgetModule | undefined {
  return NativeModules.OneWalletWidget as OneWalletWidgetModule | undefined;
}

function nextPlannedTransaction(state: LedgerState): Transaction | undefined {
  const now = Date.now();
  return state.transactions
    .filter(
      (transaction) =>
        transaction.status === 'scheduled' && new Date(transaction.occurredAt).getTime() >= now,
    )
    .sort((left, right) => left.occurredAt.localeCompare(right.occurredAt))[0];
}

function upcomingLabel(state: LedgerState, transaction: Transaction): string {
  const label =
    transaction.notes?.trim() ||
    transaction.paymentMethod ||
    transactionTypeLabel(transaction.type);
  return `${label}: ${formatMoney(transaction.amount, state.preferences.locale)} ${dueLabel(transaction.occurredAt)}`;
}

function dueLabel(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

function updatedAtLabel(): string {
  return `Updated ${new Date().toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' })}`;
}
