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

  testWidgets(
    'header Add record button exposes a semantic label for screen readers',
    (tester) async {
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

      // `find.byType(HeaderIconButton)` resolves to that widget's own
      // (unlabeled) render object; the semantic label actually lives on a
      // nested `Semantics` node further down inside `GlassIconButton`, so
      // search the semantics tree directly by label instead.
      expect(find.bySemanticsLabel('Add record'), findsOneWidget);

      handle.dispose();
    },
  );
}

LedgerState _ledger() {
  return LedgerState(
    version: currentLedgerStateVersion,
    userId: 'test-user',
    preferences: const LedgerPreferences(),
    accounts: const [],
    categories: const [],
    transactions: const [],
    captureCandidates: const [],
  );
}
