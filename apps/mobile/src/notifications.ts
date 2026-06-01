import { formatMoney } from '@1wallet/domain/money';
import type { Account, Transaction } from '@1wallet/domain/types';
import { budgetStatuses, goalStatuses } from '@1wallet/ledger/services';
import type { LedgerState, NotificationPreferences } from '@1wallet/ledger/store/types';
import { defaultNotificationPreferences } from '@1wallet/ledger/store/types';
import type { AppIconName } from './components/AppKit';
import { transactionTypeLabel } from './transactionTypes';

export type AppNotificationSeverity = 'critical' | 'warning' | 'info' | 'success';
export type AppNotificationChannel =
  | 'reviewQueue'
  | 'scheduled'
  | 'budgets'
  | 'goals'
  | 'accounts'
  | 'imports';

export type AppNotificationTarget =
  | { type: 'route'; route: string }
  | { type: 'account'; accountId: string }
  | { type: 'transaction'; transactionId: string };

export interface AppNotification {
  id: string;
  channel: AppNotificationChannel;
  severity: AppNotificationSeverity;
  icon: AppIconName;
  title: string;
  body: string;
  createdAt: string;
  dueAt?: string;
  badges: string[];
  target: AppNotificationTarget;
  read: boolean;
  snoozedUntil?: string;
}

type NotificationDraft = Omit<AppNotification, 'read' | 'snoozedUntil'>;

const SEVERITY_RANK: Record<AppNotificationSeverity, number> = {
  critical: 0,
  warning: 1,
  info: 2,
  success: 3,
};

const CHANNEL_LABELS: Record<AppNotificationChannel, string> = {
  reviewQueue: 'Review',
  scheduled: 'Due',
  budgets: 'Budget',
  goals: 'Goal',
  accounts: 'Account',
  imports: 'Import',
};

export function normalizeNotificationPreferences(
  preferences?: Partial<NotificationPreferences>,
): NotificationPreferences {
  const defaults = defaultNotificationPreferences();
  return {
    ...defaults,
    ...(preferences ?? {}),
    channels: {
      ...defaults.channels,
      ...(preferences?.channels ?? {}),
    },
    quietHours: {
      ...defaults.quietHours,
      ...(preferences?.quietHours ?? {}),
    },
    readIds: preferences?.readIds ?? [],
    dismissedIds: preferences?.dismissedIds ?? [],
    nativeDeliveredIds: preferences?.nativeDeliveredIds ?? [],
    snoozedUntilById: preferences?.snoozedUntilById ?? {},
  };
}

export function buildNotificationInbox(state: LedgerState, now = new Date()): AppNotification[] {
  const preferences = normalizeNotificationPreferences(state.preferences.notifications);
  if (!preferences.enabled) return [];

  const drafts: NotificationDraft[] = [];
  const nowIso = now.toISOString();

  if (preferences.channels.reviewQueue) {
    drafts.push(...reviewQueueNotifications(state));
  }
  if (preferences.channels.scheduled) {
    drafts.push(...scheduledNotifications(state, now));
  }
  if (preferences.channels.budgets) {
    drafts.push(...budgetNotifications(state, nowIso));
  }
  if (preferences.channels.goals) {
    drafts.push(...goalNotifications(state, now));
  }
  if (preferences.channels.accounts) {
    drafts.push(...accountNotifications(state, nowIso));
  }
  if (preferences.channels.imports) {
    drafts.push(...importNotifications(state));
  }

  const readIds = new Set(preferences.readIds);
  const dismissedIds = new Set(preferences.dismissedIds);

  return drafts
    .filter((notification) => !dismissedIds.has(notification.id))
    .map((notification) => ({
      ...notification,
      read: readIds.has(notification.id),
      snoozedUntil: preferences.snoozedUntilById[notification.id],
    }))
    .filter((notification) => !isSnoozed(notification, now))
    .sort(compareNotifications);
}

export function unreadNotificationCount(state: LedgerState, now = new Date()): number {
  return buildNotificationInbox(state, now).filter((notification) => !notification.read).length;
}

export function notificationChannelLabel(channel: AppNotificationChannel): string {
  return CHANNEL_LABELS[channel];
}

export function markAllNotificationsRead(
  state: LedgerState,
  notifications: readonly AppNotification[],
) {
  const preferences = normalizeNotificationPreferences(state.preferences.notifications);
  const nextIds = new Set(preferences.readIds);
  for (const notification of notifications) nextIds.add(notification.id);
  state.preferences.notifications = { ...preferences, readIds: Array.from(nextIds) };
}

