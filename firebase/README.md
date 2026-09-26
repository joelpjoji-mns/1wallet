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

CI runs this automatically: `.github/workflows/pr-validation.yml`'s
`validate-firestore-rules` job sets up JDK 21 + Node, installs
`firebase/package-lock.json`'s dependencies, and runs the same command via
`npx firebase-tools emulators:exec --only firestore --project
demo-1wallet-rules "npm --prefix firebase test"` on every PR — so a rules
change that breaks these tests fails CI the same way a Flutter or PWA
regression would, rather than only being caught locally.

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

**Cross-client status — now a formally shared protocol:** Firestore
transactions can only `get()` individual document references, not run
queries, so the transaction reads `users/{uid}` only (not the chunk
collection) — the exact stale-chunk prune range is instead computed from a
`chunkCount` the caller observed in the same read as its conflict baseline,
trusted only because the transaction's own conflict check just confirmed
nothing has changed since that read. The Flutter client (implemented in
`lib/src/cloud_sync/cloud_sync_write_guard.dart` + `CloudSyncController`) now
implements the matching half of this protocol: it reads `users/{uid}` live
inside its own transaction, compares `cloudRevision` (exact match required —
and, even on a match, also conflicts if `updatedAt` differs — falling back to
the no-device-exemption `updatedAt`-only comparison when either side lacks a
revision yet), and writes its metadata bump + chunk sets + prune deletes
together in one commit. Both clients increment `cloudRevision` by exactly 1
per successful write. This means the protocol below is **implemented on both
sides**, not just a same-origin safeguard with incidental Flutter protection
— a stale writer on *either* client can no longer partially or fully clobber
a snapshot written by the other.

A wallet whose compressed snapshot is too large to write as one atomic
Firestore commit (over ~9 MiB, or requiring more than ~500 combined
chunk/prune/metadata writes) is refused outright by both clients with a
clear `WalletSyncTooLargeError`/`CloudSyncOversizeException` — rather than
silently falling back to a non-atomic multi-step write that would reopen the
exact race this design closes. Both `assertFitsInOneCommit()`
(`pwa/src/lib/walletSyncGuards.ts`) and `ensureWithinCloudSyncWriteBudget()`
(`lib/src/cloud_sync/cloud_sync_write_guard.dart`) guard the same two
ceilings — the 500-write limit and a matching conservative 9 MiB
(`cloudSyncMaxCommitBytes`/`FIRESTORE_COMMIT_BYTE_LIMIT`) byte budget.
Supporting wallets larger than either ceiling would need a versioned
staging/pointer protocol (write new chunks to fresh, immutable locations,
then atomically flip a small pointer document) coordinated across both
clients, since neither reader has such indirection today.

### Shared schema (implemented on both clients)

1. `users/{uid}.cloudRevision` (optional int, `0..2147483647`, validated by
   these rules) is read live inside a transaction before every write.
   **Both clients guard against overflowing this ceiling before writing
   anything**: `nextCloudRevision()` (`pwa/src/lib/walletSyncGuards.ts` /
   `lib/src/cloud_sync/cloud_sync_write_guard.dart`) throws a distinct,
   explicit error (`WalletSyncRevisionOverflowError` /
   `CloudSyncRevisionOverflowException`) *before* the transaction issues any
   writes if incrementing would exceed `2147483647`, rather than letting the
   write fail as an opaque rules-permission-denied rejection. Practically
   unreachable (over two billion successful syncs), but cheap to guard
   explicitly on both sides.
2. Conflict iff the live value differs from what the writer last observed
   (exact `!=`, not just "newer/older") — this is what closes the
   same-writer-identity race (two PWA tabs, or two app installs sharing a
   restored device id): the revision doesn't care who wrote it.
3. **Even when the live `cloudRevision` matches what was observed, still
   conflict if both sides also carry an `updatedAt` (or, on the PWA side, the
   precise microsecond token derived from it) and it differs.** A matching
   revision alone does not prove nothing changed: an old/partial writer that
   touches `users/{uid}` (e.g. profile-only fields) without going through
   this revision-bumping transaction advances `updatedAt` without ever
   bumping `cloudRevision`, and a revision-only check would silently treat
   that as "no conflict" and let it be clobbered. **Implemented on both
   clients**: `hasCloudSyncConflict()` in
   `lib/src/cloud_sync/cloud_sync_write_guard.dart` and `hasWriteConflict()`
   in `pwa/src/lib/walletSyncGuards.ts` both cross-check the timestamp
   whenever both sides have one, even when `cloudRevision` matches.
