import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1455/g1455.dart' as g1455;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/features/home/home_screen.dart';
import 'package:one_wallet_flutter/src/features/home/home_widgets.dart';

import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Tapping an account tile triggers selection and g1455 glass ripple surface', (
    tester,
  ) async {
    const accountColor = Color(0xFF315DA8);
    const state = LedgerState(
      version: currentLedgerStateVersion,
      userId: 'test-user',
      preferences: LedgerPreferences(),
      accounts: [
        Account(
          id: 'acc-1',
          name: 'Ripple Checking',
          type: 'bank',
          currency: 'INR',
          openingBalance: Money(amountMinor: 50000, currency: 'INR'),
          color: accountColor,
          sortOrder: 1,
        ),
      ],
      categories: [],
      transactions: [],
      captureCandidates: [],
    );

    late final ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: authenticatedSampleOverrides(ledger: state),
        child: Consumer(
          builder: (context, ref, child) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              home: Scaffold(
                body: AccountGridHomeWidget(
                  state: state,
                  onTabSelected: (int index) {},
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial state: not selected
    expect(container.read(homeSelectedAccountProvider), isNull);

    // GlassSurface with g1455.GlassRipple must wrap the all accounts card
    final glassSurfaceFinder = find.byWidgetPredicate((w) {
      if (w is! g1455.GlassSurface) return false;
      return w.ripple != null;
    });
    expect(glassSurfaceFinder, findsOneWidget);

    // Tap the tile
    final tileFinder = find.text('Ripple Checking');
    expect(tileFinder, findsOneWidget);

    await tester.tap(tileFinder);
    await tester.pumpAndSettle();

    // Selection must be updated to acc-1
    expect(container.read(homeSelectedAccountProvider), 'acc-1');

    // Tap the tile again to unselect
    await tester.tap(tileFinder);
    await tester.pumpAndSettle();

    // Selection must be cleared back to null (unselected)
    expect(container.read(homeSelectedAccountProvider), isNull);
  });
}
