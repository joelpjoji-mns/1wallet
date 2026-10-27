import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/auth_controller.dart';
import '../../theme/theme_controller.dart';

final permissionSetupControllerProvider =
    StateNotifierProvider<PermissionSetupController, PermissionSetupState>((
      ref,
    ) {
      SharedPreferences? prefs;
      try {
        prefs = ref.watch(sharedPreferencesProvider);
      } catch (_) {}
      String? initialUserId;
      try {
        initialUserId = ref.read(authControllerProvider).ownerId;
      } catch (_) {}
      final controller = PermissionSetupController(
        prefs: prefs,
        initialUserId: initialUserId,
      );
      ref.listen<AuthState>(authControllerProvider, (prev, next) {
        final nextUserId = next.ownerId;
        if (nextUserId != null && prefs != null) {
          controller.syncForUser(nextUserId);
        }
      });
      return controller;
    });

@immutable
class PermissionSetupState {
  const PermissionSetupState({
    this.userId,
    this.isLoading = false,
    this.completed = false,
    this.errorMessage,
  });

  final String? userId;
  final bool isLoading;
  final bool completed;
  final String? errorMessage;
}

class PermissionSetupController extends StateNotifier<PermissionSetupState> {
  PermissionSetupController({
    SharedPreferences? prefs,
    String? initialUserId,
  }) : _prefs = prefs,
       super(
         (prefs != null && initialUserId != null)
             ? PermissionSetupState(
                 userId: initialUserId,
                 completed: prefs.getBool(_key(initialUserId)) ?? false,
               )
             : const PermissionSetupState(),
       );

  final SharedPreferences? _prefs;

  void syncForUser(String userId) {
    final prefs = _prefs;
    if (prefs == null) return;
    if (state.userId == userId && !state.isLoading) return;
    state = PermissionSetupState(
      userId: userId,
      completed: prefs.getBool(_key(userId)) ?? false,
    );
  }

  Future<void> loadForUser(String userId) async {
    if (state.userId == userId && !state.isLoading) return;
    final syncPrefs = _prefs;
    if (syncPrefs != null) {
      state = PermissionSetupState(
        userId: userId,
        completed: syncPrefs.getBool(_key(userId)) ?? false,
      );
      return;
    }
    state = PermissionSetupState(userId: userId, isLoading: true);
    try {
      final preferences = await SharedPreferences.getInstance();
      final completed = preferences.getBool(_key(userId)) ?? false;
      if (!mounted) return;
      state = PermissionSetupState(userId: userId, completed: completed);
    } catch (error) {
      if (!mounted) return;
      state = PermissionSetupState(
        userId: userId,
        errorMessage: 'Unable to load permission setup state: $error',
      );
    }
  }

  Future<void> setCompleted(String userId, bool completed) async {
    final preferences = _prefs ?? await SharedPreferences.getInstance();
    await preferences.setBool(_key(userId), completed);
    if (!mounted) return;
    state = PermissionSetupState(userId: userId, completed: completed);
  }

  void clear() {
    state = const PermissionSetupState();
  }

  /// Marks [to] as set up when [from] already finished permission setup,
  /// without switching the active owner (used by the offline → Google
  /// upgrade).
  static Future<void> copyCompletion({
    required String from,
    required String to,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_key(from)) ?? false) {
      await preferences.setBool(_key(to), true);
    }
  }

  static String _key(String userId) {
    return 'one_wallet_flutter.permissions_setup.completed.$userId';
  }
}
