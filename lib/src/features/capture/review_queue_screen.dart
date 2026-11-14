import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../../ledger/ledger_selectors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:g1455/g1455.dart' as g1455;

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../capture/message_parser.dart';
import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';
import '../common/route_scaffold.dart';
import '../../widgets/privacy_text.dart';
import '../notifications/notification_engine.dart';
import 'capture_queue.dart';

class TransferCandidatePair {
  const TransferCandidatePair({
    required this.debitCandidate,
    required this.creditCandidate,
  });

  final CaptureCandidate debitCandidate;
  final CaptureCandidate creditCandidate;

  DateTime get createdAt =>
      debitCandidate.createdAt.isAfter(creditCandidate.createdAt)
      ? debitCandidate.createdAt
      : creditCandidate.createdAt;
}

class ReviewQueueScreen extends ConsumerStatefulWidget {
  const ReviewQueueScreen({super.key});

  @override
  ConsumerState<ReviewQueueScreen> createState() => _ReviewQueueScreenState();
}

class _ReviewQueueScreenState extends ConsumerState<ReviewQueueScreen>
    with WidgetsBindingObserver {
  bool _legacyPromptShown = false;
  int _reportedQuarantineCount = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshSpooled();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshSpooled();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refreshSpooled() async {
    if (!mounted) return;
    try {
      if (!_legacyPromptShown && await CaptureQueue.client.unassigned() > 0) {
        if (!mounted) return;
        _legacyPromptShown = true;
        final owner = ref.read(ledgerProvider).userId;
        final confirmed = await showAppConfirmDialog(
          context,
          title: 'Assign legacy captures?',
          message:
              'Older queued messages have no recorded wallet owner. '
              'Import them into the currently signed-in wallet only if they belong to it.',
          cancelLabel: 'Keep unassigned',
          confirmLabel: 'Assign to this wallet',
        );
        if (!mounted) return;
        if (confirmed && ref.read(ledgerProvider).userId == owner) {
          await ref.read(ledgerProvider.notifier).assignLegacyCaptures();
        }
      }
      if (!mounted) return;
      await ref.read(ledgerProvider.notifier).processSpooledSms();
      if (!mounted) return;
      await ref.read(ledgerProvider.notifier).processSpooledNotifications();
      if (!mounted) return;
      final count = await CaptureQueue.client.quarantineCount(
        ref.read(ledgerProvider).userId,
      );
      if (mounted && count > _reportedQuarantineCount) {
        _reportedQuarantineCount = count;
        showAppSnackBar(
          context,
          '$count invalid capture item(s) were retained in quarantine, not imported.',
        );
      }
    } catch (error, stack) {
      debugPrint('Queued capture processing failed: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) {
        showAppSnackBar(
          context,
          'Queued captures could not be processed. Unacknowledged items were retained for retry.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerProvider);
    final candidates = state.captureCandidates
        .where((candidate) => candidate.status == 'pending')
        .toList();

    final allNotifications = buildNotificationInbox(state);
    final unreadCount = allNotifications
        .where((notification) => !notification.read)
        .length;

    final items = _groupReviewItems(
      pendingCandidates: candidates,
      notifications: allNotifications,
    );

    return GlassIsolationScope(
      defaultQuality: GlassQuality.standard,
      child: RouteScaffold(
        title: 'Review & Inbox',
        // The route sits under a drawer-enabled DrawerConfig but has always
        // offered a back action; keep that navigation.
        hasDrawer: false,
        actions: [
          if (unreadCount > 0)
            HeaderIconButton(
              icon: Icons.mark_email_read_outlined,
              semanticLabel: 'Mark all read',
              tooltip: 'Mark all read',
              onPressed: () => _markAllRead(ref, allNotifications),
            ),
          g1455.GlassMenuAnchor(
            finish: ref.watch(glassFinishProvider),
            items: [
              g1455.GlassMenuItem(
                label: 'SMS auto-capture',
                icon: const Icon(Icons.sms_outlined, size: 20),
                onPressed: () => context.push('/import-sms'),
              ),
              g1455.GlassMenuItem(
                label: 'Notification capture',
                icon: const Icon(Icons.notifications_active_outlined, size: 20),
                onPressed: () => context.push('/notification-capture'),
              ),
              g1455.GlassMenuItem(
                label: 'Capture diagnostics',
                icon: const Icon(Icons.bug_report_outlined, size: 20),
                onPressed: () => context.push('/auto-capture/debug'),
              ),
            ],
            builder: (context, controller) => IconButton(
              tooltip: 'Capture tools',
              icon: const Icon(Icons.tune_rounded),
              onPressed:
                  controller.isOpen ? controller.close : controller.open,
            ),
          ),
        ],
        scrollView: RefreshIndicator(
          onRefresh: _refreshSpooled,
          child: items.isEmpty
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.xl,
                            ),
                            child: _buildEmptyState(context),
                          ),
                        ),
                      ),
                    );
                  },
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
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
                    if (item is TransferCandidatePair) {
                      return _buildTransferPairCard(context, ref, state, item);
                    } else if (item is CaptureCandidate) {
                      return _buildCandidateCard(context, ref, state, item);
                    } else if (item is AppNotification) {
                      return _buildNotificationCard(context, ref, state, item);
                    }
                    return const SizedBox();
                  },
                ),
        ),
      ),
    );
  }

  /// Empty state wrapped in a centred glass panel for visual polish (opaque
  /// on AMOLED).
  Widget _buildEmptyState(BuildContext context) {
    return const AppPanel(
      glass: true,
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.xxl,
        vertical: AppSpacing.xxl,
      ),
      child: EmptyState(
        icon: Icons.done_all_rounded,
        title: 'All caught up',
        body: 'New transactions and alerts will appear here.',
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
    final matchedPlan = _findMatchingPlan(state, candidate);

    // Glass is reserved for navigation/control chrome (per the
    // liquid_glass_widgets guidance); scrolling list rows stay opaque.
    return AppPanel(
      onTap: () => context.push('/capture/${candidate.id}'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: icon + merchant/date + amount ──────────────────
          Row(
            children: [
              IconBubble(
                icon: candidate.source == 'sms'
                    ? Icons.sms_rounded
                    : Icons.receipt_long_rounded,
                color: isIncome ? scheme.positive : scheme.primary,
                compact: true,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _candidateDisplayName(
                        state,
                        candidate,
                        matchedPlan: matchedPlan,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxxs),
                    Text(
                      DateFormat.MMMd(
                        state.preferences.locale.replaceAll('_', '-'),
                      ).add_jm().format(candidate.createdAt.toLocal()),
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
                      color: isIncome ? scheme.positive : scheme.onSurface,
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
              matchedPlan != null ||
              candidate.suggestedCategoryId != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                if (candidate.suggestedAccountId != null)
                  _ReviewQueueChip(
                    label:
                        state.accounts
                            .where((a) => a.id == candidate.suggestedAccountId)
                            .firstOrNull
                            ?.name ??
                        'Account',
                    icon: const Icon(Icons.account_balance_wallet_rounded),
                    iconColor: scheme.primary,
                    semanticLabel:
                        'Account: ${state.accounts.where((a) => a.id == candidate.suggestedAccountId).firstOrNull?.name ?? 'Account'}',
                  ),
                if (matchedPlan != null)
                  _ReviewQueueChip(
                    label: matchedPlan.name?.isNotEmpty == true
                        ? 'Planned: ${matchedPlan.name}'
                        : 'Planned payment detected',
                    icon: const Icon(Icons.event_repeat_rounded),
                    iconColor: scheme.tertiary,
                    labelStyle: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.tertiary,
                    ),
                    semanticLabel:
                        'Planned payment detected: ${matchedPlan.name ?? ''}',
                  ),
                if (candidate.suggestedCategoryId != null)
                  _ReviewQueueChip(
                    label: _categoryChipText(state, candidate),
                    icon: const Icon(Icons.category_rounded),
                    iconColor: scheme.secondary,
                    semanticLabel:
                        'Category: ${_categoryChipText(state, candidate)}',
                  ),
              ],
            ),
          ],

          // ── Raw text preview ────────────────────────────────────────
          if (candidate.rawText != null && candidate.rawText!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: PrivacyText(
                candidate.rawText!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFamily: AppFonts.mono,
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
            LayoutBuilder(
              builder: (context, constraints) {
                if (matchedPlan != null) {
                  // 4 Buttons: Perfectly aligned 2x2 grid
                  // Top Row: [ Block ] ... [ Pay Plan ]
                  // Bottom Row: [ Dismiss ] ... [ Confirm ]
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextButton.icon(
                              onPressed: () =>
                                  _showBlockDialog(context, ref, candidate),
                              icon: const Icon(Icons.block_rounded, size: 16),
                              label: const Text(
                                'Block',
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: AppButtonStyles.destructiveText(
                                context,
                              ).merge(AppButtonStyles.compact(context)),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () async {
                                final router = GoRouter.of(context);
                                await router.push(
                                  '/add?plannedId=${matchedPlan.id}&captureCandidateId=${candidate.id}',
                                );
                              },
                              icon: const Icon(
                                Icons.event_repeat_rounded,
                                size: 16,
                              ),
                              label: const Text(
                                'Pay Plan',
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: scheme.tertiaryContainer,
                                foregroundColor: scheme.onTertiaryContainer,
                              ).merge(AppButtonStyles.compact(context)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
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
                              icon: const Icon(Icons.close_rounded, size: 16),
                              label: const Text(
                                'Dismiss',
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: AppButtonStyles.destructiveText(
                                context,
                              ).merge(AppButtonStyles.compact(context)),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _updateCandidateStatus(
                                context,
                                ref,
                                candidate.id,
                                'approved',
                              ),
                              icon: const Icon(Icons.check_rounded, size: 16),
                              label: const Text(
                                'Confirm',
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                              ),
                              style: AppButtonStyles.compact(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }

                // 3 Buttons: [ Block ] (left) ... [ Dismiss ] (middle) ... [ Confirm ] (right)
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: TextButton.icon(
                        onPressed: () =>
                            _showBlockDialog(context, ref, candidate),
                        icon: const Icon(Icons.block_rounded, size: 16),
                        label: const Text(
                          'Block',
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: AppButtonStyles.destructiveText(
                          context,
                        ).merge(AppButtonStyles.compact(context)),
                      ),
                    ),
                    Flexible(
                      child: TextButton.icon(
                        onPressed: () => _updateCandidateStatus(
                          context,
                          ref,
                          candidate.id,
                          'rejected',
                        ),
                        icon: const Icon(Icons.close_rounded, size: 16),
                        label: const Text(
                          'Dismiss',
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: AppButtonStyles.destructiveText(
                          context,
                        ).merge(AppButtonStyles.compact(context)),
                      ),
                    ),
                    Flexible(
                      child: FilledButton.icon(
                        onPressed: () => _updateCandidateStatus(
                          context,
                          ref,
                          candidate.id,
                          'approved',
                        ),
                        icon: const Icon(Icons.check_rounded, size: 16),
                        label: const Text(
                          'Confirm',
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: AppButtonStyles.compact(context),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNotificationCard(
    BuildContext context,
    WidgetRef ref,
    LedgerState state,
    AppNotification notification,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final account = notification.accountId != null
        ? accountById(state, notification.accountId!)
        : null;

    if (account != null) {
      final accountColor = account.color ?? scheme.primary;
      final dueStatus = creditCardDueStatus(state, account);

      return Dismissible(
        key: ValueKey(notification.id),
        direction: DismissDirection.endToStart,
        onDismissed: (_) => _dismiss(ref, notification.id),
        background: Container(
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Icon(Icons.archive_outlined, color: scheme.onErrorContainer),
        ),
        child: AppPanel(
          color: notification.read
              ? null
              : Color.alphaBlend(
                  (notification.isOverdue || notification.isDueSoon
                          ? scheme.error
                          : scheme.primary)
                      .withValues(alpha: 0.12),
                  scheme.surfaceContainerLow,
                ),
          padding: EdgeInsets.zero,
          onTap: () => _openNotification(context, ref, notification),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: accountColor.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        accountIcon(account),
                        size: 22,
                        color: accountColor,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  account.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (notification.badgeLabel != null) ...[
                                const SizedBox(width: AppSpacing.xs),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.xs,
                                    vertical: AppSpacing.xxxs,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        (notification.isOverdue ||
                                                    notification.isDueSoon
                                                ? scheme.error
                                                : scheme.primary)
                                            .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(
                                      AppRadii.xs,
                                    ),
                                  ),
                                  child: Text(
                                    notification.badgeLabel!,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color:
                                          notification.isOverdue ||
                                              notification.isDueSoon
                                          ? scheme.error
                                          : scheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xxxs),
                          Text(
                            [
                              if (account.institution?.isNotEmpty == true)
                                account.institution!,
                              if (dueStatus != null)
                                'Due ${dueStatus.daysUntilDue >= 0 ? "in ${dueStatus.daysUntilDue}d" : "${-dueStatus.daysUntilDue}d ago"} (${dueStatus.dueDate.day}/${dueStatus.dueDate.month})',
                            ].join(' · '),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (notification.amount != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: PrivacyText(
                          formatMoney(
                            convertMoneyForDisplay(state, notification.amount!),
                            state.preferences.locale,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: notification.isOverdue
                                ? scheme.error
                                : scheme.onSurface,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Text(
                  notification.body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Divider(
                height: 1,
                thickness: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.3),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    TextButton.icon(
                      onPressed: () => _dismiss(ref, notification.id),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('Dismiss', softWrap: false),
                      style: AppButtonStyles.compact(context),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'View Card Details',
                          icon: const Icon(
                            Icons.credit_card_outlined,
                            size: 20,
                          ),
                          onPressed: () => context.push('/cards'),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        FilledButton.icon(
                          onPressed: () async {
                            final cycle =
                                notification.cycleKey ?? dueStatus?.cycleKey;
                            await ref
                                .read(ledgerProvider.notifier)
                                .markCardBillPaid(account.id, cycle);
                            await _dismiss(ref, notification.id);
                            if (context.mounted) {
                              showAppSnackBar(
                                context,
                                'Marked ${account.name} bill as paid',
                                action: SnackBarAction(
                                  label: 'Undo',
                                  onPressed: () {
                                    ref
                                        .read(ledgerProvider.notifier)
                                        .markCardBillPaid(account.id, null);
                                  },
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: const Text('Confirm Paid', softWrap: false),
                          style: AppButtonStyles.compact(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

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
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Icon(
          Icons.archive_outlined,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      child: AppPanel(
        color: notification.read
            ? null
            : Color.alphaBlend(
                scheme.primaryContainer.withValues(alpha: 0.25),
                scheme.surfaceContainerLow,
              ),
        padding: EdgeInsets.zero,
        onTap: () => _openNotification(context, ref, notification),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: notification.read ? 0 : 4,
                  height: 64,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(AppRadii.md),
                      bottomLeft: Radius.circular(AppRadii.md),
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
                              const SizedBox(height: AppSpacing.xxxs),
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
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: Icon(
                              Icons.fiber_manual_record_rounded,
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
            Divider(
              height: 1,
              thickness: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.3),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xxs,
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  TextButton.icon(
                    onPressed: () => _dismiss(ref, notification.id),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: const Text('Dismiss', softWrap: false),
                    style: AppButtonStyles.compact(context),
                  ),
                  if (notification.actionRoute != null)
                    TextButton.icon(
                      onPressed: () =>
                          _openNotification(context, ref, notification),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                      label: const Text('View', softWrap: false),
                      style: AppButtonStyles.compact(context),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => AlertDialog(
          title: const Text('Block Message Pattern'),
          // Keeps the dialog's previous width cap on wide screens.
          constraints: const BoxConstraints(minWidth: 280, maxWidth: 420),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Messages matching this regex pattern will be automatically ignored.',
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Original Message:',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                  child: Text(
                    rawText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: AppFonts.mono,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (words.isNotEmpty) ...[
                  Text(
                    'Tap to add word:',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Wrap(
                    spacing: AppSpacing.xxs,
                    runSpacing: AppSpacing.xxs,
                    children: words.map((word) {
                      return ActionChip(
                        label: Text(word),
                        labelStyle: Theme.of(context).textTheme.labelMedium,
                        onPressed: () {
                          final text = controller.text;
                          controller.text = text.isEmpty
                              ? word
                              : '$text.*$word';
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                AppGlassTextField(
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
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final pattern = controller.text.trim();
                if (pattern.isNotEmpty) {
                  final ledger = ref.read(ledgerProvider.notifier);
                  final prefs = ref.read(ledgerProvider).preferences;
                  final patterns = List<String>.from(prefs.smsBlockPatterns);
                  if (!patterns.contains(pattern)) {
                    patterns.add(pattern);
                    await ledger.updatePreferencesWith(
                      (livePreferences) =>
                          livePreferences.copyWith(smsBlockPatterns: patterns),
                    );
                  }
                  await ledger.updateCaptureCandidateStatus(
                    candidate.id,
                    'rejected',
                  );
                }
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Block Pattern'),
            ),
          ],
        ),
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
        await router.push('/add?captureCandidateId=$id');
        return;
      } else {
        await ref
            .read(ledgerProvider.notifier)
            .updateCaptureCandidateStatus(id, status);
      }
      if (!context.mounted) return;
      showAppSnackBar(context, 'Capture candidate marked $status.');
    } catch (e) {
      if (!context.mounted) return;
      showAppSnackBar(context, e.toString());
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
        .updatePreferencesWith(
          (livePreferences) => livePreferences.copyWith(
            readNotificationIds: nextRead.toList()..sort(),
          ),
        );
  }

  Future<void> _dismiss(WidgetRef ref, String id) async {
    final prefs = ref.read(ledgerProvider).preferences;
    final nextDismissed = Set<String>.from(prefs.dismissedNotificationIds)
      ..add(id);
    final nextRead = Set<String>.from(prefs.readNotificationIds)..remove(id);
    await ref
        .read(ledgerProvider.notifier)
        .updatePreferencesWith(
          (livePreferences) => livePreferences.copyWith(
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
        .updatePreferencesWith(
          (livePreferences) => livePreferences.copyWith(
            readNotificationIds: nextRead.toList()..sort(),
          ),
        );
  }

  List<dynamic> _groupReviewItems({
    required List<CaptureCandidate> pendingCandidates,
    required List<AppNotification> notifications,
  }) {
    final pairedIds = <String>{};
    final pairs = <TransferCandidatePair>[];

    // 1. Explicitly paired candidates
    for (final c in pendingCandidates) {
      if (c.pairedCandidateId != null && !pairedIds.contains(c.id)) {
        final other = pendingCandidates.firstWhereOrNull(
          (o) => o.id == c.pairedCandidateId && !pairedIds.contains(o.id),
        );
        if (other != null) {
          final debit = c.transactionType == 'expense' ? c : other;
          final credit = c.transactionType == 'expense' ? other : c;
          pairs.add(
            TransferCandidatePair(
              debitCandidate: debit,
              creditCandidate: credit,
            ),
          );
          pairedIds.add(debit.id);
          pairedIds.add(credit.id);
        }
      }
    }

    // 2. Discover potential transfer pairs:
    // Same amountMinor & currency, opposite directions (one expense, one income),
    // different accounts (or different texts), within 24 hours.
    for (final c in pendingCandidates) {
      if (pairedIds.contains(c.id) || c.parsedAmount == null) continue;
      if (c.transactionType != 'expense' && c.transactionType != 'income') {
        continue;
      }

      for (final other in pendingCandidates) {
        if (other.id == c.id ||
            pairedIds.contains(other.id) ||
            other.parsedAmount == null) {
          continue;
        }
        if (other.transactionType != 'expense' &&
            other.transactionType != 'income') {
          continue;
        }

        // Opposite flow direction: one debit and one income
        if (c.transactionType == other.transactionType) continue;

        // Same amount and currency
        if (c.parsedAmount!.amountMinor != other.parsedAmount!.amountMinor ||
            c.parsedAmount!.currency.toUpperCase() !=
                other.parsedAmount!.currency.toUpperCase()) {
          continue;
        }

        // Within 24 hours
        if ((c.createdAt.difference(other.createdAt).inHours).abs() > 24) {
          continue;
        }

        // Different accounts if both are present
        if (c.suggestedAccountId != null &&
            other.suggestedAccountId != null &&
            c.suggestedAccountId == other.suggestedAccountId) {
          continue;
        }

        final debit = c.transactionType == 'expense' ? c : other;
        final credit = c.transactionType == 'expense' ? other : c;
        pairs.add(
          TransferCandidatePair(debitCandidate: debit, creditCandidate: credit),
        );
        pairedIds.add(debit.id);
        pairedIds.add(credit.id);
        break;
      }
    }

    final standalone = pendingCandidates
        .where((c) => !pairedIds.contains(c.id))
        .toList();

    final items = <dynamic>[...pairs, ...standalone, ...notifications];
    items.sort((a, b) {
      final aDate = a is TransferCandidatePair
          ? a.createdAt
          : (a is CaptureCandidate
                ? a.createdAt
                : (a as AppNotification).createdAt);
      final bDate = b is TransferCandidatePair
          ? b.createdAt
          : (b is CaptureCandidate
                ? b.createdAt
                : (b as AppNotification).createdAt);
      return bDate.compareTo(aDate);
    });
    return items;
  }

  TransactionRecord? _findMatchingPlan(
    LedgerState state,
    CaptureCandidate candidate,
  ) {
    if (candidate.parsedAmount == null) return null;
    final candAmt = candidate.parsedAmount!;
    final scheduled = scheduledTransactions(state);

    TransactionRecord? bestMatch;
    int bestScore = -1;

    for (final plan in scheduled) {
      if (plan.status != 'scheduled' && plan.status != 'paused') continue;

      final planAmt = plan.originalAmount ?? plan.amount;
      if (planAmt.amountMinor != candAmt.amountMinor ||
          planAmt.currency.toUpperCase() != candAmt.currency.toUpperCase()) {
        continue;
      }

      if (candidate.transactionType != null &&
          candidate.transactionType != 'transfer') {
        final isCandidateIncome = candidate.transactionType == 'income';
        final isPlanIncome = plan.type == 'income';
        if (isCandidateIncome != isPlanIncome) continue;
      }

      // Check within +/- 3 days (72 hours)
      final diffHours =
          (candidate.createdAt.difference(plan.occurredAt).inHours).abs();
      if (diffHours > 72) continue;

      int score = 10;
      if (candidate.suggestedAccountId != null &&
          candidate.suggestedAccountId == plan.accountId) {
        score += 20;
      }
      final cleanMerchant = resolveCleanMerchant(
        candidate.merchant,
        rawText: candidate.rawText,
      );
      if (plan.name != null && cleanMerchant != null) {
        final pName = plan.name!.trim().toLowerCase();
        final cName = cleanMerchant.toLowerCase();
        if (pName.isNotEmpty &&
            cName.isNotEmpty &&
            (pName.contains(cName) || cName.contains(pName))) {
          score += 15;
        }
      }
      if (diffHours <= 24) {
        score += 5;
      } else if (diffHours <= 48) {
        score += 2;
      }

      if (score > bestScore) {
        bestScore = score;
        bestMatch = plan;
      }
    }

    return bestMatch;
  }

  Widget _buildTransferPairCard(
    BuildContext context,
    WidgetRef ref,
    LedgerState state,
    TransferCandidatePair pair,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final debit = pair.debitCandidate;
    final credit = pair.creditCandidate;

    final fromAccount = state.accounts.firstWhereOrNull(
      (a) => a.id == debit.suggestedAccountId,
    );
    final toAccount = state.accounts.firstWhereOrNull(
      (a) => a.id == credit.suggestedAccountId,
    );

    final amount = debit.parsedAmount ?? credit.parsedAmount;

    return AppPanel(
      onTap: () => _confirmTransferPair(context, ref, pair),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: Transfer icon + title + amount ──────────────────
          Row(
            children: [
              IconBubble(
                icon: Icons.swap_horiz_rounded,
                color: scheme.primary,
                compact: true,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Transfer detected',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxxs),
                    Text(
                      DateFormat.MMMd(
                        state.preferences.locale.replaceAll('_', '-'),
                      ).add_jm().format(pair.createdAt.toLocal()),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (amount != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: PrivacyText(
                    formatMoney(amount, state.preferences.locale),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ],
            ],
          ),

          // ── Accounts route chips: From ➔ To ─────────────────────────
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _ReviewQueueChip(
                label: 'From: ${fromAccount?.name ?? 'Account'}',
                icon: const Icon(Icons.call_made_rounded),
                iconColor: scheme.error,
              ),
              Icon(
                Icons.arrow_forward_rounded,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              _ReviewQueueChip(
                label: 'To: ${toAccount?.name ?? 'Account'}',
                icon: const Icon(Icons.call_received_rounded),
                iconColor: scheme.positive,
              ),
              _ReviewQueueChip(
                label: 'Transfer',
                icon: const Icon(Icons.swap_horiz_rounded),
                iconColor: scheme.tertiary,
                labelStyle: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.tertiary,
                ),
              ),
            ],
          ),

          // ── Raw text preview (both debit & credit messages) ─────────
          if ((debit.rawText?.isNotEmpty == true) ||
              (credit.rawText?.isNotEmpty == true)) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (debit.rawText?.isNotEmpty == true)
                    PrivacyText(
                      'Debit: ${debit.rawText!}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFamily: AppFonts.mono,
                        height: 1.3,
                      ),
                    ),
                  if (debit.rawText?.isNotEmpty == true &&
                      credit.rawText?.isNotEmpty == true)
                    const SizedBox(height: AppSpacing.xxs),
                  if (credit.rawText?.isNotEmpty == true)
                    PrivacyText(
                      'Credit: ${credit.rawText!}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFamily: AppFonts.mono,
                        height: 1.3,
                      ),
                    ),
                ],
              ),
            ),
          ],

          // ── Divider ─────────────────────────────────────────────────
          const SizedBox(height: AppSpacing.md),
          Divider(
            height: 1,
            thickness: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── Actions ─────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Dismiss both
              TextButton.icon(
                onPressed: () => _dismissTransferPair(context, ref, pair),
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Dismiss', softWrap: false),
                style: AppButtonStyles.destructiveText(
                  context,
                ).merge(AppButtonStyles.compact(context)),
              ),

              // Confirm Transfer
              FilledButton.icon(
                onPressed: () => _confirmTransferPair(context, ref, pair),
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('Confirm Transfer', softWrap: false),
                style: AppButtonStyles.compact(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmTransferPair(
    BuildContext context,
    WidgetRef ref,
    TransferCandidatePair pair,
  ) async {
    try {
      await ref
          .read(ledgerProvider.notifier)
          .linkTransferCandidates(
            debitCandidateId: pair.debitCandidate.id,
            creditCandidateId: pair.creditCandidate.id,
          );
      if (!context.mounted) return;
      final router = GoRouter.of(context);
      await router.push('/add?captureCandidateId=${pair.debitCandidate.id}');
    } catch (e) {
      if (!context.mounted) return;
      showAppSnackBar(context, e.toString());
    }
  }

  Future<void> _dismissTransferPair(
    BuildContext context,
    WidgetRef ref,
    TransferCandidatePair pair,
  ) async {
    try {
      await ref
          .read(ledgerProvider.notifier)
          .updateCaptureCandidateStatus(pair.debitCandidate.id, 'rejected');
      await ref
          .read(ledgerProvider.notifier)
          .updateCaptureCandidateStatus(pair.creditCandidate.id, 'rejected');
      if (!context.mounted) return;
      showAppSnackBar(context, 'Transfer candidates dismissed.');
    } catch (e) {
      if (!context.mounted) return;
      showAppSnackBar(context, e.toString());
    }
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
  final localDate = date.toLocal();
  final diff = now.difference(localDate);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${localDate.year.toString().padLeft(4, '0')}-${localDate.month.toString().padLeft(2, '0')}-${localDate.day.toString().padLeft(2, '0')}';
}

String _candidateDisplayName(
  LedgerState state,
  CaptureCandidate candidate, {
  TransactionRecord? matchedPlan,
}) {
  // 1. Try clean merchant (existing or re-parsed from rawText)
  final cleanMerchant = resolveCleanMerchant(
    candidate.merchant,
    rawText: candidate.rawText,
  );
  if (cleanMerchant != null && cleanMerchant.isNotEmpty) {
    return cleanMerchant;
  }

  // 2. Try matched planned payment name
  if (matchedPlan?.name != null && matchedPlan!.name!.trim().isNotEmpty) {
    return matchedPlan.name!.trim();
  }

  // 3. Try suggested account name
  if (candidate.suggestedAccountId != null) {
    final acc = state.accounts
        .where((a) => a.id == candidate.suggestedAccountId)
        .firstOrNull;
    if (acc != null && acc.name.trim().isNotEmpty) {
      return acc.name.trim();
    }
  }

  // 4. Clean fallback for transaction type
  if (candidate.transactionType?.toLowerCase() == 'income') {
    return 'Income';
  }
  return 'Expense';
}

String _categoryChipText(LedgerState state, CaptureCandidate candidate) {
  final category = categoryById(state, candidate.suggestedCategoryId);
  final name = category?.name ?? 'Category';
  final reason = candidate.suggestedCategoryReason?.trim();
  if (reason == null || reason.isEmpty) return name;
  return '$name · $reason';
}

/// A responsive, non-overflowing chip designed for capture candidate and
/// notification cards across various screen widths and accessibility font scales.
class _ReviewQueueChip extends StatelessWidget {
  const _ReviewQueueChip({
    required this.label,
    required this.icon,
    required this.iconColor,
    this.labelStyle,
    this.semanticLabel,
  });

  final String label;
  final Widget icon;
  final Color iconColor;
  final TextStyle? labelStyle;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: semanticLabel ?? label,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTheme(
              data: IconThemeData(color: iconColor, size: 13),
              child: icon,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Flexible(
              child: Text(
                label,
                style:
                    labelStyle ??
                    theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
