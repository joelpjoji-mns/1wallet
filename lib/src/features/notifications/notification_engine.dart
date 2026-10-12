import '../../data/ledger_models.dart';
import '../../ledger/ledger_selectors.dart';

/// Notification channels matching the React Native notification system.
enum AppNotificationChannel { scheduled }

/// A notification item in the inbox.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.channel,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
    this.actionRoute,
    this.accountId,
    this.cycleKey,
    this.amount,
    this.badgeLabel,
    this.isOverdue = false,
    this.isDueSoon = false,
  });

  final String id;
  final AppNotificationChannel channel;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;
  final String? actionRoute;
  final String? accountId;
  final String? cycleKey;
  final Money? amount;
  final String? badgeLabel;
  final bool isOverdue;
  final bool isDueSoon;
}

final Expando<Map<String, List<AppNotification>>> _inboxCacheExpando =
    Expando<Map<String, List<AppNotification>>>('buildNotificationInboxCache');

/// Builds the notification inbox from ledger state.
///
/// - Overdue scheduled payments
List<AppNotification> buildNotificationInbox(LedgerState state, {DateTime? now}) {
  // The master "Notification inbox" toggle disables the in-app inbox
  // entirely (native/device alerts are gated separately in
  // NotificationService using deviceNotificationsEnabled).
  if (!state.preferences.notificationInboxEnabled) {
    return const [];
  }

  final currentTime = now ?? DateTime.now();
  final todayKey =
      '${currentTime.year}-${currentTime.month.toString().padLeft(2, '0')}-${currentTime.day.toString().padLeft(2, '0')}';

  if (now == null) {
    final cachedByDay = _inboxCacheExpando[state];
    final cached = cachedByDay?[todayKey];
    if (cached != null) {
      return cached;
    }
  }

  final notifications = <AppNotification>[];

  // Scheduled payment notifications
  if (state.preferences.channelScheduledEnabled) {
    final today = DateTime(currentTime.year, currentTime.month, currentTime.day);
    for (final transaction in scheduledTransactions(
      state,
    ).where((t) => t.status == 'scheduled')) {
      final txDay = DateTime(
        transaction.occurredAt.year,
        transaction.occurredAt.month,
        transaction.occurredAt.day,
      );
      final daysDiff = txDay.difference(today).inDays;

      if (daysDiff < 0) {
        final when = daysDiff == -1 ? 'yesterday' : '${-daysDiff} days ago';
        notifications.add(
          AppNotification(
            id: 'scheduled_overdue_${transaction.id}',
            channel: AppNotificationChannel.scheduled,
            title:
                'Overdue: ${transaction.notes ?? transactionTypeLabel(transaction.type)}',
            body: _dueBody(
              state: state,
              amount: transaction.amount,
              when: when,
            ),
            createdAt: transaction.occurredAt,
            actionRoute: '/recurring/${transaction.id}',
          ),
        );
      } else if (daysDiff <= 14) {
        final String when;
        if (daysDiff == 0) {
          when = 'today';
        } else if (daysDiff == 1) {
          when = 'tomorrow';
        } else {
          when = 'in $daysDiff days';
        }
        notifications.add(
          AppNotification(
            id: 'scheduled_soon_${transaction.id}',
            channel: AppNotificationChannel.scheduled,
            title:
                'Upcoming: ${transaction.notes ?? transactionTypeLabel(transaction.type)}',
            body: _dueBody(
              state: state,
              amount: transaction.amount,
              when: when,
            ),
            createdAt: currentTime,
            actionRoute: '/recurring/${transaction.id}',
          ),
        );
      }
    }
  }

  // Credit card due / overdue / statement notifications
  for (final account in state.accounts) {
    final status = creditCardDueStatus(state, account, now: currentTime);
    if (status == null || status.isPaid) continue;

    final balance = accountBalance(state, account);
    final absBalance = Money(
      amountMinor: balance.amountMinor.abs(),
      currency: balance.currency,
    );
    final balanceText = formatMoney(
      convertMoneyForDisplay(state, absBalance),
      state.preferences.locale,
    );

    if (status.isOverdue) {
      final when = status.daysUntilDue == -1
          ? 'yesterday'
          : '${-status.daysUntilDue} days ago';
      notifications.add(
        AppNotification(
          id: 'card_overdue_${account.id}_$todayKey',
          channel: AppNotificationChannel.scheduled,
          title: 'Bill overdue: ${account.name}',
          body: state.preferences.privacyModeEnabled
              ? 'Credit card bill was due $when.'
              : 'Payment of $balanceText was due $when.',
          createdAt: status.dueDate,
          actionRoute: '/cards',
          accountId: account.id,
          cycleKey: status.cycleKey,
          amount: absBalance,
          badgeLabel: status.daysUntilDue == -1
              ? 'Overdue yesterday'
              : 'Overdue ${-status.daysUntilDue}d',
          isOverdue: true,
        ),
      );
    } else if (status.isDueSoon) {
      final when = status.daysUntilDue == 0
          ? 'today'
          : (status.daysUntilDue == 1
              ? 'tomorrow'
              : 'in ${status.daysUntilDue} days');
      notifications.add(
        AppNotification(
          id: 'card_due_${account.id}_$todayKey',
          channel: AppNotificationChannel.scheduled,
          title: 'Bill due soon: ${account.name}',
          body: state.preferences.privacyModeEnabled
              ? 'Credit card bill is due $when.'
              : 'Payment of $balanceText is due $when.',
          createdAt: currentTime,
          actionRoute: '/cards',
          accountId: account.id,
          cycleKey: status.cycleKey,
          amount: absBalance,
          badgeLabel: status.daysUntilDue == 0
              ? 'Due today'
              : (status.daysUntilDue == 1
                  ? 'Due tomorrow'
                  : 'Due in ${status.daysUntilDue}d'),
          isDueSoon: true,
        ),
      );
    } else if (status.isStatementGenerated) {
      final when = 'in ${status.daysUntilDue} days';
      notifications.add(
        AppNotification(
          id: 'card_statement_${account.id}_${status.cycleKey}_$todayKey',
          channel: AppNotificationChannel.scheduled,
          title: 'Statement ready: ${account.name}',
          body: state.preferences.privacyModeEnabled
              ? 'Monthly statement was generated (due $when).'
              : 'Monthly bill of $balanceText generated. Due $when.',
          createdAt: status.statementDate ?? currentTime,
          actionRoute: '/cards',
          accountId: account.id,
          cycleKey: status.cycleKey,
          amount: absBalance,
          badgeLabel: 'Bill ready',
        ),
      );
    }
  }

  final readIds = state.preferences.readNotificationIds.toSet();
  final dismissedIds = state.preferences.dismissedNotificationIds.toSet();

  final filtered = notifications
      .where((n) => !dismissedIds.contains(n.id))
      .map(
        (n) => AppNotification(
          id: n.id,
          channel: n.channel,
          title: n.title,
          body: n.body,
          createdAt: n.createdAt,
          read: readIds.contains(n.id),
          actionRoute: n.actionRoute,
          accountId: n.accountId,
          cycleKey: n.cycleKey,
          amount: n.amount,
          badgeLabel: n.badgeLabel,
          isOverdue: n.isOverdue,
          isDueSoon: n.isDueSoon,
        ),
      )
      .toList();

  filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final result = List<AppNotification>.unmodifiable(filtered);
  if (now == null) {
    _inboxCacheExpando[state] = {todayKey: result};
  }
  return result;
}

/// Count of unread notifications.
int unreadNotificationCount(LedgerState state) {
  return buildNotificationInbox(state).where((n) => !n.read).length;
}

String _dueBody({
  required LedgerState state,
  required Money amount,
  required String when,
}) {
  if (state.preferences.privacyModeEnabled) {
    return 'A scheduled payment is due $when.';
  }
  return '${formatMoney(amount, state.preferences.locale)} is due $when.';
}
