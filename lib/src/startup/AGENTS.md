# `lib/src/startup/` — Application Startup & Hydration

## 🎯 Role & Overview
Coordinates application warmup, local database loading from disk, migration checks, and initial state hydration before rendering the main shell.

---

## 📜 Key Files

- **`startup_state.dart`**:
  - Tracks warmup progress (`initializing`, `ready`, `error`).
  - Ensures `LedgerController` completes loading cached state from `SharedPreferences` or local filesystem before screens read the ledger.

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
