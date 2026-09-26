import 'package:flutter/material.dart';
import '../../ledger/ledger_selectors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

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

    final allNotifications = buildNotificationInbox(state);
    final unreadCount = allNotifications
        .where((notification) => !notification.read)
        .length;

    final items = <dynamic>[...candidates, ...allNotifications];
    items.sort((a, b) {
      final aDate = a is CaptureCandidate
          ? a.createdAt
          : (a as AppNotification).createdAt;
      final bDate = b is CaptureCandidate
          ? b.createdAt
          : (b as AppNotification).createdAt;
      return bDate.compareTo(aDate);
    });

    return GlassIsolationScope(
      isolated: true,
      defaultQuality: GlassQuality.standard,
      child: Scaffold(
        appBar: GlassAppBar(
          title: Text(
            'Review & Inbox',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          leading: Navigator.of(context).canPop()
              ? const AppBackAction()
              : null,
          centerTitle: false,
          actions: [
            IconButton(
              tooltip: 'Auto-capture settings',
              icon: const Icon(Icons.settings_suggest_outlined),
              onPressed: () => context.push('/capture-settings'),
            ),
            if (candidates.isNotEmpty) ...[
              IconButton(
                tooltip: 'Approve All',
                onPressed: () => _approveAll(context, ref, candidates),
                icon: const Icon(Icons.done_all_rounded),
              ),
              IconButton(
                tooltip: 'Dismiss All',
                onPressed: () => _dismissAll(context, ref, candidates),
                icon: const Icon(Icons.clear_all_rounded),
              ),
            ],
            if (unreadCount > 0)
              IconButton(
                tooltip: 'Mark all read',
                onPressed: () => _markAllRead(ref, allNotifications),
                icon: const Icon(Icons.mark_email_read_outlined),
              ),
          ],
        ),
        body: SafeArea(
          child: items.isEmpty
              ? _buildEmptyState(context)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.xxl,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    if (item is CaptureCandidate) {
                      return _buildCandidateCard(context, ref, state, item);
                    } else if (item is AppNotification) {
                      return _buildNotificationCard(context, ref, item);
                    }
                    return const SizedBox();
                  },
                ),
        ),
      ),
    );
  }

  /// Empty state wrapped in a centred GlassCard for visual polish.
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: GlassCard(
          useOwnLayer: true,
          quality: GlassQuality.premium,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.xxl,
          ),
          shape: LiquidRoundedSuperellipse(borderRadius: AppRadii.lg),
          child: const EmptyState(
            icon: Icons.done_all_rounded,
            title: 'All caught up',
            body: 'New transactions and alerts will appear here.',
          ),
        ),
      ),
    );
  }

  Widget _buildCandidateCard(
    BuildContext context,
    WidgetRef ref,
    LedgerState state,
    CaptureCandidate candidate,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isIncome = candidate.transactionType == 'income';
    final colorScheme = isIncome
        ? ColorScheme.fromSeed(
            seedColor: Colors.green,
            brightness: theme.brightness,
          )
        : scheme;

    // Glass is reserved for navigation/control chrome (per the
    // liquid_glass_widgets guidance); scrolling list rows stay opaque.
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/capture/${candidate.id}'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: icon + merchant/date + amount ──────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          candidate.merchant ??
                              candidate.transactionType?.toUpperCase() ??
                              'UNKNOWN',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat.MMMd(
                            state.preferences.locale.replaceAll('_', '-'),
                          ).add_jm().format(candidate.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(
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
                        style: theme.textTheme.titleLarge?.copyWith(
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

              // ── Suggestion chips ────────────────────────────────────────
              if (candidate.suggestedAccountId != null ||
                  candidate.suggestedCategoryId != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    if (candidate.suggestedAccountId != null)
                      GlassChip(
                        label: state.accounts
                                .where(
                                  (a) => a.id == candidate.suggestedAccountId,
                                )
                                .firstOrNull
                                ?.name ??
                            'Account',
                        icon: const Icon(
                          Icons.account_balance_wallet_rounded,
                        ),
                        iconSize: 13,
                        iconColor: scheme.primary,
                        labelStyle: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        quality: GlassQuality.standard,
                        useOwnLayer: true,
                        semanticLabel:
                            'Account: ${state.accounts.where((a) => a.id == candidate.suggestedAccountId).firstOrNull?.name ?? 'Account'}',
                      ),
                    if (candidate.suggestedCategoryId != null)
                      GlassChip(
                        label: _categoryChipText(state, candidate),
                        icon: const Icon(Icons.category_rounded),
                        iconSize: 13,
                        iconColor: scheme.secondary,
                        labelStyle: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        quality: GlassQuality.standard,
                        useOwnLayer: true,
                        semanticLabel:
                            'Category: ${_categoryChipText(state, candidate)}',
                      ),
                  ],
                ),
              ],

              // ── Raw text preview ────────────────────────────────────────
              if (candidate.rawText != null &&
                  candidate.rawText!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(AppRadii.md),
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

              // ── Divider between content and action buttons ──────────────
              if (candidate.status == 'pending') ...[
                const SizedBox(height: AppSpacing.md),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                ),
                const SizedBox(height: AppSpacing.sm),

                // ── Action bar: block | dismiss | confirm ─────────────────
                // Uses pill-shaped buttons at full height for easy tap targets.
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Block: GlassIconButton (standalone, glass chrome)
                      Tooltip(
                        message: 'Block Pattern',
                        child: GlassIconButton(
                          icon: const Icon(Icons.block_rounded),
                          onPressed: () =>
                              _showBlockDialog(context, ref, candidate),
                          size: 48,
                          iconSize: 22,
                          glowColor: scheme.error,
                          shape: GlassIconButtonShape.roundedSquare,
                          borderRadius: AppRadii.pill,
                          useOwnLayer: true,
                          quality: GlassQuality.standard,
                          semanticLabel: 'Block Pattern',
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),

                      // Dismiss
                      Expanded(
                        flex: 2,
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
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadii.pill),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),

                      // Confirm
                      Expanded(
                        flex: 3,
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
                            backgroundColor: colorScheme.primaryContainer,
                            foregroundColor: colorScheme.onPrimaryContainer,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadii.pill),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationCard(
    BuildContext context,
    WidgetRef ref,
    AppNotification notification,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final icon = switch (notification.channel) {
      AppNotificationChannel.scheduled => Icons.event_repeat_rounded,
    };

    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _dismiss(ref, notification.id),
      background: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Icon(
          Icons.archive_outlined,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      // Glass is reserved for navigation/control chrome (per the
      // liquid_glass_widgets guidance); scrolling list rows stay opaque. The
      // unread tint is pre-blended onto an opaque base instead of relying on
      // a blurred backdrop to show through a transparent color.
      child: Material(
        color: notification.read
            ? scheme.surfaceContainerHigh
            : Color.alphaBlend(
                scheme.primaryContainer.withValues(alpha: 0.25),
                scheme.surfaceContainerHigh,
              ),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openNotification(context, ref, notification),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left-border accent for unread state
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: notification.read ? 0 : 4,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppRadii.lg),
                    bottomLeft: Radius.circular(AppRadii.lg),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconBubble(
                        icon: icon,
                        color: notification.read
                            ? scheme.onSurfaceVariant
                            : scheme.primary,
                        compact: true,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              notification.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: notification.read
                                    ? FontWeight.w600
                                    : FontWeight.w800,
                                color: scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              notification.body,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              _relativeDate(notification.createdAt),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!notification.read) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Icon(
                            Icons.fiber_manual_record,
                            size: 10,
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _approveAll(
    BuildContext context,
    WidgetRef ref,
    List<CaptureCandidate> candidates,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve All?'),
        content: Text(
          'Are you sure you want to approve all ${candidates.length} pending items?\n\n'
          'They will be added as transactions using their suggested accounts and categories.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve All'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final ledger = ref.read(ledgerProvider.notifier);
      for (final candidate in candidates) {
        try {
          await ledger.approveCaptureCandidate(candidate.id);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to approve item: $e')),
            );
          }
        }
      }
    }
  }

  Future<void> _dismissAll(
    BuildContext context,
    WidgetRef ref,
    List<CaptureCandidate> candidates,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dismiss All?'),
        content: Text(
          'Are you sure you want to dismiss all ${candidates.length} pending items?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Dismiss All'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final ledger = ref.read(ledgerProvider.notifier);
      await ledger.updateCaptureCandidateStatuses(
        candidates.map((c) => c.id),
        'rejected',
      );
    }
  }

  Future<void> _showBlockDialog(
    BuildContext context,
    WidgetRef ref,
    CaptureCandidate candidate,
  ) async {
    final rawText = candidate.rawText ?? '';
    if (rawText.isEmpty) return;

    final controller = TextEditingController();

    // Suggest some words by splitting the raw text
    final words = rawText
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 3)
        .take(10)
        .toList();

    try {
      await GlassDialog.show<void>(
        context: context,
        title: 'Block Message Pattern',
        content: Material(
          color: Colors.transparent,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Messages matching this regex pattern will be automatically ignored.',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                Text(
                  'Original Message:',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    rawText,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (words.isNotEmpty) ...[
                  Text(
                    'Tap to add word:',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: words.map((word) {
                      return ActionChip(
                        label: Text(word),
                        labelStyle: const TextStyle(fontSize: 12),
                        onPressed: () {
                          final text = controller.text;
                          controller.text = text.isEmpty
                              ? word
                              : '$text.*$word';
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Regex Pattern',
                    border: OutlineInputBorder(),
                    hintText: 'e.g. promo.*sale',
                  ),
                ),
              ],
            ),
          ),
        ),
        barrierDismissible: true,
        maxWidth: 420,
        actions: [
          GlassDialogAction(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
          GlassDialogAction(
            label: 'Block Pattern',
            isPrimary: true,
            onPressed: () async {
              final pattern = controller.text.trim();
              if (pattern.isNotEmpty) {
                final ledger = ref.read(ledgerProvider.notifier);
                final prefs = ref.read(ledgerProvider).preferences;
                final patterns = List<String>.from(prefs.smsBlockPatterns);
                if (!patterns.contains(pattern)) {
                  patterns.add(pattern);
                  await ledger.updatePreferences(
                    prefs.copyWith(smsBlockPatterns: patterns),
                  );
                }
                await ledger.updateCaptureCandidateStatus(
                  candidate.id,
                  'rejected',
                );
              }
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      );
    } finally {
      controller.dispose();
    }
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

  Future<void> _markAllRead(
    WidgetRef ref,
    Iterable<AppNotification> notifications,
  ) async {
    final prefs = ref.read(ledgerProvider).preferences;
    final nextRead = Set<String>.from(prefs.readNotificationIds)
      ..addAll(notifications.map((notification) => notification.id));
    await ref
        .read(ledgerProvider.notifier)
        .updatePreferences(
          prefs.copyWith(readNotificationIds: nextRead.toList()..sort()),
        );
  }

  void _openNotification(
    BuildContext context,
    WidgetRef ref,
    AppNotification notification,
  ) {
    _markRead(ref, notification.id);
    final actionRoute = notification.actionRoute;
    if (actionRoute == null || actionRoute.trim().isEmpty) return;
    context.push(actionRoute);
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
