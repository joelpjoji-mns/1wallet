import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../cloud_sync/cloud_sync_controller.dart';
import '../../widgets/app_kit.dart';

class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sync = ref.watch(cloudSyncControllerProvider);
    final enabled = sync.phase != CloudSyncPhase.disabled;

    final isWorking =
        sync.phase == CloudSyncPhase.checking ||
        sync.phase == CloudSyncPhase.restoring ||
        sync.phase == CloudSyncPhase.uploading;

    return AppScreen(
      title: 'Sync',
      child: Column(
        children: [
          if (isWorking) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 16),
          ],
          SectionCard(
            title: 'Status',
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
                  icon: Icons.cloud_outlined,
                  label: 'Mode',
                  value: enabled ? 'Cloud' : 'Local',
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
                  icon: Icons.commit_outlined,
                  label: 'Cloud revision',
                  value: sync.metadata?.lastCloudRevision != null
                      ? sync.metadata!.lastCloudRevision.toString()
                      : 'None',
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
          const SizedBox(height: 24),
          if (enabled) ...[
            SectionCard(
              title: 'Settings',
              subtitle: 'Configure how often your wallet syncs with the cloud.',
              compact: true,
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int?>(
                    value: sync.metadata?.syncIntervalHours ?? 4,
                    decoration: InputDecoration(
                      labelText: 'Periodic Sync Interval',
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
                  const SizedBox(height: 8),
                  Text(
                    'Note: Automatic sync on change is always active when connected.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
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