4. When both sides lack `cloudRevision` yet (rollout window / very old
   client), fall back to `updatedAt` alone: conflict iff the live value is
   strictly newer than what was observed. Deliberately has **no**
   `lastWriterDeviceId`-based exemption on either client — an earlier version
   of both implementations special-cased "same last writer" as always safe,
   which silently reopened the same-identity race this whole protocol exists
   to close.
5. **Comparing `updatedAt` for exact equality (item 3) only works if a
   device's own last-written `updatedAt` and its persisted next baseline are
   bit-for-bit identical — otherwise a device can falsely conflict with
   itself.** A lazily-resolved `FieldValue.serverTimestamp()`/server
   timestamp is never visible to the client that wrote it, so approximating
   it client-side after commit (e.g. a separately-captured "now") will not
   round-trip exactly. Both clients capture one concrete timestamp *before*
   opening the transaction, write that same value verbatim as
   `users/{uid}.updatedAt`, and persist that exact value as the next baseline
   (Flutter: `CloudSyncController.uploadSnapshot()`'s `writeTimestamp` /
   `CloudSyncMetadata.lastObservedCloudUpdatedAt`; PWA:
   `claimAndWriteSnapshot()`'s `writeTimestamp`, returned as part of the
   `CloudMeta` the caller adopts directly). **That captured timestamp is
   normalized to millisecond precision on both clients** — Dart's
   `DateTime.now()`/`Timestamp.now()` natively carries microsecond precision,
   so Flutter explicitly truncates with
   `Timestamp.fromMillisecondsSinceEpoch(DateTime.now()
   .millisecondsSinceEpoch)`; the Firestore JS SDK's `Timestamp.now()` the PWA
   captures is already millisecond-precision by construction (built from
   `Date.now()`), so no extra truncation is needed on that side — comparing
   at full microsecond precision would otherwise make "exact equality" a
   Flutter-only concept the PWA's own writes could never satisfy. The PWA
   compares at microsecond *resolution* (`timestampToMicros()` in
   `pwa/src/lib/walletSyncGuards.ts`) purely to distinguish two
   *different-writer* documents landing in the same millisecond — its own
   writes are still always exact multiples of 1000 microseconds, so this
   never introduces a false self-conflict.
6. On no-conflict: write `cloudRevision: liveRevision + 1` together with
   `updatedAt`/`lastWriterDeviceId`/profile fields **and** the chunk
   sets/prune-deletes, all in the same transaction.
7. **The baseline must be "what this client's in-memory ledger is actually
   known to be consistent with" — the state observed at the last successful
   load or write — never a value re-read fresh right before this specific
   write attempt.** An earlier version of both clients did the latter,
   reasoning it would only reduce spurious conflicts since "the transaction's
   own live re-read at commit time is still the real check either way". That
   reasoning was wrong: it's a false-negative bug. If another writer commits
   *between* this client's last successful sync and that fresh pre-write
   read, the fresh read already reflects the other writer's revision — so it
   matches what the transaction re-reads live at commit, "no conflict" is
   reported, and this client's in-memory ledger (which never saw that
   commit) silently overwrites it. Both clients now build `expected` from the
   last-synced state instead (`WalletDataContext`'s `lastKnownMetaRef` /
   `CloudSyncMetadata.lastCloudRevision`); the transaction's live re-read at
   commit remains the authoritative safety net for races *after* that
   baseline was captured, but only if the baseline itself was correct to
   begin with. See `hasWriteConflict: a stale "last-synced" baseline detects
   a conflict a fresh pre-write read would miss` in
   `pwa/src/lib/walletSyncGuards.test.ts`.
8. Surface a distinct conflict error (`WalletSyncConflictError` /
   `CloudSyncConflictException`) and a distinct oversize error
   (`WalletSyncTooLargeError` / `CloudSyncOversizeException`) — never retry a
   stale write silently.
9. **Read-side version consistency.** A bulk read that spans multiple
   round-trips (downloading+decoding `wallet_backups/chunk_N`, or just
   counting them) must not be paired with a separately-fetched
   `cloudRevision`/`updatedAt` baseline — the two reads can straddle an
   atomic write, so the chunk content and the revision you end up trusting
   as "what I just saw" could describe two different snapshot versions.
   `pwa/src/lib/walletSync.ts`'s `downloadSnapshot()`/`readCloudMeta()` and
   the Flutter side's `readCloudSyncVersionConsistent()` in
   `lib/src/cloud_sync/cloud_sync_write_guard.dart` both bracket their bulk
   read with two reads of `cloudRevision`/`updatedAt`, retrying the whole
   cycle (bounded, 3 attempts) if they disagree, and throwing
   `WalletSyncUnstableError`/`CloudSyncUnstableException` if it never
   stabilizes. **Both clients'** "stable" check also requires an
   equal-revision pair's `updatedAt` to match exactly (mirroring item 3
   above — `isVersionStable()` in `pwa/src/lib/walletSyncGuards.ts` and
   `isCloudSyncVersionStable()` in `cloud_sync_write_guard.dart`), for the
   same reason: a write between the two bracketing reads that only advances
   `updatedAt` must not be missed just because `cloudRevision` happens to
   still match. The verified-stable `after` version this bracket returns is
   what gates both the trusted chunk count used for the stale-chunk prune
   range and the decoded snapshot content itself — never a value read
   separately from either.
