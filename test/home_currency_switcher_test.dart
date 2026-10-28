import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/home/home_components.dart';
import 'package:one_wallet_flutter/src/features/home/home_screen.dart';
import 'package:one_wallet_flutter/src/features/home/home_widgets.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

import 'test_harness.dart';

Future<void> _pumpBounded(
  WidgetTester tester, {
  int times = 5,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(step);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'BalanceHomeWidget renders currency dropdown switcher when multiple currencies are available',
    (tester) async {
      final now = DateTime.now();
      final usdAccount = Account(
        id: 'acc-usd',
        name: 'Chase Checking',
        type: 'bank',
        currency: 'USD',
        accountLast4: '1111',
        openingBalance: const Money(amountMinor: 100000, currency: 'USD'),
      );
      final inrAccount = Account(
        id: 'acc-inr',
        name: 'HDFC Savings',
        type: 'bank',
        currency: 'INR',
        accountLast4: '2222',
        openingBalance: const Money(amountMinor: 5000000, currency: 'INR'),
      );

      final state = emptyLedgerState().copyWith(
        accounts: [usdAccount, inrAccount],
        preferences: const LedgerPreferences(
          baseCurrency: 'USD',
          displayCurrency: 'USD',
          enabledCurrencies: ['USD', 'INR'],
        ),
      );

      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(ledger: state, prefs: prefs),
      );
      addTearDown(container.dispose);
      await container.read(ledgerProvider.notifier).restoreLedgerState(state);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light().copyWith(
              splashFactory: NoSplash.splashFactory,
            ),
            home: Scaffold(
              body: BalanceHomeWidget(
                state: state,
                onTabSelected: (_) {},
              ),
            ),
          ),
        ),
      );

      await _pumpBounded(tester);

      // Verify the currency dropdown pill is present with 'Display currency' semantic label
      final currencyDropdown = find.byWidgetPredicate(
        (widget) =>
            widget is GlassDropdownPill<String> &&
            widget.semanticLabel == 'Display currency',
      );
      expect(currencyDropdown, findsOneWidget);

      // Verify currently displaying USD
      expect(
        find.descendant(of: currencyDropdown, matching: find.text('USD')),
        findsOneWidget,
      );

      // When an account is selected, currency is pinned to that account's currency as HomeBalancePill
      container.read(homeSelectedAccountProvider.notifier).state = inrAccount.id;
      await _pumpBounded(tester);

      expect(find.byType(HomeBalancePill), findsOneWidget);
      expect(find.text('INR'), findsWidgets);
    },
  );
}
