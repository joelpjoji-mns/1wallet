import 'package:flutter/material.dart';

import '../design/tokens.dart';

abstract final class AppTheme {
  static ThemeData light({String? accentColor}) => _theme(Brightness.light, accentColor: accentColor);

  static ThemeData dark({String? accentColor}) => _theme(Brightness.dark, accentColor: accentColor);

  static ThemeData amoled({String? accentColor}) => _theme(Brightness.dark, amoled: true, accentColor: accentColor);

  static ThemeData _theme(Brightness brightness, {bool amoled = false, String? accentColor}) {
    final dark = brightness == Brightness.dark;
    
    Color primaryColor = AppColors.primary;
    if (accentColor != null && accentColor.length == 7 && accentColor.startsWith('#')) {
      final intValue = int.tryParse(accentColor.substring(1), radix: 16);
      if (intValue != null) {
        primaryColor = Color(intValue | 0xFF000000);
      }
    }

    final scheme =
        ColorScheme.fromSeed(
          seedColor: primaryColor,
          brightness: brightness,
        ).copyWith(
          primary: primaryColor,
          secondary: AppColors.secondary,
          tertiary: AppColors.tertiary,
          error: dark ? AppColors.dangerDark : AppColors.dangerLight,
          surface: amoled
              ? const Color(0xFF050505)
              : dark
              ? const Color(0xFF121316)
              : const Color(0xFFFFFBFF),
          surfaceContainerLow: amoled
              ? const Color(0xFF050505)
              : dark
              ? const Color(0xFF191A1E)
              : const Color(0xFFFFF6EC),
          surfaceContainer: amoled
              ? const Color(0xFF090909)
              : dark
              ? const Color(0xFF1F2024)
              : const Color(0xFFF7EFE6),
          surfaceContainerHigh: amoled
              ? const Color(0xFF101010)
              : dark
              ? const Color(0xFF292A2F)
              : const Color(0xFFF1E7DC),
          surfaceContainerHighest: amoled
              ? const Color(0xFF171717)
              : dark
              ? const Color(0xFF33343A)
              : const Color(0xFFE9DDD0),
          outlineVariant: dark
              ? const Color(0xFF4A4C52)
              : const Color(0xFFCFC2B5),
        );

    final textTheme = Typography.material2021(
      platform: TargetPlatform.android,
    ).black.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: amoled
          ? AppColors.amoledBackground
          : dark
          ? AppColors.darkBackground
          : const Color(0xFFFFFBFF),
      visualDensity: VisualDensity.standard,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
    );
  }
}
