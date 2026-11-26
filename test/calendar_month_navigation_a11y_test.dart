import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/design/tokens.dart';
import 'package:one_wallet_flutter/src/features/calendar/calendar_screen.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

import 'test_harness.dart';

/// Accessibility regression coverage for the calendar screen's header
/// controls: the month-navigation chevrons must expose a tooltip, and the
/// "Add record" `HeaderIconButton` (a Liquid Glass button, not a plain
/// `IconButton`) must expose a semantic label instead of relying on a
/// `Tooltip`, since without one `GlassIconButton` announces an empty label.
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
      final semantics = tester.ensureSemantics();
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
      for (final label in ['Previous month', 'Current month', 'Next month']) {
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }

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
      semantics.dispose();
    },
  );

  testWidgets('calendar days announce full dates and preserve privacy', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await initializeDateFormatting();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final state = _ledger().copyWith(
      preferences: const LedgerPreferences(privacyModeEnabled: true),
      accounts: const [
        Account(
          id: 'bank',
          name: 'Bank',
          type: 'bank',
          currency: 'USD',
          openingBalance: Money(amountMinor: 100000, currency: 'USD'),
        ),
      ],
      transactions: [_expense('today', today, 87600)],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: authenticatedSampleOverrides(ledger: state),
        child: MaterialApp(
          home: Scaffold(body: CalendarScreen(onMenuPressed: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final todayLabel = DateFormat.yMMMMEEEEd('en-US').format(today);
    final todayFinder = find.bySemanticsLabel(
      RegExp(RegExp.escape(todayLabel)),
    );
    expect(todayFinder, findsOneWidget);
    final todayData = tester.getSemantics(todayFinder).getSemanticsData();
    expect(todayData.hasAction(SemanticsAction.tap), isTrue);
    expect(todayData.label, contains('•'));
    expect(todayData.label, isNot(contains('876')));

    var month = DateTime(now.year, now.month);
    var first = DateTime(month.year, month.month);
    var last = DateTime(month.year, month.month + 1, 0);
    if (first.weekday % 7 == 0 && last.weekday % 7 == 6) {
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      month = DateTime(month.year, month.month + 1);
      first = DateTime(month.year, month.month);
      last = DateTime(month.year, month.month + 1, 0);
    }
    final adjacent = first.weekday % 7 != 0
        ? DateTime(month.year, month.month, 1 - first.weekday % 7)
        : DateTime(month.year, month.month + 1);
    final adjacentLabel = DateFormat.yMMMMEEEEd('en-US').format(adjacent);
    final adjacentFinder = find.bySemanticsLabel(
      RegExp(RegExp.escape(adjacentLabel)),
    );
    expect(adjacentFinder, findsOneWidget);
    final adjacentNode = tester.getSemantics(adjacentFinder);
    expect(
      adjacentNode.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    tester
        .renderObject(adjacentFinder)
        .owner!
        .semanticsOwner!
        .performAction(adjacentNode.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(
      find.text(DateFormat.yMMMMd('en-US').format(adjacent)),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('past month balance excludes the next month from midnight', (
    tester,
  ) async {
    await initializeDateFormatting();
    final now = DateTime.now();
    final state = _ledger().copyWith(
      accounts: const [
        Account(
          id: 'bank',
          name: 'Bank',
          type: 'bank',
          currency: 'USD',
          openingBalance: Money(amountMinor: 100000, currency: 'USD'),
        ),
      ],
      transactions: [
        _expense('last-day', DateTime(now.year, now.month, 0, 23, 59), 10000),
        _expense('midnight', DateTime(now.year, now.month), 20000),
        _expense('first-day', DateTime(now.year, now.month, 1, 23, 59), 5000),
        _expense('second-day', DateTime(now.year, now.month, 2), 3000),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: authenticatedSampleOverrides(ledger: state),
        child: MaterialApp(
          home: Scaffold(body: CalendarScreen(onMenuPressed: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();

    final balance = tester.widget<SummaryPill>(find.byType(SummaryPill).first);
    expect(balance.money.amountMinor, 90000);
    expect(balance.label, 'Balance');
  });

  testWidgets('day details exclude transactions from the following midnight', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await initializeDateFormatting();
    final now = DateTime.now();
    final day = DateTime(now.year, now.month - 1, 15);
    final state = _ledger().copyWith(
      accounts: const [
        Account(
          id: 'bank',
          name: 'Bank',
          type: 'bank',
          currency: 'USD',
          openingBalance: Money(amountMinor: 100000, currency: 'USD'),
        ),
      ],
      transactions: [
        _expense(
          'target-day',
          DateTime(day.year, day.month, day.day, 23, 59),
          10000,
        ),
        _expense(
          'next-midnight',
          DateTime(day.year, day.month, day.day + 1),
          20000,
        ),
        _expense(
          'next-day',
          DateTime(day.year, day.month, day.day + 1, 12),
          5000,
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: authenticatedSampleOverrides(ledger: state),
        child: MaterialApp(
          home: Scaffold(body: CalendarScreen(onMenuPressed: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    final dayFinder = find.bySemanticsLabel(
      RegExp(RegExp.escape(DateFormat.yMMMMEEEEd('en-US').format(day))),
    );
    final node = tester.getSemantics(dayFinder);
    tester
        .renderObject(dayFinder)
        .owner!
        .semanticsOwner!
        .performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();

    expect(find.text('End-of-day balance'), findsOneWidget);
    expect(find.text('\$900.00'), findsOneWidget);
    semantics.dispose();
  });

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
          theme: AppTheme.light(),
          home: Scaffold(body: CalendarScreen(onMenuPressed: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in ['All categories', 'All accounts']) {
      expect(
        tester
            .renderObject<RenderParagraph>(
              find.descendant(
                of: find.text(label),
                matching: find.byType(RichText),
              ),
            )
            .didExceedMaxLines,
        isFalse,
        reason: label,
      );
    }
    expect(
      tester.getTopLeft(find.text('All accounts')).dy,
      closeTo(tester.getTopLeft(find.text('All categories')).dy, 0.01),
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

  testWidgets(
    'calendar filters stay paired at large text and open their pickers',
    (tester) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: authenticatedSampleOverrides(ledger: _ledger()),
          child: MaterialApp(
            theme: AppTheme.light(),
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
      final category = find.descendant(
        of: find.byTooltip('Filter by category: All categories'),
        matching: find.byType(AppPanel),
      );
      final account = find.descendant(
        of: find.byTooltip('Filter by account: All accounts'),
        matching: find.byType(AppPanel),
      );
      final categoryBounds = tester.getRect(category);
      final accountBounds = tester.getRect(account);
      expect(categoryBounds.top, closeTo(accountBounds.top, 0.01));
      expect(categoryBounds.width, closeTo(accountBounds.width, 0.01));
      expect(categoryBounds.height, closeTo(accountBounds.height, 0.01));
      expect(categoryBounds.height, greaterThanOrEqualTo(48));
      expect(accountBounds.left, greaterThan(categoryBounds.right));
      await tester.ensureVisible(category);
      await tester.pumpAndSettle();
      await tester.tap(category);
      await tester.pumpAndSettle();
      expect(find.text('Calendar categories'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(account);
      await tester.pumpAndSettle();
      expect(find.text('Calendar account'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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

TransactionRecord _expense(String id, DateTime date, int amountMinor) {
  final money = Money(amountMinor: amountMinor, currency: 'USD');
  return TransactionRecord(
    id: id,
    type: 'expense',
    status: 'cleared',
    source: 'manual',
    accountId: 'bank',
    amount: money,
    baseAmount: money,
    occurredAt: date,
  );
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
