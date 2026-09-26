// Reads and writes the same GZip-compressed JSON snapshot format the Flutter
// app produces at `users/{uid}/wallet_backups/chunk_N` (see
// `uploadSnapshot()` / `_restoreFromCloud()` in
// `lib/src/cloud_sync/cloud_sync_controller.dart`). Keep the wire format
// (gzip -> UTF-8 JSON, 900KB chunk size, zero-padded-free `chunk_<index>` doc
// ids ordered by an `index` field) in lockstep with that file.

import { gzip, ungzip } from 'pako';
import {
  Bytes,
  collection,
  doc,
  getCountFromServer,
  getDoc,
  getDocs,
  orderBy,
  query,
  runTransaction,
  Timestamp,
  type DocumentData,
} from 'firebase/firestore';
import { db } from './firestore';
import { getDeviceId } from './deviceId';
import { decodeSnapshot, encodeSnapshot } from './ledgerCodec.ts';
import type { LedgerSnapshot } from './ledgerTypes';
import {
  assertFitsInOneCommit,
  hasWriteConflict,
  nextCloudRevision,
  readVersionConsistent,
  splitIntoChunks,
  timestampToMicros,
  type VersionToken,
} from './walletSyncGuards.ts';

export {
  CHUNK_SIZE,
  MAX_CLOUD_REVISION,
  timestampToMicros,
  WalletSyncRevisionOverflowError,
  WalletSyncTooLargeError,
  WalletSyncUnstableError,
  splitIntoChunks,
} from './walletSyncGuards.ts';

export interface CloudMeta {
  /**
   * Epoch-**microseconds** token derived from `users/{uid}.updatedAt` via
   * {@link timestampToMicros} — not `Timestamp.toMillis()`. See
   * `ConflictBaseline.updatedAtToken` in `walletSyncGuards.ts` for why
   * sub-millisecond precision matters here: it's what lets the conflict
   * check tell apart two writes landing in the same millisecond, which is
   * exactly the fallback signal a legacy (pre-`cloudRevision`) Flutter write
   * relies on.
   */
  updatedAtToken: number | null;
  lastWriterDeviceId: string | null;
  /**
   * Monotonically-incremented counter both clients now maintain on
   * `users/{uid}.cloudRevision` in the *same* transaction as the
   * profile-metadata/`wallet_backups` chunk writes (see
   * `firebase/firestore.rules`, which validates its type/range). When
   * present on both sides of a conflict check, it's the primary signal —
   * but *not* an automatic pass on its own: `updatedAtToken` is still
   * cross-checked when both sides have one, because an older Flutter
   * install that hasn't adopted `cloudRevision` yet can merge-update
   * `updatedAt` without bumping the counter. When absent entirely (an
   * account never touched by a revision-aware client), the check falls back
   * to `updatedAtToken` alone.
   */
  cloudRevision: number | null;
  /**
   * Number of `wallet_backups/chunk_N` documents observed at the same
   * instant as `updatedAtToken`/`cloudRevision` (i.e. from the same read).
   * Trusted *only* when a subsequent write's conflict check confirms the
   * cloud state hasn't moved since that read — see `claimAndWriteSnapshot`.
   */
  chunkCount: number;
}

/** Thrown when another writer has changed `users/{uid}` since `expectedMeta` was observed. */
export class WalletSyncConflictError extends Error {
  constructor(message = 'Wallet changed on another device/tab since the last sync.') {
    super(message);
    this.name = 'WalletSyncConflictError';
  }
}

function backupsCollection(uid: string) {
  return collection(db, 'users', uid, 'wallet_backups');
}

function chunkRef(uid: string, index: number) {
  return doc(db, 'users', uid, 'wallet_backups', `chunk_${index}`);
}

/**
 * Exported so `WalletDataContext`'s realtime listener can build a
 * `CloudMeta`-shaped value from a raw `onSnapshot` payload and feed it
 * straight into {@link hasWriteConflict} — reusing this instead of
 * duplicating the same `cloudRevision`/`updatedAt` field parsing inline
 * keeps that "did the cloud move since my baseline?" check in lockstep with
 * the one `claimAndWriteSnapshot` uses for its own conflict check.
 */
export function cloudMetaFromUserDoc(data: DocumentData | undefined, chunkCount: number): CloudMeta {
  if (!data) return { updatedAtToken: null, lastWriterDeviceId: null, cloudRevision: null, chunkCount };
  const cloudRevision = typeof data.cloudRevision === 'number' ? data.cloudRevision : null;
  return {
    updatedAtToken: timestampToMicros(data.updatedAt),
    lastWriterDeviceId: (data.lastWriterDeviceId as string | undefined) ?? null,
    cloudRevision,
    chunkCount,
  };
}