10. **Applying a verified-stable incoming snapshot must not fall back to a
    content-based heuristic.** Once item 9's bracket has positively verified
    the bulk read matches one specific cloud revision, that snapshot *is*
    the current cloud state by definition — including one with fewer
    transactions than what's currently loaded, or none at all (a legitimate
    deletion, or a wallet cleared entirely, necessarily shrinks the
    transaction count). An earlier version of both clients instead re-ran a
    count/timestamp heuristic at this point (`isIncomingSnapshotSafer()` in
    `pwa/src/lib/ledgerCodec.ts` / `LedgerState.isIncomingLedgerSafer` in
    `lib/src/data/ledger_models.dart`) that rejected exactly those legitimate
    cases, permanently blocking cross-device deletions from ever syncing
    down. Both clients now instead only ask whether *this* device itself has
    unsynced local edits still pending or in flight —
    `shouldAcceptCloudLoad({ hasUnsyncedLocalChanges })` in
    `pwa/src/lib/walletSyncGuards.ts` and `shouldAcceptCloudRestore({
    required bool hasUnsyncedLocalChanges })` in
    `lib/src/cloud_sync/cloud_sync_write_guard.dart` are the same
    single-boolean-negation contract: accept the verified snapshot outright
    when there's nothing local left to protect; otherwise leave local state
    and the cloud-metadata baseline untouched so the next upload attempt's
    own conflict check (item 2/3 above) runs against the true live cloud
    state instead. The old heuristic (`isIncomingSnapshotSafer`/
    `isIncomingLedgerSafer`) is kept, unchanged, on both clients purely for
    a local-backup-file restore path with no version information to lean on
    (Flutter's `importArchive()`; not yet implemented on the PWA side).

## Cross-client parity: findings and resolutions

Found during a parity review between the Flutter and PWA sync
implementations. `lib/**` is outside the PWA workstream's direct scope, so
Flutter-side fixes were implemented by the Flutter workstream and are
recorded here for reference; the counterpart PWA-side work is cross-referenced
inline where relevant.

### Resolved (Flutter-side)

1. **Bootstrap didn't restore PWA-first-created accounts.**
   `CloudSyncController._bootstrap()` used to gate its entire
   restore-from-cloud decision on whether the legacy
   `users/{uid}/metadata/preferences` document existed. The web client never
   writes that document (it only *reads* it as part of the legacy-collections
   fallback in `downloadLegacySnapshot()`), so an account created via the PWA
   first had `users/{uid}` + `wallet_backups/chunk_N` populated but no
   `metadata/preferences` doc, and `_bootstrap()` would silently never
   restore it. Fixed with `hasCloudWalletData(userDocExists,
   legacyPreferencesDocExists) => userDocExists || legacyPreferencesDocExists`
   as the shared gate (deduped into a `shouldPullCloudSnapshot()` helper used
   by both `_bootstrap()` and `fullSync()`) — a PWA-only wallet is now
   correctly detected and pulled.
2. **`uploadSnapshot()`'s conflict baseline was re-read fresh right before
   the write** (the same false-negative class as item 7 in "Shared schema"
   above): if a write landed between the in-memory ledger's last load and
   that fresh pre-write read, the fresh read would already reflect it,
   masking the conflict and letting the stale in-memory ledger clobber it.
   Fixed to build `expected` from `CloudSyncMetadata.lastCloudRevision` /
   `lastObservedCloudUpdatedAt` — the state persisted at the last successful
   push or pull — instead of a fresh read. `WalletDataContext.persist()` had
   the identical bug (introduced when an earlier revision of this doc
   recommended "read as fresh as possible" as a pure optimization); fixed the
   same way — see item 7 above.
3. **`ensureWithinCloudSyncWriteBudget()` had no byte-size guard.** It only
   checked the 500-write ceiling, not Firestore's ~10 MiB per-commit byte
   ceiling. Fixed to match `assertFitsInOneCommit()` exactly: a
   `cloudSyncMaxCommitBytes = 9 * 1024 * 1024` budget (same conservative 9
   MiB figure as `FIRESTORE_COMMIT_BYTE_LIMIT` on the web side), checked via
   `exceedsCloudSyncByteBudget({ totalBytes, limit })` alongside the
   existing write-count check, throwing `CloudSyncOversizeException` for
   either ceiling before the transaction opens.
4. **`_restoreFromCloud()` had the same read-version-consistency gap
   `downloadSnapshot()` was fixed for on the web side — confirmed real and
   reachable, not just theoretical.** It took `cloudRevision`/`cloudUpdatedAt`
   as parameters from its caller's earlier single `users/{uid}` read, then
   did its own separate, later `wallet_backups` collection query to actually
   download chunks, and persisted the *original* pre-download values as the
   new baseline regardless of what was actually downloaded — so a write
   landing between the initial check and the chunk download could pair
   downloaded content with a stale revision. Fixed with
   `isCloudSyncVersionStable()` / `readCloudSyncVersionConsistent()` in
   `cloud_sync_write_guard.dart`, mirroring `isVersionStable()` /
   `readVersionConsistent()` (same revision-exact-match-else-
   updatedAt-exact-match semantics, same "retry the whole cycle including the
   payload fetch, not just the version check" behavior, same 3-attempt
   bound, matching `CloudSyncUnstableException` /
   `WalletSyncUnstableError`). The chunk-download/legacy-fallback logic was
   extracted into `_fetchCloudRestoreData()` so it can be the injectable,
   wholesale-re-run payload fetch; `_restoreFromCloud()` now brackets it with
   two `users/{uid}` reads and persists the *verified-stable* `after` version
   as the new baseline — the redundant `cloudUpdatedAt`/`cloudRevision`
   parameters were dropped from its signature entirely (all three call
   sites — `fullSync`, `_bootstrap`, `_handleCloudUpdate` — updated).
5. **A matching `cloudRevision` was trusted as "no conflict" even when
   `updatedAt` had also changed, and `lastObservedCloudUpdatedAt` was
   persisted as a `DateTime.now()` approximation of the server-resolved
   `FieldValue.serverTimestamp()` the writer never actually sees.** Both
   `hasCloudSyncConflict()` and `isCloudSyncVersionStable()` now also compare
   `updatedAt` for exact equality when both sides carry a matching
   `cloudRevision` (see items 3 and 9 in "Shared schema" above), to catch an
   old/partial writer that advances `updatedAt` without going through the
   revision-bumping transaction. Making that comparison exact required
   fixing the self-conflict risk it would otherwise introduce:
   `uploadSnapshot()` now captures one client-side timestamp
   (`writeTimestamp`), normalized to millisecond precision via
   `Timestamp.fromMillisecondsSinceEpoch(DateTime.now()
   .millisecondsSinceEpoch)` (Dart's `DateTime.now()`/`Timestamp.now()` are
   microsecond-precision by default, but the PWA's Firestore JS SDK
   `Timestamp.now()` is millisecond-only via `Date.now()` — comparing at
   microsecond precision would make "exact equality" impossible for the PWA
   to ever satisfy), before opening the transaction, writes that literal
   value as `users/{uid}.updatedAt` instead of `FieldValue.serverTimestamp()`,
   and persists that same value's `DateTime` as
   `CloudSyncMetadata.lastObservedCloudUpdatedAt` — so a device's own round
   trip (write → persist baseline → next upload's live re-read) is
   bit-for-bit identical and never falsely conflicts with itself, while a
   genuinely different writer's timestamp (including an old client's
   full-precision `FieldValue.serverTimestamp()`) still differs and is still
   caught. **The PWA side now mirrors this exactly**:
   `pwa/src/lib/walletSyncGuards.ts`'s `hasWriteConflict()`/
   `isVersionStable()` have the same equal-revision-but-changed-`updatedAt`
   branch (comparing the epoch-microsecond `updatedAtToken` derived from
   `timestampToMicros()`), and `pwa/src/lib/walletSync.ts`'s
   `claimAndWriteSnapshot()` captures one `Timestamp.now()` before opening
   the transaction (already millisecond-precision on that side by
   construction), writes it verbatim, and returns the resulting `CloudMeta`
   directly from the transaction — no post-commit re-read — for
   `WalletDataContext.persist()` to adopt as its next baseline. Both clients
   now agree on what counts as a conflict.

Everything in this document has been implemented and verified on both
clients as of this writing — no remaining cross-client parity gaps are
tracked here. Future changes to either client's sync protocol should update
this document and its counterpart doc comments together, keeping both
implementations in lockstep.
