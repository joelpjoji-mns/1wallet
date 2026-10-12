import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('User-scoped local backup filenames', () {
    test('includes full name and email before .onewallet extension', () {
      final suffix = buildUserBackupFileSuffix(
        userId: 'uid-joel-1',
        email: 'joel@example.com',
        displayName: 'Joel Thomas',
      );

      expect(suffix, 'Joel_Thomas_joel@example.com');
      expect(
        buildAutoBackupFileName(suffix: suffix),
        '1wallet_auto_backup_Joel_Thomas_joel@example.com.onewallet',
      );
      expect(
        buildAutoBackupFileName(suffix: suffix, variant: 'previous'),
        '1wallet_auto_backup_previous_Joel_Thomas_joel@example.com.onewallet',
      );
      expect(
        buildAutoBackupFileName(suffix: suffix, variant: 'safety'),
        '1wallet_auto_backup_safety_Joel_Thomas_joel@example.com.onewallet',
      );
      expect(
        buildManualBackupFileName(
          userId: 'uid-joel-1',
          email: 'joel@example.com',
          displayName: 'Joel Thomas',
        ),
        '1wallet_backup_Joel_Thomas_joel@example.com.onewallet',
      );
    });

    test('uses email when display name is empty or identical to email', () {
      final suffixNoName = buildUserBackupFileSuffix(
        userId: 'uid-2',
        email: 'alice@domain.org',
      );
      expect(
        buildAutoBackupFileName(suffix: suffixNoName),
        '1wallet_auto_backup_alice@domain.org.onewallet',
      );
      expect(
        buildManualBackupFileName(
          userId: 'uid-2',
          email: 'alice@domain.org',
        ),
        '1wallet_backup_alice@domain.org.onewallet',
      );

      final suffixSameAsEmail = buildUserBackupFileSuffix(
        userId: 'uid-3',
        email: 'bob@domain.org',
        displayName: 'bob@domain.org',
      );
      expect(
        buildAutoBackupFileName(suffix: suffixSameAsEmail),
        '1wallet_auto_backup_bob@domain.org.onewallet',
      );
    });

    test('falls back to legacy filename when no user is signed in', () {
      expect(
        buildAutoBackupFileName(suffix: null),
        '1wallet_auto_backup.onewallet',
      );
      expect(
        buildManualBackupFileName(),
        '1wallet_backup.onewallet',
      );
    });
  });

  group('Sign-out and cross-account isolation', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      LedgerProvidersConfig.disableAutoBackup = true;
    });

    test('clearSessionOnSignOut wipes active local ledger and unsynced flags', () async {
      const repo = LedgerRepository();
      const userA = LedgerUserIdentity(
        userId: 'user-a',
        email: 'usera@example.com',
        displayName: 'User A',
      );

      final ready = Completer<void>();
      final controller = LedgerController(
        repo,
        setLoadState: (state) {
          if (state.isReady && !ready.isCompleted) ready.complete();
        },
        initialUser: userA,
      );
      addTearDown(controller.dispose);
      await ready.future;

      expect(
        controller.defaultManualBackupFileName(),
        '1wallet_backup_User_A_usera@example.com.onewallet',
      );

      await controller.createStarterWallet(
        userId: 'user-a',
        accountName: 'User A Checking',
        currency: 'INR',
        accountColor: Colors.blue,
        openingBalanceMinor: 50000,
      );

      expect(controller.state.userId, 'user-a');
      expect(controller.state.accounts, isNotEmpty);

      await controller.clearSessionOnSignOut();

      expect(controller.state.userId, 'local-user');
      expect(controller.state.accounts, isEmpty);
      expect(controller.state.transactions, isEmpty);

      final persistedAfterSignOut = await repo.load();
      expect(persistedAfterSignOut, isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('has_unsynced_changes'), isNull);
      expect(prefs.getString('last_local_modified_at'), isNull);
      expect(prefs.getString('last_active_user_id'), isNull);
    });

    test('switching to a different user discards previous user persisted ledger', () async {
      const repo = LedgerRepository();
      // Seed SharedPreferences with User A's wallet
      final userALedger = emptyLedgerState(userId: 'user-a').copyWith(
        accounts: const [
          Account(
            id: 'acc-a',
            name: 'User A Private Account',
            type: 'bank',
            currency: 'INR',
            openingBalance: Money(amountMinor: 100000, currency: 'INR'),
            color: Colors.teal,
            sortOrder: 1,
          ),
        ],
      );
      await repo.save(userALedger);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_active_user_id', 'user-a');
      await prefs.setBool('has_unsynced_changes', true);

      // Now User B signs in
      const userB = LedgerUserIdentity(
        userId: 'user-b',
        email: 'userb@example.com',
        displayName: 'User B',
      );
      final ready = Completer<void>();
      final controller = LedgerController(
        repo,
        setLoadState: (state) {
          if (state.isReady && !ready.isCompleted) ready.complete();
        },
        initialUser: userB,
      );
      addTearDown(controller.dispose);
      await ready.future;

      expect(controller.state.userId, 'user-b');
      expect(controller.state.accounts, isEmpty);
      expect(prefs.getBool('has_unsynced_changes'), isNull);
      expect(prefs.getString('last_active_user_id'), 'user-b');
    });

    test('importArchive rejects backup from a different account unless forced', () async {
      const repo = LedgerRepository();
      const userA = LedgerUserIdentity(
        userId: 'user-a',
        email: 'usera@example.com',
        displayName: 'User A',
      );
      const userB = LedgerUserIdentity(
        userId: 'user-b',
        email: 'userb@example.com',
        displayName: 'User B',
      );

      final ready = Completer<void>();
      final controllerA = LedgerController(
        repo,
        setLoadState: (state) {
          if (state.isReady && !ready.isCompleted) ready.complete();
        },
        initialUser: userA,
      );
      addTearDown(controllerA.dispose);
      await ready.future;

      await controllerA.createStarterWallet(
        userId: 'user-a',
        accountName: 'User A Savings',
        currency: 'INR',
        accountColor: Colors.indigo,
        openingBalanceMinor: 25000,
      );
      final archiveFromA = controllerA.exportArchive();
      await controllerA.clearSessionOnSignOut();

      // User B logs in and attempts to import User A's archive
      await controllerA.setActiveUser(userB);
      await expectLater(
        controllerA.importArchive(archiveFromA),
        throwsA(
          predicate(
            (e) => e.toString().contains('different account'),
          ),
        ),
      );
      expect(controllerA.state.accounts, isEmpty);

      // Force restore succeeds and re-stamps userId to User B
      await controllerA.importArchive(archiveFromA, force: true);
      expect(controllerA.state.userId, 'user-b');
      expect(controllerA.state.accounts.single.name, 'User A Savings');
    });
  });
}
