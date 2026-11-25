import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_controller.dart';
import '../../auth/auth_session_teardown.dart';
import '../../cloud_sync/cloud_sync_controller.dart';
import '../../data/ledger_providers.dart';
import '../../startup/startup_state.dart';
import '../onboarding/onboarding_controller.dart';
import '../settings/offline_mode_section.dart';
import 'brand_widgets.dart';

final latestAutoBackupFileProvider = FutureProvider.autoDispose<File?>((
  ref,
) async {
  return ref.read(ledgerProvider.notifier).getLatestAutoBackupFile();
});

class LaunchScreen extends ConsumerStatefulWidget {
  const LaunchScreen({super.key});

  @override
  ConsumerState<LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends ConsumerState<LaunchScreen> {
  bool _signingOut = false;

  Future<void> _signOut() async {
    if (_signingOut) return;
    final auth = ref.read(authControllerProvider);
    // An offline wallet has no other copy, so leaving it must be confirmed
    // and erases it; a Google wallet stays safe in the cloud.
    if (auth.isLocalOnly) {
      await confirmOfflineSignOut(context, ref);
      return;
    }
    setState(() => _signingOut = true);
    final router = GoRouter.of(context);
    try {
      await signOutAppSession(ref);
      router.go('/login');
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final startup = ref.watch(startupStateProvider);
    final auth = ref.watch(authControllerProvider);
    final onSignOut = (auth.user != null || auth.isLocalOnly) && !_signingOut
        ? _signOut
        : null;
    final autoBackupAsync = ref.watch(latestAutoBackupFileProvider);

    if (startup.isRecoverableError) {
      final autoBackupFile = autoBackupAsync.valueOrNull;

      if (autoBackupFile != null) {
        return RecoveryState(
          title: startup.title ?? 'Unable to open wallet',
          body:
              startup.message ?? 'Something went wrong while starting 1wallet.',
          actionLabel: 'Review local backup restore',
          onAction: () => context.push('/data-backup'),
          secondaryLabel: 'Retry cloud sync',
          onSecondaryAction: () {
            ref.read(cloudSyncControllerProvider.notifier).retryBootstrap();
            ref.invalidate(ledgerProvider);
          },
          tertiaryLabel: 'Open wallet anyway',
          onTertiaryAction: () {
            final ownerId = ref.read(authControllerProvider).ownerId;
            if (ownerId != null) {
              ref
                  .read(onboardingControllerProvider.notifier)
                  .setCompleted(ownerId, true);
            }
            ref.read(cloudSyncControllerProvider.notifier).skipBootstrap();
          },
          onSignOut: onSignOut,
        );
      }

      return RecoveryState(
        title: startup.title ?? 'Unable to open wallet',
        body: startup.message ?? 'Something went wrong while starting 1wallet.',
        actionLabel: 'Try again',
        onAction: () {
          ref.read(authControllerProvider.notifier).retryLocalOwnershipCheck();
          ref.read(cloudSyncControllerProvider.notifier).retryBootstrap();
          ref.invalidate(ledgerProvider);
        },
        secondaryLabel: 'Import a backup file',
        onSecondaryAction: () => context.push('/data-backup'),
        tertiaryLabel: 'Reset local wallet',
        onTertiaryAction: () async {
          ref.read(cloudSyncControllerProvider.notifier).retryBootstrap();
          await ref.read(ledgerProvider.notifier).clearLocalWallet();
          ref.invalidate(ledgerProvider);
        },
        onSignOut: onSignOut,
      );
    }

    return BrandedLoadingState(
      stage: startup.stage,
      message: startup.message ?? 'Wallet ready',
      progress: startup.progress,
    );
  }
}
