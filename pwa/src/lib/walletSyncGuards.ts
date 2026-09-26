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
  /**
   * A precision-safe, directly-comparable token derived from the
   * `users/{uid}.updatedAt` Firestore `Timestamp` — epoch **microseconds**
   * (`seconds * 1e6 + floor(nanoseconds / 1000)`, see
   * {@link timestampToMicros}), not milliseconds. Two writes
   * landing within the same millisecond (plausible for automated tooling,
   * or a legacy client and this one racing) must still compare as
   * different, since that's exactly the gap this token exists to close —
   * see `hasWriteConflict`'s doc comment.
   */
  updatedAtToken: number | null;
  cloudRevision: number | null;
}

/**
 * Converts a Firestore `Timestamp` (duck-typed here as `{ seconds,
 * nanoseconds }` so this module never has to import the Firestore SDK — see
 * the file header) to a single comparable integer: epoch microseconds
 * (`seconds * 1e6 + floor(nanoseconds / 1000)`). Deliberately *not*
 * `Timestamp.toMillis()` (whole milliseconds only) — two distinct writes
 * landing within the same millisecond would otherwise look identical to
 * {@link hasWriteConflict}/{@link isVersionStable}, which is exactly the
 * scenario the equal-`cloudRevision`-but-changed-`updatedAt` legacy-writer
 * guard needs to catch. Epoch microseconds for any real-world timestamp
 * comfortably fits in a JS safe integer (~4.1e15 through year 2100, vs.
 * `Number.MAX_SAFE_INTEGER` ~9.007e15). The real Firestore-backed caller is
 * `cloudMetaFromUserDoc()` in `walletSync.ts`.
 */
