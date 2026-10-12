import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';

LedgerState _stateWith({
  required List<Category> categories,
  required List<TransactionRecord> transactions,
  int version = currentLedgerStateVersion,
}) {
  return LedgerState(
    version: version,
    userId: 'local-user',
    preferences: const LedgerPreferences(),
    accounts: const [],
    categories: categories,
    transactions: transactions,
    captureCandidates: const [],
  );
}

TransactionRecord _tx(String id, {String? categoryId}) {
  return TransactionRecord(
    id: id,
    type: 'expense',
    status: 'cleared',
    source: 'manual',
    accountId: 'acc-1',
    amount: const Money(amountMinor: 100, currency: 'USD'),
    baseAmount: const Money(amountMinor: 100, currency: 'USD'),
    occurredAt: DateTime(2026, 1, 1),
    categoryId: categoryId,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LedgerProvidersConfig.disableAutoBackup = true;
  });

  test(
    'normalizing a current-version ledger is an O(1) no-op that reuses the '
    'same transaction, category, and capture-candidate lists',
    () {
      final state = _stateWith(
        categories: defaultCategories(),
        transactions: [_tx('tx-1', categoryId: 'cat-food')],
      );

      final normalized = normalizeLedgerState(state);

      expect(identical(normalized, state), isTrue);
      expect(identical(normalized.transactions, state.transactions), isTrue);
      expect(
        identical(normalized.captureCandidates, state.captureCandidates),
        isTrue,
      );
    },
  );

  test(
    'normalizing a large current-version ledger never scans the transaction list',
    () {
      final bigTransactionList = [
        for (var i = 0; i < 50000; i++)
          _tx('tx-$i', categoryId: i.isEven ? 'cat-food' : 'cat-bills'),
      ];
      final state = _stateWith(
        categories: defaultCategories(),
        transactions: bigTransactionList,
      );

      final stopwatch = Stopwatch()..start();
      final normalized = normalizeLedgerState(state);
      stopwatch.stop();

      expect(identical(normalized.transactions, bigTransactionList), isTrue);
      expect(stopwatch.elapsedMilliseconds, lessThan(50));
    },
  );

  test(
    'decoding a ledger payload does not run legacy category migration and '
    'preserves categories as-is',
    () {
      final customState = _stateWith(
        categories: [
          ...defaultCategories(),
          const Category(id: 'custom-cat', name: 'My Custom', kind: 'expense'),
        ],
        transactions: [_tx('tx-1', categoryId: 'custom-cat')],
      );

      final roundTripped = decodeLedgerState(encodeLedgerState(customState));

      expect(roundTripped.version, currentLedgerStateVersion);
      expect(
        roundTripped.categories.any((c) => c.id == 'custom-cat'),
        isTrue,
      );
      expect(roundTripped.transactions.single.categoryId, 'custom-cat');
    },
  );

  test(
    'forceFullCategoryReferenceScan clears dangling category references '
    'while keeping valid transactions untouched',
    () {
      final untouched = _tx('tx-fine', categoryId: 'cat-food');
      final state = _stateWith(
        categories: defaultCategories(),
        transactions: [
          untouched,
          _tx('tx-orphan', categoryId: 'cat-deleted-long-ago'),
        ],
      );

      final defaultResult = normalizeLedgerState(state);
      expect(identical(defaultResult.transactions, state.transactions), isTrue);

      final forcedResult = normalizeLedgerState(
        state,
        forceFullCategoryReferenceScan: true,
      );
      expect(identical(forcedResult.transactions.first, untouched), isTrue);
      expect(forcedResult.transactions.last.categoryId, isNull);
    },
  );

  test(
    'resetCategoriesToDefault restores standard 100 categories and clears merchant rules',
    () async {
      final controller = LedgerController(
        const LedgerRepository(),
        initialState: _stateWith(
          categories: [
            const Category(id: 'custom-foo', name: 'Custom Foo', kind: 'expense'),
          ],
          transactions: [_tx('tx-1', categoryId: 'custom-foo')],
        ).copyWith(
          preferences: const LedgerPreferences(
            merchantCategoryRules: {'Merchant': 'custom-foo'},
          ),
        ),
      );
      addTearDown(controller.dispose);

      await controller.resetCategoriesToDefault();

      expect(controller.state.categories.length, defaultCategories().length);
      expect(
        controller.state.categories.where((c) => c.id == 'custom-foo'),
        isEmpty,
      );
      expect(controller.state.preferences.merchantCategoryRules, isEmpty);
      expect(controller.state.transactions.single.categoryId, isNull);
    },
  );
}
