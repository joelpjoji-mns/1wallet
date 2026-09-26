// Regression coverage for the "direct account switch (A→B) leaks the
// previous user's data" bug in `WalletDataContext.tsx`, updated for the
// version-aware `load()` acceptance gate.
//
// History: `load()` used to guard against replacing local state with an
// emptier/older-looking remote snapshot via a count/timestamp heuristic,
// `isIncomingSnapshotSafer(current, incoming)`. If `current` were still user
// A's leftover snapshot at the moment user B's data loaded, and B's
// (perfectly legitimate) wallet happened to have fewer transactions than
// A's, that heuristic would refuse to apply it — permanently stranding A's
// private financial data on screen for user B to see. That heuristic has
// since been replaced entirely (see `walletSyncGuards.test.ts`'s
// `shouldAcceptCloudLoad` coverage) with a version-aware check that ignores
// snapshot content altogether and only asks whether *this* client has its
// own unsynced local edits pending — so the specific "B's smaller wallet
// gets rejected" failure mode this file used to reproduce is now
// structurally impossible at the gate level, independent of any reset.
//
// What still matters at uid-switch time is *what counts as "this client's
// own unsynced local edits"* for the new user. That's driven by
// `PendingSaveGuard`, whose `setActiveUid()` (called from the same
// uid-switch effect that resets `snapshot`) unconditionally drops whatever
// was queued for the previous user — see `pendingSaveGuard.test.ts` for that
// guard's own regression coverage. This file exercises the exact pure
// decision `load()` evaluates today, `shouldAcceptCloudLoad()`, against that
// scenario: proving a direct A→B switch can never have B's first load
// rejected because of a leftover pending save that belonged to A.
//
// (The separate *visual* privacy leak — A's stale snapshot briefly painted
// under B's uid before the load resolves — is unrelated to load
// acceptance and is covered by `uidSwitchRender.test.ts`'s `key={user?.uid}`
// remount regression instead.)
//
// Run with: node --test src/lib/uidSwitchGuard.test.ts

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { PendingSaveGuard } from './pendingSaveGuard.ts';
import { shouldAcceptCloudLoad } from './walletSyncGuards.ts';

interface Payload {
  note: string;
}

test('uid switch: a pending save left over from the previous user never blocks the new user\'s first load', () => {
  const guard = new PendingSaveGuard<Payload>();
  guard.setActiveUid('user-a');
  guard.schedule('user-a', { note: 'A had an unsynced edit queued' });
  assert.equal(guard.hasPending(), true);

  // The uid-switch effect calls `setActiveUid()` for the new user — this is
  // the same call `WalletDataContext`'s `useLayoutEffect` makes on every uid
  // change, and it unconditionally drops whatever was pending for A.
  guard.setActiveUid('user-b');
  assert.equal(guard.hasPending(), false, "A's pending save must not survive the switch to B");

  // `load()` computes `hasUnsyncedLocalChanges` from this same guard — with
  // no pending save (and no in-flight `persist()`) for the new user, B's
  // first load is accepted outright, however small or empty B's wallet is.
  const hasUnsyncedLocalChanges = guard.hasPending();
  assert.equal(shouldAcceptCloudLoad({ hasUnsyncedLocalChanges }), true);
});

test('uid switch: the new user\'s own unsynced edit (scheduled after switching) still correctly protects local state', () => {
  const guard = new PendingSaveGuard<Payload>();
  guard.setActiveUid('user-b');
  guard.schedule('user-b', { note: "B's own unsynced edit" });

  const hasUnsyncedLocalChanges = guard.hasPending();
  assert.equal(
    shouldAcceptCloudLoad({ hasUnsyncedLocalChanges }),
    false,
    "B's own pending edit must still be protected from a racing realtime cloud load",
  );
});

test('sanity: no pending save at all (steady-state, no edits in flight) always accepts a verified cloud load', () => {
  const guard = new PendingSaveGuard<Payload>();
  guard.setActiveUid('user-a');
  assert.equal(shouldAcceptCloudLoad({ hasUnsyncedLocalChanges: guard.hasPending() }), true);
});
