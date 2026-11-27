# 1Wallet — Master Repository Architecture & LLM Operating Guide

Welcome to the **1Wallet** repository. This document serves as the master guide and architectural reference for AI agents, LLMs, and human engineers navigating and contributing to this codebase.

---

## 🧭 Repository Overview & Mission

**1Wallet** is an offline-first, privacy-focused, cross-platform personal finance application built with Flutter, paired with a companion PWA (React + Vite) and Firebase backend services.

The system is designed around:
1. **Deterministic double-entry / ledger integrity**: Transactions, multi-currency conversions, and account balances are mathematically consistent, immutable, and strictly validated.
2. **Offline-First Resilience**: Full operational capability without network connection. Local state persists using encrypted/safe local stores, with optimistic background synchronization to Firebase Firestore when connectivity resumes.
3. **End-to-End Privacy & Local Security**: Biometric app locks, PIN protections, AES-256 encrypted local backups, and minimal server-side reliance.
4. **Intelligent Ingestion Pipeline**: On-device Google ML Kit OCR for receipts, Android SMS spooling for transaction alerts, and robust statement parsers (PDF, CSV).

---

## 🏛️ System Architecture & Technology Stack

| Layer | Technologies & Libraries |
| :--- | :--- |
| **Mobile & Desktop Core** | Flutter 3.x, Dart 3.x, Material 3, `liquid_glass_widgets` |
| **State Management** | `flutter_riverpod` (v2.6.1+), StateNotifier, Providers |
| **Routing & Deep Linking** | `go_router` (v17.3.0+) |
| **Local Persistence & Security** | `shared_preferences`, `flutter_secure_storage`, `encrypt` (AES-256-GCM / PBKDF2), `crypto` |
| **Cloud Synchronization** | Firebase Auth (`firebase_auth`), Cloud Firestore (`cloud_firestore`) |
| **Ingestion & ML** | `google_mlkit_text_recognition`, `file_picker`, `syncfusion_flutter_pdf` |
| **Charts & Visuals** | `fl_chart`, `dynamic_color`, custom glassmorphism design tokens |
| **Companion Web PWA** | React 19, TypeScript, Vite, Tailwind CSS, Firebase SDK |
| **Testing Harness** | `flutter_test`, custom test fixtures, golden tests |

---

## 📁 Repository Directory Map & AGENTS.md Index

Every functional directory in this codebase maintains its own dedicated `AGENTS.md` file describing its exact responsibilities, invariants, and modification checklists:

