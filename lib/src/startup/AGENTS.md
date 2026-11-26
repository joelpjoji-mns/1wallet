# `lib/src/startup/` — Application Startup & Hydration

## 🎯 Role & Overview
Coordinates application warmup, local database loading from disk, migration checks, and initial state hydration before rendering the main shell.

---

## 📜 Key Files

- **`startup_state.dart`**:
  - Tracks warmup progress (`initializing`, `ready`, `error`).
  - Ensures `LedgerController` completes loading cached state from `SharedPreferences` or local filesystem before screens read the ledger.
  - **Offline mode branch** (`AuthState.isLocalOnly`, via `_offlineStartupState`): verifies ownership and sends a new `'local-user'` wallet to setup, requiring at least one account before discovery. Existing wallets open Home without hints. It skips cloud-sync gating. A uid-owned wallet finishes an interrupted upgrade or returns to sign-in.
  - Signed-out users route to `/login`. For an online wallet with no local data, bootstrap and cloud-wallet checks must finish before treating it as new and showing the welcome.

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
- [ ] Use `_deferStartupAction` for deferred startup mutations. It discards superseded builds and avoids reading an invalidated provider `Ref` inside a microtask.
- [ ] Offline startup must never depend on `cloudSyncControllerProvider` progress or Firebase. Run `test/offline_mode_startup_test.dart`.
