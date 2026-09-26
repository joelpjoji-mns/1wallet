import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/routing/app_router.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

import 'fixtures/sample_ledger.dart';
import 'test_harness.dart';

/// Regression coverage for the Cards screen's "Add" action: it used to push
/// a generic `/account/new` with no type hint, forcing the user to manually
/// change the type away from the "Bank" default. It should now jump
/// straight into a pre-selected "Credit Card" type.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'Cards screen "Add" preselects the Credit Card account type',
    (tester) async {
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
      router.go('/cards');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      expect(find.text('New account'), findsOneWidget);
      expect(find.text('Credit Card'), findsOneWidget);
    },
  );

  testWidgets(
    'the plain Accounts screen "Add account" still defaults to Bank (no '
    'type hint)',
    (tester) async {
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
      router.go('/account/new');
      await tester.pumpAndSettle();

      expect(find.text('New account'), findsOneWidget);
      expect(find.text('Bank'), findsOneWidget);
      expect(find.text('Credit Card'), findsNothing);
    },
  );
}
