# Firebase (Firestore rules)

This folder owns the Firestore security rules (`firestore.rules`) that gate
every read/write the 1Wallet clients (Flutter mobile/desktop and the web PWA
in `../pwa`) make against Cloud Firestore.

## Data model this enforces

- `users/{uid}` — profile doc (`email`, `displayName`, `authProvider`,
  `lastWriterDeviceId`, …), owner-only.
- `users/{uid}/wallet_backups/chunk_N` — the **live** sync path. Both the
  Flutter app (`uploadSnapshot()` /  `_restoreFromCloud()` in
  `lib/src/cloud_sync/cloud_sync_controller.dart`) and the web PWA
  (`pwa/src/lib/walletSync.ts`) write/read a GZip-compressed JSON snapshot of
  the ledger here, split into ≤900KB chunks (`{ index, data: bytes,
  updatedAt }`), owner-only, strict schema.
- `users/{uid}/wallets/{walletId}/snapshots/{snapshotId}/chunks/{chunkId}` —
  a newer/alternate snapshot layout kept for forward-compatibility; not
  currently written by either client, but validated the same way.
- `users/{uid}/{accounts,categories,transactions,budgets,goals,
  captureCandidates,importBatches}/{id}` — legacy per-document collections,
  still readable/writable by the owner as a restore fallback.
- `appUpdates/{platform}/releases|channels/{id}` — public, read-only
  (`get` only, no `list`) release metadata used by in-app update checks.

## Running the rules tests

Tests live in `rules.test.mjs` and run against the **Firebase Local Emulator
Suite only** — no real project, credentials, or network access to Firebase is
used or required.

```powershell
# From the repo root:
npm --prefix firebase install

# Requires a JDK 21+ on PATH for the Firestore emulator, and the Firebase CLI
# (`npm install -g firebase-tools`, or use `npx firebase-tools`).
firebase emulators:exec --only firestore --project demo-1wallet-rules `
  "node --test firebase/rules.test.mjs"
```

The tests cover: owner-only access to profile/transaction/backup-chunk
documents, rejection of cross-user reads/writes, schema enforcement on
`wallet_backups` chunks (required fields, unknown-field rejection, empty-blob
rejection), chunk pruning (delete), the public-read/no-write/no-list contract
for `appUpdates`, optional-field type/range validation on `users/{uid}`
(`cloudRevision`, `ledgerVersion`), and three deterministic regressions for
the optimistic-concurrency transaction the web client uses to claim a write
slot and write chunks atomically (see below).

## Concurrency-safety: `users/{uid}` + `wallet_backups` writes

The web client (`pwa/src/lib/walletSync.ts`, `claimAndWriteSnapshot()`) writes
the `users/{uid}` metadata bump **and every chunk set/delete** inside a single
Firestore transaction. An earlier version split this into a metadata-only
transaction followed by a separate chunk `writeBatch()`; that left a real gap
where `updatedAt` could claim a new snapshot existed before its chunk
documents were actually written, and where another writer (a second web
tab/device, or the Flutter client) could write chunks in between the two
steps that the delayed chunk-batch would then silently clobber. Folding
everything into one transaction closes that window entirely for the web
client's own writes: the commit is now genuinely all-or-nothing.

The conflict check itself (`hasWriteConflict()` in
`pwa/src/lib/walletSyncGuards.ts`) was also fixed to remove a
`lastWriterDeviceId`-based exemption that silently broke down for two browser
**tabs of the same device** (they share one persisted device id) — the
second tab's stale baseline would never be flagged as conflicting with the
first tab's write, because "the last writer was me" was treated as
automatically safe. The fixed check is judged purely on whether the cloud
state (a `cloudRevision` counter when present, else `updatedAt`) has advanced
past what *that specific caller* last observed, with no identity-based
exemptions at all. `rules.test.mjs` has three deterministic regressions for
this transaction: a different-device stale-baseline rejection, a
**same-device second-tab** stale-baseline rejection (the actual bug), and a
same-commit atomicity check (metadata + chunk both land together, or neither
does). `pwa/src/lib/walletSyncGuards.test.ts` covers the same conflict logic
as a pure unit test, with zero Firestore/emulator dependency.

**What this does and does not guarantee against the Flutter client:**
Firestore transactions can only `get()` individual document references, not
run queries, so the transaction reads `users/{uid}` only (not the chunk
collection) — the exact stale-chunk prune range is instead computed from a
`chunkCount` the caller observed in the same read as its conflict baseline,
trusted only because the transaction's own conflict check just confirmed
nothing has changed since that read. Because the transaction reads
`users/{uid}`, which Flutter's `uploadSnapshot()` batch also always touches,
Firestore's engine will force this transaction to retry if a concurrent
Flutter write lands mid-transaction, and the retried conflict check will then
correctly see Flutter's update — so there **is** real, practical protection
against a race with the current Flutter client. However, this is **not** a
formally agreed cross-client protocol: Flutter does not read or write
`cloudRevision`, does not perform its own compare-and-swap transaction, and
its own chunk writes are not individually version-checked by this
transaction. Do not describe this mechanism as *guaranteeing* atomicity with
Flutter until Flutter's writer adopts a matching transactional protocol.

A wallet whose compressed snapshot is too large to write as one atomic
Firestore commit (over ~9 MiB, or requiring more than ~500 combined
chunk/prune/metadata writes) is refused outright with a clear
`WalletSyncTooLargeError` — rather than silently falling back to a
non-atomic multi-step write that would reopen the exact race this design
closes. Supporting wallets that large would need a versioned
staging/pointer protocol (write new chunks to fresh, immutable locations,
then atomically flip a small pointer document) coordinated with the Flutter
client, since Flutter's reader has no such indirection today — see
`assertFitsInOneCommit()` in `pwa/src/lib/walletSyncGuards.ts` for where this
is enforced.

### Proposed schema for Flutter to adopt (not yet implemented there)

To turn "practical, retry-driven protection" into a *guaranteed*
cross-client protocol, the Flutter writer would need to:

1. Read `users/{uid}.cloudRevision` (already validated by these rules:
   optional int, `0..2147483647`) inside its own transaction before writing.
2. Reject/retry if the observed value doesn't match what it last persisted
   locally (the same compare-and-swap the web client performs).
3. Increment `cloudRevision` by exactly 1 in the same transaction/batch that
   writes its chunks, exactly mirroring `claimAndWriteSnapshot()`.

Until that lands, `cloudRevision` is written by the web client only; accounts
never touched by a revision-aware client simply fall back to the
`updatedAt`-based heuristic, which is safe but less precise (subject to
clock/server-timestamp resolution, though not to the device-identity
exemption bug described above, since that check has no identity component at
all anymore).
