/// Pure, dependency-free helpers backing the atomic conditional-write
/// protocol for `users/{uid}/wallet_backups/chunk_N`.
///
/// This module intentionally has no `cloud_firestore` imports so its
/// decision logic can be unit tested without a Firestore emulator/fake.
/// `CloudSyncController` wires these helpers into an actual
/// `FirebaseFirestore.runTransaction` call.
///
/// ## The contract (shared with the PWA client)
///
/// `users/{uid}` gains a monotonically increasing `cloudRevision` (int,
/// starts at 0 when absent). Every writer — Flutter or web — must, inside a
/// single Firestore transaction:
///
/// 1. Read the live `users/{uid}` document.
/// 2. Compare it against the state the writer *expected* (the state it last
///    observed, read as close as possible to the start of its write attempt).
///    Conflict — abort, write nothing — iff the live `cloudRevision` differs
///    from the expected one, **or** both sides carry a `cloudRevision` that
///    matches but both also carry an `updatedAt` that differs. The second
///    half closes a gap the revision counter alone can't: an old client that
///    still writes `users/{uid}` (e.g. only touching profile fields) without
///    going through this revision-bumping transaction would otherwise look
///    like "no change" purely because it never advanced `cloudRevision`,
///    silently letting its write be clobbered. This is the exact rule
///    proposed to, and expected to be mirrored by,
///    `pwa/src/lib/walletSyncGuards.ts`'s `hasWriteConflict()`.
/// 3. If both sides still don't carry `cloudRevision` yet (an old client on
///    either end), fall back to a plain `updatedAt` comparison: conflict if
///    the live `updatedAt` is strictly newer than expected. This keeps a new
///    client fully interoperable with an old one during the rollout, and
///    deliberately has no "same device wrote it" exemption — matching
///    `pwa/src/lib/walletSyncGuards.ts`'s `hasWriteConflict()`, which was
///    rewritten to drop that exact exemption after finding it silently
///    broke detection between two same-device writers.
/// 4. On success, write `cloudRevision: liveRevision + 1` together with the
///    rest of the payload (new chunk documents, trailing stale-chunk
///    deletes, `updatedAt`/`lastWriterDeviceId`) in the very same
///    transaction, so a partial snapshot can never be observed by a reader.
///    [nextCloudRevision] throws [CloudSyncRevisionOverflowException]
///    instead of computing that increment if it would exceed Firestore
///    rules' int32 `cloudRevision` ceiling (`isOptionalBoundedInt(data,
///    'cloudRevision', 0, 2147483647)` in `firebase/firestore.rules`) —
///    practically unreachable, but this reports it as a clear, distinct
///    error before any write is staged rather than an opaque rules
///    rejection at commit time. Matches `pwa/src/lib/walletSyncGuards.ts`'s
///    `nextCloudRevision()`/`WalletSyncRevisionOverflowError`.
///
/// Because the revision check is keyed purely on the counter (not on which
/// device wrote it), it also closes the gap the device-id heuristic alone
/// cannot: two writers sharing the same device id (e.g. two same-device PWA
/// tabs, or two app installs sharing a restored/cloned device id) still
/// correctly conflict with each other once both sides adopt `cloudRevision`
/// — and even before that, the legacy `updatedAt`-only fallback above no
/// longer masks that case either.
///
/// ### Avoiding false self-conflicts once `updatedAt` is compared exactly
///
/// Once a matching `cloudRevision` no longer guarantees "no conflict" (rule
/// 2 above), the `updatedAt` written by *this* device's own last successful
/// write, and the `updatedAt` this device persists as its next baseline,
/// must be bit-for-bit identical — otherwise a device could falsely conflict
/// with itself. `CloudSyncController.uploadSnapshot()` gets this right by
/// capturing one client-side timestamp before opening the transaction,
/// writing that exact value (not a lazily server-resolved
/// `FieldValue.serverTimestamp()`, whose committed value is never visible to
/// the client that wrote it) as `users/{uid}.updatedAt`, and persisting that
/// same value's `DateTime` as `CloudSyncMetadata.lastObservedCloudUpdatedAt`
/// — instead of a separately-captured `DateTime.now()` approximation of
/// "whatever the server resolved".
///
/// That captured timestamp is deliberately normalized to millisecond
/// precision (`Timestamp.fromMillisecondsSinceEpoch(DateTime.now()
/// .millisecondsSinceEpoch)`), not the microsecond precision `DateTime.now()`
/// natively carries in Dart: the PWA's Firestore JS SDK builds its own
/// client-captured `Timestamp.now()` from `Date.now()`, which is
/// millisecond-only. "Exact equality" between two clients is only a
/// well-defined comparison if both round their own captured timestamps to
/// the coarser of the two precisions *before* writing — otherwise Flutter's
/// microsecond-precision self-comparison would happen to always match itself
/// while never being able to match a value the PWA captured, and a
/// millisecond-level PWA-vs-Flutter race could be missed by a
/// microsecond-exact comparison that's really just comparing noise. The web
/// client must capture and reuse its own single millisecond-precision
/// `Timestamp.now()` the same way for the two sides to stay interoperable;
/// a genuinely different writer's timestamp — including an old client's
/// server-resolved `FieldValue.serverTimestamp()`, which keeps full
/// server-side precision — still differs from either side's expected
/// baseline whenever it lands at a different moment, so the conflict check
/// still fires correctly.
library;

