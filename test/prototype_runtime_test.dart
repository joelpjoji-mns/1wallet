import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/app/prototype_main.dart';
import 'package:one_wallet_flutter/src/app/prototype_sample.dart';
import 'package:one_wallet_flutter/src/auth/app_mode.dart';
import 'package:one_wallet_flutter/src/auth/auth_controller.dart';
import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/features/login/login_screen.dart';
import 'package:one_wallet_flutter/src/features/notifications/notification_engine.dart';
import 'package:one_wallet_flutter/src/ledger/ledger_selectors.dart';
import 'package:one_wallet_flutter/src/startup/startup_state.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/utils/secure_key_store.dart';

import 'offline_mode_fakes.dart';
import 'test_harness.dart';

void main() {
  test('prototype encryption keys never reach persistent storage', () async {
    final original = FlutterSecureStoragePlatform.instance;
    addTearDown(() => FlutterSecureStoragePlatform.instance = original);
    final memory = PrototypeSecureStorage();
    FlutterSecureStoragePlatform.instance = memory;
    final cipher = await SecureKeyStore.encrypt(
      'fictitious account details',
      userId: 'prototype-test-owner',
    );
    expect(
      await SecureKeyStore.decrypt(cipher, userId: 'prototype-test-owner'),
      'fictitious account details',
    );
    expect(await memory.readAll(options: {}), isNotEmpty);
    expect(await PrototypeSecureStorage().readAll(options: {}), isEmpty);
  });
  test(
    'prototype ledger edits are isolated and reset with a fresh store',
    () async {
      final seed = prototypeSample(DateTime(2026, 11, 26));
      final first = PrototypeLedgerRepository(seed);
      final second = PrototypeLedgerRepository(seed);
      await first.save(seed.copyWith(transactions: []));
      expect((await first.load())!.transactions, isEmpty);
      expect((await second.load())!.transactions, isNotEmpty);
      await first.clear();
      expect(await first.load(), isNull);
      expect((await second.load())!.accounts, isNotEmpty);
    },
  );

  test('prototype sample references resolve to real sample entities', () {
    final seed = prototypeSample(DateTime(2026, 11, 26));
    final accounts = seed.accounts.map((a) => a.id).toSet();
    final categories = seed.categories.map((c) => c.id).toSet();
    for (final record in seed.transactions) {
      expect(accounts, contains(record.accountId));
      if (record.counterAccountId != null) {
        expect(accounts, contains(record.counterAccountId));
      }
      expect(categories, contains(record.categoryId));
    }
    expect(
      seed.transactions.map((r) => r.id).toSet(),
      hasLength(seed.transactions.length),
    );
    expect(seed.transactions.length, greaterThanOrEqualTo(800));
    expect(
      seed.accounts.map((a) => a.type).toSet(),
      containsAll([
        'bank',
        'cash',
        'wallet',
        'savings',
        'investment',
        'credit_card',
        'loan',
        'overdraft',
      ]),
    );
    expect(seed.preferences.enabledCurrencies, hasLength(6));
    for (var month = 1; month <= 12; month++) {
      expect(
        seed.transactions.any(
          (r) =>
              r.occurredAt.year == 2025 &&
              r.occurredAt.month == month &&
              r.status == 'cleared',
        ),
        isTrue,
        reason: 'The previous year must have usable activity in every month.',
      );
    }
    final rent = seed.transactions.firstWhere((r) => r.id == 'demo-rent');
    final emi = seed.transactions.firstWhere((r) => r.id == 'demo-emi');
    expect(recurringPlanPaymentSummary(seed, rent).paymentCount, 30);
    expect(recurringPlanPaymentSummary(seed, emi).paymentCount, 24);
    final paidLoan = seed.accounts.firstWhere((a) => a.id == 'demo-paid-loan');
    expect(isPastLoan(seed, paidLoan), isTrue);
    expect(accountBalance(seed, paidLoan).amountMinor, 0);
    expect(scheduledTransactions(seed).length, greaterThanOrEqualTo(20));
    expect(seed.captureCandidates.length, greaterThanOrEqualTo(10));
    for (final capture in seed.captureCandidates) {
      expect(capture.parsedAmount, isNotNull);
      expect(capture.rawText, isNotEmpty);
    }
  });

  test('demo inbox covers every supported alert on month boundaries', () {
    for (final now in [
      DateTime(2026, 11, 26),
      DateTime(2026, 2, 1),
      DateTime(2026, 12, 31),
    ]) {
      final seed = prototypeSample(now);
      final notifications = buildNotificationInbox(seed, now: now);
      for (final prefix in [
        'scheduled_overdue_',
        'scheduled_soon_',
        'card_overdue_',
        'card_due_',
        'card_statement_',
      ]) {
        expect(
          notifications.any((n) => n.id.startsWith(prefix)),
          isTrue,
          reason: '$prefix must be populated at $now',
        );
      }
      expect(notifications.any((n) => n.read), isTrue);
      expect(notifications.any((n) => !n.read), isTrue);
      expect(
        seed.transactions
            .where((r) => r.status == 'cleared')
            .every(
              (r) => !r.occurredAt.isAfter(
                DateTime(now.year, now.month, now.day, 23, 59),
              ),
            ),
        isTrue,
      );
    }
  });

  testWidgets('prototype opens gated UI without changing production startup', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      AppModeStore.storageKey: AppMode.offline.name,
    });
    final prefs = await SharedPreferences.getInstance();
    final auth = FakeAuthRepository(available: false);
    final container = ProviderContainer(
      overrides: [
        ...authenticatedSampleOverrides(
          ledger: emptyLedgerState(),
          prefs: prefs,
        ),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(container.dispose);
    final router = createPrototypeRouter(initialLocation: '/login');
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(),
        ),
      ),
    );
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(
      container.read(startupStateProvider).destination,
      StartupDestination.home,
    );
    expect(container.read(authControllerProvider).isLocalOnly, isTrue);
    expect(auth.signInCalls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
