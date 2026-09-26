// Regression tests for `_migrateCategoryTaxonomy` (via `normalizeLedgerState`)
// in ledger_codec.dart.
//
// Three things are covered here:
//
// 1. Performance: `normalizeLedgerState` runs on every `LedgerController`
//    commit (i.e. every user edit), not just on load/import/restore. The
//    category-taxonomy pass must not do *any* O(ledger size) work in the
//    common case — not a per-record rebuild, and not even a scan just to
//    check whether a rebuild is needed (e.g. collecting every referenced
//    category id). Whether records need touching is decided purely from
//    O(categories) signals: did any category actually get merged/renamed,
//    or is this a genuinely legacy ledger (`version` below current) that
//    might carry dangling references. `_commit` always passes a ledger
//    already at `currentLedgerStateVersion`, so on that hot path — as long
//    as categories are already canonical — nothing about the transaction/
//    capture-candidate/rule lists is even inspected.
//
// 2. Correctness: category ids that don't correspond to any known category
//    (dangling/orphaned references) are cleared to `null` when migrating a
//    legacy ledger (`version` below current), which is the only place such
//    references can legitimately still be found (in-app mutations can never
//    introduce one — see `LedgerController.deleteCategory`, which archives
//    rather than removes an in-use category). The naive
//    `record.copyWith(categoryId: redirectCategoryId(x))` pattern can't
//    actually express "clear to null" because `copyWith` uses
//    `x ?? this.x`, so a `null` result quietly falls back to the old
//    (invalid) value unless the record is rebuilt directly.
//
// 3. Root cause of why (1) is even possible: a handful of default
//    categories (`cat-sales`, `cat-cashback`, `cat-vehicle`,
//    `cat-parking-tolls`, `cat-vehicle-insurance`, `cat-charges`,
//    `cat-lending`, `cat-movies`) are themselves superseded by an alias
//    entry in `preferredByName` (their own name normalizes to a *different*
//    canonical id). The taxonomy pass used to unconditionally re-add every
//    default category to its output regardless, which resurrected these
//    "retired" ids on *every single normalization pass forever* — so
//    `idRedirect` could never reach a stable identity mapping, and the
//    cheap "did a merge happen" check would always report `true` for any
//    real wallet, permanently defeating the perf fix in (1). They're now
//    excluded from that unconditional re-add.
//
// 4. Escape hatch: `normalizeLedgerState` accepts an opt-in
//    `forceFullCategoryReferenceScan` flag so a trusted caller that builds a
//    `LedgerState` from raw foreign data while still stamping it at
//    `currentLedgerStateVersion` (e.g. cloud restore via
//    `emptyLedgerState(...).copyWith(...)`, where the version check alone
//    can't detect it needs migrating) can force the full scan and still get
//    dangling references cleared, without slowing down the default
//    (`_commit`'s hot-path) behavior for everyone else.
import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';

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

// `defaultCategories()` (the raw seed taxonomy used for brand-new wallets)
// is not itself alias-free: it still contains a few legacy ids (e.g.
// `cat-charges`, `cat-fines`) that the alias table always redirects into a
// newer canonical id (`cat-bank-fees`) the first time normalization runs.
// That's expected — a fresh wallet gets fully canonicalized on its very
// first commit, and every commit after that is a true no-op. So "already
// canonical" test fixtures must use the *post*-normalization category list,
// not the raw seed list, to accurately represent what `_commit`'s hot path
// actually sees on every edit after the first.
List<Category> _canonicalCategories() {
  final seeded = _stateWith(
    categories: defaultCategories(),
    transactions: const [],
  );
  return normalizeLedgerState(seeded).categories;
}

