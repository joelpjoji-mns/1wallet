import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final permissionSetupControllerProvider =
    StateNotifierProvider<PermissionSetupController, PermissionSetupState>((
      ref,
    ) {
      return PermissionSetupController();
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
  PermissionSetupController() : super(const PermissionSetupState());

  Future<void> loadForUser(String userId) async {
    if (state.userId == userId && !state.isLoading) return;
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
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_key(userId), completed);
    if (!mounted) return;
    state = PermissionSetupState(userId: userId, completed: completed);
  }

  void clear() {
    state = const PermissionSetupState();
  }

  static String _key(String userId) {
    return 'one_wallet_flutter.permissions_setup.completed.$userId';
  }
}
