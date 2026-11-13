# ADR 0002: Testing Pyramid and End-to-End Testing Framework

## Status
Accepted

## Context
1Wallet requires a robust testing pyramid to safeguard ledger integrity, multi-currency conversions, and offline-first state synchronization. For higher-level integration and End-to-End (E2E) testing, three candidate frameworks were evaluated:

1. **Flutter `integration_test` (Official)**:
   - Built into the Flutter SDK.
   - Runs directly on device/emulator or headless desktop.
   - Seamlessly accesses Flutter test bindings, widget finders, and in-memory Riverpod overrides.
   - Does not interact with native OS dialogs (e.g. native biometric prompt, system permission dialog) out of the box.

2. **Patrol (LeanCode)**:
   - Extends `flutter_test` with native automation capabilities (taps system permission dialogs, biometric auth prompts).
   - Requires custom Gradle plugins, native test runners, and an external test orchestrator daemon.
   - Adds build complexity and maintenance overhead in CI containers.

3. **Maestro (mobile.dev)**:
   - Black-box UI automation using YAML flow definitions.
   - Operates entirely outside the Flutter runtime and cannot access in-memory fakes (`offline_mode_fakes.dart`, memory ledger repositories) or inspect Riverpod state.
   - Impractical for verifying database-level assertions (e.g., verifying that zero network packets or Firestore writes occurred).

## Decision
We select **Flutter `integration_test`** as our primary E2E and UI integration harness, complemented by mocked native adapters (`test_harness.dart` and `offline_mode_fakes.dart`):

1. **Deterministic State Control**: `integration_test` executes inside the Dart runtime, enabling injection of `MemoryLedgerRepository`, mock biometric providers, and in-memory Firebase instances. This allows tests to rigorously verify ledger state transitions and prove that zero Firestore writes occur in offline mode.
2. **Containerized Headless Execution**: Runs cleanly in containerized Linux CI runners without requiring heavyweight nested KVM emulators or external native runner daemons.
3. **Timeline & Performance Profiling**: Directly hooks into Flutter's `Timeline` API (`traceAction`) to capture frame rasterization times, UI jank, and startup benchmarks in `--profile` mode.
4. **Native Dialog Isolation**: Native OS permission and biometric dialogs are abstracted behind clean repository interfaces (`LocalAuthProvider`, `PermissionSetupController`), which are scriptable without depending on brittle native UI drivers.

## Consequences
- E2E tests run quickly and reliably in CI without emulator flakiness.
- Tests assert both UI presentation and internal ledger consistency.
- If native OS dialog testing is ever strictly necessary in physical lab environments, isolated Patrol runs can be evaluated without displacing `integration_test` as the core framework.
