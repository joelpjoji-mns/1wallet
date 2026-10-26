# `lib/src/app/` — Application Root & Lifecycle

## 🎯 Role & Overview
This directory contains the root widget of the Flutter application (`OneWalletApp`). It coordinates top-level application infrastructure, including MaterialApp initialization, GoRouter configuration, Material 3 theming with dynamic colors, and security gate wrapping.

---

## 📜 Key Files

- **`one_wallet_app.dart`**:
  - The root `ConsumerWidget` or `ConsumerStatefulWidget` for the Flutter app.
  - Subscribes to `themeControllerProvider` to apply light/dark/system themes, accent colors, and dynamic Android 12+ palette adaptations.
  - Binds `appRouterProvider` to `MaterialApp.router`.
  - Integrates `AppLockGate` to ensure unauthorized access is blocked when biometric/PIN lock is active.
  - Configures app-wide localization delegates (`GlobalMaterialLocalizations`, etc.).

---

## 🛡️ Critical Invariants & Architecture

1. **Security Gate Positioning**:
   - `AppLockGate` must wrap the router content or reside at the root level of the widget hierarchy so that unauthorized users cannot inspect sensitive financial screens or widget trees.
2. **Dynamic Colors**:
   - Dynamic colors via `DynamicColorBuilder` should provide a fallback scheme (`lightColorScheme`, `darkColorScheme`) based on user-selected accent color tokens when dynamic theming is unavailable.
3. **No Direct Business Logic**:
   - Do not add financial calculations or ledger mutations to this directory.

---

## 🔍 LLM / Developer Checklist

- [ ] When modifying `one_wallet_app.dart`, verify that theme switching between light, dark, and system modes works smoothly without rebuilding unnecessary subtrees.
- [ ] Ensure that `AppLockGate` is not bypassed or conditionally omitted in release mode.
- [ ] Confirm router transitions do not cause flickering or flashes of unauthenticated content.
