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
  serverTimestamp,
  type DocumentData,
} from 'firebase/firestore';
import { db } from './firebase';
import { getDeviceId } from './deviceId';
import { decodeSnapshot, encodeSnapshot } from './ledgerCodec.ts';
import type { LedgerSnapshot } from './ledgerTypes';
import {
  assertFitsInOneCommit,
  hasWriteConflict,
  splitIntoChunks,
} from './walletSyncGuards.ts';

export { CHUNK_SIZE, WalletSyncTooLargeError, splitIntoChunks } from './walletSyncGuards.ts';

export interface CloudMeta {
  updatedAtMs: number | null;
  lastWriterDeviceId: string | null;
  /**
   * Monotonically-incremented counter this client maintains on
   * `users/{uid}.cloudRevision` (see `firebase/firestore.rules`, which
   * validates its type/range but is written by this client only today —
   * the Flutter client does not yet participate in this field). When
   * present on both sides of a conflict check, it's the authoritative
   * signal; when absent (an account never touched by a revision-aware
   * client, or one only ever written by the current Flutter client), the
   * check falls back to `updatedAtMs`.
   */
  cloudRevision: number | null;
  /**
   * Number of `wallet_backups/chunk_N` documents observed at the same
   * instant as `updatedAtMs`/`cloudRevision` (i.e. from the same read).
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

function cloudMetaFromUserDoc(data: DocumentData | undefined, chunkCount: number): CloudMeta {
  if (!data) return { updatedAtMs: null, lastWriterDeviceId: null, cloudRevision: null, chunkCount };
  const updatedAt = data.updatedAt;
  const updatedAtMs =
    updatedAt && typeof updatedAt.toMillis === 'function' ? (updatedAt.toMillis() as number) : null;
  const cloudRevision = typeof data.cloudRevision === 'number' ? data.cloudRevision : null;
  return {
    updatedAtMs,
    lastWriterDeviceId: (data.lastWriterDeviceId as string | undefined) ?? null,
    cloudRevision,
    chunkCount,
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
  /** Chunk doc count observed at the same instant, or `0` for the legacy fallback path. */
  chunkCount: number;
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
 * Also reports the exact chunk count observed, so callers can later present
 * it back as part of `expectedMeta` for {@link claimAndWriteSnapshot} — this
 * is what lets a write compute an *exact* stale-chunk prune range without
 * needing a query inside the write transaction (Firestore transactions can't
 * run queries).
 */
export async function downloadSnapshot(uid: string): Promise<DownloadedSnapshot> {
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
 * Folding everything into one transaction closes that window for this
 * client's own writes, and — because the transaction reads `users/{uid}`
 * (which every writer, Flutter included, already touches on every save) —
 * Firestore's transaction engine will force a retry (re-running this whole
 * function, including the conflict check) if any other commit touches that
 * same document while this one is in flight. That gives real, practical
 * protection against a race with the current Flutter client too, **but it
 * is not a formally agreed cross-client protocol**: Flutter does not (yet)
 * read/write `cloudRevision`, does not perform its own compare-and-swap
 * transaction, and its chunk writes are not individually version-checked
 * within this transaction (only `users/{uid}` is `get()`-ed). Do not
 * describe this as guaranteeing atomicity *with* Flutter until Flutter
 * adopts a matching transactional protocol — see `firebase/README.md` for
 * the proposed shared schema.
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
 */
export async function claimAndWriteSnapshot(
  uid: string,
  snapshot: LedgerSnapshot,
  profile: { email: string | null; displayName: string | null },
  expectedMeta: CloudMeta,
): Promise<void> {
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

  await runTransaction(db, async (transaction) => {
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
    const nextRevision = (cloudMeta.cloudRevision ?? 0) + 1;
    transaction.set(
      userRef,
      {
        email: profile.email,
        displayName: profile.displayName,
        authProvider: 'google',
        updatedAt: serverTimestamp(),
        lastWriterDeviceId: deviceId,
        cloudRevision: nextRevision,
      },
      { merge: true },
    );

    chunks.forEach((chunk, i) => {
      transaction.set(chunkRef(uid, i), {
        index: i,
        data: Bytes.fromUint8Array(chunk),
        updatedAt: serverTimestamp(),
      });
    });
    for (let i = chunks.length; i < expectedMeta.chunkCount; i++) {
      transaction.delete(chunkRef(uid, i));
    }
  });
}

/** Reads `users/{uid}`'s metadata plus the current `wallet_backups` chunk count, for conflict checks. */
export async function readCloudMeta(uid: string): Promise<CloudMeta> {
  const [userSnap, countSnap] = await Promise.all([
    getDoc(doc(db, 'users', uid)),
    getCountFromServer(backupsCollection(uid)),
  ]);
  return cloudMetaFromUserDoc(userSnap.exists() ? userSnap.data() : undefined, countSnap.data().count);
}
