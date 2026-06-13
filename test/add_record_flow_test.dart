import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/transactions/add_record_screen.dart';
import 'package:one_wallet_flutter/src/routing/app_router.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

import 'fixtures/sample_ledger.dart';
import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Add Record UI saves a transaction to the ledger', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(),
    );
    addTearDown(container.dispose);
    await container.read(ledgerProvider.notifier).restoreLedgerState(
          sampleLedgerState(),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: const AddRecordScreen(initialAccountId: 'acc-cash'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 20; i++) {
      if (container.read(ledgerProvider).accounts.isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    final beforeCount = container.read(ledgerProvider).transactions.length;
    expect(find.text('Cash Wallet'), findsOneWidget);
    expect(find.text('Choose category'), findsOneWidget);

    await tester.tap(find.text('1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.check_rounded).first);
    await tester.pumpAndSettle();
    expect(container.read(ledgerProvider).transactions.length, beforeCount);
    expect(find.text('Choose a category before saving.'), findsOneWidget);

    await tester.tap(find.text('Choose category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food').last);
    await tester.pumpAndSettle();
    expect(find.text('Choose subcategory'), findsOneWidget);
    await tester.tap(find.text('Groceries').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.check_rounded).first);
    await tester.pumpAndSettle();

    final transactions = container.read(ledgerProvider).transactions;
    expect(transactions.length, beforeCount + 1);
    expect(transactions.first.amount.amountMinor, 100);
    expect(transactions.first.type, 'expense');
    expect(transactions.first.accountId, 'acc-cash');
    expect(transactions.first.categoryId, 'cat-grocery');
  });

  testWidgets('Add Record edit route updates an existing transaction', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(),
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
    router.go('/add?transactionId=tx-salary');
    await tester.pumpAndSettle();

    expect(find.text('Edit record'), findsOneWidget);
    await tester.tap(find.text('⌫').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('9').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.check_rounded).first);
    await tester.pumpAndSettle();

    final transaction = container
        .read(ledgerProvider)
        .transactions
        .firstWhere((item) => item.id == 'tx-salary');
    expect(transaction.amount.amountMinor, 18500900);
  });

  testWidgets('budget and goal forms create persisted entries', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(),
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

    router.go('/budgets/new');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'QA groceries');
    await tester.enterText(find.byType(TextFormField).at(1), '1234');
    await tester.tap(find.byIcon(Icons.check_rounded).first);
    await tester.pumpAndSettle();

    router.go('/goals/new');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'QA trip');
    await tester.enterText(find.byType(TextFormField).at(1), '4321');
    await tester.tap(find.byIcon(Icons.check_rounded).first);
    await tester.pumpAndSettle();

    final state = container.read(ledgerProvider);
    expect(state.budgets.first.name, 'QA groceries');
    expect(state.budgets.first.amount.amountMinor, 123400);
    expect(state.goals.first.name, 'QA trip');
    expect(state.goals.first.target.amountMinor, 432100);
  });

  testWidgets('Transaction Detail delete removes a transaction', (
    tester,
  ) async {
    await initializeDateFormatting('en_IN');
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(),
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
    router.go('/transaction/tx-salary');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(
      container
          .read(ledgerProvider)
          .transactions
          .any((item) => item.id == 'tx-salary'),
      isFalse,
    );
  });

  testWidgets('Categories screen creates a category', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(),
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
    router.go('/categories');
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'QA category UI');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      container
          .read(ledgerProvider)
          .categories
          .any((item) => item.name == 'QA category UI'),
      isTrue,
    );
  });
}