export function timestampToMicros(
  ts: { seconds: number; nanoseconds: number } | null | undefined,
): number | null {
  if (!ts || typeof ts.seconds !== 'number' || typeof ts.nanoseconds !== 'number') return null;
  return ts.seconds * 1_000_000 + Math.floor(ts.nanoseconds / 1000);
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
 *
 * Equal `cloudRevision` is **not** an automatic pass, unlike an earlier
 * version of this check: today's contract (agreed with the Flutter side —
 * see `firebase/README.md`) is that both clients bump `cloudRevision` in the
 * *same* transaction as the profile-metadata/`wallet_backups` chunk writes —
 * but older, not-yet-updated Flutter installs are still out there, and they
 * only merge-update `users/{uid}.updatedAt` without touching
 * `cloudRevision` at all. If one of those clients writes between this
 * caller's last observation and its own write attempt, `cloudRevision`
 * would look unchanged (the legacy writer never bumped it) while
 * `updatedAt` has actually moved forward — so trusting `cloudRevision` alone
 * would let this client silently clobber that legacy write. Whenever both
 * sides *also* carry an `updatedAtToken`, it's cross-checked even when the
 * revisions match; only when a side lacks a token entirely (never written,
 * or an ancient pre-`updatedAt` account) does equal-revision alone pass.
 *
 * Mirrored byte-for-byte by the Flutter client's `hasCloudSyncConflict()` in
 * `lib/src/cloud_sync/cloud_sync_write_guard.dart` — both clients share one
 * formally agreed conflict protocol keyed on `users/{uid}.cloudRevision`
 * (falling back to `updatedAt` with the same no-exemption semantics when
 * either side hasn't written a revision yet) and both implement the
 * revision-equal-but-updatedAt-changed cross-check above, not just parallel
 * same-origin safeguards — see `firebase/README.md` for the full shared
 * contract.
 */
export function hasWriteConflict(cloud: ConflictBaseline, expected: ConflictBaseline): boolean {
  if (cloud.cloudRevision != null && expected.cloudRevision != null) {
    // Both sides participate in the revision counter: exact-match required.
    // Any divergence — including a same-device second tab that raced ahead
    // — is a conflict.
    if (cloud.cloudRevision !== expected.cloudRevision) return true;
    // Revisions match, but a legacy (pre-cloudRevision) writer could still
    // have advanced `updatedAt` without touching the counter — cross-check
    // whenever both sides have a token to compare.
    if (cloud.updatedAtToken != null && expected.updatedAtToken != null) {
      return cloud.updatedAtToken !== expected.updatedAtToken;
    }
    return false;
  }
  if (cloud.updatedAtToken == null) return false; // nothing written yet; nothing to conflict with
  if (expected.updatedAtToken == null) return true; // caller never observed a baseline but cloud has data
  return cloud.updatedAtToken > expected.updatedAtToken;
}

/**
 * Whether `WalletDataContext`'s realtime `onSnapshot` listener should
 * auto-trigger a reload upon observing that the cloud state has moved past
 * `baseline` (per {@link hasWriteConflict}).
 *
 * Gated on `hasUnsyncedLocalChanges` for the same reason
 * {@link shouldAcceptCloudLoad} is: an automatic background reload racing a
 * debounced-but-not-yet-sent local edit (or an edit actively mid-flight to
 * the cloud) must never win and silently replace that edit's in-memory
 * snapshot before the edit's own `persist()`/conflict handling gets a
 * chance to run. `load()`'s own `shouldAcceptCloudLoad` check is a second,
 * independent layer of the same protection — reachable by triggering it
 * anyway and letting `load()` reject it — but gating *here* too avoids the
 * wasted chunk download/decode and the premature "local changes not
 * uploaded yet" message that a doomed-to-be-rejected auto-load would
 * otherwise surface on every ordinary keystroke-to-save debounce window,
 * not just a genuine race.
 */
export function shouldAutoLoadOnRemoteChange({
  cloud,
  baseline,
  hasUnsyncedLocalChanges,
}: {
  cloud: ConflictBaseline;
  baseline: ConflictBaseline;
  hasUnsyncedLocalChanges: boolean;
}): boolean {
  if (hasUnsyncedLocalChanges) return false;
  return hasWriteConflict(cloud, baseline);
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

// The int32 ceiling `firestore.rules` enforces on `users/{uid}.cloudRevision`
// (`isOptionalBoundedInt(data, 'cloudRevision', 0, 2147483647)`). Both
// clients increment this by exactly 1 per successful write, so an account
// would need over two billion successful syncs to ever reach it in
// practice — but the ceiling is real and a raw rules-permission-denied
// failure from the commit itself would be a confusing way to hit it.
export const MAX_CLOUD_REVISION = 2147483647;

/**
 * Thrown when incrementing `cloudRevision` would exceed {@link
 * MAX_CLOUD_REVISION} — surfaced explicitly, before the write is even
 * attempted, instead of letting the commit fail with an opaque
 * rules-permission-denied error that gives the caller no actionable
 * explanation.
 */
export class WalletSyncRevisionOverflowError extends Error {
  constructor(
    message = `Wallet cloud revision counter has reached its maximum value (${MAX_CLOUD_REVISION}) ` +
      'and cannot be synced further from this device. Please contact support.',
  ) {
    super(message);
    this.name = 'WalletSyncRevisionOverflowError';
  }
}

/**
 * Computes the next `cloudRevision` value the same way as Flutter's
 * `nextCloudRevision()` in `lib/src/cloud_sync/cloud_sync_write_guard.dart`
 * (`(liveRevision ?? 0) + 1`), but throws {@link WalletSyncRevisionOverflowError}
 * *before* `claimAndWriteSnapshot()`'s transaction issues any writes if doing
 * so would exceed {@link MAX_CLOUD_REVISION} — the same int32 ceiling
 * `firestore.rules` enforces on this field. Without this guard, exceeding
 * the ceiling would instead surface as an opaque Firestore
 * permission-denied rejection from the commit itself (the rules would
 * reject the write, but give no indication *why* to the caller). Flutter's
 * `nextCloudRevision()` does not yet have this guard — flagged as a
 * still-needed parity fix in `firebase/README.md`.
 */
export function nextCloudRevision(liveRevision: number | null): number {
  if (liveRevision != null && liveRevision >= MAX_CLOUD_REVISION) {
    throw new WalletSyncRevisionOverflowError();
  }
  return (liveRevision ?? 0) + 1;
}

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

// ---------------------------------------------------------------------------
// Version-consistent bulk reads
// ---------------------------------------------------------------------------

/** The `users/{uid}` fields that change on every atomic snapshot write — cheap to re-read as a "version check". */
export interface VersionToken {
  cloudRevision: number | null;
  /** See {@link ConflictBaseline.updatedAtToken} — epoch microseconds, not milliseconds. */
  updatedAtToken: number | null;
  lastWriterDeviceId: string | null;
}

/**
 * True if `before` and `after` describe the *same* cloud write — i.e. no
 * atomic snapshot write landed between the two reads they came from.
 *
 * Prefers exact `cloudRevision` match when both sides have one (any change
 * at all means a write landed) — but, mirroring {@link hasWriteConflict},
 * matching revisions alone don't prove stability: a legacy (pre-
 * `cloudRevision`) Flutter client can merge-update `updatedAt` without
 * bumping the counter, so an unchanged revision with a *changed*
 * `updatedAtToken` between `before` and `after` still means a write landed
 * mid-bracket and must be reported unstable. Falls back to exact
 * `updatedAtToken` match when either side lacks a revision (also treats
 * "never written, both null" as stable — a brand-new account with no data
 * yet is a perfectly valid stable read).
 */
export function isVersionStable(before: VersionToken, after: VersionToken): boolean {
  if (before.cloudRevision != null && after.cloudRevision != null) {
    if (before.cloudRevision !== after.cloudRevision) return false;
    if (before.updatedAtToken != null && after.updatedAtToken != null) {
      return before.updatedAtToken === after.updatedAtToken;
    }
    return true;
  }
  return before.updatedAtToken === after.updatedAtToken;
}

export const MAX_VERSION_CONSISTENCY_ATTEMPTS = 3;

/**
 * Thrown when a bulk read (downloading/decoding chunks, or just counting
 * them) can't get a version-consistent snapshot of `users/{uid}` after
 * {@link MAX_VERSION_CONSISTENCY_ATTEMPTS} attempts — i.e. the account is
 * being written to faster than this client can read it consistently.
 */
export class WalletSyncUnstableError extends Error {
  constructor(
    message = 'Wallet cloud state kept changing while trying to read it. Please try again shortly.',
  ) {
    super(message);
    this.name = 'WalletSyncUnstableError';
  }
}

/**
 * Brackets `fetchPayload` (a bulk read whose result must describe one
 * consistent snapshot version — e.g. downloading+decoding
 * `wallet_backups/chunk_N`, or just counting them) with two reads of the
 * cheap `users/{uid}` version fields, retrying the *entire* cycle
 * (re-running `fetchPayload` too, not just the version reads) if they
 * disagree — meaning another atomic write landed while `fetchPayload` was in
 * flight, so its result and the "after" version could describe two
 * different snapshot versions (e.g. `fetchPayload` returns the OLD chunk
 * content while "after" already reflects the NEW `cloudRevision`).
 *
 * Fully injectable/pure (`readVersionToken`/`fetchPayload` are just
 * functions) precisely so this retry/stability control flow can be unit
 * tested without Firestore — see `walletSyncGuards.test.ts`. The real
 * Firestore-backed callers are `downloadSnapshot()` and `readCloudMeta()` in
 * `walletSync.ts`.
 *
 * Throws {@link WalletSyncUnstableError} if it never stabilizes within
 * `maxAttempts` tries.
 */
export async function readVersionConsistent<TPayload>(
  readVersionToken: () => Promise<VersionToken>,
  fetchPayload: () => Promise<TPayload>,
  maxAttempts: number = MAX_VERSION_CONSISTENCY_ATTEMPTS,
): Promise<{ payload: TPayload; version: VersionToken }> {
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const before = await readVersionToken();
    const payload = await fetchPayload();
    const after = await readVersionToken();
    if (isVersionStable(before, after)) {
      return { payload, version: after };
    }
  }
  throw new WalletSyncUnstableError(
    `Wallet cloud state changed on every one of ${maxAttempts} attempts to read a consistent ` +
      'snapshot version. Please try again once syncing settles.',
  );
}

// ---------------------------------------------------------------------------
// Cloud-load acceptance (replaces a content-based heuristic)
// ---------------------------------------------------------------------------

/**
 * Whether a version-consistent incoming cloud snapshot — already positively
 * verified via {@link readVersionConsistent} to accurately describe one
 * specific cloud revision, not a straddled/partial read — should be applied
 * over this device's in-memory ledger inside `WalletDataContext.load()`.
 *
 * This deliberately replaces a *heuristic* count/timestamp-based guess
 * (`isIncomingSnapshotSafer()` in `ledgerCodec.ts` — still kept, unchanged,
 * for a possible future local-backup-file restore path, which has no version
 * information to lean on) with a version-aware one: once `load()` has
 * already fetched a bulk read that's been verified to actually match a
 * specific `cloudRevision`/`updatedAt`, the downloaded snapshot *is* the
 * correct, current cloud state by definition — including a snapshot with
 * fewer transactions than local, or none at all. A legitimate deletion (or a
 * wallet cleared entirely, made from another device/tab) necessarily shrinks
 * the transaction count, and the old content-based heuristic rejected
 * exactly those cases, permanently preventing deletions from ever syncing
 * down to this client.
 *
 * The only genuine risk left to guard against is *this* client silently
 * discarding local edits it made after its last successful sync but hasn't
 * pushed to the cloud yet — so that's the only thing this checks. If there
 * are unsynced local changes, this returns `false`: `load()` must preserve
 * local state (and leave the previous cloud-metadata baseline untouched, so
 * a later `persist()` attempt's own conflict check runs against the true
 * live cloud state and can properly detect/report the conflict) rather than
 * blindly overwriting the pending edit. If there are no unsynced local
 * changes, there is nothing local left to protect and the verified cloud
 * snapshot is trusted outright, whatever its content.
 *
 * Mirrors the Flutter client's `shouldAcceptCloudRestore()` in
 * `lib/src/cloud_sync/cloud_sync_write_guard.dart` byte-for-byte (same
 * single-boolean-negation contract) — both clients now use the same
 * criterion for accepting a verified incoming cloud snapshot.
 */
export function shouldAcceptCloudLoad({
  hasUnsyncedLocalChanges,
}: {
  hasUnsyncedLocalChanges: boolean;
}): boolean {
  return !hasUnsyncedLocalChanges;
}
