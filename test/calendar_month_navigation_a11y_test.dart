import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/design/tokens.dart';
import 'package:one_wallet_flutter/src/features/calendar/calendar_screen.dart';

import 'test_harness.dart';

/// Accessibility regression coverage for the calendar screen's header
/// controls: the month-navigation chevrons must expose a tooltip, and the
/// "Add record" `HeaderIconButton` (a Liquid Glass button, not a plain
/// `IconButton`) must expose a semantic label instead of relying on a
/// `Tooltip`, since without one `GlassIconButton` announces an empty label.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('last calendar days can scroll above an undocked action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await initializeDateFormatting();
    const actionKey = ValueKey('floating-add');
    await tester.pumpWidget(
      ProviderScope(
        overrides: authenticatedSampleOverrides(ledger: _ledger()),
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Stack(
              children: [
                CalendarScreen(onMenuPressed: () {}),
                const Positioned(
                  right: 14,
                  bottom: AppSizes.bottomBarClearance,
                  child: SizedBox(
                    key: actionKey,
                    width: AppSizes.islandActionSize,
                    height: AppSizes.islandActionSize,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    );
    scroll.position.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final lastDay = find
        .descendant(
          of: find.byType(SliverFillRemaining),
          matching: find.byType(InkWell),
        )
        .last;
    expect(
      tester.getBottomLeft(lastDay).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byKey(actionKey)).dy),
    );
    await tester.tap(lastDay);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'month navigation buttons expose accessible tooltips and update the '
    'visible month',
    (tester) async {
      await initializeDateFormatting();

      final now = DateTime.now();
      final state = _ledger();

      await tester.pumpWidget(
        ProviderScope(
          overrides: authenticatedSampleOverrides(ledger: state),
          child: MaterialApp(
            home: Scaffold(body: CalendarScreen(onMenuPressed: () {})),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Previous month'), findsOneWidget);
      expect(find.byTooltip('Next month'), findsOneWidget);

      final currentMonthLabel = DateFormat.yMMMM().format(
        DateTime(now.year, now.month),
      );
      expect(find.text(currentMonthLabel), findsOneWidget);

      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();

      final nextMonthLabel = DateFormat.yMMMM().format(
        DateTime(now.year, now.month + 1),
      );
      expect(find.text(nextMonthLabel), findsOneWidget);
      expect(find.text(currentMonthLabel), findsNothing);

      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();

      expect(find.text(currentMonthLabel), findsOneWidget);
    },
  );

  testWidgets('calendar has no duplicate header Add record action', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final state = _ledger();

    await tester.pumpWidget(
      ProviderScope(
        overrides: authenticatedSampleOverrides(ledger: state),
        child: MaterialApp(
          home: Scaffold(body: CalendarScreen(onMenuPressed: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // MainShell owns the fixed add action; Calendar no longer duplicates it
    // in the page header.
    expect(find.bySemanticsLabel('Add record'), findsNothing);

    handle.dispose();
  });

  testWidgets('calendar scrolls to the full month on a compact screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: authenticatedSampleOverrides(ledger: _ledger()),
        child: MaterialApp(
          home: Scaffold(body: CalendarScreen(onMenuPressed: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in ['All categories', 'Filter by category']) {
      expect(
        tester
            .renderObject<RenderParagraph>(find.text(label))
            .didExceedMaxLines,
        isFalse,
        reason: label,
      );
    }
    expect(tester.getSize(find.text('All categories')).width, greaterThan(140));
    expect(
      tester.getTopLeft(find.text('All accounts')).dy,
      greaterThan(tester.getBottomLeft(find.text('All categories')).dy),
    );
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text gives the calendar heading and totals enough width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await initializeDateFormatting();
    await tester.pumpWidget(
      ProviderScope(
        overrides: authenticatedSampleOverrides(ledger: _ledger()),
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(body: CalendarScreen(onMenuPressed: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final month = DateFormat.yMMMM().format(DateTime.now());
    expect(
      tester.getTopLeft(find.byTooltip('Previous month')).dy,
      greaterThan(tester.getBottomLeft(find.text(month)).dy),
    );
    final totals = find.byType(SummaryPill);
    expect(totals, findsNWidgets(3));
    expect(tester.getSize(totals.first).width, greaterThan(250));
    expect(
      tester.getTopLeft(totals.at(1)).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(totals.first).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'calendar month navigation icons do not hardcode white and adapt to light theme',
    (tester) async {
      final state = _ledger();

      await tester.pumpWidget(
        ProviderScope(
          overrides: authenticatedSampleOverrides(ledger: state),
          child: MaterialApp(
            theme: ThemeData.light(),
            home: Scaffold(body: CalendarScreen(onMenuPressed: () {})),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final prevIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byTooltip('Previous month'),
          matching: find.byType(Icon),
        ),
      );
      final nextIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byTooltip('Next month'),
          matching: find.byType(Icon),
        ),
      );
      final todayIcon = tester.widget<Icon>(
        find.descendant(
          of: find.byTooltip('Current month'),
          matching: find.byType(Icon),
        ),
      );

      // Icons should not have hardcoded white color so they can inherit
      // theme/legibility color in light theme
      expect(prevIcon.color, isNot(Colors.white));
      expect(nextIcon.color, isNot(Colors.white));
      expect(todayIcon.color, isNot(Colors.white));
      expect(prevIcon.color, ThemeData.light().colorScheme.onSurface);
      expect(nextIcon.color, ThemeData.light().colorScheme.onSurface);
      expect(todayIcon.color, ThemeData.light().colorScheme.onSurface);
    },
  );

  testWidgets('calendar month navigation icons adapt to dark theme', (
    tester,
  ) async {
    final state = _ledger();
    final darkTheme = ThemeData.dark();

    await tester.pumpWidget(
      ProviderScope(
        overrides: authenticatedSampleOverrides(ledger: state),
        child: MaterialApp(
          theme: darkTheme,
          home: Scaffold(body: CalendarScreen(onMenuPressed: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final prevIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byTooltip('Previous month'),
        matching: find.byType(Icon),
      ),
    );
    final nextIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byTooltip('Next month'),
        matching: find.byType(Icon),
      ),
    );
    final todayIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byTooltip('Current month'),
        matching: find.byType(Icon),
      ),
    );

    expect(prevIcon.color, darkTheme.colorScheme.onSurface);
    expect(nextIcon.color, darkTheme.colorScheme.onSurface);
    expect(todayIcon.color, darkTheme.colorScheme.onSurface);
  });
}

LedgerState _ledger() {
  return const LedgerState(
    version: currentLedgerStateVersion,
    userId: 'test-user',
    preferences: LedgerPreferences(),
    accounts: [],
    categories: [],
    transactions: [],
    captureCandidates: [],
  );
}