/** Cheap "version check" read of just the fields that change on every atomic snapshot write. */
async function readVersionToken(uid: string): Promise<VersionToken> {
  const snap = await getDoc(doc(db, 'users', uid));
  const meta = cloudMetaFromUserDoc(snap.exists() ? snap.data() : undefined, 0);
  return {
    cloudRevision: meta.cloudRevision,
    updatedAtToken: meta.updatedAtToken,
    lastWriterDeviceId: meta.lastWriterDeviceId,
  };
}

function legacyAccountsCollection(uid: string) {
  return collection(db, 'users', uid, 'accounts');
}
function legacyCategoriesCollection(uid: string) {
  return collection(db, 'users', uid, 'categories');
}
function legacyTransactionsCollection(uid: string) {
  return collection(db, 'users', uid, 'transactions');
}
function legacyCaptureCandidatesCollection(uid: string) {
  return collection(db, 'users', uid, 'captureCandidates');
}
function legacyImportBatchesCollection(uid: string) {
  return collection(db, 'users', uid, 'importBatches');
}
function legacyPreferencesDoc(uid: string) {
  return doc(db, 'users', uid, 'metadata', 'preferences');
}

/**
 * Reads the legacy uncompressed per-document collections — the same ones
 * `_restoreFromCloud()` in `lib/src/cloud_sync/cloud_sync_controller.dart`
 * falls back to when `wallet_backups` has no chunks yet (e.g. an account
 * that predates the compressed-blob sync format, or one only ever synced
 * from a very old client). Read-only: the PWA never writes to these
 * collections directly, it only migrates them forward the same way Flutter
 * does — implicitly, the next time *any* client uploads a fresh compressed
 * snapshot (see `claimAndWriteSnapshot()` below).
 */
async function downloadLegacySnapshot(uid: string): Promise<LedgerSnapshot> {
  const [accountsSnap, categoriesSnap, transactionsSnap, captureSnap, importsSnap, prefsSnap] =
    await Promise.all([
      getDocs(legacyAccountsCollection(uid)),
      getDocs(legacyCategoriesCollection(uid)),
      getDocs(legacyTransactionsCollection(uid)),
      getDocs(legacyCaptureCandidatesCollection(uid)),
      getDocs(legacyImportBatchesCollection(uid)),
      getDoc(legacyPreferencesDoc(uid)),
    ]);

  // Same restoreData shape Dart builds for this path (`preferences`,
  // `accounts`, `categories`, `transactions`, `captureCandidates`,
  // `importBatches` — no `syncSettings`/`exchangeRates`, which `decodeSnapshot`
  // already defaults sensibly when absent). Routed through the same robust
  // `decodeSnapshot` used for the compressed-chunk path so every field gets
  // the same defensive validation/coercion and unknown-field preservation.
  return decodeSnapshot({
    preferences: prefsSnap.exists() ? prefsSnap.data() : null,
    accounts: accountsSnap.docs.map((d) => d.data()),
    categories: categoriesSnap.docs.map((d) => d.data()),
    transactions: transactionsSnap.docs.map((d) => d.data()),
    captureCandidates: captureSnap.docs.map((d) => d.data()),
    importBatches: importsSnap.docs.map((d) => d.data()),
  });
}

export interface DownloadedSnapshot {
  snapshot: LedgerSnapshot;
  /**
   * Version-consistent cloud metadata captured atomically with `snapshot` —
   * use this directly as the baseline for a subsequent
   * {@link claimAndWriteSnapshot} call rather than a separate
   * `readCloudMeta()` read (see below for why that matters).
   */
  meta: CloudMeta;
}

/**
 * Downloads and decompresses every `wallet_backups/chunk_N` doc for `uid`.
 * Falls back to {@link downloadLegacySnapshot} when no compressed backup
 * exists yet, exactly mirroring Flutter's `_restoreFromCloud()` fallback —
 * without it, an existing user who hasn't been migrated to chunked backups
 * would see an empty wallet on the web client even though their data is
 * still in Firestore. The very next save from either client writes fresh
 * `wallet_backups` chunks, so this fallback is only ever needed once per
 * account: subsequent loads take the compressed-chunk path directly.
 *
 * The returned `meta` is captured **version-consistently** with `snapshot`
 * via {@link readVersionConsistent}: the chunk query (or legacy fallback)
 * is bracketed by two reads of `users/{uid}`'s `cloudRevision`/`updatedAt`,
 * and the whole cycle retries if they disagree. Without this, a separate
 * `Promise.all([downloadSnapshot(uid), readCloudMeta(uid)])` — as this
 * provider used to do — could straddle an atomic snapshot write: the chunk
 * query might return the *old* chunks while the metadata read returns the
 * *new* `cloudRevision`. The caller would then store the new revision as its
 * baseline alongside stale wallet content, and a later write from that same
 * baseline would pass its own conflict check (the baseline matches "live")
 * while actually clobbering a newer wallet with older data — exactly the
 * class of bug `claimAndWriteSnapshot`'s conflict check exists to prevent,
 * just smuggled in through a stale *read* instead of a stale write. Throws
 * {@link WalletSyncUnstableError} if the cloud state changes on every one of
 * `MAX_VERSION_CONSISTENCY_ATTEMPTS` attempts (an account being written to
 * faster than this client can read it consistently).
 */
