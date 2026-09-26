import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/routing/app_router.dart';
import 'package:one_wallet_flutter/src/startup/startup_state.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

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
        Account(
          id: 'acc-1',
          name: 'Main Checking',
          type: 'bank',
          currency: 'USD',
          openingBalance: const Money(amountMinor: 500000, currency: 'USD'),
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

  testWidgets(
    'Past recurring still shows skipped occurrences when '
    'hideSkippedInHistory is false',
    (tester) async {
      await pumpPastRecurring(tester, buildSeed(hideSkipped: false));
      expect(find.text('SkippedRentMarker'), findsOneWidget);
    },
  );

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
      final saveButton = find.text('Create scheduled record');
      await tester.ensureVisible(saveButton);
      await tester.pumpAndSettle();
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
      final saveButton = find.text('Create scheduled record');
      await tester.ensureVisible(saveButton);
      await tester.pumpAndSettle();

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
