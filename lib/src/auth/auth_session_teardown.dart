import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cloud_sync/cloud_sync_controller.dart';
import '../data/ledger_providers.dart';
import '../features/onboarding/onboarding_controller.dart';
import '../features/onboarding/discovery_controller.dart';
import 'app_mode.dart';
import '../features/settings/permission_setup_controller.dart';
import 'auth_controller.dart';

/// Signs out of offline mode. The device-only wallet has no other copy, so it
/// is permanently erased (callers must confirm first) before the device
/// returns to the sign-in screen. Throws, leaving offline mode active, when
/// the wallet could not be erased.
Future<void> signOutOfflineWallet(WidgetRef ref) async {
  if (!ref.read(authControllerProvider).isLocalOnly) return;
  // Read everything up front: erasing the wallet re-routes the app, which can
  // dispose the widget that owns [ref] before teardown finishes.
  final ledger = ref.read(ledgerProvider.notifier);
  final auth = ref.read(authControllerProvider.notifier);
  final onboarding = ref.read(onboardingControllerProvider.notifier);
  final permissions = ref.read(permissionSetupControllerProvider.notifier);
  final discovery = ref.read(
    discoveryControllerProvider(localOwnerId).notifier,
  );
  await ledger.purgeAllLocalData();
  await discovery.clearLocal();
  await auth.leaveOfflineMode();
  onboarding.clear();
  permissions.clear();
}

/// Safely tears down all session data, queues, sync subscriptions, and signs out.
/// Even if backup flush, sync detach, or remote sign out times out or throws,
/// the local session is guaranteed to be terminated cleanly and reliably.
Future<void> signOutAppSession(WidgetRef ref) async {
  if (ref.read(authControllerProvider).isLocalOnly) return;
  // Read everything up front: sign-out re-routes the app, which can dispose
  // the widget that owns [ref] before teardown finishes.
  final ledger = ref.read(ledgerProvider.notifier);
  final cloudSync = ref.read(cloudSyncControllerProvider.notifier);
  final onboarding = ref.read(onboardingControllerProvider.notifier);
  final permissions = ref.read(permissionSetupControllerProvider.notifier);
  final auth = ref.read(authControllerProvider.notifier);

  try {
    await ledger.flushAutoBackupBeforeSignOut().timeout(
      const Duration(seconds: 4),
      onTimeout: () {
        debugPrint('flushAutoBackupBeforeSignOut timed out');
      },
    );
  } catch (e) {
    debugPrint('flushAutoBackupBeforeSignOut failed: $e');
  }

  try {
    await cloudSync.handleSignOut().timeout(
      const Duration(seconds: 4),
      onTimeout: () {
        debugPrint('handleSignOut timed out');
      },
    );
  } catch (e) {
    debugPrint('handleSignOut failed: $e');
  }

  try {
    await ledger.clearSessionOnSignOut().timeout(
      const Duration(seconds: 4),
      onTimeout: () {
        debugPrint('clearSessionOnSignOut timed out');
      },
    );
  } catch (e) {
    debugPrint('clearSessionOnSignOut failed: $e');
  }

  try {
    onboarding.clear();
    permissions.clear();
  } catch (e) {
    debugPrint('clear onboarding/permissions failed: $e');
  }

  try {
    await auth.signOut().timeout(
      const Duration(seconds: 6),
      onTimeout: () {
        debugPrint('authController.signOut timed out');
      },
    );
  } catch (e) {
    debugPrint('authController.signOut failed: $e');
  }
}
