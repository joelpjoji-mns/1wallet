import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/auth_controller.dart';
import '../../cloud_sync/cloud_sync_controller.dart';
import '../../data/ledger_providers.dart';
import '../../security/app_lock.dart';
import '../../services/notification_service.dart';
import '../../utils/secure_key_store.dart';
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
  });

  final AccountDeletionStage stage;
  final String? errorMessage;

  bool get isBusy =>
      stage == AccountDeletionStage.deletingCloudData ||
      stage == AccountDeletionStage.deletingCloudAccount ||
      stage == AccountDeletionStage.deletingLocalData;

  String get statusMessage => switch (stage) {
    AccountDeletionStage.idle => '',
    AccountDeletionStage.deletingCloudData => 'Deleting cloud data and backups…',
    AccountDeletionStage.deletingCloudAccount =>
      'Deleting account credentials…',
    AccountDeletionStage.deletingLocalData =>
      'Wiping local storage and auto-backups…',
    AccountDeletionStage.success => 'Account and data permanently deleted.',
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
  AccountDeletionController(this._ref) : super(const AccountDeletionState());

  final Ref _ref;

  Future<bool> deleteAccountAndAllData() async {
    if (state.isBusy) return false;

    final auth = _ref.read(authControllerProvider);
    final user = auth.user;

    try {
      // 1. Delete all cloud data in Firestore (if user is logged in)
      if (user != null) {
        state = const AccountDeletionState(
          stage: AccountDeletionStage.deletingCloudData,
        );
        await _ref
            .read(cloudSyncControllerProvider.notifier)
            .deleteAllCloudData(userId: user.id);

        // 2. Delete Firebase Auth account
        state = const AccountDeletionState(
          stage: AccountDeletionStage.deletingCloudAccount,
        );
        await _ref.read(authControllerProvider.notifier).deleteAccount();
      }

      // 3. Delete all local data, auto-backups, and secure storage
      state = const AccountDeletionState(
        stage: AccountDeletionStage.deletingLocalData,
      );

      // Cancel notifications
      try {
        await NotificationService.cancelAll();
      } catch (e) {
        debugPrint('Cancel notifications: $e');
      }

      // Clear local ledger and auto backups
      try {
        await _ref.read(ledgerProvider.notifier).purgeAllLocalData();
      } catch (e) {
        debugPrint('Purge local data: $e');
      }

      // Clear secure cryptographic keys
      try {
        await SecureKeyStore.clear();
      } catch (e) {
        debugPrint('Clear secure keys: $e');
      }

      // Disable and reset app lock
      try {
        await _ref.read(appLockProvider.notifier).disable();
      } catch (e) {
        debugPrint('Disable app lock: $e');
      }

      // Reset onboarding and permissions setup
      try {
        _ref.read(onboardingControllerProvider.notifier).clear();
        _ref.read(permissionSetupControllerProvider.notifier).clear();
      } catch (e) {
        debugPrint('Clear onboarding/permissions: $e');
      }

      // Clear all SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
      } catch (e) {
        debugPrint('Clear preferences: $e');
      }

      state = const AccountDeletionState(stage: AccountDeletionStage.success);
      return true;
    } catch (e) {
      debugPrint('Account deletion failed: $e');
      state = AccountDeletionState(
        stage: AccountDeletionStage.error,
        errorMessage: e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''),
      );
      return false;
    }
  }

  void reset() {
    state = const AccountDeletionState();
  }
}
