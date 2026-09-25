// Pure, Firebase-free helpers extracted from `walletSync.ts` so they can be
// unit tested directly with Node's built-in test runner — `walletSync.ts`
// itself can't be imported outside Vite (it transitively pulls in
// `./firebase`, which reads `import.meta.env.VITE_FIREBASE_*`, a Vite-only
// feature that throws under plain `node --test`).
//
// See `walletSyncGuards.test.ts` for the regression coverage, including the
// same-device-second-tab conflict scenario this module's conflict check was
// specifically rewritten to catch.

export interface ConflictBaseline {
  updatedAtMs: number | null;
  cloudRevision: number | null;
}

/**
 * Pure conflict decision used by `claimAndWriteSnapshot()` in
 * `walletSync.ts`.
 *
 * Deliberately has **no exemption for a matching `lastWriterDeviceId`**: an
 * earlier version of this check skipped the conflict entirely whenever the
 * cloud's last writer matched the caller's own device id, which silently
 * broke down for two browser *tabs* of the same device/profile (they share
 * one `getDeviceId()` value, since it's persisted in `localStorage`) — the
 * second tab's `expected` baseline would still look "not conflicting" even
 * though the first tab had already moved the cloud state forward between
 * the two tabs' reads. Conflict is now judged purely by whether the cloud
 * state has advanced past what *this specific caller* last observed,
 * regardless of who wrote it — including "myself, in another tab".
 */
export function hasWriteConflict(cloud: ConflictBaseline, expected: ConflictBaseline): boolean {
  if (cloud.cloudRevision != null && expected.cloudRevision != null) {
    // Both sides participate in the revision counter: exact-match required.
    // Any divergence — including a same-device second tab that raced ahead
    // — is a conflict.
    return cloud.cloudRevision !== expected.cloudRevision;
  }
  if (cloud.updatedAtMs == null) return false; // nothing written yet; nothing to conflict with
  if (expected.updatedAtMs == null) return true; // caller never observed a baseline but cloud has data
  return cloud.updatedAtMs > expected.updatedAtMs;
}

// Firestore hard-caps a single transaction/batch commit at 500 write
// operations *and* ~10 MiB of total request payload — whichever is hit
// first. A meta write + N chunk sets + M prune deletes must fit both. Chunk
// count is normally tiny (0-2 stale entries) because the prune range is
// computed exactly from a trusted prior observation (see
// `claimAndWriteSnapshot` in walletSync.ts) rather than swept over a fixed
// ceiling, so the practical limiter for real wallets is the byte budget, not
// the write count — but both are still asserted explicitly so a future
// change can never silently violate either.
export const FIRESTORE_BATCH_WRITE_LIMIT = 500;
// Deliberately conservative vs. Firestore's actual ~10 MiB commit ceiling,
// to leave headroom for the user-doc write and protobuf/gRPC framing
// overhead on top of the raw chunk bytes.
export const FIRESTORE_COMMIT_BYTE_LIMIT = 9 * 1024 * 1024;

/** Thrown when a snapshot can't be written as a single atomic Firestore commit. */
export class WalletSyncTooLargeError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'WalletSyncTooLargeError';
  }
}

/**
 * Verifies a snapshot write of `newChunkCount` chunks (totalling
 * `totalBytes`, deleting up to `staleChunkCount` old ones) can fit in a
 * single atomic Firestore commit, throwing {@link WalletSyncTooLargeError}
 * *before anything is written* if not — this is the "fail visibly" half of
 * the fix: rather than silently falling back to a non-atomic multi-step
 * write (which would reopen the exact TOCTOU/lost-update race this module
 * exists to close), a wallet too large for one atomic commit is refused
 * outright with a clear, actionable error.
 */
export function assertFitsInOneCommit({
  newChunkCount,
  staleChunkCount,
  totalBytes,
}: {
  newChunkCount: number;
  staleChunkCount: number;
  totalBytes: number;
}): void {
  const totalWrites = newChunkCount + staleChunkCount + 1; // + user-doc meta write
  if (totalWrites > FIRESTORE_BATCH_WRITE_LIMIT) {
    throw new WalletSyncTooLargeError(
      `Wallet snapshot needs ${totalWrites} writes (chunks + prune + metadata) in a single atomic ` +
        `commit, which exceeds Firestore's ${FIRESTORE_BATCH_WRITE_LIMIT}-write limit. Refusing to ` +
        'write it non-atomically — that would reopen the exact torn-write race this client fixed. ' +
        'This wallet needs a versioned staging/pointer protocol (coordinated with the Flutter client) ' +
        'to sync from the web safely.',
    );
  }
  if (totalBytes > FIRESTORE_COMMIT_BYTE_LIMIT) {
    throw new WalletSyncTooLargeError(
      `Wallet snapshot is ${(totalBytes / (1024 * 1024)).toFixed(1)} MiB compressed, which exceeds ` +
        `the ${(FIRESTORE_COMMIT_BYTE_LIMIT / (1024 * 1024)).toFixed(0)} MiB budget this client uses to ` +
        "stay safely under Firestore's ~10 MiB atomic-commit ceiling. Refusing to write it " +
        'non-atomically — that would reopen the exact torn-write race this client fixed. This wallet ' +
        'needs a versioned staging/pointer protocol (coordinated with the Flutter client) to sync from ' +
        'the web safely.',
    );
  }
}

// Matches the 900KB Firestore Blob-safe chunk size used by the Flutter client.
export const CHUNK_SIZE = 900 * 1024;

/** Splits `compressed` into ≤900KB chunks, always yielding at least one (possibly empty) chunk. */
export function splitIntoChunks(compressed: Uint8Array): Uint8Array[] {
  const chunks: Uint8Array[] = [];
  for (let i = 0; i < compressed.length; i += CHUNK_SIZE) {
    chunks.push(compressed.subarray(i, Math.min(i + CHUNK_SIZE, compressed.length)));
  }
  if (chunks.length === 0) chunks.push(new Uint8Array());
  return chunks;
}
