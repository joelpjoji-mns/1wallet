import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/design/tokens.dart';

void main() {
  test('system Material 3 schemes provide the shared accent color', () {
    const systemLight = ColorScheme.light(
      primary: Color(0xFF6750A4),
      secondary: Color(0xFF625B71),
    );
    const systemDark = ColorScheme.dark(
      primary: Color(0xFFD0BCFF),
      secondary: Color(0xFFCCC2DC),
    );

    expect(
      AppTheme.light(systemColorScheme: systemLight).colorScheme.primary,
      systemLight.primary,
    );
    expect(
      AppTheme.amoled(systemColorScheme: systemDark).colorScheme.primary,
      systemDark.primary,
    );
  });

  test(
    'generated fallback stays consistent and AMOLED surfaces stay black',
    () {
      final firstLight = AppTheme.light().colorScheme;
      final secondLight = AppTheme.light().colorScheme;
      final firstDark = AppTheme.amoled().colorScheme;
      final secondDark = AppTheme.amoled().colorScheme;

      expect(firstLight.primary, secondLight.primary);
      expect(firstDark.primary, secondDark.primary);
      expect(firstDark.surface, AppColors.amoledBackground);
      expect(
        AppTheme.amoled().scaffoldBackgroundColor,
        AppColors.amoledBackground,
      );
    },
  );
}
