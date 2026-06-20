import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cloud_sync/cloud_sync_controller.dart';
import '../../data/ledger_providers.dart';
import '../../startup/startup_state.dart';
import 'brand_widgets.dart';

class LaunchScreen extends ConsumerWidget {
  const LaunchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(startupStateProvider);
    if (startup.isRecoverableError) {
      return RecoveryState(
        title: startup.title ?? 'Unable to open wallet',
        body: startup.message ?? 'Something went wrong while starting 1wallet.',
        actionLabel: 'Try again',
        onAction: () {
          ref.read(cloudSyncControllerProvider.notifier).retryBootstrap();
          ref.invalidate(ledgerProvider);
        },
        secondaryLabel: 'Reset local wallet',
        onSecondaryAction: () async {
          ref.read(cloudSyncControllerProvider.notifier).retryBootstrap();
          await ref.read(ledgerProvider.notifier).clearLocalWallet();
          ref.invalidate(ledgerProvider);
        },
      );
    }

    return BrandedLoadingState(
      stage: startup.stage,
      message: startup.message ?? 'Wallet ready',
      progress: startup.progress,
    );
  }
}
