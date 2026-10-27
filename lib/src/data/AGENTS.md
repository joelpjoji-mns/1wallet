# `lib/src/data/` — Ledger Models, Serialization & State Providers

## 🎯 Role & Overview
This directory is the foundational domain layer of 1Wallet. It defines the core immutable financial models (`LedgerState`, `TransactionRecord`, `Account`, `Category`, `FutureGenerationRule`), codecs for serialization/deserialization, and Riverpod providers that maintain global application state.

---

## 📜 Key Files

| File | Responsibilities |
| :--- | :--- |
| `ledger_models.dart` | Core data models: `Money`, `Account`, `Category`, `TransactionRecord`, `FutureGenerationRule`, `ExchangeRateRecord`, `CaptureCandidate`, `ImportBatch`, `LedgerPreferences`, and `LedgerState`. |
| `ledger_codec.dart` | Encodes and decodes `LedgerState` to/from JSON maps, ensuring backward compatibility across schema migrations. |
| `ledger_providers.dart` | Riverpod providers: `ledgerProvider` (`LedgerController`), `ledgerRepositoryProvider`, `ledgerLoadStateProvider`, and automatic backup triggers. `LedgerUserIdentity.localOwner` / `ownsDeviceWallet` model the offline owner. Offline lifecycle: `claimForLocalOwner`, `releaseLocalOwner`, `adoptLocalWalletForOwner`, `resetLocalWalletForCloudOwner`. |
| `ledger_merge.dart` | `mergeLedgerStates`: cloud-wins-by-id union of two same-owner wallets for the offline → Google "merge" choice. |
| `backup_codec.dart` | AES-256-GCM portable backups (PBKDF2 passphrase) and device backups. `decodeBackup(adoptAsLocalOwner: true)` re-wraps secure fields for the offline owner. `rekeyLedgerForOwner` moves a wallet to a new owner and keeps unreadable fields instead of failing. |
| `ledger_defaults.dart` | Default seed categories, default payment methods, and initial settings for new wallets. |
| `ledger_archive.dart` | Export and import mechanisms for wallet backups, JSON dumps, and historical archives. |
| `category_taxonomy.dart` | Hierarchical category definitions, parent-child mappings, and default taxonomy trees. |
| `exchange_rate_service.dart` | FX rate fetching, local rate caching, and currency conversion math. |

---

## 🛡️ Critical Invariants & Architecture

1. **Integer Minor Units**:
   - `Money.amountMinor` is an `int`. Decimal fractions of standard currencies must never be stored as floating point numbers.
2. **Immutability & Pure Reducers**:
   - `LedgerState` is strictly immutable. Every mutation in `LedgerController` (`addRecord`, `deleteAccount`, `updateRule`) creates a new instance via `.copyWith(...)` and marks `unsyncedChanges = true`.
3. **Double-Entry Consistency**:
   - For transfer transactions (`type == 'transfer'`), both `accountId` and `counterAccountId` must be present and distinct.
4. **Data Isolation**:
   - Backups and local JSON payloads must not store raw unencrypted master keys.
5. **Wallet Ownership (`'local-user'` vs Google uid)**:
   - `LedgerUserIdentity.isAuthenticated` means "a real Google account" and drives owner stamping and foreign-wallet detection. Do not widen it.
   - Device-capture ownership (native capture queue, spool polling, legacy capture assignment) uses `ownsDeviceWallet`, so offline mode captures like a signed-in account.
   - Secure account fields are encrypted per owner. Moving a wallet between owners must re-key them (`rekeyLedgerForOwner`).
   - An offline import is stamped `'local-user'` and never takes the backup's Google uid.

---

## 🔍 LLM / Developer Checklist

- [ ] If you add a new field to any model in `ledger_models.dart`:
  - Add it to `copyWith(...)`.
  - Add it to `toMap()` and `fromMap(...)`.
  - Provide a sensible default value in `fromMap(...)` to support reading older schema versions.
  - Update `ledger_codec.dart` tests (`test/ledger_persistence_test.dart`).
- [ ] Ensure `LedgerProvidersConfig.disableAutoBackup` is respected during unit tests to avoid file system race conditions.
- [ ] Ownership changes: run `test/offline_backup_roundtrip_test.dart`, `test/offline_upgrade_migration_test.dart` and `test/user_backup_isolation_test.dart`.
