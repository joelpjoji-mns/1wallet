import '../../data/ledger_models.dart';
import '../../ledger/ledger_selectors.dart';

/// Notification channels matching the React Native notification system.
enum AppNotificationChannel { scheduled, budgets, goals }

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
      AppNotificationChannel.budgets:
          (raw['channels'] as Map<String, dynamic>?)?['budgets'] as bool? ??
          true,
      AppNotificationChannel.goals:
          (raw['channels'] as Map<String, dynamic>?)?['goals'] as bool? ?? true,
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
/// Generates notifications for:
/// - Overdue scheduled payments
/// - Budget overspend
/// - Goal progress
List<AppNotification> buildNotificationInbox(LedgerState state) {
  final notifications = <AppNotification>[];
  final now = DateTime.now();

  // Scheduled payment notifications
  final scheduled = scheduledTransactions(state);
  for (final transaction in scheduled) {
    if (transaction.occurredAt.isBefore(now)) {
      notifications.add(
        AppNotification(
          id: 'scheduled_${transaction.id}',
          channel: AppNotificationChannel.scheduled,
          title:
              'Overdue: ${transaction.notes ?? transactionTypeLabel(transaction.type)}',
          body:
              '${formatMoney(transaction.amount, state.preferences.locale)} was due ${_relativeDate(transaction.occurredAt, now)}.',
          createdAt: transaction.occurredAt,
          actionRoute: '/recurring/${transaction.id}',
        ),
      );
    } else if (transaction.occurredAt.difference(now).inDays <= 3) {
      notifications.add(
        AppNotification(
          id: 'upcoming_${transaction.id}',
          channel: AppNotificationChannel.scheduled,
          title:
              'Upcoming: ${transaction.notes ?? transactionTypeLabel(transaction.type)}',
          body:
              '${formatMoney(transaction.amount, state.preferences.locale)} due ${_relativeDate(transaction.occurredAt, now)}.',
          createdAt: now,
          actionRoute: '/recurring/${transaction.id}',
        ),
      );
    }
  }

  // Budget overspend notifications
  for (final budget in state.budgets) {
    final spentMinor = budget.spent.amountMinor;
    final limitMinor = budget.amount.amountMinor;
    if (limitMinor <= 0) continue;
    if (spentMinor > limitMinor) {
      final overspend = spentMinor - limitMinor;
      notifications.add(
        AppNotification(
          id: 'budget_${budget.id}',
          channel: AppNotificationChannel.budgets,
          title: '${budget.name} over budget',
          body:
              'Overspent by ${formatMoney(Money(amountMinor: overspend, currency: budget.amount.currency), state.preferences.locale)}.',
          createdAt: now,
        ),
      );
    } else if (spentMinor > limitMinor * 0.8) {
      final pct = ((spentMinor / limitMinor) * 100).round();
      notifications.add(
        AppNotification(
          id: 'budget_warn_${budget.id}',
          channel: AppNotificationChannel.budgets,
          title: '${budget.name} nearing limit',
          body: '$pct% of budget used.',
          createdAt: now,
        ),
      );
    }
  }

  // Goal progress notifications
  for (final goal in state.goals) {
    final targetMinor = goal.target.amountMinor;
    final savedMinor = goal.saved.amountMinor;
    if (targetMinor <= 0) continue;
    final progress = savedMinor / targetMinor;
    if (progress >= 1.0) {
      notifications.add(
        AppNotification(
          id: 'goal_done_${goal.id}',
          channel: AppNotificationChannel.goals,
          title: '${goal.name} complete! 🎉',
          body: 'You reached your savings goal.',
          createdAt: now,
        ),
      );
    } else if (progress >= 0.75) {
      notifications.add(
        AppNotification(
          id: 'goal_almost_${goal.id}',
          channel: AppNotificationChannel.goals,
          title: '${goal.name} almost there',
          body: '${(progress * 100).round()}% of goal reached.',
          createdAt: now,
        ),
      );
    }
  }

  notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return notifications;
}

/// Count of unread notifications.
int unreadNotificationCount(LedgerState state) {
  return buildNotificationInbox(state).where((n) => !n.read).length;
}

String _relativeDate(DateTime date, DateTime now) {
  final diff = now.difference(date);
  if (diff.inDays == 0) return 'today';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 0) {
    final futureDays = diff.inDays.abs();
    if (futureDays == 1) return 'tomorrow';
    return 'in $futureDays days';
  }
  return '${diff.inDays} days ago';
}
