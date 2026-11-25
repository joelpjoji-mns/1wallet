// Regression tests for two loan-form bugs fixed in loans_screen.dart:
//   1. The "Tenure count" field had no validation, so a non-positive value
//      (e.g. 0, or a pasted negative number) was silently saved and produced
//      nonsensical payoff projections. `_saveLoan` now rejects it with a
//      clear inline SnackBar and never calls the notifier.
//   2. The "Create loan" button had no re-entrancy guard, so a fast double
//      tap while the async save was in flight could create two loan
//      accounts. `_saveLoan` now disables the button / ignores re-entrant
//      calls via an `_isSaving` flag.
import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/loans/loans_screen.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('forecast axes fit compact currency labels at large text sizes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dates = List.generate(6, (index) => DateTime(2026, index + 1));
    for (final (isBar, scale, isPrivate) in [
      (false, 1.0, false),
      (false, 2.0, true),
      (true, 1.0, false),
      (true, 2.0, true),
    ]) {
      final chart = isBar
          ? DynamicForecastBarChart(
              key: ValueKey('$isBar-$scale-$isPrivate'),
              barGroups: List.generate(
                dates.length,
                (index) => BarChartGroupData(
                  x: index,
                  barRods: [BarChartRodData(toY: 4000000 + index * 1000000)],
                ),
              ),
              chartWidth: 280,
              timeKeys: dates,
              locale: 'en_IN',
              currencySymbol: '\u20b9',
              isPrivate: isPrivate,
            )
          : DynamicForecastLineChart(
              key: ValueKey('$isBar-$scale-$isPrivate'),
              spots: const [FlSpot(0, 1234567), FlSpot(30, 9876543)],
              chartWidth: 280,
              lineColor: Colors.blue,
              balanceCurve: const [],
              locale: 'en_IN',
              payoffDots: const {},
              currencySymbol: '\u20b9',
              isPrivate: isPrivate,
            );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 280, height: 380, child: chart),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final chartFinder = isBar
          ? find.byType(BarChart)
          : find.byType(LineChart);
      final labels = find.descendant(
        of: chartFinder,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Text && (widget.data?.contains('\u20b9') ?? false),
        ),
      );
      expect(labels, findsWidgets);
      for (var i = 0; i < labels.evaluate().length; i++) {
        final label = labels.at(i);
        final paragraph = tester.renderObject<RenderParagraph>(label);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(
          paragraph.size.width + 0.01,
          greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity)),
        );
        if (isPrivate) {
          expect(
            tester.widget<Text>(label).data,
            isNot(contains(RegExp(r'\d'))),
          );
        }
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('zoomed forecast labels stay distinct and controls stay clear', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dates = List.generate(6, (index) => DateTime(2026, index + 1));
    for (final (isBar, scale, locale, symbol) in [
      (false, 1.0, 'en_IN', '\u20b9'),
      (false, 2.0, 'en_IN', '\u20b9'),
      (true, 1.0, 'en_IN', '\u20b9'),
      (true, 2.0, 'en_IN', '\u20b9'),
      (false, 1.0, 'en_US', r'$'),
      (true, 2.0, 'en_US', r'$'),
    ]) {
      final chart = isBar
          ? DynamicForecastBarChart(
              key: ValueKey('$isBar-$scale-$locale'),
              barGroups: List.generate(
                dates.length,
                (index) => BarChartGroupData(
                  x: index,
                  barRods: [BarChartRodData(toY: 12300000 + index * 200)],
                ),
              ),
              chartWidth: 280,
              timeKeys: dates,
              locale: locale,
              currencySymbol: symbol,
            )
          : DynamicForecastLineChart(
              key: ValueKey('$isBar-$scale-$locale'),
              spots: const [
                FlSpot(0, 12300000),
                FlSpot(100, 12301000),
                FlSpot(200, 12302000),
              ],
              chartWidth: 280,
              lineColor: Colors.blue,
              balanceCurve: const [],
              locale: locale,
              payoffDots: const {},
              currencySymbol: symbol,
            );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 280, height: 380, child: chart),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final chartFinder = isBar
          ? find.byType(BarChart)
          : find.byType(LineChart);

      void expectDistinctLabels() {
        final labels = find.descendant(
          of: chartFinder,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Text && (widget.data?.contains(symbol) ?? false),
          ),
        );
        final texts = tester.widgetList<Text>(labels).map((text) => text.data);
        expect(texts.length, greaterThan(1));
        expect(texts.toSet(), hasLength(texts.length));
        final rects = [
          for (var i = 0; i < labels.evaluate().length; i++)
            tester.getRect(labels.at(i)),
        ];
        for (var i = 0; i < rects.length; i++) {
          final paragraph = tester.renderObject<RenderParagraph>(labels.at(i));
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(
            paragraph.size.width + 0.01,
            greaterThanOrEqualTo(
              paragraph.getMaxIntrinsicWidth(double.infinity),
            ),
          );
          for (var j = i + 1; j < rects.length; j++) {
            expect(rects[i].overlaps(rects[j]), isFalse);
          }
        }
      }

      void expectReadableDates() {
        final dateLabels = find.descendant(
          of: chartFinder,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                (widget.data != null) &&
                RegExp(
                  r'^(\d{2} [A-Za-z]{3}|[A-Za-z]{3} \d{2}|\d{4})$',
                ).hasMatch(widget.data!),
          ),
        );
        expect(dateLabels, findsWidgets);
        final dateRects = [
          for (var i = 0; i < dateLabels.evaluate().length; i++)
            tester.getRect(dateLabels.at(i)),
        ];
        for (var i = 0; i < dateRects.length; i++) {
          final paragraph = tester.renderObject<RenderParagraph>(
            dateLabels.at(i),
          );
          expect(paragraph.didExceedMaxLines, isFalse);
          for (var j = i + 1; j < dateRects.length; j++) {
            expect(
              dateRects[i].overlaps(dateRects[j]),
              isFalse,
              reason: 'bar=$isBar scale=$scale dates=$dateRects',
            );
          }
        }
      }

      expectDistinctLabels();
      expectReadableDates();
      if (!isBar) {
        final zoom = find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Zoom in',
        );
        final zoomRect = tester.getRect(zoom);
        expect(zoomRect.shortestSide, greaterThanOrEqualTo(48));
        expect(
          zoomRect.top,
          greaterThanOrEqualTo(tester.getRect(chartFinder).bottom),
        );
        final before = tester.widget<LineChart>(chartFinder).data;
        await tester.tap(zoom);
        await tester.pumpAndSettle();
        final after = tester.widget<LineChart>(chartFinder).data;
        expect(after.maxX - after.minX, lessThan(before.maxX - before.minX));
        expectDistinctLabels();
        expectReadableDates();
        final reset = find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == 'Reset view',
        );
        await tester.tap(reset);
        await tester.pumpAndSettle();
        final restored = tester.widget<LineChart>(chartFinder).data;
        expect(restored.maxX - restored.minX, before.maxX - before.minX);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('sub-unit forecast ranges retain readable currency ticks', (
    tester,
  ) async {
    final dates = List.generate(6, (index) => DateTime(2026, index + 1));
    for (final isBar in [false, true]) {
      final chart = isBar
          ? DynamicForecastBarChart(
              barGroups: List.generate(
                dates.length,
                (index) => BarChartGroupData(
                  x: index,
                  barRods: [BarChartRodData(toY: 123 + index * 0.01)],
                ),
              ),
              chartWidth: 280,
              timeKeys: dates,
              locale: 'en_US',
              currencySymbol: r'$',
            )
          : const DynamicForecastLineChart(
              spots: [FlSpot(0, 123), FlSpot(100, 123.02)],
              chartWidth: 280,
              lineColor: Colors.blue,
              balanceCurve: [],
              locale: 'en_US',
              payoffDots: {},
              currencySymbol: r'$',
            );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 280, height: 380, child: chart),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final labels = find.descendant(
        of: isBar ? find.byType(BarChart) : find.byType(LineChart),
        matching: find.byWidgetPredicate(
          (widget) => widget is Text && (widget.data?.contains(r'$') ?? false),
        ),
      );
      final values = tester.widgetList<Text>(labels).map((text) => text.data);
      expect(values.length, greaterThan(1));
      expect(values.toSet(), hasLength(values.length));
      expect(tester.takeException(), isNull);
    }
  });

  // A router scoped to just the loans feature (rather than the full app
  // router) so this test only compiles/exercises loans_screen.dart and its
  // direct dependencies.
  GoRouter buildLoansOnlyRouter() {
    return GoRouter(
      initialLocation: '/loans',
      routes: [
        GoRoute(
          path: '/loans',
          builder: (context, state) => const LoansScreen(),
        ),
        GoRoute(
          path: '/loans/new',
          builder: (context, state) => const LoansScreen(mode: 'new'),
        ),
      ],
    );
  }

  Future<ProviderContainer> pumpLoanForm(
    WidgetTester tester, {
    Size size = const Size(1080, 2400),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await initializeDateFormatting('en_IN');
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(prefs: prefs),
    );
    addTearDown(container.dispose);
    final router = buildLoansOnlyRouter();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          // NoSplash avoids the ink_sparkle shader (unavailable in the test
          // environment) so button taps don't trigger flaky asset errors.
          theme: ThemeData(
            useMaterial3: true,
            splashFactory: NoSplash.splashFactory,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    router.go('/loans/new');
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('loan amount inputs stack on a narrow phone', (tester) async {
    await pumpLoanForm(tester, size: const Size(360, 780));
    Finder field(String placeholder) => find.byWidgetPredicate(
      (widget) => widget is GlassTextField && widget.placeholder == placeholder,
    );
    final principal = tester.getRect(field('Original Principal'));
    final balance = tester.getRect(field('Current Balance'));
    expect(principal.width, greaterThan(200));
    expect(balance.width, greaterThan(200));
    expect(balance.top, greaterThan(principal.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejects a non-positive tenure instead of silently saving it', (
    tester,
  ) async {
    final container = await pumpLoanForm(tester);
    final loansBefore = container.read(ledgerProvider).accounts.length;

    await tester.enterText(find.byType(CupertinoTextField).at(0), 'Bike Loan');
    await tester.enterText(find.byType(CupertinoTextField).at(2), '50000');
    // 0 is a valid *digit* (so it passes the digits-only input formatter)
    // but is not a valid tenure length.
    await tester.enterText(find.byType(CupertinoTextField).at(6), '0');
    await tester.pumpAndSettle();

    final saveButton = find.bySemanticsLabel('Save');
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(
      find.text('Tenure must be a positive number of payments.'),
      findsOneWidget,
    );
    expect(
      container.read(ledgerProvider).accounts.length,
      loansBefore,
      reason: 'An invalid tenure must not reach the ledger notifier.',
    );
  });

  testWidgets('the negative sign cannot even be typed into the tenure field', (
    tester,
  ) async {
    await pumpLoanForm(tester);

    await tester.enterText(find.byType(CupertinoTextField).at(6), '-12');
    await tester.pumpAndSettle();

    final field = tester.widget<CupertinoTextField>(
      find.byType(CupertinoTextField).at(6),
    );
    expect(field.controller?.text, '12');
  });

  testWidgets('double-tapping Create loan only creates a single loan account', (
    tester,
  ) async {
    final container = await pumpLoanForm(tester);
    final loansBefore = container
        .read(ledgerProvider)
        .accounts
        .where((a) => a.type == 'loan')
        .length;

    await tester.enterText(
      find.byType(CupertinoTextField).at(0),
      'Double Tap Loan',
    );
    await tester.enterText(find.byType(CupertinoTextField).at(2), '75000');
    await tester.pumpAndSettle();

    final saveButton = find.byType(HeaderSaveAction);
    // Invoke onPressed twice back-to-back with no await in between, so
    // both calls run before the (fast, in-memory) ledger notifier gets a
    // chance to resolve the first save. This is what a real double-tap
    // race looks like: `_saveLoan` must reject the re-entrant call via
    // its `_isSaving` guard rather than relying on timing. (Two
    // sequential `await tester.tap(...)` calls don't reproduce the race:
    // the mocked ledger resolves fast enough that the first save fully
    // completes before the second tap is even dispatched.)
    final onPressed = tester.widget<HeaderSaveAction>(saveButton).onPressed;
    unawaited(onPressed());
    unawaited(onPressed());
    await tester.pumpAndSettle();

    final loansAfter = container
        .read(ledgerProvider)
        .accounts
        .where((a) => a.type == 'loan' && a.name == 'Double Tap Loan')
        .length;
    expect(loansAfter, 1);
    expect(
      container
          .read(ledgerProvider)
          .accounts
          .where((a) => a.type == 'loan')
          .length,
      loansBefore + 1,
    );
  });
}
