import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/home/home_async_providers.dart';
import 'package:one_wallet_flutter/src/features/home/home_dashboard_selectors.dart';
import 'package:one_wallet_flutter/src/features/home/home_screen.dart';
import 'package:one_wallet_flutter/src/features/home/home_widgets.dart';

import 'fixtures/sample_ledger.dart';
import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'BalanceTrendHomeWidget updates subtitle and queries account trend when account is selected',
    (tester) async {
      const checkingAccount = Account(
        id: 'checking_1',
        name: 'Checking Account',
        type: 'bank',
        currency: 'USD',
        openingBalance: Money(amountMinor: 500000, currency: 'USD'),
      );
      const savingsAccount = Account(
        id: 'savings_1',
        name: 'High Yield Savings',
        type: 'savings',
        currency: 'USD',
        openingBalance: Money(amountMinor: 1000000, currency: 'USD'),
      );

      final base = sampleLedgerState();
      final state = base.copyWith(
        accounts: [checkingAccount, savingsAccount],
        transactions: const [],
        preferences: base.preferences.copyWith(
          baseCurrency: 'USD',
          displayCurrency: 'USD',
        ),
      );

      final capturedAccountIds = <String?>[];

      final container = ProviderContainer(
        overrides: [
          ...authenticatedSampleOverrides(ledger: state),
          homeBalanceTrendProvider.overrideWith((ref, args) {
            capturedAccountIds.add(args.accountId);
            return balanceTrendForRange(
              state,
              start: args.start,
              end: args.end,
              accountId: args.accountId,
              targetCurrency: args.targetCurrency,
            );
          }),
          homeBalanceFutureTrendProvider.overrideWith((ref, args) {
            return balanceFutureTrendForRange(
              state,
              start: args.start,
              end: args.end,
              accountId: args.accountId,
              targetCurrency: args.targetCurrency,
            );
          }),
        ],
      );
      addTearDown(container.dispose);
      await container.read(ledgerProvider.notifier).restoreLedgerState(state);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: BalanceTrendHomeWidget(state: state)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially no account is selected
      expect(capturedAccountIds.last, isNull);
      expect(find.textContaining('Checking Account ·'), findsNothing);

      // Select Checking Account
      container.read(homeSelectedAccountProvider.notifier).state = 'checking_1';
      await tester.pumpAndSettle();

      expect(capturedAccountIds.last, 'checking_1');
      expect(find.textContaining('Checking Account ·'), findsOneWidget);

      // Select Savings Account
      container.read(homeSelectedAccountProvider.notifier).state = 'savings_1';
      await tester.pumpAndSettle();

      expect(capturedAccountIds.last, 'savings_1');
      expect(find.textContaining('High Yield Savings ·'), findsOneWidget);
      expect(find.textContaining('Checking Account ·'), findsNothing);

      // Unselect account
      container.read(homeSelectedAccountProvider.notifier).state = null;
      await tester.pumpAndSettle();

      expect(capturedAccountIds.last, isNull);
      expect(find.textContaining('High Yield Savings ·'), findsNothing);
      expect(find.textContaining('Checking Account ·'), findsNothing);
    },
  );
}
