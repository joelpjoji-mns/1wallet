import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../auth/auth_controller.dart';
import '../../cloud_sync/cloud_sync_controller.dart';
import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../common/route_scaffold.dart';
import '../transactions/transaction_row.dart';

class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sync = ref.watch(cloudSyncControllerProvider);
    final enabled = sync.phase != CloudSyncPhase.disabled;
    final state = ref.watch(ledgerProvider);
    final pending = state.captureCandidates
        .where((candidate) => candidate.status == 'pending')
        .length;

    final isWorking =
        sync.phase == CloudSyncPhase.checking ||
        sync.phase == CloudSyncPhase.restoring ||
        sync.phase == CloudSyncPhase.uploading;

    return AppScreen(
      title: 'Data & Sync',
      child: Column(
        children: [
          if (isWorking) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 16),
          ],
          
          // --- CLOUD SYNC SECTION ---
          SectionCard(
            title: 'Cloud Sync',
            subtitle:
                'Google sign-in, cloud restore, and automatic wallet upload.',
            compact: true,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: enabled
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: isWorking
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              )
                            : Icon(
                                enabled
                                    ? Icons.cloud_done_outlined
                                    : Icons.cloud_off_outlined,
                                size: 22,
                                color: enabled
                                    ? theme.colorScheme.onPrimaryContainer
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              enabled ? _phaseLabel(sync.phase) : 'Not syncing',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              enabled
                                  ? 'Cloud sync is connected for this Google account.'
                                  : sync.disabledReason ??
                                        'Sign in to enable sync.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                InfoRow(
                  icon: Icons.schedule_outlined,
                  label: 'Last upload',
                  value: _dateValue(sync.metadata?.lastPushedAt),
                ),
                InfoRow(
                  icon: Icons.cloud_download_outlined,
                  label: 'Last restore',
                  value: _dateValue(sync.metadata?.lastPulledAt),
                ),
                InfoRow(
                  icon: Icons.hourglass_empty_outlined,
                  label: 'Pending upload',
                  value: sync.pendingUpload ? 'Yes' : 'No',
                  tone: sync.pendingUpload
                      ? MetricTone.warning
                      : MetricTone.positive,
                ),
                if (sync.error != null)
                  InfoRow(
                    icon: Icons.error_outline,
                    label: 'Sync error',
                    value: sync.error!,
                    tone: MetricTone.warning,
                  ),
              ],
            ),
          ),
          
          if (enabled) ...[
            const SizedBox(height: 16),
            SectionCard(
              title: 'Auto Upload Interval',
              compact: true,
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int?>(
                    value: sync.metadata?.syncIntervalHours ?? 4,
                    decoration: InputDecoration(
                      labelText: 'Interval',
                      labelStyle: theme.textTheme.bodyMedium,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: null,
                        child: Text('Automatic (On change)'),
                      ),
                      DropdownMenuItem(
                        value: 4,
                        child: Text('Every 4 hours (Default)'),
                      ),
                      DropdownMenuItem(value: 6, child: Text('Every 6 hours')),
                      DropdownMenuItem(
                        value: 12,
                        child: Text('Every 12 hours'),
                      ),
                      DropdownMenuItem(value: 24, child: Text('Daily')),
                    ],
                    onChanged: (value) {
                      ref
                          .read(cloudSyncControllerProvider.notifier)
                          .updateSyncInterval(value);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: FilledButton.icon(
                onPressed: isWorking
                    ? null
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Starting manual sync...'),
                          ),
                        );
                        ref
                            .read(cloudSyncControllerProvider.notifier)
                            .fullSync(reason: 'manual');
                      },
                icon: const Icon(Icons.sync_rounded),
                label: Text(isWorking ? 'Syncing...' : 'Sync now'),
              ),
            ),
          ],
          
          const Gap(AppSpacing.lg),
          
          // --- IMPORT / BACKUP SECTION ---
          SectionCard(
            title: 'Data & Imports',
            subtitle:
                'Queue SMS drafts, review captures, and import/export CSVs.',
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
            title: 'Local File Backup',
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
          
          const Gap(AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: isWorking
                ? null
                : () => _cleanupLegacyData(context, ref),
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Clean up legacy cloud data'),
          ),
        ],
      ),
    );
  }

  String _phaseLabel(CloudSyncPhase phase) {
    switch (phase) {
      case CloudSyncPhase.checking:
        return 'Checking cloud wallet';
      case CloudSyncPhase.restoring:
        return 'Restoring from cloud';
      case CloudSyncPhase.uploading:
        return 'Uploading to cloud';
      case CloudSyncPhase.error:
        return 'Needs attention';
      default:
        return 'Synced locally';
    }
  }

  String _dateValue(String? value) {
    if (value == null) return 'Never';
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    return date.toLocal().toString().split('.')[0];
  }

  Future<void> _cleanupLegacyData(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cleaning up legacy cloud data...')),
    );

    try {
      final firestore = FirebaseFirestore.instance;
      final defaultWallet = firestore.doc('users/${user.id}/wallets/default');
      final walletDoc = await defaultWallet.get();

      if (!walletDoc.exists) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No legacy data found to clean.')),
        );
        return;
      }

      final snapshotId = walletDoc.data()?['latestSnapshotId'] as String?;
      if (snapshotId != null) {
        final chunks = await defaultWallet
            .collection('snapshots/$snapshotId/chunks')
            .get();
        final batch = firestore.batch();
        for (final doc in chunks.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
      await defaultWallet.delete();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Legacy data successfully cleaned!')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cleanup failed: $e')));
    }
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
          onAction: () => context.pop(),
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
