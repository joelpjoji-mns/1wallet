import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../design/tokens.dart';

abstract final class AppTheme {
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
          ? AppColors.amoledSurfaceLow
          : baseScheme.surfaceContainerLow,
      surfaceContainer: amoled
          ? AppColors.amoledSurface
          : baseScheme.surfaceContainer,
      surfaceContainerHigh: amoled
          ? AppColors.amoledSurfaceHigh
          : baseScheme.surfaceContainerHigh,
      surfaceContainerHighest: amoled
          ? AppColors.amoledSurfaceHighest
          : baseScheme.surfaceContainerHighest,
      outlineVariant: baseScheme.outlineVariant,
    );

    // `ThemeData.fontFamily` only applies to the *default* text theme; an
    // explicit `textTheme` (like this one) keeps Typography's platform font
    // (Roboto / SF) unless the family is applied here as well.
    final textTheme = Typography.material2021().black.apply(
      fontFamily: 'Inter',
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: amoled
          ? AppColors.amoledBackground
          : dark
          ? AppColors.darkBackground
          : AppColors.lightBackground,
      visualDensity: VisualDensity.standard,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.xl),
        ),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
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
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        contentTextStyle: TextStyle(color: Colors.transparent, fontSize: 0.001),
        actionTextColor: Colors.transparent,
        disabledActionTextColor: Colors.transparent,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
