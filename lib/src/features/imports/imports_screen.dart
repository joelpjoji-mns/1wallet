import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../../ledger/ledger_selectors.dart';
import '../common/route_scaffold.dart';
import '../transactions/transaction_row.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';

class ImportsScreen extends ConsumerWidget {
  const ImportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ledgerProvider);
    final pending = state.captureCandidates
        .where((candidate) => candidate.status == 'pending')
        .length;
    return RouteScaffold(
      title: 'Import & backup',
      child: Column(
        children: [
          SectionCard(
            title: 'Import center',
            subtitle:
                'Queue SMS drafts, review captures, and restore archives.',
            child: Row(
              children: [
                Expanded(
                  child: MetricTile(
                    label: 'Pending review',
                    value: '$pending',
                    icon: Icons.fact_check_outlined,
                    compact: true,
                    tone: pending > 0
                        ? MetricTone.warning
                        : MetricTone.standard,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: MetricTile(
                    label: 'Imports',
                    value: '${state.importBatches.length}',
                    icon: Icons.file_upload_outlined,
                    compact: true,
                  ),
                ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          PremiumRow(
            icon: Icons.sms_outlined,
            title: 'Import SMS',
            subtitle: 'Paste a bank or card message and queue a review draft',
            onTap: () => context.push('/import-sms'),
          ),
          const SizedBox(height: AppSpacing.sm),
          PremiumRow(
            icon: Icons.backup_outlined,
            title: 'Data backup',
            subtitle: 'Export or restore a checksum-protected ledger archive',
            onTap: () => context.push('/data-backup'),
          ),
          const SizedBox(height: AppSpacing.sm),
          PremiumRow(
            icon: Icons.fact_check_outlined,
            title: 'Review queue',
            subtitle: 'Confirm, edit, or dismiss imported capture candidates',
            meta: pending == 0 ? null : '$pending',
            onTap: () => context.push('/review'),
          ),
          const SizedBox(height: AppSpacing.sm),
          PremiumRow(
            icon: Icons.table_chart_outlined,
            title: 'Wallet CSV',
            subtitle: 'Paste CSV rows, preview, and import transactions',
            onTap: () => context.push('/import-wallet-csv'),
          ),
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Recent imports',
            child: state.importBatches.isEmpty
                ? const EmptyState(
                    icon: Icons.history_toggle_off_outlined,
                    title: 'No import history yet',
                    body: 'SMS and CSV import batches will appear here.',
                  )
                : Column(
                    children: [
                      for (final batch in state.importBatches.take(5)) ...[
                        PremiumRow(
                          icon: Icons.file_upload_outlined,
                          title: transactionTypeLabel(batch.source),
                          subtitle:
                              '${DateFormat.MMMd().add_jm().format(batch.createdAt)} · ${transactionTypeLabel(batch.status)}',
                          meta:
                              '${batch.importedCount}/${batch.rowCount}${batch.duplicateCount > 0 ? ' · ${batch.duplicateCount} dupes' : ''}',
                          onTap: () => context.push('/imports/${batch.id}'),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class ImportBatchDetailScreen extends ConsumerWidget {
  const ImportBatchDetailScreen({required this.batchId, super.key});

  final String batchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ledgerProvider);
    final batch = state.importBatches.firstWhereOrNull(
      (batch) => batch.id == batchId,
    );
    if (batch == null) {
      return RouteScaffold(
        title: 'Import detail',
        child: EmptyState(
          icon: Icons.file_upload_outlined,
          title: 'Import not found',
          body: 'This import batch is not available in the local ledger.',
          actionLabel: 'Back to imports',
          onAction: () => context.push('/imports'),
        ),
      );
    }
    final transactions = state.transactions
        .where((transaction) => transaction.importBatchId == batch.id)
        .toList();
    return RouteScaffold(
      title: 'Import detail',
      child: Column(
        children: [
          SectionCard(
            title: transactionTypeLabel(batch.source),
            subtitle: DateFormat.yMMMMEEEEd().add_jm().format(batch.createdAt),
            child: Column(
              children: [
                InfoRow(
                  label: 'Status',
                  value: transactionTypeLabel(batch.status),
                  icon: Icons.verified_outlined,
                  tone: batch.status == 'rolled_back'
                      ? MetricTone.warning
                      : MetricTone.standard,
                ),
                InfoRow(
                  label: 'Imported rows',
                  value: '${batch.importedCount}/${batch.rowCount}',
                  icon: Icons.playlist_add_check_outlined,
                ),
                InfoRow(
                  label: 'Duplicates skipped',
                  value: '${batch.duplicateCount}',
                  icon: Icons.content_copy_outlined,
                  tone: batch.duplicateCount > 0
                      ? MetricTone.warning
                      : MetricTone.standard,
                ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Imported transactions',
            child: transactions.isEmpty
                ? EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: batch.status == 'rolled_back'
                        ? 'Import rolled back'
                        : 'No linked transactions',
                    body: batch.status == 'rolled_back'
                        ? 'Transactions from this import were removed.'
                        : 'Older imports may not have transaction links.',
                  )
                : Column(
                    children: [
                      for (final transaction in transactions.take(8)) ...[
                        TransactionRow(
                          state: state,
                          transaction: transaction,
                          onTap: () =>
                              context.push('/transaction/${transaction.id}'),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
                  ),
          ),
          const Gap(AppSpacing.lg),
          FilledButton.tonalIcon(
            onPressed: batch.status == 'rolled_back' || transactions.isEmpty
                ? null
                : () => _confirmRollback(context, ref, batch),
            icon: const Icon(Icons.undo_rounded),
            label: const Text('Rollback import'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRollback(
    BuildContext context,
    WidgetRef ref,
    ImportBatch batch,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rollback import?'),
        content: const Text(
          'This removes transactions created by this import batch from the local ledger.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Rollback'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = await ref
        .read(ledgerProvider.notifier)
        .rollbackImportBatch(batch.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Rolled back $removed imported transactions.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}
