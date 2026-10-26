# `lib/src/features/routes/` — Route Screen Factories

## 🎯 Role & Overview
Defines screen factory methods and route wrappers connecting `GoRoute` entries with their corresponding screen widgets and parameter extraction.

---

## 📜 Key Files

- **`route_screens.dart`**:
  - Encapsulates path-to-widget instantiation for transactions, accounts, categories, settings, and captures.
  - Safely extracts path parameters (e.g. `:id`) and query parameters, handling missing or malformed IDs with fallback screens.

---

## 🛡️ Critical Invariants & Architecture

1. **Parameter Validation**:
   - Route parameters must be validated before passing into screens. If an entity ID does not exist in `LedgerState`, present an informative "Not Found" state rather than a red screen error.

---

## 🔍 LLM / Developer Checklist

- [ ] Run `test/routes_smoke_test.dart` to verify that all registered paths instantiate valid widget trees without unhandled exceptions.
