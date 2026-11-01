import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

  testWidgets('AccountGridHomeWidget Manage button navigates to /accounts when no account is selected', (tester) async {
    final ledgerState = sampleLedgerState();
    String? navigatedRoute;

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: SingleChildScrollView(
              child: AccountGridHomeWidget(
                state: ledgerState,
                onTabSelected: (_) {},
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/accounts',
          builder: (context, state) {
            navigatedRoute = '/accounts';
            return const Scaffold(body: Text('Accounts Screen'));
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...authenticatedSampleOverrides(ledger: ledgerState),
        ],
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('All accounts'), findsOneWidget);
    final manageButton = find.text('Manage');
    expect(manageButton, findsOneWidget);

    await tester.tap(manageButton);
    await tester.pumpAndSettle();

    expect(navigatedRoute, '/accounts');
    expect(find.text('Accounts Screen'), findsOneWidget);
  });
}
