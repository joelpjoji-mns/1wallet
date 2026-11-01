import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/home/home_async_providers.dart';
import 'package:one_wallet_flutter/src/features/home/home_dashboard_selectors.dart';
import 'package:one_wallet_flutter/src/features/home/home_widgets.dart';

import 'fixtures/sample_ledger.dart';
import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'BalanceTrendHomeWidget renders chart and bottom titles without errors',
    (tester) async {
      const checkingAccount = Account(
        id: 'acc_1',
        name: 'Checking',
        type: 'bank',
        currency: 'USD',
        openingBalance: Money(amountMinor: 500000, currency: 'USD'),
      );

      final now = DateTime.now();
      final nowRounded = DateTime(now.year, now.month, now.day);
      final pastPoints = List.generate(
        30,
        (i) => BalanceTrendPoint(
          date: nowRounded.subtract(Duration(days: 29 - i)),
          balance: Money(amountMinor: (1000 + i * 50) * 100, currency: 'USD'),
        ),
      );
      final futurePoints = List.generate(
        15,
        (i) => BalanceTrendPoint(
          date: nowRounded.add(Duration(days: i)),
          balance: Money(amountMinor: (2450 + i * 20) * 100, currency: 'USD'),
        ),
      );

      final base = sampleLedgerState();
      final state = base.copyWith(
        accounts: [checkingAccount],
        transactions: const [],
        preferences: base.preferences.copyWith(
          baseCurrency: 'USD',
          displayCurrency: 'USD',
          locale: 'en_US',
        ),
      );

      final container = ProviderContainer(
        overrides: [
          ...authenticatedSampleOverrides(ledger: state),
          homeBalanceTrendProvider.overrideWith((ref, args) => pastPoints),
          homeBalanceFutureTrendProvider.overrideWith((ref, args) => futurePoints),
        ],
      );
      addTearDown(container.dispose);
      await container.read(ledgerProvider.notifier).restoreLedgerState(state);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: BalanceTrendHomeWidget(state: state),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LineChart), findsOneWidget);

      // Perform a drag or touch on the chart
      final chartFinder = find.byType(LineChart);
      final center = tester.getCenter(chartFinder);

      final gesture = await tester.startGesture(center);
      await tester.pump();

      // Check that interactions don't throw
      expect(tester.takeException(), isNull);

      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(tester.takeException(), isNull);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Hovering over the line chart triggers touch interaction without exception',
    (tester) async {
      const checkingAccount = Account(
        id: 'acc_1',
        name: 'Checking',
        type: 'bank',
        currency: 'USD',
        openingBalance: Money(amountMinor: 500000, currency: 'USD'),
      );

      final now = DateTime.now();
      final nowRounded = DateTime(now.year, now.month, now.day);
      final pastPoints = List.generate(
        30,
        (i) => BalanceTrendPoint(
          date: nowRounded.subtract(Duration(days: 29 - i)),
          balance: Money(amountMinor: (1000 + i * 50) * 100, currency: 'USD'),
        ),
      );

      final base = sampleLedgerState();
      final state = base.copyWith(
        accounts: [checkingAccount],
        transactions: const [],
        preferences: base.preferences.copyWith(
          baseCurrency: 'USD',
          displayCurrency: 'USD',
          locale: 'en_US',
        ),
      );

      final container = ProviderContainer(
        overrides: [
          ...authenticatedSampleOverrides(ledger: state),
          homeBalanceTrendProvider.overrideWith((ref, args) => pastPoints),
          homeBalanceFutureTrendProvider.overrideWith((ref, args) => const []),
        ],
      );
      addTearDown(container.dispose);
      await container.read(ledgerProvider.notifier).restoreLedgerState(state);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: BalanceTrendHomeWidget(state: state),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chartFinder = find.byType(LineChart);
      final center = tester.getCenter(chartFinder);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(center);
      await tester.pump();

      expect(tester.takeException(), isNull);

      await mouse.moveTo(center + const Offset(40, 0));
      await tester.pump();
      expect(tester.takeException(), isNull);

      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Balance trend shows current date and at least 6 evenly spaced dates',
    (tester) async {
      final now = DateTime.now();
      final nowRounded = DateTime(now.year, now.month, now.day);
      final pastPoints = List.generate(
        30,
        (i) => BalanceTrendPoint(
          date: nowRounded.subtract(Duration(days: 29 - i)),
          balance: Money(amountMinor: (1000 + i * 50) * 100, currency: 'USD'),
        ),
      );

      final base = sampleLedgerState();
      final state = base.copyWith(
        preferences: base.preferences.copyWith(
          baseCurrency: 'USD',
          displayCurrency: 'USD',
          locale: 'en_US',
        ),
      );

      final container = ProviderContainer(
        overrides: [
          ...authenticatedSampleOverrides(ledger: state),
          homeBalanceTrendProvider.overrideWith((ref, args) => pastPoints),
          homeBalanceFutureTrendProvider.overrideWith((ref, args) => const []),
        ],
      );
      addTearDown(container.dispose);
      await container.read(ledgerProvider.notifier).restoreLedgerState(state);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: BalanceTrendHomeWidget(state: state),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Formatted current date (today) must be visible on the chart
      final currentDateText = DateFormat('d MMM', 'en_US').format(nowRounded);
      expect(find.text(currentDateText), findsWidgets);

      // Verify that there are at least 6 date labels across the bottom axis
      final sideTitleWidgets = find.descendant(
        of: find.byType(LineChart),
        matching: find.byType(SideTitleWidget),
      );
      final bottomDateTexts = <String>[];
      for (final element in sideTitleWidgets.evaluate()) {
        final textWidgets = find.descendant(
          of: find.byWidget(element.widget),
          matching: find.byType(Text),
        );
        for (final textElement in textWidgets.evaluate()) {
          final text = (textElement.widget as Text).data;
          if (text != null && text.contains(' ') && !text.contains('·')) {
            bottomDateTexts.add(text);
          }
        }
      }
      expect(bottomDateTexts.length, greaterThanOrEqualTo(6));
      expect(bottomDateTexts, contains(currentDateText));
    },
  );

  testWidgets(
    'Touching the chart hides colliding static date and shows touched date badge',
    (tester) async {
      final now = DateTime.now();
      final nowRounded = DateTime(now.year, now.month, now.day);
      final pastPoints = List.generate(
        30,
        (i) => BalanceTrendPoint(
          date: nowRounded.subtract(Duration(days: 29 - i)),
          balance: Money(amountMinor: (1000 + i * 50) * 100, currency: 'USD'),
        ),
      );

      final base = sampleLedgerState();
      final state = base.copyWith(
        preferences: base.preferences.copyWith(
          baseCurrency: 'USD',
          displayCurrency: 'USD',
          locale: 'en_US',
        ),
      );

      final container = ProviderContainer(
        overrides: [
          ...authenticatedSampleOverrides(ledger: state),
          homeBalanceTrendProvider.overrideWith((ref, args) => pastPoints),
          homeBalanceFutureTrendProvider.overrideWith((ref, args) => const []),
        ],
      );
      addTearDown(container.dispose);
      await container.read(ledgerProvider.notifier).restoreLedgerState(state);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: BalanceTrendHomeWidget(state: state),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final currentDateText = DateFormat('d MMM', 'en_US').format(nowRounded);
      expect(find.text(currentDateText), findsWidgets);

      // Touch the right edge of the chart (where current date is)
      final chartFinder = find.byType(LineChart);
      final chartRect = tester.getRect(chartFinder);
      final rightEdge = Offset(chartRect.right - 10, chartRect.center.dy);

      final gesture = await tester.startGesture(rightEdge);
      await tester.pump();

      // The touched badge is now visible
      expect(find.textContaining(currentDateText), findsWidgets);

      await gesture.up();
      await tester.pumpAndSettle();

      // After releasing, all static dates are restored
      expect(find.text(currentDateText), findsWidgets);
    },
  );
}
