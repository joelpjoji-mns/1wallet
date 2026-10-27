# `lib/src/cloud_sync/` — Cloud Synchronization & Write Guards

## 🎯 Role & Overview
This directory houses the offline-first synchronization engine connecting local `LedgerState` to Firebase Cloud Firestore. It is responsible for safe snapshot uploads, remote snapshot downloads, conflict detection, and race condition prevention.

---

## 📜 Key Files

- **`cloud_sync_metadata.dart`**:
  - `CloudSyncMetadata`: Holds owner/device identity, the last cloud revision/timestamp baseline, push/pull times, and sync interval. Old per-document IDs/checksums are ignored on read and no longer written.
- **`cloud_sync_write_guard.dart`**:
  - `CloudSyncWriteGuard`: Invariant verification service ensuring an outdated local state never overwrites a newer cloud state.
  - Guards against race conditions during user login, logouts, or simultaneous edits across multiple devices.
  - `cloudWritesAllowed(...)` / `offlineModeSyncDisabledReason`: offline mode (a device-only wallet) may never write to Firestore.
- **`cloud_sync_controller.dart`**:
  - `CloudSyncController`: A `StateNotifier<CloudSyncState>` that coordinates syncing phases:
    `disabled`, `idle`, `checking`, `restoring`, `uploading`, `error`.
  - Serializes `LedgerState` into Firestore document `users/{uid}`.
  - Monitors connectivity and automatically pushes dirty (`unsyncedChanges == true`) local states.
  - In offline mode it stays `CloudSyncPhase.disabled` with `offlineModeSyncDisabledReason`. This holds even when Firebase is not configured, and `uploadSnapshot` refuses up front.
  - Offline → Google upgrade helpers (used only via `OfflineUpgradeCloudGateway` in `lib/src/offline_mode/`):
    - `probeCloudWallet`: server-only presence check mirroring `_bootstrap`.
    - `fetchCloudWalletSnapshot`: version-consistent download for a merge.
    - `primeCloudSyncOwnerForUpgrade`: records the uid and the cloud baseline the migrated wallet supersedes, so `_bootstrap` never resets it as a previous user's data.
  - The bulk download is shared with `_restoreFromCloud` through `_fetchCloudRestoreDataFrom`.

---

## 🛡️ Critical Invariants & Architecture

1. **Safety Before Upload**:
   - Before any upload, the remote snapshot timestamp and revision must be checked. If remote is newer, conflict resolution or merge logic is triggered instead of an unverified overwrite.
2. **Account Switching Isolation**:
   - When switching Firebase `uid`, syncing must halt immediately, state flushed/reloaded for the new user, and write guard reset.
3. **Optimistic Local Commits**:
   - Local ledger modifications are committed immediately to local storage with `unsyncedChanges = true`. Cloud sync processes asynchronously in the background.
4. **Offline Mode Is Permanently Disabled Sync**:
   - Every Firestore path requires a published Firebase user (`AuthState.user`), and offline mode never publishes one. Do not add a Firestore call that is reachable without that user.
   - Offline edits still set `has_unsynced_changes`, so an upgrade uploads them.

---

## 🔍 LLM / Developer Checklist

- [ ] Verify changes against `test/cloud_sync_write_guard_test.dart`, `test/cloud_sync_restore_category_scan_test.dart` and `test/offline_mode_startup_test.dart` (offline sync stays disabled).
- [ ] Ensure sensitive local credentials or encryption passphrases are never synced in plain text to Firestore.
- [ ] Confirm error states are user-visible via `CloudSyncPhase.error` so the UI can present retry or diagnostic options.
