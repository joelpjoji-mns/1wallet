# `lib/src/observability/` — Observability, Structured Logging, Error Reporting & Privacy

## 🎯 Role & Overview
Provides a centralized, privacy-respecting observability façade for the 1Wallet Flutter application. Coordinates:
1. **Structured Logging (`AppLogger`)**: Replaces raw `print()` statements with structured log records, levels, and automated PII/financial amount redaction.
2. **Crash & Error Reporting (`CrashReporter`)**: Decouples error capture from third-party vendor SDKs (Firebase Crashlytics, Sentry), enforces SHA-256 user ID anonymization, and strips sensitive context keys.
3. **Performance Monitoring (`PerfTracer`)**: Implements `TraceSpan` with defined performance budgets for cold start (<1500ms), ledger hydration (<500ms), and cloud sync (<800ms).
4. **Privacy-First Analytics (`AnalyticsService`)**: Opt-in only telemetry that strictly rejects financial numbers, balances, account details, and transaction notes.

---

## 📜 Key Files

| File | Responsibilities |
| :--- | :--- |
| `app_logger.dart` | Structured logger with `trace`, `debug`, `info`, `warning`, `error`, `fatal` levels and regular expression redaction. |
| `crash_reporter.dart` | `CrashReporter` interface, release tagging (`appVersion`, `buildNumber`, `gitCommitSha`), and hashed user IDs. |
| `perf_tracer.dart` | Performance budget definitions and trace span duration tracking. |
| `analytics_service.dart` | Swappable analytics abstraction with opt-in gates and financial parameter filtering. |

---

## 🛡️ Critical Invariants & Architecture

1. **Zero Financial PII in Logs & Telemetry**:
   - Currency figures, balances, bank account details, and transaction notes must never be emitted in plain text to any log sink or remote reporter.
   - Any string matching currency symbols (`$`, `€`, `£`, `₹`, `¥`) or metadata keys (`amount`, `balance`, `token`, `secret`) is sanitized to `[REDACTED]`.
2. **No `print()` or `debugPrint()` in Production Code**:
   - Always invoke `AppLogger.info()`, `AppLogger.debug()`, `AppLogger.warning()`, or `AppLogger.error()`.
3. **Strict Opt-In Analytics**:
   - Analytics events are dropped immediately if the user has not explicitly consented (`isOptedIn == false`).
4. **Performance Budgets**:
   - Operations that exceed budgets must emit `LogLevel.warning` with structured metadata.

---

## 🔍 LLM / Developer Checklist

- [ ] Run `test/observability_test.dart` after modifying loggers or reporters.
- [ ] Ensure any newly added telemetry parameter is not financial or personally identifiable.
- [ ] Never log unencrypted authorization headers or master encryption keys.
