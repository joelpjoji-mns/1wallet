# `test/` — Flutter Test Suite & Quality Assurance

## 🎯 Role & Overview
Contains unit tests, widget tests, integration flows, and test fixtures for the 1Wallet Flutter application. Ensures zero regressions across financial balance math, state persistence, cloud write guards, and navigation.

---

## 🏗️ Organization & Key Helpers

- **`flutter_test_config.dart`**: Test runner configuration, font loading for golden tests, and test environment setup.
- **`test_harness.dart`**: Boilerplate test harness providing mocked Riverpod containers, Fake authentication users, and standard screen test wrappers.
- **`test_prefs.dart` & `test_sp.dart`**: In-memory `SharedPreferences` mocks for deterministic testing without disk I/O.
- **`fixtures/`**: Sample bank SMS messages, mock PDF statements, and sample CSV export files.
- **`offline_mode_fakes.dart`**: `FakeAuthRepository` (scripted Google sign-in, no Firebase), `MemoryLedgerRepository` and `FakeUpgradeGateway` (Firestore stand-in for the offline → Google upgrade).

### Offline mode coverage

| Test | Covers |
| :--- | :--- |
| `offline_mode_startup_test.dart` | Offline startup routing with no Firebase. Default online flow unchanged. Foreign/interrupted ownership. Cloud sync stays disabled and never reaches Firestore. |
| `offline_backup_roundtrip_test.dart` | Encrypted export → wipe → import, and local-owner re-ownership of imported backups. |
| `offline_upgrade_migration_test.dart` | Offline → Google migration: no cloud wallet, and keep local / keep cloud / merge / cancel / failure branches. Also `mergeLedgerStates`. |
| `login_offline_option_test.dart` | Offline entry button and acknowledgement gate. |
| `offline_mode_screens_test.dart` | Settings and Sync render the offline state through the real router. |

### Design-system coverage

| Test | Covers |
| :--- | :--- |
| `ui_route_matrix_test.dart` | Renders every route (plus login/onboarding/permissions) in light and AMOLED dark, at 1.0× and 1.3× text, on a 360 dp phone and a tablet, with sample data and with an empty wallet. It loads the real Inter/Material Icons fonts and fails on any overflow or framework error, reporting the offending `lib/src` file:line. `--dart-define=UI_AUDIT_SHOTS=<dir>` (+ optional `UI_AUDIT_SHOTS_FILTER=slug[@variant],…`) also writes PNG screenshots, used by `doc/ui-audit.md`. |
| `ui_design_system_guard_test.dart` | Lint-style guard: feature screens may not use raw radii, font sizes or families, hex/named colours, inline `SnackBar`s, raw bottom sheets, Material `Card`/`ListTile`/`Switch`/`AppBar`, raw `GlassGroupedSection`/`GlassListTile`/`GlassButton`, or extra `Scaffold`s. All of `lib/src` must avoid `withAlpha(int)` and plain icon glyphs. Exceptions are allow-listed with reasons; a justified one-off uses `// ui-guard: allow <reason>`. |
| `app_kit_helpers_test.dart` | The canonical helpers: `showAppSnackBar`, `showAppConfirmDialog`, `showAppSheet`, `AppLoadingState`, the `EmptyState` danger tone, `AppGroupedSection`/`AppGroupedTile` (font and merged toggle semantics) and the `HeaderIconButton` tooltip. |

---

## 🛡️ Critical Invariants & Architecture

1. **Auto-Backup Disabling in Tests**:
   - Tests that initialize `LedgerController` must set `LedgerProvidersConfig.disableAutoBackup = true` to prevent periodic backup timers or file system writes from persisting across test cases.
2. **Deterministic Time**:
   - Tests involving recurring rules, relative timestamps, or calendar days should use explicit fixed `DateTime` instances rather than `DateTime.now()`.

---

## 🧪 Running Tests

```bash
# Run the entire test suite
flutter test

# Run a specific test file
flutter test test/ledger_persistence_test.dart

# Run tests matching a specific pattern
flutter test --name "opening balance"
```