export function markNotificationRead(state: LedgerState, notificationId: string, read = true) {
  const preferences = normalizeNotificationPreferences(state.preferences.notifications);
  const nextIds = new Set(preferences.readIds);
  if (read) nextIds.add(notificationId);
  else nextIds.delete(notificationId);
  state.preferences.notifications = { ...preferences, readIds: Array.from(nextIds) };
}

export function dismissNotification(state: LedgerState, notificationId: string) {
  const preferences = normalizeNotificationPreferences(state.preferences.notifications);
  const dismissedIds = new Set(preferences.dismissedIds);
  dismissedIds.add(notificationId);
  state.preferences.notifications = { ...preferences, dismissedIds: Array.from(dismissedIds) };
}

export function dismissAllNotifications(
  state: LedgerState,
  notifications: readonly AppNotification[],
) {
  const preferences = normalizeNotificationPreferences(state.preferences.notifications);
  const dismissedIds = new Set(preferences.dismissedIds);
  for (const notification of notifications) dismissedIds.add(notification.id);
  state.preferences.notifications = { ...preferences, dismissedIds: Array.from(dismissedIds) };
}

export function snoozeNotification(state: LedgerState, notificationId: string, until: Date) {
  const preferences = normalizeNotificationPreferences(state.preferences.notifications);
  state.preferences.notifications = {
    ...preferences,
    snoozedUntilById: {
      ...preferences.snoozedUntilById,
      [notificationId]: until.toISOString(),
    },
  };
}

function reviewQueueNotifications(state: LedgerState): NotificationDraft[] {
  const pending = state.captureCandidates.filter((candidate) => candidate.status === 'pending');
  if (pending.length === 0) return [];

  const warningCount = pending.reduce(
    (sum, candidate) => sum + (candidate.warnings?.length ?? 0),
    0,
  );
  const newest = pending.reduce(
    (latest, candidate) => (candidate.createdAt > latest ? candidate.createdAt : latest),
    pending[0]?.createdAt ?? new Date().toISOString(),
  );

  return [
    {
      id: `review:${pending.length}:${warningCount}`,
      channel: 'reviewQueue',
      severity: warningCount > 0 ? 'warning' : 'info',
      icon: warningCount > 0 ? 'robot-confused-outline' : 'robot-outline',
      title: `${pending.length} capture${pending.length === 1 ? '' : 's'} need review`,
      body:
        warningCount > 0
          ? `${warningCount} warning${warningCount === 1 ? '' : 's'} need a quick look before posting.`
          : 'Approve imported, notification, email, or API captures before they hit the ledger.',
      createdAt: newest,
      badges: ['Review queue', `${pending.length} pending`],
      target: { type: 'route', route: '/review' },
    },
  ];
}

function scheduledNotifications(state: LedgerState, now: Date): NotificationDraft[] {
  const sevenDaysFromNow = addDays(startOfDay(now), 7);
  return state.transactions
    .filter((transaction) => transaction.status === 'scheduled')
    .filter((transaction) => {
      const due = parseDate(transaction.occurredAt);
      return Boolean(due && due < sevenDaysFromNow);
    })
    .sort((left, right) => left.occurredAt.localeCompare(right.occurredAt))
    .slice(0, 8)
    .map((transaction) => {
      const account = state.accounts.find((item) => item.id === transaction.accountId);
      const counterAccount = state.accounts.find(
        (item) => item.id === transaction.counterAccountId,
      );
      const due = parseDate(transaction.occurredAt) ?? now;
      const overdue = startOfDay(due) < startOfDay(now);
      const dueToday = sameDay(due, now);
      return {
        id: `scheduled:${transaction.id}`,
        channel: 'scheduled' as const,
        severity: overdue ? 'critical' : dueToday ? 'warning' : 'info',
        icon: overdue ? 'calendar-alert' : 'calendar-clock-outline',
        title: `${typeLabel(transaction.type)} ${overdue ? 'overdue' : dueToday ? 'due today' : 'coming up'}`,
        body: scheduledNotificationBody(state, transaction, account, counterAccount, due, now),
        createdAt: transaction.updatedAt ?? transaction.createdAt,
        dueAt: transaction.occurredAt,
        badges: [
          'Scheduled',
          formatDueDate(due, now),
          transaction.paymentMethod === 'Auto debit' ? 'Auto debit' : undefined,
        ].filter((badge): badge is string => Boolean(badge)),
        target: { type: 'transaction' as const, transactionId: transaction.id },
      };
    });
}

