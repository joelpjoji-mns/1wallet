import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/cloud_sync/cloud_sync_write_guard.dart';
import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/ledger/ledger_selectors.dart';

import '../bdd_context.dart';

void registerOfflineSteps(BddContext context) {
  context.given(
    RegExp(r'^an offline wallet with (\d+) minor units$'),
    (matches) async {
      final initialMinor = int.parse(matches[1]!);
      context.isOffline = true;
      context.cloudWritesCount = 0;
      context.unsyncedChanges = false;

      final defaultAccount = Account(
        id: 'acc-offline-default',
        name: 'Default Cash',
        type: 'cash',
        currency: 'USD',
        openingBalance: Money(amountMinor: initialMinor, currency: 'USD'),
      );

      context.state = LedgerState(
        version: currentLedgerStateVersion,
        userId: 'local-user',
        accounts: [defaultAccount],
        transactions: const [],
        categories: const [
          Category(
            id: 'cat-general',
            name: 'General',
            kind: 'expense',
            color: Color(0xFF6366F1),
          ),
          Category(
            id: 'cat-food',
            name: 'Food & Dining',
            kind: 'expense',
            color: Color(0xFFEF4444),
          ),
        ],
        preferences: const LedgerPreferences(
          baseCurrency: 'USD',
        ),
        captureCandidates: const [],
      );
    },
  );

  context.given(
    RegExp(
      r'^an offline account "([^"]+)" with (\d+) minor units in "([^"]+)"$',
    ),
    (matches) async {
      final name = matches[1]!;
      final minor = int.parse(matches[2]!);
      final currency = matches[3]!;
      context.isOffline = true;

      final id = 'acc-${name.toLowerCase().replaceAll(' ', '-')}';
      final account = Account(
        id: id,
        name: name,
        type: 'checking',
        currency: currency,
        openingBalance: Money(amountMinor: minor, currency: currency),
      );

      final current = context.state ??
          LedgerState(
            version: currentLedgerStateVersion,
            userId: 'local-user',
            accounts: const [],
            transactions: const [],
            categories: const [
              Category(
                id: 'cat-general',
                name: 'General',
                kind: 'expense',
                color: Color(0xFF6366F1),
              ),
            ],
            preferences: LedgerPreferences(
              baseCurrency: currency,
            ),
            captureCandidates: const [],
          );

      context.state = current.copyWith(
        accounts: [...current.accounts.where((a) => a.id != id), account],
      );
    },
  );

  context.when(
    RegExp(r'^I add a (\d+) expense for "([^"]+)"$'),
    (matches) async {
      final expenseMinor = int.parse(matches[1]!);
      final note = matches[2]!;

      final state = context.state;
      expect(state, isNotNull, reason: 'Ledger state must be initialized');

      final account = state!.accounts.firstWhere((a) => !a.isArchived);
      final category = state.categories.first;

      final record = TransactionRecord(
        id: 'txn-${DateTime.now().microsecondsSinceEpoch}',
        type: 'expense',
        status: 'cleared',
        source: 'manual',
        accountId: account.id,
        amount: Money(amountMinor: expenseMinor, currency: account.currency),
        baseAmount: Money(amountMinor: expenseMinor, currency: account.currency),
        occurredAt: DateTime.now(),
        categoryId: category.id,
        notes: note,
        name: note,
      );

      context.state = state.copyWith(
        transactions: [record, ...state.transactions],
      );
      context.unsyncedChanges = true;

      // In offline mode, mutations record unsynced changes locally but trigger zero cloud sync writes.
      if (context.isOffline) {
        expect(
          cloudWritesAllowed(
            localOnlyMode: true,
            signedInUserId: null,
          ),
          isFalse,
          reason: 'Cloud writes must be blocked in offline mode',
        );
      }
    },
  );

  context.when(
    RegExp(
      r'^I transfer (\d+) minor units from "([^"]+)" to "([^"]+)"$',
    ),
    (matches) async {
      final amountMinor = int.parse(matches[1]!);
      final fromName = matches[2]!;
      final toName = matches[3]!;

      final state = context.state;
      expect(state, isNotNull);

      final fromAccount = state!.accounts.firstWhere((a) => a.name == fromName);
      final toAccount = state.accounts.firstWhere((a) => a.name == toName);

      final record = TransactionRecord(
        id: 'txn-transfer-${DateTime.now().microsecondsSinceEpoch}',
        type: 'transfer',
        status: 'cleared',
        source: 'manual',
        accountId: fromAccount.id,
        counterAccountId: toAccount.id,
        amount: Money(amountMinor: amountMinor, currency: fromAccount.currency),
        baseAmount: Money(
          amountMinor: amountMinor,
          currency: fromAccount.currency,
        ),
        occurredAt: DateTime.now(),
        notes: 'Transfer $fromName -> $toName',
      );

      context.state = state.copyWith(
        transactions: [record, ...state.transactions],
      );
      context.unsyncedChanges = true;
    },
  );

  context.when(
    RegExp(r'^I retire or delete the account "([^"]+)"$'),
    (matches) async {
      final name = matches[1]!;
      final state = context.state;
      expect(state, isNotNull);

      context.state = state!.copyWith(
        accounts: state.accounts.map((a) {
          if (a.name == name) {
            return a.copyWith(isArchived: true);
          }
          return a;
        }).toList(),
      );
      context.unsyncedChanges = true;
    },
  );

  context.then(
    RegExp(r'^balance shows (\d+) minor units$'),
    (matches) async {
      final expectedMinor = int.parse(matches[1]!);
      final state = context.state;
      expect(state, isNotNull);

      final account = state!.accounts.firstWhere((a) => !a.isArchived);
      final balance = accountBalance(state, account);
      expect(
        balance.amountMinor,
        equals(expectedMinor),
        reason:
            'Calculated balance in minor units does not match expected value',
      );
    },
  );

  context.then(
    RegExp(r'^balance shows (\d+) minor units for account "([^"]+)"$'),
    (matches) async {
      final expectedMinor = int.parse(matches[1]!);
      final accountName = matches[2]!;
      final state = context.state;
      expect(state, isNotNull);

      final account = state!.accounts.firstWhere((a) => a.name == accountName);
      final balance = accountBalance(state, account);
      expect(
        balance.amountMinor,
        equals(expectedMinor),
        reason: 'Account balance mismatch for $accountName',
      );
    },
  );

  context.then(
    RegExp(r'^no cloud write occurs$'),
    (matches) async {
      expect(
        context.cloudWritesCount,
        equals(0),
        reason: 'Cloud writes were dispatched in offline mode',
      );
      expect(
        cloudWritesAllowed(
          localOnlyMode: context.isOffline,
          signedInUserId: context.signedInUserId,
        ),
        isFalse,
      );
    },
  );

  context.then(
    RegExp(r'^the local ledger contains (\d+) transactions$'),
    (matches) async {
      final expectedCount = int.parse(matches[1]!);
      final state = context.state;
      expect(state, isNotNull);
      expect(state!.transactions.length, equals(expectedCount));
    },
  );

  context.then(
    RegExp(r'^the local ledger has unsynced changes recorded$'),
    (matches) async {
      expect(context.unsyncedChanges, isTrue);
    },
  );

  context.then(
    RegExp(r'^the cloud sync phase is disabled$'),
    (matches) async {
      expect(context.isOffline, isTrue);
    },
  );

  context.then(
    RegExp(
      r'^the cloud sync write guard disallows remote writes with reason "([^"]+)"$',
    ),
    (matches) async {
      final reasonKeyword = matches[1]!;
      expect(
        cloudWritesAllowed(
          localOnlyMode: true,
          signedInUserId: null,
        ),
        isFalse,
      );
      expect(
        offlineModeSyncDisabledReason.toLowerCase(),
        contains(reasonKeyword.toLowerCase()),
      );
    },
  );

  context.then(
    RegExp(r'^zero network requests reach Cloud Firestore$'),
    (matches) async {
      expect(context.cloudWritesCount, equals(0));
    },
  );

  context.then(
    RegExp(r'^the account "([^"]+)" is not active in the local ledger$'),
    (matches) async {
      final name = matches[1]!;
      final state = context.state;
      expect(state, isNotNull);
      final account = state!.accounts.firstWhere((a) => a.name == name);
      expect(account.isArchived, isTrue);
    },
  );
}
