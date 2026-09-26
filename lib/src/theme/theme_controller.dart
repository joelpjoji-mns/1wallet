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
    final previousPreference = state.preference;
    state = state.copyWith(preference: preference, isLoaded: true);
    try {
      await _preferences.setString(_storageKey, preference.name);
    } catch (error) {
      // The optimistic update above already flipped the live theme. If the
      // write itself fails, roll back instead of leaving the UI showing a
      // preference that silently reverts on the next launch (it wasn't
      // actually persisted). Rethrow so an awaiting caller (see
      // settings_screen.dart, which shows a "saved" confirmation after this
      // completes) observes the failure instead of reporting success.
      //
      // Only touch the `preference` field, and only roll it back if it
      // still holds the value *this* call optimistically applied. Calls can
      // overlap (e.g. the user taps two theme options in quick succession);
      // an overlapping call that already moved `preference` on to something
      // newer — or changed `accentColor` — must not be clobbered by this
      // call's later, unrelated failure.
      if (state.preference == preference) {
        state = state.copyWith(preference: previousPreference);
      }
      debugPrint('ThemeController.setPreference failed to persist: $error');
      rethrow;
    }
  }

  Future<void> setAccentColor(String? hexColor) async {
    final previousAccent = state.accentColor;
    state = state.copyWith(
      accentColor: hexColor,
      isLoaded: true,
      clearAccent: hexColor == null,
    );
    try {
      if (hexColor == null) {
        await _preferences.remove(_accentKey);
      } else {
        await _preferences.setString(_accentKey, hexColor);
      }
    } catch (error) {
      // See setPreference above: roll back only the `accentColor` field,
      // and only if it still holds the value this call applied, so an
      // overlapping call's newer accent (or unrelated `preference` change)
      // isn't clobbered by this call's later failure.
      if (state.accentColor == hexColor) {
        state = state.copyWith(
          accentColor: previousAccent,
          clearAccent: previousAccent == null,
        );
      }
      debugPrint('ThemeController.setAccentColor failed to persist: $error');
      rethrow;
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
    } catch (error) {
      // Best-effort read at startup: fall back to defaults rather than
      // blocking app boot on a corrupted/unavailable preference store, but
      // still surface the failure for developers instead of staying fully
      // silent about it.
      debugPrint('ThemeController._load failed to read preferences: $error');
      state = const AppThemeState(isLoaded: true);
    }
  }
}
