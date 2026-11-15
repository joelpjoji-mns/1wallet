import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design/tokens.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final themeControllerProvider =
    StateNotifierProvider<ThemeController, AppThemeState>((ref) {
      SharedPreferences? prefs;
      try {
        prefs = ref.watch(sharedPreferencesProvider);
      } catch (_) {
        // Fallback for widget tests where sharedPreferencesProvider is not overridden
      }
      return ThemeController(prefs);
    });

enum AppThemePreference { system, light, amoled }

class AppThemeState {
  const AppThemeState({
    this.preference = AppThemePreference.amoled,
    this.useSystemColor = true,
    this.customAccentColor,
    this.colorIntensity = 1.0,
    this.isLoaded = false,
  });

  final AppThemePreference preference;
  final bool useSystemColor;
  final Color? customAccentColor;
  final double colorIntensity;
  final bool isLoaded;

  ThemeMode get themeMode => switch (preference) {
    AppThemePreference.light => ThemeMode.light,
    AppThemePreference.amoled => ThemeMode.dark,
    AppThemePreference.system => ThemeMode.system,
  };

  Color get effectiveAccentColor => customAccentColor ?? AppColors.primary;

  AppThemeState copyWith({
    AppThemePreference? preference,
    bool? useSystemColor,
    Color? customAccentColor,
    bool clearCustomAccentColor = false,
    double? colorIntensity,
    bool? isLoaded,
  }) {
    return AppThemeState(
      preference: preference ?? this.preference,
      useSystemColor: useSystemColor ?? this.useSystemColor,
      customAccentColor: clearCustomAccentColor
          ? null
          : (customAccentColor ?? this.customAccentColor),
      colorIntensity: colorIntensity ?? this.colorIntensity,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

class ThemeController extends StateNotifier<AppThemeState> {
  ThemeController([this._preferences]) : super(const AppThemeState()) {
    _load();
  }

  final SharedPreferences? _preferences;

  static const _storageKey = 'one_wallet_flutter.theme.preference.v1';
  static const _useSystemColorKey = 'one_wallet_flutter.theme.use_system_color.v1';
  static const _accentColorKey = 'one_wallet_flutter.theme.accent_color.v1';
  static const _colorIntensityKey = 'one_wallet_flutter.theme.color_intensity.v1';

  Future<void> setPreference(AppThemePreference preference) async {
    final previousPreference = state.preference;
    state = state.copyWith(preference: preference, isLoaded: true);
    if (_preferences == null) return;
    try {
      await _preferences.setString(_storageKey, preference.name);
    } catch (error) {
      if (state.preference == preference) {
        state = state.copyWith(preference: previousPreference);
      }
      debugPrint('ThemeController.setPreference failed to persist: $error');
      rethrow;
    }
  }

  Future<void> setUseSystemColor(bool useSystemColor) async {
    final previousUseSystem = state.useSystemColor;
    state = state.copyWith(useSystemColor: useSystemColor, isLoaded: true);
    if (_preferences == null) return;
    try {
      await _preferences.setBool(_useSystemColorKey, useSystemColor);
    } catch (error) {
      if (state.useSystemColor == useSystemColor) {
        state = state.copyWith(useSystemColor: previousUseSystem);
      }
      debugPrint('ThemeController.setUseSystemColor failed to persist: $error');
      rethrow;
    }
  }

  Future<void> setCustomAccentColor(Color color) async {
    final previousAccent = state.customAccentColor;
    final previousUseSystem = state.useSystemColor;
    state = state.copyWith(
      customAccentColor: color,
      useSystemColor: false,
      isLoaded: true,
    );
    if (_preferences == null) return;
    try {
      await _preferences.setInt(_accentColorKey, color.toARGB32());
      await _preferences.setBool(_useSystemColorKey, false);
    } catch (error) {
      if (state.customAccentColor == color) {
        state = state.copyWith(
          customAccentColor: previousAccent,
          useSystemColor: previousUseSystem,
        );
      }
      debugPrint('ThemeController.setCustomAccentColor failed to persist: $error');
      rethrow;
    }
  }

  Future<void> setColorIntensity(double intensity, {bool persist = true}) async {
    final clamped = intensity.clamp(0.2, 1.8);
    final previousIntensity = state.colorIntensity;
    state = state.copyWith(colorIntensity: clamped, isLoaded: true);
    if (!persist || _preferences == null) return;
    try {
      await _preferences.setDouble(_colorIntensityKey, clamped);
    } catch (error) {
      if (state.colorIntensity == clamped) {
        state = state.copyWith(colorIntensity: previousIntensity);
      }
      debugPrint('ThemeController.setColorIntensity failed to persist: $error');
      rethrow;
    }
  }

  Future<void> resetToDefaults() async {
    final previousState = state;
    state = const AppThemeState(
      preference: AppThemePreference.amoled,
      useSystemColor: true,
      customAccentColor: null,
      colorIntensity: 1.0,
      isLoaded: true,
    );
    if (_preferences == null) return;
    try {
      await _preferences.setString(_storageKey, AppThemePreference.amoled.name);
      await _preferences.setBool(_useSystemColorKey, true);
      await _preferences.remove(_accentColorKey);
      await _preferences.setDouble(_colorIntensityKey, 1.0);
    } catch (error) {
      state = previousState;
      debugPrint('ThemeController.resetToDefaults failed to persist: $error');
      rethrow;
    }
  }

  void _load() {
    if (_preferences == null) {
      state = const AppThemeState(isLoaded: true);
      return;
    }
    try {
      final raw = _preferences.getString(_storageKey);
      final mappedRaw = raw == 'dark' ? 'amoled' : raw;
      final preference = AppThemePreference.values.firstWhere(
        (item) => item.name == mappedRaw,
        orElse: () => AppThemePreference.amoled,
      );

      final useSystemColor = _preferences.getBool(_useSystemColorKey) ?? true;
      final accentValue = _preferences.getInt(_accentColorKey);
      final customAccentColor = accentValue != null ? Color(accentValue) : null;
      final colorIntensity = (_preferences.getDouble(_colorIntensityKey) ?? 1.0)
          .clamp(0.2, 1.8);

      state = AppThemeState(
        preference: preference,
        useSystemColor: useSystemColor,
        customAccentColor: customAccentColor,
        colorIntensity: colorIntensity,
        isLoaded: true,
      );
    } catch (error) {
      debugPrint('ThemeController._load failed to read preferences: $error');
      state = const AppThemeState(isLoaded: true);
    }
  }
}
