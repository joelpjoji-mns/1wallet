// Regression test for the "debounced save races a user switch" bug: a save
// scheduled while user A is signed in must never be flushed once user B
// becomes active, even though the JS timer/closure that fires later has no
// intrinsic knowledge that the signed-in user changed underneath it.
//
// Pure unit test — no Firebase, no React, no emulator required. Run with:
//   node --test pwa/src/lib/pendingSaveGuard.test.ts

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { PendingSaveGuard } from './pendingSaveGuard.ts';

test('flushes a pending save when the same uid is still active', () => {
  const guard = new PendingSaveGuard<{ value: string }>();
  guard.setActiveUid('alice');
  guard.schedule('alice', { value: 'alice-snapshot' });

  const result = guard.take();
  assert.ok(result);
  assert.equal(result.uid, 'alice');
  assert.equal(result.payload.value, 'alice-snapshot');
});

test('drops a pending save scheduled for a user who is no longer active (user switch)', () => {
  const guard = new PendingSaveGuard<{ value: string }>();
  guard.setActiveUid('alice');
  guard.schedule('alice', { value: 'alice-snapshot' });

  // Alice signs out / bob signs in before the debounce timer fires.
  guard.setActiveUid('bob');

  // The stale timer for alice's save must not be flushable at all — this is
  // the exact scenario that previously risked uploading a snapshot to the
  // wrong uid: `take()` must return null rather than a value that some
  // caller might mistakenly persist under the *new* active uid.
  const result = guard.take();
  assert.equal(result, null);
});

test('a save scheduled for the newly-active uid after a switch is unaffected by the old pending save', () => {
  const guard = new PendingSaveGuard<{ value: string }>();
  guard.setActiveUid('alice');
  guard.schedule('alice', { value: 'alice-snapshot' });

  guard.setActiveUid('bob');
  guard.schedule('bob', { value: 'bob-snapshot' });

  const result = guard.take();
  assert.ok(result);
  assert.equal(result.uid, 'bob');
  assert.equal(result.payload.value, 'bob-snapshot');
});

test('switching uid back and forth never resurrects a stale pending save', () => {
  const guard = new PendingSaveGuard<{ value: string }>();
  guard.setActiveUid('alice');
  guard.schedule('alice', { value: 'alice-snapshot-1' });

  guard.setActiveUid('bob');
  guard.setActiveUid('alice'); // back to alice, but this is a *new* session

  // Even though the uid matches again, `setActiveUid` always clears pending
  // state, so a save queued before the round-trip must not silently reappear
  // (it could otherwise clobber edits Alice made after signing back in).
  const result = guard.take();
  assert.equal(result, null);
});

test('take() is a one-shot consume: calling it twice never double-flushes', () => {
  const guard = new PendingSaveGuard<{ value: string }>();
  guard.setActiveUid('alice');
  guard.schedule('alice', { value: 'alice-snapshot' });

  const first = guard.take();
  assert.ok(first);
  const second = guard.take();
  assert.equal(second, null);
});

test('clear() drops a pending save without ever flushing it (e.g. unmount)', () => {
  const guard = new PendingSaveGuard<{ value: string }>();
  guard.setActiveUid('alice');
  guard.schedule('alice', { value: 'alice-snapshot' });
  guard.clear();

  assert.equal(guard.hasPending(), false);
  assert.equal(guard.take(), null);
});

test('signing out (uid -> null) drops any pending save and blocks future flushes', () => {
  const guard = new PendingSaveGuard<{ value: string }>();
  guard.setActiveUid('alice');
  guard.schedule('alice', { value: 'alice-snapshot' });

  guard.setActiveUid(null);
  assert.equal(guard.take(), null);

  // Even if something mistakenly tries to schedule under a null-ish uid
  // sentinel, take() only flushes for a uid that is both scheduled AND
  // currently active — signed-out has no active uid, so nothing can flush.
  assert.equal(guard.getActiveUid(), null);
});
