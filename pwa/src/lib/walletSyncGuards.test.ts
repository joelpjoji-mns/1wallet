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
  isVersionStable,
  MAX_CLOUD_REVISION,
  MAX_VERSION_CONSISTENCY_ATTEMPTS,
  nextCloudRevision,
  readVersionConsistent,
  shouldAcceptCloudLoad,
  shouldAutoLoadOnRemoteChange,
  splitIntoChunks,
  timestampToMicros,
  WalletSyncRevisionOverflowError,
  WalletSyncTooLargeError,
  WalletSyncUnstableError,
  type VersionToken,
} from './walletSyncGuards.ts';

test('hasWriteConflict: no conflict when nothing has ever been written', () => {
  assert.equal(
    hasWriteConflict(
      { updatedAtToken: null, cloudRevision: null },
      { updatedAtToken: null, cloudRevision: null },
    ),
    false,
  );
});

test('hasWriteConflict: conflict when cloud has data but caller never observed a baseline', () => {
  assert.equal(
    hasWriteConflict(
      { updatedAtToken: 1000, cloudRevision: null },
      { updatedAtToken: null, cloudRevision: null },
    ),
    true,
  );
});

test("hasWriteConflict: no conflict when the caller's own last write is still the latest (timestamp path)", () => {
  assert.equal(
    hasWriteConflict(
      { updatedAtToken: 1000, cloudRevision: null },
      { updatedAtToken: 1000, cloudRevision: null },
    ),
    false,
  );
});

test('hasWriteConflict: conflict when the cloud has moved forward (timestamp path)', () => {
  assert.equal(
    hasWriteConflict(
      { updatedAtToken: 2000, cloudRevision: null },
      { updatedAtToken: 1000, cloudRevision: null },
    ),
    true,
  );
});

test('hasWriteConflict: any cloudRevision mismatch is a conflict, even if the expected timestamp looks newer', () => {
  assert.equal(
    hasWriteConflict({ updatedAtToken: 1000, cloudRevision: 4 }, { updatedAtToken: 5000, cloudRevision: 3 }),
    true,
  );
});

test('hasWriteConflict: matching cloudRevision AND matching updatedAtToken is not a conflict', () => {
  assert.equal(
    hasWriteConflict({ updatedAtToken: 5000, cloudRevision: 3 }, { updatedAtToken: 5000, cloudRevision: 3 }),
    false,
  );
});

// Regression for the cross-client compatibility gap: both this client and
// the (updated) Flutter client now bump `cloudRevision` in the same
// transaction as `updatedAt`/the wallet_backups writes — but older Flutter
// installs still in the wild only merge-update `users/{uid}.updatedAt`
// without touching `cloudRevision` at all. If one of those clients writes
// between this caller's last observation and its own write attempt,
// `cloudRevision` looks unchanged (the legacy writer never bumped it) while
// `updatedAt` has actually moved — trusting `cloudRevision` alone here would
// let this client silently clobber that legacy write. So an equal
// `cloudRevision` is no longer an automatic pass by itself: `updatedAtToken`
// must also be cross-checked whenever both sides carry one.
test('hasWriteConflict: equal cloudRevision but changed updatedAtToken is still a conflict (legacy-writer guard)', () => {
  assert.equal(
    hasWriteConflict({ updatedAtToken: 5000, cloudRevision: 3 }, { updatedAtToken: 1000, cloudRevision: 3 }),
    true,
    'a legacy client can advance updatedAt via a merge-update without bumping cloudRevision at all — ' +
      'equal revisions must not mask that',
  );
});

