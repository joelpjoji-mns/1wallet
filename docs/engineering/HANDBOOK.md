# 1Wallet Engineering Handbook

Welcome to the **1Wallet Engineering Handbook**. This document serves as the primary technical onboarding guide and architectural reference for engineering at 1Wallet.

---

## 🧭 Mission & Product Philosophy

1Wallet is a personal finance system engineered around:
1. **Financial Integrity**: Mathematical consistency via integer minor units (`amountMinor`). Floating-point arithmetic is strictly forbidden.
2. **Offline-First Resilience**: The user owns their data. The app operates with complete autonomy offline, writing only to secure local stores.
3. **Privacy by Design**: Telemetry, logs, and crash reports never receive monetary figures, account identifiers, or transaction notes.
4. **Transparent Releases**: Cryptographically verified build artifacts, reproducible builds, and automated semantic versioning.

---

## 🏛️ System Architecture

### Layered Separation of Concerns
1. **Presentation / UI (`lib/src/features/`, `lib/src/widgets/`)**:
   - Flutter widgets built with Material 3 and Liquid Glass styling tokens.
   - Declarative routing via `GoRouter` (`lib/src/routing/app_router.dart`).
   - UI components read state via memoized selectors and Riverpod providers; they never write directly to SQLite, SharedPreferences, or Firestore.
2. **State Management (`lib/src/data/`, Riverpod)**:
   - State resides in immutable data classes (`LedgerState`, `AuthState`, `CloudSyncState`).
   - Mutations are initiated strictly via StateNotifier methods on `ledgerProvider.notifier` or `authProvider.notifier`.
3. **Persistence & Cryptography (`lib/src/data/`, `lib/src/utils/`)**:
   - Encrypted local store using AES-256-GCM with keys derived from user passwords/biometrics via PBKDF2 (`secure_key_store.dart`).
   - Codec serialization (`ledger_codec.dart`) guarantees backwards-compatible deserialization for legacy backups.
4. **Cloud Synchronization (`lib/src/cloud_sync/`)**:
   - Offline-first background synchronization to Firebase Firestore (`users/{uid}`).
   - Conditional write guard (`CloudSyncWriteGuard`) compares remote revisions before committing to prevent clobbering.
   - In offline mode, the sync phase remains permanently `disabled`.
5. **Observability Façade (`lib/src/observability/`)**:
   - Structured logger (`AppLogger`) with automatic regex PII redaction.
   - Error reporting (`CrashReporter`) with hashed user identifiers.
   - Performance budget tracker (`PerfTracer`).
   - Privacy-respecting opt-in analytics (`AnalyticsService`).

---

## 🧪 Testing Pyramid & Quality Assurance

All features must be tested according to the 5-tier testing pyramid:

| Tier | Category | Scope | Command |
| :--- | :--- | :--- | :--- |
| **1** | Unit Tests | Integer money arithmetic, codec roundtrips, SMS parsers | `flutter test test/ledger_*_test.dart` |
| **2** | Widget & UI Matrix | Route matrix, responsive phone/tablet, design system guard | `flutter test test/ui_route_matrix_test.dart` |
| **3** | BDD Executable Specs | Business-readable `.feature` files for offline & money flows | `flutter test test/bdd_suite_test.dart` |
| **4** | Accessibility (a11y) | Automated WCAG contrast & tap target guidelines | `flutter test test/accessibility/` |
| **5** | E2E & Perf Timeline | Frame rasterization benchmark, startup budgets | `flutter test integration_test/` |

---

## 🔒 Security & Invariant Protocols

### Invariant 1: Integer Minor Units
```dart
// CORRECT: Integer minor units
const amount = Money(amountMinor: 25000, currency: 'USD'); // $250.00

// STRICTLY FORBIDDEN: Floating-point money
double balance = 250.00; // NEVER DO THIS
```

### Invariant 2: Zero Financial Data in Telemetry
```dart
// CORRECT: Redacted structured log
AppLogger.info('Sync', 'Ledger commit complete', metadata: {'operation': 'push'});

// STRICTLY FORBIDDEN: Logging monetary amounts or balances
print('User spent $amount'); // NEVER DO THIS
```

### Invariant 3: Offline Write Guard
Offline mode requires `cloudWritesAllowed(...) == false`. Under no circumstances should a network call to `cloud_firestore` be reachable when `AuthState.user == null`.

---

## 📦 Monorepo & Package Structure (Melos)

The project uses Melos to orchestrate packages:
- `.` (Root Flutter Application)
- `pwa/` (React 19 + TypeScript companion web app)
- `packages/one_wallet_money` (Standalone integer money arithmetic package)
- `packages/one_wallet_design_system` (Extracted design tokens and components)

Use `make help` or `melos run <script>` for common operations.
