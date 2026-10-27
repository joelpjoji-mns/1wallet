import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../design/tokens.dart';
import '../../offline_mode/offline_mode_controller.dart';
import '../../widgets/app_kit.dart';

/// Offline-mode status plus the backup actions an offline user owns:
/// encrypted export/import and the upgrade to Google backup & sync.
class OfflineModeCard extends StatelessWidget {
  const OfflineModeCard({super.key});

  static const upgradeKey = Key('offline-upgrade-google');

  @override
  Widget build(BuildContext context) {
    return AppGroupedSection(
      header: 'Offline mode',
      children: [
        const AppGroupedTile(
          leading: Icon(Icons.phonelink_lock_outlined),
          title: Text('Stored only on this device'),
          subtitle: Text(
            'Cloud sync is off and nothing is uploaded. Export an encrypted '
            'backup regularly so you can restore your wallet.',
          ),
        ),
        const GlassDivider(),
        AppGroupedTile(
          key: upgradeKey,
          leading: const Icon(Icons.cloud_upload_outlined),
          title: const Text('Back up & sync with Google'),
          subtitle: const Text(
            'Sign in to move this wallet to your Google account and keep it '
            'in sync across devices.',
          ),
          showChevron: true,
          onTap: () => showOfflineUpgradeSheet(context),
        ),
        const GlassDivider(),
        AppGroupedTile(
          leading: const Icon(Icons.file_download_outlined),
          title: const Text('Export encrypted backup'),
          subtitle: const Text('AES-256 protected with your own passphrase.'),
          showChevron: true,
          onTap: () => context.push('/data-backup'),
        ),
        const GlassDivider(),
        AppGroupedTile(
          leading: const Icon(Icons.restore_outlined),
          title: const Text('Import backup'),
          subtitle: const Text('Restore a 1Wallet backup file to this device.'),
          showChevron: true,
          onTap: () => context.push('/data-backup'),
        ),
      ],
    );
  }
}

/// Runs the offline → Google upgrade. The sheet starts Google sign-in, asks
/// which wallet to keep when the account already has one, and never closes
/// while the wallet is being moved.
Future<void> showOfflineUpgradeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const OfflineUpgradeSheet(),
  );
}

class OfflineUpgradeSheet extends ConsumerStatefulWidget {
  const OfflineUpgradeSheet({super.key});

  @override
  ConsumerState<OfflineUpgradeSheet> createState() =>
      _OfflineUpgradeSheetState();
}

