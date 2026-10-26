import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/features/home/home_widget_models.dart';
import 'package:one_wallet_flutter/src/ledger/ledger_selectors.dart';

void main() {
  group('homeWidgetDateRange', () {
    test('accurately calculates ranges for past and calendar periods', () {
      final now = DateTime.now();

      final thisMonth = homeWidgetDateRange('This month');
      expect(thisMonth.start, DateTime(now.year, now.month));
      expect(thisMonth.end, DateTime(now.year, now.month + 1));

      final lastMonth = homeWidgetDateRange('Last month');
      expect(lastMonth.start, DateTime(now.year, now.month - 1));
      expect(lastMonth.end, DateTime(now.year, now.month));

      final thisYear = homeWidgetDateRange('This year');
      expect(thisYear.start, DateTime(now.year, 1, 1));
      expect(thisYear.end, DateTime(now.year + 1, 1, 1));

      final allTime = homeWidgetDateRange('All time');
      expect(allTime.start, DateTime(1970, 1, 1));
      expect(allTime.end, DateTime(2100, 1, 1));
    });
  });

  group('homeWidgetFutureLimit', () {
    test('accurately calculates future limits for upcoming periods', () {
      final now = DateTime.now();

      final thisMonthLimit = homeWidgetFutureLimit('This month');
      expect(thisMonthLimit, DateTime(now.year, now.month + 1));

      final thisYearLimit = homeWidgetFutureLimit('This year');
      expect(thisYearLimit, DateTime(now.year + 1, 1, 1));

      final allTimeLimit = homeWidgetFutureLimit('All time');
      expect(allTimeLimit, DateTime(2100, 1, 1));
    });
  });

  group('flowForPeriod', () {
    test('correctly isolates transactions in Last month, This month, and This year', () {
      final now = DateTime.now();
      final currentMonthDate = DateTime(now.year, now.month, 10);
      final lastMonthDate = DateTime(now.year, now.month - 1, 10);

      final state = LedgerState(
        version: currentLedgerStateVersion,
        userId: 'test-user',
        preferences: const LedgerPreferences(displayCurrency: 'USD'),
        accounts: const [
          Account(
            id: 'bank',
            name: 'Bank',
            type: 'bank',
            currency: 'USD',
            openingBalance: Money(amountMinor: 0, currency: 'USD'),
          ),
        ],
        categories: const [],
        transactions: [
          TransactionRecord(
            id: 'tx-this-month',
            accountId: 'bank',
            type: 'income',
            status: 'cleared',
            source: 'manual',
            amount: const Money(amountMinor: 50000, currency: 'USD'),
            baseAmount: const Money(amountMinor: 50000, currency: 'USD'),
            occurredAt: currentMonthDate,
          ),
          TransactionRecord(
            id: 'tx-last-month',
            accountId: 'bank',
            type: 'expense',
            status: 'cleared',
            source: 'manual',
            amount: const Money(amountMinor: 30000, currency: 'USD'),
            baseAmount: const Money(amountMinor: 30000, currency: 'USD'),
            occurredAt: lastMonthDate,
          ),
        ],
        captureCandidates: const [],
        exchangeRates: const [],
      );

      final thisMonthFlow = flowForPeriod(state, 'This month');
      expect(thisMonthFlow.income.amountMinor, equals(50000));
      expect(thisMonthFlow.expense.amountMinor, equals(0));

      final lastMonthFlow = flowForPeriod(state, 'Last month');
      expect(lastMonthFlow.income.amountMinor, equals(0));
      expect(lastMonthFlow.expense.amountMinor, equals(30000));

      final thisYearFlow = flowForPeriod(state, 'This year');
      expect(thisYearFlow.income.amountMinor, equals(50000));
      if (now.month > 1) {
        expect(thisYearFlow.expense.amountMinor, equals(30000));
      }

      final allTimeFlow = flowForPeriod(state, 'All time');
      expect(allTimeFlow.income.amountMinor, equals(50000));
      expect(allTimeFlow.expense.amountMinor, equals(30000));
    });
  });
}
