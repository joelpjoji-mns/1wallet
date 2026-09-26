import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/cloud_sync/cloud_sync_controller.dart';
import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';

/// Regression coverage for `_parseCloudRestoreData()` (exposed for testing
/// via `parseCloudRestoreDataForTesting()`, since Dart's per-library privacy
/// otherwise hides a file-private top-level function from this test file)
/// passing `forceFullCategoryReferenceScan: true` to `normalizeLedgerState()`
/// — added alongside the core ledger change that introduced that parameter
/// (defaulting to `false`/no-op to preserve `LedgerController._commit()`'s
/// per-edit performance).
///
/// Cloud snapshots can describe a peer's ledger that diverged from this
/// device's own incrementally-consistent category set — e.g. a category
/// deleted on another device after this snapshot's transactions last
/// referenced it — so a restored snapshot can contain a transaction
/// referencing a category id that isn't in its own `categories` list at all.
/// `normalizeLedgerState()` only clears such dangling references when
/// `forceFullCategoryReferenceScan` is `true` (or an incidental category-name
/// merge already forces the same per-record rewrite); otherwise it leaves
/// them untouched, since assuming their absence is only safe for `_commit()`'s
/// own already-consistent local state.
void main() {
  test('regression: cloud restore clears a category reference dangling in the '
      'snapshot itself, proving _parseCloudRestoreData() forces the full '
      'category-reference scan instead of relying on the default fast '
      'no-op path', () {
    const account = Account(
      id: 'acc-1',
      name: 'Checking',
      type: 'checking',
      currency: 'USD',
      openingBalance: Money(amountMinor: 0, currency: 'USD'),
    );
    final orphanTransaction = TransactionRecord(
      id: 'tx-1',
      type: 'expense',
      status: 'posted',
      source: 'manual',
      accountId: account.id,
      amount: const Money(amountMinor: -500, currency: 'USD'),
      baseAmount: const Money(amountMinor: -500, currency: 'USD'),
      occurredAt: DateTime.utc(2026, 1, 1),
      // Neither a default life-taxonomy id nor present in `categories`
      // below, and not a known legacy alias — a genuinely dangling
      // reference with no merge/redirect to follow.
      categoryId: 'cat-does-not-exist-anywhere',
    );

    final restoreData = <String, dynamic>{
      'userId': 'user-1',
      'preferences': null,
      'accounts': [accountToJson(account)],
      // Deliberately empty: the referenced category was never included in
      // this snapshot (or was deleted on the writer's side), so nothing
      // here can "merge" it — only a forced full scan can catch this.
      'categories': <Map<String, dynamic>>[],
      'transactions': [transactionToJson(orphanTransaction)],
    };

    final restored = parseCloudRestoreDataForTesting(restoreData);

    expect(restored.transactions, hasLength(1));
    expect(
      restored.transactions.single.categoryId,
      isNull,
      reason:
          'forceFullCategoryReferenceScan: true must clear a category '
          'reference that is dangling in the restored snapshot itself, '
          'not just leave it as-is the way the default fast path would '
          '(which only rewrites records when an incidental category-name '
          'merge already forces it).',
    );
  });
}
