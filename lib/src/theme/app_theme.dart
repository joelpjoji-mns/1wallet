import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../design/tokens.dart';

class ThemeAccentOption {
  const ThemeAccentOption({required this.name, required this.color});

  final String name;
  final Color color;
}

abstract final class AppThemeAccents {
  static const crimson = Color(0xFFFA233B); // Apple Music Red (Default)
  static const sapphire = Color(0xFF007AFF); // iOS Blue
  static const violet = Color(0xFF7C3AED); // Electric Violet
  static const emerald = Color(0xFF10B981); // Emerald Green
  static const orange = Color(0xFFFF6B00); // Sunset Orange
  static const rose = Color(0xFFF43F5E); // Rose Pink
  static const cyan = Color(0xFF06B6D4); // Ocean Cyan
  static const indigo = Color(0xFF4F46E5); // Royal Indigo
  static const amber = Color(0xFFF59E0B); // Amber Gold
  static const magenta = Color(0xFFEC4899); // Bubblegum Magenta
  static const slate = Color(0xFF64748B); // Nordic Slate

  static const List<ThemeAccentOption> options = [
    ThemeAccentOption(name: 'Crimson', color: crimson),
    ThemeAccentOption(name: 'Sapphire', color: sapphire),
    ThemeAccentOption(name: 'Violet', color: violet),
    ThemeAccentOption(name: 'Emerald', color: emerald),
    ThemeAccentOption(name: 'Orange', color: orange),
    ThemeAccentOption(name: 'Rose', color: rose),
    ThemeAccentOption(name: 'Cyan', color: cyan),
    ThemeAccentOption(name: 'Indigo', color: indigo),
    ThemeAccentOption(name: 'Amber', color: amber),
    ThemeAccentOption(name: 'Magenta', color: magenta),
    ThemeAccentOption(name: 'Slate', color: slate),
  ];
}

abstract final class AppTheme {
  static Color adjustColorIntensity(
    Color color,
    double intensity, {
    Brightness brightness = Brightness.light,
  }) {
    if (intensity == 1.0) return color;
    final hsl = HSLColor.fromColor(color);

    if (intensity > 1.0) {
      // Boost saturation beyond the base value
      final boost = ((intensity - 1.0) * 0.5).clamp(0.0, 0.5);
      return hsl
          .withSaturation((hsl.saturation + boost).clamp(0.0, 1.0))
          .toColor();
    }

    // intensity < 1.0: desaturate AND lerp lightness toward the neutral extreme
    // so that at intensity=0 the color is essentially pure black (dark) or
    // pure white (light), matching the user's "transparent / no-color" intent.
    final t = intensity.clamp(0.0, 1.0);
    final newSaturation = (hsl.saturation * t).clamp(0.0, 1.0);
    // Target lightness: near-black for dark themes, near-white for light themes
    final targetLightness = brightness == Brightness.dark ? 0.12 : 0.92;
    final newLightness = lerpDouble(
      targetLightness,
      hsl.lightness,
      t,
    )!.clamp(0.0, 1.0);
    return hsl
        .withSaturation(newSaturation)
        .withLightness(newLightness)
        .toColor();
  }

  static ThemeData light({
    ColorScheme? systemColorScheme,
    Color? customAccentColor,
    double colorIntensity = 1.0,
    bool useSystemColor = true,
  }) => _theme(
    Brightness.light,
    systemColorScheme: systemColorScheme,
    customAccentColor: customAccentColor,
    colorIntensity: colorIntensity,
    useSystemColor: useSystemColor,
  );

  static ThemeData amoled({
    ColorScheme? systemColorScheme,
    Color? customAccentColor,
    double colorIntensity = 1.0,
    bool useSystemColor = true,
  }) => _theme(
    Brightness.dark,
    amoled: true,
    systemColorScheme: systemColorScheme,
    customAccentColor: customAccentColor,
    colorIntensity: colorIntensity,
    useSystemColor: useSystemColor,
  );

