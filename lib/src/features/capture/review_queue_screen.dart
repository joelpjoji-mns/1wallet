import 'package:flutter/material.dart';
import '../../ledger/ledger_selectors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review queue'),
        actions: [
          IconButton(
            tooltip: 'Import SMS',
            icon: const Icon(Icons.sms_outlined),
            onPressed: () => context.push('/import-sms'),
          ),
          IconButton(
            tooltip: 'Import CSV',
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: () => context.push('/import-wallet-csv'),
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
                                    'approved'),
                                icon: const Icon(Icons.done_all_outlined),
                                label: const Text('Approve all'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => _updateAllPending(
                                    context,
                                    ref,
                                    candidates.map((e) => e.id),
                                    'rejected'),
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
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final candidate = candidates[index];
                    final theme = Theme.of(context);
                    final scheme = theme.colorScheme;
                    final isIncome = candidate.transactionType == 'income';
                    final colorScheme = isIncome ? ColorScheme.fromSeed(seedColor: Colors.green, brightness: theme.brightness) : scheme;

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                      child: Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            candidate.merchant ?? candidate.transactionType?.toUpperCase() ?? 'UNKNOWN',
                                            style: theme.textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          Text(
                                            DateFormat.MMMd(state.preferences.locale.replaceAll('_', '-')).add_jm().format(candidate.createdAt),
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (candidate.parsedAmount != null)
                                      Text(
                                        (isIncome ? '+' : '') + formatMoney(candidate.parsedAmount!, state.preferences.locale),
                                        style: theme.textTheme.titleLarge?.copyWith(
                                          color: isIncome ? Colors.green.shade600 : scheme.onSurface,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -0.5,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.md),
                                Wrap(
                                  spacing: AppSpacing.sm,
                                  runSpacing: AppSpacing.sm,
                                  children: [
                                    if (candidate.suggestedAccountId != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: scheme.primaryContainer.withValues(alpha: 0.5),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.account_balance_wallet_rounded, size: 14, color: scheme.primary),
                                            const SizedBox(width: 4),
                                            Text(
                                              state.accounts.where((a) => a.id == candidate.suggestedAccountId).firstOrNull?.name ?? 'Account',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: scheme.primary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (candidate.suggestedCategoryId != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: scheme.secondaryContainer.withValues(alpha: 0.5),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.category_rounded, size: 14, color: scheme.secondary),
                                            const SizedBox(width: 4),
                                            Text(
                                              state.categories.where((c) => c.id == candidate.suggestedCategoryId).firstOrNull?.name ?? 'Category',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: scheme.secondary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                                if (candidate.rawText != null && candidate.rawText!.isNotEmpty) ...[
                                  const SizedBox(height: AppSpacing.md),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(AppSpacing.md),
                                    decoration: BoxDecoration(
                                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
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
                                          onPressed: () => _updateCandidateStatus(context, ref, candidate.id, 'rejected'),
                                          icon: const Icon(Icons.close_rounded),
                                          label: const Text('Dismiss'),
                                          style: TextButton.styleFrom(
                                            foregroundColor: scheme.error,
                                            padding: const EdgeInsets.symmetric(vertical: 16),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed: () => _updateCandidateStatus(context, ref, candidate.id, 'approved'),
                                          icon: const Icon(Icons.check_rounded),
                                          label: const Text('Confirm'),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: colorScheme.primaryContainer,
                                            foregroundColor: colorScheme.onPrimaryContainer,
                                            padding: const EdgeInsets.symmetric(vertical: 16),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  },
                  childCount: candidates.length,
                ),
              ),
            // Bottom padding to ensure last item is fully visible
            const SliverToBoxAdapter(
              child: SizedBox(height: AppSpacing.xxl),
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
    int count = 0;
    for (final id in ids) {
      if (status == 'approved') {
        await notifier.approveCaptureCandidate(id);
      } else {
        await notifier.updateCaptureCandidateStatus(id, status);
      }
      count++;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$count candidates marked $status.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }


}
