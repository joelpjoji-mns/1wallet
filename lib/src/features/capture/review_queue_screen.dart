import 'package:flutter/material.dart';
import '../../ledger/ledger_selectors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/privacy_text.dart';
import '../notifications/notification_engine.dart';

class ReviewQueueScreen extends ConsumerWidget {
  const ReviewQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ledgerProvider);
    final candidates = state.captureCandidates
        .where((candidate) => candidate.status == 'pending')
        .toList();
    final sources = candidates
        .map((candidate) => candidate.source)
        .toSet()
        .length;

    final allNotifications = buildNotificationInbox(state);
    final unreadCount = allNotifications
        .where((notification) => !notification.read)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review & Inbox'),
        actions: [
          IconButton(
            tooltip: 'Import SMS',
            icon: const Icon(Icons.sms_outlined),
            onPressed: () => context.push('/import-sms'),
          ),
          if (unreadCount > 0)
            IconButton(
              tooltip: 'Mark all read',
              onPressed: () => _markAllRead(ref, allNotifications),
              icon: const Icon(Icons.mark_email_read_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  SectionCard(
                    title: 'Automation queue',
                    subtitle:
                        'Imported SMS, OCR, CSV, and migration candidates before they post.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          alignment: WrapAlignment.spaceBetween,
                          children: [
                            SizedBox(
                              width: 140,
                              child: MetricTile(
                                label: 'Pending',
                                value: '${candidates.length}',
                                icon: Icons.fact_check_outlined,
                                compact: true,
                                tone: candidates.isEmpty
                                    ? MetricTone.standard
                                    : MetricTone.warning,
                              ),
                            ),
                            SizedBox(
                              width: 140,
                              child: MetricTile(
                                label: 'Sources',
                                value: '$sources',
                                icon: Icons.auto_awesome_outlined,
                                compact: true,
                              ),
                            ),
                          ],
                        ),
                        if (candidates.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.md),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              FilledButton.icon(
                                onPressed: () => _updateAllPending(
                                  context,
                                  ref,
                                  candidates.map((e) => e.id),
                                  'approved',
                                ),
                                icon: const Icon(Icons.done_all_outlined),
                                label: const Text('Approve all'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _updateAllPending(
                                  context,
                                  ref,
                                  candidates.map((e) => e.id),
                                  'rejected',
                                ),
                                icon: const Icon(Icons.clear_all_outlined),
                                label: const Text('Dismiss all'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Gap(AppSpacing.lg),
                  if (candidates.isEmpty)
                    const EmptyState(
                      icon: Icons.fact_check_outlined,
                      title: 'Nothing to review',
                      body:
                          'SMS, OCR, and CSV candidates will appear here before posting.',
                    ),
                ]),
              ),
            ),
            if (candidates.isNotEmpty)
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final candidate = candidates[index];
                  final theme = Theme.of(context);
                  final scheme = theme.colorScheme;
                  final isIncome = candidate.transactionType == 'income';
                  final colorScheme = isIncome
                      ? ColorScheme.fromSeed(
                          seedColor: Colors.green,
                          brightness: theme.brightness,
                        )
                      : scheme;

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => context.push('/capture/${candidate.id}'),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  IconBubble(
                                    icon: candidate.source == 'sms'
                                        ? Icons.sms_rounded
                                        : Icons.receipt_long_rounded,
                                    color: colorScheme.primary,
                                    compact: true,
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          candidate.merchant ??
                                              candidate.transactionType
                                                  ?.toUpperCase() ??
                                              'UNKNOWN',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                        Text(
                                          DateFormat.MMMd(
                                            state.preferences.locale.replaceAll(
                                              '_',
                                              '-',
                                            ),
                                          ).add_jm().format(
                                            candidate.createdAt,
                                          ),
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: scheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (candidate.parsedAmount != null) ...[
                                    const SizedBox(width: AppSpacing.sm),
                                    Flexible(
                                      child: PrivacyText(
                                        (isIncome ? '+' : '') +
                                            formatMoney(
                                              candidate.parsedAmount!,
                                              state.preferences.locale,
                                            ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleLarge
                                            ?.copyWith(
                                              color: isIncome
                                                  ? positiveTone(context)
                                                  : scheme.onSurface,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: -0.5,
                                            ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Wrap(
                                spacing: AppSpacing.sm,
                                runSpacing: AppSpacing.sm,
                                children: [
                                  if (candidate.suggestedAccountId != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: scheme.primaryContainer
                                            .withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons
                                                .account_balance_wallet_rounded,
                                            size: 14,
                                            color: scheme.primary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            state.accounts
                                                    .where(
                                                      (a) =>
                                                          a.id ==
                                                          candidate
                                                              .suggestedAccountId,
                                                    )
                                                    .firstOrNull
                                                    ?.name ??
                                                'Account',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: scheme.primary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (candidate.suggestedCategoryId != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: scheme.secondaryContainer
                                            .withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.category_rounded,
                                            size: 14,
                                            color: scheme.secondary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _categoryChipText(
                                              state,
                                              candidate,
                                            ),
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: scheme.secondary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              if (candidate.rawText != null &&
                                  candidate.rawText!.isNotEmpty) ...[
                                const SizedBox(height: AppSpacing.md),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(AppSpacing.md),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest
                                        .withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    candidate.rawText!,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontFamily: 'monospace',
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                              if (candidate.status == 'pending') ...[
                                const SizedBox(height: AppSpacing.lg),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextButton.icon(
                                        onPressed: () => _updateCandidateStatus(
                                          context,
                                          ref,
                                          candidate.id,
                                          'rejected',
                                        ),
                                        icon: const Icon(Icons.close_rounded),
                                        label: const Text('Dismiss'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: scheme.error,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: () => _updateCandidateStatus(
                                          context,
                                          ref,
                                          candidate.id,
                                          'approved',
                                        ),
                                        icon: const Icon(Icons.check_rounded),
                                        label: const Text('Confirm'),
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              colorScheme.primaryContainer,
                                          foregroundColor:
                                              colorScheme.onPrimaryContainer,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          elevation: 0,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }, childCount: candidates.length),
              ),
            // Bottom padding to ensure last item is fully visible
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const Gap(AppSpacing.lg),
                  SectionCard(
                    title: 'Inbox',
                    subtitle:
                        '$unreadCount unread · ${allNotifications.length} active item${allNotifications.length == 1 ? '' : 's'}',
                    actionLabel: allNotifications.isEmpty ? null : 'Dismiss all',
                    onAction: allNotifications.isEmpty
                        ? null
                        : () => _dismissAll(ref, allNotifications),
                    child: allNotifications.isEmpty
                        ? const EmptyState(
                            icon: Icons.notifications_off_outlined,
                            title: 'Nothing waiting',
                            body: 'Budget and goal alerts will appear here.',
                          )
                        : Column(
                            children: [
                              for (final notification in allNotifications)
                                _NotificationRow(
                                  notification: notification,
                                  read: notification.read,
                                  onOpen: () => _openNotification(context, ref, notification),
                                  onDismiss: () => _dismiss(ref, notification.id),
                                ),
                            ],
                          ),
                  ),
                  const Gap(AppSpacing.xxl),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateCandidateStatus(
    BuildContext context,
    WidgetRef ref,
    String id,
    String status,
  ) async {
    try {
      if (status == 'approved') {
        final router = GoRouter.of(context);
        router.push('/add?captureCandidateId=$id');
        return;
      } else {
        await ref
            .read(ledgerProvider.notifier)
            .updateCaptureCandidateStatus(id, status);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Capture candidate marked $status.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _updateAllPending(
    BuildContext context,
    WidgetRef ref,
    Iterable<String> ids,
    String status,
  ) async {
    final notifier = ref.read(ledgerProvider.notifier);
    if (status == 'approved') {
      final newTxs = await notifier.approveCaptureCandidates(ids);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              newTxs.length == ids.length
                  ? '${newTxs.length} candidates marked approved.'
                  : '${newTxs.length} out of ${ids.length} candidates approved. Check if an account is set.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } else {
      await notifier.updateCaptureCandidateStatuses(ids, status);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${ids.length} candidates marked $status.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _markRead(WidgetRef ref, String id, {bool read = true}) async {
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

  Future<void> _dismiss(WidgetRef ref, String id) async {
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

  Future<void> _markAllRead(WidgetRef ref, Iterable<AppNotification> notifications) async {
    final prefs = ref.read(ledgerProvider).preferences;
    final nextRead = Set<String>.from(prefs.readNotificationIds)
      ..addAll(notifications.map((notification) => notification.id));
    await ref
        .read(ledgerProvider.notifier)
        .updatePreferences(
          prefs.copyWith(readNotificationIds: nextRead.toList()..sort()),
        );
  }

  Future<void> _dismissAll(WidgetRef ref, Iterable<AppNotification> notifications) async {
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

  void _openNotification(BuildContext context, WidgetRef ref, AppNotification notification) {
    _markRead(ref, notification.id);
    final actionRoute = notification.actionRoute;
    if (actionRoute == null || actionRoute.trim().isEmpty) return;
    context.push(actionRoute);
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

String _categoryChipText(LedgerState state, CaptureCandidate candidate) {
  final category = categoryById(state, candidate.suggestedCategoryId);
  final name = category?.name ?? 'Category';
  final reason = candidate.suggestedCategoryReason?.trim();
  if (reason == null || reason.isEmpty) return name;
  return '$name · $reason';
}
