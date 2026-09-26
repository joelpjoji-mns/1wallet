import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/features/home/home_widgets.dart';

import 'test_harness.dart';

/// Regression coverage for a fixed-height overflow in the "All accounts"
/// grid tile: it used to size its content box with a hard `height: 60`,
/// which clips/overflows once accessibility text scaling makes the
/// name/balance/currency rows taller than that. It now uses a `minHeight`
/// constraint so the tile can grow instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'account tiles do not overflow under a large accessibility text scale',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final state = _ledger();

      await tester.pumpWidget(
        ProviderScope(
          overrides: authenticatedSampleOverrides(ledger: state),
          child: MaterialApp(
            // Simulate a large system accessibility text-scale setting
            // (well beyond typical "Largest" presets) applied app-wide.
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(3.0)),
              child: child!,
            ),
            home: Scaffold(
              body: AccountGridHomeWidget(
                state: state,
                onTabSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Foreign Wallet'), findsOneWidget);
      expect(find.text('Cash Purse'), findsOneWidget);
    },
  );
}

LedgerState _ledger() {
  return LedgerState(
    version: currentLedgerStateVersion,
    userId: 'test-user',
    preferences: const LedgerPreferences(baseCurrency: 'INR'),
    accounts: const [
      Account(
        id: 'foreign',
        name: 'Foreign Wallet',
        type: 'bank',
        currency: 'USD',
        openingBalance: Money(amountMinor: 543210, currency: 'USD'),
        showOnHome: true,
        sortOrder: 1,
      ),
      Account(
        id: 'cash',
        name: 'Cash Purse',
        type: 'cash',
        currency: 'INR',
        openingBalance: Money(amountMinor: 250000, currency: 'INR'),
        showOnHome: true,
        sortOrder: 2,
      ),
    ],
    categories: const [],
    transactions: const [],
    captureCandidates: const [],
  );
}
