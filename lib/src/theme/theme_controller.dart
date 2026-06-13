import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeControllerProvider =
    StateNotifierProvider<ThemeController, AppThemeState>((ref) {
      return ThemeController();
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
  ThemeController() : super(const AppThemeState()) {
    _load();
  }

  static const _storageKey = 'one_wallet_flutter.theme.preference.v1';
  static const _accentKey = 'one_wallet_flutter.accent.preference.v1';

  Future<void> setPreference(AppThemePreference preference) async {
    state = state.copyWith(preference: preference, isLoaded: true);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, preference.name);
  }

  Future<void> setAccentColor(String? hexColor) async {
    state = state.copyWith(
      accentColor: hexColor,
      isLoaded: true,
      clearAccent: hexColor == null,
    );
    final preferences = await SharedPreferences.getInstance();
    if (hexColor == null) {
      await preferences.remove(_accentKey);
    } else {
      await preferences.setString(_accentKey, hexColor);
    }
  }

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_storageKey);
      final accent = preferences.getString(_accentKey);
      final preference = AppThemePreference.values.firstWhere(
        (item) => item.name == raw,
        orElse: () => AppThemePreference.amoled,
      );
      if (!mounted) return;
      state = AppThemeState(
        preference: preference,
        accentColor: accent,
        isLoaded: true,
      );
    } catch (_) {
      if (!mounted) return;
      state = const AppThemeState(isLoaded: true);
    }
  }
}
