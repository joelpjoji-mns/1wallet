# `pwa/src/` — PWA Application Source

## 🎯 Role & Overview
Houses all TypeScript/React source code for the PWA client, organized into components, contexts, libraries, and page routes.

---

## 🗂️ Directory Sub-modules

- **`components/`**: Interactive modal dialogs for creating/editing transactions and accounts.
- **`context/`**: React contexts providing authentication state (`AuthContext`) and synchronized ledger state (`WalletDataContext`).
- **`lib/`**: Domain types, codecs, Firestore adapter, and sync guards.
- **`pages/`**: Top-level views corresponding to navigation routes.

---

## 🛡️ Critical Invariants & Architecture

1. **Context Hierarchy**:
   - `AuthProvider` wraps `WalletDataProvider`. `WalletDataProvider` resets when `user.uid` changes to guarantee strict user isolation.
2. **Immutable State Transitions**:
   - State updates in `WalletDataContext` must treat ledger state immutably, triggering atomic Firestore syncs with pending write guards.

---

## 🔍 LLM / Developer Checklist

- [ ] Ensure any newly added React components or hooks adhere to React 19 standards.
- [ ] Verify that `npm test` passes in `pwa/` after any changes in `src/`.
