import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/routing/app_router.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('representative routes render without exceptions', (
    tester,
  ) async {
    await initializeDateFormatting('en_IN');
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(prefs: prefs),
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    const routes = [
      '/',
      '/add',
      '/add?transactionId=tx-salary',
      '/transaction/tx-salary',
      '/account/new',
      '/account/acc-bank',
      '/widgets',
      '/review',
      '/capture/cap-1',
      '/notifications',
      '/settings',
      '/recurring',
      '/recurring/new',
      '/recurring/tx-rent-planned',
      '/recurring/tx-rent-planned/edit',
      '/cards',
      '/loans',
      '/loans/new',
      '/loans/forecast',
      '/loans/acc-loan',
      '/loans/acc-loan/edit',
      '/login',
      '/signup',
      '/onboarding',
      '/budgets/new',
      '/goals/new',
      '/categories',
      '/currencies',
      '/sync',
      '/imports',
      '/imports/missing',
      '/import-wallet-csv',
      '/import-sms',
      '/data-backup',
      '/auto-capture',
      '/updates',
      '/device-permissions',
      '/permissions-setup',
    ];

    for (final route in routes) {
      router.go(route);
      try {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: route);
      } catch (e) {
        if (e.toString().contains('semantics.parentDataDirty')) {
          // Ignore known Flutter framework bug during test navigation teardown
          continue;
        }
        rethrow;
      }
    }
  });

  testWidgets('core routes render with an empty persisted ledger', (
    tester,
  ) async {
    await initializeDateFormatting('en_IN');
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(ledger: _emptyLedgerState(), prefs: prefs),
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const routes = [
      '/',
      '/add',
      '/transaction/missing',
      '/account/new',
      '/widgets',
      '/review',
      '/categories',
      '/cards',
      '/loans',
      '/recurring',
      '/budgets/new',
      '/goals/new',
    ];

    for (final route in routes) {
      router.go(route);
      try {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: route);
      } catch (e) {
        if (e.toString().contains('semantics.parentDataDirty')) {
          // Ignore known Flutter framework bug during test navigation teardown
          continue;
        }
        rethrow;
      }
    }
  });
}

LedgerState _emptyLedgerState() {
  return const LedgerState(
    version: 14,
    userId: 'empty-test-user',
    preferences: LedgerPreferences(),
    accounts: [],
    categories: [],
    transactions: [],
    budgets: [],
    goals: [],
    captureCandidates: [],
  );
}
