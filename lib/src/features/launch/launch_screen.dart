import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../cloud_sync/cloud_sync_controller.dart';
import '../../data/ledger_providers.dart';
import '../../startup/startup_state.dart';
import '../onboarding/onboarding_controller.dart';
import 'brand_widgets.dart';

final latestAutoBackupFileProvider =
    FutureProvider.autoDispose<File?>((ref) async {
      return ref.read(ledgerProvider.notifier).getLatestAutoBackupFile();
    });

class LaunchScreen extends ConsumerWidget {
  const LaunchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(startupStateProvider);
    final autoBackupAsync = ref.watch(latestAutoBackupFileProvider);

    if (startup.isRecoverableError) {
      final autoBackupFile = autoBackupAsync.valueOrNull;

      if (autoBackupFile != null) {
        return RecoveryState(
          title: startup.title ?? 'Unable to open wallet',
          body:
              startup.message ?? 'Something went wrong while starting 1wallet.',
          actionLabel: 'Restore latest auto-backup',
          onAction: () async {
            try {
              await ref
                  .read(ledgerProvider.notifier)
                  .restoreFromAutoBackup(autoBackupFile, force: true);
              final user = ref.read(authControllerProvider).user;
              if (user != null) {
                await ref
                    .read(onboardingControllerProvider.notifier)
                    .setCompleted(user.id, true);
              }
              ref.read(cloudSyncControllerProvider.notifier).skipBootstrap();
              await ref
                  .read(cloudSyncControllerProvider.notifier)
                  .uploadSnapshot(reason: 'restore_auto_backup');
              ref.invalidate(ledgerProvider);
            } catch (e) {
              debugPrint('Failed to restore from auto backup: $e');
            }
          },
          secondaryLabel: 'Retry cloud sync',
          onSecondaryAction: () {
            ref.read(cloudSyncControllerProvider.notifier).retryBootstrap();
            ref.invalidate(ledgerProvider);
          },
          tertiaryLabel: 'Open wallet anyway',
          onTertiaryAction: () {
            final user = ref.read(authControllerProvider).user;
            if (user != null) {
              ref
                  .read(onboardingControllerProvider.notifier)
                  .setCompleted(user.id, true);
            }
            ref.read(cloudSyncControllerProvider.notifier).skipBootstrap();
          },
        );
      }

      return RecoveryState(
        title: startup.title ?? 'Unable to open wallet',
        body: startup.message ?? 'Something went wrong while starting 1wallet.',
        actionLabel: 'Try again',
        onAction: () {
          ref.read(cloudSyncControllerProvider.notifier).retryBootstrap();
          ref.invalidate(ledgerProvider);
        },
        secondaryLabel: 'Open wallet anyway',
        onSecondaryAction: () {
          final user = ref.read(authControllerProvider).user;
          if (user != null) {
            ref
                .read(onboardingControllerProvider.notifier)
                .setCompleted(user.id, true);
          }
          ref.read(cloudSyncControllerProvider.notifier).skipBootstrap();
        },
        tertiaryLabel: 'Reset local wallet',
        onTertiaryAction: () async {
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
