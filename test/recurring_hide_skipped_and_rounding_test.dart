import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/routing/app_router.dart';
import 'package:one_wallet_flutter/src/startup/startup_state.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/widgets/privacy_text.dart';

import 'test_harness.dart';

/// Regression coverage for the Recurring screen:
/// - "Past recurring" must respect `hideSkippedInHistory` instead of always
///   dropping void (skipped) occurrences regardless of the preference.
/// - The plan amount field must round extra fractional digits instead of
///   truncating them.
/// - Rapid double-tapping "Create scheduled record" must only create one
///   plan.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  LedgerState buildSeed({required bool hideSkipped}) {
    final now = DateTime.now();
    final plan = TransactionRecord(
      id: 'plan-rent',
      type: 'expense',
      status: 'scheduled',
      source: 'recurring',
      accountId: 'acc-1',
      amount: const Money(amountMinor: 32000, currency: 'USD'),
      baseAmount: const Money(amountMinor: 32000, currency: 'USD'),
      occurredAt: now.add(const Duration(days: 4)),
      recurrenceFrequency: 'monthly',
    );
    final skippedInstance = TransactionRecord(
      id: 'tx-skipped-rent',
      type: 'expense',
      status: 'void',
      source: 'recurring',
      accountId: 'acc-1',
      amount: const Money(amountMinor: 32000, currency: 'USD'),
      baseAmount: const Money(amountMinor: 32000, currency: 'USD'),
      occurredAt: now.subtract(const Duration(days: 26)),
      originalTransactionId: 'plan-rent',
      notes: 'SkippedRentMarker',
    );
    return emptyLedgerState().copyWith(
      accounts: [
        const Account(
          id: 'acc-1',
          name: 'Main Checking',
          type: 'bank',
          currency: 'USD',
          openingBalance: Money(amountMinor: 500000, currency: 'USD'),
        ),
      ],
      transactions: [plan, skippedInstance],
      preferences: LedgerPreferences(hideSkippedInHistory: hideSkipped),
    );
  }

  Future<ProviderContainer> pumpPastRecurring(
    WidgetTester tester,
    LedgerState seed,
  ) async {
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(ledger: seed),
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    await container.read(ledgerProvider.notifier).restoreLedgerState(seed);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          theme: AppTheme.light().copyWith(
            splashFactory: NoSplash.splashFactory,
          ),
          darkTheme: AppTheme.amoled().copyWith(
            splashFactory: NoSplash.splashFactory,
          ),
        ),
      ),
    );
    router.go('/recurring/past');
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'Past recurring hides skipped occurrences when hideSkippedInHistory is '
    'true',
    (tester) async {
      await pumpPastRecurring(tester, buildSeed(hideSkipped: true));
      expect(find.text('SkippedRentMarker'), findsNothing);
    },
  );

  testWidgets('Past recurring still shows skipped occurrences when '
      'hideSkippedInHistory is false', (tester) async {
    await pumpPastRecurring(tester, buildSeed(hideSkipped: false));
    expect(find.text('SkippedRentMarker'), findsOneWidget);
  });

  testWidgets('recurring amount remains readable at large text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final seed = buildSeed(hideSkipped: false);
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(ledger: seed),
    );
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    await container.read(ledgerProvider.notifier).restoreLedgerState(seed);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
        ),
      ),
    );
    router.go('/recurring/new');
    await tester.pumpAndSettle();
    final amount = find.widgetWithText(TextFormField, 'Amount');
    final currency = find.widgetWithText(OutlinedButton, 'USD');
    expect(tester.getSize(amount).width, greaterThan(250));
    expect(
      tester.getTopLeft(currency).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(amount).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('urgent planned payments keep names and amounts readable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const name = 'Quarterly rent payment';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final (days, badge, scale) in [
      (-1, 'OVERDUE', 1.0),
      (0, 'TODAY', 2.0),
      (2, '2D', 1.0),
    ]) {
      final seed = buildSeed(hideSkipped: false);
      final plan = seed.transactions.first.copyWith(
        name: name,
        occurredAt: today.add(Duration(days: days)),
      );
      final state = seed.copyWith(transactions: [plan]);
      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(ledger: state),
      );
      await container.read(ledgerProvider.notifier).restoreLedgerState(state);
      final router = container.read(appRouterProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
        ),
      );
      router.go('/recurring');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(name));

      final card = find.ancestor(
        of: find.text(name),
        matching: find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_RecurringCompactCard',
        ),
      );
      expect(
        tester.getSize(find.text(name)).width,
        greaterThan(scale == 1 ? 180 : 120),
      );
      expect(
        find.descendant(of: card, matching: find.text(badge)),
        findsOneWidget,
      );
      final amount = find.descendant(
        of: card,
        matching: find.byType(PrivacyText),
      );
      expect(amount, findsOneWidget);
      final amountText = find.descendant(
        of: amount,
        matching: find.byType(Text),
      );
      expect(
        tester.renderObject<RenderParagraph>(amountText).didExceedMaxLines,
        isFalse,
      );
      if (scale == 1) {
        final fitted = find
            .ancestor(of: amount, matching: find.byType(FittedBox))
            .first;
        expect(
          tester.getSize(fitted).width + 0.01,
          greaterThanOrEqualTo(tester.getSize(amountText).width),
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    }
  });

  testWidgets(
    'entering more fractional digits than the currency supports rounds '
    'the plan amount instead of truncating',
    (tester) async {
      final seed = buildSeed(hideSkipped: false);
      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(ledger: seed),
      );
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      await container.read(ledgerProvider.notifier).restoreLedgerState(seed);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
            theme: AppTheme.light().copyWith(
              splashFactory: NoSplash.splashFactory,
            ),
            darkTheme: AppTheme.amoled().copyWith(
              splashFactory: NoSplash.splashFactory,
            ),
          ),
        ),
      );
      router.go('/recurring/new');
      await tester.pumpAndSettle();

      // acc-1 defaults in automatically (first account); USD is 2 decimals,
      // so "1.239" should round to 124 minor units, not truncate to 123.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '1.239',
      );
      await tester.pumpAndSettle();

      final beforeIds = container
          .read(ledgerProvider)
          .transactions
          .map((t) => t.id)
          .toSet();
      final saveButton = find.bySemanticsLabel('Save');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      final created = container
          .read(ledgerProvider)
          .transactions
          .singleWhere((t) => !beforeIds.contains(t.id));
      expect(created.amount.amountMinor, 124);
    },
  );

  testWidgets(
    'rapid double-tap on "Create scheduled record" only creates one plan '
    '(duplicate-submit guard)',
    (tester) async {
      final seed = buildSeed(hideSkipped: false);
      final repository = _DelayedSaveLedgerRepository(seed);
      final container = ProviderContainer(
        overrides: [
          startupStateProvider.overrideWithValue(
            const StartupState.ready(destination: StartupDestination.home),
          ),
          ledgerRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
            theme: AppTheme.light().copyWith(
              splashFactory: NoSplash.splashFactory,
            ),
            darkTheme: AppTheme.amoled().copyWith(
              splashFactory: NoSplash.splashFactory,
            ),
          ),
        ),
      );
      // Seed synchronously (see add_record_calculator_and_rounding_test.dart
      // for why we don't rely on the controller's own startup load here).
      unawaited(
        container.read(ledgerProvider.notifier).restoreLedgerState(seed),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      router.go('/recurring/new');
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '50',
      );
      await tester.pumpAndSettle();

      final beforeIds = container
          .read(ledgerProvider)
          .transactions
          .map((t) => t.id)
          .toSet();
      final saveButton = find.bySemanticsLabel('Save');

      await tester.tap(saveButton);
      await tester.tap(saveButton);

      expect(
        container
            .read(ledgerProvider)
            .transactions
            .where((t) => !beforeIds.contains(t.id))
            .length,
        1,
      );

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(
        container
            .read(ledgerProvider)
            .transactions
            .where((t) => !beforeIds.contains(t.id))
            .length,
        1,
      );
    },
  );
}

class _DelayedSaveLedgerRepository extends LedgerRepository {
  _DelayedSaveLedgerRepository(this._seed);

  final LedgerState _seed;
  LedgerState? _saved;

  @override
  Future<LedgerState?> load() async => _saved ?? _seed;

  @override
  Future<void> save(LedgerState state) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _saved = state;
  }

  @override
  Future<void> clear() async {
    _saved = null;
  }
}
