import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/transactions/transactions_components.dart';
import 'package:one_wallet_flutter/src/ledger/ledger_selectors.dart';
import 'package:one_wallet_flutter/src/routing/app_router.dart';
import 'package:one_wallet_flutter/src/startup/startup_state.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart' show AppPanel;
import 'package:one_wallet_flutter/src/widgets/privacy_text.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'test_harness.dart';

/// Regression coverage for the Recurring screen:
/// - "Past recurring" must respect `hideSkippedInHistory` instead of always
///   dropping void (skipped) occurrences regardless of the preference.
/// - The plan amount field must round extra fractional digits instead of
///   truncating them.
/// - Rapid double-tapping "Create scheduled record" must only create one
///   plan.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final font = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await font.load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  LedgerState buildSeed({required bool hideSkipped}) {
    final now = DateTime.now();
    final plan = TransactionRecord(
      id: 'plan-rent',
      type: 'expense',
      status: 'scheduled',
      source: 'recurring',
      accountId: 'acc-1',
      amount: const Money(amountMinor: 32000, currency: 'USD'),
      baseAmount: const Money(amountMinor: 32000, currency: 'USD'),
      occurredAt: now.add(const Duration(days: 4)),
      recurrenceFrequency: 'monthly',
    );
    final skippedInstance = TransactionRecord(
      id: 'tx-skipped-rent',
      type: 'expense',
      status: 'void',
      source: 'recurring',
      accountId: 'acc-1',
      amount: const Money(amountMinor: 32000, currency: 'USD'),
      baseAmount: const Money(amountMinor: 32000, currency: 'USD'),
      occurredAt: now.subtract(const Duration(days: 26)),
      originalTransactionId: 'plan-rent',
      notes: 'SkippedRentMarker',
    );
    return emptyLedgerState().copyWith(
      accounts: [
        const Account(
          id: 'acc-1',
          name: 'Main Checking',
          type: 'bank',
          currency: 'USD',
          openingBalance: Money(amountMinor: 500000, currency: 'USD'),
        ),
      ],
      transactions: [plan, skippedInstance],
      preferences: LedgerPreferences(hideSkippedInHistory: hideSkipped),
    );
  }

  Future<ProviderContainer> pumpPastRecurring(
    WidgetTester tester,
    LedgerState seed,
  ) async {
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(ledger: seed),
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    await container.read(ledgerProvider.notifier).restoreLedgerState(seed);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          theme: AppTheme.light().copyWith(
            splashFactory: NoSplash.splashFactory,
          ),
          darkTheme: AppTheme.amoled().copyWith(
            splashFactory: NoSplash.splashFactory,
          ),
        ),
      ),
    );
    router.go('/recurring/past');
    await tester.pumpAndSettle();
    return container;
  }

  LedgerState paymentSeed() {
    final seed = buildSeed(hideSkipped: false);
    final plan = seed.transactions.first.copyWith(
      occurredAt: DateTime(2099, 1, 1),
      recurrenceLimit: 6,
    );
    return seed.copyWith(
      transactions: [
        plan,
        seed.transactions.last,
        plan.copyWith(
          id: 'paid-first',
          status: 'posted',
          amount: const Money(amountMinor: 24500, currency: 'USD'),
          baseAmount: const Money(amountMinor: 24500, currency: 'USD'),
          occurredAt: DateTime(2026, 1, 1),
          originalTransactionId: plan.id,
        ),
        plan.copyWith(
          id: 'paid-second',
          status: 'cleared',
          amount: const Money(amountMinor: 33000, currency: 'USD'),
          baseAmount: const Money(amountMinor: 33000, currency: 'USD'),
          occurredAt: DateTime(2026, 2, 1),
          originalTransactionId: plan.id,
        ),
      ],
    );
  }

  Future<void> pumpPlanDetails(
    WidgetTester tester,
    LedgerState seed, {
    double scale = 1,
  }) async {
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(ledger: seed),
    );
    addTearDown(container.dispose);
    await container.read(ledgerProvider.notifier).restoreLedgerState(seed);
    final router = container.read(appRouterProvider);
    router.go('/recurring/plan-rent');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: scale == 1 ? AppTheme.light() : AppTheme.amoled(),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('planned summary remains readable at ${scale}x text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final seed = buildSeed(hideSkipped: false);
      final plan = seed.transactions.first.copyWith(
        amount: const Money(amountMinor: 7850000, currency: 'USD'),
        baseAmount: const Money(amountMinor: 7850000, currency: 'USD'),
      );
      final ledger = seed.copyWith(transactions: [plan]);
      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(ledger: ledger),
      );
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      router.go('/recurring');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final text in ['Planned summary', 'INCOME', 'EXPENSE', 'NET']) {
        final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
        expect(paragraph.didExceedMaxLines, isFalse, reason: text);
      }
      final expense = find.byWidgetPredicate(
        (widget) => widget is MiniFlowStat && widget.label == 'EXPENSE',
      );
      final stat = tester.widget<MiniFlowStat>(expense);
      final amount = find.descendant(
        of: expense,
        matching: find.text(stat.value),
      );
      expect(tester.getRect(amount).height, greaterThanOrEqualTo(12 * scale));
      if (scale == 1.0) {
        final net = tester.getRect(find.byKey(const ValueKey('mini-flow-net')));
        final income = tester.getRect(
          find.byKey(const ValueKey('mini-flow-income')),
        );
        final expenseBox = tester.getRect(
          find.byKey(const ValueKey('mini-flow-expense')),
        );
        expect(net.top, income.top);
        expect(income.top, expenseBox.top);
        expect(net.right, lessThan(income.left));
        expect(income.right, lessThan(expenseBox.left));
      }
    });
  }

  test('plan totals use actual posted amounts and exclude unpaid records', () {
    final seed = paymentSeed();
    final plan = seed.transactions.first;
    final state = seed.copyWith(
      transactions: [
        ...seed.transactions,
        plan.copyWith(id: 'unrelated', status: 'posted'),
        for (final status in ['scheduled', 'paused', 'finished'])
          plan.copyWith(
            id: 'unpaid-$status',
            status: status,
            originalTransactionId: plan.id,
          ),
      ],
    );
    final summary = recurringPlanPaymentSummary(state, plan);
    expect(summary.paymentCount, 2);
    expect(summary.totals.single.amountMinor, 57500);
    expect(summary.totals.single.currency, 'USD');
  });

  test('plan totals preserve original currencies without blending amounts', () {
    final seed = paymentSeed();
    final plan = seed.transactions.first;
    final state = seed.copyWith(
      transactions: [
        plan,
        seed.transactions[2].copyWith(
          originalAmount: const Money(amountMinor: 22000, currency: 'EUR'),
        ),
        seed.transactions[3],
      ],
    );
    final summary = recurringPlanPaymentSummary(state, plan);
    expect(summary.paymentCount, 2);
    expect(
      {for (final money in summary.totals) money.currency: money.amountMinor},
      {'EUR': 22000, 'USD': 33000},
    );
    final empty = recurringPlanPaymentSummary(
      seed.copyWith(transactions: [plan]),
      plan,
    );
    expect(empty.paymentCount, 0);
    expect(empty.totals.single.amountMinor, 0);
  });

  testWidgets('finite plan details show total paid and occurrence progress', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final seed = paymentSeed();
    await pumpPlanDetails(tester, seed);

    expect(find.text('Spent so far'), findsOneWidget);
    expect(find.text('\$575.00'), findsOneWidget);
    expect(find.text('2 of 6 payments'), findsOneWidget);
    expect(find.byType(GlassProgressIndicator), findsOneWidget);
    // Totals and payment information share one panel.
    expect(
      tester.getTopLeft(find.text('2 of 6 payments')).dx,
      greaterThan(tester.getTopRight(find.text('\$575.00')).dx),
    );
    final panelFinder = find.byKey(const ValueKey('recurring-payment-summary'));
    final panel = tester.getRect(panelFinder);
    for (final text in ['Spent so far', 'Next payment', 'Account']) {
      expect(
        find.descendant(of: panelFinder, matching: find.text(text)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: panelFinder, matching: find.byType(AppPanel)),
      findsNothing,
    );
    final label = tester.getRect(find.text('Spent so far'));
    final bar = tester.getRect(find.byType(GlassProgressIndicator));
    // The count hugs the panel's right edge (12dp padding), no inner gap.
    expect(
      panel.right - tester.getRect(find.text('2 of 6 payments')).right,
      closeTo(12, 1),
    );
    expect(label.top - panel.top, closeTo(12, 1));
    expect(
      panel.bottom - tester.getRect(find.text('Main Checking')).bottom,
      closeTo(12, 1),
    );
    expect(bar.bottom, lessThan(tester.getRect(find.text('Next payment')).top));
    expect(
      tester.getBottomLeft(find.text('Spent so far')).dy,
      lessThan(tester.getTopLeft(find.text('Next payment')).dy),
    );
    final header = find.byKey(const ValueKey('recurring-header-plan-rent'));
    final headerAmount = find.descendant(
      of: header,
      matching: find.byKey(const ValueKey('recurring-header-amount')),
    );
    final title = tester.getRect(
      find.descendant(
        of: header,
        matching: find.byKey(const ValueKey('recurring-header-title')),
      ),
    );
    final amountRect = tester.getRect(headerAmount);
    expect(amountRect.top, closeTo(title.top, 1));
    expect(amountRect.left, greaterThan(title.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ongoing and date-limited totals stay readable without a bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final (type, label, endDate) in [
      ('expense', 'Spent so far', null),
      ('expense', 'Spent so far', DateTime(2099, 12, 31)),
      ('income', 'Received so far', null),
      ('transfer', 'Transferred so far', null),
    ]) {
      final seed = paymentSeed();
      final oldPlan = seed.transactions.first;
      final plan = TransactionRecord(
        id: oldPlan.id,
        type: type,
        status: oldPlan.status,
        source: oldPlan.source,
        accountId: oldPlan.accountId,
        amount: const Money(amountMinor: 3200000, currency: 'USD'),
        baseAmount: const Money(amountMinor: 3200000, currency: 'USD'),
        occurredAt: oldPlan.occurredAt,
        recurrenceFrequency: 'monthly',
        recurrenceEndDate: endDate,
      );
      await pumpPlanDetails(
        tester,
        seed.copyWith(
          transactions: [
            plan,
            for (final record in seed.transactions.skip(1))
              record.copyWith(
                type: type,
                amount: record.amount.copyWith(
                  amountMinor: record.amount.amountMinor * 1000,
                ),
                baseAmount: record.baseAmount.copyWith(
                  amountMinor: record.baseAmount.amountMinor * 1000,
                ),
              ),
          ],
        ),
        scale: 2,
      );
      expect(find.text(label), findsOneWidget);
      final total = find.text('\$575,000.00');
      expect(total, findsOneWidget);
      final upcoming = find.text(
        '${incomeTypes.contains(type) ? '+' : '-'}\$32,000.00',
      );
      for (final amount in [total, upcoming]) {
        final paragraph = tester.renderObject<RenderParagraph>(amount);
        final painter = TextPainter(
          text: paragraph.text,
          textDirection: paragraph.textDirection,
          textScaler: paragraph.textScaler,
        )..layout(maxWidth: paragraph.size.width);
        expect(painter.computeLineMetrics(), hasLength(1));
        expect(paragraph.didExceedMaxLines, isFalse);
        painter.dispose();
      }
      final nextPaymentField = find
          .ancestor(
            of: find.text('Next payment'),
            matching: find.byType(Column),
          )
          .first;
      expect(
        tester
            .getTopLeft(
              find.descendant(
                of: nextPaymentField,
                matching: find.text(
                  formatLedgerDate(plan.occurredAt, seed.preferences.locale),
                ),
              ),
            )
            .dy,
        greaterThan(tester.getBottomLeft(find.text('Next payment')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Main Checking')).dy,
        greaterThan(tester.getBottomLeft(find.text('Account')).dy),
      );
      expect(find.byType(GlassProgressIndicator), findsNothing);
      if (endDate == null) {
        expect(find.text('No end date'), findsOneWidget);
      } else {
        expect(
          find.text(
            'Ends ${formatLedgerDate(endDate, seed.preferences.locale)}',
          ),
          findsOneWidget,
        );
        expect(find.text('No end date'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'Past recurring hides skipped occurrences when hideSkippedInHistory is '
    'true',
    (tester) async {
      await pumpPastRecurring(tester, buildSeed(hideSkipped: true));
      expect(find.text('SkippedRentMarker'), findsNothing);
    },
  );

  testWidgets('Past recurring still shows skipped occurrences when '
      'hideSkippedInHistory is false', (tester) async {
    await pumpPastRecurring(tester, buildSeed(hideSkipped: false));
    expect(find.text('SkippedRentMarker'), findsOneWidget);
  });

  testWidgets('recurring amount remains readable at large text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final seed = buildSeed(hideSkipped: false);
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(ledger: seed),
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    await container.read(ledgerProvider.notifier).restoreLedgerState(seed);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
        ),
      ),
    );
    router.go('/recurring/new');
    await tester.pumpAndSettle();
    final amount = find.widgetWithText(TextFormField, 'Amount');
    final currency = find.widgetWithText(OutlinedButton, 'USD');
    expect(tester.getSize(amount).width, greaterThan(250));
    expect(
      tester.getTopLeft(currency).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(amount).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'urgent planned payments ellipsize titles and keep amounts readable',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const name = 'Quarterly rent payment';
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      for (final (days, badge, scale) in [
        (-1, 'OVERDUE', 1.0),
        (0, 'TODAY', 2.0),
        (2, '2D', 1.0),
      ]) {
        final seed = buildSeed(hideSkipped: false);
        final plan = seed.transactions.first.copyWith(
          name: name,
          occurredAt: today.add(Duration(days: days)),
        );
        final state = seed.copyWith(transactions: [plan]);
        final container = ProviderContainer(
          overrides: authenticatedSampleOverrides(ledger: state),
        );
        await container.read(ledgerProvider.notifier).restoreLedgerState(state);
        final router = container.read(appRouterProvider);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: router,
              theme: AppTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
            ),
          ),
        );
        router.go('/recurring');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(name));

        final card = find.ancestor(
          of: find.text(name),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget.runtimeType.toString() == '_RecurringCompactCard',
          ),
        );
        final title = tester.widget<Text>(find.text(name));
        expect(title.maxLines, 1);
        expect(title.overflow, TextOverflow.ellipsis);
        expect(
          find.descendant(of: card, matching: find.text(badge)),
          findsNothing,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.byKey(ValueKey('recurring-urgency-${plan.id}')),
          ),
          findsOneWidget,
        );
        final amount = find.descendant(
          of: card,
          matching: find.byType(PrivacyText),
        );
        expect(amount, findsOneWidget);
        final amountColumn = find.descendant(
          of: card,
          matching: find.byKey(const ValueKey('recurring-header-amount')),
        );
        expect(
          tester.getRect(amountColumn).top,
          closeTo(tester.getRect(find.text(name)).top, 1),
        );
        final amountText = find.descendant(
          of: amount,
          matching: find.byType(Text),
        );
        expect(
          tester.renderObject<RenderParagraph>(amountText).didExceedMaxLines,
          isFalse,
        );
        if (scale == 1) {
          final fitted = find
              .ancestor(of: amount, matching: find.byType(FittedBox))
              .first;
          expect(
            tester.getSize(fitted).width + 0.01,
            greaterThanOrEqualTo(tester.getSize(amountText).width),
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      }
    },
  );

  testWidgets(
    'entering more fractional digits than the currency supports rounds '
    'the plan amount instead of truncating',
    (tester) async {
      final seed = buildSeed(hideSkipped: false);
      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(ledger: seed),
      );
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      await container.read(ledgerProvider.notifier).restoreLedgerState(seed);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
            theme: AppTheme.light().copyWith(
              splashFactory: NoSplash.splashFactory,
            ),
            darkTheme: AppTheme.amoled().copyWith(
              splashFactory: NoSplash.splashFactory,
            ),
          ),
        ),
      );
      router.go('/recurring/new');
      await tester.pumpAndSettle();

      // acc-1 defaults in automatically (first account); USD is 2 decimals,
      // so "1.239" should round to 124 minor units, not truncate to 123.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '1.239',
      );
      await tester.pumpAndSettle();

      final beforeIds = container
          .read(ledgerProvider)
          .transactions
          .map((t) => t.id)
          .toSet();
      final saveButton = find.bySemanticsLabel('Save');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      final created = container
          .read(ledgerProvider)
          .transactions
          .singleWhere((t) => !beforeIds.contains(t.id));
      expect(created.amount.amountMinor, 124);
    },
  );

  testWidgets(
    'rapid double-tap on "Create scheduled record" only creates one plan '
    '(duplicate-submit guard)',
    (tester) async {
      final seed = buildSeed(hideSkipped: false);
      final repository = _DelayedSaveLedgerRepository(seed);
      final container = ProviderContainer(
        overrides: [
          startupStateProvider.overrideWithValue(
            const StartupState.ready(destination: StartupDestination.home),
          ),
          ledgerRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
            theme: AppTheme.light().copyWith(
              splashFactory: NoSplash.splashFactory,
            ),
            darkTheme: AppTheme.amoled().copyWith(
              splashFactory: NoSplash.splashFactory,
            ),
          ),
        ),
      );
      // Seed synchronously (see add_record_calculator_and_rounding_test.dart
      // for why we don't rely on the controller's own startup load here).
      unawaited(
        container.read(ledgerProvider.notifier).restoreLedgerState(seed),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      router.go('/recurring/new');
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '50',
      );
      await tester.pumpAndSettle();

      final beforeIds = container
          .read(ledgerProvider)
          .transactions
          .map((t) => t.id)
          .toSet();
      final saveButton = find.bySemanticsLabel('Save');

      await tester.tap(saveButton);
      await tester.tap(saveButton);

      expect(
        container
            .read(ledgerProvider)
            .transactions
            .where((t) => !beforeIds.contains(t.id))
            .length,
        1,
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(
        container
            .read(ledgerProvider)
            .transactions
            .where((t) => !beforeIds.contains(t.id))
            .length,
        1,
      );
    },
  );
}

class _DelayedSaveLedgerRepository extends LedgerRepository {
  _DelayedSaveLedgerRepository(this._seed);

  final LedgerState _seed;
  LedgerState? _saved;

  @override
  Future<LedgerState?> load() async => _saved ?? _seed;

  @override
  Future<void> save(LedgerState state) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _saved = state;
  }

  @override
  Future<void> clear() async {
    _saved = null;
  }
}
