import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/transactions/add_record_screen.dart';
import 'package:one_wallet_flutter/src/features/transactions/add_record_widgets.dart';
import 'package:one_wallet_flutter/src/routing/app_router.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

import 'fixtures/sample_ledger.dart';
import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('transaction types remain selectable with large text', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SizedBox(
              width: 320,
              child: AddRecordTypeTabs(
                value: 'expense',
                onChanged: (value) => selected = value,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(ChoiceChip), findsNWidgets(3));
    await tester.tap(find.text('Transfer'));
    expect(selected, 'transfer');
    expect(tester.takeException(), isNull);
  });

  testWidgets('account and category selectors reflow for large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var accountTapped = false;
    var categoryTapped = false;
    final state = sampleLedgerState();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: AddRecordSelectorGrid(
            state: state,
            sourceAccount: state.accounts.first,
            counterAccount: null,
            category: state.categories.first,
            type: 'expense',
            onSelectAccount: () => accountTapped = true,
            onSelectCounter: () {},
            onSelectCategory: () => categoryTapped = true,
          ),
        ),
      ),
    );
    final selectors = find.byType(AddRecordSelectorBox);
    expect(selectors, findsNWidgets(2));
    final first = tester.getRect(selectors.first);
    final second = tester.getRect(selectors.last);
    expect(second.top, greaterThanOrEqualTo(first.bottom));
    expect(second.left, first.left);
    for (final label in ['Account', 'Category']) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(
        paragraph.size.width,
        greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity)),
      );
    }
    await tester.tap(selectors.first);
    await tester.tap(selectors.last);
    expect(accountTapped, isTrue);
    expect(categoryTapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing add-record route parameters opens the intended draft', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(),
    );
    addTearDown(container.dispose);
    await container
        .read(ledgerProvider.notifier)
        .restoreLedgerState(sampleLedgerState());
    final router = container.read(appRouterProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
        ),
      ),
    );

    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    router.go('/add');
    await settle();
    expect(
      tester.widget<AddRecordTypeTabs>(find.byType(AddRecordTypeTabs)).value,
      'expense',
    );
    router.go(
      '/add?type=transfer&accountId=acc-bank&counterAccountId=acc-card',
    );
    await settle();
    expect(
      tester.widget<AddRecordTypeTabs>(find.byType(AddRecordTypeTabs)).value,
      'transfer',
    );
    final grid = tester.widget<AddRecordSelectorGrid>(
      find.byType(AddRecordSelectorGrid),
    );
    expect(grid.sourceAccount?.id, 'acc-bank');
    expect(grid.counterAccount?.id, 'acc-card');

    await tester.tap(find.text('1'));
    await settle();
    expect(
      tester.widget<Text>(find.byKey(const Key('addRecordAmountDisplay'))).data,
      '-1',
    );
    router.go(
      '/add?type=transfer&accountId=acc-bank&counterAccountId=acc-card&tab=1',
    );
    await settle();
    expect(
      DefaultTabController.of(
        tester.element(find.byType(AddRecordTypeTabs)),
      ).index,
      1,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('addRecordAmountDisplay'))).data,
      '-1',
    );
    expect(
      tester
          .widget<AddRecordSelectorGrid>(find.byType(AddRecordSelectorGrid))
          .sourceAccount
          ?.id,
      'acc-bank',
    );

    router.go('/add?transactionId=tx-salary');
    await settle();
    expect(
      tester.widget<AddRecordTypeTabs>(find.byType(AddRecordTypeTabs)).value,
      'income',
    );
    expect(find.text('Edit record'), findsOneWidget);
    router.go('/add');
    await settle();
    expect(
      tester.widget<AddRecordTypeTabs>(find.byType(AddRecordTypeTabs)).value,
      'expense',
    );
    expect(
      tester
          .widget<AddRecordSelectorGrid>(find.byType(AddRecordSelectorGrid))
          .sourceAccount,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('calculator backspace has a usable accessible label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    String? pressed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddRecordCalculatorPad(
            type: 'expense',
            onKey: (key) => pressed = key,
          ),
        ),
      ),
    );
    final backspace = find.bySemanticsLabel('Backspace');
    expect(backspace, findsOneWidget);
    await tester.tap(backspace);
    expect(pressed, '⌫');
    semantics.dispose();
  });

  testWidgets('compact large-text entry scrolls to the keypad and notes', (
    tester,
  ) async {
    final font = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await font.load();
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(),
    );
    addTearDown(container.dispose);
    await container
        .read(ledgerProvider.notifier)
        .restoreLedgerState(sampleLedgerState());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AddRecordScreen(initialAccountId: 'acc-cash'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Finder key(String label) => find.byWidgetPredicate(
      (widget) => widget is AddRecordCalcKey && widget.label == label,
    );

    await tester.scrollUntilVisible(
      key('1'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(key('1')).height, greaterThanOrEqualTo(48));
    await tester.tap(key('1'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('addRecordAmountDisplay'))).data,
      '-1',
    );

    await tester.scrollUntilVisible(
      key('+/-'),
      -120,
      scrollable: find.byType(Scrollable).first,
    );
    final signLabel = find.descendant(
      of: key('+/-'),
      matching: find.text('+/-'),
    );
    final paragraph = tester.renderObject<RenderParagraph>(signLabel);
    expect(
      paragraph.getTransformTo(null).getMaxScaleOnAxis(),
      greaterThanOrEqualTo(0.5),
    );

    await tester.ensureVisible(find.text('Details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();

    final notes = find.byWidgetPredicate(
      (widget) =>
          widget is AppGlassTextField && widget.decoration.labelText == 'Notes',
    );
    await tester.scrollUntilVisible(
      notes,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    final editable = find.descendant(
      of: notes,
      matching: find.byType(EditableText),
    );
    await tester.showKeyboard(editable);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pumpAndSettle();
    await tester.ensureVisible(notes);
    await tester.pumpAndSettle();
    expect(tester.getRect(notes).bottom, lessThanOrEqualTo(328));

    final paymentMethod = find.byWidgetPredicate(
      (widget) =>
          widget is AppGlassTextField &&
          widget.decoration.labelText == 'Payment method',
    );
    final detailsScroll = find.descendant(
      of: find.byType(TabBarView),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable &&
            axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
      ),
    );
    await tester.scrollUntilVisible(
      paymentMethod,
      120,
      scrollable: detailsScroll.first,
    );
    await tester.showKeyboard(
      find.descendant(of: paymentMethod, matching: find.byType(EditableText)),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(paymentMethod);
    await tester.pumpAndSettle();
    expect(tester.getRect(paymentMethod).bottom, lessThanOrEqualTo(328));
    expect(tester.takeException(), isNull);
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
    await container
        .read(ledgerProvider.notifier)
        .restoreLedgerState(sampleLedgerState());

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.amoled(),
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
    expect(find.text('Choose'), findsOneWidget);

    await tester.tap(find.text('1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.check_rounded).first);
    await tester.pumpAndSettle();
    expect(container.read(ledgerProvider).transactions.length, beforeCount);
    expect(find.text('Choose a category.'), findsOneWidget);

    await tester.tap(find.text('Choose'));
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
          darkTheme: AppTheme.amoled(),
        ),
      ),
    );
    // Seed state directly rather than relying on the controller's own
    // startup load, which pipes the restored ledger through a background
    // isolate (foundation.compute) that flutter_test can't reliably
    // resolve before the first navigation below.
    await container
        .read(ledgerProvider.notifier)
        .restoreLedgerState(sampleLedgerState());
    await tester.pumpAndSettle();
    router.go('/add?transactionId=tx-salary');
    await tester.pumpAndSettle();

    expect(find.text('Edit record'), findsOneWidget);
    // The backspace key renders as an icon, not literal text.
    await tester.tap(find.byIcon(Icons.backspace_rounded).last);
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
          darkTheme: AppTheme.amoled(),
        ),
      ),
    );
    // Seed state directly rather than relying on the controller's own
    // startup load, which pipes the restored ledger through a background
    // isolate (foundation.compute) that flutter_test can't reliably
    // resolve before the first navigation below.
    await container
        .read(ledgerProvider.notifier)
        .restoreLedgerState(sampleLedgerState());
    await tester.pumpAndSettle();
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
          darkTheme: AppTheme.amoled(),
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
