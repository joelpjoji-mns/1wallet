import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/features/home/home_widgets.dart';

import 'test_harness.dart';

/// Covers the currency calculator's controller lifecycle and conversion math,
/// including the zero/no-rate edge case and the currency add/remove churn
/// that drives its internal TextEditingController map (guards against the
/// disposed-controller crash where a deferred post-frame callback could
/// reference a currency whose controller had already been removed).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows empty state when no extra currencies are enabled', (
    tester,
  ) async {
    final state = _ledger(enabledCurrencies: const ['INR']);

    await tester.pumpWidget(_wrap(state));
    await tester.pumpAndSettle();

    expect(find.text('No currencies enabled'), findsOneWidget);
  });

  testWidgets(
    'auto-converts the seeded default currency and flags currencies with '
    'no usable rate',
    (tester) async {
      final state = _ledger(
        enabledCurrencies: const ['INR', 'GBP', 'JPY'],
        exchangeRates: [
          ExchangeRateRecord(
            base: 'GBP',
            quote: 'INR',
            rate: 100.0,
            asOfDate: DateTime(2026, 1, 1),
          ),
          ExchangeRateRecord(
            base: 'JPY',
            quote: 'INR',
            rate: 0.0, // Zero/invalid rate: JPY must be treated as "no rate".
            asOfDate: DateTime(2026, 1, 1),
          ),
        ],
      );

      await tester.pumpWidget(_wrap(state));
      await tester.pumpAndSettle();

      // GBP (alphabetically first enabled currency) is seeded with 1 and
      // auto-converted into INR (100) once the frame settles.
      expect(find.text('100'), findsOneWidget);
      // JPY has no positive rate, so its field (and its matching hint) must
      // show the fallback text.
      expect(find.text('No rate'), findsWidgets);

      // Typing into the GBP field re-propagates the conversion to INR.
      await tester.enterText(find.byType(TextField).at(1), '2');
      await tester.pumpAndSettle();

      expect(find.text('200'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'removing then re-adding a currency does not crash and disposes '
    'stale controllers',
    (tester) async {
      var state = _ledger(enabledCurrencies: const ['INR', 'USD', 'EUR']);

      await tester.pumpWidget(_wrap(state));
      await tester.pumpAndSettle();
      expect(find.textContaining('USD'), findsOneWidget);
      expect(find.textContaining('EUR'), findsOneWidget);

      // Disable USD - its controller must be disposed without throwing, and
      // the deferred post-frame recalculation must not touch it either.
      state = _ledger(enabledCurrencies: const ['INR', 'EUR']);
      await tester.pumpWidget(_wrap(state));
      await tester.pumpAndSettle();
      expect(find.textContaining('USD'), findsNothing);
      expect(find.textContaining('EUR'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Re-enable USD and disable EUR in the same step to exercise both
      // controller creation and disposal together.
      state = _ledger(enabledCurrencies: const ['INR', 'USD']);
      await tester.pumpWidget(_wrap(state));
      await tester.pumpAndSettle();
      expect(find.textContaining('USD'), findsOneWidget);
      expect(find.textContaining('EUR'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _wrap(LedgerState state) {
  return ProviderScope(
    overrides: authenticatedSampleOverrides(ledger: state),
    child: MaterialApp(
      home: Scaffold(body: CurrencyValuesHomeWidget(state: state)),
    ),
  );
}

LedgerState _ledger({
  required List<String> enabledCurrencies,
  List<ExchangeRateRecord> exchangeRates = const [],
}) {
  return LedgerState(
    version: currentLedgerStateVersion,
    userId: 'test-user',
    preferences: LedgerPreferences(
      baseCurrency: 'INR',
      displayCurrency: 'INR',
      enabledCurrencies: enabledCurrencies,
    ),
    accounts: const [],
    categories: const [],
    transactions: const [],
    captureCandidates: const [],
    exchangeRates: exchangeRates,
  );
}