| Path | Purpose & Domain | Dedicated Guide |
| :--- | :--- | :--- |
| `lib/` | Core Flutter source code | [lib/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/AGENTS.md) |
| `lib/src/app/` | App bootstrap, root widget, multi-theme wiring | [app/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/app/AGENTS.md) |
| `lib/src/auth/` | Authentication controller & user session state | [auth/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/auth/AGENTS.md) |
| `lib/src/capture/` | SMS & notification parsing pipeline, regex engines | [capture/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/capture/AGENTS.md) |
| `lib/src/cloud_sync/` | Offline-first sync engine, write guards, conflict resolution | [cloud_sync/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/cloud_sync/AGENTS.md) |
| `lib/src/config/` | Environment variables, Firebase setup | [config/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/config/AGENTS.md) |
| `lib/src/data/` | Ledger models, codecs, providers, JSON serialization | [data/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/data/AGENTS.md) |
| `lib/src/design/` | Design tokens, typography, glass styling | [design/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/design/AGENTS.md) |
| `lib/src/features/` | Feature screen modules & UI domains | [features/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/features/AGENTS.md) |
| `lib/src/imports/` | PDF statement extraction, CSV parser | [imports/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/imports/AGENTS.md) |
| `lib/src/ledger/` | Derived selectors, balance aggregation, net worth | [ledger/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/ledger/AGENTS.md) |
| `lib/src/offline_mode/` | Offline-only mode entry & offline → Google upgrade coordination | [offline_mode/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/offline_mode/AGENTS.md) |
| `lib/src/routing/` | GoRouter declarative routes, redirect guards | [routing/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/routing/AGENTS.md) |
| `lib/src/security/` | Biometric authentication, PIN lock gate | [security/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/security/AGENTS.md) |
| `lib/src/services/` | Local notifications & device background services | [services/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/services/AGENTS.md) |
| `lib/src/startup/` | Warmup orchestration & initial state hydration | [startup/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/startup/AGENTS.md) |
| `lib/src/theme/` | Theme controller, Material 3 color palettes | [theme/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/theme/AGENTS.md) |
| `lib/src/utils/` | Security key store, currency math, formatting | [utils/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/utils/AGENTS.md) |
| `lib/src/widgets/` | Reusable UI widgets, navigation chrome, dialogs | [widgets/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/widgets/AGENTS.md) |
| `web/prototype/` | Screen Studio: the real app rendered in the browser at phone sizes for visual testing | [web/prototype/README.md](file:///c:/Users/Joel/Documents/Github/1wallet/web/prototype/README.md) |
| `pwa/` | Web companion Progressive Web App (React + TS) | [pwa/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/pwa/AGENTS.md) |
| `firebase/` | Firestore security rules & automated rules tests | [firebase/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/firebase/AGENTS.md) |
| `scripts/` | Release manifest & update publishing scripts | [scripts/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/scripts/AGENTS.md) |
| `test/` | Unit, widget, and integration test suite | [test/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/test/AGENTS.md) |
| `android/`, `ios/`, `web/`, etc. | Native platform runners & configuration | [android/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/android/AGENTS.md), [ios/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/ios/AGENTS.md), [web/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/web/AGENTS.md) |

---

## ⚠️ Critical Engineering Invariants for LLMs

When modifying any part of this repository, you must observe these strict system invariants:

1. **Integer Minor Units for Money**:
   - Never represent financial currency amounts as floating point numbers (`double`).
   - All monetary calculations are performed in minor units (`amountMinor` as an integer: cents, pence, paise).
   - Use `Money` struct (`amountMinor`, `currency`) and format via `formatMoney()` or `NumberFormatter`.

2. **Immutable Ledger Operations**:
   - `LedgerState` is an immutable data class. Updates must happen via `LedgerController` copy methods or reducers.
   - Every mutation must preserve or appropriately update `unsyncedChanges` flag to trigger `CloudSyncController`.

3. **Multi-Currency Balancing**:
   - An account has a base `currency`. Transactions can occur in foreign currencies, but transfer pairs must maintain consistent exchange rates and balance adjustments.

4. **Biometric & Lock Invariant**:
   - The app lock gate (`AppLockGate`) wraps the entire navigation tree. No authenticated view must leak data before authentication completes when lock is enabled.

5. **No Network Operations on the UI Thread**:
   - All disk I/O, encryption, and network operations must run asynchronously and gracefully handle failures/retries.

6. **Mandatory Changelog & Automated Release Notes**:
   - Every commit and modification affecting user-facing behavior, architecture, UI, or capabilities must maintain a changelog entry.
   - For every release version bump, update `kBuiltInReleaseHistory` in `lib/src/features/updates/app_update_provider.dart` with structured `newFeatures`, `bugFixes`, and `notes`.
   - Every deployment pipeline automatically packages and publishes localized release notes (`whatsNewDirectory`) to Google Play Store and Fastlane metadata (`distribution/whatsnew/whatsnew-en-US` and `android/fastlane/metadata/android/en-US/changelogs/`).
   - Releases must never be published without release notes.

7. **Visual Verification for Every UI Change**:
   - Any change to screens, widgets, design tokens, themes, layout or user-visible behaviour must be checked in **Screen Studio** (`web/prototype/`) before the task is done. Passing `flutter test` alone is not enough.
   - Keep Screen Studio running during UI development and rebuild after the final edit. Check each touched screen at 390, 360 and 320 widths, in AMOLED and Light, with the sample and empty wallets.
   - Keep Screen Studio complete: register new routes in `web/prototype/studio.js` and add fictitious sample data for new scenarios in `lib/src/app/prototype_sample.dart`.

---

## 🧪 Testing and Verification Protocol

Before finishing any task, run the test suite to ensure no regressions:
```bash
# Run all Flutter unit and widget tests
flutter test

# Run a specific feature test
flutter test test/<test_file_name>_test.dart

# Run Firebase security rules tests
cd firebase && npm test
```

Before finishing any task, complete every step that applies:

1. **Static checks:** `flutter analyze` must report no issues. Run `dart format` on changed Dart files.
2. **Focused tests:** run the test files that cover the changed code, and add tests for new behaviour or fixed bugs.
3. **Shared UI tests:** for any UI change, also run `test/ui_route_matrix_test.dart`, `test/ui_design_system_guard_test.dart` and `test/app_kit_helpers_test.dart`.
4. **Visual verification in Screen Studio (required for UI changes):**
   ```powershell
   .\scripts\build-prototype.ps1      # rebuild after your final edit
   node scripts\serve-prototype.mjs   # reuse it if http://127.0.0.1:4173 already responds
   ```
   - Open every changed screen and every screen that uses a changed shared widget.
   - Check 390, 360 and 320 widths, AMOLED and Light, and the sample and empty wallets.
   - Scroll to the bottom, open the affected dialogs and sheets, and tap through the flow.
   - Look for overflow, clipped or wrapped labels, misalignment, uneven spacing and regressions on neighbouring screens.
   - The full checklist is in [web/prototype/README.md](file:///c:/Users/Joel/Documents/Github/1wallet/web/prototype/README.md).
5. **Close the loop:** for every visual bug, write a widget test that fails because of it, fix the bug, then rebuild and check again.
6. **Full suite** before a release or a broad change: `flutter test`. Report failures that existed before your change instead of hiding them.
7. **Evidence:** report each command run with its result, and the screens, sizes, themes and wallet states checked visually.
