import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/design/tokens.dart';
import 'package:one_wallet_flutter/src/routing/app_router.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

import 'test_harness.dart';

const _emptyLedger = LedgerState(
  version: 14,
  userId: 'empty-test-user',
  preferences: LedgerPreferences(),
  accounts: [],
  categories: [],
  transactions: [],
  captureCandidates: [],
);

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpTab(
  WidgetTester tester, {
  required Size size,
  required double textScale,
  required int tab,
  LedgerState? ledger,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: authenticatedSampleOverrides(prefs: prefs, ledger: ledger),
  );
  addTearDown(container.dispose);
  final router = container.read(appRouterProvider);
  router.go('/?tab=$tab');
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router, theme: AppTheme.light()),
    ),
  );
  await _settle(tester);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_IN');
    final inter = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await inter.load();
  });

  testWidgets('EmptyState is centered within its parent container', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: AppTopFadeMask(
              child: EmptyState(
                icon: Icons.search_off_rounded,
                title: 'No matching transactions',
                body: 'Clear filters to see the full ledger.',
                actionLabel: 'Clear filters',
                onAction: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final titleFinder = find.text('No matching transactions');
    expect(titleFinder, findsOneWidget);

    final emptyStateFinder = find.byType(EmptyState);
    final emptyStateCenter = tester.getCenter(emptyStateFinder);

    // Parent center is (400, 300)
    expect(emptyStateCenter.dx, equals(400.0));
    expect(emptyStateCenter.dy, equals(300.0));

    // Clear filters uses filter_alt_off_rounded instead of add_rounded
    final clearIconFinder = find.byIcon(Icons.filter_alt_off_rounded);
    expect(clearIconFinder, findsOneWidget);
  });

  testWidgets('EmptyState supports back action icon inference', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.wallet_outlined,
            title: 'Not found',
            body: 'Item not found.',
            actionLabel: 'Back home',
            onAction: () {},
          ),
        ),
      ),
    );

    final backIconFinder = find.byIcon(Icons.arrow_back_rounded);
    expect(backIconFinder, findsOneWidget);
  });

  for (final (name, size, textScale) in [
    ('compact', const Size(320, 568), 1.0),
    ('compact large text', const Size(320, 568), 2.0),
    ('landscape', const Size(780, 360), 1.0),
  ]) {
    for (final (tab, label, destination) in [
      (3, 'Add account', 'New account'),
      (1, 'Add transaction', 'Add record'),
    ]) {
      testWidgets('empty $label action clears navigation ($name)', (
        tester,
      ) async {
        await _pumpTab(
          tester,
          size: size,
          textScale: textScale,
          tab: tab,
          ledger: _emptyLedger,
        );
        final action = find.widgetWithText(AppActionButton, label);
        if (tab == 1) {
          expect(
            tester.getRect(find.byType(CustomScrollView).first).bottom,
            lessThanOrEqualTo(
              tester.getRect(find.byType(IslandFloatingActionButton)).top,
            ),
          );
          final scrollable = find.descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          );
          await tester.scrollUntilVisible(
            action,
            180,
            scrollable: scrollable.first,
          );
        }
        expect(action, findsOneWidget);
        await tester.ensureVisible(action);
        await _settle(tester);
        final scroll = tester.state<ScrollableState>(
          find.ancestor(of: action, matching: find.byType(Scrollable)).first,
        );
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await _settle(tester);

        final actionRect = tester.getRect(action);
        final floatingAction = find.byType(IslandFloatingActionButton);
        expect(floatingAction, findsOneWidget);
        expect(actionRect.overlaps(tester.getRect(floatingAction)), isFalse);
        expect(
          actionRect.bottom,
          lessThanOrEqualTo(size.height - AppSizes.bottomBarClearance),
        );
        expect(action.hitTestable(), findsOneWidget);
        await tester.tap(action);
        await _settle(tester);
        expect(find.text(destination), findsOneWidget);
      });
    }
  }

  testWidgets('history search keeps focus when results become empty', (
    tester,
  ) async {
    await _pumpTab(tester, size: const Size(360, 780), textScale: 1, tab: 1);
    final field = find.descendant(
      of: find.byType(PremiumSearchInput),
      matching: find.byType(EditableText),
    );
    expect(field, findsOneWidget);
    await tester.showKeyboard(field);
    final editable = tester.state<EditableTextState>(field);
    expect(editable.widget.focusNode.hasFocus, isTrue);

    await tester.enterText(field, 'no-matching-record-123');
    await _settle(tester);
    expect(find.text('No matching transactions'), findsOneWidget);
    expect(tester.state<EditableTextState>(field), same(editable));
    expect(editable.widget.focusNode.hasFocus, isTrue);

    await tester.enterText(field, '');
    await _settle(tester);
    expect(tester.state<EditableTextState>(field), same(editable));
    expect(editable.widget.focusNode.hasFocus, isTrue);
  });

  testWidgets('empty history keeps a viewport with the keyboard open', (
    tester,
  ) async {
    await _pumpTab(
      tester,
      size: const Size(320, 568),
      textScale: 2,
      tab: 1,
      ledger: _emptyLedger,
    );
    tester.view.viewInsets = const FakeViewPadding(bottom: 340);
    await _settle(tester);

    final scrollView = find.byType(CustomScrollView);
    final search = find.byType(PremiumSearchInput);
    expect(
      tester.getSize(scrollView).height,
      greaterThanOrEqualTo(tester.getSize(search).height),
    );
    final field = find.descendant(
      of: search,
      matching: find.byType(EditableText),
    );
    expect(field.hitTestable(), findsOneWidget);
    await tester.tap(field);
    await _settle(tester);
    expect(
      tester.state<EditableTextState>(field).widget.focusNode.hasFocus,
      isTrue,
    );
    await tester.enterText(field, 'groceries');
    await _settle(tester);
    expect(
      tester.state<EditableTextState>(field).widget.controller.text,
      'groceries',
    );
  });
}
