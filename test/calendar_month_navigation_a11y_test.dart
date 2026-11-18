import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
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
