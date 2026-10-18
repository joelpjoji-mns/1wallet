import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/home/home_async_providers.dart';
import 'package:one_wallet_flutter/src/features/home/home_screen.dart';
import 'package:one_wallet_flutter/src/features/home/home_widgets.dart';
import 'package:one_wallet_flutter/src/ledger/ledger_selectors.dart';

import 'fixtures/sample_ledger.dart';
import 'test_harness.dart';

void main() {
  testWidgets('BalanceHomeWidget animates main net balance number on changes', (
    WidgetTester tester,
  ) async {
    final baseState = sampleLedgerState();
    final state = baseState.copyWith(
      preferences: baseState.preferences.copyWith(
        displayCurrency: 'INR',
      ),
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
            body: BalanceHomeWidget(
              state: state,
              onTabSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The widget should have TweenAnimationBuilder for total net balance, income, and expense (3 total)
    expect(find.byType(TweenAnimationBuilder<double>), findsNWidgets(3));

    final initialTotal = container.read(homeTotalBalanceProvider((
      accountId: null,
      targetCurrency: 'INR',
    )));
    expect(
      find.text(formatMoney(initialTotal, state.preferences.locale)),
      findsOneWidget,
    );

    // Switch selected account to trigger a net balance change
    final account = state.accounts.first;
    container.read(homeSelectedAccountProvider.notifier).state = account.id;

    // Pump frame: animation begins
    await tester.pump();

    final targetTotal = container.read(homeTotalBalanceProvider((
      accountId: account.id,
      targetCurrency: account.currency,
    )));

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
}
