# `lib/` — Flutter Application Root

## 🎯 Role & Overview
The `lib/` directory is the root of the Flutter mobile, desktop, and web application for 1Wallet. It contains the application entry point (`main.dart`) and the entire structured source tree under `src/`.

---

## 🏗️ Architecture & Organization

```
lib/
├── main.dart             # Application entrypoint: initialization, error boundaries, runApp
└── src/
    ├── app/              # OneWalletApp root widget, lifecycle and theme wiring
    ├── auth/             # Authentication controller, session state, and persisted app mode (online/offline)
    ├── capture/          # Core message, SMS, and receipt capture parsing pipeline
    ├── cloud_sync/       # Offline-first Firestore sync engine and write guards
    ├── config/           # Environment and Firebase configurations
    ├── data/             # Ledger state models, serialization codecs, and providers
    ├── design/           # Design tokens, color schemes, and styling constants
    ├── features/         # Screen-level feature modules (accounts, transactions, home, etc.)
    ├── imports/          # Statement parsing engines (PDF, CSV)
    ├── ledger/           # Pure ledger selectors, derived aggregations, and balances
    ├── offline_mode/     # Offline-only mode entry and offline → Google upgrade coordinator
    ├── routing/          # GoRouter definitions and route protection
    ├── security/         # App lock, biometric auth, and gate widgets
    ├── services/         # Background services and notification dispatchers
    ├── startup/          # Cold start state hydration and warmup
    ├── theme/            # Theme controller and dynamic M3 palettes
    ├── utils/            # Utilities (cryptography, currency math, formatting)
    └── widgets/          # Reusable shared UI components and navigation chrome
```

---

## 📜 Key Files

- **`lib/main.dart`**:
  - Initializes Flutter bindings (`WidgetsFlutterBinding.ensureInitialized()`).
  - Sets up error handling (`FlutterError.onError`, `PlatformDispatcher.instance.onError`).
  - Loads environment variables via `flutter_dotenv`.
  - Wraps the application in `ProviderScope` and runs `OneWalletApp`.

---

## 💡 LLM & Developer Operating Guidelines

1. **Do Not Pollute `lib/` Root**:
   - Only `main.dart` belongs at the root of `lib/`. All new models, widgets, services, and features must be placed in their appropriate subdirectory under `lib/src/`.
2. **State Management**:
   - Use Riverpod (`flutter_riverpod`). State should reside in providers, not within StatefulWidget state, unless the state is purely transient UI state (e.g. text input focus or scroll position).
3. **Immutability**:
   - Treat all domain models as immutable. Use `.copyWith(...)` patterns.
4. **Formatting & Lints**:
   - Adhere to `analysis_options.yaml`. Never disable lints without explicit architectural reasoning.