  static ThemeData _theme(
    Brightness brightness, {
    bool amoled = false,
    ColorScheme? systemColorScheme,
    Color? customAccentColor,
    double colorIntensity = 1.0,
    bool useSystemColor = true,
  }) {
    final dark = brightness == Brightness.dark;

    final effectiveSeedColor = adjustColorIntensity(
      customAccentColor ?? AppColors.primary,
      colorIntensity,
      brightness: brightness,
    );

    ColorScheme baseScheme;
    if (useSystemColor &&
        systemColorScheme != null &&
        systemColorScheme.brightness == brightness) {
      if (colorIntensity == 1.0) {
        baseScheme = systemColorScheme;
      } else {
        baseScheme = systemColorScheme.copyWith(
          primary: adjustColorIntensity(
            systemColorScheme.primary,
            colorIntensity,
            brightness: brightness,
          ),
          secondary: adjustColorIntensity(
            systemColorScheme.secondary,
            colorIntensity,
            brightness: brightness,
          ),
          tertiary: adjustColorIntensity(
            systemColorScheme.tertiary,
            colorIntensity,
            brightness: brightness,
          ),
          primaryContainer: adjustColorIntensity(
            systemColorScheme.primaryContainer,
            colorIntensity,
            brightness: brightness,
          ),
          secondaryContainer: adjustColorIntensity(
            systemColorScheme.secondaryContainer,
            colorIntensity,
            brightness: brightness,
          ),
          tertiaryContainer: adjustColorIntensity(
            systemColorScheme.tertiaryContainer,
            colorIntensity,
            brightness: brightness,
          ),
        );
      }
    } else {
      baseScheme = ColorScheme.fromSeed(
        seedColor: effectiveSeedColor,
        brightness: brightness,
      );
      if (colorIntensity != 1.0) {
        baseScheme = baseScheme.copyWith(
          primary: adjustColorIntensity(
            baseScheme.primary,
            colorIntensity,
            brightness: brightness,
          ),
          secondary: adjustColorIntensity(
            baseScheme.secondary,
            colorIntensity,
            brightness: brightness,
          ),
          tertiary: adjustColorIntensity(
            baseScheme.tertiary,
            colorIntensity,
            brightness: brightness,
          ),
          primaryContainer: adjustColorIntensity(
            baseScheme.primaryContainer,
            colorIntensity,
            brightness: brightness,
          ),
        );
      }
    }

    final scheme = baseScheme.copyWith(
      primaryContainer: dark
          ? Color.lerp(
              baseScheme.surfaceContainerHigh,
              baseScheme.primaryContainer,
              0.65,
            )
          : Color.lerp(
              baseScheme.surfaceContainerHighest,
              baseScheme.primaryContainer,
              0.65,
            ),
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
    final baseTypography = dark
        ? Typography.material2021().white
        : Typography.material2021().black;
    final textTheme = baseTypography
        .apply(
          fontFamily: 'Inter',
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        )
        .copyWith(
          labelLarge:
              (dark
                      ? Typography.material2021().white.labelLarge
                      : Typography.material2021().black.labelLarge)
                  ?.copyWith(color: scheme.onSurface, fontFamily: 'Inter'),
          labelMedium:
              (dark
                      ? Typography.material2021().white.labelMedium
                      : Typography.material2021().black.labelMedium)
                  ?.copyWith(color: scheme.onSurface, fontFamily: 'Inter'),
          labelSmall:
              (dark
                      ? Typography.material2021().white.labelSmall
                      : Typography.material2021().black.labelSmall)
                  ?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFamily: 'Inter',
                  ),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: 'Inter',
      canvasColor: scheme.surfaceContainerHigh,
      scaffoldBackgroundColor: amoled
          ? AppColors.amoledBackground
          : dark
          ? AppColors.darkBackground
          : AppColors.lightBackground,
      visualDensity: VisualDensity.standard,
      textTheme: textTheme,
      iconTheme: IconThemeData(color: scheme.onSurface),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: scheme.onPrimary,
          backgroundColor: scheme.primary,
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
          disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.12),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          foregroundColor: scheme.primary,
          backgroundColor: scheme.surfaceContainerHigh,
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
          disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.12),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
            width: 1.0,
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurface,
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.onPrimary;
            }
            return scheme.onSurface;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.primary;
            }
            return scheme.surfaceContainerHigh;
          }),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
            width: 0.8,
          ),
        ),
        textStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurface),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
                width: 0.8,
              ),
            ),
          ),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
                width: 0.8,
              ),
            ),
          ),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(scheme.onSurface),
          iconColor: WidgetStatePropertyAll(scheme.onSurface),
        ),
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: scheme.primary,
        barBackgroundColor: Colors.transparent,
        scaffoldBackgroundColor: amoled
            ? AppColors.amoledBackground
            : dark
            ? AppColors.darkBackground
            : AppColors.lightBackground,
        textTheme: CupertinoTextThemeData(
          primaryColor: scheme.primary,
          textStyle: TextStyle(color: scheme.onSurface, fontFamily: 'Inter'),
          navActionTextStyle: TextStyle(
            color: scheme.primary,
            fontFamily: 'Inter',
          ),
        ),
      ),
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
