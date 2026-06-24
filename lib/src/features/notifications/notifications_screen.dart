import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/ledger_providers.dart';
import '../../widgets/app_kit.dart';
import '../common/route_scaffold.dart';
import 'notification_engine.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  Future<void> _markRead(String id, {bool read = true}) async {
    final prefs = ref.read(ledgerProvider).preferences;
    final nextRead = Set<String>.from(prefs.readNotificationIds);
    if (read) {
      nextRead.add(id);
    } else {
      nextRead.remove(id);
    }
    await ref
        .read(ledgerProvider.notifier)
        .updatePreferences(
          prefs.copyWith(readNotificationIds: nextRead.toList()..sort()),
        );
  }

  Future<void> _dismiss(String id) async {
    final prefs = ref.read(ledgerProvider).preferences;
    final nextDismissed = Set<String>.from(prefs.dismissedNotificationIds)
      ..add(id);
    final nextRead = Set<String>.from(prefs.readNotificationIds)..remove(id);
    await ref
        .read(ledgerProvider.notifier)
        .updatePreferences(
          prefs.copyWith(
            dismissedNotificationIds: nextDismissed.toList()..sort(),
            readNotificationIds: nextRead.toList()..sort(),
          ),
        );
  }

  Future<void> _markAllRead(Iterable<AppNotification> notifications) async {
    final prefs = ref.read(ledgerProvider).preferences;
    final nextRead = Set<String>.from(prefs.readNotificationIds)
      ..addAll(notifications.map((notification) => notification.id));
    await ref
        .read(ledgerProvider.notifier)
        .updatePreferences(
          prefs.copyWith(readNotificationIds: nextRead.toList()..sort()),
        );
  }

  Future<void> _dismissAll(Iterable<AppNotification> notifications) async {
    final prefs = ref.read(ledgerProvider).preferences;
    final nextDismissed = Set<String>.from(prefs.dismissedNotificationIds)
      ..addAll(notifications.map((notification) => notification.id));
    final nextRead = Set<String>.from(prefs.readNotificationIds)
      ..removeAll(notifications.map((notification) => notification.id));
    await ref
        .read(ledgerProvider.notifier)
        .updatePreferences(
          prefs.copyWith(
            dismissedNotificationIds: nextDismissed.toList()..sort(),
            readNotificationIds: nextRead.toList()..sort(),
          ),
        );
  }

  void _openNotification(AppNotification notification) {
    _markRead(notification.id);
    final actionRoute = notification.actionRoute;
    if (actionRoute == null || actionRoute.trim().isEmpty) return;
    context.push(actionRoute);
  }

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(ledgerProvider);
    final allNotifications = buildNotificationInbox(ledger);
    final unreadCount = allNotifications
        .where((notification) => !notification.read)
        .length;

    return RouteScaffold(
      title: 'Notifications',
      actions: [
        if (unreadCount > 0)
          IconButton(
            tooltip: 'Mark all read',
            onPressed: () => _markAllRead(allNotifications),
            icon: const Icon(Icons.mark_email_read_outlined),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: 'Inbox',
            subtitle:
                '$unreadCount unread · ${allNotifications.length} active item${allNotifications.length == 1 ? '' : 's'}',
            actionLabel: allNotifications.isEmpty ? null : 'Dismiss all',
            onAction: allNotifications.isEmpty
                ? null
                : () => _dismissAll(allNotifications),
            child: allNotifications.isEmpty
                ? const EmptyState(
                    icon: Icons.notifications_off_outlined,
                    title: 'Nothing waiting',
                    body: 'Budget, goal, and schedule alerts will appear here.',
                  )
                : Column(
                    children: [
                      for (final notification in allNotifications)
                        _NotificationRow(
                          notification: notification,
                          read: notification.read,
                          onOpen: () => _openNotification(notification),
                          onDismiss: () => _dismiss(notification.id),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.notification,
    required this.read,
    required this.onOpen,
    required this.onDismiss,
  });

  final AppNotification notification;
  final bool read;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = switch (notification.channel) {
      AppNotificationChannel.scheduled => Icons.event_repeat_outlined,
      AppNotificationChannel.budgets => Icons.donut_large_outlined,
      AppNotificationChannel.goals => Icons.flag_outlined,
    };

    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Icon(
          Icons.archive_outlined,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      child: Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: read
            ? theme.colorScheme.surfaceContainerLow
            : theme.colorScheme.primaryContainer.withAlpha(130),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            child: Icon(icon, color: theme.colorScheme.primary),
          ),
          title: Text(
            notification.title,
            style: TextStyle(
              fontWeight: read ? FontWeight.w600 : FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${notification.body}\n${_relativeDate(notification.createdAt)}',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          trailing: read
              ? null
              : Icon(
                  Icons.fiber_manual_record,
                  size: 10,
                  color: theme.colorScheme.primary,
                ),
          onTap: onOpen,
        ),
      ),
    );
  }
}

String _relativeDate(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
