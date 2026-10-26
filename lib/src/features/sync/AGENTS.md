# `lib/src/features/sync/` — Cloud Sync Status & Conflict Resolution

## 🎯 Role & Overview
UI screen and diagnostics for monitoring cloud synchronization status, viewing last sync timestamps, inspecting pending unsynced changes, triggering manual synchronization, and resolving conflict states.

---

## 📜 Key Files

- **`sync_screen.dart`**:
  - Displays sync state (`idle`, `restoring`, `uploading`, `error`), pending record counts, connected device ID, and account email.
  - Provides a manual "Sync Now" button and conflict resolution actions.

---

## 🛡️ Critical Invariants & Architecture

1. **Clear Sync State Feedback**:
   - The UI must distinguish between network offline status and authentication errors.
2. **Conflict Prevention**:
   - If a conflict occurs, the screen offers clear choices: keep local state, overwrite with cloud state, or create a backup before overwriting.

---

## 🔍 LLM / Developer Checklist

- [ ] Check `test/cloud_sync_write_guard_test.dart`.
- [ ] Confirm that tapping "Sync Now" disables subsequent button presses while sync is in progress (`CloudSyncPhase.uploading` or `checking`).
