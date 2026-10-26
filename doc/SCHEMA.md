# 1Wallet — Ledger State Schema & Codec Specification

This document details the serialization formats, Firestore document structure, and schema migration guarantees of the 1Wallet data layer.

---

## 🗄️ Firestore Document Structure: `users/{uid}`

In Cloud Firestore, each user's synchronized wallet is stored at the single document path:
```
users/{uid}
```

### Document Top-Level Fields

| Field | Type | Description |
| :--- | :--- | :--- |
| `schemaVersion` | `int` | Current schema version (e.g. `2`). Used by write guards to reject older/unsupported clients. |
| `updatedAt` | `timestamp` / `int` | Epoch millisecond timestamp of the last write. Used for conflict detection. |
| `deviceId` | `string` | Unique client installation identifier preventing self-conflict loops. |
| `data` | `map` / `string` | Serialized ledger JSON object or compressed Pako/Gzip payload string. |

---

## 🧩 In-Memory `LedgerState` Schema

```typescript
interface LedgerState {
  schemaVersion: number;
  unsyncedChanges: boolean;
  accounts: Account[];
  categories: Category[];
  records: TransactionRecord[];
  recurringRules: FutureGenerationRule[];
  exchangeRates: ExchangeRateRecord[];
  captureQueue: CaptureCandidate[];
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
  openingBalanceMinor: number; // Integer minor units
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
  amountMinor: number;      // Integer minor units (e.g. 5000 = $50.00)
  currency: string;         // ISO-4217 code
  timestamp: string;        // ISO 8601 UTC timestamp
  payeeOrMerchant?: string; // Merchant / recipient name
  notes?: string;           // Optional user notes
  tags: string[];           // Custom tags array
  attachments?: TransactionAttachment[];
  recurringRuleId?: string; // Link to originating scheduled rule
  transferDestinationAmountMinor?: number; // Converted amount in counter-account currency
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
1. Increment `kLedgerSchemaVersion` in `lib/src/data/ledger_models.dart`.
2. Add migration transformations in `lib/src/data/ledger_codec.dart` to upgrade older documents upon deserialization.
3. Keep `pwa/src/lib/ledgerCodec.ts` and `firebase/firestore.rules` synchronized.
4. Backwards compatibility tests must be added to `test/ledger_persistence_test.dart` and `test/backup_restore_and_downgrade_guard_test.dart`.
