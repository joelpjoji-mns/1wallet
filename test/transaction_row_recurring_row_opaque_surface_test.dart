import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/recurring/recurring_screen.dart';
import 'package:one_wallet_flutter/src/features/transactions/transaction_row.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/widgets/privacy_text.dart';

import 'test_harness.dart';

/// Covers the package-fidelity fix: `TransactionRow` and the recurring
/// screen's compact row card are rendered in bulk inside scrolling lists
/// (Transactions, Recurring, Home recent activity), so per the
/// liquid_glass_widgets guidance they must stay lightweight opaque
/// surfaces rather than per-item refractive `GlassCard`s. Glass stays
/// reserved for the surrounding chrome (e.g. the recurring summary header).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'TransactionRow renders a Liquid Glass surface and remains tappable',
    (tester) async {
      var tapped = false;
      final state = emptyLedgerState().copyWith(
        accounts: [
          const Account(
            id: 'acc-cash',
            name: 'Cash Wallet',
            type: 'cash',
            currency: 'USD',
            openingBalance: Money(amountMinor: 0, currency: 'USD'),
          ),
        ],
      );
      final transaction = TransactionRecord(
        id: 'tx-1',
        type: 'expense',
        status: 'cleared',
        source: 'manual',
        accountId: 'acc-cash',
        amount: const Money(amountMinor: 1250, currency: 'USD'),
        baseAmount: const Money(amountMinor: 1250, currency: 'USD'),
        occurredAt: DateTime(2026, 1, 5),
        notes: 'Coffee',
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
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.amoled(),
            home: Scaffold(
              body: TransactionRow(
                state: state,
                transaction: transaction,
                onTap: () => tapped = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(TransactionRow),
          matching: find.byType(GlassCard),
        ),
        findsOneWidget,
      );

      // Content and interactivity are unaffected by the surface change.
      expect(find.text('Coffee'), findsOneWidget);
      await tester.tap(find.byType(TransactionRow));
      expect(tapped, isTrue);
    },
  );

  testWidgets('large-text transaction details and amount do not overlap', (
    tester,
  ) async {
    const accountName = 'A long account name for monthly household expenses';
    const notes = 'A long note that should remain readable on a narrow phone';
    final state = emptyLedgerState().copyWith(
      accounts: [
        const Account(
          id: 'acc-cash',
          name: accountName,
          type: 'cash',
          currency: 'USD',
          openingBalance: Money(amountMinor: 0, currency: 'USD'),
        ),
      ],
    );
    final transaction = TransactionRecord(
      id: 'tx-1',
      type: 'expense',
      status: 'cleared',
      source: 'manual',
      accountId: 'acc-cash',
      amount: const Money(amountMinor: 123456789, currency: 'USD'),
      baseAmount: const Money(amountMinor: 123456789, currency: 'USD'),
      occurredAt: DateTime(2026, 1, 5),
      notes: notes,
    );
    var tapped = false;
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(ledger: state),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 320,
                    child: TransactionRow(
                      state: state,
                      transaction: transaction,
                      showSurface: false,
                      onTap: () => tapped = true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final account = tester.widget<Text>(find.text(accountName));
    final note = tester.widget<Text>(find.text(notes));
    expect(account.maxLines, isNull);
    expect(note.maxLines, isNull);
    expect(
      tester.getRect(find.byType(PrivacyText).first).top,
      greaterThanOrEqualTo(tester.getRect(find.text(notes)).bottom),
    );
    await tester.tap(find.byType(TransactionRow));
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Recurring planned-list rows use Liquid Glass surfaces', (
    tester,
  ) async {
    final now = DateTime.now();
    final state = emptyLedgerState().copyWith(
      accounts: [
        const Account(
          id: 'acc-bank',
          name: 'HDFC Main',
          type: 'bank',
          currency: 'USD',
          openingBalance: Money(amountMinor: 500000, currency: 'USD'),
        ),
      ],
      transactions: [
        TransactionRecord(
          id: 'plan-rent',
          type: 'expense',
          status: 'scheduled',
          source: 'recurring',
          accountId: 'acc-bank',
          amount: const Money(amountMinor: 32000, currency: 'USD'),
          baseAmount: const Money(amountMinor: 32000, currency: 'USD'),
          occurredAt: now.add(const Duration(days: 4)),
          recurrenceFrequency: 'monthly',
          name: 'Rent',
        ),
      ],
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
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.amoled(),
          home: const Scaffold(body: RecurringScreen(mode: 'overview')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rowFinder = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_RecurringCompactCard',
    );
    expect(rowFinder, findsOneWidget);
    expect(
      find.descendant(of: rowFinder, matching: find.byType(GlassCard)),
      findsOneWidget,
    );
  });

  testWidgets(
    'planned list, detail and history keep amounts and dates beside titles',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final now = DateTime.now();
      final rent = TransactionRecord(
        id: 'plan-rent',
        type: 'expense',
        status: 'scheduled',
        source: 'recurring',
        accountId: 'acc-bank',
        amount: const Money(amountMinor: 123456789, currency: 'USD'),
        categoryId: 'cat-nested',
        baseAmount: const Money(amountMinor: 123456789, currency: 'USD'),
        occurredAt: now.add(const Duration(days: 4)),
        recurrenceFrequency: 'monthly',
        name: 'Apartment rent with a long descriptive title',
      );
      final bill = rent.copyWith(
        id: 'plan-bill',
        name: 'Electricity',
        amount: const Money(amountMinor: 1234, currency: 'USD'),
        baseAmount: const Money(amountMinor: 1234, currency: 'USD'),
      );
      final payment = bill.copyWith(
        id: 'payment-rent',
        name: 'Previous rent payment',
        status: 'cleared',
        originalTransactionId: rent.id,
        occurredAt: now.subtract(const Duration(days: 30)),
      );
      final state = emptyLedgerState().copyWith(
        accounts: [
          const Account(
            id: 'acc-bank',
            name: 'Household expenses account',
            type: 'bank',
            currency: 'USD',
            openingBalance: Money(amountMinor: 500000, currency: 'USD'),
          ),
        ],
        transactions: [rent, bill, payment],
        categories: const [
          Category(id: 'cat-house', name: 'Household', kind: 'expense'),
          Category(
            id: 'cat-bills',
            name: 'Bills',
            kind: 'expense',
            parentId: 'cat-house',
          ),
          Category(
            id: 'cat-nested',
            name: 'Apartment maintenance and rent',
            kind: 'expense',
            parentId: 'cat-bills',
          ),
        ],
      );
      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(ledger: state),
      );
      addTearDown(container.dispose);
      await container.read(ledgerProvider.notifier).restoreLedgerState(state);

      Rect expectSideBySideHeader(TransactionRecord record) {
        final header = find.byKey(ValueKey('recurring-header-${record.id}'));
        final titleWidget = tester.widget<Text>(
          find.descendant(
            of: header,
            matching: find.byKey(const ValueKey('recurring-header-title')),
          ),
        );
        expect(titleWidget.maxLines, 1);
        expect(titleWidget.overflow, TextOverflow.ellipsis);
        final title = tester.getRect(
          find.descendant(of: header, matching: find.text(record.name!)),
        );
        final amount = tester.getRect(
          find.descendant(
            of: header,
            matching: find.byKey(const ValueKey('recurring-header-amount')),
          ),
        );
        final date = tester.getRect(
          find.descendant(
            of: header,
            matching: find.byKey(const ValueKey('recurring-header-status')),
          ),
        );
        expect(amount.top, closeTo(title.top, 0.1));
        expect(amount.left, greaterThan(title.right));
        expect(date.right, closeTo(amount.right, 0.1));
        expect(date.top, greaterThanOrEqualTo(amount.bottom));
        final category = find.descendant(
          of: header,
          matching: find.byKey(const ValueKey('recurring-header-category')),
        );
        expect(
          tester.widget<Text>(category).data,
          'Household > Bills > Apartment maintenance and rent',
        );
        expect(tester.widget<Text>(category).maxLines, 1);
        expect(tester.getRect(category).top, closeTo(date.top, 0.1));
        return amount;
      }

      for (final width in [320.0, 390.0]) {
        await tester.binding.setSurfaceSize(Size(width, 844));
        for (final scale in [1.0, 2.0]) {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          for (final detail in [false, true]) {
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: container,
                child: MaterialApp(
                  theme: AppTheme.light(),
                  home: RecurringScreen(recordId: detail ? rent.id : null),
                ),
              ),
            );
            await tester.pumpAndSettle();

            final first = expectSideBySideHeader(rent);
            final second = expectSideBySideHeader(detail ? payment : bill);
            expect(first.right, closeTo(second.right, 0.1));
            if (detail) {
              final schedule = find.byKey(const ValueKey('recurring-schedule'));
              final value = tester.getRect(schedule);
              final header = find.byKey(
                const ValueKey('recurring-header-plan-rent'),
              );
              final due = tester.getRect(
                find.descendant(
                  of: header,
                  matching: find.byKey(
                    const ValueKey('recurring-header-status'),
                  ),
                ),
              );
              expect(value.top, greaterThanOrEqualTo(due.bottom));
              expect(value.right, closeTo(first.right, 0.1));
            }
            expect(tester.takeException(), isNull);
          }
        }
      }
    },
  );

  testWidgets(
    'planned detail keeps posting and recurrence actions in two-column rows',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      final state = emptyLedgerState().copyWith(
        accounts: [
          const Account(
            id: 'acc-bank',
            name: 'HDFC Main',
            type: 'bank',
            currency: 'USD',
            openingBalance: Money(amountMinor: 500000, currency: 'USD'),
          ),
        ],
        transactions: [
          TransactionRecord(
            id: 'plan-rent',
            type: 'expense',
            status: 'scheduled',
            source: 'recurring',
            accountId: 'acc-bank',
            amount: const Money(amountMinor: 32000, currency: 'USD'),
            baseAmount: const Money(amountMinor: 32000, currency: 'USD'),
            occurredAt: now.add(const Duration(days: 4)),
            recurrenceFrequency: 'monthly',
            name: 'Rent',
          ),
        ],
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
            theme: AppTheme.light(),
            home: const Scaffold(body: RecurringScreen(recordId: 'plan-rent')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Post now'), findsOneWidget);
      expect(find.text('Postpone'), findsOneWidget);
      expect(find.text('Skip next'), findsOneWidget);
      expect(find.text('Pause'), findsOneWidget);
      expect(
        tester.getCenter(find.text('Post now')).dy,
        closeTo(tester.getCenter(find.text('Postpone')).dy, 1),
      );
      expect(
        tester.getCenter(find.text('Skip next')).dy,
        closeTo(tester.getCenter(find.text('Pause')).dy, 1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('planned cards join schedule and account, notes span the card', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now();
    TransactionRecord plan(String id, String type, String name, String? notes) {
      return TransactionRecord(
        id: id,
        type: type,
        status: 'scheduled',
        source: 'recurring',
        accountId: 'acc-bank',
        amount: const Money(amountMinor: 32000, currency: 'USD'),
        baseAmount: const Money(amountMinor: 32000, currency: 'USD'),
        occurredAt: now.add(const Duration(days: 4)),
        recurrenceFrequency: 'monthly',
        recurrenceInterval: 2,
        recurrenceDaysOfMonth: const [17],
        name: name,
        notes: notes,
      );
    }

    const longNote =
        'Landlord: Mr Sharma. Includes maintenance; pay before the 5th to '
        'avoid the late fee.';
    final state = emptyLedgerState().copyWith(
      accounts: [
        const Account(
          id: 'acc-bank',
          name: 'HDFC Main',
          type: 'bank',
          currency: 'USD',
          openingBalance: Money(amountMinor: 500000, currency: 'USD'),
        ),
      ],
      transactions: [
        plan('plan-rent', 'expense', 'Rent', longNote),
        plan('plan-salary', 'income', 'Salary', 'Salary'),
      ],
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
          theme: AppTheme.light(),
          home: const Scaffold(body: RecurringScreen(mode: 'overview')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final expense = find.text(
      'Every 2 months on 17 from HDFC Main',
      findRichText: true,
    );
    expect(expense, findsOneWidget);
    final scheduleText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('recurring-card-schedule')).first,
        matching: find.byType(Text),
      ),
    );
    final accountSpan = (scheduleText.textSpan! as TextSpan).children!
        .whereType<TextSpan>()
        .firstWhere((span) => span.text == 'HDFC Main');
    expect(accountSpan.style!.color, AppTheme.light().colorScheme.primary);
    expect(
      find.text('Every 2 months on 17 into HDFC Main', findRichText: true),
      findsOneWidget,
    );
    // Notes that only repeat the plan name are not shown twice.
    expect(find.byKey(const ValueKey('recurring-card-notes')), findsOneWidget);

    final schedule = tester.getRect(expense);
    final notes = tester.getRect(find.text(longNote));
    final title = tester.getRect(find.text('Rent'));
    final amount = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('recurring-header-plan-rent')),
        matching: find.byKey(const ValueKey('recurring-header-amount')),
      ),
    );
    expect(schedule.right, greaterThan(amount.left));
    expect(schedule.left, closeTo(title.left, 0.1));
    expect(notes.left, closeTo(title.left, 0.1));
    expect(notes.top, greaterThanOrEqualTo(schedule.bottom));
    // Notes use the full card width and wrap only past the right edge.
    expect(notes.right, greaterThan(amount.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('skipped and urgent planned cards keep status compact', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime.now();
    final plan = TransactionRecord(
      id: 'plan-groceries',
      type: 'expense',
      status: 'scheduled',
      source: 'recurring',
      accountId: 'acc-bank',
      amount: const Money(amountMinor: 3000, currency: 'USD'),
      baseAmount: const Money(amountMinor: 3000, currency: 'USD'),
      occurredAt: now.add(const Duration(days: 2)),
      recurrenceFrequency: 'weekly',
      name: 'Groceries',
    );
    final skipped = plan.copyWith(
      id: 'skip-groceries',
      status: 'void',
      notes: 'Skipped',
      originalTransactionId: plan.id,
      occurredAt: now.subtract(const Duration(days: 12)),
    );
    final state = emptyLedgerState().copyWith(
      accounts: [
        const Account(
          id: 'acc-bank',
          name: 'Monzo Bank',
          type: 'bank',
          currency: 'USD',
          openingBalance: Money(amountMinor: 500000, currency: 'USD'),
        ),
      ],
      transactions: [plan, skipped],
    );
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(ledger: state),
    );
    addTearDown(container.dispose);
    await container.read(ledgerProvider.notifier).restoreLedgerState(state);

    Future<void> pump(Widget home) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(body: home),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // Urgency remains on the left rail, without an extra day badge.
    await pump(const RecurringScreen(mode: 'overview'));
    final header = find.byKey(
      const ValueKey('recurring-header-plan-groceries'),
    );
    final amount = tester.getRect(
      find.descendant(
        of: header,
        matching: find.byKey(const ValueKey('recurring-header-amount')),
      ),
    );
    final status = tester.getRect(
      find.descendant(
        of: header,
        matching: find.byKey(const ValueKey('recurring-header-status')),
      ),
    );
    expect(find.text('2D'), findsNothing);
    expect(
      find.byKey(const ValueKey('recurring-urgency-plan-groceries')),
      findsOneWidget,
    );
    expect(status.top, greaterThanOrEqualTo(amount.bottom));
    final schedule = tester.getRect(
      find.text('Every 1 week from Monzo Bank', findRichText: true),
    );
    expect(schedule.top - status.bottom, lessThan(8));

    // A skipped history entry keeps its icon beside its label.
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    await pump(RecurringScreen(recordId: plan.id));
    final skippedHeader = find.byKey(
      const ValueKey('recurring-header-skip-groceries'),
    );
    final icon = tester.getRect(
      find.descendant(
        of: skippedHeader,
        matching: find.byIcon(Icons.block_rounded),
      ),
    );
    final label = find.descendant(
      of: skippedHeader,
      matching: find.textContaining('Skipped'),
    );
    final labelRect = tester.getRect(label);
    final skippedStatus = tester.getRect(
      find.descendant(
        of: skippedHeader,
        matching: find.byKey(const ValueKey('recurring-header-status')),
      ),
    );
    expect(tester.widget<Text>(label).maxLines, 1);
    // Single line: a wrapped label would be roughly twice as tall.
    expect(skippedStatus.height, lessThan(20));
    expect(labelRect.left - icon.right, lessThanOrEqualTo(4.5));
    expect(icon.center.dy, closeTo(labelRect.center.dy, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping Skip next twice skips one occurrence', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final due = DateTime.now().add(const Duration(days: 4));
    final state = emptyLedgerState().copyWith(
      accounts: [
        const Account(
          id: 'acc-bank',
          name: 'HDFC Main',
          type: 'bank',
          currency: 'USD',
          openingBalance: Money(amountMinor: 500000, currency: 'USD'),
        ),
      ],
      transactions: [
        TransactionRecord(
          id: 'plan-rent',
          type: 'expense',
          status: 'scheduled',
          source: 'recurring',
          accountId: 'acc-bank',
          amount: const Money(amountMinor: 32000, currency: 'USD'),
          baseAmount: const Money(amountMinor: 32000, currency: 'USD'),
          occurredAt: due,
          recurrenceFrequency: 'monthly',
          name: 'Rent',
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(ledger: state),
    );
    addTearDown(container.dispose);
    await container.read(ledgerProvider.notifier).restoreLedgerState(state);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const Scaffold(
                  body: RecurringScreen(recordId: 'plan-rent'),
                ),
              ),
              GoRoute(
                path: '/recurring',
                builder: (context, state) => const SizedBox(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Skip next'));
    await tester.tap(find.text('Skip next'), warnIfMissed: false);
    await tester.pumpAndSettle();

    final ledger = container.read(ledgerProvider);
    final skipped = ledger.transactions.where(
      (t) => t.status == 'void' && t.originalTransactionId == 'plan-rent',
    );
    expect(skipped, hasLength(1));
    final next = ledger.transactions.firstWhere((t) => t.id == 'plan-rent');
    expect(next.occurredAt.isAfter(due), isTrue);
    expect(next.occurredAt.difference(due).inDays, lessThan(32));
  });
}
