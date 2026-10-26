# `test/` — Flutter Test Suite & Quality Assurance

## 🎯 Role & Overview
Contains unit tests, widget tests, integration flows, and test fixtures for the 1Wallet Flutter application. Ensures zero regressions across financial balance math, state persistence, cloud write guards, and navigation.

---

## 🏗️ Organization & Key Helpers

- **`flutter_test_config.dart`**: Test runner configuration, font loading for golden tests, and test environment setup.
- **`test_harness.dart`**: Boilerplate test harness providing mocked Riverpod containers, Fake authentication users, and standard screen test wrappers.
- **`test_prefs.dart` & `test_sp.dart`**: In-memory `SharedPreferences` mocks for deterministic testing without disk I/O.
- **`fixtures/`**: Sample bank SMS messages, mock PDF statements, and sample CSV export files.

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
