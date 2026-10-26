---
name: 1wallet-test-runner
description: >-
  Standard procedures for running and creating Flutter tests in 1Wallet.
  Use when validating changes, authoring new tests, or investigating failures.
---

# 1Wallet Test Runner Skill

## Key Test Conventions

1. **Test Harness**:
   - Always wrap test widgets with `ProviderScope` and appropriate overrides when testing Riverpod-connected screens.
   - Use `test/test_harness.dart` and `test/test_prefs.dart` for deterministic `SharedPreferences` and authentication mocks.

2. **Common Commands**:
   - Full test run:
     ```bash
     flutter test
     ```
   - Run a single test file:
     ```bash
     flutter test test/ledger_persistence_test.dart
     ```
   - Filter by test description:
     ```bash
     flutter test --name "opening balance"
     ```

3. **Gotchas**:
   - Ensure `LedgerProvidersConfig.disableAutoBackup = true` in tests where filesystem or periodic backup timers would leak across test boundaries.
   - For tests involving `fl_chart` or animations, pump sufficient frames (`tester.pumpAndSettle()`).
