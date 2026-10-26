# `test/fixtures/` — Test Fixtures & Sample Payloads

## 🎯 Role & Overview
Houses static mock data used by the automated test suite, including:
- Sample bank SMS alert strings across various Indian and global financial institutions.
- Multi-page bank statements (PDF, CSV).
- Encrypted and unencrypted sample wallet JSON backups.

---

## 🛡️ Critical Invariants & Architecture

1. **Synthetic & Anonymized Data Only**:
   - Fixtures must never contain real personal, banking, or credit card numbers. All account numbers, phone numbers, and names must be synthetic mocks.
2. **Deterministic Inputs**:
   - These fixtures are referenced in parser unit tests (`test/message_parser_test.dart`, `test/universal_pdf_statement_test.dart`, etc.). Modifying them will impact test assertions.
