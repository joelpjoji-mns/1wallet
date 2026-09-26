import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/routing/app_router.dart';
import 'package:one_wallet_flutter/src/startup/startup_state.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

import 'fixtures/sample_ledger.dart';
import 'test_harness.dart';

/// Regression coverage for the account editor's "Opening balance" field:
/// previously there was no way to set a starting balance at all (new
/// accounts always persisted with amountMinor 0), and the field must accept
/// a negative sign so liability-style accounts (credit cards, loans) can
/// start with a balance already owed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Finder openingBalanceField() => find.ancestor(
    of: find.text('Opening balance'),
    matching: find.byType(TextFormField),
  );

  testWidgets(
    'creating a new account with a negative opening balance persists the '
    'signed amount',
    (tester) async {
      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(),
      );
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      await container
          .read(ledgerProvider.notifier)
          .restoreLedgerState(sampleLedgerState());

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
          ),
        ),
      );
      router.go('/account/new');
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Account name'),
        'Owed Credit Card',
      );
      await tester.enterText(openingBalanceField(), '-500.25');
      await tester.pumpAndSettle();

      final beforeCount = container.read(ledgerProvider).accounts.length;
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pumpAndSettle();

      final accounts = container.read(ledgerProvider).accounts;
      expect(accounts.length, beforeCount + 1);
      final created = accounts.firstWhere(
        (a) => a.name == 'Owed Credit Card',
      );
      expect(created.openingBalance.amountMinor, -50025);
      expect(created.openingBalance.currency, 'USD');
    },
  );

  testWidgets(
    'editing an existing account preloads and updates its opening balance',
    (tester) async {
      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(),
      );
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      await container
          .read(ledgerProvider.notifier)
          .restoreLedgerState(sampleLedgerState());

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
          ),
        ),
      );
      router.go('/account/acc-bank');
      await tester.pumpAndSettle();

      // acc-bank's fixture opening balance is 12,456,000 minor (INR, 2
      // decimals) => "124560.00" preloaded into the field.
      final fieldWidget = tester.widget<TextFormField>(openingBalanceField());
      expect(fieldWidget.controller?.text, '124560.00');

      await tester.enterText(openingBalanceField(), '1000');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.check_rounded));
      await tester.pumpAndSettle();

      final updated = container
          .read(ledgerProvider)
          .accounts
          .firstWhere((a) => a.id == 'acc-bank');
      expect(updated.openingBalance.amountMinor, 100000);
      expect(updated.openingBalance.currency, 'INR');
    },
  );

  testWidgets(
    'rapid double-tap on save only creates one account (duplicate-submit '
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
      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
          ),
        ),
      );
      // Let the controller's automatic startup load (LedgerRepository.load,
      // which is *not* delayed) finish populating state from the seed.
      await tester.pumpAndSettle();

      router.go('/account/new');
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Account name'),
        'Double Tap Wallet',
      );
      await tester.pumpAndSettle();

      final beforeCount = container.read(ledgerProvider).accounts.length;
      final saveButton = find.byIcon(Icons.check_rounded);

      // The repository's save() is artificially delayed behind a real Timer
      // that flutter_test's fake clock won't advance until we explicitly
      // pump a duration, so `_isSaving` stays true across both taps here —
      // reproducing a slow-network double-tap without needing real time to
      // pass. Without the guard, the second tap would synchronously commit
      // a second account (ledger state updates happen before the repository
      // write completes) even though the save is still in flight.
      await tester.tap(saveButton);
      await tester.tap(saveButton);

      expect(
        container
            .read(ledgerProvider)
            .accounts
            .where((a) => a.name == 'Double Tap Wallet')
            .length,
        1,
      );

      // Let the delayed save resolve so the widget finishes navigating away
      // and the test doesn't end with a pending Timer.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      final accounts = container
          .read(ledgerProvider)
          .accounts
          .where((a) => a.name == 'Double Tap Wallet');
      expect(accounts.length, 1);
      expect(
        container.read(ledgerProvider).accounts.length,
        beforeCount + 1,
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
