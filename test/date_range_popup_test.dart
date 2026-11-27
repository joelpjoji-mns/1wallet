import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/widgets/date_range_popup.dart';

void main() {
  Future<BuildContext> pumpHost(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext hostContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    return hostContext;
  }

  Finder day(int year, int month, int day) =>
      find.byKey(ValueKey('date-range-day-$year-$month-$day'));

  testWidgets('opens as a compact dialog, not a full-screen page', (
    tester,
  ) async {
    final hostContext = await pumpHost(tester);
    showAppDateRangePicker(
      context: hostContext,
      initialDateRange: DateTimeRange(
        start: DateTime(2026, 3, 4),
        end: DateTime(2026, 3, 9),
      ),
    );
    await tester.pumpAndSettle();

    final popup = find.byKey(const ValueKey('date-range-popup'));
    expect(popup, findsOneWidget);
    expect(find.byType(DateRangePickerDialog), findsNothing);
    final size = tester.getSize(
      find.descendant(of: popup, matching: find.byType(Material)).first,
    );
    expect(size.height, lessThan(844 * 0.75));
    expect(size.width, lessThan(390));
    expect(find.text('March 2026'), findsOneWidget);
    expect(find.text('Mar 4 – Mar 9, 2026'), findsOneWidget);
    final band = find.byKey(const ValueKey('date-range-band-2026-3-6'));
    expect(band, findsOneWidget);
    expect(tester.getSize(band).height, greaterThan(20));
    final clear = tester.getSize(
      find.byKey(const ValueKey('date-range-clear')),
    );
    final cancel = tester.getSize(
      find.byKey(const ValueKey('date-range-cancel')),
    );
    final apply = tester.getSize(
      find.byKey(const ValueKey('date-range-apply')),
    );
    expect(cancel, clear);
    expect(apply, clear);
  });

  testWidgets('selects across months and restarts on an earlier day', (
    tester,
  ) async {
    final hostContext = await pumpHost(tester);
    DateTimeRange? result;
    showAppDateRangePicker(
      context: hostContext,
      initialDateRange: DateTimeRange(
        start: DateTime(2026, 3, 1),
        end: DateTime(2026, 3, 2),
      ),
    ).then((value) => result = value);
    await tester.pumpAndSettle();

    await tester.tap(day(2026, 3, 20));
    await tester.pump();
    await tester.tap(day(2026, 3, 10));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('date-range-next-month')));
    await tester.pumpAndSettle();
    await tester.tap(day(2026, 4, 5));
    await tester.pump();
    expect(find.text('Mar 10 – Apr 5, 2026'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('date-range-apply')));
    await tester.pumpAndSettle();
    expect(
      result,
      DateTimeRange(start: DateTime(2026, 3, 10), end: DateTime(2026, 4, 5)),
    );
    expect(find.byKey(const ValueKey('date-range-popup')), findsNothing);
  });

  testWidgets('one tapped day applies a one-day range; cancel returns null', (
    tester,
  ) async {
    final hostContext = await pumpHost(tester);
    final results = <DateTimeRange?>[];
    showAppDateRangePicker(
      context: hostContext,
      initialDateRange: DateTimeRange(
        start: DateTime(2026, 5, 1),
        end: DateTime(2026, 5, 3),
      ),
    ).then(results.add);
    await tester.pumpAndSettle();
    await tester.tap(day(2026, 5, 14));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('date-range-apply')));
    await tester.pumpAndSettle();
    expect(
      results.single,
      DateTimeRange(start: DateTime(2026, 5, 14), end: DateTime(2026, 5, 14)),
    );

    showAppDateRangePicker(context: hostContext).then(results.add);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(results, hasLength(2));
    expect(results.last, isNull);
  });
}
