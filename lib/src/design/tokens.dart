import 'package:flutter/material.dart';

abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class AppRadii {
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 22;
  static const double xl = 28;
  static const double pill = 999;
}

abstract final class AppSizes {
  static const double bottomBar = 86;
  static const double bottomBarClearance = 140;
  static const double rowLarge = 76;
  static const double islandMaxWidth = 430;
}

abstract final class AppColors {
  static const Color primary = Color(0xFFFA233B); // Apple Music Red
  static const Color secondary = Color(0xFF8B929E); // Neutral cool grey
  static const Color tertiary = Color(0xFFFA233B); // Red

  static const Color positiveLight = Color(0xFF137A3A);
  static const Color positiveDark = Color(0xFF8ED99F);
  static const Color dangerLight = Color(0xFFBA1A1A);
  static const Color dangerDark = Color(0xFFFFB4AB);
  static const Color warning = Color(0xFF946200);
  static const Color lightBackground = Color(0xFFF8F9FF);
  static const Color darkBackground = Color(0xFF101318);
  static const Color amoledBackground = Color(0xFF000000);
  static const Color launchBackground = Color(0xFF0F1820);
  static const Color launchBackgroundDeep = Color(0xFF0B1218);
  static const Color launchPrimary = Color(0xFFA9C7FF);
  static const Color launchTertiary = Color(0xFF9BDDB5);
  static const Color launchGold = Color(0xFFDFC894);
  static const Color launchText = Color(0xFFF4F7FB);
  static const Color launchMutedText = Color(0xFFC8D3DF);

  static const List<Color> accountPalette = [
    // Original colors
    Color(0xFF315DA8),
    Color(0xFF2F6B4F),
    Color(0xFF6B5F47),
    Color(0xFF7C4DFF),
    Color(0xFF006A6A),
    Color(0xFFA84731),
    Color(0xFF7256A8),
    Color(0xFF3D6A25),
    
    // Additional Material-like curated colors
    Color(0xFFD32F2F), // Red
    Color(0xFFC2185B), // Pink
    Color(0xFF7B1FA2), // Purple
    Color(0xFF512DA8), // Deep Purple
    Color(0xFF303F9F), // Indigo
    Color(0xFF1976D2), // Blue
    Color(0xFF0288D1), // Light Blue
    Color(0xFF0097A7), // Cyan
    Color(0xFF00796B), // Teal
    Color(0xFF388E3C), // Green
    Color(0xFF689F38), // Light Green
    Color(0xFFAFB42B), // Lime
    Color(0xFFFBC02D), // Yellow
    Color(0xFFFFA000), // Amber
    Color(0xFFF57C00), // Orange
    Color(0xFFE64A19), // Deep Orange
    Color(0xFF5D4037), // Brown
    Color(0xFF616161), // Grey
    Color(0xFF455A64), // Blue Grey
    
    // More vibrant modern tones
    Color(0xFFE040FB), // Vibrant Purple
    Color(0xFF536DFE), // Vibrant Blue
    Color(0xFF18FFFF), // Vibrant Cyan
    Color(0xFF00E676), // Vibrant Green
    Color(0xFFFFEA00), // Vibrant Yellow
    Color(0xFFFF3D00), // Vibrant Red
  ];
}

extension ColorAlpha on Color {
  Color withAlphaFactor(double opacity) =>
      withAlpha((opacity.clamp(0, 1) * 255).round());
}
