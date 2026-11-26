# `lib/src/features/onboarding/` — First-Run Onboarding Flow

## 🎯 Role & Overview
Fresh wallets complete the setup wizard with at least one account before reaching Home. An optional compact, anchored tour then teaches the real interface. Established wallets never receive automatic hints.

---

## 📜 Key Files

- **`onboarding_screen.dart`**: Multi-step wizard UI with fluid page indicator and card transitions. Uses `AuthState.ownerId`, so it also creates the offline (`'local-user'`) wallet. Offline, the display name is stored on the device (`AuthController.setLocalDisplayName`) and no cloud upload is attempted.
- **`onboarding_controller.dart`**: State notifier holding temporary user selections before atomic initialization into `LedgerController`. Completion is keyed by owner id. `copyCompletion` carries it over on an offline → Google upgrade.
- **`discovery_controller.dart`** and **`discovery_cloud_store.dart`**: Owner-scoped local progress and a separate Firestore document that transactionally merges introductory steps and dismissed hints. Replays stay device-local.
- **`discovery_overlay.dart`** and **`guided_editor_overlay.dart`**: Measured spotlights on Home and the real account and record editors.
- **`contextual_discovery_hint.dart`**: Dismissible inline guidance on feature screens.
- **`discovery_coach_mark.dart`**: Small measured coach marks, safe-area placement and reduced-motion-aware arrows; only the card intercepts input.
- **`discovery_feature_guides.dart`** and **`feature_discovery_guide.dart`**: Real-route workflow catalogue, per-route anchors, locally persisted positions and isolated samples. Samples must never mutate ledger state or hold real credentials.

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
- [ ] Existing wallets have no unsolicited welcome, hint or resume popup. Restarts require an explicit Settings resume; returning from a guided editor in the same session continues smoothly.
