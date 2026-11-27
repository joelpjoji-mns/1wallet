import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
        expect(date.left, closeTo(amount.left, 0.1));
        expect(date.right, closeTo(amount.right, 0.1));
        expect(date.top, greaterThanOrEqualTo(amount.bottom));
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
            expect(first.width, closeTo(second.width, 0.1));
            if (detail) {
              final schedule = find.byKey(const ValueKey('recurring-schedule'));
              final label = tester.getRect(
                find.descendant(of: schedule, matching: find.text('SCHEDULED')),
              );
              final value = tester.getRect(
                find.descendant(of: schedule, matching: find.text('MONTHLY')),
              );
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
              expect(label.top, closeTo(value.top, 0.1));
              expect(value.top, greaterThanOrEqualTo(due.bottom));
              expect(value.right, closeTo(first.right, 0.1));
              expect(label.right, lessThan(value.left));
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
}