export async function downloadSnapshot(uid: string): Promise<DownloadedSnapshot> {
  const { payload, version } = await readVersionConsistent(
    () => readVersionToken(uid),
    async () => {
      const snap = await getDocs(query(backupsCollection(uid), orderBy('index')));
      if (snap.empty) {
        return { snapshot: await downloadLegacySnapshot(uid), chunkCount: 0 };
      }

      const parts: Uint8Array[] = [];
      for (const d of snap.docs) {
        const data = d.data();
        const bytes = data.data as Bytes | undefined;
        if (bytes) parts.push(bytes.toUint8Array());
      }
      const total = parts.reduce((sum, p) => sum + p.length, 0);
      const merged = new Uint8Array(total);
      let offset = 0;
      for (const part of parts) {
        merged.set(part, offset);
        offset += part.length;
      }

      const jsonBytes = ungzip(merged);
      const jsonStr = new TextDecoder('utf-8').decode(jsonBytes);
      const parsed: unknown = JSON.parse(jsonStr);

      // Robust, defensive decode: every field is validated/coerced with safe
      // fallbacks (mirrors lib/src/data/ledger_codec.dart), and any keys this
      // client doesn't model yet are preserved via the `Extra` bag on each
      // object instead of being silently dropped.
      return { snapshot: decodeSnapshot(parsed), chunkCount: snap.docs.length };
    },
  );

  return {
    snapshot: payload.snapshot,
    meta: { ...version, chunkCount: payload.chunkCount },
  };
}

/**
 * Atomically re-validates `expectedMeta` against the current cloud state and
 * — if it still holds — writes the new snapshot's chunks, prunes exactly the
 * stale trailing ones, and bumps `users/{uid}` metadata, **all in one
 * Firestore transaction**. This replaces an earlier version that committed
 * the metadata bump in one transaction and the chunk batch in a *separate*
 * step: that left a real window where `updatedAt` claimed a new snapshot
 * existed before the chunk documents backing it were actually written, and
 * where the Flutter client (or another web tab/device) could write chunks
 * in between the two steps that this client's later chunk-batch would then
 * silently clobber.
 *
 * The Flutter client now implements the matching half of this protocol in
 * `lib/src/cloud_sync/cloud_sync_write_guard.dart` / `CloudSyncController`:
 * it reads `users/{uid}` live inside its own transaction, compares
 * `cloudRevision` (or falls back to `updatedAt` when either side lacks it,
 * with the same no-device-exemption semantics as {@link hasWriteConflict}),
 * and writes its metadata bump + chunk sets + prune deletes together in one
 * commit — so this is now a **formally shared cross-client protocol**, not
 * just a same-origin safeguard with incidental Flutter protection. Both
 * sides increment `cloudRevision` by exactly 1 per successful write and
 * treat any mismatch (not just "older/newer") as a conflict, which is what
 * closes the same-writer-identity race (two PWA tabs, or two app installs
 * sharing a restored device id) that a `lastWriterDeviceId`-based check
 * alone cannot.
 *
 * The exact stale-chunk prune range (`[newChunkCount, expectedMeta.chunkCount)`)
 * is only trustworthy because it's computed *after* confirming the cloud
 * state hasn't moved since `expectedMeta` was observed — if it had, this
 * throws {@link WalletSyncConflictError} before touching anything, so a
 * stale `chunkCount` can never lead to an incorrect prune.
 *
 * Firestore transactions can only `get()` individual document references,
 * not run queries — this design deliberately avoids ever needing to query
 * the chunk collection from inside the transaction (see
 * {@link assertFitsInOneCommit} for the size/write-count guard that fails
 * visibly instead of falling back to an unsafe non-atomic path when a
 * wallet is too large to write this way).
 *
 * Returns the exact {@link CloudMeta} this write produced — `nextRevision`,
 * `deviceId` as `lastWriterDeviceId`, the precise `updatedAt` token, and
 * `chunks.length` as the new `chunkCount` — so the caller (`persist()` in
 * `WalletDataContext.tsx`) can adopt it directly as its new baseline instead
 * of issuing a separate `readCloudMeta()` round-trip after the commit. That
 * separate read used to be exactly the same class of bug this function's
 * conflict check exists to prevent, just smuggled back in on the *read*
 * side: if another writer's commit landed in the gap between this
 * transaction committing and that follow-up read, the follow-up read would
 * return *that other writer's* revision/timestamp, and this client would
 * adopt it as "my own last-known-good baseline" — even though its in-memory
 * ledger was never built from it. A subsequent write from that poisoned
 * baseline would then pass its own conflict check and clobber the other
 * writer's commit. Using a `Timestamp.now()` captured once, before the
 * transaction (fixed across any transaction-internal retry, the same way
 * `chunks`/`deviceId` already are), means this call always knows the exact
 * value it wrote and never needs to ask the server what it just committed.
 */
