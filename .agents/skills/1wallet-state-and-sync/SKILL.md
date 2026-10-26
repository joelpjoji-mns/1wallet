---
name: 1wallet-state-and-sync
description: >-
  Rules and runbooks for maintaining the offline-first ledger, cloud sync, and encryption state.
  Use when modifying data models, codecs, cloud sync, or authentication hooks.
---

# 1Wallet State & Sync Engine Skill

## Invariants

1. **Deterministic Serialization**:
   - `LedgerCodec` encodes and decodes `LedgerState`.
   - Any new property added to `TransactionRecord`, `Account`, `Category`, or `LedgerPreferences` must be handled in both `toMap()` and `fromMap()` in `lib/src/data/ledger_models.dart`, with backwards compatibility for old backups.

2. **Write Guards**:
   - `CloudSyncWriteGuard` prevents local state from overwriting newer remote snapshots if the user switched accounts or restored from a backup.
   - Never force upload without checking `unsyncedChanges` and comparing remote revision timestamps.

3. **Multi-User Isolation**:
   - Each authenticated user gets their own Firestore document: `users/{uid}`.
   - When switching users (`AuthState` changes), `LedgerController` must reset or reload user-scoped data to prevent cross-account contamination.

4. **Biometric & Encryption Flow**:
   - Sensitive backups or keys are encrypted using `AES-256-GCM` with keys derived via `PBKDF2`.
   - Refer to `lib/src/utils/secure_key_store.dart` and `lib/src/security/app_lock.dart`.
