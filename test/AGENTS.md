# `test/` — Flutter Test Suite & Quality Assurance

## 🎯 Role & Overview
Contains unit tests, widget tests, BDD executable specifications, accessibility verifications, integration flows, and test fixtures for the 1Wallet Flutter application. Ensures zero regressions across financial balance math, state persistence, cloud write guards, and navigation.

---

## 🏛️ The 1Wallet Testing Pyramid

The testing strategy follows a 5-tier pyramid designed for rapid feedback and rigorous invariant verification:

| Layer | Purpose | Tooling / Files | Execution Command |
| :--- | :--- | :--- | :--- |
| **Tier 1: Unit & Domain** | Integer money arithmetic, ledger serialization, codecs, SMS parsers | `test/ledger_*_test.dart`, `test/sms_parser_test.dart` | `flutter test test/ledger_serialization_test.dart` |
| **Tier 2: Widget & UI Matrix** | Route rendering, responsive design, dark/light themes, design system guard | `test/ui_route_matrix_test.dart`, `test/ui_design_system_guard_test.dart` | `flutter test test/ui_route_matrix_test.dart` |
| **Tier 3: BDD / Executable Specs** | Business-readable `.feature` files for offline & money invariants | `test/bdd/features/*.feature`, `test/bdd_suite_test.dart` | `flutter test test/bdd_suite_test.dart` |
| **Tier 4: Accessibility (a11y)** | WCAG 2.1 AA tap target and contrast automated guidelines | `test/accessibility/*_test.dart` | `flutter test test/accessibility/` |
| **Tier 5: Integration / E2E & Perf** | End-to-end user flows, timeline tracing, jank detection, startup budgets | `integration_test/` | `flutter drive --no-dds --keep-app-running -d <disposable-device> --driver test_driver/integration_test.dart --target integration_test/perf_timeline_test.dart` |

Use only a disposable device for integration tests: Flutter may install or
uninstall the app and delete its local data. Always specify the device explicitly.
`flutter test` defaults to uninstalling unless `--no-uninstall` is passed;
`flutter drive` defaults to uninstalling unless `--keep-app-running` is passed.

### Visual verification (required for UI changes)

Automated tests are necessary but not sufficient for UI work. Every UI change
must also be checked visually in **Screen Studio**, the real Flutter app
rendered in the browser at phone sizes with sample data:

```powershell
.\scripts\build-prototype.ps1      # rebuild after the final edit
node scripts\serve-prototype.mjs   # http://127.0.0.1:4173 (reuse if already running)
```

Check each touched screen, and the screens that share a changed widget, at
390, 360 and 320 widths, in AMOLED and Light, with the sample and empty
wallets. Scroll through each screen, open its dialogs and sheets, and tap
through the flow. When the visual pass finds a bug, add a widget test that
reproduces it before fixing it. The full checklist and automation tips are in
`web/prototype/README.md`.

---

## 🏗️ Organization & Key Helpers

- **`flutter_test_config.dart`**: Test runner configuration, font loading for golden tests, and test environment setup.
- **`test_harness.dart`**: Boilerplate test harness providing mocked Riverpod containers, Fake authentication users, and standard screen test wrappers.
- **`test_prefs.dart` & `test_sp.dart`**: In-memory `SharedPreferences` mocks for deterministic testing without disk I/O.
- **`fixtures/`**: Sample bank SMS messages, mock PDF statements, and sample CSV export files.
- **`offline_mode_fakes.dart`**: `FakeAuthRepository` (scripted Google sign-in, no Firebase), `MemoryLedgerRepository` and `FakeUpgradeGateway` (Firestore stand-in for the offline → Google upgrade).
- **`bdd/`**: Behavior-driven development suite containing `.feature` files, Gherkin parsers, step definitions, and report generators.

### Offline mode coverage

| Test | Covers |
| :--- | :--- |
| `offline_mode_startup_test.dart` | Offline startup routing with no Firebase. Default online flow unchanged. Foreign/interrupted ownership. Cloud sync stays disabled and never reaches Firestore. |
| `offline_backup_roundtrip_test.dart` | Encrypted export → wipe → import, and local-owner re-ownership of imported backups. |
| `offline_upgrade_migration_test.dart` | Offline → Google migration: no cloud wallet, and keep local / keep cloud / merge / cancel / failure branches. Also `mergeLedgerStates`. |
| `login_offline_option_test.dart` | Offline entry button and acknowledgement gate. |
| `offline_mode_screens_test.dart` | Settings and Sync render the offline state through the real router. |
| `bdd_suite_test.dart` | Executable business specs verifying offline balance deductions and cloud sync write guard isolation. |

