import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/app_mode.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_user.dart';
import '../cloud_sync/cloud_sync_controller.dart';
import '../cloud_sync/cloud_sync_write_guard.dart';
import '../data/ledger_merge.dart';
import '../data/ledger_models.dart';
import '../data/ledger_providers.dart';
import '../features/onboarding/onboarding_controller.dart';
import '../features/settings/permission_setup_controller.dart';

/// Cloud reads/writes the offline → Google upgrade needs, behind an interface
/// so the migration can be verified without Firestore.
abstract interface class OfflineUpgradeCloudGateway {
  Future<CloudWalletProbe> probe(String userId);
  Future<CloudWalletSnapshot> fetchSnapshot(String userId);
  Future<void> primeOwner(String userId, {CloudWriteState? baseline});
}

class FirestoreOfflineUpgradeGateway implements OfflineUpgradeCloudGateway {
  const FirestoreOfflineUpgradeGateway();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  @override
  Future<CloudWalletProbe> probe(String userId) =>
      probeCloudWallet(_firestore, userId);

  @override
  Future<CloudWalletSnapshot> fetchSnapshot(String userId) =>
      fetchCloudWalletSnapshot(_firestore, userId);

  @override
  Future<void> primeOwner(String userId, {CloudWriteState? baseline}) =>
      primeCloudSyncOwnerForUpgrade(userId, baseline: baseline);
}

final offlineUpgradeCloudGatewayProvider = Provider<OfflineUpgradeCloudGateway>(
  (ref) => const FirestoreOfflineUpgradeGateway(),
);

final offlineModeControllerProvider =
    StateNotifierProvider<OfflineModeController, OfflineModeState>(
      (ref) => OfflineModeController(ref),
    );

enum OfflineEntryResult { entered, walletBelongsToAccount, failed }

enum OfflineUpgradeStage {
  idle,
  signingIn,
  checkingCloud,
  awaitingChoice,
  migrating,
  completed,
}

/// What to do when the Google account already has a cloud wallet.
enum CloudWalletChoice {
  /// Upload this device's wallet and replace the cloud wallet.
  keepLocal,

  /// Use the cloud wallet; the offline wallet stays only in the on-device
  /// automatic backup.
  keepCloud,

  /// Combine both wallets and upload the result.
  merge,
}

@immutable
class OfflineModeState {
  const OfflineModeState({
    this.stage = OfflineUpgradeStage.idle,
    this.errorMessage,
    this.accountEmail,
    this.cloudAccountCount,
    this.cloudTransactionCount,
    this.cloudUpdatedAt,
    this.localAccountCount = 0,
    this.localTransactionCount = 0,
    this.resolvedChoice,
    this.completionAnnounced = false,
  });

  final OfflineUpgradeStage stage;
  final String? errorMessage;
  final String? accountEmail;
  final int? cloudAccountCount;
  final int? cloudTransactionCount;
  final DateTime? cloudUpdatedAt;
  final int localAccountCount;
  final int localTransactionCount;
  final CloudWalletChoice? resolvedChoice;

  /// Whether the app already confirmed a completed upgrade to the user.
  final bool completionAnnounced;

  bool get isBusy =>
      stage == OfflineUpgradeStage.signingIn ||
      stage == OfflineUpgradeStage.checkingCloud ||
      stage == OfflineUpgradeStage.migrating;
}

/// Orchestrates entering offline mode and the offline → Google upgrade.
///
/// Upgrade ordering (each step only starts after the previous succeeded):
/// 1. Google sign-in without publishing the account (session stays offline).
/// 2. Server-side probe of the account's cloud wallet; the user chooses
///    keep-local / keep-cloud / merge when both sides hold data.
/// 3. All remaining network reads (the cloud wallet for a merge).
/// 4. Record the account as sync owner with the cloud baseline to supersede.
/// 5. One serialized ledger mutation moves the wallet to the account.
/// 6. Persist online mode, then publish the account so the standard cloud
///    bootstrap uploads (keep-local/merge) or restores (keep-cloud).
/// Failing before step 5 leaves offline mode and the wallet untouched.
class OfflineModeController extends StateNotifier<OfflineModeState> {
  OfflineModeController(this._ref) : super(const OfflineModeState());

