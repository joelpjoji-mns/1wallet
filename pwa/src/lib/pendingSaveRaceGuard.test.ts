// Focused regression coverage for the "onSnapshot/persist can silently
// discard a local edit" race in `WalletDataContext.tsx`.
//
// Two distinct scenarios were found and fixed together, both stemming from
// the same root cause — a background reload being allowed to replace
// in-memory `snapshot` state while this client still has an edit that
// hasn't successfully reached the cloud yet:
//
// 1. The realtime `onSnapshot` listener used to call `startLoad(uid)`
//    whenever the cloud state differed from `lastKnownMetaRef`, with no
//    regard for whether a debounced local edit was still queued
//    (`PendingSaveGuard.hasPending()`) or actively being written
//    (`savingSelfRef`). Even though `load()`'s own `shouldAcceptCloudLoad()`
//    check would ultimately refuse to apply the download in that case, the
//    listener still kicked off a wasted download/decode and a premature
//    "local changes not uploaded yet" message on every ordinary
//    keystroke-to-save debounce window — not just a genuine race.
//    `shouldAutoLoadOnRemoteChange()` now gates the decision to even start
//    that reload on the same `hasUnsyncedLocalChanges` signal.
//
// 2. Far more seriously: `persist()`'s `WalletSyncConflictError` handler
//    used to call `startLoad(uid)` immediately after a conflicting write
//    failed. By that point, `scheduleSave()`'s debounce timer had already
//    dequeued the failed edit via `PendingSaveGuard.take()` — so once the
//    triggered reload's download resolved, there was no pending save left
//    to protect it, `shouldAcceptCloudLoad()` happily accepted the fresh
//    cloud snapshot, and `commitSnapshot()` silently overwrote the user's
//    in-memory edit — the exact edit the error message claimed the user
//    should "reapply". The fix re-queues the failed payload
//    (`saveGuardRef.current.schedule(uid, { snapshot: next, profile })`)
//    instead of auto-reloading, so it keeps protecting itself via the same
//    `hasUnsyncedLocalChanges` gate used everywhere else, until an explicit
//    user-confirmed action resolves the conflict — see the
//    "discardConflictAndReload" tests below for that action's own pure
//    logic (`PendingSaveGuard.clear()` unblocking the same gates).
//
// This file exercises the exact pure decisions both paths depend on —
// `PendingSaveGuard`, `shouldAcceptCloudLoad()`, and
// `shouldAutoLoadOnRemoteChange()` — end to end, without needing to render
// `WalletDataContext` itself (which can't be imported outside Vite; see
// `walletSyncGuards.test.ts`'s file header for why).
//
// Run with: node --test src/lib/pendingSaveRaceGuard.test.ts

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { PendingSaveGuard } from './pendingSaveGuard.ts';
import {
  shouldAcceptCloudLoad,
  shouldAutoLoadOnRemoteChange,
  type ConflictBaseline,
} from './walletSyncGuards.ts';

interface Payload {
  snapshot: string; // stand-in for LedgerSnapshot; content is irrelevant to these guards
}

test('realtime listener: a debounced-but-not-yet-sent edit blocks auto-reload even though the cloud has moved', () => {
  const guard = new PendingSaveGuard<Payload>();
  guard.setActiveUid('user-a');
  guard.schedule('user-a', { snapshot: 'unsaved local edit' });

  const baseline: ConflictBaseline = { cloudRevision: 3, updatedAtToken: 1000 };
  const cloud: ConflictBaseline = { cloudRevision: 4, updatedAtToken: 2000 }; // another device wrote meanwhile

  const hasUnsyncedLocalChanges = guard.hasPending();
  assert.equal(hasUnsyncedLocalChanges, true);
  assert.equal(
    shouldAutoLoadOnRemoteChange({ cloud, baseline, hasUnsyncedLocalChanges }),
    false,
    'a pending debounced edit must block the realtime listener from auto-reloading over it',
  );
});

