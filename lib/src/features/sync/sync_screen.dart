import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../cloud_sync/cloud_sync_controller.dart';
import '../../cloud_sync/cloud_sync_write_guard.dart';
import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../common/route_scaffold.dart';
import '../transactions/transaction_row.dart';

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(cloudSyncControllerProvider.notifier)
          .checkAndTriggerSync(fromScreen: true);
    });
  }

  @override
  Widget build(BuildContext context) {
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
    final hasConflict =
        sync.phase == CloudSyncPhase.error &&
        (sync.error?.toLowerCase().contains('conflict') == true ||
            sync.error?.toLowerCase().contains('wallet changed') == true ||
            sync.error?.toLowerCase().contains('changed on another device') ==
                true);
    final localLatest = getLatestTransactionDate(state);
    final cloudLatest = sync.cloudLatestTransactionAt;
    final isCloudOlder = localLatest != null &&
        cloudLatest != null &&
        cloudLatest.isBefore(localLatest);
    final isCloudFewer = sync.cloudTransactionCount != null &&
        sync.cloudTransactionCount! < state.transactions.length;

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
                              enabled ? _phaseLabel(sync) : 'Not syncing',
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
                if (sync.errorDetails != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(
                      left: AppSpacing.md,
                      right: AppSpacing.sm,
                      bottom: AppSpacing.sm,
                    ),
                    title: Text(
                      'Technical details',
                      style: theme.textTheme.labelLarge,
                    ),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          sync.errorDetails!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (hasConflict) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: (isCloudOlder || isCloudFewer)
                          ? theme.colorScheme.errorContainer.withValues(alpha: 0.25)
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (isCloudOlder || isCloudFewer)
                            ? theme.colorScheme.error
                            : theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              (isCloudOlder || isCloudFewer)
                                  ? Icons.warning_amber_rounded
                                  : Icons.compare_arrows_rounded,
                              color: (isCloudOlder || isCloudFewer)
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.primary,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                (isCloudOlder || isCloudFewer)
                                    ? 'Potential Data Downgrade Detected'
                                    : 'Sync Conflict Detected',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: (isCloudOlder || isCloudFewer)
                                      ? theme.colorScheme.error
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          (isCloudOlder || isCloudFewer)
                              ? 'The cloud copy appears to be older or has fewer transactions than this device. Keeping this device will safely update the cloud.'
                              : 'Choose which complete wallet copy to keep. This replaces the other copy.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Table(
                          columnWidths: const {
                            0: FlexColumnWidth(2),
                            1: FlexColumnWidth(2.5),
                            2: FlexColumnWidth(2.5),
                          },
                          children: [
                            TableRow(
                              children: [
                                const SizedBox.shrink(),
                                Text(
                                  'This Device',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Cloud Copy',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const TableRow(children: [
                              SizedBox(height: 6),
                              SizedBox(height: 6),
                              SizedBox(height: 6),
                            ]),
                            TableRow(
                              children: [
                                Text('Latest Record', style: theme.textTheme.bodySmall),
                                Text(
                                  localLatest != null ? DateFormat.yMMMd().format(localLatest) : 'None',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  cloudLatest != null ? DateFormat.yMMMd().format(cloudLatest) : 'Unknown',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: isCloudOlder ? theme.colorScheme.error : null,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const TableRow(children: [
                              SizedBox(height: 4),
                              SizedBox(height: 4),
                              SizedBox(height: 4),
                            ]),
                            TableRow(
                              children: [
                                Text('Transactions', style: theme.textTheme.bodySmall),
                                Text(
                                  '${state.transactions.length}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  sync.cloudTransactionCount != null ? '${sync.cloudTransactionCount}' : 'Unknown',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: isCloudFewer ? theme.colorScheme.error : null,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            AppActionButton(
                              prominent: true,
                              onPressed: isWorking ? null : _confirmOverwriteCloud,
                              icon: Icons.cloud_upload_outlined,
                              label: (isCloudOlder || isCloudFewer)
                                  ? 'Keep this device & update cloud'
                                  : 'Overwrite cloud with this device',
                            ),
                            AppActionButton(
                              prominent: false,
                              onPressed: isWorking
                                  ? null
                                  : () => _confirmUseCloudCopy(isCloudOlder: isCloudOlder),
                              icon: Icons.cloud_download_outlined,
                              label: 'Use cloud copy',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
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
                    initialValue:
                        const [
                          null,
                          4,
                          6,
                          12,
                          24,
                        ].contains(sync.metadata?.syncIntervalHours)
                        ? sync.metadata?.syncIntervalHours
                        : null,
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
                        child: Text('Automatic (On change - Default)'),
                      ),
                      DropdownMenuItem(value: 4, child: Text('Every 4 hours')),
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
            const Gap(AppSpacing.md),
            SectionCard(
              title: 'Live Cloud Verification',
              subtitle:
                  'Directly query Google Cloud Firestore to verify what is stored on Firebase servers.',
              compact: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (sync.cloudVerificationStatus != null) ...[
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: sync.cloudVerificationStatus!.contains('100% In Sync') ||
                                sync.cloudVerificationStatus!.contains('Verified')
                            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                            : theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            sync.cloudVerificationStatus!.contains('100% In Sync') ||
                                    sync.cloudVerificationStatus!.contains('Verified')
                                ? Icons.verified_rounded
                                : Icons.info_outline_rounded,
                            size: 18,
                            color: sync.cloudVerificationStatus!.contains('100% In Sync') ||
                                    sync.cloudVerificationStatus!.contains('Verified')
                                ? theme.colorScheme.primary
                                : theme.colorScheme.error,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              sync.cloudVerificationStatus!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (sync.verifiedCloudRevision != null) ...[
                    InfoRow(
                      icon: Icons.tag_rounded,
                      label: 'Cloud Revision',
                      value: 'Revision #${sync.verifiedCloudRevision}',
                    ),
                    if (sync.verifiedCloudUpdatedAt != null)
                      InfoRow(
                        icon: Icons.cloud_done_outlined,
                        label: 'Firebase Server Time',
                        value: DateFormat.yMMMd().add_jms().format(sync.verifiedCloudUpdatedAt!),
                      ),
                    if (sync.verifiedCloudTransactionCount != null)
                      InfoRow(
                        icon: Icons.receipt_long_outlined,
                        label: 'Transactions on Cloud',
                        value: '${sync.verifiedCloudTransactionCount} records',
                      ),
                    if (sync.verifiedCloudAccountCount != null)
                      InfoRow(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'Accounts on Cloud',
                        value: '${sync.verifiedCloudAccountCount} accounts',
                      ),
                    if (sync.verifiedCloudChunkCount != null)
                      InfoRow(
                        icon: Icons.folder_zip_outlined,
                        label: 'Cloud Chunks',
                        value: '${sync.verifiedCloudChunkCount} chunk(s)',
                      ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  FilledButton.tonalIcon(
                    onPressed: sync.isVerifyingCloud
                        ? null
                        : () => ref
                            .read(cloudSyncControllerProvider.notifier)
                            .verifyCloudBackup(),
                    icon: sync.isVerifyingCloud
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_user_outlined),
                    label: Text(
                      sync.isVerifyingCloud
                          ? 'Checking Google Cloud…'
                          : 'Verify Cloud Copy in Firebase',
                    ),
                  ),
                ],
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

  Future<void> _confirmUseCloudCopy({bool isCloudOlder = false}) async {
    final localLatest = getLatestTransactionDate(ref.read(ledgerProvider));
    final cloudLatest =
        ref.read(cloudSyncControllerProvider).cloudLatestTransactionAt;

    final String message;
    final String title;
    final String action;

    if (isCloudOlder) {
      title = 'Replace with older cloud copy?';
      message =
          'WARNING: The cloud copy is older than your device records!\n\n'
          '• Local latest record: ${localLatest != null ? DateFormat.yMMMd().format(localLatest) : 'None'}\n'
          '• Cloud latest record: ${cloudLatest != null ? DateFormat.yMMMd().format(cloudLatest) : 'Older'}\n\n'
          'Using the cloud copy will replace your device data with older records and you may lose recent transactions. Are you sure you want to proceed?';
      action = 'Discard local & use cloud';
    } else {
      title = 'Use cloud wallet?';
      message =
          'This replaces the wallet on this device with the cloud copy. Unsynced local changes will be discarded.';
      action = 'Use cloud copy';
    }

    final confirmed = await _confirmReplacement(
      title: title,
      message: message,
      action: action,
    );
    if (confirmed != true || !mounted) return;
    await ref.read(cloudSyncControllerProvider.notifier).useCloudCopy();
  }

  Future<void> _confirmOverwriteCloud() async {
    final confirmed = await _confirmReplacement(
      title: 'Overwrite cloud wallet?',
      message:
          'This replaces the cloud wallet on your other devices with this device’s complete wallet.',
      action: 'Overwrite cloud',
    );
    if (confirmed != true || !mounted) return;
    await ref
        .read(cloudSyncControllerProvider.notifier)
        .overwriteCloudWithLocal();
  }

  Future<bool?> _confirmReplacement({
    required String title,
    required String message,
    required String action,
  }) => GlassDialog.show<bool>(
    context: context,
    title: title,
    message: message,
    barrierDismissible: true,
    actions: [
      GlassDialogAction(
        label: 'Cancel',
        onPressed: () => Navigator.of(context).pop(false),
      ),
      GlassDialogAction(
        label: action,
        isPrimary: true,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  );

  String _phaseLabel(CloudSyncState sync) {
    switch (sync.phase) {
      case CloudSyncPhase.checking:
        return 'Checking cloud wallet';
      case CloudSyncPhase.restoring:
        return 'Restoring from cloud';
      case CloudSyncPhase.uploading:
        return 'Uploading to cloud';
      case CloudSyncPhase.error:
        return 'Needs attention';
      default:
        return sync.pendingUpload
            ? 'Changes waiting to upload'
            : 'Synced with cloud';
    }
  }

  String _dateValue(String? value) {
    if (value == null) return 'Never';
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    return date.toLocal().toString().split('.')[0];
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