  final Ref _ref;
  AuthUser? _pendingUser;
  CloudWalletProbe? _pendingProbe;

  /// Enters offline mode from the signed-out entry screen.
  Future<OfflineEntryResult> enterOfflineMode() async {
    final auth = _ref.read(authControllerProvider);
    if (auth.isLocalOnly) return OfflineEntryResult.entered;
    if (auth.isAuthenticated || auth.isSigningIn) {
      return OfflineEntryResult.failed;
    }
    final ledger = _ref.read(ledgerProvider.notifier);
    try {
      if (!await ledger.claimForLocalOwner()) {
        return OfflineEntryResult.walletBelongsToAccount;
      }
      final entered = await _ref
          .read(authControllerProvider.notifier)
          .continueOffline();
      if (!entered) {
        await ledger.releaseLocalOwner();
        return OfflineEntryResult.failed;
      }
      return OfflineEntryResult.entered;
    } catch (error, stack) {
      debugPrint('Could not enter offline mode: $error');
      debugPrintStack(stackTrace: stack);
      return OfflineEntryResult.failed;
    }
  }

  Future<void> startGoogleUpgrade() async {
    if (state.isBusy || state.stage == OfflineUpgradeStage.awaitingChoice) {
      return;
    }
    if (!_ref.read(authControllerProvider).isLocalOnly) return;
    state = const OfflineModeState(stage: OfflineUpgradeStage.signingIn);

    final AuthUser user;
    try {
      user = await _ref
          .read(authControllerProvider.notifier)
          .signInWithGoogleForUpgrade();
    } catch (error) {
      if (!mounted) return;
      state = OfflineModeState(errorMessage: _describe(error));
      return;
    }
    if (!mounted) return;
    _pendingUser = user;
    state = OfflineModeState(
      stage: OfflineUpgradeStage.checkingCloud,
      accountEmail: user.email,
    );

    final CloudWalletProbe probe;
    try {
      await _ref.read(ledgerProvider.notifier).flushPendingWrites();
      probe = await _ref
          .read(offlineUpgradeCloudGatewayProvider)
          .probe(user.id);
    } catch (error) {
      debugPrint('Cloud wallet probe failed: $error');
      await _abandon(
        'Could not check your Google account for an existing wallet. '
        'Check your connection and try again. Nothing was changed.',
      );
      return;
    }
    if (!mounted) return;

    final local = _ref.read(ledgerProvider);
    if (!probe.exists) {
      await _migrate(user, CloudWalletChoice.keepLocal, probe);
      return;
    }
    if (!_hasWalletData(local)) {
      await _migrate(user, CloudWalletChoice.keepCloud, probe);
      return;
    }
    _pendingProbe = probe;
    state = OfflineModeState(
      stage: OfflineUpgradeStage.awaitingChoice,
      accountEmail: user.email,
      cloudAccountCount: probe.live.accountCount,
      cloudTransactionCount: probe.live.transactionCount,
      cloudUpdatedAt: probe.live.updatedAt,
      localAccountCount: local.accounts.length,
      localTransactionCount: local.transactions.length,
    );
  }

  /// Applies the user's explicit choice when both wallets hold data.
  Future<void> resolveCloudWalletChoice(CloudWalletChoice choice) async {
    final user = _pendingUser;
    final probe = _pendingProbe;
    if (state.stage != OfflineUpgradeStage.awaitingChoice ||
        user == null ||
        probe == null) {
      return;
    }
    await _migrate(user, choice, probe);
  }

  /// Abandons an upgrade that has not started moving the wallet yet.
  Future<void> cancelUpgrade() async {
    if (state.stage == OfflineUpgradeStage.migrating ||
        state.stage == OfflineUpgradeStage.completed) {
      return;
    }
    if (_pendingUser == null) {
      state = const OfflineModeState();
      return;
    }
    await _abandon(null);
  }

  /// Clears a finished or failed upgrade so the next attempt starts fresh.
  void acknowledge() {
    if (state.isBusy || state.stage == OfflineUpgradeStage.awaitingChoice) {
      return;
    }
    state = const OfflineModeState();
  }