/// The relevant fields of `users/{uid}` used to detect a concurrent writer.
/// Also doubles as the "expected" baseline captured before a write attempt.
class CloudWriteState {
  const CloudWriteState({
    this.cloudRevision,
    this.updatedAt,
    this.lastWriterDeviceId,
  });

  /// No prior observation at all (e.g. first-ever sync on this device).
  static const CloudWriteState unknown = CloudWriteState();

  final int? cloudRevision;
  final DateTime? updatedAt;
  final String? lastWriterDeviceId;

  @override
  String toString() =>
      'CloudWriteState(cloudRevision: $cloudRevision, updatedAt: $updatedAt, '
      'lastWriterDeviceId: $lastWriterDeviceId)';
}

/// Thrown when a write is aborted because the cloud state changed since the
/// writer's expected baseline. Callers should re-check (typically pull) the
/// latest cloud state instead of blindly retrying the same stale write.
class CloudSyncConflictException implements Exception {
  const CloudSyncConflictException([
    this.message = 'Wallet changed on another device since the last sync.',
  ]);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when a snapshot would need more chunk/prune writes than Firestore
/// allows in a single transaction. Callers should surface this distinctly —
/// retrying will not help until the underlying data shrinks.
class CloudSyncOversizeException implements Exception {
  const CloudSyncOversizeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when a bulk read (downloading/decoding `wallet_backups` chunks, or
/// the legacy per-document collections) can't get a version-consistent
/// snapshot of `users/{uid}` after [cloudSyncMaxVersionConsistencyAttempts]
/// attempts — i.e. the account is being written to faster than this client
/// can read it consistently. Matches
/// `pwa/src/lib/walletSyncGuards.ts`'s `WalletSyncUnstableError`.
class CloudSyncUnstableException implements Exception {
  const CloudSyncUnstableException([
    this.message =
        'Wallet cloud state kept changing while trying to read it. '
        'Please try again shortly.',
  ]);

  final String message;

  @override
  String toString() => message;
}

/// Firestore rules cap `cloudRevision` at the int32 ceiling
/// (`isOptionalBoundedInt(data, 'cloudRevision', 0, 2147483647)` in
/// `firebase/firestore.rules`). Matches `pwa/src/lib/walletSyncGuards.ts`'s
/// `MAX_CLOUD_REVISION`.
const cloudSyncMaxRevision = 2147483647;

/// Thrown by [nextCloudRevision] instead of silently computing a
/// `cloudRevision` past Firestore rules' int32 ceiling, which would
/// otherwise surface at commit time as an opaque rules `permission-denied`
/// rejection rather than a clear, distinct error. Practically unreachable
/// (2^31-1 successful syncs on one account), but cheap to guard explicitly.
/// Matches `pwa/src/lib/walletSyncGuards.ts`'s
/// `WalletSyncRevisionOverflowError`.
class CloudSyncRevisionOverflowException implements Exception {
  const CloudSyncRevisionOverflowException([
    this.message =
        'Wallet sync revision counter has reached its maximum value and '
        'cannot be incremented further.',
  ]);

  final String message;

  @override
  String toString() => message;
}

/// Firestore caps a single transaction/batch at 500 document writes. Reserve
/// one for the `users/{uid}` document itself.
const cloudSyncMaxWritesPerTransaction = 500;

/// Firestore also caps a single transaction/batch commit at ~10 MiB of total
/// request payload — independent of, and reached well before, the 500-write
/// ceiling above (900KB chunks hit this at ~11 chunks, ≈9.9MB). Matches
/// `pwa/src/lib/walletSyncGuards.ts`'s `FIRESTORE_COMMIT_BYTE_LIMIT`:
/// deliberately conservative vs. the real ~10 MiB limit, to leave headroom
/// for the profile-document write and protobuf/gRPC framing overhead on top
/// of the raw chunk bytes.
const cloudSyncMaxCommitBytes = 9 * 1024 * 1024;

/// True if committing `newChunkCount` chunk writes plus `staleChunkCount`
/// prune deletes plus the one `users/{uid}` write would exceed Firestore's
/// per-transaction write ceiling.
bool exceedsCloudSyncWriteBudget({
  required int newChunkCount,
  required int staleChunkCount,
  int limit = cloudSyncMaxWritesPerTransaction,
}) {
  final totalWrites = newChunkCount + staleChunkCount + 1;
  return totalWrites > limit;
}

/// True if `totalBytes` (the compressed snapshot payload, before chunking)
/// would exceed Firestore's per-transaction/batch commit byte ceiling.
bool exceedsCloudSyncByteBudget({
  required int totalBytes,
  int limit = cloudSyncMaxCommitBytes,
}) {
  return totalBytes > limit;
}

/// Throws [CloudSyncOversizeException] if the planned transaction would
/// exceed Firestore's write-count *or* commit-byte-size ceiling. Called
/// *before* opening the transaction so an oversized snapshot fails fast
/// with a clear message instead of a mid-commit Firestore error — and,
/// critically, before any partial write has been attempted.
void ensureWithinCloudSyncWriteBudget({
  required int newChunkCount,
  required int staleChunkCount,
  required int totalBytes,
  int writeLimit = cloudSyncMaxWritesPerTransaction,
  int byteLimit = cloudSyncMaxCommitBytes,
}) {
  if (exceedsCloudSyncWriteBudget(
    newChunkCount: newChunkCount,
    staleChunkCount: staleChunkCount,
    limit: writeLimit,
  )) {
    final totalWrites = newChunkCount + staleChunkCount + 1;
    throw CloudSyncOversizeException(
      'Wallet snapshot needs $totalWrites Firestore writes ($newChunkCount '
      'chunk(s) + $staleChunkCount stale chunk delete(s) + 1 profile write), '
      'which exceeds the $writeLimit-write transaction limit. Refusing to '
      'upload a partial/inconsistent backup.',
    );
  }
  if (exceedsCloudSyncByteBudget(totalBytes: totalBytes, limit: byteLimit)) {
    final totalMiB = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
    final limitMiB = (byteLimit / (1024 * 1024)).toStringAsFixed(0);
    throw CloudSyncOversizeException(
      'Wallet snapshot is $totalMiB MiB compressed, which exceeds the '
      '$limitMiB MiB budget used to stay safely under Firestore\'s ~10 MiB '
      'atomic-commit ceiling. Refusing to upload a partial/inconsistent '
      'backup.',
    );
  }
}

/// The next `cloudRevision` to write, given the live value read inside the
/// transaction (or `null` if the document/field doesn't exist yet).
///
/// Called before any writes are staged in the enclosing transaction (see
/// `CloudSyncController.uploadSnapshot()`), so throwing
/// [CloudSyncRevisionOverflowException] here — instead of returning a value
/// past Firestore rules' int32 `cloudRevision` ceiling — reports the
/// overflow as a clear, distinct error before anything is written, rather
/// than as an opaque rules `permission-denied` rejection at commit time.
int nextCloudRevision(int? liveRevision) {
  if (liveRevision != null && liveRevision >= cloudSyncMaxRevision) {
    throw const CloudSyncRevisionOverflowException();
  }
  return (liveRevision ?? 0) + 1;
}

/// Decides whether `live` (read live, inside the transaction) conflicts with
/// `expected` (the baseline this writer observed before starting its write
/// attempt).
///
/// Prefers the monotonic `cloudRevision` counter when both sides have one:
/// any divergence is a conflict, full stop — including a same-device second
/// writer (e.g. two PWA tabs, or two app instances sharing a restored
/// deviceId) that raced ahead, since the revision doesn't care who wrote it.
/// Even when the revisions match, still conflicts if both sides also carry
/// an `updatedAt` that differs — an old client that writes `users/{uid}`
/// without going through the revision-bumping transaction in this file (so
/// its write never advanced `cloudRevision`) would otherwise be invisible to
/// a revision-only check, silently letting its write be clobbered. This
/// exact-equality `updatedAt` comparison relies on both writers persisting
/// the *precise* value they wrote (see the "Avoiding false self-conflicts"
/// section of this file's top-level doc comment) so a device never falsely
/// conflicts with its own prior write.
///
/// Otherwise falls back to a plain `updatedAt` comparison (matching the PWA
/// client's `hasWriteConflict()` in `pwa/src/lib/walletSyncGuards.ts` byte
/// for byte) so an old peer that has never written `cloudRevision` is still
/// correctly detected as a conflicting writer. This deliberately has **no
/// exemption for a matching `lastWriterDeviceId`**: an earlier version of
/// this check special-cased "same device" as never conflicting, which
/// looked safe for native Flutter (normally one instance per device) but
/// silently reopens the exact same-device-race gap the PWA side found for
/// its own browser tabs — e.g. a restored/cloned local backup that shares a
/// device id with another live installation. Conflict is judged purely by
/// whether the cloud state advanced past what *this* writer last observed,
/// regardless of who wrote it.
bool hasCloudSyncConflict({
  required CloudWriteState expected,
  required CloudWriteState live,
}) {
  if (live.cloudRevision != null && expected.cloudRevision != null) {
    if (live.cloudRevision != expected.cloudRevision) return true;

    // Both sides agree on `cloudRevision`, but an *old* client (one that
    // still writes `users/{uid}` — e.g. touching only `updatedAt`/profile
    // fields — without going through the atomic `runTransaction` bump in
    // this file) can advance `updatedAt` while leaving `cloudRevision`
    // untouched. Trusting the matching revision alone here would silently
    // treat that write as "no change" and clobber it. Compare `updatedAt`
    // whenever both sides also have one to catch that case; this is the
    // exact rule this fix expects `pwa/src/lib/walletSyncGuards.ts`'s
    // `hasWriteConflict()` to mirror so both writers agree on what counts
    // as a conflict.
    final liveUpdatedAt = live.updatedAt;
    final expectedUpdatedAt = expected.updatedAt;
    if (liveUpdatedAt != null && expectedUpdatedAt != null) {
      return liveUpdatedAt != expectedUpdatedAt;
    }
    return false;
  }

  final liveUpdatedAt = live.updatedAt;
  if (liveUpdatedAt == null) return false;

  final expectedUpdatedAt = expected.updatedAt;
  if (expectedUpdatedAt == null) return true;
  return liveUpdatedAt.isAfter(expectedUpdatedAt);
}

/// The `chunk_<index>` indices present today (from a plain, non-transactional
/// listing of `wallet_backups`) that would be orphaned/stale once a new,
/// smaller snapshot of `newChunkCount` chunks is written — i.e. leftovers
/// from a previous, larger backup that must be pruned so a later read
/// doesn't concatenate them onto the new (smaller) snapshot and corrupt it.
List<int> staleCloudSyncChunkIndices({
  required Iterable<int> existingChunkIndices,
  required int newChunkCount,
}) {
  return existingChunkIndices.where((index) => index >= newChunkCount).toList()
    ..sort();
}

/// Whether an account has *any* cloud wallet data reachable from
/// `_bootstrap`/`fullSync`, from either the modern chunked-backup path
/// (`users/{uid}`, written by every client — Flutter or PWA — on every
/// successful upload) or the legacy per-document/`metadata/preferences`
/// path (written by neither current client anymore, but still readable for
/// very old accounts).
///
/// Gating solely on the legacy `metadata/preferences` doc's existence would
/// make a client blind to any wallet created purely through the modern
/// chunked path — in particular, the PWA writes `users/{uid}` and
/// `wallet_backups/chunk_N` but never `metadata/preferences`. An empty
/// local ledger would then wrongly take the "no cloud data" seed/idle path
/// instead of pulling the PWA's wallet, and a non-empty local ledger could
/// seed straight over it.
bool hasCloudWalletData({
  required bool userDocExists,
  required bool legacyPreferencesDocExists,
}) {
  return userDocExists || legacyPreferencesDocExists;
}

/// The shared pull-vs-push decision used by both `fullSync` and
/// `_bootstrap`: should this device pull the cloud snapshot down (instead of
/// pushing its own local ledger up)?
///
/// Pulls when: the local ledger has no user data yet (nothing to lose by
/// pulling); the cloud's `updatedAt` is observably newer than the local
/// ledger's own last-modified time; the cloud's monotonic `cloudRevision`
/// has advanced past what this device last observed (a stronger signal than
/// `updatedAt` when both sides support it, immune to clock skew); or another
/// device wrote most recently and this device has no unsynced local changes
/// to protect.
bool shouldPullCloudSnapshot({
  required bool hasLocalUserData,
  required bool hasUnsyncedLocalChanges,
  required DateTime? cloudUpdatedAt,
  required DateTime? localModifiedAt,
  required int? cloudRevision,
  required int? lastKnownCloudRevision,
  required String? cloudLastWriterDeviceId,
  required String localDeviceId,
}) {
  final isCloudNewer =
      cloudUpdatedAt != null &&
      localModifiedAt != null &&
      cloudUpdatedAt.isAfter(localModifiedAt);
  final isCloudRevisionAhead =
      cloudRevision != null &&
      lastKnownCloudRevision != null &&
      cloudRevision > lastKnownCloudRevision;

  return !hasLocalUserData ||
      isCloudNewer ||
      isCloudRevisionAhead ||
      (cloudLastWriterDeviceId != null &&
          cloudLastWriterDeviceId != localDeviceId &&
          !hasUnsyncedLocalChanges);
}

/// Whether a version-consistent incoming cloud snapshot (already positively
/// verified, via [readCloudSyncVersionConsistent], to accurately describe
/// one specific cloud revision — not a straddled/partial read) should be
/// applied over this device's local ledger inside `_restoreFromCloud()`.
///
/// This deliberately replaces a *heuristic* count/timestamp-based guess
/// (`LedgerState.isIncomingLedgerSafer` in `lib/src/data/ledger_models.dart`
/// — still used, unchanged, by the unrelated manual local-backup-file
/// `importArchive()` path, which has no version information to lean on) with
/// a version-aware one: once `shouldPullCloudSnapshot` has already decided
/// the cloud state is ahead of what this device last observed, and the bulk
/// download has been verified to actually match that specific version, the
/// downloaded snapshot *is* the correct, current cloud state by definition —
/// including a snapshot with fewer transactions than local, or none at all.
/// A legitimate deletion (or a wallet cleared entirely) necessarily shrinks
/// the transaction count, and the old heuristic rejected exactly those
/// cases, permanently preventing deletions from ever syncing.
///
/// The only genuine risk left to guard against is this *local* device
/// silently discarding edits it made after its last successful sync but
/// hasn't pushed yet — so that's the only thing this checks. If the local
/// ledger has unsynced changes, this returns `false`: `_restoreFromCloud()`
/// must preserve local state and surface a conflict (leaving the unsynced
/// edit pending upload, so a later `uploadSnapshot()` attempt runs the real
/// conflict check against the live cloud state) rather than blindly
/// overwriting it. If there are no unsynced local changes, there is nothing
/// local left to protect and the verified cloud snapshot is trusted outright.
bool shouldAcceptCloudRestore({required bool hasUnsyncedLocalChanges}) {
  return !hasUnsyncedLocalChanges;
}

/// The three outcomes `uploadSnapshot()`'s `CloudSyncConflictException`
/// handler can resolve to once it has re-read the live cloud state.
///
/// Replaces an earlier unconditional `unawaited(fullSync(reason:
/// 'conflict-recheck'))` retry, which could recurse indefinitely: `fullSync`
/// pushes again (calling `uploadSnapshot()` right back) whenever its own
/// pull-vs-push decision doesn't recognize the cloud as ahead — which
/// happens for exactly the equal-`cloudRevision`-but-changed-`updatedAt`
/// conflict this file's own `hasCloudSyncConflict()` now also detects (an
/// old/partial writer that never bumps `cloudRevision`). That combination
/// re-attempted the *exact same* stale write with the *exact same* baseline
/// against a cloud state that hadn't changed from this device's point of
/// view, guaranteeing an immediate repeat conflict — with no backoff, and
/// entirely bypassing the upload circuit breaker (only the generic
/// catch-all and `TimeoutException` branches bump it).
///
/// This enum has **no "retry the push" outcome at all**, so whatever
/// consumes it structurally cannot recurse back into `uploadSnapshot()`.
enum CloudSyncConflictResolution {
  /// The local ledger has unsynced edits — never pull over them (matches
  /// [shouldAcceptCloudRestore]). Preserve local data untouched and leave
  /// the conflict surfaced for a later legitimate trigger (a new local
  /// edit, app resume, or explicit user action) to resolve.
  preserveLocalAndSurfaceConflict,

  /// No unsynced local edits, and the cloud is verifiably ahead of what
  /// this device last observed — safe to pull the newer snapshot once to
  /// resolve the conflict.
  pullCloudSnapshot,

  /// No unsynced local edits, but the cloud isn't recognized as ahead
  /// either (the ambiguous case described above). Never blind-retry the
  /// same stale write — just surface the conflict and wait; nothing here is
  /// unsafe to leave as-is, since there's no unsynced local edit at risk.
  surfaceConflictOnly,
}

/// Decides how `uploadSnapshot()`'s conflict handler should resolve a
/// `CloudSyncConflictException`, given a fresh read of the live cloud state.
///
/// `shouldPull` should be computed the same way `fullSync`/`_bootstrap` do,
/// via [shouldPullCloudSnapshot] — this function only adds the "and never
/// retry the push instead" guarantee on top by construction (see
/// [CloudSyncConflictResolution]'s doc comment).
CloudSyncConflictResolution resolveCloudSyncConflict({
  required bool hasUnsyncedLocalChanges,
  required bool shouldPull,
}) {
  if (hasUnsyncedLocalChanges) {
    return CloudSyncConflictResolution.preserveLocalAndSurfaceConflict;
  }
  if (shouldPull) {
    return CloudSyncConflictResolution.pullCloudSnapshot;
  }
  return CloudSyncConflictResolution.surfaceConflictOnly;
}

// ---------------------------------------------------------------------------
// Version-consistent bulk reads
// ---------------------------------------------------------------------------
//
// A restore has to bracket a *bulk* read (downloading every `chunk_N`
// document, or the several legacy per-document collections) with two cheap
// reads of `users/{uid}`'s version fields. Firestore's plain multi-document
// queries/`Future.wait` reads are not transactionally consistent with each
// other or with a concurrent writer's transaction — only a single document
// read is strongly consistent — so if another atomic snapshot write lands
// while the bulk read is in flight, the downloaded content and the
// `cloudRevision`/`updatedAt` recorded as "what we just synced to" could
// describe two different versions. Mirrors
// `pwa/src/lib/walletSyncGuards.ts`'s `isVersionStable()`/
// `readVersionConsistent()`.

/// How many times [readCloudSyncVersionConsistent] retries the whole cycle
/// (both version reads *and* the bulk read) before giving up.
const cloudSyncMaxVersionConsistencyAttempts = 3;

/// True if `before` and `after` describe the *same* cloud write — i.e. no
/// atomic snapshot write landed between the two reads they came from.
///
/// Prefers exact `cloudRevision` match when both sides have one (any change
/// at all means a write landed); falls back to exact `updatedAt` match
/// otherwise (also treats "never written, both null" as stable — a
/// brand-new account with no data yet is a perfectly valid stable read).
///
/// Even when both reads agree on `cloudRevision`, also checks `updatedAt`
/// when both carry one: an old client that writes `users/{uid}` without
/// bumping `cloudRevision` could otherwise land a write between the two
/// bracketing reads that goes completely undetected, letting the bulk
/// payload in between describe a different version than the "stable"
/// version token implies. Matches [hasCloudSyncConflict]'s equivalent
/// equal-revision-but-changed-`updatedAt` guard, and is a proposed rule
/// this fix expects `pwa/src/lib/walletSyncGuards.ts`'s `isVersionStable()`
/// to mirror.
bool isCloudSyncVersionStable({
  required CloudWriteState before,
  required CloudWriteState after,
}) {
  if (before.cloudRevision != null && after.cloudRevision != null) {
    if (before.cloudRevision != after.cloudRevision) return false;
    final beforeUpdatedAt = before.updatedAt;
    final afterUpdatedAt = after.updatedAt;
    if (beforeUpdatedAt != null && afterUpdatedAt != null) {
      return beforeUpdatedAt == afterUpdatedAt;
    }
    return true;
  }
  return before.updatedAt == after.updatedAt;
}

/// Brackets `fetchPayload` (a bulk read whose result must describe one
/// consistent snapshot version) with two reads of `readVersionToken` (the
/// cheap `users/{uid}` version fields), retrying the *entire* cycle
/// (re-running `fetchPayload` too, not just the version reads) if they
/// disagree.
///
/// Fully injectable/pure (`readVersionToken`/`fetchPayload` are just
/// functions) so this retry/stability control flow can be unit tested
/// without Firestore — the real Firestore-backed caller is
/// `_restoreFromCloud()` in `cloud_sync_controller.dart`.
///
/// Throws [CloudSyncUnstableException] if it never stabilizes within
/// `maxAttempts` tries.
Future<(TPayload, CloudWriteState)> readCloudSyncVersionConsistent<TPayload>({
  required Future<CloudWriteState> Function() readVersionToken,
  required Future<TPayload> Function() fetchPayload,
  int maxAttempts = cloudSyncMaxVersionConsistencyAttempts,
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final before = await readVersionToken();
    final payload = await fetchPayload();
    final after = await readVersionToken();
    if (isCloudSyncVersionStable(before: before, after: after)) {
      return (payload, after);
    }
  }
  throw CloudSyncUnstableException(
    'Wallet cloud state changed on every one of $maxAttempts attempts to '
    'read a consistent snapshot version. Please try again once syncing '
    'settles.',
  );
}
