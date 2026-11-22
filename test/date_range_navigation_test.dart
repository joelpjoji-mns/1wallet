import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/utils/date_range_utils.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';
import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';

void main() {
  group('Date Range Shifting & Navigation Utils', () {
    final fixedNow = DateTime(2026, 11, 22, 14, 30); // Sunday Nov 22, 2026

    test('shiftDateFilter handles today', () {
      final shiftedPast = shiftDateFilter('today', -1, now: fixedNow);
      expect(shiftedPast, 'custom:2026-11-21..2026-11-21');
      expect(formatCustomDateRangeLabel(shiftedPast, now: fixedNow), 'Yesterday');

      final shiftedFuture = shiftDateFilter(shiftedPast, 1, now: fixedNow);
      expect(shiftedFuture, 'today');
    });

    test('shiftDateFilter handles this_week', () {
      final shiftedPast = shiftDateFilter('this_week', -1, now: fixedNow);
      // Week of Nov 22, 2026 starts Monday Nov 16 to Sunday Nov 22.
      // Previous week starts Monday Nov 09 to Sunday Nov 15.
      expect(shiftedPast, 'custom:2026-11-09..2026-11-15');
      expect(formatCustomDateRangeLabel(shiftedPast, now: fixedNow), 'Last week');

      final shiftedForward = shiftDateFilter(shiftedPast, 1, now: fixedNow);
      expect(shiftedForward, 'this_week');
    });

    test('shiftDateFilter handles this_month', () {
      final shiftedPast = shiftDateFilter('this_month', -1, now: fixedNow);
      expect(shiftedPast, 'custom:2026-10-01..2026-10-31');
      expect(formatCustomDateRangeLabel(shiftedPast, now: fixedNow), 'Last month');

      final shiftedForward = shiftDateFilter(shiftedPast, 1, now: fixedNow);
      expect(shiftedForward, 'this_month');
    });

    test('shiftDateFilter handles this_year', () {
      final shiftedPast = shiftDateFilter('this_year', -1, now: fixedNow);
      expect(shiftedPast, 'custom:2025-01-01..2025-12-31');
      expect(formatCustomDateRangeLabel(shiftedPast, now: fixedNow), 'Last year');

      final shiftedForward = shiftDateFilter(shiftedPast, 1, now: fixedNow);
      expect(shiftedForward, 'this_year');
    });

    test('shiftDateFilter handles 30_days', () {
      final shiftedPast = shiftDateFilter('30_days', -1, now: fixedNow);
      expect(shiftedPast.startsWith('custom:'), isTrue);

      final shiftedForward = shiftDateFilter(shiftedPast, 1, now: fixedNow);
      expect(shiftedForward, '30_days');
    });

    test('shiftDateFilter leaves all untouched', () {
      expect(shiftDateFilter('all', -1, now: fixedNow), 'all');
      expect(shiftDateFilter('all', 1, now: fixedNow), 'all');
    });

    test('shiftDateFilter handles continuous 2+ shifts left and right seamlessly', () {
      // Start from This month (Nov 2026)
      var filter = 'This month';
      // 1st shift left -> Oct 2026
      filter = shiftDateFilter(filter, -1, now: fixedNow);
      expect(filter, 'custom:2026-10-01..2026-10-31');
      expect(formatCustomDateRangeLabel(filter, now: fixedNow), 'Last month');

      // 2nd shift left -> Sep 2026
      filter = shiftDateFilter(filter, -1, now: fixedNow);
      expect(filter, 'custom:2026-09-01..2026-09-30');
      expect(formatCustomDateRangeLabel(filter, now: fixedNow), 'September');

      // 3rd shift left -> Aug 2026
      filter = shiftDateFilter(filter, -1, now: fixedNow);
      expect(filter, 'custom:2026-08-01..2026-08-31');
      expect(formatCustomDateRangeLabel(filter, now: fixedNow), 'August');

      // 1st shift right -> back to Sep 2026
      filter = shiftDateFilter(filter, 1, now: fixedNow);
      expect(filter, 'custom:2026-09-01..2026-09-30');

      // 2nd shift right -> back to Oct 2026
      filter = shiftDateFilter(filter, 1, now: fixedNow);
      expect(filter, 'custom:2026-10-01..2026-10-31');

      // 3rd shift right -> back to current month
      filter = shiftDateFilter(filter, 1, now: fixedNow);
      expect(filter, 'this_month');

      // 4th shift right -> Dec 2026 (future)
      filter = shiftDateFilter(filter, 1, now: fixedNow);
      expect(filter, 'custom:2026-12-01..2026-12-31');
      expect(formatCustomDateRangeLabel(filter, now: fixedNow), 'December');

      // 5th shift right -> Jan 2027
      filter = shiftDateFilter(filter, 1, now: fixedNow);
      expect(filter, 'custom:2027-01-01..2027-01-31');
      expect(formatCustomDateRangeLabel(filter, now: fixedNow), 'Jan 2027');
    });

    test('shiftDateFilter handles continuous 2+ shifts for weeks', () {
      var filter = 'This week';
      // Week of Nov 22, 2026 (Mon Nov 16 .. Sun Nov 22)
      // 1st shift left -> Nov 9 .. Nov 15
      filter = shiftDateFilter(filter, -1, now: fixedNow);
      expect(filter, 'custom:2026-11-09..2026-11-15');
      expect(formatCustomDateRangeLabel(filter, now: fixedNow), 'Last week');

      // 2nd shift left -> Nov 2 .. Nov 8
      filter = shiftDateFilter(filter, -1, now: fixedNow);
      expect(filter, 'custom:2026-11-02..2026-11-08');
      expect(formatCustomDateRangeLabel(filter, now: fixedNow), 'Nov 2 – Nov 8, 2026');

      // 3rd shift left -> Oct 26 .. Nov 1
      filter = shiftDateFilter(filter, -1, now: fixedNow);
      expect(filter, 'custom:2026-10-26..2026-11-01');

      // Shift back 3 times to This week
      filter = shiftDateFilter(filter, 1, now: fixedNow);
      expect(filter, 'custom:2026-11-02..2026-11-08');
      filter = shiftDateFilter(filter, 1, now: fixedNow);
      expect(filter, 'custom:2026-11-09..2026-11-15');
      filter = shiftDateFilter(filter, 1, now: fixedNow);
      expect(filter, 'this_week');
    });
  });

  group('GlassDropdownPill with Arrow and Swipe Navigation', () {
    testWidgets('renders left and right arrows and responds to taps and swipes', (tester) async {
      int prevCalls = 0;
      int nextCalls = 0;
      String currentVal = 'this_week';

      final container = ProviderContainer(
        overrides: [
          ledgerProvider.overrideWith(
            (ref) => LedgerControllerFake(
              emptyLedgerState().copyWith(
                preferences: const LedgerPreferences(
                  baseCurrency: 'USD',
                  displayCurrency: 'USD',
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return GlassDropdownPill<String>(
                    value: currentVal,
                    options: const [
                      GlassDropdownOption('today', 'Today'),
                      GlassDropdownOption('this_week', 'This week'),
                      GlassDropdownOption('this_month', 'This month'),
                    ],
                    onChanged: (val) => setState(() => currentVal = val),
                    onPrevious: () => prevCalls++,
                    onNext: () => nextCalls++,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Chevrons should be visible
      expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);

      // Tap left chevron
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      expect(prevCalls, 1);

      // Tap right chevron
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
      expect(nextCalls, 1);

      // Swipe right (from left to right) -> triggers previous
      await tester.fling(find.text('This week'), const Offset(200, 0), 1000);
      await tester.pumpAndSettle();
      expect(prevCalls, 2);

      // 2nd swipe right -> triggers previous again (testing consecutive swipes!)
      await tester.fling(find.text('This week'), const Offset(200, 0), 1000);
      await tester.pumpAndSettle();
      expect(prevCalls, 3);

      // 3rd swipe right -> triggers previous again
      await tester.fling(find.text('This week'), const Offset(200, 0), 1000);
      await tester.pumpAndSettle();
      expect(prevCalls, 4);

      // Swipe left (from right to left) -> triggers next
      await tester.fling(find.text('This week'), const Offset(-200, 0), 1000);
      await tester.pumpAndSettle();
      expect(nextCalls, 2);

      // 2nd swipe left -> triggers next again
      await tester.fling(find.text('This week'), const Offset(-200, 0), 1000);
      await tester.pumpAndSettle();
      expect(nextCalls, 3);

      // 3rd swipe left -> triggers next again
      await tester.fling(find.text('This week'), const Offset(-200, 0), 1000);
      await tester.pumpAndSettle();
      expect(nextCalls, 4);

      // Consecutive taps on chevrons
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      expect(prevCalls, 5);

      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      expect(prevCalls, 6);

      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
      expect(nextCalls, 5);

      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
      expect(nextCalls, 6);
    });
  });
}

class LedgerControllerFake extends StateNotifier<LedgerState>
    implements LedgerController {
  LedgerControllerFake(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
