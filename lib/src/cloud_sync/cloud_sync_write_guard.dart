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
///    If the live `cloudRevision` differs from the expected one, abort with a
///    conflict — do not write anything.
/// 3. If both sides still don't carry `cloudRevision` yet (an old client on
///    either end), fall back to the legacy heuristic already in use today:
///    conflict if the live `updatedAt` is newer than expected *and* the live
///    `lastWriterDeviceId` differs from this writer's own id. This keeps a
///    new client fully interoperable with an old one during the rollout.
/// 4. On success, write `cloudRevision: liveRevision + 1` together with the
///    rest of the payload (new chunk documents, trailing stale-chunk
///    deletes, `updatedAt`/`lastWriterDeviceId`) in the very same
///    transaction, so a partial snapshot can never be observed by a reader.
///
/// Because the revision check is keyed purely on the counter (not on which
/// device wrote it), it also closes the gap the device-id heuristic alone
/// cannot: two writers sharing the same device id (e.g. two same-device PWA
/// tabs) still correctly conflict with each other once both sides adopt
/// `cloudRevision`.
library;

/// The relevant fields of `users/{uid}` used to detect a concurrent writer.
/// Also doubles as the "expected" baseline captured before a write attempt.
class CloudWriteState {
  const CloudWriteState({this.cloudRevision, this.updatedAt, this.lastWriterDeviceId});

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

/// Firestore caps a single transaction/batch at 500 document writes. Reserve
/// one for the `users/{uid}` document itself.
const cloudSyncMaxWritesPerTransaction = 500;

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

/// Throws [CloudSyncOversizeException] if the planned transaction would
/// exceed Firestore's write-count ceiling. Called *before* opening the
/// transaction so an oversized snapshot fails fast with a clear message
/// instead of a mid-commit Firestore error.
void ensureWithinCloudSyncWriteBudget({
  required int newChunkCount,
  required int staleChunkCount,
  int limit = cloudSyncMaxWritesPerTransaction,
}) {
  if (exceedsCloudSyncWriteBudget(
    newChunkCount: newChunkCount,
    staleChunkCount: staleChunkCount,
    limit: limit,
  )) {
    final totalWrites = newChunkCount + staleChunkCount + 1;
    throw CloudSyncOversizeException(
      'Wallet snapshot needs $totalWrites Firestore writes ($newChunkCount '
      'chunk(s) + $staleChunkCount stale chunk delete(s) + 1 profile write), '
      'which exceeds the $limit-write transaction limit. Refusing to upload '
      'a partial/inconsistent backup.',
    );
  }
}

/// The next `cloudRevision` to write, given the live value read inside the
/// transaction (or `null` if the document/field doesn't exist yet).
int nextCloudRevision(int? liveRevision) => (liveRevision ?? 0) + 1;

/// Decides whether `live` (read live, inside the transaction) conflicts with
/// `expected` (the baseline this writer observed before starting its write
/// attempt), from `localDeviceId`'s point of view.
///
/// Prefers the monotonic `cloudRevision` counter when both sides have one;
/// otherwise falls back to the legacy `updatedAt`/`lastWriterDeviceId`
/// heuristic so an old peer that has never written `cloudRevision` is still
/// correctly detected as a conflicting writer.
bool hasCloudSyncConflict({
  required CloudWriteState expected,
  required CloudWriteState live,
  required String localDeviceId,
}) {
  if (live.cloudRevision != null && expected.cloudRevision != null) {
    return live.cloudRevision != expected.cloudRevision;
  }

  final liveUpdatedAt = live.updatedAt;
  if (liveUpdatedAt == null) return false;
  if (live.lastWriterDeviceId == localDeviceId) return false;

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