export async function claimAndWriteSnapshot(
  uid: string,
  snapshot: LedgerSnapshot,
  profile: { email: string | null; displayName: string | null },
  expectedMeta: CloudMeta,
): Promise<CloudMeta> {
  const deviceId = getDeviceId();

  const jsonStr = JSON.stringify(encodeSnapshot(snapshot));
  const jsonBytes = new TextEncoder().encode(jsonStr);
  const compressed = gzip(jsonBytes);
  const chunks = splitIntoChunks(compressed);

  const staleChunkCount = Math.max(0, expectedMeta.chunkCount - chunks.length);
  assertFitsInOneCommit({
    newChunkCount: chunks.length,
    staleChunkCount,
    totalBytes: compressed.length,
  });

  const userRef = doc(db, 'users', uid);
  // Captured once, outside (and before) the transaction body — see the doc
  // comment above for why this must be the exact value returned as this
  // write's `CloudMeta` baseline, not re-derived from a post-commit read.
  const writeTimestamp = Timestamp.now();

  return await runTransaction(db, async (transaction) => {
    const userSnap = await transaction.get(userRef);
    const cloudMeta = cloudMetaFromUserDoc(
      userSnap.exists() ? userSnap.data() : undefined,
      expectedMeta.chunkCount, // not authoritative yet — only trusted after the check below passes
    );

    if (hasWriteConflict(cloudMeta, expectedMeta)) {
      throw new WalletSyncConflictError();
    }

    // Past this point, the cloud state is confirmed unchanged since
    // `expectedMeta` was observed, so `expectedMeta.chunkCount` is now known
    // to be the true current chunk count — safe to use for an exact prune.
    // `nextCloudRevision()` throws `WalletSyncRevisionOverflowError` here —
    // before any `transaction.set()`/`transaction.delete()` call below is
    // even issued — if bumping the counter would exceed the int32 ceiling
    // `firestore.rules` enforces, so that failure mode is a clear, actionable
    // error instead of an opaque rules-permission-denied rejection from the
    // commit itself.
    const nextRevision = nextCloudRevision(cloudMeta.cloudRevision);
    transaction.set(
      userRef,
      {
        email: profile.email,
        displayName: profile.displayName,
        authProvider: 'google',
        updatedAt: writeTimestamp,
        lastWriterDeviceId: deviceId,
        cloudRevision: nextRevision,
      },
      { merge: true },
    );

    chunks.forEach((chunk, i) => {
      transaction.set(chunkRef(uid, i), {
        index: i,
        data: Bytes.fromUint8Array(chunk),
        updatedAt: writeTimestamp,
      });
    });
    for (let i = chunks.length; i < expectedMeta.chunkCount; i++) {
      transaction.delete(chunkRef(uid, i));
    }

    return {
      updatedAtToken: timestampToMicros(writeTimestamp),
      lastWriterDeviceId: deviceId,
      cloudRevision: nextRevision,
      chunkCount: chunks.length,
    };
  });
}

/**
 * Reads `users/{uid}`'s metadata plus the current `wallet_backups` chunk
 * count, for conflict checks — version-consistently (see the doc comment on
 * {@link downloadSnapshot} for why the count and the revision/timestamp must
 * come from the same cloud state, not two independent round-trips).
 */
export async function readCloudMeta(uid: string): Promise<CloudMeta> {
  const { payload: chunkCount, version } = await readVersionConsistent(
    () => readVersionToken(uid),
    async () => {
      const countSnap = await getCountFromServer(backupsCollection(uid));
      return countSnap.data().count;
    },
  );
  return { ...version, chunkCount };
}
