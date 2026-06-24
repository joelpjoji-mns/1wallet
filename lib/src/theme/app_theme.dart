import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../design/tokens.dart';

abstract final class AppTheme {
  static bool disableGoogleFonts = false;

  static ThemeData light({
    String? accentColor,
    ColorScheme? systemColorScheme,
  }) => _theme(
    Brightness.light,
    accentColor: accentColor,
    systemColorScheme: systemColorScheme,
  );

  static ThemeData dark({
    String? accentColor,
    ColorScheme? systemColorScheme,
  }) => _theme(
    Brightness.dark,
    accentColor: accentColor,
    systemColorScheme: systemColorScheme,
  );

  static ThemeData amoled({
    String? accentColor,
    ColorScheme? systemColorScheme,
  }) => _theme(
    Brightness.dark,
    amoled: true,
    accentColor: accentColor,
    systemColorScheme: systemColorScheme,
  );

  static ThemeData _theme(
    Brightness brightness, {
    bool amoled = false,
    String? accentColor,
    ColorScheme? systemColorScheme,
  }) {
    final dark = brightness == Brightness.dark;
    final customAccentColor = _parseAccentColor(accentColor);
    final baseScheme =
        customAccentColor == null &&
            systemColorScheme != null &&
            systemColorScheme.brightness == brightness
        ? systemColorScheme
        : ColorScheme.fromSeed(
            seedColor: customAccentColor ?? AppColors.primary,
            brightness: brightness,
          );

    var scheme = baseScheme;
    if (customAccentColor != null) {
      scheme = scheme.copyWith(primary: customAccentColor);
    }

    scheme = scheme.copyWith(
      error: dark ? AppColors.dangerDark : AppColors.dangerLight,
      surface: amoled
          ? const Color(0xFF050505)
          : _accentTintedSurface(
              scheme.surface,
              scheme.primary,
              dark ? 0.03 : 0.018,
            ),
      surfaceContainerLow: amoled
          ? const Color(0xFF050505)
          : _accentTintedSurface(
              scheme.surfaceContainerLow,
              scheme.primary,
              dark ? 0.08 : 0.045,
            ),
      surfaceContainer: amoled
          ? const Color(0xFF090909)
          : _accentTintedSurface(
              scheme.surfaceContainer,
              scheme.primary,
              dark ? 0.10 : 0.06,
            ),
      surfaceContainerHigh: amoled
          ? const Color(0xFF101010)
          : _accentTintedSurface(
              scheme.surfaceContainerHigh,
              scheme.primary,
              dark ? 0.12 : 0.075,
            ),
      surfaceContainerHighest: amoled
          ? const Color(0xFF171717)
          : _accentTintedSurface(
              scheme.surfaceContainerHighest,
              scheme.primary,
              dark ? 0.14 : 0.09,
            ),
      outlineVariant: _accentTintedSurface(
        scheme.outlineVariant,
        scheme.primary,
        dark ? 0.18 : 0.12,
      ),
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
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }

  static Color? _parseAccentColor(String? accentColor) {
    if (accentColor != null &&
        accentColor.length == 7 &&
        accentColor.startsWith('#')) {
      final intValue = int.tryParse(accentColor.substring(1), radix: 16);
      if (intValue != null) {
        return Color(intValue | 0xFF000000);
      }
    }
    return null;
  }

  static Color _accentTintedSurface(
    Color surface,
    Color accent,
    double opacity,
  ) {
    return Color.alphaBlend(accent.withAlphaFactor(opacity), surface);
  }
}
