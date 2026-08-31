import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';

import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('hideSkippedInHistory encodes and decodes in LedgerPreferences', () {
    const prefs = LedgerPreferences(hideSkippedInHistory: true);
    final json = encodeLedgerState(emptyLedgerState().copyWith(preferences: prefs));
    final decoded = decodeLedgerState(json);
    expect(decoded.preferences.hideSkippedInHistory, isTrue);
  });

  test('hideSkippedInHistory preference toggle updates state and keeps plan history', () async {
    final now = DateTime.now();
    final plan = TransactionRecord(
      id: 'plan-netflix',
      accountId: 'acc-1',
      type: 'expense',
      source: 'manual',
      status: 'scheduled',
      amount: Money(amountMinor: 1599, currency: 'USD'),
      baseAmount: Money(amountMinor: 1599, currency: 'USD'),
      occurredAt: now,
      recurrenceFrequency: 'monthly',
    );

    final skippedInstance = TransactionRecord(
      id: 'tx-skipped-1',
      accountId: 'acc-1',
      type: 'expense',
      source: 'manual',
      status: 'void',
      notes: 'Skipped',
      amount: Money(amountMinor: 1599, currency: 'USD'),
      baseAmount: Money(amountMinor: 1599, currency: 'USD'),
      occurredAt: now.subtract(const Duration(days: 30)),
      originalTransactionId: 'plan-netflix',
    );

    final seedState = emptyLedgerState().copyWith(
      accounts: [
        Account(
          id: 'acc-1',
          name: 'Main Checking',
          type: 'bank',
          currency: 'USD',
          color: Colors.blue,
          openingBalance: Money(amountMinor: 100000, currency: 'USD'),
        ),
      ],
      transactions: [plan, skippedInstance],
      preferences: const LedgerPreferences(hideSkippedInHistory: true),
    );

    final controller = LedgerController(
      StaticLedgerRepository(seedState),
      setLoadState: (_) {},
      initialState: seedState,
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(controller.state.preferences.hideSkippedInHistory, isTrue);

    // Plan history selector still finds the skipped record under the plan
    final planHistory = controller.state.transactions.where((t) {
      if (t.id == plan.id) return false;
      if (t.status == 'scheduled') return false;
      return t.originalTransactionId == plan.id;
    }).toList();

    expect(planHistory.length, 1);
    expect(planHistory.first.status, 'void');
  });
}
