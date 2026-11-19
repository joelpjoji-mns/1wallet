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
    this.surfaceContrast = 1.0,
    this.outlineThickness = 0.4,
    this.outlineOpacity = 0.15,
    this.islandOutlineThickness = 0.3,
    this.islandOutlineOpacity = 0.10,
    this.fabOutlineThickness = 0.3,
    this.fabOutlineOpacity = 0.10,
    this.isLoaded = false,
  });

  final AppThemePreference preference;
  final bool useSystemColor;
  final Color? customAccentColor;
  final double colorIntensity;
  final double surfaceContrast;
  final double outlineThickness;
  final double outlineOpacity;
  final double islandOutlineThickness;
  final double islandOutlineOpacity;
  final double fabOutlineThickness;
  final double fabOutlineOpacity;
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
    double? surfaceContrast,
    double? outlineThickness,
    double? outlineOpacity,
    double? islandOutlineThickness,
    double? islandOutlineOpacity,
    double? fabOutlineThickness,
    double? fabOutlineOpacity,
    bool? isLoaded,
  }) {
    return AppThemeState(
      preference: preference ?? this.preference,
      useSystemColor: useSystemColor ?? this.useSystemColor,
      customAccentColor: clearCustomAccentColor
          ? null
          : (customAccentColor ?? this.customAccentColor),
      colorIntensity: colorIntensity ?? this.colorIntensity,
      surfaceContrast: surfaceContrast ?? this.surfaceContrast,
      outlineThickness: outlineThickness ?? this.outlineThickness,
      outlineOpacity: outlineOpacity ?? this.outlineOpacity,
      islandOutlineThickness:
          islandOutlineThickness ?? this.islandOutlineThickness,
      islandOutlineOpacity: islandOutlineOpacity ?? this.islandOutlineOpacity,
      fabOutlineThickness: fabOutlineThickness ?? this.fabOutlineThickness,
      fabOutlineOpacity: fabOutlineOpacity ?? this.fabOutlineOpacity,
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
  static const _useSystemColorKey =
      'one_wallet_flutter.theme.use_system_color.v1';
  static const _accentColorKey = 'one_wallet_flutter.theme.accent_color.v1';
  static const _colorIntensityKey =
      'one_wallet_flutter.theme.color_intensity.v1';
  static const _surfaceContrastKey =
      'one_wallet_flutter.theme.surface_contrast.v1';
  static const _outlineThicknessKey =
      'one_wallet_flutter.theme.outline_thickness.v1';
  static const _outlineOpacityKey =
      'one_wallet_flutter.theme.outline_opacity.v1';
  static const _islandOutlineThicknessKey =
      'one_wallet_flutter.theme.island_outline_thickness.v1';
  static const _islandOutlineOpacityKey =
      'one_wallet_flutter.theme.island_outline_opacity.v1';
  static const _fabOutlineThicknessKey =
      'one_wallet_flutter.theme.fab_outline_thickness.v1';
  static const _fabOutlineOpacityKey =
      'one_wallet_flutter.theme.fab_outline_opacity.v1';

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
      debugPrint(
        'ThemeController.setCustomAccentColor failed to persist: $error',
      );
      rethrow;
    }
  }

  Future<void> setColorIntensity(
    double intensity, {
    bool persist = true,
  }) async {
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

  Future<void> setSurfaceContrast(
    double contrast, {
    bool persist = true,
  }) async {
    final clamped = contrast.clamp(0.0, 1.8);
    final previousContrast = state.surfaceContrast;
    state = state.copyWith(surfaceContrast: clamped, isLoaded: true);
    if (!persist || _preferences == null) return;
    try {
      await _preferences.setDouble(_surfaceContrastKey, clamped);
    } catch (error) {
      if (state.surfaceContrast == clamped) {
        state = state.copyWith(surfaceContrast: previousContrast);
      }
      debugPrint(
        'ThemeController.setSurfaceContrast failed to persist: $error',
      );
      rethrow;
    }
  }

  Future<void> setOutlineThickness(
    double thickness, {
    bool persist = true,
  }) async {
    final clamped = thickness.clamp(0.0, 2.5);
    final previousThickness = state.outlineThickness;
    state = state.copyWith(outlineThickness: clamped, isLoaded: true);
    if (!persist || _preferences == null) return;
    try {
      await _preferences.setDouble(_outlineThicknessKey, clamped);
    } catch (error) {
      if (state.outlineThickness == clamped) {
        state = state.copyWith(outlineThickness: previousThickness);
      }
      debugPrint(
        'ThemeController.setOutlineThickness failed to persist: $error',
      );
      rethrow;
    }
  }

  Future<void> setOutlineOpacity(double opacity, {bool persist = true}) async {
    final clamped = opacity.clamp(0.0, 1.0);
    final previousOpacity = state.outlineOpacity;
    state = state.copyWith(outlineOpacity: clamped, isLoaded: true);
    if (!persist || _preferences == null) return;
    try {
      await _preferences.setDouble(_outlineOpacityKey, clamped);
    } catch (error) {
      if (state.outlineOpacity == clamped) {
        state = state.copyWith(outlineOpacity: previousOpacity);
      }
      debugPrint('ThemeController.setOutlineOpacity failed to persist: $error');
      rethrow;
    }
  }

  Future<void> setIslandOutlineThickness(
    double thickness, {
    bool persist = true,
  }) async {
    final clamped = thickness.clamp(0.0, 2.5);
    final previous = state.islandOutlineThickness;
    state = state.copyWith(islandOutlineThickness: clamped, isLoaded: true);
    if (!persist || _preferences == null) return;
    try {
      await _preferences.setDouble(_islandOutlineThicknessKey, clamped);
    } catch (error) {
      if (state.islandOutlineThickness == clamped) {
        state = state.copyWith(islandOutlineThickness: previous);
      }
      debugPrint(
        'ThemeController.setIslandOutlineThickness failed to persist: $error',
      );
      rethrow;
    }
  }

  Future<void> setIslandOutlineOpacity(
    double opacity, {
    bool persist = true,
  }) async {
    final clamped = opacity.clamp(0.0, 1.0);
    final previous = state.islandOutlineOpacity;
    state = state.copyWith(islandOutlineOpacity: clamped, isLoaded: true);
    if (!persist || _preferences == null) return;
    try {
      await _preferences.setDouble(_islandOutlineOpacityKey, clamped);
    } catch (error) {
      if (state.islandOutlineOpacity == clamped) {
        state = state.copyWith(islandOutlineOpacity: previous);
      }
      debugPrint(
        'ThemeController.setIslandOutlineOpacity failed to persist: $error',
      );
      rethrow;
    }
  }

  Future<void> setFabOutlineThickness(
    double thickness, {
    bool persist = true,
  }) async {
    final clamped = thickness.clamp(0.0, 2.5);
    final previous = state.fabOutlineThickness;
    state = state.copyWith(fabOutlineThickness: clamped, isLoaded: true);
    if (!persist || _preferences == null) return;
    try {
      await _preferences.setDouble(_fabOutlineThicknessKey, clamped);
    } catch (error) {
      if (state.fabOutlineThickness == clamped) {
        state = state.copyWith(fabOutlineThickness: previous);
      }
      debugPrint(
        'ThemeController.setFabOutlineThickness failed to persist: $error',
      );
      rethrow;
    }
  }

  Future<void> setFabOutlineOpacity(
    double opacity, {
    bool persist = true,
  }) async {
    final clamped = opacity.clamp(0.0, 1.0);
    final previous = state.fabOutlineOpacity;
    state = state.copyWith(fabOutlineOpacity: clamped, isLoaded: true);
    if (!persist || _preferences == null) return;
    try {
      await _preferences.setDouble(_fabOutlineOpacityKey, clamped);
    } catch (error) {
      if (state.fabOutlineOpacity == clamped) {
        state = state.copyWith(fabOutlineOpacity: previous);
      }
      debugPrint(
        'ThemeController.setFabOutlineOpacity failed to persist: $error',
      );
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
      surfaceContrast: 1.0,
      outlineThickness: 0.4,
      outlineOpacity: 0.15,
      islandOutlineThickness: 0.3,
      islandOutlineOpacity: 0.10,
      fabOutlineThickness: 0.3,
      fabOutlineOpacity: 0.10,
      isLoaded: true,
    );
    if (_preferences == null) return;
    try {
      await _preferences.setString(_storageKey, AppThemePreference.amoled.name);
      await _preferences.setBool(_useSystemColorKey, true);
      await _preferences.remove(_accentColorKey);
      await _preferences.setDouble(_colorIntensityKey, 1.0);
      await _preferences.setDouble(_surfaceContrastKey, 1.0);
      await _preferences.setDouble(_outlineThicknessKey, 0.4);
      await _preferences.setDouble(_outlineOpacityKey, 0.15);
      await _preferences.setDouble(_islandOutlineThicknessKey, 0.3);
      await _preferences.setDouble(_islandOutlineOpacityKey, 0.10);
      await _preferences.setDouble(_fabOutlineThicknessKey, 0.3);
      await _preferences.setDouble(_fabOutlineOpacityKey, 0.10);
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
      final surfaceContrast =
          (_preferences.getDouble(_surfaceContrastKey) ?? 1.0).clamp(0.0, 1.8);
      final outlineThickness =
          (_preferences.getDouble(_outlineThicknessKey) ?? 0.4).clamp(0.0, 2.5);
      final outlineOpacity =
          (_preferences.getDouble(_outlineOpacityKey) ?? 0.15).clamp(0.0, 1.0);
      final islandOutlineThickness =
          (_preferences.getDouble(_islandOutlineThicknessKey) ?? 0.3).clamp(
            0.0,
            2.5,
          );
      final islandOutlineOpacity =
          (_preferences.getDouble(_islandOutlineOpacityKey) ?? 0.10).clamp(
            0.0,
            1.0,
          );
      final fabOutlineThickness =
          (_preferences.getDouble(_fabOutlineThicknessKey) ?? 0.3).clamp(
            0.0,
            2.5,
          );
      final fabOutlineOpacity =
          (_preferences.getDouble(_fabOutlineOpacityKey) ?? 0.10).clamp(
            0.0,
            1.0,
          );

      state = AppThemeState(
        preference: preference,
        useSystemColor: useSystemColor,
        customAccentColor: customAccentColor,
        colorIntensity: colorIntensity,
        surfaceContrast: surfaceContrast,
        outlineThickness: outlineThickness,
        outlineOpacity: outlineOpacity,
        islandOutlineThickness: islandOutlineThickness,
        islandOutlineOpacity: islandOutlineOpacity,
        fabOutlineThickness: fabOutlineThickness,
        fabOutlineOpacity: fabOutlineOpacity,
        isLoaded: true,
      );
    } catch (error) {
      debugPrint('ThemeController._load failed to read preferences: $error');
      state = const AppThemeState(isLoaded: true);
    }
  }
}
