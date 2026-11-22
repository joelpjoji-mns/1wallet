import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cloud_sync/cloud_sync_controller.dart';
import '../data/ledger_providers.dart';
import '../features/onboarding/onboarding_controller.dart';
import '../features/settings/permission_setup_controller.dart';
import 'auth_controller.dart';

/// Safely tears down all session data, queues, sync subscriptions, and signs out.
/// Even if backup flush, sync detach, or remote sign out times out or throws,
/// the local session is guaranteed to be terminated cleanly and reliably.
Future<void> signOutAppSession(WidgetRef ref) async {
  if (ref.read(authControllerProvider).isLocalOnly) return;

  try {
    await ref
        .read(ledgerProvider.notifier)
        .flushAutoBackupBeforeSignOut()
        .timeout(
          const Duration(seconds: 4),
          onTimeout: () {
            debugPrint('flushAutoBackupBeforeSignOut timed out');
          },
        );
  } catch (e) {
    debugPrint('flushAutoBackupBeforeSignOut failed: $e');
  }

  try {
    await ref
        .read(cloudSyncControllerProvider.notifier)
        .handleSignOut()
        .timeout(
          const Duration(seconds: 4),
          onTimeout: () {
            debugPrint('handleSignOut timed out');
          },
        );
  } catch (e) {
    debugPrint('handleSignOut failed: $e');
  }

  try {
    await ref
        .read(ledgerProvider.notifier)
        .clearSessionOnSignOut()
        .timeout(
          const Duration(seconds: 4),
          onTimeout: () {
            debugPrint('clearSessionOnSignOut timed out');
          },
        );
  } catch (e) {
    debugPrint('clearSessionOnSignOut failed: $e');
  }

  try {
    ref.read(onboardingControllerProvider.notifier).clear();
    ref.read(permissionSetupControllerProvider.notifier).clear();
  } catch (e) {
    debugPrint('clear onboarding/permissions failed: $e');
  }

  try {
    await ref
        .read(authControllerProvider.notifier)
        .signOut()
        .timeout(
          const Duration(seconds: 6),
          onTimeout: () {
            debugPrint('authController.signOut timed out');
          },
        );
  } catch (e) {
    debugPrint('authController.signOut failed: $e');
  }
}