test('realtime listener: an in-flight persist() (no longer "pending", but still unsynced) also blocks auto-reload', () => {
  const guard = new PendingSaveGuard<Payload>();
  guard.setActiveUid('user-a');
  guard.schedule('user-a', { snapshot: 'edit about to be sent' });
  guard.take(); // simulates the debounce timer firing and persist() starting
  assert.equal(guard.hasPending(), false, 'take() dequeues it — no longer "pending" by itself');

  const savingSelf = true; // persist() has set this synchronously before its first await
  const baseline: ConflictBaseline = { cloudRevision: 3, updatedAtToken: 1000 };
  const cloud: ConflictBaseline = { cloudRevision: 4, updatedAtToken: 2000 };

  const hasUnsyncedLocalChanges = guard.hasPending() || savingSelf;
  assert.equal(
    shouldAutoLoadOnRemoteChange({ cloud, baseline, hasUnsyncedLocalChanges }),
    false,
    'an in-flight write must also block auto-reload, even though PendingSaveGuard alone no longer reports it as pending',
  );
});

test('realtime listener: with no unsynced changes at all, a real cloud advance is still auto-loaded', () => {
  const guard = new PendingSaveGuard<Payload>();
  guard.setActiveUid('user-a');

  const baseline: ConflictBaseline = { cloudRevision: 3, updatedAtToken: 1000 };
  const cloud: ConflictBaseline = { cloudRevision: 4, updatedAtToken: 2000 };

  assert.equal(
    shouldAutoLoadOnRemoteChange({ cloud, baseline, hasUnsyncedLocalChanges: guard.hasPending() }),
    true,
    'the whole point of the listener: a genuine remote change with nothing local to protect must still auto-reload',
  );
});

test('conflict handling: re-queuing the failed edit after WalletSyncConflictError protects it from a subsequent realtime auto-reload', () => {
  const guard = new PendingSaveGuard<Payload>();
  guard.setActiveUid('user-a');

  // scheduleSave() queues the edit, the debounce timer fires and dequeues
  // it via take() to attempt persist()...
  guard.schedule('user-a', { snapshot: 'the edit that will conflict' });
  const dequeued = guard.take();
  assert.ok(dequeued);
  assert.equal(guard.hasPending(), false);

  // ...persist()'s write conflicts. The fixed catch handler re-queues the
  // same payload instead of calling startLoad() immediately.
  guard.schedule(dequeued.uid, dequeued.payload);
  assert.equal(guard.hasPending(), true, "the failed edit must be marked pending again after a conflict");

  // A realtime update for a *different* remote write arrives right after —
  // it must not be allowed to silently discard the still-unsaved edit.
  const baseline: ConflictBaseline = { cloudRevision: 5, updatedAtToken: 5000 };
  const cloudAfterYetAnotherWrite: ConflictBaseline = { cloudRevision: 6, updatedAtToken: 6000 };
  assert.equal(
    shouldAutoLoadOnRemoteChange({
      cloud: cloudAfterYetAnotherWrite,
      baseline,
      hasUnsyncedLocalChanges: guard.hasPending(),
    }),
    false,
    "the re-queued failed edit must still block auto-reload — it hasn't been saved or explicitly discarded",
  );
});

