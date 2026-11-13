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

  group('Glass intensity preferences model & codec', () {
    test('default preferences have medium intensity and standard values', () {
      const prefs = LedgerPreferences();
      expect(prefs.glassIntensity, GlassIntensity.medium);
      expect(prefs.glassBlurLevel, 9.0);
      expect(prefs.glassBackgroundOpacity, 0.15);
      expect(prefs.glassRefractionLevel, 1.0);
      expect(prefs.glassInteractionStrength, 0.35);
      expect(prefs.glassSpecularOpacity, 1.0);
    });

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

    test('LedgerCodec round-trips glassIntensity', () {
      final initial = emptyLedgerState().copyWith(
        preferences: const LedgerPreferences().withGlassIntensity(
          GlassIntensity.heavy,
        ),
      );
      final json = encodeLedgerState(initial);
      final decoded = decodeLedgerState(json);

      expect(decoded.preferences.glassIntensity, GlassIntensity.heavy);
      expect(decoded.preferences.glassBlurLevel, 16.0);
      expect(decoded.preferences.glassBackgroundOpacity, 0.28);
    });

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
      'shows one glass option (Light/Medium/Heavy) and no individual property sliders',
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

        // Sliders for individual properties must NOT exist
        expect(find.text('Frosting'), findsNothing);
        expect(find.text('Tint strength'), findsNothing);
        expect(find.text('Refraction'), findsNothing);
        expect(find.text('Bounce'), findsNothing);
        expect(find.text('Highlight'), findsNothing);
        expect(
          find.text(
            'Tune the shared glass surfaces and interactions across the app.',
          ),
          findsNothing,
        );

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
        expect(find.text('Medium'), findsOneWidget);

        // Tap to open picker
        await tester.tap(find.text('Glass effect'));
        await tester.pumpAndSettle();

        // Picker options should be present
        expect(find.text('Light'), findsOneWidget);
        expect(
          find.text('Subtle frosted surface with soft blur and low opacity'),
          findsOneWidget,
        );
        expect(find.text('Medium'), findsWidgets); // title and/or option
        expect(
          find.text('Balanced liquid glass with standard blur and refraction'),
          findsOneWidget,
        );
        expect(find.text('Heavy'), findsOneWidget);
        expect(
          find.text('Strong frosted glass with deeper blur and opacity'),
          findsOneWidget,
        );

        // Select 'Heavy'
        await tester.tap(find.text('Heavy'));
        await tester.pumpAndSettle();

        // Preference should now be Heavy
        expect(
          container.read(ledgerProvider).preferences.glassIntensity,
          GlassIntensity.heavy,
        );
        expect(container.read(ledgerProvider).preferences.glassBlurLevel, 16.0);

        // Screen subtitle should update to Heavy
        expect(find.text('Heavy'), findsOneWidget);
      },
    );
  });
}
