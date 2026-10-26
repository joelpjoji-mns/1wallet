# `pwa/src/lib/` — PWA Core Logic, Codecs & Sync Guards

## 🎯 Role & Overview
Houses domain logic for the PWA client, matching the Flutter app's ledger codecs, sync write guards, race prevention, and balance selectors.

---

## 📜 Key Files

| File | Responsibilities |
| :--- | :--- |
| `ledgerTypes.ts` | TypeScript interfaces for `LedgerState`, `TransactionRecord`, `Account`, `Category`, `FutureGenerationRule`, and `Money`. |
| `ledgerCodec.dart` / `ledgerCodec.ts` | Encodes/decodes JSON payloads and decompresses gzip/pako payloads from Firestore `users/{uid}`. |
| `ledgerSelectors.ts` | Calculates account balances, net worth, and flow totals. |
| `pendingSaveGuard.ts` & `walletSyncGuards.ts` | Concurrency and race guards preventing multi-tab write collisions and stale snapshots. |
| `firestore.ts` & `walletSync.ts` | Cloud Firestore document listeners and atomic writer functions. |
| `money.ts` | Formatting and arithmetic utilities for integer minor currency units. |

---

## 🛡️ Critical Invariants & Architecture

1. **Parity with Dart Codec**:
   - `ledgerCodec.ts` must exactly mirror `lib/src/data/ledger_codec.dart`. Any schema evolution must be synchronized between both codebases.
2. **Race Guard Verification**:
   - Outdated local saves are aborted if a newer cloud revision is detected.

---

## 🧪 Testing and Verification

Run library tests with Node.js built-in test runner:
```bash
node --test src/lib/*.test.ts
```
