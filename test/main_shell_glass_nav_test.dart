import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/app/one_wallet_app.dart';
import 'package:one_wallet_flutter/src/features/main/main_shell.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final fontLoader = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      fontLoader.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await fontLoader.load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Liquid Glass island indicator follows page swipes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(prefs: prefs),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OneWalletApp(),
      ),
    );
    await tester.pumpAndSettle();

    final tabBar = find.byType(GlassTabBar);
    expect(tabBar, findsOneWidget);
    expect(tester.widget<GlassTabBar>(tabBar).selectedIndex, 0);
    final glass = tester.widget<GlassTabBar>(tabBar);
    expect(glass.settings, isNotNull);
    expect(glass.settings?.whitenStrength, 0);

    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await tester.pumpAndSettle();

    expect(tester.widget<GlassTabBar>(tabBar).selectedIndex, 1);
  });

  testWidgets(
    'System back press on non-home tab does not reset selected tab to home',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(prefs: prefs),
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const OneWalletApp(),
        ),
      );
      await tester.pumpAndSettle();

      final tabBar = find.byType(GlassTabBar);
      expect(tester.widget<GlassTabBar>(tabBar).selectedIndex, 0);

      // Switch to tab 1 (History)
      await tester.drag(find.byType(PageView), const Offset(-320, 0));
      await tester.pumpAndSettle();
      expect(tester.widget<GlassTabBar>(tabBar).selectedIndex, 1);

      // Simulate system back button
      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Must not reset to home tab (tab 0)
      expect(tester.widget<GlassTabBar>(tabBar).selectedIndex, 1);
      expect(handled, isFalse);
    },
  );

  testWidgets('feedback does not cover the mobile navigation or add action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(prefs: prefs),
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OneWalletApp(),
      ),
    );
    await tester.pumpAndSettle();

    showAppSnackBar(tester.element(find.byType(MainShell)), 'Could not save');
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final feedback = tester.getRect(find.text('Could not save'));
    expect(
      feedback.overlaps(tester.getRect(find.byType(GlassTabBar))),
      isFalse,
    );
    expect(
      feedback.overlaps(
        tester.getRect(find.byType(IslandFloatingActionButton)),
      ),
      isFalse,
    );
  });
}