class _OfflineUpgradeSheetState extends ConsumerState<OfflineUpgradeSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = ref.read(offlineModeControllerProvider.notifier);
      controller.acknowledge();
      controller.startGoogleUpgrade();
    });
  }

  Future<void> _close() async {
    final controller = ref.read(offlineModeControllerProvider.notifier);
    final stage = ref.read(offlineModeControllerProvider).stage;
    if (stage == OfflineUpgradeStage.awaitingChoice) {
      await controller.cancelUpgrade();
    }
    controller.acknowledge();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _choose(CloudWalletChoice choice) async {
    final confirmed = switch (choice) {
      CloudWalletChoice.keepLocal => await _confirm(
        title: 'Replace the Google wallet?',
        body:
            'The wallet stored in your Google account will be replaced by '
            'this device\'s wallet. Other devices will receive this wallet '
            'the next time they sync.',
        action: 'Replace Google wallet',
      ),
      CloudWalletChoice.keepCloud => await _confirm(
        title: 'Replace this device\'s wallet?',
        body:
            'This device will switch to the wallet stored in your Google '
            'account. An encrypted copy of this device\'s offline wallet is '
            'kept in its on-device automatic backup. Export a backup first '
            'from Data backup if you want a file you can restore later.',
        action: 'Use Google wallet',
      ),
      CloudWalletChoice.merge => await _confirm(
        title: 'Merge both wallets?',
        body:
            'Accounts, categories and records from both wallets are combined '
            'and uploaded to your Google account. Records you entered in '
            'both places may appear twice.',
        action: 'Merge wallets',
      ),
    };
    if (!confirmed || !mounted) return;
    await ref
        .read(offlineModeControllerProvider.notifier)
        .resolveCloudWalletChoice(choice);
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(offlineModeControllerProvider);
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !state.isBusy) _close();
      },
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: AppPanel(
          glass: true,
          radius: AppRadii.lg,
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Back up & sync with Google',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ..._body(context, state),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, OfflineModeState state) {
    final scheme = Theme.of(context).colorScheme;
    switch (state.stage) {
      case OfflineUpgradeStage.signingIn:
        return const [_Progress('Waiting for Google sign-in…')];
      case OfflineUpgradeStage.checkingCloud:
        return [
          _Progress(
            'Checking ${state.accountEmail ?? 'your Google account'} for an '
            'existing wallet…',
          ),
        ];
      case OfflineUpgradeStage.migrating:
        return const [
          _Progress(
            'Moving your wallet to your Google account. Keep the app open.',
          ),
        ];
      case OfflineUpgradeStage.completed:
        return [
          Row(
            children: [
              Icon(Icons.cloud_done_outlined, color: scheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Backup & sync is on for '
                  '${state.accountEmail ?? 'your Google account'}.',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(onPressed: _close, child: const Text('Done')),
        ];
      case OfflineUpgradeStage.awaitingChoice:
        return _choiceBody(context, state);
      case OfflineUpgradeStage.idle:
        return [
          if (state.errorMessage != null) ...[
            Text(state.errorMessage!, style: TextStyle(color: scheme.error)),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () => ref
                  .read(offlineModeControllerProvider.notifier)
                  .startGoogleUpgrade(),
              child: const Text('Try again'),
            ),
          ] else
            const _Progress('Preparing Google sign-in…'),
          const SizedBox(height: AppSpacing.xs),
          TextButton(onPressed: _close, child: const Text('Close')),
        ];
    }
  }

  List<Widget> _choiceBody(BuildContext context, OfflineModeState state) {
    final theme = Theme.of(context);
    final updated = state.cloudUpdatedAt;
    return [
      Text(
        '${state.accountEmail ?? 'This Google account'} already has a '
        '1Wallet wallet. Choose what to keep — nothing changes until you '
        'confirm.',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: AppSpacing.md),
      Table(
        columnWidths: const {
          0: FlexColumnWidth(2),
          1: FlexColumnWidth(2),
          2: FlexColumnWidth(2),
        },
        children: [
          TableRow(
            children: [
              const SizedBox.shrink(),
              Text('This device', style: theme.textTheme.labelLarge),
              Text('Google', style: theme.textTheme.labelLarge),
            ],
          ),
          TableRow(
            children: [
              const Text('Accounts'),
              Text('${state.localAccountCount}'),
              Text('${state.cloudAccountCount ?? '—'}'),
            ],
          ),
          TableRow(
            children: [
              const Text('Records'),
              Text('${state.localTransactionCount}'),
              Text('${state.cloudTransactionCount ?? '—'}'),
            ],
          ),
        ],
      ),
      if (updated != null) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Google wallet last updated '
          '${DateFormat.yMMMd().add_jm().format(updated.toLocal())}',
          style: theme.textTheme.bodySmall,
        ),
      ],
      const SizedBox(height: AppSpacing.md),
      PremiumRow(
        key: const Key('offline-upgrade-keep-local'),
        icon: Icons.smartphone_outlined,
        title: 'Keep this device\'s wallet',
        subtitle: 'Upload it and replace the wallet in your Google account.',
        onTap: () => _choose(CloudWalletChoice.keepLocal),
      ),
      const SizedBox(height: AppSpacing.xs),
      PremiumRow(
        key: const Key('offline-upgrade-keep-cloud'),
        icon: Icons.cloud_download_outlined,
        title: 'Use the Google wallet',
        subtitle: 'Replace this device\'s wallet with the one in Google.',
        onTap: () => _choose(CloudWalletChoice.keepCloud),
      ),
      const SizedBox(height: AppSpacing.xs),
      PremiumRow(
        key: const Key('offline-upgrade-merge'),
        icon: Icons.merge_type_outlined,
        title: 'Merge both',
        subtitle: 'Combine both wallets and upload the result.',
        onTap: () => _choose(CloudWalletChoice.merge),
      ),
      const SizedBox(height: AppSpacing.md),
      TextButton(
        onPressed: _close,
        child: const Text('Cancel and stay offline'),
      ),
    ];
  }
}

class _Progress extends StatelessWidget {
  const _Progress(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(message)),
      ],
    );
  }
}
