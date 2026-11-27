import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/features/home/home_insight_selectors.dart';
import 'package:one_wallet_flutter/src/features/home/home_widget_card.dart';
import 'package:one_wallet_flutter/src/features/home/home_widget_models.dart';
import 'package:one_wallet_flutter/src/features/home/home_widgets.dart';
import 'package:one_wallet_flutter/src/ledger/ledger_selectors.dart';

import 'fixtures/sample_ledger.dart';

void main() {
  final now = DateTime(2026, 11, 20, 9);
  Money inr(int minor) => Money(amountMinor: minor, currency: 'INR');

  TransactionRecord record(
    String id, {
    String type = 'expense',
    String status = 'cleared',
    String accountId = 'acc-bank',
    String? counterAccountId,
    String? categoryId,
    required int amountMinor,
    required DateTime at,
    String? frequency,
    DateTime? endDate,
    int? limit,
    String? parentId,
    String? name,
  }) {
    return TransactionRecord(
      id: id,
      type: type,
      status: status,
      source: 'manual',
      accountId: accountId,
      counterAccountId: counterAccountId,
      amount: inr(amountMinor),
      baseAmount: inr(amountMinor),
      occurredAt: at,
      categoryId: categoryId,
      recurrenceFrequency: frequency,
      recurrenceEndDate: endDate,
      recurrenceLimit: limit,
      originalTransactionId: parentId,
      name: name,
    );
  }

  TransactionRecord salaryPlan(
    String id,
    DateTime due, {
    String status = 'scheduled',
    String accountId = 'acc-bank',
    DateTime? endDate,
    int? limit,
  }) => record(
    id,
    type: 'income',
    status: status,
    accountId: accountId,
    categoryId: 'cat-salary',
    amountMinor: 10000000,
    at: due,
    frequency: 'monthly',
    endDate: endDate,
    limit: limit,
  );

  LedgerState withTransactions(
    List<TransactionRecord> transactions, {
    List<Account>? accounts,
  }) {
    final base = sampleLedgerState();
    return base.copyWith(
      transactions: transactions,
      accounts: accounts ?? base.accounts,
    );
  }

  group('paydayInfo', () {
    test('counts calendar days, cycle progress and bills before payday', () {
      final state = withTransactions([
        salaryPlan('salary', DateTime(2026, 12, 1, 10)),
        record(
          'salary-paid',
          type: 'income',
          categoryId: 'cat-salary',
          amountMinor: 10000000,
          at: DateTime(2026, 11, 1, 10),
          parentId: 'salary',
        ),
        salaryPlan('paused', DateTime(2026, 11, 22), status: 'paused'),
        salaryPlan(
          'ended',
          DateTime(2026, 11, 21),
          endDate: DateTime(2026, 10, 31),
        ),
        record(
          'rent',
          status: 'scheduled',
          categoryId: 'cat-bills',
          amountMinor: 3200000,
          at: DateTime(2026, 11, 24),
          frequency: 'monthly',
        ),
        record(
          'weekly-gym',
          status: 'scheduled',
          amountMinor: 50000,
          at: DateTime(2026, 11, 18),
          frequency: 'weekly',
        ),
        record(
          'on-payday',
          status: 'scheduled',
          amountMinor: 999900,
          at: DateTime(2026, 12, 1),
          frequency: 'monthly',
        ),
        record(
          'savings-transfer',
          type: 'transfer',
          status: 'scheduled',
          counterAccountId: 'acc-cash',
          amountMinor: 500000,
          at: DateTime(2026, 11, 25),
          frequency: 'monthly',
        ),
      ]);

      final info = paydayInfo(state, now: now)!;

      expect(info.plan.id, 'salary');
      expect(info.daysUntil, 11);
      expect(info.cycleLength, 30);
      expect(info.cycleProgress, closeTo(19 / 30, 0.001));
      expect(info.otherPlanIds, isEmpty);
      // Overdue gym (18 Nov) plus weekly repeats on 25 Nov, plus rent.
      expect(info.bills.map((bill) => bill.planId), [
        'weekly-gym',
        'rent',
        'weekly-gym',
      ]);
      expect(info.billsTotal.amountMinor, 3200000 + 2 * 50000);
      final balance = accountBalance(
        state,
        accountById(state, 'acc-bank')!,
      ).amountMinor;
      expect(info.leftAfterBills!.amountMinor, balance - 3300000);
    });

    test('ignores plans on deleted accounts and plans at their limit', () {
      final base = sampleLedgerState();
      final state = withTransactions(
        [
          salaryPlan('deleted', DateTime(2026, 11, 25), accountId: 'acc-cash'),
          salaryPlan('limited', DateTime(2026, 11, 26), limit: 1),
          record(
            'limited-paid',
            type: 'income',
            categoryId: 'cat-salary',
            amountMinor: 10000000,
            at: DateTime(2026, 10, 26),
            parentId: 'limited',
          ),
        ],
        accounts: [
          for (final account in base.accounts)
            account.id == 'acc-cash'
                ? account.copyWith(isDeleted: true, isArchived: true)
                : account,
        ],
      );

      expect(paydayInfo(state, now: now), isNull);
    });

    test('shows a late salary, then rolls forward after the grace period', () {
      final late = paydayInfo(
        withTransactions([salaryPlan('salary', DateTime(2026, 11, 17))]),
        now: now,
      )!;
      expect(late.daysUntil, -3);
      expect(late.isLate, isTrue);
      expect(late.missedCount, 0);

      final missed = paydayInfo(
        withTransactions([salaryPlan('salary', DateTime(2026, 11, 5))]),
        now: now,
      )!;
      expect(missed.payday, DateTime(2026, 12, 5));
      expect(missed.daysUntil, 15);
      expect(missed.missedCount, 1);
    });

    test('uses the nearest salary unless another one is pinned', () {
      final transactions = [
        salaryPlan('job-a', DateTime(2026, 11, 30)),
        salaryPlan('job-b', DateTime(2026, 11, 25)),
      ];
      final nearest = paydayInfo(withTransactions(transactions), now: now)!;
      expect(nearest.plan.id, 'job-b');
      expect(nearest.otherPlanIds, ['job-a']);

      final base = withTransactions(transactions);
      final pinned = base.copyWith(
        preferences: base.preferences.copyWith(
          homeWidgetFilters: {paydayPinnedPlanKey: 'job-a'},
        ),
      );
      expect(paydayInfo(pinned, now: now)!.plan.id, 'job-a');
    });

    test('handles DST-free day counts and month-end salaries', () {
      expect(
        calendarDaysBetween(DateTime(2026, 3, 28, 23), DateTime(2026, 3, 30)),
        2,
      );
      final info = paydayInfo(
        withTransactions([salaryPlan('salary', DateTime(2027, 1, 31))]),
        now: DateTime(2027, 2, 9),
      )!;
      // Nine days late rolls to 28 Feb (31st clamps in short months).
      expect(info.payday, DateTime(2027, 2, 28));
      expect(info.missedCount, 1);
    });
  });

  group('cardBills', () {
    test('orders unpaid bills first and excludes deleted cards', () {
      final base = sampleLedgerState();
      final card = base.accounts.firstWhere((a) => a.id == 'acc-card');
      final state = base.copyWith(
        transactions: const [],
        accounts: [
          card.copyWith(dueDay: 25, openingBalance: inr(-500000)),
          card.copyWith(
            id: 'card-paid',
            name: 'Paid card',
            dueDay: 22,
            lastPaidBillMonth: '2026-11',
          ),
          card.copyWith(
            id: 'card-deleted',
            dueDay: 21,
            isDeleted: true,
            isArchived: true,
          ),
        ],
      );

      final bills = cardBills(state, now: now);

      expect(bills.map((bill) => bill.status.account.id), [
        'acc-card',
        'card-paid',
      ]);
      expect(bills.first.owed.amountMinor, 500000);
      expect(bills.first.status.daysUntilDue, 5);
      expect(bills.last.status.isPaid, isTrue);
    });
  });

  group('categorySpikes', () {
    List<TransactionRecord> monthOf(
      int month, {
      required int dining,
      required int shopping,
    }) => [
      record(
        'dining-$month',
        categoryId: 'cat-dining',
        amountMinor: dining,
        at: DateTime(2026, month, 10),
      ),
      record(
        'shopping-$month',
        categoryId: 'cat-shopping',
        amountMinor: shopping,
        at: DateTime(2026, month, 12),
      ),
    ];

    test('compares month-to-date spending with the recent average', () {
      final state = withTransactions([
        ...monthOf(8, dining: 100000, shopping: 200000),
        ...monthOf(9, dining: 100000, shopping: 200000),
        ...monthOf(10, dining: 100000, shopping: 200000),
        // After day 20, so outside the like-for-like window.
        record(
          'late-october',
          categoryId: 'cat-dining',
          amountMinor: 900000,
          at: DateTime(2026, 10, 25),
        ),
        ...monthOf(11, dining: 200000, shopping: 205000),
        record(
          'dining-refund',
          type: 'refund',
          categoryId: 'cat-dining',
          amountMinor: 20000,
          at: DateTime(2026, 11, 15),
        ),
        record(
          'tiny',
          categoryId: 'cat-travel',
          amountMinor: 500,
          at: DateTime(2026, 11, 3),
        ),
        record(
          'scheduled',
          status: 'scheduled',
          categoryId: 'cat-dining',
          amountMinor: 900000,
          at: DateTime(2026, 11, 19),
        ),
      ]);

      final result = categorySpikes(state, now: now);

      expect(result.hasEnoughHistory, isTrue);
      expect(result.monthsCompared, 3);
      expect(result.items, hasLength(1));
      final dining = result.items.single;
      expect(dining.category.id, 'cat-food');
      expect(dining.current.amountMinor, 180000);
      expect(dining.baseline.amountMinor, 100000);
      expect(dining.change, closeTo(0.8, 0.001));
    });

    test('needs two previous months of spending', () {
      final state = withTransactions([
        ...monthOf(10, dining: 100000, shopping: 200000),
        ...monthOf(11, dining: 400000, shopping: 200000),
      ]);
      final result = categorySpikes(state, now: now);
      expect(result.hasEnoughHistory, isFalse);
      expect(result.items, isEmpty);
    });
  });

  group('insight widgets', () {
    test('sit at the bottom of new and existing dashboards', () {
      const insights = [
        HomeDashboardWidgetId.paydayCountdown,
        HomeDashboardWidgetId.nextCardBill,
        HomeDashboardWidgetId.categorySpikes,
      ];
      final fresh = resolveHomeWidgetOrder(kRnDefaultHomeWidgetOrder);
      expect(fresh.skip(fresh.length - 3), insights);
      for (final id in undatedHomeWidgets) {
        expect(homeWidgetSupportsDateFilter(id), isFalse);
      }

      // A saved order from before these widgets existed gets them appended.
      final existing = resolveHomeWidgetOrder([
        'recentRecords',
        'balanceHero',
        'weekendWeekdayRatio',
      ]);
      expect(existing.take(2), [
        HomeDashboardWidgetId.recentRecords,
        HomeDashboardWidgetId.balanceHero,
      ]);
      expect(existing.skip(existing.length - 3), insights);

      final restored = restoreHomeWidgetStorageKey([
        'balanceHero',
        'weekendWeekdayRatio',
        'categorySpikes',
      ], 'nextCardBill');
      expect(restored, [
        'balanceHero',
        'weekendWeekdayRatio',
        'nextCardBill',
        'categorySpikes',
      ]);
    });

    testWidgets('render through the dashboard dispatcher', (tester) async {
      final today = DateTime.now();
      final base = sampleLedgerState();
      final state = base.copyWith(
        transactions: [
          ...base.transactions,
          salaryPlan(
            'salary',
            DateTime(today.year, today.month, today.day + 5, 10),
          ),
        ],
      );

      for (final id in undatedHomeWidgets) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProviderScope(
                child: SingleChildScrollView(
                  child: Builder(
                    builder: (context) => buildHomeDashboardWidget(
                      context: context,
                      id: id,
                      state: state,
                      onTabSelected: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(HomeWidgetCard), findsOneWidget, reason: '$id');
        expect(tester.takeException(), isNull, reason: '$id');
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProviderScope(
              child: SingleChildScrollView(
                child: Builder(
                  builder: (context) => buildHomeDashboardWidget(
                    context: context,
                    id: HomeDashboardWidgetId.paydayCountdown,
                    state: state,
                    onTabSelected: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('5 days'), findsOneWidget);
      expect(find.textContaining('Bills before payday'), findsOneWidget);
    });
  });
}
