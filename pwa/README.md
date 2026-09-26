# 1Wallet Web (PWA)

This is the **active web client** for 1Wallet, and the app deployed at the
Firebase Hosting root (see `../firebase.json`). It reads and writes the same
real wallet data as the Flutter mobile/desktop app — no mock/placeholder
figures — by sharing the exact cloud sync format the Flutter client uses.

## How data sync works

Both clients read/write GZip-compressed JSON ledger snapshots at
`users/{uid}/wallet_backups/chunk_N` in Firestore (owner-scoped by Firestore
security rules in `../firebase/firestore.rules`):

- `src/lib/walletSync.ts` — downloads/decompresses all chunks into a
  `LedgerSnapshot` (`src/lib/ledgerTypes.ts`, which mirrors
  `lib/src/data/ledger_codec.dart` field-for-field), and re-compresses +
  re-chunks (900KB/chunk, matching the Flutter client) on save.
  `claimAndWriteSnapshot()` writes the `users/{uid}` metadata bump **and**
  every chunk set/delete inside one Firestore transaction — metadata and
  chunk content commit atomically together, or neither does. The Flutter
  client implements the matching half of this protocol
  (`lib/src/cloud_sync/cloud_sync_write_guard.dart` /
  `CloudSyncController`), so this is a **formally shared cross-client
  protocol**, not just a same-origin safeguard — see `../firebase/README.md`
  for the full contract and deterministic regression tests on both sides.
- `src/lib/walletSyncGuards.ts` — the pure (Firebase-free) conflict-decision
  and atomic-commit-size logic `claimAndWriteSnapshot()` relies on, unit
  tested directly in `walletSyncGuards.test.ts` (`npm test`). The conflict
  check has **no exemption for a matching device id** — two browser tabs of
  the same device/profile share one persisted device id, so an earlier
  version that skipped the conflict whenever "the last writer was me" let a
  second tab silently clobber the first tab's write; this is covered by a
  dedicated same-device-second-tab regression test in both this file and
  `firebase/rules.test.mjs` (and mirrored on the Flutter side in
  `hasCloudSyncConflict()`). A wallet too large to write as a single atomic
  Firestore commit (over ~9 MiB, or too many combined chunk/prune/metadata
  writes) throws `WalletSyncTooLargeError` rather than silently falling back
  to a non-atomic write that would reopen the same race. It also has
  `readVersionConsistent()`: `downloadSnapshot()` and `readCloudMeta()` both
  use this to bracket their bulk read (chunk download+decode, or just a chunk
  count) with two reads of `users/{uid}`'s `cloudRevision`/`updatedAt`,
  retrying the whole cycle if they disagree. Without it, a previous version
  of `WalletDataContext.load()` did
  `Promise.all([downloadSnapshot(uid), readCloudMeta(uid)])` — two
  independent round-trips that could straddle an atomic snapshot write: the
  chunk query could return the *old* chunks while the metadata read returned
  the *new* `cloudRevision`, poisoning the baseline the provider would later
  trust for its own writes (a later write from that stale-but-"matching"
  baseline could pass its own conflict check while actually clobbering a
  newer wallet). Throws `WalletSyncUnstableError` if the cloud state changes
  on every retry attempt; see `walletSyncGuards.test.ts` for the injected
  version-change regression (no Firestore/emulator needed).
- **The conflict baseline (`expectedMeta`) must be what this client's
  in-memory ledger was last actually synced to — never a value re-read fresh
  right before a specific write attempt.** `WalletDataContext.persist()`
  passes `lastKnownMetaRef.current` (set at the last successful `load()` or
  `persist()`) to `claimAndWriteSnapshot()`. An earlier version instead did a
  fresh `readCloudMeta()` call immediately before each write, reasoned to
  only reduce spurious conflicts since "the transaction's live re-read at
  commit is the real check either way" — that reasoning was wrong: it's a
  false-negative bug. If another writer commits between this client's last
  sync and that fresh pre-write read, the fresh read already reflects the
  other commit, so it "matches" the live state at commit time and the
  conflict check wrongly reports "no conflict", letting this client's
  in-memory ledger (which never saw that commit) silently overwrite it.
  Flutter's `CloudSyncController.uploadSnapshot()` had the identical bug,
  fixed the same way (baseline from `CloudSyncMetadata.lastCloudRevision`
  instead of a fresh read). See `hasWriteConflict: a stale "last-synced"
  baseline detects a conflict a fresh pre-write read would miss` in
  `walletSyncGuards.test.ts`.
- `src/context/WalletDataContext.tsx` — owns the in-memory snapshot, debounces
  saves, and relies on `claimAndWriteSnapshot()` for concurrency safety: if
  another writer won the race, the upload throws `WalletSyncConflictError`
  (no partial write), the app reloads the newer cloud copy, and asks you to
  reapply your change. Every debounced save is also bound to the uid that was
  active when it was scheduled (`src/lib/pendingSaveGuard.ts`) — switching
  users (sign-out / sign-in as someone else) while a save is still pending
  drops it instead of uploading it to the wrong account; see
  `src/lib/pendingSaveGuard.test.ts` for the regression coverage
  (`npm test`). On *any* uid change — sign-out **and** a direct switch from
  one signed-in user straight to another — the provider's own
  `useLayoutEffect` synchronously resets `snapshot` to
  `emptyLedgerSnapshot()` and clears the cloud-metadata baseline, before
  starting the new user's load. This isn't just privacy hygiene: `load()`'s
  `isIncomingSnapshotSafer()` safety check compares the incoming wallet
  against whatever `current` snapshot is in memory, and would otherwise
  compare user B's legitimate (but possibly smaller) wallet against user A's
  leftover transactions — refusing to apply it and leaving A's data stuck on
  screen. Resetting first means that check always starts from zero
  transactions for a new uid, so it can never block the new user's first
  load. See `src/lib/uidSwitchGuard.test.ts` for that regression (pure logic,
  no DOM needed).
