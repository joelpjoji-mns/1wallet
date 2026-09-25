// Regression coverage for the "legacy per-document restore fallback" shape
// that `downloadLegacySnapshot()` in `walletSync.ts` builds when
// `wallet_backups` has no chunks yet (mirrors `_restoreFromCloud()`'s legacy
// branch in `lib/src/cloud_sync/cloud_sync_controller.dart`).
//
// `walletSync.ts` itself can't be unit-tested outside Vite (it transitively
// imports `./firebase`, which reads `import.meta.env.VITE_FIREBASE_*` — a
// Vite-only feature not available under plain `node --test`). This test
// instead exercises the exact transformation that matters: feeding
// `decodeSnapshot()` the same `{ preferences, accounts, categories,
// transactions, captureCandidates, importBatches }` shape Firestore's
// per-document collections produce, and asserting it comes out as a
// correctly-populated, unknown-field-preserving `LedgerSnapshot` — not an
// empty wallet. Run with: node --test src/lib/legacyRestoreFallback.test.ts

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { decodeSnapshot } from './ledgerCodec.ts';

/** Duck-typed Firestore `Timestamp`, like what `doc.data()` returns for a timestamp field. */
function fakeFirestoreTimestamp(date: Date) {
  return {
    toDate: () => date,
    toMillis: () => date.getTime(),
  };
}

test('legacy restore fallback: populates a non-empty snapshot instead of an empty wallet', () => {
  const legacyRestoreData = {
    preferences: {
      baseCurrency: 'EUR',
      displayCurrency: 'EUR',
      // Unknown/legacy-only field this web client doesn't model explicitly.
      somePreExistingSettingNotYetModeled: 'keep-me',
    },
    accounts: [
      {
        id: 'acc-1',
        name: 'Everyday Checking',
        type: 'bank',
        currency: 'EUR',
        openingBalance: { amountMinor: 50000, currency: 'EUR' },
        includeInTotals: true,
        includeInReports: true,
        includeInNetWorth: true,
        showOnHome: true,
        isArchived: false,
        sortOrder: 0,
        // Unknown field a newer/older Flutter version might have written.
        legacyOnlyField: 'preserve-me',
      },
    ],
    categories: [
      { id: 'cat-1', name: 'Groceries', kind: 'expense', isArchived: false, sortOrder: 0 },
    ],
    transactions: [
      {
        id: 'tx-1',
        type: 'expense',
        status: 'cleared',
        source: 'manual',
        accountId: 'acc-1',
        amount: { amountMinor: 1234, currency: 'EUR' },
        baseAmount: { amountMinor: 1234, currency: 'EUR' },
        // Legacy per-document collections may have Firestore Timestamp
        // values instead of ISO strings for date fields.
        occurredAt: fakeFirestoreTimestamp(new Date('2024-03-15T10:00:00Z')),
        recurrenceInterval: 1,
        attachments: [],
        isReimbursable: false,
        isTaxDeductible: false,
        isExcludedFromReports: false,
      },
    ],
    captureCandidates: [],
    importBatches: [],
  };

  const snapshot = decodeSnapshot(legacyRestoreData);

  // The wallet must come back populated, not empty.
  assert.equal(snapshot.accounts.length, 1);
  assert.equal(snapshot.categories.length, 1);
  assert.equal(snapshot.transactions.length, 1);

  assert.equal(snapshot.accounts[0]?.name, 'Everyday Checking');
  assert.equal(snapshot.accounts[0]?.openingBalance.amountMinor, 50000);
  // Unknown fields must round-trip via the `Extra` bag, not be dropped.
  assert.equal(snapshot.accounts[0]?.legacyOnlyField, 'preserve-me');
  assert.equal(snapshot.preferences.somePreExistingSettingNotYetModeled, 'keep-me');
  assert.equal(snapshot.preferences.baseCurrency, 'EUR');

  // Firestore Timestamp-shaped `occurredAt` must decode to a valid ISO string.
  assert.equal(snapshot.transactions[0]?.occurredAt, new Date('2024-03-15T10:00:00Z').toISOString());

  // Fields absent from the legacy restore shape (no syncSettings/exchangeRates
  // in this path) must fall back to sensible empty defaults, not crash.
  assert.equal(snapshot.syncSettings, null);
  assert.deepEqual(snapshot.exchangeRates, []);
});

test('legacy restore fallback: a brand-new user with no legacy documents decodes to a genuinely empty (not crashed) snapshot', () => {
  const snapshot = decodeSnapshot({
    preferences: null,
    accounts: [],
    categories: [],
    transactions: [],
    captureCandidates: [],
    importBatches: [],
  });

  assert.deepEqual(snapshot.accounts, []);
  assert.deepEqual(snapshot.categories, []);
  assert.deepEqual(snapshot.transactions, []);
  assert.equal(snapshot.preferences.baseCurrency, 'USD');
});
