# 1Wallet — Ledger State Schema & Codec Specification

This document details the serialization formats, Firestore document structure, and schema migration guarantees of the 1Wallet data layer.

---

## 🗄️ Firestore Document Structure: `users/{uid}`

The profile and optimistic-concurrency baseline use:
```
users/{uid}
```

### Document Top-Level Fields

| Field | Type | Description |
| :--- | :--- | :--- |
| `cloudRevision` | optional bounded `int` | Incremented transactionally on every successful snapshot upload. |
| `updatedAt` | `timestamp` | Exact committed baseline timestamp; compared even when revisions match. |
| `lastWriterDeviceId` | nullable `string` | Writer identity for restore heuristics, never an exemption from write conflicts. |
| `email`, `displayName`, `authProvider` | profile fields | Owner-only fields validated by Firestore rules. |

The actual live payload is GZip JSON split into
`users/{uid}/wallet_backups/chunk_N` documents with `index`, binary `data`, and
`updatedAt`. Profile metadata, chunk writes, and stale-chunk pruning commit in one
transaction. Readers bracket the bulk download with matching version reads.
A present, valid empty snapshot is authoritative; record dates do not override
its revision. Legacy per-document collections remain readable for migration.

---

## 🧩 In-Memory `LedgerState` Schema

```typescript
interface LedgerState {
  version: number;
  userId: string;
  accounts: Account[];
  categories: Category[];
  transactions: TransactionRecord[];
  exchangeRates: ExchangeRateRecord[];
  captureCandidates: CaptureCandidate[];
  importBatches: ImportBatch[];
  preferences: LedgerPreferences;
}
```

### 1. `Account`
```typescript
interface Account {
  id: string;               // UUID v4
  name: string;             // e.g. "Primary Checking"
  type: string;             // "checking" | "savings" | "credit" | "cash" | "loan" | "wallet"
  currency: string;         // ISO-4217 code (e.g. "USD", "INR")
  openingBalance: Money;      // Integer minor units and currency
  color: number;            // ARGB 32-bit integer color
  iconName: string;         // Material icon identifier string
  creditLimitMinor?: number; // Credit limit for cards (minor units)
  statementDay?: number;    // Day of month (1-31)
  dueDay?: number;          // Day of month (1-31)
  isArchived: boolean;
}
```

### 2. `TransactionRecord`
```typescript
interface TransactionRecord {
  id: string;               // UUID v4
  type: string;             // "expense" | "income" | "transfer"
  accountId: string;        // Source account ID
  counterAccountId?: string;// Destination account ID (for transfers)
  categoryId?: string;      // Category ID (optional for transfers)
  amount: Money;            // Integer minor units and ISO currency
  baseAmount: Money;
  occurredAt: string;       // ISO 8601 UTC timestamp
  payeeOrMerchant?: string; // Merchant / recipient name
  notes?: string;           // Optional user notes
  tags: string[];           // Custom tags array
  attachments?: TransactionAttachment[];
  originalTransactionId?: string; // Link to originating scheduled record
  counterAmount?: Money;    // Converted destination amount for a transfer
}
```

### 3. `Category`
```typescript
interface Category {
  id: string;
  name: string;
  type: string;             // "expense" | "income"
  parentId?: string;        // Hierarchical subcategory support
  color: number;            // ARGB integer
  iconName: string;
  monthlyBudgetMinor?: number;
  isArchived: boolean;
}
```

---

## 🔄 Schema Migration Protocol

When evolving the schema:
1. Increment `currentLedgerStateVersion` in
   [the Dart ledger codec](../lib/src/data/ledger_codec.dart) when the shared
   ledger schema changes.
2. Add migration transformations in `lib/src/data/ledger_codec.dart` to upgrade older documents upon deserialization.
3. Keep `pwa/src/lib/ledgerCodec.ts` and `firebase/firestore.rules` synchronized.
4. Backwards compatibility tests must be added to `test/ledger_persistence_test.dart` and `test/backup_restore_and_downgrade_guard_test.dart`.

## Local persistence, revisions, and ingress receipts

Local persistence wraps canonical ledger JSON in `onewallet.local.v2`, with
owner, monotonically increasing local revision, pending ingress receipt IDs, and
an authoritative-empty checkpoint. An arbitrary preference-only revision does
not prove an empty wallet is initialized or authorize erasing an existing cloud
wallet; explicit restoration/deletion and verified synchronization establish it.
These are device bookkeeping, not extra cloud payload fields. A valid primary
snapshot is trusted even when empty; an older populated fallback file must not
resurrect deleted data. Decode errors are explicit, not a fresh-wallet fallback.

