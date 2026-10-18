import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/ledger/ledger_selectors.dart';
import 'package:one_wallet_flutter/src/routing/app_router.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

import 'fixtures/sample_ledger.dart';
import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Cash Account Multi-Currency Data Model & Selectors', () {
    test('Account model effectiveOpeningBalances returns multiple opening balances', () {
      const account = Account(
        id: 'cash_1',
        name: 'Cash Wallet',
        type: 'cash',
        currency: 'USD',
        openingBalance: Money(amountMinor: 10000, currency: 'USD'),
        openingBalances: [
          Money(amountMinor: 10000, currency: 'USD'),
          Money(amountMinor: 5000, currency: 'EUR'),
          Money(amountMinor: 2000, currency: 'GBP'),
        ],
      );

      expect(account.effectiveOpeningBalances.length, 3);
      expect(account.effectiveOpeningBalances[0].currency, 'USD');
      expect(account.effectiveOpeningBalances[0].amountMinor, 10000);
      expect(account.effectiveOpeningBalances[1].currency, 'EUR');
      expect(account.effectiveOpeningBalances[1].amountMinor, 5000);
      expect(account.effectiveOpeningBalances[2].currency, 'GBP');
      expect(account.effectiveOpeningBalances[2].amountMinor, 2000);
    });

    test('Ledger codec correctly serializes and deserializes openingBalances', () {
      const account = Account(
        id: 'cash_1',
        name: 'Cash Wallet',
        type: 'cash',
        currency: 'USD',
        openingBalance: Money(amountMinor: 10000, currency: 'USD'),
        openingBalances: [
          Money(amountMinor: 10000, currency: 'USD'),
          Money(amountMinor: 5000, currency: 'EUR'),
        ],
      );

      final state = sampleLedgerState().copyWith(accounts: [account]);
      final jsonStr = encodeLedgerState(state);
      final decoded = decodeLedgerState(jsonStr);

      final decodedAccount = decoded.accounts.firstWhere((a) => a.id == 'cash_1');
      expect(decodedAccount.openingBalances.length, 2);
      expect(decodedAccount.openingBalances[0].currency, 'USD');
      expect(decodedAccount.openingBalances[0].amountMinor, 10000);
      expect(decodedAccount.openingBalances[1].currency, 'EUR');
      expect(decodedAccount.openingBalances[1].amountMinor, 5000);
    });

    test('cashCurrencyBalancesForAccount and accountBalance track multiple opening balances', () {
      const account = Account(
        id: 'cash_wallet',
        name: 'Physical Wallet',
        type: 'cash',
        currency: 'USD',
        openingBalance: Money(amountMinor: 10000, currency: 'USD'),
        openingBalances: [
          Money(amountMinor: 10000, currency: 'USD'),
          Money(amountMinor: 5000, currency: 'EUR'),
        ],
      );

      final state = sampleLedgerState().copyWith(
        accounts: [account],
        transactions: [],
      );

      final balances = cashCurrencyBalancesForAccount(state, account);
      expect(balances.length, 2);
      expect(balances.any((m) => m.currency == 'USD' && m.amountMinor == 10000), isTrue);
      expect(balances.any((m) => m.currency == 'EUR' && m.amountMinor == 5000), isTrue);

      final totalBalance = accountBalance(state, account);
      expect(totalBalance.currency, 'USD');
      // Converted total should be USD 10000 + converted EUR 5000
      expect(totalBalance.amountMinor, greaterThan(10000));
    });
  });

  group('Cash Account Editor Widget Tests', () {
    testWidgets('shows Multi-currency and Opening balances section when category is cash', (tester) async {
      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(),
      );
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      await container
          .read(ledgerProvider.notifier)
          .restoreLedgerState(sampleLedgerState());

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
            theme: AppTheme.light(),
            darkTheme: AppTheme.amoled(),
          ),
        ),
      );

      // Open new account with initialType=cash
      router.go('/account/new?type=cash');
      await tester.pumpAndSettle();

      // Verify "Cash" is selected and "Multi-currency" is displayed
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Multi-currency'), findsOneWidget);

      // Verify "Opening balances" section is present
      expect(find.text('Opening balances'), findsOneWidget);
      expect(find.text('Add currency'), findsOneWidget);

      // Enter account name
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Account name'),
        'My Travel Cash',
      );

      // Enter amount for the first opening currency (USD)
      final textFields = find.byType(TextFormField);
      // The opening balance input in the cash opening row:
      await tester.enterText(textFields.at(2), '250.00');
      await tester.pumpAndSettle();

      // Tap Save
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pumpAndSettle();

      // Verify account was created with openingBalances
      final accounts = container.read(ledgerProvider).accounts;
      final created = accounts.firstWhere((a) => a.name == 'My Travel Cash');
      expect(created.type, 'cash');
      expect(created.effectiveOpeningBalances.isNotEmpty, isTrue);
      expect(created.effectiveOpeningBalances.first.amountMinor, 25000);
    });

    testWidgets('can add multiple currencies in editor and save all opening balances', (tester) async {
      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(),
      );
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      await container
          .read(ledgerProvider.notifier)
          .restoreLedgerState(sampleLedgerState());

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
            theme: AppTheme.light(),
            darkTheme: AppTheme.amoled(),
          ),
        ),
      );

      router.go('/account/new?type=cash');
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Account name'),
        'Multi Cash Drawer',
      );

      // USD row amount
      var textFields = find.byType(TextFormField);
      await tester.enterText(textFields.at(2), '150.00');
      await tester.pumpAndSettle();

      // Tap "Add currency"
      await tester.tap(find.text('Add currency'));
      await tester.pumpAndSettle();

      // Pick AUD in the currency picker
      await tester.tap(find.textContaining('(AUD)').first);
      await tester.pumpAndSettle();

      // Enter amount for AUD
      textFields = find.byType(TextFormField);
      await tester.enterText(textFields.at(3), '75.50');
      await tester.pumpAndSettle();

      // Tap Save
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pumpAndSettle();

      // Verify account was saved with both opening balances
      final state = container.read(ledgerProvider);
      final created = state.accounts.firstWhere((a) => a.name == 'Multi Cash Drawer');
      expect(created.effectiveOpeningBalances.length, 2);
      expect(
        created.effectiveOpeningBalances.any((m) => m.currency == 'USD' && m.amountMinor == 15000),
        isTrue,
      );
      expect(
        created.effectiveOpeningBalances.any((m) => m.currency == 'AUD' && m.amountMinor == 7550),
        isTrue,
      );

      // Verify cashCurrencyBalancesForAccount reflects both opening currencies
      final cashBalances = cashCurrencyBalancesForAccount(state, created);
      expect(cashBalances.length, 2);
      expect(
        cashBalances.any((m) => m.currency == 'USD' && m.amountMinor == 15000),
        isTrue,
      );
      expect(
        cashBalances.any((m) => m.currency == 'AUD' && m.amountMinor == 7550),
        isTrue,
      );
    });
  });
}