// Directly answers "does a conflict retain the pending snapshot?" with a
// financial-shaped payload: the re-queued payload must be the *exact* same
// object/content the failed write attempted — never merged, patched, or
// otherwise reconciled with whatever the (unknown-to-this-client) live cloud
// state currently is. `WalletDataContext.persist()` has no cloud read at the
// point it catches `WalletSyncConflictError` (the transaction aborted before
// telling it anything about the live document beyond "it didn't match"), so
// any kind of merge here would necessarily be guessing — for financial data
// (amounts, account balances, transaction lists) a guessed merge is exactly
// the kind of silent corruption this whole conflict protocol exists to
// prevent. Retention-not-merge is the only safe option until the user
// explicitly reloads and re-applies their edit against the real cloud state.
test('conflict handling: retains the exact pending snapshot content — no merge/patch with the live cloud state', () => {
  interface FinancialPayload {
    snapshot: {
      accounts: { id: string; balanceMinor: number }[];
      transactions: { id: string; amountMinor: number }[];
    };
    profile: { email: string | null };
  }

  const guard = new PendingSaveGuard<FinancialPayload>();
  guard.setActiveUid('user-a');

  const attemptedEdit: FinancialPayload = {
    snapshot: {
      accounts: [{ id: 'acc-1', balanceMinor: 543_21 }],
      transactions: [{ id: 'tx-1', amountMinor: -1200 }],
    },
    profile: { email: 'owner@example.com' },
  };

  guard.schedule('user-a', attemptedEdit);
  const dequeued = guard.take();
  assert.ok(dequeued);

  // The conflict handler re-queues exactly what it received — no
  // reconciliation logic of any kind touches it.
  guard.schedule(dequeued.uid, dequeued.payload);

  const retained = guard.take();
  assert.ok(retained);
  assert.deepEqual(
    retained.payload,
    attemptedEdit,
    'the retained payload must be byte-for-byte identical to the original attempted edit — no merge, no patch, no partial application',
  );
  // Same object identity too, not just deep-equal content: proves nothing
  // ever cloned/rebuilt it along the way (a rebuild step would be exactly
  // where an accidental merge could sneak in).
  assert.equal(retained.payload, attemptedEdit);
});

test('conflict handling: re-queuing the failed edit also protects it from a manual refresh() overwriting it', () => {
  const guard = new PendingSaveGuard<Payload>();
  guard.setActiveUid('user-a');
  guard.schedule('user-a', { snapshot: 'the edit that will conflict' });
  const dequeued = guard.take();
  assert.ok(dequeued);
  guard.schedule(dequeued.uid, dequeued.payload); // re-queued after the conflict, as `persist()` now does

  // `refresh()` funnels through the exact same `load()` -> `shouldAcceptCloudLoad`
  // gate a realtime update does — it must not silently discard the edit either.
  assert.equal(
    shouldAcceptCloudLoad({ hasUnsyncedLocalChanges: guard.hasPending() }),
    false,
    "refresh() must not silently discard a re-queued, still-unsaved edit after a conflict",
  );
});

test('conflict handling: once the edit is genuinely gone (guard cleared), both auto-reload and refresh() work normally again', () => {
  const guard = new PendingSaveGuard<Payload>();
  guard.setActiveUid('user-a');
  guard.schedule('user-a', { snapshot: 'edit' });
  guard.take();
  // No re-queue this time — e.g. the conflict resolved a different way, or
  // this models a plain successful save with nothing left pending.
  assert.equal(guard.hasPending(), false);

  const baseline: ConflictBaseline = { cloudRevision: 5, updatedAtToken: 5000 };
  const cloud: ConflictBaseline = { cloudRevision: 6, updatedAtToken: 6000 };
  assert.equal(
    shouldAutoLoadOnRemoteChange({ cloud, baseline, hasUnsyncedLocalChanges: guard.hasPending() }),
    true,
  );
  assert.equal(shouldAcceptCloudLoad({ hasUnsyncedLocalChanges: guard.hasPending() }), true);
});

// ---------------------------------------------------------------------------
// discardConflictAndReload
//
// `WalletDataContext.discardConflictAndReload()` is the explicit,
// user-confirmed action wired to `Workspace.tsx`'s `ConflictBanner` button
// ("Discard unsaved edit and load cloud"). It exists because, before it, a
// conflicted edit had nowhere to go: `refresh()` has no UI consumer, and
// `SyncBadge` only ever rendered a small `<span>` with no way to act on it —
// so once a write conflicted, the re-queued edit stayed pending forever,
// correctly blocking every load path but with no way to ever *resolve* it
// short of an unannounced full page reload.
//
// Its implementation is exactly `saveGuardRef.current.clear()` (never reads
// or merges the discarded payload) followed by a normal `startLoad(uid)`.
// These tests model that exact sequence with `PendingSaveGuard.clear()`.
// ---------------------------------------------------------------------------

