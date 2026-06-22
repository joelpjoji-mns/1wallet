import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/features/home/home_widgets.dart';

import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('All accounts tiles use account color and contrast foreground', (
    tester,
  ) async {
    const accountColor = Color(0xFF315DA8);
    final state = _ledger(
      accounts: const [
        Account(
          id: 'dark-account',
          name: 'Dark Account Tile',
          type: 'bank',
          currency: 'INR',
          openingBalance: Money(amountMinor: 10000, currency: 'INR'),
          color: accountColor,
          sortOrder: 1,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: authenticatedSampleOverrides(ledger: state),
        child: MaterialApp(
          home: Scaffold(
            body: AccountGridHomeWidget(state: state, onTabSelected: (int index) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final darkName = tester.widget<Text>(find.text('Dark Account Tile'));
    final accountTiles = find.byWidgetPredicate((widget) {
      if (widget is! Container) return false;
      final decoration = widget.decoration;
      return decoration is BoxDecoration && decoration.color == accountColor;
    });

    expect(accountTiles, findsWidgets);
    expect(darkName.style?.color, Colors.white);
  });

  testWidgets('All accounts tiles use dark text on light account color', (
    tester,
  ) async {
    const accountColor = Color(0xFFFFE082);
    final state = _ledger(
      accounts: const [
        Account(
          id: 'light-account',
          name: 'Light Account Tile',
          type: 'wallet',
          currency: 'INR',
          openingBalance: Money(amountMinor: 20000, currency: 'INR'),
          color: accountColor,
          sortOrder: 1,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: authenticatedSampleOverrides(ledger: state),
        child: MaterialApp(
          home: Scaffold(
            body: AccountGridHomeWidget(state: state, onTabSelected: (int index) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final lightName = tester.widget<Text>(find.text('Light Account Tile'));
    final accountTiles = find.byWidgetPredicate((widget) {
      if (widget is! Container) return false;
      final decoration = widget.decoration;
      return decoration is BoxDecoration && decoration.color == accountColor;
    });

    expect(accountTiles, findsWidgets);
    expect(lightName.style?.color, Colors.black);
  });
}

LedgerState _ledger({required List<Account> accounts}) {
  return LedgerState(
    version: currentLedgerStateVersion,
    userId: 'test-user',
    preferences: const LedgerPreferences(),
    accounts: accounts,
    categories: const [],
    transactions: const [],
    budgets: const [],
    goals: const [],
    captureCandidates: const [],
  );
}
