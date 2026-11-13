# ADR 0003: Observability, Crash Reporting, and Telemetry

## Status
Accepted

## Context
1Wallet requires production crash reporting, error monitoring, and performance telemetry to detect defects and maintain high performance. However, because 1Wallet is a personal finance app, it has strict privacy constraints:
- Financial amounts, account numbers, PINs, transaction notes, and personal identifiers must **never** be logged, captured in stack traces, or transmitted to external servers.
- The app already utilizes Firebase Core and Firestore for cloud sync (when the user opts into online mode).

Two primary candidates for error monitoring were considered:
1. **Sentry**:
   - Comprehensive error tracking, performance tracing, and session replay.
   - Requires introducing the `sentry_flutter` dependency (~2MB binary size impact) and managing separate account/project credentials.
   - Session replay poses a severe risk of accidentally capturing financial data or leaking sensitive screens unless heavily masked.
2. **Firebase Crashlytics + Firebase Performance**:
   - Native integration with the existing Firebase infrastructure already present in the app.
   - Zero additional third-party vendor footprint or duplicate SDK overhead.
   - Lightweight, with built-in release tagging, ProGuard/mapping upload, and NDK crash capture.

## Decision
We select **Firebase Crashlytics + Firebase Performance** wired through an abstracted **Privacy-First Observability Façade** (`AppLogger`, `CrashReporter`, `PerformanceTracker`, `AnalyticsService`):

1. **Façade Abstraction**: Application code never calls Firebase Crashlytics or external logging APIs directly. All logging, error reporting, and tracing flow through the observability façade.
2. **Automated PII & Financial Redaction**: `AppLogger` and `CrashReporter` automatically scrub log messages, breadcrumbs, and error metadata using regular expressions and strict key whitelisting. Any field matching money amounts, balances, tokens, or personal identifiers is sanitized to `[REDACTED]`.
3. **Opt-in, Anonymous Analytics**: Analytics telemetry is strictly opt-in via user preferences. No monetary amounts, accounts, or free-text descriptions are accepted into the event payload schema.
4. **Zero Print Rule**: Raw Dart `print()` and `debugPrint()` are prohibited in production code, enforced by linting and custom log routing.
5. **Swappable Architecture**: Because the façade decouples the application from concrete implementations, Sentry can be introduced in the future simply by providing an alternate adapter without touching feature code.

## Consequences
- Bundle size remains compact without redundant vendor SDKs.
- Zero risk of financial PII leakage across crash logs, network breadcrumbs, or performance traces.
- Complete operational parity between offline mode (where telemetry is safely dropped or stored locally) and online mode.
