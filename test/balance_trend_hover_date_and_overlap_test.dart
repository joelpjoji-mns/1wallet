import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
