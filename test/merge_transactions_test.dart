import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LedgerProvidersConfig.disableAutoBackup = true;
  });

  tearDown(() {
    LedgerProvidersConfig.disableAutoBackup = false;
  });

  Future<LedgerController> setupController() async {
    const repository = LedgerRepository();
    final controller = LedgerController(repository);
    await Future<void>.delayed(Duration.zero);
    await controller.upsertAccount(
      id: 'acc-1',
      name: 'Checking Account',
      type: 'bank',
      currency: 'INR',
      openingBalanceMinor: 100000,
    );
    await controller.upsertAccount(
      id: 'acc-2',
      name: 'Savings Account',
      type: 'bank',
      currency: 'INR',
      openingBalanceMinor: 50000,
    );
    return controller;
  }

  test('merging transactions from the same account sums amount and combines details', () async {
    final controller = await setupController();
    addTearDown(controller.dispose);

    final tx1 = await controller.upsertTransaction(
      id: 'tx-1',
      type: 'expense',
      accountId: 'acc-1',
      amountMinor: 20000, // 200.00
      categoryId: 'cat-food',
      name: 'Coffee',
      occurredAt: DateTime(2026, 6, 1, 10, 0),
    );

    final tx2 = await controller.upsertTransaction(
      id: 'tx-2',
      type: 'expense',
      accountId: 'acc-1',
      amountMinor: 35000, // 350.00
      categoryId: 'cat-food',
      name: 'Lunch',
      occurredAt: DateTime(2026, 6, 1, 13, 0),
    );

    expect(controller.state.transactions, hasLength(2));

    final merged = await controller.mergeTransactions(
      transactionIds: {tx1.id, tx2.id},
    );

    expect(controller.state.transactions, hasLength(1));
    expect(merged.amount.amountMinor, 55000); // 200 + 350 = 550
    expect(merged.accountId, 'acc-1');
    expect(merged.categoryId, 'cat-food'); // Same category kept
    expect(merged.occurredAt, tx2.occurredAt); // Latest timestamp kept
  });

  test('merging allows overriding category if categories differed', () async {
    final controller = await setupController();
    addTearDown(controller.dispose);

    final tx1 = await controller.upsertTransaction(
      id: 'tx-a',
      type: 'expense',
      accountId: 'acc-1',
      amountMinor: 10000,
      categoryId: 'cat-groceries',
      name: 'Milk',
    );

    final tx2 = await controller.upsertTransaction(
      id: 'tx-b',
      type: 'expense',
      accountId: 'acc-1',
      amountMinor: 15000,
      categoryId: 'cat-utilities',
      name: 'Power',
    );

    final merged = await controller.mergeTransactions(
      transactionIds: {tx1.id, tx2.id},
      categoryId: 'cat-custom',
      name: 'Combined household',
    );

    expect(controller.state.transactions, hasLength(1));
    expect(merged.amount.amountMinor, 25000);
    expect(merged.categoryId, 'cat-custom');
    expect(merged.name, 'Combined household');
  });

  test('merging transactions from different accounts throws ArgumentError', () async {
    final controller = await setupController();
    addTearDown(controller.dispose);

    final tx1 = await controller.upsertTransaction(
      id: 'tx-x',
      type: 'expense',
      accountId: 'acc-1',
      amountMinor: 10000,
    );

    final tx2 = await controller.upsertTransaction(
      id: 'tx-y',
      type: 'expense',
      accountId: 'acc-2',
      amountMinor: 20000,
    );

    expect(
      () => controller.mergeTransactions(
        transactionIds: {tx1.id, tx2.id},
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
