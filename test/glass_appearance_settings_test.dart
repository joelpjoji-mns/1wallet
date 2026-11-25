import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/settings/settings_screen.dart';

import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Glass intensity and component optics preferences model & codec', () {
    test(
      'default preferences have clear finish, medium intensity and standard values',
      () {
        const prefs = LedgerPreferences();
        expect(prefs.glassFinish, AppGlassFinish.clear);
        expect(prefs.glassIntensity, GlassIntensity.medium);
        expect(prefs.glassBlurLevel, 0.5);
        expect(prefs.glassBackgroundOpacity, 0.04);
        expect(prefs.glassRefractionLevel, 1.0);
        expect(prefs.glassInteractionStrength, 0.35);
        expect(prefs.glassSpecularOpacity, 0.30);
        expect(prefs.glassComponentOptics, isEmpty);
      },
    );

    test(
      'withGlassFinish updates glass finish to regular and clear, frosted migrates to regular',
      () {
        const base = LedgerPreferences();
        expect(
          base.withGlassFinish(AppGlassFinish.regular).glassFinish,
          AppGlassFinish.regular,
        );
        expect(
          base.withGlassFinish(AppGlassFinish.clear).glassFinish,
          AppGlassFinish.clear,
        );
        expect(AppGlassFinish.fromString('frosted'), AppGlassFinish.regular);
      },
    );

    test(
      'per-component optics customization works independently for each target',
      () {
        const base = LedgerPreferences();

        // Every component defaults to the Clear finish.
        for (final target in GlassComponentTarget.values) {
          expect(
            base.opticsFor(target).finish,
            AppGlassFinish.clear,
            reason: target.name,
          );
        }
        final defaultIsland = base.opticsFor(GlassComponentTarget.islandBar);
        expect(defaultIsland.blur, 0.5);

        final defaultFab = base.opticsFor(GlassComponentTarget.fab);
        expect(defaultFab.finish, AppGlassFinish.clear);
        expect(defaultFab.blur, 1.0);

        // Customize Island Bar
        final updatedIsland = base.withComponentOptics(
          GlassComponentTarget.islandBar,
          finish: AppGlassFinish.regular,
          blur: 10.0,
          backgroundOpacity: 0.18,
        );
        expect(
          updatedIsland.opticsFor(GlassComponentTarget.islandBar).finish,
          AppGlassFinish.regular,
        );
        expect(
          updatedIsland.opticsFor(GlassComponentTarget.islandBar).blur,
          10.0,
        );
        expect(
          updatedIsland
              .opticsFor(GlassComponentTarget.islandBar)
              .backgroundOpacity,
          0.18,
        );
        // FAB remains unchanged
        expect(updatedIsland.opticsFor(GlassComponentTarget.fab).blur, 1.0);

        // Customize Dropdown Menu
        final updatedMenu = updatedIsland.withComponentOptics(
          GlassComponentTarget.dropdownMenu,
          blur: 22.0,
          backgroundOpacity: 0.30,
        );
        expect(
          updatedMenu.opticsFor(GlassComponentTarget.dropdownMenu).blur,
          22.0,
        );
        expect(
          updatedMenu
              .opticsFor(GlassComponentTarget.dropdownMenu)
              .backgroundOpacity,
          0.30,
        );
        expect(
          updatedMenu.opticsFor(GlassComponentTarget.islandBar).blur,
          10.0,
        );

        // Reset Island Bar to defaults
        final resetIsland = updatedMenu.resetComponentOptics(
          GlassComponentTarget.islandBar,
        );
        expect(resetIsland.opticsFor(GlassComponentTarget.islandBar).blur, 0.5);
        expect(
          resetIsland.opticsFor(GlassComponentTarget.islandBar).finish,
          AppGlassFinish.clear,
        );
        // Menu still retains its custom optics
        expect(
          resetIsland.opticsFor(GlassComponentTarget.dropdownMenu).blur,
          22.0,
        );
      },
    );

    test(
      'withGlassIntensity updates all glass parameters for light, medium, and heavy',
      () {
        const base = LedgerPreferences();

        final light = base.withGlassIntensity(GlassIntensity.light);
        expect(light.glassIntensity, GlassIntensity.light);
        expect(light.glassBlurLevel, 4.0);
        expect(light.glassBackgroundOpacity, 0.08);
        expect(light.glassRefractionLevel, 0.5);
        expect(light.glassInteractionStrength, 0.20);
        expect(light.glassSpecularOpacity, 0.60);

        final heavy = base.withGlassIntensity(GlassIntensity.heavy);
        expect(heavy.glassIntensity, GlassIntensity.heavy);
        expect(heavy.glassBlurLevel, 16.0);
        expect(heavy.glassBackgroundOpacity, 0.28);
        expect(heavy.glassRefractionLevel, 1.0);
        expect(heavy.glassInteractionStrength, 0.50);
        expect(heavy.glassSpecularOpacity, 1.0);

        final medium = heavy.withGlassIntensity(GlassIntensity.medium);
        expect(medium.glassIntensity, GlassIntensity.medium);
        expect(medium.glassBlurLevel, 9.0);
        expect(medium.glassBackgroundOpacity, 0.15);
        expect(medium.glassRefractionLevel, 1.0);
        expect(medium.glassInteractionStrength, 0.35);
        expect(medium.glassSpecularOpacity, 1.0);
      },
    );

    test(
      'LedgerCodec round-trips glassIntensity, glassFinish, and per-component optics',
      () {
        final initial = emptyLedgerState().copyWith(
          preferences: const LedgerPreferences()
              .withGlassFinish(AppGlassFinish.regular)
              .withGlassIntensity(GlassIntensity.heavy)
              .withComponentOptics(
                GlassComponentTarget.islandBar,
                blur: 8.5,
                backgroundOpacity: 0.12,
              )
              .withComponentOptics(
                GlassComponentTarget.fab,
                finish: AppGlassFinish.clear,
                blur: 0.0,
              ),
        );
        final json = encodeLedgerState(initial);
        final decoded = decodeLedgerState(json);

        expect(decoded.preferences.glassIntensity, GlassIntensity.heavy);
        expect(decoded.preferences.glassFinish, AppGlassFinish.regular);
        expect(
          decoded.preferences.opticsFor(GlassComponentTarget.islandBar).blur,
          8.5,
        );
        expect(
          decoded.preferences
              .opticsFor(GlassComponentTarget.islandBar)
              .backgroundOpacity,
          0.12,
        );
        expect(
          decoded.preferences.opticsFor(GlassComponentTarget.fab).finish,
          AppGlassFinish.clear,
        );
        expect(
          decoded.preferences.opticsFor(GlassComponentTarget.fab).blur,
          0.0,
        );
      },
    );

    test(
      'LedgerCodec falls back to deduced intensity on legacy JSON without glassIntensity',
      () {
        final json = {
          'version': currentLedgerStateVersion,
          'accounts': <Object?>[],
          'categories': <Object?>[],
          'transactions': <Object?>[],
          'preferences': {'baseCurrency': 'USD', 'glassBlurLevel': 4.0},
        };
        final decoded = decodeLedgerState(jsonEncode(json));
        expect(decoded.preferences.glassIntensity, GlassIntensity.light);
      },
    );
  });

  group('Settings screen glass appearance UI', () {
    testWidgets(
      'shows glass effect tile and navigates to optics customization screen with per-component selector and no frosted',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: authenticatedSampleOverrides(prefs: prefs),
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: const SettingsScreen(),
              theme: ThemeData(
                useMaterial3: true,
                splashFactory: NoSplash.splashFactory,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Sliders for individual properties must NOT exist on main settings screen
        expect(find.text('Blur Radius'), findsNothing);
        expect(find.text('Background Opacity'), findsNothing);
        expect(find.text('Refraction Strength'), findsNothing);
        expect(find.text('Rim Sheen / Specular'), findsNothing);

        // Scroll until the Glass appearance section is visible
        await tester.scrollUntilVisible(
          find.text('Glass effect'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        // Section and tile should exist
        expect(find.text('Glass appearance'), findsOneWidget);
        expect(find.text('Glass effect'), findsOneWidget);
        expect(find.textContaining('Clear'), findsOneWidget);

        // Tap to open glass effect options and live preview screen
        await tester.tap(find.text('Glass effect'));
        await tester.pumpAndSettle();

        // Component selector items should be present
        expect(find.text('Island Bar'), findsWidgets);
        expect(find.text('FAB'), findsOneWidget);
        expect(find.text('Dropdowns'), findsOneWidget);
        expect(find.text('Toolbars'), findsOneWidget);
        expect(find.text('Surfaces'), findsOneWidget);

        // Finish options: Clear and Regular should be present, but Frosted must be REMOVED
        expect(find.text('Clear'), findsWidgets);
        expect(find.text('Regular'), findsWidgets);
        expect(find.text('Frosted'), findsNothing);

        // Optics customization options should be present
        expect(find.text('Blur Radius'), findsOneWidget);
        expect(find.text('Background Opacity'), findsOneWidget);
        expect(find.text('Refraction Strength'), findsOneWidget);
        expect(find.text('Rim Sheen / Specular'), findsOneWidget);

        // Select 'Regular' finish for the current target (Island Bar)
        await tester.tap(find.text('Regular').first);
        await tester.pumpAndSettle();
        expect(
          container
              .read(ledgerProvider)
              .preferences
              .opticsFor(GlassComponentTarget.islandBar)
              .finish,
          AppGlassFinish.regular,
        );
        final badge = tester.widget<Text>(find.text('Recommended'));
        final badgeContainer = tester.widget<Container>(
          find
              .ancestor(
                of: find.text('Recommended'),
                matching: find.byType(Container),
              )
              .first,
        );
        final background = (badgeContainer.decoration! as BoxDecoration).color!;
        final foreground = badge.style!.color!;
        final lighter =
            foreground.computeLuminance() > background.computeLuminance()
            ? foreground
            : background;
        final darker = lighter == foreground ? background : foreground;
        expect(
          (lighter.computeLuminance() + 0.05) /
              (darker.computeLuminance() + 0.05),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          container
              .read(ledgerProvider)
              .preferences
              .opticsFor(GlassComponentTarget.islandBar)
              .blur,
          14.0,
        );

        // Switch to FAB component
        await tester.tap(find.text('FAB'));
        await tester.pumpAndSettle();

        // Finish options still present, header updated
        expect(find.text('Action Button (FAB) Finish'), findsOneWidget);
        expect(
          find.text('Action Button (FAB) Optics Customization'),
          findsOneWidget,
        );

        // Select Clear finish for FAB
        await tester.tap(find.text('Clear').first);
        await tester.pumpAndSettle();
        expect(
          container
              .read(ledgerProvider)
              .preferences
              .opticsFor(GlassComponentTarget.fab)
              .finish,
          AppGlassFinish.clear,
        );

        // Allow auto-backup debounce timer to finish
        await tester.pump(const Duration(milliseconds: 600));
      },
    );
  });
}
