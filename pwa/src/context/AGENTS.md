# `pwa/src/context/` — PWA React Contexts & State

## 🎯 Role & Overview
Provides global React contexts managing user authentication and real-time ledger data persistence.

---

## 📜 Key Files

- **`AuthContext.tsx`**:
  - Provides `useAuth()` hook tracking current Firebase Auth user, Google Sign-In, and sign-out routines.
- **`WalletDataContext.tsx`**:
  - Provides `useWalletData()` hook exposing `ledgerState`, CRUD functions (`addRecord`, `deleteRecord`, `updateRecord`, `addAccount`, etc.), sync status, and save operations.

---

## 🛡️ Critical Invariants & Architecture

1. **User UID Boundary**:
   - When `user.uid` switches, `WalletDataContext` unbinds existing listeners and resets state immediately.
2. **Optimistic Updates & Conflict Prevention**:
   - State updates locally in memory immediately while `walletSync.ts` pushes changes to Firestore.

---

## 🔍 LLM / Developer Checklist

- [ ] Check `src/lib/uidSwitchGuard.test.ts` and `src/lib/uidSwitchRender.test.ts`.
- [ ] Confirm context hooks throw helpful runtime errors if used outside their respective providers.
