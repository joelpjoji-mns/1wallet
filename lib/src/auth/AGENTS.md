# `lib/src/auth/` — Authentication, Session & App Mode

## 🎯 Role & Overview
This directory manages the session: Google Sign-In via Firebase Auth (plus QA-only email/password), and the device-scoped **app mode** that lets a user run 1Wallet fully offline with no account. It isolates authentication logic from financial ledger state while keeping lifecycle transitions clean.

---

## 📜 Key Files

- **`app_mode.dart`**:
  - `AppMode { online, offline }` persisted in `shared_preferences` (`one_wallet.app_mode.v1`) by `AppModeStore` / `appModeStoreProvider`. A missing value means `online`, so devices that predate offline mode keep their behaviour.
  - `localOwnerId` (`'local-user'`): the owner id of an offline wallet (the long-standing ledger sentinel).
  - Optional offline display name (`one_wallet.app_mode.local_name.v1`).
- **`auth_user.dart`**:
  - `AuthUser` (`id`, `email`, `displayName`, `photoUrl`, `provider`). `AuthUser.local()` is the synthetic offline identity used only for profile UI. It is never published as `AuthState.user`.
- **`auth_controller.dart`**:
  - `AuthPhase { initializing, signedOut, signedIn, unavailable, localOnly }`. `localOnly` is offline mode.
  - `AuthState`: `isAuthenticated` (a Firebase user), `isLocalOnly`, `ownerId` (uid or `'local-user'`), `profileUser`, `localOwnershipVerified`. `appModeProvider` is derived from it.
  - `AuthController`:
    - Reads `AppMode` synchronously at construction. Offline starts `localOnly` immediately, with no network and no Firebase dependency.
    - Online behaviour (Google sign-in, QA email/password, sign-out, re-authentication for backend-managed erasure) is unchanged.
    - Offline APIs: `continueOffline()`, `signInWithGoogleForUpgrade()` (signs in **without publishing**), `completeOfflineUpgrade()`, `discardUpgradeSession()`, `verifyLocalOwnership()`, `retryLocalOwnershipCheck()`, `setLocalDisplayName()`.
    - It must not delete Firebase credentials directly; the backend deletion job owns that final step.

---

## 🛡️ Critical Invariants & Architecture

1. **User Scoping & Isolation**:
   - When a user logs out or switches accounts, `LedgerController` must be notified to reset or reload the corresponding ledger repository. Never allow one user's transactions to leak into another's session.
2. **Offline mode keeps Firebase Auth untouched**:
   - No anonymous Firebase account is ever created. In `localOnly`, `AuthState.user` is always `null`, which keeps every cloud-sync, Firestore and account-deletion path (all keyed off `user`) unreachable.
   - `signInWithGoogle()` and `signOut()` are no-ops in `localOnly`: upgrades go through `OfflineModeController` (`lib/src/offline_mode/`), and "signing out" would strand the device-only wallet.
   - Offline mode may only open a `'local-user'` wallet. `verifyLocalOwnership` finishes an interrupted upgrade, or returns the device to sign-in when the stored wallet belongs to a Google account.
3. **No Direct Firestore Queries Here**:
   - `auth/` is strictly for authentication and session mode. Firestore synchronization logic belongs in `lib/src/cloud_sync/`.

---

## 🔍 LLM / Developer Checklist

- [ ] Keep the online code path behaviour-identical when changing offline logic; existing users default to `AppMode.online`.
- [ ] Persist `AppMode.online` before publishing an upgraded Google user (`completeOfflineUpgrade`).
- [ ] Ensure sign-out cleans up sensitive local tokens and clears in-memory keys where necessary.
- [ ] Check that `authControllerProvider` changes re-evaluate `startupStateProvider` / `appRouterProvider`.
- [ ] Run `test/offline_mode_startup_test.dart` and `test/offline_upgrade_migration_test.dart`.
