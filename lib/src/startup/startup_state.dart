import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../cloud_sync/cloud_sync_controller.dart';
import '../data/ledger_models.dart';
import '../data/ledger_providers.dart';
import '../features/onboarding/onboarding_controller.dart';
import '../theme/theme_controller.dart';

final startupStateProvider = Provider<StartupState>((ref) {
  final auth = ref.watch(authControllerProvider);
  final ledgerLoad = ref.watch(ledgerLoadStateProvider);
  final ledger = ref.watch(ledgerProvider);
  final onboarding = ref.watch(onboardingControllerProvider);
  final theme = ref.watch(themeControllerProvider);
  final cloudSync = ref.watch(cloudSyncControllerProvider);

  if (!theme.isLoaded || auth.phase == AuthPhase.initializing) {
    return const StartupState.pending(
      stage: StartupStage.session,
      message: 'Checking your secure session',
    );
  }

  if (!auth.isAuthenticated) {
    return StartupState.ready(
      destination: StartupDestination.login,
      message: auth.errorMessage,
    );
  }

  final userId = auth.user!.id;

  if (!ledgerLoad.isReady) {
    return const StartupState.pending(
      stage: StartupStage.wallet,
      message: 'Restoring your wallet',
    );
  }

  if (ledgerLoad.errorMessage != null) {
    return StartupState.recoverableError(
      title: 'Wallet setup needs attention',
      message: ledgerLoad.errorMessage!,
    );
  }

  final hasWalletData = _hasWalletData(ledger);

  // Existing local/restored data is authoritative for startup routing. Do not
  // keep the user on onboarding or a sync splash while usable wallet data is
  // already present; cloud sync can finish in the background.
  if (hasWalletData) {
    if (!onboarding.completed || onboarding.userId != userId) {
      Future.microtask(() {
        ref
            .read(onboardingControllerProvider.notifier)
            .setCompleted(userId, true);
      });
    }
    return const StartupState.ready(destination: StartupDestination.home);
  }

  if (cloudSync.phase == CloudSyncPhase.error) {
    return StartupState.recoverableError(
      title: 'Firebase restore failed',
      message: cloudSync.error ?? 'Could not restore your wallet backup.',
    );
  }

  // Only block on Firebase restore when there is no local wallet to show.
  if (!cloudSync.bootstrapComplete || cloudSync.bootstrappedUserId != userId) {
    return const StartupState.pending(
      stage: StartupStage.wallet,
      message: 'Syncing your wallet from Firebase',
    );
  }

  if (cloudSync.phase == CloudSyncPhase.checking ||
      cloudSync.phase == CloudSyncPhase.restoring) {
    return const StartupState.pending(
      stage: StartupStage.wallet,
      message: 'Restoring your Google wallet data',
    );
  }

  if (onboarding.userId != userId && !onboarding.isLoading) {
    Future.microtask(() {
      ref.read(onboardingControllerProvider.notifier).loadForUser(userId);
    });
    return const StartupState.pending(
      stage: StartupStage.wallet,
      message: 'Loading your wallet setup',
    );
  }

  if (onboarding.isLoading) {
    return const StartupState.pending(
      stage: StartupStage.wallet,
      message: 'Loading your wallet setup',
    );
  }

  if (onboarding.errorMessage != null) {
    return StartupState.recoverableError(
      title: 'Wallet setup needs attention',
      message: onboarding.errorMessage!,
    );
  }

  return const StartupState.ready(destination: StartupDestination.onboarding);
});

bool _hasWalletData(LedgerState ledger) {
  return ledger.accounts.isNotEmpty ||
      ledger.transactions.isNotEmpty ||
      ledger.captureCandidates.isNotEmpty ||
      ledger.importBatches.isNotEmpty ||
      ledger.budgets.isNotEmpty ||
      ledger.goals.isNotEmpty;
}

enum StartupStage { session, wallet, ready }

enum StartupDestination { launch, login, onboarding, home }

@immutable
class StartupState {
  const StartupState._({
    required this.stage,
    required this.destination,
    required this.isPending,
    this.title,
    this.message,
    this.isRecoverableError = false,
  });

  const StartupState.pending({
    required StartupStage stage,
    required String message,
  }) : this._(
         stage: stage,
         destination: StartupDestination.launch,
         isPending: true,
         message: message,
       );

  const StartupState.ready({
    required StartupDestination destination,
    String? message,
  }) : this._(
         stage: StartupStage.ready,
         destination: destination,
         isPending: false,
         message: message,
       );

  const StartupState.recoverableError({
    required String title,
    required String message,
  }) : this._(
         stage: StartupStage.wallet,
         destination: StartupDestination.launch,
         isPending: false,
         title: title,
         message: message,
         isRecoverableError: true,
       );

  final StartupStage stage;
  final StartupDestination destination;
  final bool isPending;
  final String? title;
  final String? message;
  final bool isRecoverableError;
}
