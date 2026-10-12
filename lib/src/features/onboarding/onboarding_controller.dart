import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/auth_controller.dart';
import '../../theme/theme_controller.dart';

final onboardingControllerProvider =
    StateNotifierProvider<OnboardingController, OnboardingState>((ref) {
      SharedPreferences? prefs;
      try {
        prefs = ref.watch(sharedPreferencesProvider);
      } catch (_) {}
      String? initialUserId;
      try {
        initialUserId = ref.read(authControllerProvider).user?.id;
      } catch (_) {}
      final controller = OnboardingController(
        prefs: prefs,
        initialUserId: initialUserId,
      );
      ref.listen<AuthState>(authControllerProvider, (prev, next) {
        final nextUserId = next.user?.id;
        if (nextUserId != null && prefs != null) {
          controller.syncForUser(nextUserId);
        }
      });
      return controller;
    });

@immutable
class OnboardingState {
  const OnboardingState({
    this.userId,
    this.isLoading = false,
    this.completed = false,
    this.errorMessage,
  });

  final String? userId;
  final bool isLoading;
  final bool completed;
  final String? errorMessage;

  OnboardingState copyWith({
    Object? userId = _unset,
    bool? isLoading,
    bool? completed,
    Object? errorMessage = _unset,
  }) {
    return OnboardingState(
      userId: identical(userId, _unset) ? this.userId : userId as String?,
      isLoading: isLoading ?? this.isLoading,
      completed: completed ?? this.completed,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

class OnboardingController extends StateNotifier<OnboardingState> {
  OnboardingController({
    SharedPreferences? prefs,
    String? initialUserId,
  }) : _prefs = prefs,
       super(
         (prefs != null && initialUserId != null)
             ? OnboardingState(
                 userId: initialUserId,
                 completed: prefs.getBool(_key(initialUserId)) ?? false,
               )
             : const OnboardingState(),
       );

  final SharedPreferences? _prefs;

  void syncForUser(String userId) {
    final prefs = _prefs;
    if (prefs == null) return;
    if (state.userId == userId && !state.isLoading) return;
    state = OnboardingState(
      userId: userId,
      completed: prefs.getBool(_key(userId)) ?? false,
    );
  }

  Future<void> loadForUser(String userId) async {
    if (state.userId == userId && !state.isLoading) return;
    final syncPrefs = _prefs;
    if (syncPrefs != null) {
      state = OnboardingState(
        userId: userId,
        completed: syncPrefs.getBool(_key(userId)) ?? false,
      );
      return;
    }
    state = OnboardingState(userId: userId, isLoading: true);
    try {
      final preferences = await SharedPreferences.getInstance();
      final completed = preferences.getBool(_key(userId)) ?? false;
      if (!mounted) return;
      state = OnboardingState(userId: userId, completed: completed);
    } catch (error) {
      if (!mounted) return;
      state = OnboardingState(
        userId: userId,
        errorMessage: 'Unable to load onboarding state: $error',
      );
    }
  }

  Future<void> setCompleted(String userId, bool completed) async {
    final preferences = _prefs ?? await SharedPreferences.getInstance();
    await preferences.setBool(_key(userId), completed);
    if (!mounted) return;
    state = OnboardingState(userId: userId, completed: completed);
  }

  void clear() {
    state = const OnboardingState();
  }

  static String _key(String userId) {
    return 'one_wallet_flutter.onboarding.completed.$userId';
  }
}

const _unset = Object();
