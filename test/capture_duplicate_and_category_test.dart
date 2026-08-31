import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/capture/capture_pipeline.dart';
import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/capture/capture_diagnostics.dart';

import 'test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('duplicate detection blocks matching notification when SMS is already captured', () async {
    final seedState = emptyLedgerState().copyWith(
      accounts: [
        Account(
          id: 'acc-chase',
          name: 'Chase Checking',
          type: 'bank',
          currency: 'USD',
          accountLast4: '1234',
          cardLast4: '1234',
          color: Colors.blue,
          openingBalance: Money(amountMinor: 500000, currency: 'USD'),
        ),
        Account(
          id: 'acc-cash',
          name: 'Cash',
          type: 'cash',
          currency: 'USD',
          color: Colors.green,
          openingBalance: Money(amountMinor: 10000, currency: 'USD'),
        ),
      ],
      categories: [
        const Category(
          id: 'cat-subs',
          name: 'Subscriptions',
          color: Colors.purple,
          kind: 'expense',
        ),
        const Category(
          id: 'cat-dining',
          name: 'Dining',
          color: Colors.orange,
          kind: 'expense',
        ),
      ],
      preferences: LedgerPreferences(
        baseCurrency: 'USD',
        displayCurrency: 'USD',
        enabledCurrencies: ['USD'],
        merchantCategoryRules: {
          'netflix': 'cat-subs',
        },
      ),
    );

    final controller = LedgerController(
      StaticLedgerRepository(seedState),
      setLoadState: (_) {},
      initialState: seedState,
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));

    final now = DateTime.now();

    // 1. Import bank SMS
    final smsResult = await controller.importSmsMessageDetailed(
      'Chase: Your card ending in 1234 was charged \$15.99 at Netflix on 01-Sep.',
      receivedAt: now,
      forceQueue: true,
    );

    expect(smsResult.queued, isTrue);
    expect(smsResult.candidate?.suggestedAccountId, 'acc-chase');
    expect(smsResult.candidate?.suggestedCategoryId, 'cat-subs');
    expect(controller.state.captureCandidates.length, 1);

    // 2. Import Google Messages / app notification for the same transaction arriving seconds later
    // Without full account info in notification
    final notificationResult = await controller.importNotificationMessageDetailed(
      'Google Pay: Paid \$15.99 to Netflix',
      receivedAt: now.add(const Duration(seconds: 2)),
      forceQueue: true,
    );

    expect(notificationResult.status, CaptureImportStatus.duplicate);
    expect(notificationResult.queued, isFalse);
    expect(controller.state.captureCandidates.length, 1);
  });
}
