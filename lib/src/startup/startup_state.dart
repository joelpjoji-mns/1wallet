import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/app_mode.dart';
import '../auth/auth_controller.dart';
import '../cloud_sync/cloud_sync_controller.dart';
import '../data/ledger_models.dart';
import '../data/ledger_providers.dart';
import '../features/onboarding/onboarding_controller.dart';
import '../features/settings/permission_setup_controller.dart';
import '../features/settings/account_deletion_controller.dart';
import '../theme/theme_controller.dart';

final startupStateProvider = Provider<StartupState>((ref) {
  final auth = ref.watch(authControllerProvider);
  final ledgerLoad = ref.watch(ledgerLoadStateProvider);
  final ledgerSummary = ref.watch(
    ledgerProvider.select(
      (s) => (
        userId: s.userId,
        hasWalletData: _hasWalletData(s),
        authoritativeEmpty: s.hasAuthoritativeEmptyWallet,
      ),
    ),
  );
  final onboarding = ref.watch(onboardingControllerProvider);
  final permissionSetup = ref.watch(permissionSetupControllerProvider);
  final isThemeLoaded = ref.watch(
    themeControllerProvider.select((s) => s.isLoaded),
  );
  final cloudSync = ref.watch(cloudSyncControllerProvider);
  final deletion = ref.watch(accountDeletionControllerProvider);
  if (deletion.operationPending || cloudSync.accountDeletionPending) {
    return const StartupState.ready(destination: StartupDestination.deletion);
  }

  if (!isThemeLoaded || auth.phase == AuthPhase.initializing) {
    return const StartupState.pending(
      stage: StartupStage.session,
      message: 'Checking your secure session',
    );
  }

  if (auth.isLocalOnly) {
    return _offlineStartupState(
      ref,
      auth: auth,
      ledgerLoad: ledgerLoad,
      ledgerOwner: ledgerSummary.userId,
      hasWalletData: ledgerSummary.hasWalletData,
      onboarding: onboarding,
      permissionSetup: permissionSetup,
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

  final hasWalletData =
      (ledgerSummary.userId == userId ||
          ledgerSummary.userId == 'local-user') &&
      ledgerSummary.hasWalletData;

  if (permissionSetup.userId != userId && !permissionSetup.isLoading) {
    Future.microtask(() {
      ref.read(permissionSetupControllerProvider.notifier).loadForUser(userId);
    });
    return const StartupState.pending(
      stage: StartupStage.wallet,
      message: 'Preparing permission setup',
    );
  }

  if (permissionSetup.isLoading) {
    return const StartupState.pending(
      stage: StartupStage.wallet,
      message: 'Checking device permissions',
    );
  }

  if (permissionSetup.errorMessage != null) {
    return StartupState.recoverableError(
      title: 'Permissions setup needs attention',
      message: permissionSetup.errorMessage!,
    );
  }

  if (!permissionSetup.completed) {
    return const StartupState.ready(
      destination: StartupDestination.permissions,
    );
  }

  // Existing local/restored data is authoritative for startup routing. Do not
  // keep the user on onboarding or a sync splash while usable wallet data is
  // already present; cloud sync can finish in the background.
  final hasVerifiedLocalEmptyWallet =
      ledgerSummary.userId == userId &&
      ledgerSummary.authoritativeEmpty &&
      cloudSync.metadata?.userId == userId &&
      cloudSync.metadata?.lastPulledAt != null;
  if (hasWalletData || hasVerifiedLocalEmptyWallet) {
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
    return StartupState.pending(
      stage: StartupStage.wallet,
      message: cloudSync.progressMessage ?? 'Restoring your Google wallet data',
      progress: cloudSync.progress,
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

  // If the user already completed onboarding for this account, send them home.
  if (onboarding.completed && onboarding.userId == userId) {
    return const StartupState.ready(destination: StartupDestination.home);
  }

  // If Firebase has an existing cloud wallet for this user, NEVER route to onboarding!
  // The user already has an established wallet in Firebase. Clobbering it with a
  // fresh onboarding setup must never be allowed.
  if (cloudSync.hasCloudWallet) {
    if (cloudSync.bootstrapComplete &&
        cloudSync.bootstrappedUserId == userId &&
        cloudSync.metadata?.lastPulledAt != null) {
      return const StartupState.ready(destination: StartupDestination.home);
    }
    return const StartupState.recoverableError(
      title: 'Cloud wallet found',
      message:
          'Your cloud wallet was found in Firebase but is not yet synced to this device. '
          'Tap "Try again" to restore your accounts.',
    );
  }

  return const StartupState.ready(destination: StartupDestination.onboarding);
});

/// Offline mode startup: the same permissions → onboarding → home flow as a
/// signed-in account, owned by [localOwnerId], with no cloud-sync gating and
/// no dependency on Firebase or the network.
StartupState _offlineStartupState(
  Ref ref, {
  required AuthState auth,
  required LedgerLoadState ledgerLoad,
  required String ledgerOwner,
  required bool hasWalletData,
  required OnboardingState onboarding,
  required PermissionSetupState permissionSetup,
}) {
  const ownerId = localOwnerId;

  if (!ledgerLoad.isReady) {
    return const StartupState.pending(
      stage: StartupStage.wallet,
      message: 'Opening your offline wallet',
    );
  }

  if (ledgerLoad.errorMessage != null) {
    return StartupState.recoverableError(
      title: 'Wallet setup needs attention',
      message: ledgerLoad.errorMessage!,
    );
  }

  // Offline mode may only ever open the device-only wallet. Anything else is
  // resolved by AuthController (finish an interrupted upgrade, or return to
  // sign-in) before any wallet data is shown.
  final ownedLocally = ledgerOwner.isEmpty || ledgerOwner == ownerId;
  if (!auth.localOwnershipVerified || !ownedLocally) {
    if (auth.errorMessage != null && !auth.localOwnershipVerified) {
      return StartupState.recoverableError(
        title: 'Offline wallet needs attention',
        message: auth.errorMessage!,
      );
    }
    Future.microtask(() {
      ref
          .read(authControllerProvider.notifier)
          .verifyLocalOwnership(ledgerOwner);
    });
    return const StartupState.pending(
      stage: StartupStage.wallet,
      message: 'Checking your offline wallet',
    );
  }

  if (permissionSetup.userId != ownerId && !permissionSetup.isLoading) {
    Future.microtask(() {
      ref.read(permissionSetupControllerProvider.notifier).loadForUser(ownerId);
    });
    return const StartupState.pending(
      stage: StartupStage.wallet,
      message: 'Preparing permission setup',
    );
  }

  if (permissionSetup.isLoading) {
    return const StartupState.pending(
      stage: StartupStage.wallet,
      message: 'Checking device permissions',
    );
  }

  if (permissionSetup.errorMessage != null) {
    return StartupState.recoverableError(
      title: 'Permissions setup needs attention',
      message: permissionSetup.errorMessage!,
    );
  }

  if (!permissionSetup.completed) {
    return const StartupState.ready(
      destination: StartupDestination.permissions,
    );
  }

  if (hasWalletData) {
    if (!onboarding.completed || onboarding.userId != ownerId) {
      Future.microtask(() {
        ref
            .read(onboardingControllerProvider.notifier)
            .setCompleted(ownerId, true);
      });
    }
    return const StartupState.ready(destination: StartupDestination.home);
  }

  if (onboarding.userId != ownerId && !onboarding.isLoading) {
    Future.microtask(() {
      ref.read(onboardingControllerProvider.notifier).loadForUser(ownerId);
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

  if (onboarding.completed && onboarding.userId == ownerId) {
    return const StartupState.ready(destination: StartupDestination.home);
  }

  return const StartupState.ready(destination: StartupDestination.onboarding);
}

bool _hasWalletData(LedgerState ledger) {
  return ledger.accounts.isNotEmpty || ledger.transactions.isNotEmpty;
}

enum StartupStage { session, wallet, ready }

enum StartupDestination {
  launch,
  login,
  permissions,
  onboarding,
  home,
  deletion,
}

@immutable
class StartupState {
  const StartupState._({
    required this.stage,
    required this.destination,
    required this.isPending,
    this.title,
    this.message,
    this.isRecoverableError = false,
    this.progress,
  });

  const StartupState.pending({
    required StartupStage stage,
    required String message,
    double? progress,
  }) : this._(
         stage: stage,
         destination: StartupDestination.launch,
         isPending: true,
         message: message,
         progress: progress,
       );

  const StartupState.ready({
    required StartupDestination destination,
    String? message,
  }) : this._(
         stage: stageReady,
         destination: destination,
         isPending: false,
         message: message,
       );

  static const StartupStage stageReady = StartupStage.ready;

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
  final double? progress;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StartupState &&
        other.stage == stage &&
        other.destination == destination &&
        other.isPending == isPending &&
        other.title == title &&
        other.message == message &&
        other.isRecoverableError == isRecoverableError &&
        other.progress == progress;
  }

  @override
  int get hashCode => Object.hash(
    stage,
    destination,
    isPending,
    title,
    message,
    isRecoverableError,
    progress,
  );
}
