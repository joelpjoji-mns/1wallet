import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final themeControllerProvider =
    StateNotifierProvider<ThemeController, AppThemeState>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider);
      return ThemeController(prefs);
    });

enum AppThemePreference { system, light, dark, amoled }

class AppThemeState {
  const AppThemeState({
    this.preference = AppThemePreference.amoled,
    this.accentColor,
    this.isLoaded = false,
  });

  final AppThemePreference preference;
  final String? accentColor;
  final bool isLoaded;

  ThemeMode get themeMode => switch (preference) {
    AppThemePreference.light => ThemeMode.light,
    AppThemePreference.dark || AppThemePreference.amoled => ThemeMode.dark,
    AppThemePreference.system => ThemeMode.system,
  };

  AppThemeState copyWith({
    AppThemePreference? preference,
    String? accentColor,
    bool? isLoaded,
    bool clearAccent = false,
  }) {
    return AppThemeState(
      preference: preference ?? this.preference,
      accentColor: clearAccent ? null : (accentColor ?? this.accentColor),
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

class ThemeController extends StateNotifier<AppThemeState> {
  ThemeController(this._preferences) : super(const AppThemeState()) {
    _load();
  }

  final SharedPreferences _preferences;

  static const _storageKey = 'one_wallet_flutter.theme.preference.v1';
  static const _accentKey = 'one_wallet_flutter.accent.preference.v1';

  Future<void> setPreference(AppThemePreference preference) async {
    state = state.copyWith(preference: preference, isLoaded: true);
    await _preferences.setString(_storageKey, preference.name);
  }

  Future<void> setAccentColor(String? hexColor) async {
    state = state.copyWith(
      accentColor: hexColor,
      isLoaded: true,
      clearAccent: hexColor == null,
    );
    if (hexColor == null) {
      await _preferences.remove(_accentKey);
    } else {
      await _preferences.setString(_accentKey, hexColor);
    }
  }

  void _load() {
    try {
      final raw = _preferences.getString(_storageKey);
      final accent = _preferences.getString(_accentKey);
      final preference = AppThemePreference.values.firstWhere(
        (item) => item.name == raw,
        orElse: () => AppThemePreference.amoled,
      );
      state = AppThemeState(
        preference: preference,
        accentColor: accent,
        isLoaded: true,
      );
    } catch (_) {
      state = const AppThemeState(isLoaded: true);
    }
  }
}
