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

      // Swipe left (from right to left) -> triggers next
      await tester.fling(find.text('This week'), const Offset(-200, 0), 1000);
      await tester.pumpAndSettle();
      expect(nextCalls, 2);
    });
  });
}

class LedgerControllerFake extends StateNotifier<LedgerState>
    implements LedgerController {
  LedgerControllerFake(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
