import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/features/calendar/calendar_screen.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

import 'fixtures/sample_ledger.dart';
import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CalendarScreen Day Selection', () {
    testWidgets('desktop view opens centered dialog with close button', (tester) async {
      await initializeDateFormatting();
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final state = sampleLedgerState();

      await tester.pumpWidget(
        ProviderScope(
          overrides: authenticatedSampleOverrides(ledger: state),
          child: MaterialApp(
            home: Scaffold(body: CalendarScreen(onMenuPressed: () {})),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on day 15 cell
      await tester.tap(find.text('15').first);
      await tester.pumpAndSettle();

      // Desktop uses a Dialog, not a ModalBottomSheet
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);

      // Verify close button dismisses dialog
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('mobile view opens constrained bottom sheet', (tester) async {
      await initializeDateFormatting();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final state = sampleLedgerState();

      await tester.pumpWidget(
        ProviderScope(
          overrides: authenticatedSampleOverrides(ledger: state),
          child: MaterialApp(
            home: Scaffold(body: CalendarScreen(onMenuPressed: () {})),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on day 15 cell
      await tester.tap(find.text('15').first);
      await tester.pumpAndSettle();

      // Mobile uses BottomSheet
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('AMOLED theme renders pure black card without GlassCard in sheet', (tester) async {
      await initializeDateFormatting();
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final state = sampleLedgerState();

      await tester.pumpWidget(
        ProviderScope(
          overrides: authenticatedSampleOverrides(ledger: state),
          child: MaterialApp(
            theme: AppTheme.amoled(),
            home: Scaffold(body: CalendarScreen(onMenuPressed: () {})),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on day 15 cell
      await tester.tap(find.text('15').first);
      await tester.pumpAndSettle();

      // In AMOLED mode, the day popup should not wrap in a GlassCard
      final dialogFinder = find.byType(Dialog);
      expect(dialogFinder, findsOneWidget);
      expect(
        find.descendant(of: dialogFinder, matching: find.byType(GlassCard)),
        findsNothing,
      );
    });
  });
}
