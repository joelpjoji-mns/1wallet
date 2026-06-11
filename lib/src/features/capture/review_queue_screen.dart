import 'package:flutter/material.dart';
import '../common/route_scaffold.dart';
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
    final warnings = candidates.fold<int>(
      0,
      (sum, candidate) => sum + candidate.warnings.length,
    );
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
                AppSpacing.md,
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
                            SizedBox(
                              width: 140,
                              child: MetricTile(
                                label: 'Warnings',
                                value: '$warnings',
                                icon: Icons.warning_amber_outlined,
                                compact: true,
                                tone: warnings == 0
                                    ? MetricTone.standard
                                    : MetricTone.danger,
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
                              if (warnings > 0)
                                OutlinedButton.icon(
                                  onPressed: () => _clearAllWarnings(
                                    context,
                                    ref,
                                    candidates.where((c) => c.warnings.isNotEmpty).map((e) => e.id),
                                  ),
                                  icon: const Icon(Icons.cleaning_services_outlined),
                                  label: const Text('Dismiss all warnings'),
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
                    final hasWarnings = candidate.warnings.isNotEmpty;
                    final theme = Theme.of(context);
                    final scheme = theme.colorScheme;
                    return InkWell(
                      onTap: () => context.push('/capture/${candidate.id}'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: scheme.outlineVariant.withAlpha(100),
                            ),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            IconBubble(
                              icon: candidate.source == 'sms'
                                  ? Icons.sms_rounded
                                  : Icons.receipt_long_rounded,
                              color: scheme.primary,
                              compact: true,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          candidate.merchant ??
                                              candidate.transactionType ??
                                              'Unknown',
                                          style: theme.textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (candidate.parsedAmount != null)
                                        Text(
                                          formatMoney(
                                            candidate.parsedAmount!,
                                            state.preferences.locale,
                                          ),
                                          style: theme.textTheme.titleSmall?.copyWith(
                                            color: scheme.primary,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(
                                        DateFormat.MMMd(
                                          state.preferences.locale.replaceAll('_', '-'),
                                        ).add_jm().format(candidate.createdAt),
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                          fontSize: 11,
                                        ),
                                      ),
                                      if (hasWarnings) ...[
                                        const SizedBox(width: AppSpacing.sm),
                                        Icon(
                                          Icons.warning_amber_rounded,
                                          size: 12,
                                          color: scheme.error,
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          '${candidate.warnings.length} warnings',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: scheme.error,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                      const Spacer(),
                                      if (candidate.status == 'pending') ...[
                                        IconButton(
                                          onPressed: () => _updateCandidateStatus(
                                              context, ref, candidate.id, 'rejected'),
                                          icon: const Icon(Icons.close_rounded, size: 20),
                                          color: scheme.error,
                                          visualDensity: VisualDensity.compact,
                                          tooltip: 'Dismiss',
                                        ),
                                        IconButton(
                                          onPressed: () => _updateCandidateStatus(
                                              context, ref, candidate.id, 'approved'),
                                          icon: const Icon(Icons.check_rounded, size: 20),
                                          color: scheme.primary,
                                          style: IconButton.styleFrom(
                                            backgroundColor: scheme.primaryContainer,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          tooltip: 'Confirm',
                                        ),
                                      ] else
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: scheme.surfaceContainerHigh,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            candidate.status.toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
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
    if (status == 'approved') {
      await ref.read(ledgerProvider.notifier).approveCaptureCandidate(id);
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
  }

  Future<void> _clearCandidateWarnings(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    await ref.read(ledgerProvider.notifier).clearCaptureCandidateWarnings(id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Warnings dismissed.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
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

  Future<void> _clearAllWarnings(
    BuildContext context,
    WidgetRef ref,
    Iterable<String> ids,
  ) async {
    final notifier = ref.read(ledgerProvider.notifier);
    int count = 0;
    for (final id in ids) {
      await notifier.clearCaptureCandidateWarnings(id);
      count++;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Warnings dismissed for $count candidates.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}
