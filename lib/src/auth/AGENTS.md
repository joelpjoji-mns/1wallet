# `lib/src/auth/` — Authentication & Session Management

## 🎯 Role & Overview
This directory manages user authentication state, supporting anonymous/guest mode, email/password, and Google Sign-In via Firebase Auth. It isolates authentication logic from financial ledger state while maintaining clean lifecycle transitions.

---

## 📜 Key Files

- **`auth_user.dart`**:
  - Domain representation of the authenticated user (`AuthUser`), storing `uid`, `email`, `displayName`, `photoUrl`, and `isAnonymous`.
- **`auth_controller.dart`**:
  - `AuthController`: A `StateNotifier<AuthState>` tracking whether the user is authenticated, unauthenticated, or in an error/loading state.
  - Listens to Firebase Auth stream (`authStateChanges()`).
  - Exposes sign-in, sign-up, sign-out, guest login, and password reset methods.

---

## 🛡️ Critical Invariants & Architecture

1. **User Scoping & Isolation**:
   - When a user logs out or switches accounts, `LedgerController` must be notified to reset or reload the corresponding ledger repository. Never allow one user's transactions to leak into another's session.
2. **Offline & Guest Mode**:
   - 1Wallet supports local-only/guest usage. If no Firebase user is logged in, the app operates in local offline mode without throwing fatal auth exceptions.
3. **No Direct Firestore Queries Here**:
   - `auth/` is strictly for authentication. Firestore synchronization logic belongs in `lib/src/cloud_sync/`.

---

## 🔍 LLM / Developer Checklist

- [ ] When modifying `AuthController`, verify that `isAnonymous` transitions (e.g. upgrading an anonymous user to a permanent Google account) preserve local ledger data.
- [ ] Ensure sign-out cleans up sensitive local tokens and clears in-memory keys where necessary.
- [ ] Check that `authControllerProvider` notifies `appRouterProvider` to trigger route redirection if required.