// Regression for a false-negative bug found while coordinating with the
// Flutter client (`CloudSyncController.uploadSnapshot()` had the identical
// issue, fixed by keying its baseline off `CloudSyncMetadata.lastCloudRevision`
// instead of a value re-read fresh right before the write attempt — mirrored
// here). `WalletDataContext.persist()` used to build `expectedMeta` from a
// fresh `readCloudMeta()` call issued right before `claimAndWriteSnapshot()`,
// reasoned to "only reduce spurious conflicts, never change correctness".
// That reasoning was wrong: if another writer commits *between* this
// client's last successful load/save and that fresh pre-write read, the
// fresh read already reflects the other writer's revision — so it
// "matches" what the transaction re-reads live at commit time, and the
// conflict check reports "no conflict" even though this client's in-memory
// ledger was never built from that revision and knows nothing about the
// changes in it. The correct baseline is whatever this client's in-memory
// data actually is known to be consistent with (i.e. what was observed at
// its *last* successful load or write), not "whatever the cloud happens to
// be right now".
test('hasWriteConflict: a stale "last-synced" baseline detects a conflict a fresh pre-write read would miss', () => {
  // This client last successfully loaded/saved at revision 5 — its in-memory
  // ledger is built from (and only from) that state.
  const lastSyncedBaseline = { updatedAtToken: 1000, cloudRevision: 5 };

  // Some other writer commits afterwards, unseen by this client, advancing
  // the cloud to revision 6.
  const cloudAfterAnotherWritersCommit = { updatedAtToken: 2000, cloudRevision: 6 };

  // BUGGY approach: re-reading the baseline fresh, right before the write
  // attempt, happens *after* the other writer's commit — so the "expected"
  // value already equals the live value, and looks like nothing changed.
  const buggyFreshlyReadBaseline = cloudAfterAnotherWritersCommit;
  assert.equal(
    hasWriteConflict(cloudAfterAnotherWritersCommit, buggyFreshlyReadBaseline),
    false,
    'documents the bug: a freshly-read baseline can falsely report "no conflict" even though the ' +
      'in-memory ledger never saw the intervening commit',
  );

  // CORRECT approach: comparing the live state against what this client's
  // in-memory ledger was actually last synced to correctly detects that the
  // cloud moved past it.
  assert.equal(
    hasWriteConflict(cloudAfterAnotherWritersCommit, lastSyncedBaseline),
    true,
    'the last-synced baseline correctly detects the conflict a fresh pre-write read would have masked',
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
  // system) and both last observed cloudRevision 3 / updatedAtToken 1000.
  const sharedBaseline = { updatedAtToken: 1000, cloudRevision: 3 };

  // Tab A writes successfully, advancing the cloud to revision 4. (The
  // "cloud" state now reflects tab A's write, regardless of the fact tab B
  // shares the same physical device/deviceId.)
  const cloudAfterTabAWrites = { updatedAtToken: 1500, cloudRevision: 4 };

  // Tab B, still holding its original (now stale) baseline, must be told
  // this is a conflict — even though the write that raced ahead of it came
  // from "itself" at the device-identity level.
  assert.equal(hasWriteConflict(cloudAfterTabAWrites, sharedBaseline), true);
});

test('hasWriteConflict: same-device stale baseline still conflicts on the timestamp-only fallback too', () => {
  // Same scenario as above but for accounts that haven't adopted
  // cloudRevision yet (cloudRevision null on both sides throughout).
  const sharedBaseline = { updatedAtToken: 1000, cloudRevision: null };
  const cloudAfterTabAWrites = { updatedAtToken: 1500, cloudRevision: null };
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

// ---------------------------------------------------------------------------
// isVersionStable / readVersionConsistent
//
// Regression coverage for the "downloadSnapshot's chunk query and the
// user-doc read straddle an atomic snapshot write" bug: `load()` used to do
// `Promise.all([downloadSnapshot(uid), readCloudMeta(uid)])` — two
// independent round-trips. If a `claimAndWriteSnapshot()` write landed
// between them, `downloadSnapshot` could return the OLD chunk content while
// `readCloudMeta` returned the NEW `cloudRevision`, so the provider would
// store the new revision as its baseline alongside stale wallet data — and
// the next write from that tab would pass its own conflict check (baseline
// matches "live") while actually overwriting a newer wallet with older data.
// ---------------------------------------------------------------------------

function version(partial: Partial<VersionToken>): VersionToken {
  return { cloudRevision: null, updatedAtToken: null, lastWriterDeviceId: null, ...partial };
}

test('isVersionStable: both null (brand-new account, nothing written yet) is stable', () => {
  assert.equal(isVersionStable(version({}), version({})), true);
});

test('isVersionStable: same cloudRevision and same updatedAtToken on both sides is stable', () => {
  assert.equal(
    isVersionStable(
      version({ cloudRevision: 3, updatedAtToken: 1000 }),
      version({ cloudRevision: 3, updatedAtToken: 1000 }),
    ),
    true,
  );
});

// Regression mirroring the `hasWriteConflict` legacy-writer guard above: a
// bracketed read (`readVersionConsistent`) must not consider itself stable
// just because `cloudRevision` didn't move — a legacy Flutter client can
// merge-update `updatedAt` between the "before" and "after" reads without
// touching `cloudRevision` at all, and that write landing mid-bracket is
// exactly the kind of instability this check exists to catch.
test('isVersionStable: same cloudRevision but changed updatedAtToken is unstable (legacy-writer guard)', () => {
  assert.equal(
    isVersionStable(
      version({ cloudRevision: 3, updatedAtToken: 1000 }),
      version({ cloudRevision: 3, updatedAtToken: 9999 }),
    ),
    false,
    'a legacy client can advance updatedAt via a merge-update without bumping cloudRevision at all — ' +
      'equal revisions must not mask that write landing mid-bracket',
  );
});

test('isVersionStable: differing cloudRevision is unstable — a write landed between reads', () => {
  assert.equal(
    isVersionStable(version({ cloudRevision: 3 }), version({ cloudRevision: 4 })),
    false,
  );
});

test('isVersionStable: falls back to updatedAtToken when either side lacks cloudRevision', () => {
  assert.equal(
    isVersionStable(version({ updatedAtToken: 1000 }), version({ updatedAtToken: 1000 })),
    true,
  );
  assert.equal(
    isVersionStable(version({ updatedAtToken: 1000 }), version({ updatedAtToken: 2000 })),
    false,
  );
});

test('readVersionConsistent: returns immediately when the bracket reads already agree', async () => {
  let payloadFetches = 0;
  const stableVersion = version({ cloudRevision: 5 });
  const result = await readVersionConsistent(
    async () => stableVersion,
    async () => {
      payloadFetches += 1;
      return 'snapshot-payload';
    },
  );
  assert.equal(result.payload, 'snapshot-payload');
  assert.deepEqual(result.version, stableVersion);
  assert.equal(payloadFetches, 1, 'should not retry when the first attempt is already stable');
});

test('readVersionConsistent: a version change during the payload fetch triggers exactly one retry, then succeeds', async () => {
  // Simulates the exact bug scenario: a write lands *while* the chunk
  // download/decode is in flight. The first attempt's "before" (rev 1) and
  // "after" (rev 2) disagree, so the whole cycle — including re-fetching the
  // payload — must retry; the second attempt is fully stable at rev 2.
  let versionReadCount = 0;
  let payloadFetchCount = 0;
  const readVersionToken = async (): Promise<VersionToken> => {
    versionReadCount += 1;
    // Reads 1 & 2 (attempt 1's before/after) disagree; reads 3 & 4 (attempt
    // 2's before/after) agree at revision 2.
    if (versionReadCount === 1) return version({ cloudRevision: 1 });
    return version({ cloudRevision: 2 });
  };
  const fetchPayload = async () => {
    payloadFetchCount += 1;
    return `payload-from-fetch-${payloadFetchCount}`;
  };

  const result = await readVersionConsistent(readVersionToken, fetchPayload);

  assert.equal(payloadFetchCount, 2, 'the stale payload from attempt 1 must be discarded and re-fetched');
  assert.equal(result.payload, 'payload-from-fetch-2', 'must return the payload from the stable attempt, not the stale one');
  assert.equal(result.version.cloudRevision, 2);
});

test('readVersionConsistent: surfaces WalletSyncUnstableError (without a payload) if it never stabilizes', async () => {
  let revision = 0;
  // Every version read returns a strictly increasing revision, so no
  // before/after pair within any attempt can ever agree.
  const readVersionToken = async (): Promise<VersionToken> => {
    revision += 1;
    return version({ cloudRevision: revision });
  };
  let payloadFetchCount = 0;
  const fetchPayload = async () => {
    payloadFetchCount += 1;
    return 'payload';
  };

  await assert.rejects(readVersionConsistent(readVersionToken, fetchPayload), WalletSyncUnstableError);
  assert.equal(
    payloadFetchCount,
    MAX_VERSION_CONSISTENCY_ATTEMPTS,
    'must attempt exactly the configured number of retries, not loop forever or give up early',
  );
});

test('readVersionConsistent: respects a custom maxAttempts', async () => {
  let revision = 0;
  const readVersionToken = async (): Promise<VersionToken> => {
    revision += 1;
    return version({ cloudRevision: revision });
  };
  let payloadFetchCount = 0;
  const fetchPayload = async () => {
    payloadFetchCount += 1;
    return 'payload';
  };

  await assert.rejects(readVersionConsistent(readVersionToken, fetchPayload, 1), WalletSyncUnstableError);
  assert.equal(payloadFetchCount, 1);
});

// ---------------------------------------------------------------------------
// timestampToMicros
// ---------------------------------------------------------------------------

test('timestampToMicros: converts seconds + nanoseconds to epoch microseconds', () => {
  assert.equal(timestampToMicros({ seconds: 1700000000, nanoseconds: 123456789 }), 1700000000_123456);
});

test('timestampToMicros: truncates (does not round) sub-microsecond nanosecond remainders', () => {
  // 999 ns -> 0 extra micros (not 1), matching plain integer-division/floor semantics.
  assert.equal(timestampToMicros({ seconds: 0, nanoseconds: 999 }), 0);
  assert.equal(timestampToMicros({ seconds: 0, nanoseconds: 1000 }), 1);
});

test('timestampToMicros: returns null for null/undefined/malformed input', () => {
  assert.equal(timestampToMicros(null), null);
  assert.equal(timestampToMicros(undefined), null);
  // @ts-expect-error deliberately malformed for the runtime guard
  assert.equal(timestampToMicros({ seconds: '1700000000', nanoseconds: 0 }), null);
});

test('timestampToMicros: two Timestamps in the same millisecond but different nanoseconds compare as different tokens', () => {
  // This is the whole point of using microseconds instead of `Timestamp.toMillis()`: two
  // writes 500 microseconds apart share the same millisecond bucket but must still be
  // distinguishable, since that's exactly the resolution the legacy-writer conflict guard
  // relies on when `cloudRevision` doesn't move.
  const a = timestampToMicros({ seconds: 1700000000, nanoseconds: 123_000_000 });
  const b = timestampToMicros({ seconds: 1700000000, nanoseconds: 123_500_000 });
  assert.notEqual(a, b);
});

// ---------------------------------------------------------------------------
// "PWA write baseline represents the exact self-write" regression
//
// `claimAndWriteSnapshot()` in `walletSync.ts` used to hand its caller back
// nothing (`Promise<void>`), forcing `WalletDataContext.persist()` to issue a
// separate `readCloudMeta()` round-trip afterward to learn the new baseline.
// That separate read could straddle another writer's commit landing right
// after this client's own transaction committed, silently adopting *that*
// writer's revision/timestamp as if it were this client's own. The fix has
// `claimAndWriteSnapshot()` build its `Timestamp.now()` once *before* the
// transaction and return the resulting `CloudMeta` (nextRevision, its own
// deviceId as lastWriterDeviceId, that exact timestamp's token, and the new
// chunk count) directly from the transaction — no post-commit read at all.
// These tests exercise the pure token/conflict math that guarantees such a
// self-produced baseline is internally consistent and always describes a
// clean advance over what was previously observed, using the same
// `hasWriteConflict`/`isVersionStable` primitives `claimAndWriteSnapshot`
// itself relies on.
// ---------------------------------------------------------------------------

test('self-write baseline: a CloudMeta built from this write\'s own Timestamp/nextRevision matches itself exactly (no self-conflict)', () => {
  const writeTimestamp = { seconds: 1700000000, nanoseconds: 500_000_000 };
  const selfWrittenBaseline = {
    updatedAtToken: timestampToMicros(writeTimestamp),
    cloudRevision: 6,
  };
  // Re-comparing a baseline against itself (as would happen if this exact
  // value were immediately used as both "cloud" and "expected" in a
  // subsequent check) must never conflict.
  assert.equal(hasWriteConflict(selfWrittenBaseline, selfWrittenBaseline), false);
});

test('self-write baseline: the returned CloudMeta cleanly advances past the pre-write expectedMeta baseline', () => {
  const expectedMeta = { updatedAtToken: 1_000_000, cloudRevision: 5 };
  const writeTimestamp = { seconds: 1700000000, nanoseconds: 0 };
  // What `claimAndWriteSnapshot()` would return: revision bumped by exactly
  // 1, token derived from the one fixed `Timestamp.now()` value it used for
  // the write (not a separately re-read value).
  const selfWrittenBaseline = {
    updatedAtToken: timestampToMicros(writeTimestamp),
    cloudRevision: expectedMeta.cloudRevision + 1,
  };
  // A third party observing the cloud immediately after this write lands
  // must see this exact baseline as "the live state" with no conflict
  // against itself...
  assert.equal(hasWriteConflict(selfWrittenBaseline, selfWrittenBaseline), false);
  // ...while the *old* pre-write baseline is now correctly stale against it.
  assert.equal(hasWriteConflict(selfWrittenBaseline, expectedMeta), true);
});

// ---------------------------------------------------------------------------
// shouldAcceptCloudLoad
//
// Regression coverage for the coupled sync bug: `WalletDataContext.load()`
// used to gate on `isIncomingSnapshotSafer()`, a count/timestamp heuristic
// that rejected *any* incoming snapshot with fewer transactions than the
// in-memory one — including a version-consistent, positively-verified newer
// cloud read. That silently blocked legitimate cross-device deletions (or a
// wallet cleared entirely) from ever syncing down to this client, since a
// deletion necessarily shrinks the transaction count. `shouldAcceptCloudLoad`
// replaces that heuristic with a version-aware check that only cares whether
// *this* client has its own unsynced local edits still pending/in-flight —
// mirroring the Flutter client's `shouldAcceptCloudRestore()` in
// `lib/src/cloud_sync/cloud_sync_write_guard.dart` exactly (same
// single-boolean-negation contract).
// ---------------------------------------------------------------------------

test('shouldAcceptCloudLoad: accepts a verified cloud snapshot when there are no unsynced local changes', () => {
  assert.equal(shouldAcceptCloudLoad({ hasUnsyncedLocalChanges: false }), true);
});

test('shouldAcceptCloudLoad: rejects when this client has unsynced local changes', () => {
  assert.equal(shouldAcceptCloudLoad({ hasUnsyncedLocalChanges: true }), false);
});

test('shouldAcceptCloudLoad: the coupled bug — a legitimate cross-device deletion (fewer transactions) must be accepted when local has nothing unsynced', () => {
  // The whole point of the fix: unlike `isIncomingSnapshotSafer`, this check
  // takes no snapshot content at all — a verified cloud read with fewer (or
  // zero) transactions than what's currently in memory is still accepted as
  // long as this client hasn't made any of its own unpushed edits.
  assert.equal(shouldAcceptCloudLoad({ hasUnsyncedLocalChanges: false }), true);
});

test('shouldAcceptCloudLoad: a genuinely emptied wallet (zero transactions) is still accepted with no unsynced local changes', () => {
  assert.equal(shouldAcceptCloudLoad({ hasUnsyncedLocalChanges: false }), true);
});

test('shouldAcceptCloudLoad: unsynced local changes are protected even when the incoming snapshot has MORE transactions', () => {
  // Unlike the old heuristic, content is irrelevant either way: a pending
  // local edit must never be silently discarded by a cloud load, even one
  // that looks "safer" by a naive count comparison.
  assert.equal(shouldAcceptCloudLoad({ hasUnsyncedLocalChanges: true }), false);
});

// ---------------------------------------------------------------------------
// nextCloudRevision / MAX_CLOUD_REVISION
//
// `firestore.rules` bounds `users/{uid}.cloudRevision` to a plain int32
// (`isOptionalBoundedInt(data, 'cloudRevision', 0, 2147483647)`), and both
// clients increment it by exactly 1 per successful write. Without an
// explicit guard, an account that ever reached the ceiling would have its
// write rejected by the rules themselves — a confusing, opaque
// permission-denied failure with no indication of the real cause.
// `nextCloudRevision()` instead throws `WalletSyncRevisionOverflowError`
// *before* `claimAndWriteSnapshot()` issues any writes, at the exact
// boundary the rules enforce.
// ---------------------------------------------------------------------------

test('nextCloudRevision: null/absent live revision (brand-new account) starts at 1', () => {
  assert.equal(nextCloudRevision(null), 1);
});

test('nextCloudRevision: increments by exactly 1 for an ordinary in-range value', () => {
  assert.equal(nextCloudRevision(0), 1);
  assert.equal(nextCloudRevision(41), 42);
});

test('nextCloudRevision: MAX_CLOUD_REVISION matches the int32 ceiling firestore.rules enforces', () => {
  assert.equal(MAX_CLOUD_REVISION, 2147483647);
});

test('nextCloudRevision: one below the ceiling (max - 1) still increments cleanly, landing exactly on the ceiling', () => {
  assert.equal(nextCloudRevision(MAX_CLOUD_REVISION - 1), MAX_CLOUD_REVISION);
});

test('nextCloudRevision: at the ceiling (max), incrementing further throws WalletSyncRevisionOverflowError instead of silently overflowing', () => {
  assert.throws(() => nextCloudRevision(MAX_CLOUD_REVISION), WalletSyncRevisionOverflowError);
});

test('nextCloudRevision: the overflow error message is explicit and actionable, not an opaque rules-rejection stand-in', () => {
  assert.throws(
    () => nextCloudRevision(MAX_CLOUD_REVISION),
    (err: unknown) => {
      assert.ok(err instanceof WalletSyncRevisionOverflowError);
      assert.match(err.message, /maximum value/);
      assert.match(err.message, new RegExp(String(MAX_CLOUD_REVISION)));
      return true;
    },
  );
});

// ---------------------------------------------------------------------------
// shouldAutoLoadOnRemoteChange
//
// Regression coverage for the realtime `onSnapshot` listener silently racing
// a debounced-but-not-yet-sent local edit (or one actively mid-flight to the
// cloud): the listener used to call `startLoad()` purely based on whether
// the cloud state had moved, with no regard for whether this client itself
// had unsynced local changes. See `pendingSaveRaceGuard.test.ts` for the
// end-to-end `PendingSaveGuard` regression this feeds into.
// ---------------------------------------------------------------------------

test('shouldAutoLoadOnRemoteChange: auto-reloads on a genuine cloud advance when there are no unsynced local changes', () => {
  assert.equal(
    shouldAutoLoadOnRemoteChange({
      cloud: { cloudRevision: 4, updatedAtToken: 2000 },
      baseline: { cloudRevision: 3, updatedAtToken: 1000 },
      hasUnsyncedLocalChanges: false,
    }),
    true,
  );
});

test('shouldAutoLoadOnRemoteChange: does not reload when the cloud has not actually moved', () => {
  assert.equal(
    shouldAutoLoadOnRemoteChange({
      cloud: { cloudRevision: 3, updatedAtToken: 1000 },
      baseline: { cloudRevision: 3, updatedAtToken: 1000 },
      hasUnsyncedLocalChanges: false,
    }),
    false,
  );
});

test('shouldAutoLoadOnRemoteChange: never reloads while there are unsynced local changes, even with a genuine cloud advance', () => {
  assert.equal(
    shouldAutoLoadOnRemoteChange({
      cloud: { cloudRevision: 4, updatedAtToken: 2000 },
      baseline: { cloudRevision: 3, updatedAtToken: 1000 },
      hasUnsyncedLocalChanges: true,
    }),
    false,
  );
});

test('shouldAutoLoadOnRemoteChange: unsynced local changes short-circuit before even checking the cloud state', () => {
  // Same cloud/baseline as the "no advance" case above, but flipping
  // `hasUnsyncedLocalChanges` must not change the (already-false) outcome —
  // proving the gate doesn't accidentally invert anything when both
  // conditions independently say "false".
  assert.equal(
    shouldAutoLoadOnRemoteChange({
      cloud: { cloudRevision: 3, updatedAtToken: 1000 },
      baseline: { cloudRevision: 3, updatedAtToken: 1000 },
      hasUnsyncedLocalChanges: true,
    }),
    false,
  );
});
