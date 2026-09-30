import '../../data/ledger_models.dart';
import '../../ledger/ledger_selectors.dart';

/// Notification channels matching the React Native notification system.
enum AppNotificationChannel { scheduled }

/// Preferences for the notification system.
class NotificationPreferences {
  const NotificationPreferences({
    this.enabled = true,
    this.pushEnabled = false,
    this.quietHours = const QuietHours(),
    this.channels = const {},
    this.nativeDeliveredIds = const [],
  });

  final bool enabled;
  final bool pushEnabled;
  final QuietHours quietHours;
  final Map<AppNotificationChannel, bool> channels;
  final List<String> nativeDeliveredIds;

  bool channelEnabled(AppNotificationChannel channel) {
    return channels[channel] ?? true;
  }
}

/// Quiet hours configuration.
class QuietHours {
  const QuietHours({
    this.enabled = false,
    this.start = '22:00',
    this.end = '07:00',
  });

  final bool enabled;
  final String start;
  final String end;
}

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
  });

  final String id;
  final AppNotificationChannel channel;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;
  final String? actionRoute;
}

/// Normalizes notification preferences from raw ledger state.
NotificationPreferences normalizeNotificationPreferences(
  Map<String, dynamic>? raw,
) {
  if (raw == null) return const NotificationPreferences();
  return NotificationPreferences(
    enabled: raw['enabled'] as bool? ?? true,
    pushEnabled: raw['pushEnabled'] as bool? ?? false,
    quietHours: QuietHours(
      enabled:
          (raw['quietHours'] as Map<String, dynamic>?)?['enabled'] as bool? ??
          false,
      start:
          (raw['quietHours'] as Map<String, dynamic>?)?['start'] as String? ??
          '22:00',
      end:
          (raw['quietHours'] as Map<String, dynamic>?)?['end'] as String? ??
          '07:00',
    ),
    channels: {
      AppNotificationChannel.scheduled:
          (raw['channels'] as Map<String, dynamic>?)?['scheduled'] as bool? ??
          true,
    },
    nativeDeliveredIds:
        ((raw['nativeDeliveredIds'] as List?)
            ?.map((id) => id.toString())
            .toList()) ??
        const [],
  );
}

/// Builds the notification inbox from ledger state.
///
/// - Overdue scheduled payments
List<AppNotification> buildNotificationInbox(LedgerState state, {DateTime? now}) {
  final notifications = <AppNotification>[];
  final currentTime = now ?? DateTime.now();

  // The master "Notification inbox" toggle disables the in-app inbox
  // entirely (native/device alerts are gated separately in
  // NotificationService using deviceNotificationsEnabled).
  if (!state.preferences.notificationInboxEnabled) {
    return const [];
  }

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

  // Credit card due / overdue notifications
  for (final account in state.accounts) {
    final status = creditCardDueStatus(state, account, now: currentTime);
    if (status == null || status.isPaid) continue;

    final balance = accountBalance(state, account);
    final balanceText = formatMoney(
      convertMoneyForDisplay(state, balance),
      state.preferences.locale,
    );

    final todayKey =
        '${currentTime.year}-${currentTime.month.toString().padLeft(2, '0')}-${currentTime.day.toString().padLeft(2, '0')}';

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
        ),
      )
      .toList();

  filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return filtered;
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
