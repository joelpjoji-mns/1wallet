# `doc/` — Project Documentation & API Reference

## 🎯 Role & Overview
Contains project documentation, generated API references, architectural decision records (ADRs), and contributor guidelines for the 1Wallet ecosystem.

---

## 🛡️ Critical Invariants & Architecture

1. **Keep Documentation in Sync**:
   - Any breaking architectural modification, API change in `lib/src/data/`, or new security rule must be reflected in corresponding documentation.
2. **API Documentation**:
   - `doc/api/` can be refreshed via `dart doc .`.
3. **UI audit**:
   - `ui-audit.md` is the UI consistency inventory: the concept × screen matrix, the canonical-choice table, token mappings, kept exceptions and before/after screenshots (`ui-audit/before`, `ui-audit/after`). Regenerate screenshots with `flutter test test/ui_route_matrix_test.dart --dart-define=UI_AUDIT_SHOTS=doc/ui-audit/after --dart-define=UI_AUDIT_SHOTS_FILTER=<slug@variant,…>`.

---

## 🔍 LLM / Developer Checklist

- [ ] Maintain markdown formatting consistency and verify internal file links.
