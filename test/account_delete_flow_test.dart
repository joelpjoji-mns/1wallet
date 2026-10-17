import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/accounts/account_editor_screen.dart';

import 'fixtures/sample_ledger.dart';
import 'test_harness.dart';

void main() {
  setUp(() {
    LedgerProvidersConfig.disableAutoBackup = true;
    SharedPreferences.setMockInitialValues({});
  });

  group('Account Deletion Behavior', () {
    testWidgets('blocks deletion if account is linked to active planned recurring payments', (
      tester,
    ) async {
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
      await container.read(ledgerProvider.notifier).restoreLedgerState(stateWithPlan);

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
      expect(
        find.textContaining('planned payment'),
        findsOneWidget,
      );

      // Dismiss dialog
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Account must still exist
      final account = container.read(ledgerProvider).accounts.firstWhere((a) => a.id == 'acc-bank');
      expect(account.isDeleted, isFalse);
    });

    testWidgets('allows deleting account with transactions, marking isDeleted=true while preserving past records', (
      tester,
    ) async {
      final base = sampleLedgerState();
      // Remove any scheduled payments on acc-bank so it only has historical transactions
      final cleared = base.copyWith(
        transactions: base.transactions.where((t) => t.status != 'scheduled' && t.status != 'paused').toList(),
      );

      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: authenticatedSampleOverrides(
          ledger: cleared,
          prefs: prefs,
        ),
      );
      addTearDown(container.dispose);
      await container.read(ledgerProvider.notifier).restoreLedgerState(cleared);

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
        find.textContaining('All previous transactions under this account will remain safely preserved'),
        findsOneWidget,
      );

      // Confirm deletion
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      final finalLedger = container.read(ledgerProvider);
      final deletedAcc = finalLedger.accounts.firstWhere((a) => a.id == 'acc-bank');
      expect(deletedAcc.isDeleted, isTrue);

      // Historical transactions belonging to this account are intact
      final transactions = finalLedger.transactions.where((t) => t.accountId == 'acc-bank');
      expect(transactions, isNotEmpty);
    });
  });
}