The immutable Dart model carries `localRevision` and `ingressReceipts`, but
canonical ledger JSON intentionally omits them. All mutators, restores, clears,
and upload acknowledgments share one serialized lane. Dirty flags are written
before state notification. An upload may clear dirty state only for its captured
local revision. Session generations invalidate stale work before teardown.

Ingress receipt IDs are saved atomically with the local ledger, retained until
the native SQLite acknowledgment succeeds, and preserved across cloud/manual
restore. The native queue tags owner/source/stable ID and retains quarantined
payloads. Legacy unowned messages require confirmation before assignment.

## Financial input validation

Required money is `{ amountMinor: integer, currency: string }`. Malformed supplied
amounts and floating minor units are rejected, not rounded or silently zeroed.
Supported legacy integer strings migrate explicitly; genuinely absent optional
fields may use their documented fallback. The PWA rejects values outside
JavaScript's safe integer range rather than silently changing financial values.

Obsolete `quietHoursEnabled` and `biometricLockEnabled` preference keys are
accepted as unknown legacy fields but are no longer emitted. The quiet-hours
control belonged only to a disabled alert path; actual device app lock uses its
separate persisted controller state and is not changed by archive restoration.

## Backup and secure-field formats

- Canonical `onewallet.ledger.archive` JSON is an internal/legacy archive, not
  encryption. Its FNV checksum detects accidental changes, not malicious edits.
- Automatic backups wrap the archive in owner/purpose-scoped device-key
  authenticated encryption and stay in app-private storage.
- Portable `onewallet.encrypted.backup` version 1 uses AES-256-GCM, a fresh
  12-byte nonce, 16-byte salt, and PBKDF2-HMAC-SHA256 with the fixed supported
  600,000-iteration profile. Envelope metadata is authenticated; unsupported KDF
  profiles, wrong passphrases, and modified ciphertext fail before mutation.
  Encoded backup envelopes are limited to 64 MiB of characters; writers and
  readers apply the same bound, so an oversized archive is rejected before
  replacing a previous backup.
- Portable export unwraps readable secure fields inside the authenticated
  transport; import re-encrypts them under the importing owner's device key.
  Unreadable source fields are not silently dropped.
- Secure fields use `v2:` plus a base64 JSON envelope containing key alias,
  context, nonce, and ciphertext/tag. Old two-part SIC and original legacy
  ciphertext remain explicit migration inputs, never the format for new writes.
- General multi-device cloud key distribution is not implemented. Remote
  unreadable secure ciphertext is preserved and reported, not overwritten.

Primary local ledger snapshots are OS-user local storage, not encrypted backup
files; desktop document-directory caches are not an application sandbox.
Cloud payload compression is likewise not end-to-end encryption.

## Deletion jobs

`accountDeletionJobs/{uid}` is a server-only immutable-owner job/tombstone outside
the erased wallet subtree. It records processing/lease state and a hash of the
client's scoped status receipt, not ledger contents. Wallet rules fence access
while it exists, including for old clients with cached tokens. Server workers
delete nested Firestore data and Auth last. Client success additionally requires
verified owner-specific local cleanup.

See the [backend deployment and recovery guide](../firebase/functions/README.md)
for receipt recovery, retention constraints, emulator verification, and the
separate production activation checklist.

## Installed-client update metadata compatibility

The build passed to Flutter is a base number. A split APK has a different native
Android `versionCode` (for example base `2102206` becomes arm64 `2104206`).
Update manifests, release-document IDs, and channel `latestVersionCode` must
carry the **actual packaged APK code**, read from the APK rather than guessed.
The semantic version and APK checksum remain the authentic release values.

The shipped 2.2.01 native update worker compares raw installed and published
codes. Publishing a base code lower than its installed split code suppresses
that worker, leaving the old Dart updater to attempt a broken notification
before exposing its install button. Correct metadata allows the existing native
worker to advance the shared delivery marker, which the shipped Dart flow reads
after its normal preference-cache refresh. Users can then use the existing
in-app checksum-verified download and Android installer handoff.

Channel publication sets both `versionName` and `latestVersionName` consistently.
The publisher never substitutes a fake zero code or disables checksum/signature
verification. Release validation checks the actual APK against its manifest,
and pinned legacy-client tests reproduce both the failure and recovery paths.