### Design-system & a11y coverage

| Test | Covers |
| :--- | :--- |
| `ui_route_matrix_test.dart` | Renders inventoried populated, empty-wallet, and gated routes across selected phone, landscape, tablet, theme, and text-scale variants. Scrolls available vertical viewports and checks rendered button labels; also samples dialogs, a keyboard, and offline consent. It filters the known `semantics.parentDataDirty` harness error and is not exhaustive interaction coverage. |
| `ui_design_system_guard_test.dart` | Lint-style guard: feature screens may not use raw radii, font sizes or families, hex/named colours, inline `SnackBar`s, raw bottom sheets, Material `Card`/`ListTile`/`Switch`/`AppBar`, or extra `Scaffold`s. |
| `app_kit_helpers_test.dart` | Canonical helpers: legacy-named `showAppSnackBar` now uses inline feedback with Undo, plus `showAppConfirmDialog`, `showAppSheet`, `AppLoadingState`, `EmptyState`, `AppGroupedSection`/`AppGroupedTile`. |
| `prototype_runtime_test.dart` | Screen Studio safety and coverage: prototype keys stay in memory, sample references resolve, the demo inbox covers every alert type, and gated UI opens without changing production startup. |
| `accessibility/a11y_guidelines_test.dart` | Automated WCAG contrast (`textContrastGuideline`) and tap target (`androidTapTargetGuideline`) audits. |

---

## 🥒 BDD & Executable Specifications

BDD scenarios reside in `test/bdd/features/` and are authored in business-readable Gherkin language:
```gherkin
Feature: Offline Wallet Transaction Management
  Scenario: Add expense in offline mode updates balance and triggers no cloud writes
    Given an offline wallet with 1000 minor units
    When I add a 250 expense for "Groceries"
    Then balance shows 750 minor units
    And no cloud write occurs
```

### Running BDD Specs and Generating Reports
```bash
# Execute the BDD suite
flutter test test/bdd_suite_test.dart

# View generated reports:
# - build/reports/bdd_summary.txt (Human-readable summary)
# - build/reports/bdd_report.json (Standard Cucumber/Gherkin JSON for CI artifact ingestion)
```

---

## 🛡️ Critical Invariants & Architecture

1. **Auto-Backup Disabling in Tests**:
   - Tests that initialize `LedgerController` must set `LedgerProvidersConfig.disableAutoBackup = true` to prevent periodic backup timers or file system writes from persisting across test cases.
2. **Deterministic Time**:
   - Tests involving recurring rules, relative timestamps, or calendar days should use explicit fixed `DateTime` instances rather than `DateTime.now()`.
3. **Integer Minor Units Invariant**:
   - Tests must assert exact integer amounts (`Money.amountMinor`). Never perform assertions with floating point numbers (`double`).
4. **Offline Isolation Invariant**:
   - Any test marked offline must verify `cloudWritesAllowed(...) == false` and assert zero calls to Firestore.

---

## 🧪 Running Tests Locally & in Container

### Local Execution
```bash
# Run the entire Flutter test suite
flutter test

# Run with test coverage
flutter test --coverage

# Run only the BDD executable specifications
flutter test test/bdd_suite_test.dart

# Run a specific unit test file
flutter test test/ledger_persistence_test.dart

# Run tests matching a specific pattern
flutter test --name "opening balance"
```

### Containerized Execution (Docker / Devcontainer)
```bash
# Run tests inside the pinned Linux devcontainer
docker run --rm -v "$(pwd)":/workspace -w /workspace ghcr.io/cirruslabs/flutter:3.47.7 \
  flutter test test/bdd_suite_test.dart

# Run full CI suite with coverage gate inside container
docker run --rm -v "$(pwd)":/workspace -w /workspace ghcr.io/cirruslabs/flutter:3.47.7 \
  bash -c "flutter pub get && flutter test --coverage"
```
