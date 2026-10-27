import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/auth_controller.dart';
import '../../cloud_sync/cloud_sync_controller.dart';
import '../../data/ledger_providers.dart';
import '../capture/capture_queue.dart';
import '../../services/notification_service.dart';
import '../../utils/secure_key_store.dart';
import '../../theme/theme_controller.dart';
import 'account_deletion_api.dart';
import '../onboarding/onboarding_controller.dart';
import 'permission_setup_controller.dart';

enum AccountDeletionStage {
  idle,
  deletingCloudData,
  deletingCloudAccount,
  deletingLocalData,
  success,
  error,
}

@immutable
class AccountDeletionState {
  const AccountDeletionState({
    this.stage = AccountDeletionStage.idle,
    this.errorMessage,
    this.operationPending = false,
    this.remoteComplete = false,
    this.localComplete = false,
    this.completionMessage,
  });

  final AccountDeletionStage stage;
  final String? errorMessage;
  final bool operationPending;
  final bool remoteComplete;
  final bool localComplete;
  final String? completionMessage;

  bool get isBusy =>
      stage == AccountDeletionStage.deletingCloudData ||
      stage == AccountDeletionStage.deletingCloudAccount ||
      stage == AccountDeletionStage.deletingLocalData;

  String get statusMessage => switch (stage) {
    AccountDeletionStage.idle => '',
    AccountDeletionStage.deletingCloudData =>
      'Deleting cloud data and backups…',
    AccountDeletionStage.deletingCloudAccount =>
      'Deleting account credentials…',
    AccountDeletionStage.deletingLocalData =>
      'Wiping local storage and auto-backups…',
    AccountDeletionStage.success =>
      completionMessage ??
          'The cloud account and verified device account data were deleted.',
    AccountDeletionStage.error => errorMessage ?? 'Account deletion failed.',
  };
}

final accountDeletionControllerProvider =
    StateNotifierProvider<AccountDeletionController, AccountDeletionState>((
      ref,
    ) {
      return AccountDeletionController(ref);
    });

class AccountDeletionController extends StateNotifier<AccountDeletionState> {
  AccountDeletionController(Ref ref, {bool? pending})
    : _ref = ref,
      super(
        AccountDeletionState(
          operationPending:
              pending ??
              ref.read(sharedPreferencesProvider).getBool(_pendingKey) ??
              false,
        ),
      ) {
    if (state.operationPending) unawaited(_advance(start: false));
  }

  final Ref _ref;
  static const _pendingKey = 'onewallet.deletion.pending.v1';
  Timer? _pollTimer;
  bool _running = false;
  DeletionOperation? _operation;

  Future<bool> deleteAccountAndAllData() => _advance(start: true);
  Future<bool> resumePendingDeletion() => _advance(start: false);

