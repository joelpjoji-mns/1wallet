import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';

void main() {
  group('Transaction tags and serialization', () {
    test('serializes and deserializes transaction tags', () {
      final tx = TransactionRecord(
        id: 'tx-1',
        type: 'expense',
        status: 'cleared',
        source: 'manual',
        accountId: 'acc-1',
        amount: const Money(amountMinor: 2500, currency: 'USD'),
        baseAmount: const Money(amountMinor: 2500, currency: 'USD'),
        occurredAt: DateTime(2026, 10, 15),
        notes: 'Grocery shopping',
        tags: const ['Food', 'Groceries', 'Weekly'],
      );

      final json = transactionToJson(tx);
      expect(json['tags'], ['Food', 'Groceries', 'Weekly']);

      final decoded = transactionFromJson(json);
      expect(decoded.tags, ['Food', 'Groceries', 'Weekly']);
      expect(decoded.notes, 'Grocery shopping');
    });

    test('defaults tags to empty list when missing in json', () {
      final json = <String, dynamic>{
        'id': 'tx-2',
        'type': 'expense',
        'status': 'cleared',
        'source': 'manual',
        'accountId': 'acc-1',
        'amount': {'amountMinor': 1000, 'currency': 'USD'},
        'occurredAt': DateTime(2026, 10, 15).toIso8601String(),
      };

      final decoded = transactionFromJson(json);
      expect(decoded.tags, isEmpty);
    });

    test('TransactionRecord copyWith updates tags', () {
      final tx = TransactionRecord(
        id: 'tx-1',
        type: 'expense',
        status: 'cleared',
        source: 'manual',
        accountId: 'acc-1',
        amount: const Money(amountMinor: 2500, currency: 'USD'),
        baseAmount: const Money(amountMinor: 2500, currency: 'USD'),
        occurredAt: DateTime(2026, 10, 15),
        tags: const ['Food'],
      );

      final updated = tx.copyWith(tags: ['Food', 'Dinner']);
      expect(updated.tags, ['Food', 'Dinner']);
    });
  });
}
