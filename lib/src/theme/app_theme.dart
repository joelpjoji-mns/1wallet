import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design/tokens.dart';

abstract final class AppTheme {
  static bool disableGoogleFonts = false;

  static ThemeData light({ColorScheme? systemColorScheme}) =>
      _theme(Brightness.light, systemColorScheme: systemColorScheme);

  static ThemeData amoled({ColorScheme? systemColorScheme}) => _theme(
    Brightness.dark,
    amoled: true,
    systemColorScheme: systemColorScheme,
  );

  static ThemeData _theme(
    Brightness brightness, {
    bool amoled = false,
    ColorScheme? systemColorScheme,
  }) {
    final dark = brightness == Brightness.dark;
    final baseScheme =
        systemColorScheme != null && systemColorScheme.brightness == brightness
        ? systemColorScheme
        : ColorScheme.fromSeed(
            seedColor: AppColors.primary,
            brightness: brightness,
          );

    final scheme = baseScheme.copyWith(
      error: dark ? AppColors.dangerDark : AppColors.dangerLight,
      surface: amoled ? AppColors.amoledBackground : baseScheme.surface,
      surfaceContainerLowest: amoled
          ? AppColors.amoledBackground
          : baseScheme.surfaceContainerLowest,
      surfaceContainerLow: amoled
          ? const Color(0xFF080808)
          : baseScheme.surfaceContainerLow,
      surfaceContainer: amoled
          ? const Color(0xFF0E0E0E)
          : baseScheme.surfaceContainer,
      surfaceContainerHigh: amoled
          ? const Color(0xFF151515)
          : baseScheme.surfaceContainerHigh,
      surfaceContainerHighest: amoled
          ? const Color(0xFF1C1C1C)
          : baseScheme.surfaceContainerHighest,
      outlineVariant: baseScheme.outlineVariant,
    );

    final textTheme = Typography.material2021(
      platform: TargetPlatform.android,
    ).black.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: disableGoogleFonts
          ? 'Outfit'
          : GoogleFonts.outfit().fontFamily,
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
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
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
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }
}