  Future<void> observeCompletedDeletion(LedgerUserIdentity owner) async {
    if (!mounted ||
        _running ||
        _ref.read(authControllerProvider).user?.id != owner.userId) {
      return;
    }
    _running = true;
    try {
      final existing = _operation ?? await DeletionOperation.load();
      if (!mounted) return;
      if (existing != null && existing.owner.userId != owner.userId) {
        throw StateError('Another account has pending deletion cleanup.');
      }
      _operation = DeletionOperation(
        owner: owner,
        receipt: existing?.receipt ?? '',
        remoteConfirmed: true,
      );
      await _operation!.persist();
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setBool(_pendingKey, true)) {
        throw StateError('Could not retain verified deletion recovery.');
      }
    } catch (error, stack) {
      debugPrint('Could not retain observed deletion: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) {
        state = AccountDeletionState(
          stage: AccountDeletionStage.error,
          operationPending: true,
          errorMessage: 'Local deletion cleanup needs attention: $error',
        );
      }
      return;
    } finally {
      _running = false;
    }
    await _advance(start: false);
  }

  Future<bool> _advance({required bool start}) async {
    if (_running || !mounted) return false;
    _running = true;
    _pollTimer?.cancel();
    final wasPending = state.operationPending;
    try {
      _operation ??= await DeletionOperation.load();
      if (!mounted) return false;
      if (_operation == null && wasPending) {
        throw StateError(
          'The deletion recovery receipt is unavailable. '
          'Completion cannot be verified; contact support before resetting recovery state.',
        );
      }
      if (_operation == null && await CaptureQueue.client.unassigned() > 0) {
        throw StateError(
          'Review and assign legacy captures before deleting this account.',
        );
      }
      final user = _ref.read(authControllerProvider).user;
      if (start &&
          _operation != null &&
          user != null &&
          _operation!.owner.userId != user.id) {
        throw StateError(
          'A previous account has a pending deletion operation. '
          'Use Resume cleanup; the current wallet has not been deleted.',
        );
      }
      bool remoteComplete = _operation?.remoteConfirmed ?? false;
      AccountDeletionApi api() => _ref.read(accountDeletionApiProvider);
      if (!remoteComplete) api();
      if (_operation != null && !remoteComplete) {
        try {
          remoteComplete = await api().isRemoteComplete(_operation!.receipt);
        } catch (error) {
          if (!start) rethrow;
          debugPrint(
            'Checking deletion status failed; retrying the authenticated request: $error',
          );
        }
      }
      if (!mounted) return false;
      String? token;
      if (start && !remoteComplete) {
        final target = _operation?.owner.userId ?? user?.id;
        if (target == null ||
            _ref.read(authControllerProvider).user?.id != target) {
          throw StateError(
            'Sign in to the account that requested deletion to retry.',
          );
        }
        token = await _ref
            .read(authControllerProvider.notifier)
            .reauthenticateForDeletion();
        if (!mounted || _ref.read(authControllerProvider).user?.id != target) {
          throw StateError(
            'The account changed during deletion authentication.',
          );
        }
      }
      if (_operation == null) {
        if (user == null || token == null) {
          throw StateError('Sign in before deleting your account.');
        }
        _operation = DeletionOperation.create(
          LedgerUserIdentity(
            userId: user.id,
            email: user.email,
            displayName: user.displayName,
          ),
        );
        await _operation!.persist();
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setBool(_pendingKey, true)) {
          throw StateError('Could not save deletion recovery state.');
        }
      }
      if (!mounted) return false;
      final operation = _operation!;
      state = const AccountDeletionState(
        stage: AccountDeletionStage.deletingCloudData,
        operationPending: true,
      );
      final ledger = _ref.read(ledgerProvider.notifier);
      if (ledger.activeUser?.userId == operation.owner.userId) {
        await ledger.freezeForDeletion(operation.owner.userId);
        await _ref.read(cloudSyncControllerProvider.notifier).handleSignOut();
      }
      if (!mounted) return false;
      if (token != null) {
        await api().request(operation.receipt, token);
      }
      if (!remoteComplete && !await api().isRemoteComplete(operation.receipt)) {
        if (mounted) {
          _pollTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) unawaited(_advance(start: false));
          });
        }
        return false;
      }
      if (!mounted) return false;
      state = const AccountDeletionState(
        stage: AccountDeletionStage.deletingLocalData,
        operationPending: true,
        remoteComplete: true,
      );
      final currentOwner = ledger.activeUser?.userId;
      if (currentOwner == operation.owner.userId || currentOwner == null) {
        await NotificationService.cancelAll();
      }
      await ledger.purgeAllLocalData(userOverride: operation.owner);
      await SecureKeyStore.clear(userId: operation.owner.userId);
      if (!mounted) return false;
      if (currentOwner == operation.owner.userId || currentOwner == null) {
        _ref.read(onboardingControllerProvider.notifier).clear();
        _ref.read(permissionSetupControllerProvider.notifier).clear();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(
        'one_wallet_flutter.onboarding.completed.${operation.owner.userId}',
      );
      await prefs.remove(
        'one_wallet_flutter.permissions_setup.completed.${operation.owner.userId}',
      );
      if (_ref.read(authControllerProvider).user?.id ==
          operation.owner.userId) {
        await _ref
            .read(authControllerProvider.notifier)
            .signOut(rethrowOnError: true);
      }
      if (!await prefs.setBool(_pendingKey, false)) {
        throw StateError('Could not acknowledge local deletion.');
      }
      await DeletionOperation.clear();
      _operation = null;
      if (!mounted) return false;
      state = AccountDeletionState(
        stage: AccountDeletionStage.success,
        remoteComplete: true,
        localComplete: true,
        completionMessage: user != null && user.id != operation.owner.userId
            ? 'Previous account cleanup completed. Your current wallet was not deleted.'
            : null,
      );
      return true;
    } catch (error, stack) {
      debugPrint('Account deletion did not complete: $error');
      debugPrintStack(stackTrace: stack);
      if (mounted) {
        state = AccountDeletionState(
          stage: AccountDeletionStage.error,
          operationPending: _operation != null || wasPending,
          remoteComplete: state.remoteComplete,
          errorMessage: 'Deletion is not complete. ${error.toString()}',
        );
      }
      return false;
    } finally {
      _running = false;
    }
  }

  void reset() {
    if (state.operationPending) return;
    state = const AccountDeletionState();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