function scheduledNotificationBody(
  state: LedgerState,
  transaction: Transaction,
  account: Account | undefined,
  counterAccount: Account | undefined,
  due: Date,
  now: Date,
): string {
  const amount = formatMoney(transaction.amount, state.preferences.locale);
  const dueLabel = formatDueDate(due, now);
  if (transaction.type === 'card_payment') {
    return `${amount} card payment from ${account?.name ?? 'account'} to ${counterAccount?.name ?? 'card'} ${dueLabel}.`;
  }
  if (transaction.type === 'loan_repayment') {
    return `${amount} EMI from ${account?.name ?? 'account'} to ${counterAccount?.name ?? 'loan'} ${dueLabel}.`;
  }
  if (transaction.type === 'transfer') {
    return `${amount} transfer from ${account?.name ?? 'account'} to ${counterAccount?.name ?? 'destination'} ${dueLabel}.`;
  }
  return `${amount} from ${account?.name ?? 'account'} ${dueLabel}.`;
}

function budgetNotifications(state: LedgerState, nowIso: string): NotificationDraft[] {
  const statuses = budgetStatuses(state);
  return statuses.flatMap((status) => {
    const budget = state.budgets.find((item) => item.id === status.budgetId);
    const thresholds = [
      ...(budget?.alertThresholds.length ? budget.alertThresholds : [80, 100]),
    ].sort((left, right) => left - right);
    const crossed = thresholds.filter((threshold) => status.share * 100 >= threshold).pop();
    if (!crossed) return [];

    return [
      {
        id: `budget:${status.budgetId}:${crossed}`,
        channel: 'budgets' as const,
        severity: status.isOver ? 'critical' : crossed >= 80 ? 'warning' : 'info',
        icon: status.isOver ? 'chart-timeline-variant-shimmer' : 'chart-timeline-variant',
        title: status.isOver ? budgetOverTitle(status.name) : `${status.name} hit ${crossed}%`,
        body: `${formatMoney(status.spent, state.preferences.locale)} spent of ${formatMoney(status.limit, state.preferences.locale)}. ${formatMoney(status.remaining, state.preferences.locale)} remaining.`,
        createdAt: nowIso,
        badges: ['Budget', `${Math.round(status.share * 100)}%`],
        target: { type: 'route' as const, route: '/widgets' },
      },
    ];
  });
}

function budgetOverTitle(name: string): string {
  return /\bbudget$/i.test(name.trim()) ? `${name} is over` : `${name} budget is over`;
}

function goalNotifications(state: LedgerState, now: Date): NotificationDraft[] {
  return goalStatuses(state, now).flatMap((status) => {
    const goal = state.goals.find((item) => item.id === status.goalId);
    if (!goal?.targetDate || status.share >= 1) return [];

    const targetDate = parseDate(goal.targetDate);
    if (!targetDate) return [];
    const days = dayDiff(now, targetDate);
    if (days > 30) return [];

    return [
      {
        id: `goal:${goal.id}:deadline`,
        channel: 'goals' as const,
        severity: days < 0 ? 'critical' : days <= 7 ? 'warning' : 'info',
        icon: days < 0 ? 'bullseye-arrow' : 'flag-checkered',
        title: days < 0 ? `${goal.name} goal is overdue` : `${goal.name} target is near`,
        body: `${Math.round(status.share * 100)}% saved toward ${formatMoney(status.target, state.preferences.locale)}. Target ${formatDueDate(targetDate, now)}.`,
        createdAt: now.toISOString(),
        dueAt: targetDate.toISOString(),
        badges: ['Goal', `${Math.round(status.share * 100)}%`],
        target: { type: 'route' as const, route: '/widgets' },
      },
    ];
  });
}