void main() {
  test(
    'normalizing an already-canonical current-version ledger reuses the '
    'same transaction and capture-candidate lists instead of rebuilding '
    'them',
    () {
      final state = _stateWith(
        categories: _canonicalCategories(),
        transactions: [_tx('tx-1', categoryId: 'cat-food')],
      );

      final normalized = normalizeLedgerState(state);

      // Identical (not just equal) list/element references prove the
      // expensive per-record rebuild was skipped entirely.
      expect(identical(normalized.transactions, state.transactions), isTrue);
      expect(
        identical(normalized.captureCandidates, state.captureCandidates),
        isTrue,
      );
    },
  );

  test(
    'normalizing a large current-version ledger with canonical categories '
    'never scans the transaction list at all (root-cause perf fix, not '
    'just fewer allocations)',
    () {
      // 50k transactions is enough that even a cheap O(n) pass (e.g. just
      // building a Set of referenced category ids, with no record copies)
      // would take measurably non-trivial time. If this stays fast and the
      // returned list is the *same* object, the taxonomy pass never touched
      // the transactions at all — proving the check itself, not just the
      // rebuild, is O(categories).
      final bigTransactionList = [
        for (var i = 0; i < 50000; i++)
          _tx('tx-$i', categoryId: i.isEven ? 'cat-food' : 'cat-bills'),
      ];
      final state = _stateWith(
        categories: _canonicalCategories(),
        transactions: bigTransactionList,
      );

      final stopwatch = Stopwatch()..start();
      final normalized = normalizeLedgerState(state);
      stopwatch.stop();

      expect(identical(normalized.transactions, bigTransactionList), isTrue);
      // Generous bound: a real O(n) scan/rebuild of 50k records is orders
      // of magnitude slower than this in practice; this just guards
      // against a regression back to per-edit O(n) work.
      expect(stopwatch.elapsedMilliseconds, lessThan(200));
    },
  );

  test(
    'a duplicate custom category is merged into the canonical id and '
    'referencing transactions are redirected to it, even at the current '
    'version',
    () {
      final state = _stateWith(
        categories: [
          ...defaultCategories(),
          const Category(id: 'custom-bills', name: 'Bills', kind: 'expense'),
        ],
        transactions: [_tx('tx-1', categoryId: 'custom-bills')],
      );

      final normalized = normalizeLedgerState(state);

      expect(
        normalized.categories.where((c) => c.id == 'custom-bills'),
        isEmpty,
      );
      expect(
        normalized.categories.where((c) => c.id == 'cat-bills'),
        hasLength(1),
      );
      expect(normalized.transactions.single.categoryId, 'cat-bills');
    },
  );

  test(
    'a legacy (older-version) snapshot with a category id that does not '
    'exist at all is normalized and the dangling reference is cleared to '
    'null',
    () {
      final state = _stateWith(
        categories: defaultCategories(),
        transactions: [_tx('tx-orphan', categoryId: 'cat-deleted-long-ago')],
        version: currentLedgerStateVersion - 1,
      );

      final normalized = normalizeLedgerState(state);

      expect(normalized.version, currentLedgerStateVersion);
      expect(normalized.transactions.single.categoryId, isNull);
    },
  );

  test(
    'currentLedgerStateVersion is 17: locks in the one-time bump that '
    'forces every already-persisted v16 local ledger through exactly one '
    'more full category-reference scan before settling on the v17 fast '
    'path',
    () {
      expect(currentLedgerStateVersion, 17);
    },
  );

  test(
    'decoding an already-persisted v16 ledger payload (pre-bump backward '
    'compatibility) with a dangling category reference self-heals it on '
    'this one decode and re-stamps the ledger at v17',
    () {
      // Build the payload the way a real pre-bump (v16) install would have
      // persisted it: a `LedgerState` explicitly stamped at the old
      // version, encoded with the real `encodeLedgerState` so the JSON
      // shape matches production exactly (no hand-rolled JSON).
      final legacyState = _stateWith(
        categories: defaultCategories(),
        transactions: [_tx('tx-orphan', categoryId: 'cat-deleted-long-ago')],
        version: 16,
      );
      final legacyJson = encodeLedgerState(legacyState);
      expect(legacyJson, contains('"version":16'));

      final restored = decodeLedgerState(legacyJson);

      expect(restored.version, 17);
      expect(restored.transactions.single.categoryId, isNull);
    },
  );

  test(
    'decoding a v17 ledger payload with already-canonical categories is a '
    'true no-op fast path: round-tripping through encode/decode again '
    'reuses the same transaction list',
    () {
      final canonicalState = _stateWith(
        categories: _canonicalCategories(),
        transactions: [_tx('tx-1', categoryId: 'cat-food')],
      );
      expect(canonicalState.version, 17);

      final roundTripped = decodeLedgerState(encodeLedgerState(canonicalState));

      expect(roundTripped.version, 17);
      expect(roundTripped.transactions.single.categoryId, 'cat-food');
      // A second normalize (as `_commit` does on every edit) must still be
      // the same O(categories) no-op after a real encode/decode round trip,
      // not just for an in-memory `LedgerState` built directly in tests.
      final secondPass = normalizeLedgerState(roundTripped);
      expect(
        identical(secondPass.transactions, roundTripped.transactions),
        isTrue,
      );
    },
  );

  test(
    'within a legacy-snapshot migration, only the transaction with a '
    'dangling category reference is rebuilt; unaffected transactions keep '
    'their object identity',
    () {
      final untouched = _tx('tx-fine', categoryId: 'cat-food');
      final state = _stateWith(
        categories: defaultCategories(),
        transactions: [
          untouched,
          _tx('tx-orphan', categoryId: 'cat-deleted-long-ago'),
        ],
        version: currentLedgerStateVersion - 1,
      );

      final normalized = normalizeLedgerState(state);

      expect(
        identical(normalized.transactions.first, untouched),
        isTrue,
        reason:
            'transactions with no dangling/redirected category should not '
            'be reallocated when others in the ledger do need a rewrite',
      );
      expect(normalized.transactions.last.categoryId, isNull);
    },
  );

  test(
    'documents the accepted default trade-off: a dangling category '
    'reference in an already current-version ledger (which in-app '
    'mutations cannot produce) is left as-is by default, rather than '
    'paying an O(n) scan on every commit to look for it — but a trusted '
    'caller can opt into the full scan via '
    '`forceFullCategoryReferenceScan` to clear it anyway',
    () {
      final state = _stateWith(
        categories: _canonicalCategories(),
        transactions: [_tx('tx-orphan', categoryId: 'cat-deleted-long-ago')],
      );

      // Default (used by `_commit`'s hot path): fast, no-op, orphan kept.
      final defaultResult = normalizeLedgerState(state);
      expect(
        identical(defaultResult.transactions, state.transactions),
        isTrue,
        reason: 'default must not scan transactions at all',
      );
      expect(
        defaultResult.transactions.single.categoryId,
        'cat-deleted-long-ago',
      );

      // Opt-in (for trusted callers like cloud restore, which stamp
      // current-version `LedgerState`s built from raw foreign data): full
      // scan runs and the dangling reference is cleared.
      final forcedResult = normalizeLedgerState(
        state,
        forceFullCategoryReferenceScan: true,
      );
      expect(forcedResult.transactions.single.categoryId, isNull);
    },
  );

  test(
    'default categories that are themselves superseded by an alias (e.g. '
    '"Charges" -> cat-bank-fees) disappear after one normalization pass '
    'and never reappear, so idRedirect reaches a stable identity mapping',
    () {
      final firstPass = normalizeLedgerState(
        _stateWith(categories: defaultCategories(), transactions: const []),
      );
      const supersededIds = {
        'cat-sales',
        'cat-cashback',
        'cat-vehicle',
        'cat-parking-tolls',
        'cat-vehicle-insurance',
        'cat-charges',
        'cat-lending',
        'cat-movies',
      };
      final firstPassIds = firstPass.categories.map((c) => c.id).toSet();
      for (final id in supersededIds) {
        expect(
          firstPassIds.contains(id),
          isFalse,
          reason: '$id should have been merged away, not resurrected',
        );
      }

      // A second pass over the now-canonical list must be a complete no-op:
      // this is what guarantees `_commit`'s hot path can stay O(1).
      final secondPass = normalizeLedgerState(firstPass);
      expect(
        secondPass.categories.map((c) => c.id).toSet(),
        firstPassIds,
      );
      expect(secondPass.categories.length, firstPass.categories.length);
    },
  );

  test(
    'a transaction referencing a soon-to-be-retired default id (e.g. the '
    'legacy cat-charges) is redirected to its replacement, not dropped, '
    'when that legacy ledger is first migrated',
    () {
      final state = _stateWith(
        categories: defaultCategories(),
        transactions: [_tx('tx-1', categoryId: 'cat-charges')],
        version: currentLedgerStateVersion - 1,
      );

      final normalized = normalizeLedgerState(state);

      expect(normalized.transactions.single.categoryId, 'cat-bank-fees');
      expect(
        normalized.categories.where((c) => c.id == 'cat-charges'),
        isEmpty,
      );
    },
  );
}
