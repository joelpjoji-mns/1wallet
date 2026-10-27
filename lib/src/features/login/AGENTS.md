# `lib/src/features/login/` — Entry Screen: Google Sign-In or Offline Mode

## 🎯 Role & Overview
The signed-out entry screen. Users either sign in with Google (cloud backup & sync) or choose **"Use without an account (Offline)"**. Offline mode keeps the whole wallet on this device with no Google account, no Firebase user and no cloud sync.

---

## 📜 Key Files

- **`login_screen.dart`**: Frosted (`BrandFrostedPanel`) card with the "Continue with Google" button and inline error feedback. Below it is the offline entry button (`LoginScreen.offlineButtonKey`).
- **`offline_mode_sheet.dart`**: `showOfflineModeSheet` / `OfflineModeSheet` explain offline mode:
  - Data stays only on this device.
  - There is no cloud backup.
  - The user owns their encrypted backups.
  - They can upgrade to Google later.
  - Data is unrecoverable without a backup.

  "Continue offline" stays disabled until the user ticks the acknowledgement (`OfflineModeSheet.acknowledgeKey` / `confirmKey`). It then calls `OfflineModeController.enterOfflineMode()`.

---

## 🛡️ Critical Invariants & Architecture

1. **Offline mode is always available**:
   - Users are never forced to create a cloud account. The offline option must work even when Google sign-in or Firebase is unavailable or unconfigured.
2. **Explicit, informed consent**:
   - Never switch to offline mode without the acknowledgement. Never open a stored wallet that belongs to a Google account offline: show the `walletBelongsToAccount` guidance instead.
3. **Loading & Error Feedback**:
   - Network errors and cancelled Google sign-ins present clean inline feedback without blocking the UI.

---

## 🔍 LLM / Developer Checklist

- [ ] Run `test/login_offline_option_test.dart`.
- [ ] Keep both entry paths styled with the brand/glass components (`brand_widgets.dart`, design tokens).
