import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1455/g1455.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/app/one_wallet_app.dart';

import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  testWidgets(
    'Tab state is kept alive across tab switches without atlas NaN corruption',
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

      // Rapidly swipe through tabs: 0 -> 1 -> 2 -> 3
      for (var i = 0; i < 3; i++) {
        await tester.drag(find.byType(PageView), const Offset(-360, 0));
        await tester.pumpAndSettle();
      }
      expect(tester.widget<GlassTabBar>(tabBar).selectedIndex, 3);

      // Swipe back: 3 -> 2 -> 1 -> 0
      for (var i = 0; i < 3; i++) {
        await tester.drag(find.byType(PageView), const Offset(360, 0));
        await tester.pumpAndSettle();
      }
      expect(tester.widget<GlassTabBar>(tabBar).selectedIndex, 0);
    },
  );
}