- **The effect-based reset above is *defense-in-depth*, not the primary
  fix.** `AuthProvider` can switch directly from signed-in user A to
  signed-in user B while `WalletDataProvider` stays mounted (only its `user`
  context value changes) — and any effect, including `useLayoutEffect`, still
  runs *after* the render that first sees the new uid. That render, on its
  own, could carry `snapshot` still holding user A's data. The actual fix is
  in `App.tsx`'s `Workspace` component: `<WalletDataProvider key={user?.uid}>`
  forces React to fully **unmount** the old provider instance (destroying its
  state entirely) and **mount a brand-new one** — whose initial `snapshot`
  state is always `emptyLedgerSnapshot()` — synchronously as part of the
  *same* reconciliation pass that picks up the new uid. There is structurally
  no render where the new uid is visible alongside the old user's data,
  because the component instance holding that data no longer exists (and its
  unmount cleanup still cancels any pending debounced-save timer normally).
  See `src/lib/uidSwitchRender.test.ts` for the regression: it renders a
  minimal reproduction of this exact shape with real React + jsdom (the one
  DOM-dependent test in this project — `WalletDataProvider`/`AuthProvider`
  themselves can't be imported outside Vite, see the test's header comment),
  proves the unkeyed version *can* render the new uid paired with the old
  user's data, proves the keyed version never does, and additionally asserts
  `App.tsx`'s source still contains the `key={user?.uid}` guard so removing
  it there also fails the test.
- Every mutation (`addTransaction`, `updateAccount`, …) spreads the original
  record rather than rebuilding it from a narrow object, so fields this web
  client doesn't model (or that only exist in newer/older app versions)
  round-trip untouched.
- If `wallet_backups` has no chunks yet (an account that predates the
  compressed-blob format, or only ever synced from a very old client),
  `downloadSnapshot()` falls back to reading the legacy uncompressed
  per-document collections (`users/{uid}/{accounts,categories,transactions,
  captureCandidates,importBatches}` + `metadata/preferences`) — the exact same
  fallback `_restoreFromCloud()` uses in
  `lib/src/cloud_sync/cloud_sync_controller.dart` — through the same
  `decodeSnapshot()` used for the compressed-chunk path, so existing users
  don't see an empty wallet on the web. This is read-only: the PWA never
  writes to those legacy collections, and the very next save from either
  client (this one included) writes fresh `wallet_backups` chunks, so the
  fallback is only ever exercised once per account. See
  `src/lib/legacyRestoreFallback.test.ts` for coverage of the decode step.

### Secure account details stay device-only

Some accounts carry `encryptedDetails` (e.g. masked card/account numbers),
encrypted with a per-device key held in the OS secure enclave/keystore on the
device that created them (`lib/src/utils/secure_key_store.dart`). This web
client has no access to that key and **never attempts to decrypt, display, or
edit** those fields — they are shown as a locked badge and always written back
unchanged.

## Installability & offline shell

- `public/manifest.webmanifest` + the icons/meta tags in `index.html` make the
  app installable (standalone display, themed splash).
- `public/sw.js` is a hand-written service worker that caches **only the
  static app shell** (built HTML/JS/CSS/icons from this origin). It explicitly
  skips every cross-origin request — which is where all Firebase Auth and
  Firestore wallet-data traffic lives — so auth tokens and wallet data are
  never cached. It's registered from `src/registerServiceWorker.ts` in
  production builds only.

## Scripts

```bash
npm install      # install dependencies
npm run dev      # local dev server
npm run build    # tsc -b && vite build -> dist/
npm run lint     # oxlint
npm run test     # node --test src/lib/*.test.ts (mostly pure unit regressions, no
                 # Firebase/emulator needed; one test uses jsdom to render real React —
                 # see uidSwitchRender.test.ts)
npm run preview  # preview a production build locally
```

Copy `.env` (already present for local development) and set the `VITE_*`
Firebase web config values for your own Firebase project if deploying
elsewhere. These are the public Firebase *web app* config values (safe to
ship in a client bundle by design) — not service-account credentials.

## Project layout

```text
pwa/
├── public/
│   ├── manifest.webmanifest   # PWA install manifest
│   └── sw.js                  # app-shell-only service worker
└── src/
    ├── lib/                   # firebase.ts, walletSync.ts, ledgerTypes.ts,
    │                          # ledgerSelectors.ts, deviceId.ts, id.ts, money.ts,
    │                          # pendingSaveGuard.ts (+ .test.ts)
    ├── context/               # AuthContext, WalletDataContext (data + CRUD)
    ├── components/            # AccountModal, TransactionModal (shared forms)
    └── pages/                 # HomePage, HistoryPage, CalendarPage,
                                 # PlannerPage, AccountsPage
```

