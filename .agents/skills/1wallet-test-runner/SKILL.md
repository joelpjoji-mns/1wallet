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

4. **Visual Verification (required for every UI change)**:
   - Build and serve Screen Studio, the real app in the browser with sample data:
     ```powershell
     .\scripts\build-prototype.ps1      # rebuild after the final edit
     node scripts\serve-prototype.mjs   # http://127.0.0.1:4173; reuse if already running
     ```
   - Open each changed screen and the screens that share a changed widget. Check 390, 360 and 320 widths, AMOLED and Light, and the sample and empty wallets.
   - Scroll to the bottom, open the affected dialogs and sheets, and tap through the flow.
   - Look for overflow, clipped or two-line button labels, orphaned buttons, misaligned amounts and dates, uneven spacing, and regressions on neighbouring screens.
   - Turn each visual bug into a widget test that fails before the fix, then rebuild and check again.
   - Add new routes to `web/prototype/studio.js`. New scenarios need fictitious data in `lib/src/app/prototype_sample.dart`; keep `test/prototype_runtime_test.dart` passing.
   - Full checklist and Playwright tips: `web/prototype/README.md`.

5. **Before Finishing**:
   - `flutter analyze` is clean and the focused tests pass.
   - UI changes also pass `test/ui_route_matrix_test.dart` and `test/ui_design_system_guard_test.dart`.
   - The visual pass is recorded: screens, sizes, themes and wallet states.
