# `lib/src/features/imports/` — Statement Import Workflows

## 🎯 Role & Overview
UI screens and wizards for importing financial transactions from external bank statements (PDF documents, CSV spreadsheets, and backup files).

---

## 📜 Key Files

- **`import_statement_screen.dart`**:
  - File picker trigger, progress bar, column-mapping modal (for CSVs), password prompt (for encrypted bank PDFs), and parsed transaction review list before importing.

---

## 🛡️ Critical Invariants & Architecture

1. **Transaction Staging**:
   - Parsed statements are grouped into an `ImportBatch`. Users can preview, edit, or cancel before records are committed to the ledger.
2. **Batch Rollback**:
   - The user can delete an entire `ImportBatch` in one action if an incorrect file was imported.

---

## 🔍 LLM / Developer Checklist

- [ ] Check `test/import_wallet_csv_flow_test.dart` and `test/multi_page_statement_test.dart`.
- [ ] Confirm error feedback when a password-protected PDF has an incorrect password provided.
