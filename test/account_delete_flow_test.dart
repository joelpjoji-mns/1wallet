import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/accounts/account_editor_screen.dart';
import 'package:one_wallet_flutter/src/ledger/ledger_selectors.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

import 'fixtures/sample_ledger.dart';
import 'test_harness.dart';

void main() {
  setUp(() {
    LedgerProvidersConfig.disableAutoBackup = true;
    SharedPreferences.setMockInitialValues({});
  });

  group('Account Deletion Behavior', () {
    testWidgets(
      'hide checkbox keeps the account off All accounts and danger actions share a row',
      (tester) async {
        final base = sampleLedgerState();
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: authenticatedSampleOverrides(ledger: base, prefs: prefs),
        );
        addTearDown(container.dispose);
        await container.read(ledgerProvider.notifier).restoreLedgerState(base);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: AccountEditorScreen(accountId: 'acc-bank'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final close = find.widgetWithText(OutlinedButton, 'Close account');
        final delete = find.widgetWithText(OutlinedButton, 'Delete account');
        await tester.ensureVisible(delete);
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(close).dy,
          closeTo(tester.getTopLeft(delete).dy, 0.5),
        );
        expect(
          tester.getTopLeft(close).dx,
          lessThan(tester.getTopLeft(delete).dx),
        );

        final hide = find.text('Hide from All accounts');
        await tester.ensureVisible(hide);
        await tester.pumpAndSettle();
        await tester.tap(hide);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<AppSwitchListTile>(
                find.ancestor(
                  of: hide,
                  matching: find.byType(AppSwitchListTile),
                ),
              )
              .value,
          isTrue,
        );

        await tester.tap(find.byType(HeaderSaveAction));
        await tester.pumpAndSettle();

        final saved = container
            .read(ledgerProvider)
            .accounts
            .firstWhere((a) => a.id == 'acc-bank');
        expect(saved.showOnHome, isFalse);
      },
    );

    testWidgets('danger actions use short one-line labels on narrow phones', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final base = sampleLedgerState();
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(ledger: base, prefs: prefs),
      );
      addTearDown(container.dispose);
      await container.read(ledgerProvider.notifier).restoreLedgerState(base);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: AccountEditorScreen(accountId: 'acc-bank'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final close = find.widgetWithText(OutlinedButton, 'Close');
      final delete = find.widgetWithText(OutlinedButton, 'Delete');
      await tester.ensureVisible(delete);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(close).dy,
        closeTo(tester.getTopLeft(delete).dy, 0.5),
      );
      expect(
        find.descendant(
          of: delete,
          matching: find.bySemanticsLabel('Delete account'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'blocks deletion if account is linked to active planned recurring payments',
      (tester) async {
        final base = sampleLedgerState();
        // Add a scheduled/planned payment linked to acc-bank
        final plan = TransactionRecord(
          id: 'plan-test-1',
          type: 'expense',
          status: 'scheduled',
          source: 'recurring',
          accountId: 'acc-bank',
          amount: const Money(amountMinor: 50000, currency: 'INR'),
          baseAmount: const Money(amountMinor: 50000, currency: 'INR'),
          occurredAt: DateTime.now().add(const Duration(days: 3)),
        );

        final stateWithPlan = base.copyWith(
          transactions: [...base.transactions, plan],
        );

        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: authenticatedSampleOverrides(
            ledger: stateWithPlan,
            prefs: prefs,
          ),
        );
        addTearDown(container.dispose);
        await container
            .read(ledgerProvider.notifier)
            .restoreLedgerState(stateWithPlan);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: AccountEditorScreen(accountId: 'acc-bank'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap Delete account button
        final deleteBtn = find.widgetWithText(OutlinedButton, 'Delete account');
        await tester.ensureVisible(deleteBtn);
        await tester.pumpAndSettle();
        await tester.tap(deleteBtn);
        await tester.pumpAndSettle();

        // Expect blocking dialog
        expect(find.text('Cannot delete account'), findsOneWidget);
        expect(find.textContaining('planned payment'), findsOneWidget);

        // Dismiss dialog
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        // Account must still exist
        final account = container
            .read(ledgerProvider)
            .accounts
            .firstWhere((a) => a.id == 'acc-bank');
        expect(account.isDeleted, isFalse);
      },
    );

    testWidgets(
      'allows deleting account with transactions, marking isDeleted=true while preserving past records',
      (tester) async {
        final base = sampleLedgerState();
        // Remove any scheduled payments on acc-bank so it only has historical transactions
        final cleared = base.copyWith(
          transactions: base.transactions
              .where((t) => t.status != 'scheduled' && t.status != 'paused')
              .toList(),
        );

        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: authenticatedSampleOverrides(
            ledger: cleared,
            prefs: prefs,
          ),
        );
        addTearDown(container.dispose);
        await container
            .read(ledgerProvider.notifier)
            .restoreLedgerState(cleared);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: AccountEditorScreen(accountId: 'acc-bank'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final deleteBtn = find.widgetWithText(OutlinedButton, 'Delete account');
        await tester.ensureVisible(deleteBtn);
        await tester.pumpAndSettle();
        await tester.tap(deleteBtn);
        await tester.pumpAndSettle();

        // Expect deletion confirmation dialog mentioning preserved transactions
        expect(find.text('Delete account?'), findsOneWidget);
        expect(
          find.textContaining(
            'All previous transactions under this account will remain safely preserved',
          ),
          findsOneWidget,
        );

        // Confirm deletion
        await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
        await tester.pumpAndSettle();

        final finalLedger = container.read(ledgerProvider);
        final deletedAcc = finalLedger.accounts.firstWhere(
          (a) => a.id == 'acc-bank',
        );
        expect(deletedAcc.isDeleted, isTrue);

        // Historical transactions belonging to this account are intact
        final transactions = finalLedger.transactions.where(
          (t) => t.accountId == 'acc-bank',
        );
        expect(transactions, isNotEmpty);
      },
    );

    testWidgets(
      'hidden EMI templates of archived loans do not block deleting the source account',
      (tester) async {
        final base = sampleLedgerState();
        final cleared = base.copyWith(
          accounts: [
            ...base.accounts,
            const Account(
              id: 'acc-old-loan',
              name: 'Old car loan',
              type: 'loan',
              currency: 'INR',
              openingBalance: Money(amountMinor: -100000, currency: 'INR'),
              isArchived: true,
            ),
          ],
          transactions: [
            ...base.transactions.where(
              (t) => t.status != 'scheduled' && t.status != 'paused',
            ),
            TransactionRecord(
              id: 'emi-old-loan',
              type: 'loan_repayment',
              status: 'paused',
              source: 'recurring',
              accountId: 'acc-bank',
              counterAccountId: 'acc-old-loan',
              amount: const Money(amountMinor: 5000, currency: 'INR'),
              baseAmount: const Money(amountMinor: 5000, currency: 'INR'),
              occurredAt: DateTime.now().add(const Duration(days: 3)),
            ),
          ],
        );

        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(
          overrides: authenticatedSampleOverrides(
            ledger: cleared,
            prefs: prefs,
          ),
        );
        addTearDown(container.dispose);
        await container
            .read(ledgerProvider.notifier)
            .restoreLedgerState(cleared);
        expect(
          visiblePlansLinkedToAccount(
            container.read(ledgerProvider),
            'acc-bank',
          ),
          isEmpty,
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: AccountEditorScreen(accountId: 'acc-bank'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final deleteBtn = find.widgetWithText(OutlinedButton, 'Delete account');
        await tester.ensureVisible(deleteBtn);
        await tester.pumpAndSettle();
        await tester.tap(deleteBtn);
        await tester.pumpAndSettle();

        expect(find.text('Cannot delete account'), findsNothing);
        await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
        await tester.pumpAndSettle();

        final bank = container
            .read(ledgerProvider)
            .accounts
            .firstWhere((a) => a.id == 'acc-bank');
        expect(bank.isDeleted, isTrue);
      },
    );
  });

  group('Deleted accounts stay deleted', () {
    test('saving a deleted account does not resurrect it', () async {
      final base = sampleLedgerState();
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(ledger: base, prefs: prefs),
      );
      addTearDown(container.dispose);
      final controller = container.read(ledgerProvider.notifier);
      await controller.restoreLedgerState(base);

      await controller.deleteAccount('acc-bank');
      final deleted = container
          .read(ledgerProvider)
          .accounts
          .firstWhere((a) => a.id == 'acc-bank');
      expect(deleted.isDeleted, isTrue);

      await controller.upsertAccount(
        id: deleted.id,
        name: 'Renamed',
        type: deleted.type,
        currency: deleted.currency,
        isArchived: deleted.isArchived,
      );
      final after = container
          .read(ledgerProvider)
          .accounts
          .firstWhere((a) => a.id == 'acc-bank');
      expect(after.isDeleted, isTrue);
    });

    test('plans tied to deleted accounts are not listed as planned', () async {
      final base = sampleLedgerState();
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(ledger: base, prefs: prefs),
      );
      addTearDown(container.dispose);
      final controller = container.read(ledgerProvider.notifier);
      await controller.restoreLedgerState(base);
      final linkedBefore = scheduledTransactions(container.read(ledgerProvider))
          .where(
            (t) =>
                t.accountId == 'acc-bank' || t.counterAccountId == 'acc-bank',
          );
      expect(linkedBefore, isNotEmpty, reason: 'fixture needs bank plans');

      await controller.deleteAccount('acc-bank');
      final state = container.read(ledgerProvider);
      expect(
        scheduledTransactions(state).where(
          (t) => t.accountId == 'acc-bank' || t.counterAccountId == 'acc-bank',
        ),
        isEmpty,
      );
      expect(visiblePlansLinkedToAccount(state, 'acc-bank'), isEmpty);
    });
  });
}
