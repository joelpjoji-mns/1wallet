import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/transactions/add_record_screen.dart';
import 'package:one_wallet_flutter/src/startup/startup_state.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

import 'fixtures/sample_ledger.dart';
import 'test_harness.dart';

/// Regression coverage for the Add Record calculator pad:
/// - the "+/-" and "%" keys used to be dead no-ops
/// - toggling sign must never render a confusing "--12" double minus
/// - amounts with more fractional digits than the currency supports must
///   round instead of silently truncating the last digit
/// - amounts entered/edited for 3-decimal currencies (KWD/BHD/OMR/...) must
///   not show a stray trailing zero (e.g. "1.50" instead of "1.5")
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Finder amountDisplay() => find.byKey(const Key('addRecordAmountDisplay'));

  Future<ProviderContainer> pumpAddRecord(
    WidgetTester tester, {
    String? initialAccountId,
    String? transactionId,
    LedgerState? ledger,
  }) async {
    final effectiveLedger = ledger ?? sampleLedgerState();
    final container = ProviderContainer(
      overrides: authenticatedSampleOverrides(ledger: effectiveLedger),
    );
    addTearDown(container.dispose);
    // Deterministically seed state rather than relying on the controller's
    // own async startup load racing the widget pump.
    await container
        .read(ledgerProvider.notifier)
        .restoreLedgerState(effectiveLedger);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          // NoSplash avoids the ink_sparkle shader (unavailable in the test
          // environment), which otherwise intermittently throws on category
          // picker / button taps.
          theme: AppTheme.light().copyWith(
            splashFactory: NoSplash.splashFactory,
          ),
          darkTheme: AppTheme.dark().copyWith(
            splashFactory: NoSplash.splashFactory,
          ),
          home: AddRecordScreen(
            initialAccountId: initialAccountId,
            transactionId: transactionId,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('+/- toggles sign on income without affecting the display '
      'prefix logic', (tester) async {
    await pumpAddRecord(tester, initialAccountId: 'acc-cash');

    // Switch to Income so the type-based "-" auto-prefix never fires,
    // isolating the +/- toggle's own effect on the displayed number.
    await tester.tap(find.text('Income'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('5').last);
    await tester.tap(find.text('0').last);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(amountDisplay()).data, '50');

    await tester.tap(find.text('+/-').last);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(amountDisplay()).data, '-50');

    // Toggling back returns to the original magnitude.
    await tester.tap(find.text('+/-').last);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(amountDisplay()).data, '50');
  });

  testWidgets(
    '+/- on an expense never renders a double "--" minus sign',
    (tester) async {
      await pumpAddRecord(tester, initialAccountId: 'acc-cash');

      // Expense is the default type, which already auto-prefixes "-".
      await tester.tap(find.text('5').last);
      await tester.tap(find.text('0').last);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(amountDisplay()).data, '-50');

      await tester.tap(find.text('+/-').last);
      await tester.pumpAndSettle();
      final displayed = tester.widget<Text>(amountDisplay()).data!;
      expect(displayed, '-50');
      expect(displayed.contains('--'), isFalse);
    },
  );

  testWidgets('% divides the current entry by 100', (tester) async {
    await pumpAddRecord(tester, initialAccountId: 'acc-cash');

    await tester.tap(find.text('5').last);
    await tester.tap(find.text('0').last);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(amountDisplay()).data, '-50');

    await tester.tap(find.text('%').last);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(amountDisplay()).data, '-0.5');
  });

  testWidgets(
    'entering more fractional digits than the currency supports rounds '
    'instead of truncating on save',
    (tester) async {
      final container = await pumpAddRecord(
        tester,
        initialAccountId: 'acc-cash',
      );

      // acc-cash is INR (2 decimals). "1.239" should round to 124 minor
      // units (1.24), not truncate to 123 (1.23).
      for (final key in ['1', '.', '2', '3', '9']) {
        await tester.tap(find.text(key).last);
      }
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Food').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Groceries').last);
      await tester.pumpAndSettle();

      final beforeIds = container
          .read(ledgerProvider)
          .transactions
          .map((t) => t.id)
          .toSet();
      final beforeCount = beforeIds.length;
      await tester.tap(find.byIcon(Icons.check_rounded).first);
      await tester.pumpAndSettle();

      final transactions = container.read(ledgerProvider).transactions;
      expect(transactions.length, beforeCount + 1);
      final saved = transactions.singleWhere(
        (t) => !beforeIds.contains(t.id),
      );
      expect(saved.amount.amountMinor, 124);
    },
  );

  testWidgets(
    'editing a 3-decimal currency transaction shows "1.5", not "1.50"',
    (tester) async {
      final seed = sampleLedgerState();
      final kwdAccount = Account(
        id: 'acc-kwd',
        name: 'Kuwait Wallet',
        type: 'cash',
        currency: 'KWD',
        openingBalance: const Money(amountMinor: 0, currency: 'KWD'),
      );
      final kwdTransaction = TransactionRecord(
        id: 'tx-kwd',
        type: 'expense',
        status: 'cleared',
        source: 'manual',
        accountId: 'acc-kwd',
        categoryId: 'cat-grocery',
        amount: const Money(amountMinor: 1500, currency: 'KWD'),
        baseAmount: const Money(amountMinor: 1500, currency: 'KWD'),
        occurredAt: DateTime(2026, 2, 1),
      );
      final ledger = seed.copyWith(
        accounts: [...seed.accounts, kwdAccount],
        transactions: [...seed.transactions, kwdTransaction],
      );

      await pumpAddRecord(tester, transactionId: 'tx-kwd', ledger: ledger);

      expect(tester.widget<Text>(amountDisplay()).data, '-1.5');
    },
  );

  testWidgets(
    'rapid double-tap on save only creates one transaction (duplicate-submit '
    'guard)',
    (tester) async {
      final seedState = sampleLedgerState();
      final repository = _DelayedSaveLedgerRepository(seedState);
      final container = ProviderContainer(
        overrides: [
          startupStateProvider.overrideWithValue(
            const StartupState.ready(destination: StartupDestination.home),
          ),
          ledgerRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light().copyWith(
              splashFactory: NoSplash.splashFactory,
            ),
            darkTheme: AppTheme.dark().copyWith(
              splashFactory: NoSplash.splashFactory,
            ),
            home: const AddRecordScreen(initialAccountId: 'acc-cash'),
          ),
        ),
      );
      // Seed state directly rather than relying on the controller's own
      // startup load, which pipes the restored ledger through a background
      // isolate (foundation.compute) that flutter_test can't reliably
      // resolve. `_commit` (which this ultimately calls) assigns `state`
      // synchronously before awaiting the (delayed, for this test)
      // repository write, so the ledger is already populated for the UI
      // immediately below without needing to await this call.
      unawaited(
        container.read(ledgerProvider.notifier).restoreLedgerState(seedState),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.text('5').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Food').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Groceries').last);
      await tester.pumpAndSettle();

      final beforeIds = container
          .read(ledgerProvider)
          .transactions
          .map((t) => t.id)
          .toSet();
      final saveButton = find.byIcon(Icons.check_rounded);

      // The repository's save() is behind a real Timer that flutter_test's
      // fake clock won't advance without an explicit pump(duration), so
      // `_isSaving` stays true across both taps here — reproducing a
      // slow-network double-tap without needing real time to pass.
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

      // Let the delayed saves (the restore above, plus this save) resolve
      // so the widget finishes navigating away and the test doesn't end
      // with a pending Timer.
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
