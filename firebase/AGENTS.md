# `firebase/` — Cloud Firestore Security Rules & Automated Tests

## 🎯 Role & Overview
Defines server-side Cloud Firestore security rules (`firestore.rules`) and automated security test suites (`rules.test.mjs`) ensuring user data isolation, payload validation, and access control.

---

## 📜 Key Files

- **`firestore.rules`**:
  - Declarative security rules for `users/{uid}`.
  - Enforces that only the authenticated user matching `request.auth.uid == uid` can read or write their ledger document.
  - Validates document schemas, field sizes, and schema versions to prevent corrupted or malicious payloads from being saved.
- **`rules.test.mjs`**:
  - Test suite using `@firebase/rules-unit-testing` simulating unauthorized access, cross-user reads/writes, malformed payloads, and valid sync flows against the Firebase Local Emulator Suite.

---

## 🛡️ Critical Invariants & Architecture

1. **Strict User Isolation**:
   - No user may read, list, or write another user's `users/{uid}` document under any condition.
2. **Schema Invariant Enforcement**:
   - Write operations must ensure required metadata fields (`schemaVersion`, `updatedAt`, `data`) exist and do not exceed Firestore's 1MB single document limit.

---

## 🧪 Testing and Verification

Run the Firestore rules emulator tests:
```bash
cd firebase
npm test
```
*(Requires Firebase CLI and local emulator suite).*