  void markAnnounced() {
    if (state.stage != OfflineUpgradeStage.completed) return;
    state = OfflineModeState(
      stage: OfflineUpgradeStage.completed,
      accountEmail: state.accountEmail,
      resolvedChoice: state.resolvedChoice,
      completionAnnounced: true,
    );
  }

  Future<void> _abandon(String? message) async {
    _pendingUser = null;
    _pendingProbe = null;
    await _ref.read(authControllerProvider.notifier).discardUpgradeSession();
    if (!mounted) return;
    state = OfflineModeState(errorMessage: message);
  }

  Future<void> _migrate(
    AuthUser user,
    CloudWalletChoice choice,
    CloudWalletProbe probe,
  ) async {
    state = OfflineModeState(
      stage: OfflineUpgradeStage.migrating,
      accountEmail: user.email,
      resolvedChoice: choice,
    );
    final gateway = _ref.read(offlineUpgradeCloudGatewayProvider);
    final ledger = _ref.read(ledgerProvider.notifier);
    final owner = LedgerUserIdentity(
      userId: user.id,
      displayName: user.displayName,
      email: user.email,
    );
    try {
      if (!_ref.read(authControllerProvider).isLocalOnly) {
        throw StateError('Offline mode ended during the upgrade.');
      }
      final cloud = choice == CloudWalletChoice.merge
          ? await gateway.fetchSnapshot(user.id)
          : null;
      final baseline = switch (choice) {
        CloudWalletChoice.keepLocal => probe.exists ? probe.live : null,
        CloudWalletChoice.merge => cloud!.version,
        CloudWalletChoice.keepCloud => null,
      };
      await gateway.primeOwner(user.id, baseline: baseline);
      await _carryOverSetupFlags(user.id);
      switch (choice) {
        case CloudWalletChoice.keepCloud:
          await ledger.resetLocalWalletForCloudOwner(owner);
        case CloudWalletChoice.keepLocal:
          await ledger.adoptLocalWalletForOwner(owner);
        case CloudWalletChoice.merge:
          final cloudLedger = cloud!.ledger.copyWith(userId: user.id);
          await ledger.adoptLocalWalletForOwner(
            owner,
            transform: (rekeyed) =>
                mergeLedgerStates(cloud: cloudLedger, local: rekeyed),
          );
      }
    } catch (error, stack) {
      debugPrint('Offline upgrade migration failed: $error');
      debugPrintStack(stackTrace: stack);
      // The wallet move is a single serialized mutation: unless it already
      // committed, offline mode and the local wallet are exactly as before.
      if (_ref.read(ledgerProvider).userId != user.id) {
        await _abandon(
          'Could not move your wallet to Google. Your offline wallet is '
          'unchanged. ${_describe(error)}',
        );
        return;
      }
    }

    try {
      await _ref
          .read(authControllerProvider.notifier)
          .completeOfflineUpgrade(user);
    } catch (error) {
      debugPrint('Could not publish the upgraded account: $error');
      if (!mounted) return;
      // The wallet already belongs to the account; startup finishes the
      // upgrade on the next launch (AuthController.verifyLocalOwnership).
      state = const OfflineModeState(
        errorMessage:
            'Your wallet was moved to your Google account. Restart 1Wallet '
            'to finish turning on sync.',
      );
      return;
    }
    _pendingUser = null;
    _pendingProbe = null;
    if (!mounted) return;
    state = OfflineModeState(
      stage: OfflineUpgradeStage.completed,
      accountEmail: user.email,
      resolvedChoice: choice,
    );
  }

  /// Carries the finished permission/onboarding setup of the offline owner
  /// over to the account so the upgrade does not replay first-run screens.
  Future<void> _carryOverSetupFlags(String userId) async {
    await PermissionSetupController.copyCompletion(
      from: localOwnerId,
      to: userId,
    );
    await OnboardingController.copyCompletion(from: localOwnerId, to: userId);
  }
}

bool _hasWalletData(LedgerState ledger) =>
    ledger.accounts.isNotEmpty ||
    ledger.transactions.isNotEmpty ||
    ledger.captureCandidates.isNotEmpty ||
    ledger.importBatches.isNotEmpty;

String _describe(Object error) {
  if (error is AuthFailure) return error.message;
  if (error is StateError) return error.message;
  return kDebugMode ? '$error' : 'Please try again.';
}
