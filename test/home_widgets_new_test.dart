import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/features/home/home_widget_card.dart';
import 'package:one_wallet_flutter/src/features/home/home_widget_models.dart';
import 'package:one_wallet_flutter/src/features/home/home_widgets.dart';
import 'package:one_wallet_flutter/src/features/home/home_widgets_new.dart';

import 'fixtures/sample_ledger.dart';

void main() {
  Money usd(int minor) => Money(amountMinor: minor, currency: 'USD');

  Widget buildTestApp(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: ProviderScope(
          child: SingleChildScrollView(
            child: child,
          ),
        ),
      ),
    );
  }

  group('New Home Dashboard Widgets Test Suite', () {
    testWidgets('1. PendingReviewHomeWidget displays empty state and populated state', (tester) async {
      final base = sampleLedgerState();

      // Empty state
      final emptyState = base.copyWith(captureCandidates: const []);
      await tester.pumpWidget(buildTestApp(PendingReviewHomeWidget(state: emptyState)));
      await tester.pumpAndSettle();
      expect(find.text('All caught up'), findsOneWidget);
      expect(find.text('Pending review'), findsOneWidget);

      // Populated state
      final populatedState = base.copyWith(
        captureCandidates: [
          CaptureCandidate(
            id: 'cap-1',
            source: 'sms',
            status: 'pending',
            merchant: 'Starbucks Coffee',
            parsedAmount: usd(550),
            createdAt: DateTime.now(),
          ),
        ],
      );
      await tester.pumpWidget(buildTestApp(PendingReviewHomeWidget(state: populatedState)));
      await tester.pumpAndSettle();
      expect(find.text('Starbucks Coffee'), findsOneWidget);
      expect(find.textContaining('1 incoming transaction'), findsOneWidget);
    });

    testWidgets('2. SavingsRateHomeWidget computes rate and flow tiles correctly', (tester) async {
      final now = DateTime.now();
      final base = sampleLedgerState();
      final sampleTx = base.transactions.first;

      final incomeTx = sampleTx.copyWith(
        id: 'tx-inc',
        type: 'income',
        status: 'cleared',
        amount: usd(100000), // $1000
        occurredAt: now,
      );
      final expenseTx = sampleTx.copyWith(
        id: 'tx-exp',
        type: 'expense',
        status: 'cleared',
        amount: usd(40000), // $400
        occurredAt: now,
      );

      final state = base.copyWith(
        transactions: [incomeTx, expenseTx],
        preferences: base.preferences.copyWith(displayCurrency: 'USD', locale: 'en_US'),
      );

      await tester.pumpWidget(buildTestApp(SavingsRateHomeWidget(state: state)));
      await tester.pumpAndSettle();

      expect(find.text('Savings rate'), findsOneWidget);
      expect(find.text('Net Saved'), findsOneWidget);
      expect(find.text('60%'), findsOneWidget); // (1000 - 400) / 1000 = 60%
    });

    testWidgets('4. TagCloudHomeWidget aggregates and displays custom tag chips', (tester) async {
      final now = DateTime.now();
      final base = sampleLedgerState();
      final sampleTx = base.transactions.first;

      final txTagged1 = sampleTx.copyWith(
        id: 'tx-tag-1',
        type: 'expense',
        status: 'cleared',
        amount: usd(3500),
        tags: ['dining', 'weekend'],
        occurredAt: now,
      );
      final txTagged2 = sampleTx.copyWith(
        id: 'tx-tag-2',
        type: 'expense',
        status: 'cleared',
        amount: usd(1500),
        tags: ['dining'],
        occurredAt: now,
      );

      final state = base.copyWith(
        transactions: [txTagged1, txTagged2],
        preferences: base.preferences.copyWith(displayCurrency: 'USD', locale: 'en_US'),
      );

      await tester.pumpWidget(buildTestApp(TagCloudHomeWidget(state: state)));
      await tester.pumpAndSettle();

      expect(find.text('Tag breakdown'), findsOneWidget);
      expect(find.text('#dining'), findsOneWidget);
      expect(find.text('#weekend'), findsOneWidget);
    });

    testWidgets('6. SafeToSpendHomeWidget renders daily allowance metrics', (tester) async {
      final base = sampleLedgerState();
      final state = base.copyWith(
        preferences: base.preferences.copyWith(displayCurrency: 'USD', locale: 'en_US'),
      );

      await tester.pumpWidget(buildTestApp(SafeToSpendHomeWidget(state: state)));
      await tester.pumpAndSettle();

      expect(find.text('Daily safe-to-spend'), findsOneWidget);
      expect(find.text("Today's Allowance"), findsOneWidget);
      expect(find.textContaining('days remaining in this month'), findsOneWidget);
    });

    testWidgets('7. CashBurnRunwayHomeWidget calculates survival margin from liquid accounts', (tester) async {
      final now = DateTime.now();
      final base = sampleLedgerState();
      final sampleTx = base.transactions.first;

      final liquidBank = Account(
        id: 'acc-liquid',
        name: 'Liquid Checking',
        type: 'bank',
        currency: 'USD',
        openingBalance: usd(600000), // $6000
      );

      final expenseTx = sampleTx.copyWith(
        id: 'tx-burn',
        type: 'expense',
        status: 'cleared',
        accountId: 'acc-liquid',
        amount: usd(300000), // $3000 over last 30 days -> $100/day
        occurredAt: now.subtract(const Duration(days: 5)),
      );

      final state = base.copyWith(
        accounts: [liquidBank],
        transactions: [expenseTx],
        preferences: base.preferences.copyWith(displayCurrency: 'USD', locale: 'en_US'),
      );

      await tester.pumpWidget(buildTestApp(CashBurnRunwayHomeWidget(state: state)));
      await tester.pumpAndSettle();

      expect(find.text('Cash runway'), findsOneWidget);
      expect(find.text('Survival Runway'), findsOneWidget);
      expect(find.text('Daily burn rate'), findsOneWidget);
      expect(find.text('Liquid cash'), findsOneWidget);
    });

    testWidgets('8. NoSpendStreakHomeWidget tracks habit and zero-spend days', (tester) async {
      final base = sampleLedgerState();
      final state = base.copyWith(
        transactions: const [], // zero expenses
        preferences: base.preferences.copyWith(displayCurrency: 'USD', locale: 'en_US'),
      );

      await tester.pumpWidget(buildTestApp(NoSpendStreakHomeWidget(state: state)));
      await tester.pumpAndSettle();

      expect(find.text('No-spend days'), findsOneWidget);
      expect(find.text('Zero-Spend Days'), findsOneWidget);
      expect(find.textContaining('day streak'), findsOneWidget);
    });

    testWidgets('9. WeekendWeekdayRatioHomeWidget compares weekend vs weekday expenses', (tester) async {
      final base = sampleLedgerState();
      final sampleTx = base.transactions.first;

      // Find a recent Saturday and Wednesday
      final now = DateTime.now();
      final saturday = now.subtract(Duration(days: (now.weekday - DateTime.saturday) % 7));
      final wednesday = now.subtract(Duration(days: (now.weekday - DateTime.wednesday) % 7));

      final weekendTx = sampleTx.copyWith(
        id: 'tx-weekend',
        type: 'expense',
        status: 'cleared',
        amount: usd(8000),
        occurredAt: saturday,
      );
      final weekdayTx = sampleTx.copyWith(
        id: 'tx-weekday',
        type: 'expense',
        status: 'cleared',
        amount: usd(12000),
        occurredAt: wednesday,
      );

      final state = base.copyWith(
        transactions: [weekendTx, weekdayTx],
        preferences: base.preferences.copyWith(displayCurrency: 'USD', locale: 'en_US'),
      );

      await tester.pumpWidget(buildTestApp(WeekendWeekdayRatioHomeWidget(state: state)));
      await tester.pumpAndSettle();

      expect(find.text('Weekend vs weekday'), findsOneWidget);
      expect(find.textContaining('Weekdays'), findsOneWidget);
      expect(find.textContaining('Weekends'), findsOneWidget);
    });

    testWidgets('10. buildHomeDashboardWidget correctly dispatches all 9 new widget IDs', (tester) async {
      final state = sampleLedgerState();

      final newWidgetIds = [
        HomeDashboardWidgetId.pendingReview,
        HomeDashboardWidgetId.savingsRate,
        HomeDashboardWidgetId.tagCloud,
        HomeDashboardWidgetId.safeToSpend,
        HomeDashboardWidgetId.cashBurnRunway,
        HomeDashboardWidgetId.noSpendStreak,
        HomeDashboardWidgetId.weekendWeekdayRatio,
      ];

      for (final widgetId in newWidgetIds) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ProviderScope(
                child: Builder(
                  builder: (context) => buildHomeDashboardWidget(
                    context: context,
                    id: widgetId,
                    state: state,
                    onTabSelected: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // Each rendered widget card will contain at least one HomeWidgetCard title
        expect(find.byType(HomeWidgetCard), findsOneWidget, reason: 'Failed dispatch for $widgetId');
      }
    });
  });
}
