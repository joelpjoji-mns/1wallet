// Regression coverage for the pure conflict-detection and atomic-commit-size
// guards `claimAndWriteSnapshot()` in `walletSync.ts` relies on. Kept
// dependency-free (see `walletSyncGuards.ts`) so this runs directly under
// Node's built-in test runner: node --test src/lib/walletSyncGuards.test.ts

import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  assertFitsInOneCommit,
  CHUNK_SIZE,
  FIRESTORE_BATCH_WRITE_LIMIT,
  FIRESTORE_COMMIT_BYTE_LIMIT,
  hasWriteConflict,
  splitIntoChunks,
  WalletSyncTooLargeError,
} from './walletSyncGuards.ts';

test('hasWriteConflict: no conflict when nothing has ever been written', () => {
  assert.equal(
    hasWriteConflict(
      { updatedAtMs: null, cloudRevision: null },
      { updatedAtMs: null, cloudRevision: null },
    ),
    false,
  );
});

test('hasWriteConflict: conflict when cloud has data but caller never observed a baseline', () => {
  assert.equal(
    hasWriteConflict(
      { updatedAtMs: 1000, cloudRevision: null },
      { updatedAtMs: null, cloudRevision: null },
    ),
    true,
  );
});

test("hasWriteConflict: no conflict when the caller's own last write is still the latest (timestamp path)", () => {
  assert.equal(
    hasWriteConflict(
      { updatedAtMs: 1000, cloudRevision: null },
      { updatedAtMs: 1000, cloudRevision: null },
    ),
    false,
  );
});

test('hasWriteConflict: conflict when the cloud has moved forward (timestamp path)', () => {
  assert.equal(
    hasWriteConflict(
      { updatedAtMs: 2000, cloudRevision: null },
      { updatedAtMs: 1000, cloudRevision: null },
    ),
    true,
  );
});

test('hasWriteConflict: exact-match required when both sides carry cloudRevision', () => {
  assert.equal(
    hasWriteConflict({ updatedAtMs: 5000, cloudRevision: 3 }, { updatedAtMs: 1000, cloudRevision: 3 }),
    false,
    'same revision must not conflict even if timestamps differ (revision is authoritative when present)',
  );
  assert.equal(
    hasWriteConflict({ updatedAtMs: 1000, cloudRevision: 4 }, { updatedAtMs: 5000, cloudRevision: 3 }),
    true,
    'any revision mismatch is a conflict, even if the expected timestamp looks newer',
  );
});

// This is the specific bug the reviewer flagged: an earlier version of this
// check exempted writes from "my own device" via `lastWriterDeviceId`
// comparison, which broke down for two browser tabs of the *same* device —
// they share one `getDeviceId()` value (persisted in localStorage), so tab
// B's write would never be flagged as conflicting with tab A's, even though
// tab A's write had already moved the cloud state forward since tab B's
// baseline. The fixed check takes no device identity at all — only the
// baseline the *specific caller* observed matters.
test('hasWriteConflict: a same-device second tab racing on a stale baseline must still conflict', () => {
  // Tab A and tab B are the same browser profile (same deviceId in the real
  // system) and both last observed cloudRevision 3 / updatedAtMs 1000.
  const sharedBaseline = { updatedAtMs: 1000, cloudRevision: 3 };

  // Tab A writes successfully, advancing the cloud to revision 4. (The
  // "cloud" state now reflects tab A's write, regardless of the fact tab B
  // shares the same physical device/deviceId.)
  const cloudAfterTabAWrites = { updatedAtMs: 1500, cloudRevision: 4 };

  // Tab B, still holding its original (now stale) baseline, must be told
  // this is a conflict — even though the write that raced ahead of it came
  // from "itself" at the device-identity level.
  assert.equal(hasWriteConflict(cloudAfterTabAWrites, sharedBaseline), true);
});

test('hasWriteConflict: same-device stale baseline still conflicts on the timestamp-only fallback too', () => {
  // Same scenario as above but for accounts that haven't adopted
  // cloudRevision yet (cloudRevision null on both sides throughout).
  const sharedBaseline = { updatedAtMs: 1000, cloudRevision: null };
  const cloudAfterTabAWrites = { updatedAtMs: 1500, cloudRevision: null };
  assert.equal(hasWriteConflict(cloudAfterTabAWrites, sharedBaseline), true);
});

test('splitIntoChunks: always yields at least one chunk, even for empty input', () => {
  const chunks = splitIntoChunks(new Uint8Array(0));
  assert.equal(chunks.length, 1);
  assert.equal(chunks[0]?.length, 0);
});

test('splitIntoChunks: splits at exactly CHUNK_SIZE boundaries', () => {
  const input = new Uint8Array(CHUNK_SIZE * 2 + 10);
  const chunks = splitIntoChunks(input);
  assert.equal(chunks.length, 3);
  assert.equal(chunks[0]?.length, CHUNK_SIZE);
  assert.equal(chunks[1]?.length, CHUNK_SIZE);
  assert.equal(chunks[2]?.length, 10);
});

test('assertFitsInOneCommit: allows a typical small wallet write', () => {
  assert.doesNotThrow(() =>
    assertFitsInOneCommit({ newChunkCount: 1, staleChunkCount: 0, totalBytes: 1024 }),
  );
});

test('assertFitsInOneCommit: fails visibly (before anything is written) when the write count is too high', () => {
  assert.throws(
    () =>
      assertFitsInOneCommit({
        newChunkCount: FIRESTORE_BATCH_WRITE_LIMIT,
        staleChunkCount: 10,
        totalBytes: 1024,
      }),
    WalletSyncTooLargeError,
  );
});

test('assertFitsInOneCommit: fails visibly when the payload exceeds the byte budget', () => {
  assert.throws(
    () =>
      assertFitsInOneCommit({
        newChunkCount: 1,
        staleChunkCount: 0,
        totalBytes: FIRESTORE_COMMIT_BYTE_LIMIT + 1,
      }),
    WalletSyncTooLargeError,
  );
});

test('assertFitsInOneCommit: error message explicitly avoids claiming Flutter protection and names the staging-protocol alternative', () => {
  assert.throws(
    () =>
      assertFitsInOneCommit({
        newChunkCount: 1,
        staleChunkCount: 0,
        totalBytes: FIRESTORE_COMMIT_BYTE_LIMIT + 1,
      }),
    (err: unknown) => {
      assert.ok(err instanceof WalletSyncTooLargeError);
      assert.match(err.message, /staging\/pointer protocol/);
      assert.match(err.message, /Flutter/);
      return true;
    },
  );
});
