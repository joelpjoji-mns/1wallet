# `lib/src/startup/` — Application Startup & Hydration

## 🎯 Role & Overview
Coordinates application warmup, local database loading from disk, migration checks, and initial state hydration before rendering the main shell.

---

## 📜 Key Files

- **`startup_state.dart`**:
  - Tracks warmup progress (`initializing`, `ready`, `error`).
  - Ensures `LedgerController` completes loading cached state from `SharedPreferences` or local filesystem before screens read the ledger.
  - **Offline mode branch** (`AuthState.isLocalOnly`, via `_offlineStartupState`): routes permissions → onboarding → home for the `'local-user'` owner and skips all cloud-sync gating, so startup works with zero network and no Firebase. Before showing any data it asks `AuthController.verifyLocalOwnership` to confirm the stored wallet is owned by `'local-user'`. A uid-owned wallet finishes an interrupted upgrade or returns to sign-in.
  - The online branch is unchanged: signed-out users route to `/login`.

---

## 🛡️ Critical Invariants & Architecture

1. **Sequential Loading**:
   - Preferences and encryption keys must hydrate before the encrypted ledger payload is loaded and decoded.
2. **Crash Resilience**:
   - If initial hydration encounters corrupted data, the startup engine falls back to the most recent automatic backup without crashing the app.

---

## 🔍 LLM / Developer Checklist

- [ ] Check `test/ledger_persistence_test.dart` and `test/backup_restore_and_downgrade_guard_test.dart`.
- [ ] Ensure any async initialization added here does not introduce unnecessary startup delay.
- [ ] Offline startup must never depend on `cloudSyncControllerProvider` progress or Firebase. Run `test/offline_mode_startup_test.dart`.