test('discardConflictAndReload: the conflicted edit remains pending — and blocks every load path — until this action actually runs', () => {
  const guard = new PendingSaveGuard<Payload>();
  guard.setActiveUid('user-a');

  // A save conflicted and was re-queued, exactly as `persist()`'s
  // `WalletSyncConflictError` handler does.
  guard.schedule('user-a', { snapshot: 'the edit that conflicted' });
  const dequeued = guard.take();
  assert.ok(dequeued);
  guard.schedule(dequeued.uid, dequeued.payload);
  assert.equal(guard.hasPending(), true);

  const baseline: ConflictBaseline = { cloudRevision: 5, updatedAtToken: 5000 };
  const cloudAfterYetAnotherWrite: ConflictBaseline = { cloudRevision: 6, updatedAtToken: 6000 };

  // Before the user clicks "Discard unsaved edit and load cloud", the edit
  // must still block both an incidental realtime update...
  assert.equal(
    shouldAutoLoadOnRemoteChange({
      cloud: cloudAfterYetAnotherWrite,
      baseline,
      hasUnsyncedLocalChanges: guard.hasPending(),
    }),
    false,
    'the pending edit must still be retained/protected before the user explicitly confirms discarding it',
  );
  // ...and a plain refresh() attempt.
  assert.equal(
    shouldAcceptCloudLoad({ hasUnsyncedLocalChanges: guard.hasPending() }),
    false,
    'refresh() must also still be blocked before the explicit discard action runs',
  );
  // The retained payload itself must still be exactly what the user typed —
  // nothing has touched or cleared it yet.
  assert.deepEqual(dequeued.payload, { snapshot: 'the edit that conflicted' });
});

test('discardConflictAndReload: clearing the guard (the action\'s actual implementation) unblocks every load path immediately', () => {
  const guard = new PendingSaveGuard<Payload>();
  guard.setActiveUid('user-a');
  guard.schedule('user-a', { snapshot: 'the edit that conflicted' });
  const dequeued = guard.take();
  assert.ok(dequeued);
  guard.schedule(dequeued.uid, dequeued.payload);
  assert.equal(guard.hasPending(), true, 'sanity: conflicted edit is pending before the user confirms discarding it');

  // The user clicks "Discard unsaved edit and load cloud" —
  // `discardConflictAndReload()` calls exactly this, and nothing else, to
  // drop the edit (never reading or merging its content).
  guard.clear();
  assert.equal(guard.hasPending(), false, 'the edit must be gone immediately once the user confirms the discard');

  // Both load paths must now proceed normally, exactly as if there had
  // never been an unsynced edit at all.
  const baseline: ConflictBaseline = { cloudRevision: 5, updatedAtToken: 5000 };
  const verifiedLiveCloud: ConflictBaseline = { cloudRevision: 6, updatedAtToken: 6000 };
  assert.equal(
    shouldAutoLoadOnRemoteChange({
      cloud: verifiedLiveCloud,
      baseline,
      hasUnsyncedLocalChanges: guard.hasPending(),
    }),
    true,
    'a subsequent load (the one discardConflictAndReload() itself triggers via startLoad()) must now be allowed through',
  );
  assert.equal(shouldAcceptCloudLoad({ hasUnsyncedLocalChanges: guard.hasPending() }), true);
});

test('discardConflictAndReload: clearing for the active uid never resurrects a pending save queued for a since-switched-away user', () => {
  // Defense-in-depth: if the user somehow signed out/switched accounts
  // between the conflict and clicking discard, `setActiveUid()` (called by
  // the uid-switch effect) would already have dropped the stale entry —
  // `clear()` on an already-empty guard is a safe no-op either way.
  const guard = new PendingSaveGuard<Payload>();
  guard.setActiveUid('user-a');
  guard.schedule('user-a', { snapshot: 'the edit that conflicted' });
  guard.take();
  guard.schedule('user-a', { snapshot: 'the edit that conflicted' });

  guard.setActiveUid('user-b'); // uid switch happens before discard is clicked
  assert.equal(guard.hasPending(), false, "switching uid already dropped user-a's re-queued edit");

  guard.clear(); // discardConflictAndReload() still runs for user-b; must not throw or misbehave
  assert.equal(guard.hasPending(), false);
});
