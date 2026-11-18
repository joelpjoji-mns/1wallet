import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/features/settings/theme_mode_screen.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/theme/theme_controller.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildSubject({ThemeController? controller}) {
    return ProviderScope(
      overrides: [
        if (controller != null)
          themeControllerProvider.overrideWith((ref) => controller),
      ],
      child: const MaterialApp(home: ThemeModeScreen()),
    );
  }

  testWidgets('renders all theme customization sections and live preview', (
    WidgetTester tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController(prefs);

    await tester.pumpWidget(buildSubject(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('Theme & Appearance'), findsOneWidget);
    expect(find.text('Live Preview'), findsOneWidget);
    expect(find.text('Theme mode'), findsOneWidget);
    expect(find.text('System'), findsWidgets);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark (AMOLED)'), findsOneWidget);
    expect(find.text('Accent color'), findsOneWidget);
    expect(find.text('Match system wallpaper'), findsOneWidget);
    expect(find.text('Color intensity'), findsOneWidget);
    expect(find.text('Vibrancy & Saturation'), findsOneWidget);
    expect(find.text('Subtle (50%)'), findsOneWidget);
    expect(find.text('Default (100%)'), findsOneWidget);
    expect(find.text('Vibrant (150%)'), findsOneWidget);
    expect(find.text('Reset theme settings'), findsOneWidget);
  });

  testWidgets('tapping Light mode updates theme controller', (
    WidgetTester tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController(prefs);

    await tester.pumpWidget(buildSubject(controller: controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    expect(controller.state.preference, AppThemePreference.light);
  });

  testWidgets('tapping an accent swatch activates custom accent color', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController(prefs);

    await tester.pumpWidget(buildSubject(controller: controller));
    await tester.pumpAndSettle();

    // Tap the Sapphire swatch (second option)
    final sapphireOption = AppThemeAccents.options.firstWhere(
      (o) => o.name == 'Sapphire',
    );
    final swatchFinder = find.byTooltip('Sapphire');
    expect(swatchFinder, findsOneWidget);

    await tester.tap(swatchFinder);
    await tester.pumpAndSettle();

    expect(controller.state.customAccentColor, sapphireOption.color);
    expect(controller.state.useSystemColor, false);
  });

  testWidgets('tapping intensity preset chip updates intensity', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController(prefs);

    await tester.pumpWidget(buildSubject(controller: controller));
    await tester.pumpAndSettle();

    final presetFinder = find.text('Vibrant (150%)');
    await tester.tap(presetFinder);
    await tester.pumpAndSettle();

    expect(controller.state.colorIntensity, 1.5);
    expect(find.text('150%'), findsWidgets);
  });

  testWidgets('tapping reset theme settings resets to defaults', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController(prefs);
    await controller.setPreference(AppThemePreference.light);
    await controller.setCustomAccentColor(const Color(0xFF10B981));
    await controller.setColorIntensity(0.5);

    await tester.pumpWidget(buildSubject(controller: controller));
    await tester.pumpAndSettle();

    final resetFinder = find.text('Reset theme settings');
    await tester.tap(resetFinder);
    await tester.pumpAndSettle();

    expect(controller.state.preference, AppThemePreference.amoled);
    expect(controller.state.useSystemColor, true);
    expect(controller.state.customAccentColor, isNull);
    expect(controller.state.colorIntensity, 1.0);
  });
}