function accountNotifications(state: LedgerState, nowIso: string): NotificationDraft[] {
  const notifications: NotificationDraft[] = [];
  const activeAccounts = state.accounts.filter((account) => !account.isArchived);
  const creditCards = activeAccounts.filter((account) => account.type === 'credit_card');
  const creditDebt = creditCards.reduce((sum, card) => {
    const balance = accountBalanceForNotification(state, card);
    return sum + Math.min(balance, 0);
  }, 0);

  if (creditDebt < 0) {
    notifications.push({
      id: 'cards:debt-summary',
      channel: 'accounts',
      severity: 'warning',
      icon: 'credit-card-clock-outline',
      title: 'Credit card balance waiting',
      body: `${formatMoney({ amountMinor: Math.abs(creditDebt), currency: state.preferences.baseCurrency }, state.preferences.locale)} across ${creditCards.length} card${creditCards.length === 1 ? '' : 's'}.`,
      createdAt: nowIso,
      badges: ['Cards', `${creditCards.length} active`],
      target: { type: 'route', route: '/cards' },
    });
  }

  for (const account of activeAccounts) {
    if (account.type === 'credit_card' || account.type === 'loan') continue;
    const balance = accountBalanceForNotification(state, account);
    if (balance >= 0) continue;
    notifications.push({
      id: `account:${account.id}:negative`,
      channel: 'accounts',
      severity: 'critical',
      icon: account.type === 'bank' ? 'bank-outline' : 'wallet-outline',
      title: `${account.name} is negative`,
      body: `${formatMoney({ amountMinor: balance, currency: account.currency }, state.preferences.locale)} current balance.`,
      createdAt: nowIso,
      badges: ['Account', account.currency],
      target: { type: 'account', accountId: account.id },
    });
  }

  return notifications.slice(0, 8);
}

function importNotifications(state: LedgerState): NotificationDraft[] {
  return state.importBatches
    .filter((batch) => batch.warningCount > 0 || batch.duplicateCount > 0)
    .slice(0, 5)
    .map((batch) => ({
      id: `import:${batch.id}:warnings`,
      channel: 'imports' as const,
      severity: batch.warningCount > 0 ? 'warning' : 'info',
      icon: batch.warningCount > 0 ? 'file-alert-outline' : 'file-check-outline',
      title: `${batch.name} needs review`,
      body: `${batch.warningCount} warning${batch.warningCount === 1 ? '' : 's'}, ${batch.duplicateCount} duplicate${batch.duplicateCount === 1 ? '' : 's'}, ${batch.candidateCount} candidate${batch.candidateCount === 1 ? '' : 's'}.`,
      createdAt: batch.updatedAt,
      badges: [batch.status.replace(/_/g, ' ')],
      target: { type: 'route' as const, route: '/imports' },
    }));
}

function accountBalanceForNotification(state: LedgerState, account: Account): number {
  let balance = account.openingBalance.amountMinor;
  for (const transaction of state.transactions) {
    if (transaction.status === 'scheduled' || transaction.status === 'void') continue;
    if (transaction.accountId === account.id) {
      balance += signedAmountForAccount(transaction, 'primary');
    }
    if (transaction.counterAccountId === account.id) {
      balance += signedAmountForAccount(transaction, 'counter');
    }
  }
  return balance;
}

function signedAmountForAccount(transaction: Transaction, side: 'primary' | 'counter'): number {
  if (side === 'counter') return transaction.amount.amountMinor;
  switch (transaction.type) {
    case 'income':
    case 'refund':
    case 'interest_in':
    case 'cashback':
    case 'borrowed':
    case 'investment_sell':
      return transaction.amount.amountMinor;
    case 'adjustment':
      return transaction.amount.amountMinor;
    default:
      return -transaction.amount.amountMinor;
  }
}

function compareNotifications(left: AppNotification, right: AppNotification): number {
  const severity = SEVERITY_RANK[left.severity] - SEVERITY_RANK[right.severity];
  if (severity !== 0) return severity;
  const leftTime = left.dueAt ?? left.createdAt;
  const rightTime = right.dueAt ?? right.createdAt;
  return rightTime.localeCompare(leftTime);
}

function isSnoozed(notification: AppNotification, now: Date): boolean {
  if (!notification.snoozedUntil) return false;
  const snoozedUntil = parseDate(notification.snoozedUntil);
  return Boolean(snoozedUntil && snoozedUntil > now);
}

function parseDate(value: string): Date | undefined {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? undefined : date;
}

function addDays(date: Date, days: number): Date {
  const next = new Date(date);
  next.setDate(next.getDate() + days);
  return next;
}

function startOfDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function sameDay(left: Date, right: Date): boolean {
  return startOfDay(left).getTime() === startOfDay(right).getTime();
}

function dayDiff(from: Date, to: Date): number {
  return Math.round((startOfDay(to).getTime() - startOfDay(from).getTime()) / 86400000);
}

function formatDueDate(date: Date, now: Date): string {
  const days = dayDiff(now, date);
  if (days < 0) return `${Math.abs(days)} day${Math.abs(days) === 1 ? '' : 's'} overdue`;
  if (days === 0) return 'today';
  if (days === 1) return 'tomorrow';
  if (days < 7) return `in ${days} days`;
  return date
    .toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })
    .replace(',', '')
    .toLowerCase();
}

function typeLabel(type: Transaction['type']): string {
  return transactionTypeLabel(type);
}
