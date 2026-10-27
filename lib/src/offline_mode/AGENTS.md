# `lib/src/offline_mode/` — Offline-Only Mode ("Local Wallet") Coordination

## 🎯 Role & Overview
Orchestrates the two cross-cutting offline-mode workflows that touch auth, the ledger and cloud sync at once:

1. **Entering offline mode** from the signed-out entry screen (no Google account, no Firebase user, no cloud sync).
2. **Upgrading offline → Google** ("Back up & sync with Google"): moving the device-only wallet to a Google account without losing or duplicating data, and never silently replacing an existing cloud wallet.

The persisted `AppMode` itself lives in `lib/src/auth/app_mode.dart` (auth is the lowest layer that needs it).

---

## 📜 Key Files

- **`offline_mode_controller.dart`**:
  - `OfflineModeController` / `offlineModeControllerProvider`: `enterOfflineMode()`, `startGoogleUpgrade()`, `resolveCloudWalletChoice()`, `cancelUpgrade()`, `acknowledge()`, `markAnnounced()`.
  - `OfflineUpgradeCloudGateway` (+ `FirestoreOfflineUpgradeGateway`, `offlineUpgradeCloudGatewayProvider`): the only Firestore access the upgrade needs (probe, consistent snapshot fetch for merge, sync-owner baseline priming). Tests override it with a fake.
  - `CloudWalletChoice { keepLocal, keepCloud, merge }`, `OfflineUpgradeStage`, `OfflineEntryResult`.

---

## 🛡️ Critical Invariants & Architecture

1. **Offline mode never touches Firebase Auth or Firestore.** No anonymous sign-in. `AuthState.user` stays `null`, and every cloud path keys off that field.
2. **Offline mode only ever opens a `'local-user'` wallet.** `enterOfflineMode` refuses (`walletBelongsToAccount`) when the stored wallet holds data owned by a Google uid. An empty leftover wallet is replaced with an empty local one.
3. **Upgrade ordering is fixed.** Each step starts only after the previous one succeeds:
   1. Google sign-in **without publishing** the account (`AuthController.signInWithGoogleForUpgrade`).
   2. Server probe of the account's cloud wallet. When both sides hold data the user must choose keep-local / keep-cloud / merge, and nothing changes before that choice.
   3. All remaining network reads (the version-consistent cloud wallet for a merge).
   4. `primeOwner`: record the uid as sync owner, plus the cloud baseline the migrated wallet supersedes (keep-local: probed version, merge: fetched version, keep-cloud: none).
   5. One serialized ledger mutation: `adoptLocalWalletForOwner` (re-keys secure fields, stamps the uid, commits as unsynced) or `resetLocalWalletForCloudOwner` (writes the on-device safety backup, then resets like a fresh sign-in).
   6. `completeOfflineUpgrade`: persist `AppMode.online`, **then** publish the account, so the standard `CloudSyncController._bootstrap` uploads or restores.

   A failure before step 5 signs out of Google and leaves offline mode and the wallet exactly as before.
4. **No silent clobbering.** Keep-local/merge uploads run through the normal transactional conflict check against the primed baseline, so a cloud write that lands mid-upgrade still surfaces as a conflict.
5. **Interrupted upgrades self-heal at startup** via `AuthController.verifyLocalOwnership`: a uid-owned wallet in offline mode either finishes the upgrade (same Google session) or returns to sign-in. Nothing is deleted.

---

## 🔍 LLM / Developer Checklist

- [ ] Run `test/offline_upgrade_migration_test.dart`, `test/offline_mode_startup_test.dart` and `test/login_offline_option_test.dart`.
- [ ] Never publish a Google user to `AuthState` before the ledger migration step completes.
- [ ] Keep all Firestore access for the upgrade behind `OfflineUpgradeCloudGateway`.
- [ ] Any new destructive branch must leave a recoverable copy (see `resetLocalWalletForCloudOwner`).
