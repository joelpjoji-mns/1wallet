import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/design/tokens.dart';
import 'package:one_wallet_flutter/src/features/home/home_async_providers.dart';
import 'package:one_wallet_flutter/src/features/home/home_screen.dart';
import 'package:one_wallet_flutter/src/features/home/home_widgets.dart';
import 'package:one_wallet_flutter/src/ledger/ledger_selectors.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

import 'fixtures/sample_ledger.dart';
import 'test_harness.dart';

void main() {
  testWidgets('balance corner controls stay on one line at phone widths', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    final base = sampleLedgerState();
    final state = base.copyWith(
      preferences: base.preferences.copyWith(
        homeWidgetFilters: {'balanceHero': 'custom:2026-01-01..2026-11-28'},
      ),
    );
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(ledger: state),
    );
    addTearDown(container.dispose);
    await container.read(ledgerProvider.notifier).restoreLedgerState(state);
    for (final width in [320.0, 360.0, 390.0, 800.0]) {
      tester.view.physicalSize = Size(width, 844);
      for (final theme in [AppTheme.light(), AppTheme.amoled()]) {
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: theme,
                home: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: BalanceHomeWidget(
                      state: state,
                      onTabSelected: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final pills = find.byType(GlassDropdownPill<String>);
          expect(pills, findsNWidgets(2));
          final date = tester.getRect(pills.first);
          final currency = tester.getRect(pills.last);
          expect(date.center.dy, closeTo(currency.center.dy, 0.1));
          expect(date.right, lessThan(currency.left));
          expect(currency.right, lessThanOrEqualTo(width));
          expect(tester.takeException(), isNull);
        }
      }
    }
  });

  testWidgets('BalanceHomeWidget animates main net balance number on changes', (
    WidgetTester tester,
  ) async {
    final baseState = sampleLedgerState();
    final state = baseState.copyWith(
      preferences: baseState.preferences.copyWith(displayCurrency: 'INR'),
    );
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(ledger: state),
    );
    addTearDown(container.dispose);
    await container.read(ledgerProvider.notifier).restoreLedgerState(state);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: BalanceHomeWidget(state: state, onTabSelected: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The widget should have TweenAnimationBuilder for total net balance, income, and expense (3 total)
    expect(find.byType(TweenAnimationBuilder<double>), findsNWidgets(3));

    final initialTotal = container.read(
      homeTotalBalanceProvider((accountId: null, targetCurrency: 'INR')),
    );
    expect(
      find.text(formatMoney(initialTotal, state.preferences.locale)),
      findsOneWidget,
    );

    // Switch selected account to trigger a net balance change
    final account = state.accounts.first;
    container.read(homeSelectedAccountProvider.notifier).state = account.id;

    // Pump frame: animation begins
    await tester.pump();

    final targetTotal = container.read(
      homeTotalBalanceProvider((
        accountId: account.id,
        targetCurrency: account.currency,
      )),
    );

    // Mid-animation frame (before 600ms)
    await tester.pump(const Duration(milliseconds: 300));
    // After 600ms completes, the final target balance is rendered
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(
      find.text(formatMoney(targetTotal, state.preferences.locale)),
      findsOneWidget,
    );
  });

  testWidgets(
    'BalanceHomeWidget animates number when switching currency and updates symbol',
    (WidgetTester tester) async {
      final baseState = sampleLedgerState();
      const accountEur = Account(
        id: 'acc-eur',
        name: 'Euro Savings',
        type: 'bank',
        currency: 'EUR',
        openingBalance: Money(amountMinor: 500000, currency: 'EUR'),
        color: AppColors.secondary,
        sortOrder: 10,
      );
      final state = baseState.copyWith(
        accounts: [...baseState.accounts, accountEur],
        preferences: baseState.preferences.copyWith(displayCurrency: 'INR'),
      );
      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(ledger: state),
      );
      addTearDown(container.dispose);
      await container.read(ledgerProvider.notifier).restoreLedgerState(state);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: BalanceHomeWidget(state: state, onTabSelected: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initialTotal = container.read(
        homeTotalBalanceProvider((accountId: null, targetCurrency: 'INR')),
      );
      expect(
        find.text(formatMoney(initialTotal, state.preferences.locale)),
        findsOneWidget,
      );

      // Switch selected account to EUR account (triggers currency change from INR to EUR)
      container.read(homeSelectedAccountProvider.notifier).state =
          accountEur.id;

      // Pump frame: animation starts
      await tester.pump();

      final targetEurTotal = container.read(
        homeTotalBalanceProvider((
          accountId: accountEur.id,
          targetCurrency: 'EUR',
        )),
      );

      // Mid-animation frame at 300ms: has not yet reached targetEurTotal
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text(formatMoney(targetEurTotal, state.preferences.locale)),
        findsNothing,
      );
      // But the symbol has immediately switched to EUR
      expect(find.textContaining('€'), findsWidgets);

      // Settle animation at 600ms: targetEurTotal is reached
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(
        find.text(formatMoney(targetEurTotal, state.preferences.locale)),
        findsOneWidget,
      );
    },
  );
}
