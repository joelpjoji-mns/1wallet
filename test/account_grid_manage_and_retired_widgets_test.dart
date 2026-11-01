import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/features/home/home_widget_models.dart';
import 'package:one_wallet_flutter/src/features/home/home_widgets.dart';

import 'fixtures/sample_ledger.dart';
import 'test_harness.dart';

void main() {
  test('HomeDashboardWidgetId no longer contains retired widgets', () {
    final storageKeys = HomeDashboardWidgetId.values.map((w) => w.storageKey).toSet();
    expect(storageKeys, isNot(contains('loansTile')));
    expect(storageKeys, isNot(contains('plannedPaymentsTile')));
    expect(storageKeys, isNot(contains('emiTracker')));
    expect(storageKeys, isNot(contains('loanPayoff')));
    expect(storageKeys, isNot(contains('cardDebt')));
    expect(storageKeys, isNot(contains('cardPaymentPlan')));
  });

  testWidgets('AccountGridHomeWidget Manage button selects Accounts tab (index 3)', (tester) async {
    final ledgerState = sampleLedgerState();
    int? selectedTab;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...authenticatedSampleOverrides(ledger: ledgerState),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AccountGridHomeWidget(
                state: ledgerState,
                onTabSelected: (tab) => selectedTab = tab,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('All accounts'), findsOneWidget);
    final manageButton = find.text('Manage');
    expect(manageButton, findsOneWidget);

    await tester.tap(manageButton);
    await tester.pumpAndSettle();

    expect(selectedTab, 3);
  });
}
