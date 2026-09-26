// Regression coverage for the "Month starts on day" field in
// settings_components.dart (`SettingsPreferencesSection`).
//
// The field previously had no `inputFormatters`, so it accepted arbitrary
// text (letters, minus signs, arbitrarily long digit runs) even though
// `keyboardType: TextInputType.number` only hints at a numeric soft
// keyboard - it does not filter physical-keyboard, IME, or paste input. The
// fix restricts input to digits only and caps the length at 2 characters
// (the valid range is 1-28), and adds a `Semantics` label so screen readers
// announce the field's purpose and valid range instead of an unlabeled text
// field. This test exercises the digit-only filtering, the length cap, and
// that a still-out-of-range value (e.g. "0") is rejected by the existing
// validation message without being persisted.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/settings/settings_screen.dart';

import 'test_harness.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> pumpSettingsScreen(WidgetTester tester) async {
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
          // NoSplash avoids the ink_sparkle shader, which is intermittently
          // unavailable in the test environment and otherwise makes
          // entering text / tapping flaky.
          theme: ThemeData(
            useMaterial3: true,
            splashFactory: NoSplash.splashFactory,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Finder startDayField() => find.byType(TextField).first;

  testWidgets('non-digit and out-of-range characters are filtered out', (
    tester,
  ) async {
    await pumpSettingsScreen(tester);

    final field = startDayField();
    await tester.enterText(field, 'a1b2c');
    await tester.pumpAndSettle();

    // FilteringTextInputFormatter.digitsOnly strips the letters.
    expect(tester.widget<TextField>(field).controller?.text, '12');
  });

  testWidgets('input is capped at 2 digits (valid range is 1-28)', (
    tester,
  ) async {
    await pumpSettingsScreen(tester);

    final field = startDayField();
    await tester.enterText(field, '12345');
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(field).controller?.text, '12');
  });

  testWidgets(
    'an out-of-range day shows a validation error and is not persisted',
    (tester) async {
      final container = await pumpSettingsScreen(tester);
      final originalStartDay = container
          .read(ledgerProvider)
          .preferences
          .startDayOfMonth;

      final field = startDayField();
      await tester.enterText(field, '0');
      await tester.pumpAndSettle();

      expect(find.text('Must be 1 – 28'), findsOneWidget);
      expect(
        container.read(ledgerProvider).preferences.startDayOfMonth,
        originalStartDay,
        reason: 'An invalid start day must not reach the ledger notifier.',
      );
    },
  );

  testWidgets('a valid day is persisted to the ledger preferences', (
    tester,
  ) async {
    final container = await pumpSettingsScreen(tester);

    final field = startDayField();
    await tester.enterText(field, '15');
    await tester.pumpAndSettle();

    expect(find.text('Must be 1 – 28'), findsNothing);
    expect(container.read(ledgerProvider).preferences.startDayOfMonth, 15);
  });
}
