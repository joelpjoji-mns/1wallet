import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../cloud_sync/cloud_sync_controller.dart';
import '../../data/ledger_codec.dart';
import '../../widgets/app_kit.dart';
import '../common/route_scaffold.dart';

class UpdatesScreen extends ConsumerStatefulWidget {
  const UpdatesScreen({super.key});

  @override
  ConsumerState<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends ConsumerState<UpdatesScreen> {
  var _checking = false;

  Future<void> _checkNow() async {
    if (_checking) return;
    setState(() => _checking = true);

    try {
      await ref
          .read(cloudSyncControllerProvider.notifier)
          .uploadSnapshot(reason: 'manual-check');
      if (!mounted) return;

      final sync = ref.read(cloudSyncControllerProvider);
      final message = switch (sync.phase) {
        CloudSyncPhase.error =>
          sync.error ?? 'Update check finished with a sync warning.',
        CloudSyncPhase.disabled =>
          sync.disabledReason ?? 'Sign in with Google to check release state.',
        _ => 'Checked update and sync status successfully.',
      };

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Could not check updates: $error'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(cloudSyncControllerProvider);

    return RouteScaffold(
      title: 'Updates',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: 'Release channel',
            subtitle: 'Flutter currently tracks the stable production channel.',
            child: Column(
              children: [
                const InfoRow(
                  icon: Icons.shield_outlined,
                  label: 'Channel',
                  value: 'Stable',
                ),
                InfoRow(
                  icon: Icons.data_object_outlined,
                  label: 'Ledger schema',
                  value: 'v$currentLedgerStateVersion',
                ),
                const InfoRow(
                  icon: Icons.phone_android_outlined,
                  label: 'Update source',
                  value: 'App Store / Play Store',
                ),
              ],
            ),
          ),
          const Gap(12),
          SectionCard(
            title: 'Status',
            subtitle: 'Cloud sync metadata used to validate release readiness.',
            child: Column(
              children: [
                InfoRow(
                  icon: Icons.cloud_outlined,
                  label: 'Sync phase',
                  value: _phaseLabel(sync.phase),
                  tone: sync.phase == CloudSyncPhase.error
                      ? MetricTone.warning
                      : MetricTone.standard,
                ),
                InfoRow(
                  icon: Icons.schedule_outlined,
                  label: 'Last upload',
                  value: _formatDate(sync.metadata?.lastPushedAt),
                ),
                InfoRow(
                  icon: Icons.cloud_download_outlined,
                  label: 'Last restore',
                  value: _formatDate(sync.metadata?.lastPulledAt),
                ),
                InfoRow(
                  icon: Icons.commit_outlined,
                  label: 'Cloud revision',
                  value: sync.metadata?.lastCloudRevision?.toString() ?? 'None',
                ),
                if (sync.error != null)
                  InfoRow(
                    icon: Icons.error_outline,
                    label: 'Latest warning',
                    value: sync.error!,
                    tone: MetricTone.warning,
                  ),
              ],
            ),
          ),
          const Gap(12),
          SectionCard(
            title: 'What this screen tracks',
            subtitle:
                'Parity with RN update visibility while Flutter-native updater lands.',
            child: const Column(
              children: [
                _BulletLine('Current app/channel visibility'),
                _BulletLine('Last cloud push and restore checkpoints'),
                _BulletLine('Wallet schema compatibility state'),
              ],
            ),
          ),
          const Gap(12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _checking ? null : _checkNow,
                icon: _checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(_checking ? 'Checking…' : 'Check now'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => context.push('/sync'),
                icon: const Icon(Icons.cloud_sync_outlined),
                label: const Text('Open sync details'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BulletLine extends StatelessWidget {
  const _BulletLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}

String _phaseLabel(CloudSyncPhase phase) {
  return switch (phase) {
    CloudSyncPhase.disabled => 'Disabled',
    CloudSyncPhase.idle => 'Synced',
    CloudSyncPhase.checking => 'Checking cloud wallet',
    CloudSyncPhase.restoring => 'Restoring wallet',
    CloudSyncPhase.uploading => 'Uploading snapshot',
    CloudSyncPhase.error => 'Needs attention',
  };
}

String _formatDate(String? value) {
  if (value == null || value.trim().isEmpty) return 'Never';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  final local = parsed.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
