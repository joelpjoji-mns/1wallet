# `lib/src/features/onboarding/` — First-Run Onboarding Flow

## 🎯 Role & Overview
Guides new users through their first launch: setting their base currency, creating initial accounts (e.g. Primary Bank, Cash), seeding standard categories, and optionally enabling cloud sync or biometric lock.

---

## 📜 Key Files

- **`onboarding_screen.dart`**: Multi-step wizard UI with fluid page indicator and card transitions. Uses `AuthState.ownerId`, so it also creates the offline (`'local-user'`) wallet. Offline, the display name is stored on the device (`AuthController.setLocalDisplayName`) and no cloud upload is attempted.
- **`onboarding_controller.dart`**: State notifier holding temporary user selections before atomic initialization into `LedgerController`. Completion is keyed by owner id. `copyCompletion` carries it over on an offline → Google upgrade.

---

## 🛡️ Critical Invariants & Architecture

1. **Atomic Ledger Initialization**:
   - Creating initial accounts, default categories, and preferences must be applied atomically so the wallet is never left in an uninitialized corrupt state.
2. **Flag Persistence**:
   - `hasCompletedOnboarding` flag in `SharedPreferences` must only be set to `true` after initial setup finishes successfully.

---

## 🔍 LLM / Developer Checklist

- [ ] Run `test/onboarding_review_accounts_test.dart` and `test/cloud_wallet_onboarding_safety_test.dart`.
- [ ] Ensure back button on Android during onboarding behaves predictably without jumping to unauthenticated routes.
