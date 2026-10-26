# `lib/src/imports/` — Statement Parsing & Data Ingestion

## 🎯 Role & Overview
Provides raw text extraction and structured tabular parsing engines for external documents: PDF bank statements, credit card bills, and CSV transaction exports.

---

## 📜 Key Files

| File | Responsibilities |
| :--- | :--- |
| `pdf_text_extractor.dart` | Wraps `syncfusion_flutter_pdf` to extract lines of text from multi-page PDF documents, handling password-protected files. |
| `statement_parser.dart` | Heuristic parser grouping raw statement lines into transaction blocks (`_DateBlock`, `_ExtractedAmount`, `_ParsedBlockCandidate`), detecting credits, debits, dates, and descriptions. |
| `wallet_csv_parser.dart` | Flexible CSV parser allowing dynamic column mapping (date, amount, note, category, account) for exported files from other wallet apps or bank portals. |
| `picked_text_file.dart` | Cross-platform abstract representation of user-picked files for mobile and web. |

---

## 🛡️ Critical Invariants & Architecture

1. **Multi-Page Continuity**:
   - Statements spanning multiple pages must stitch table rows seamlessly across page headers and footers without dropping boundary transactions.
2. **Robust Currency Parsing**:
   - Handles localized numbers (`$1,234.50`, `1.234,50 €`, `Rs. 5,000.00`).
3. **No Unchecked Ingestion**:
   - Parsers return a `StatementParseResult` or `ParsedWalletCsvResult` containing structured candidates and error lists; they do not write directly to `LedgerState`.

---

## 🔍 LLM / Developer Checklist

- [ ] Check `test/universal_pdf_statement_test.dart`, `test/wallet_csv_parser_test.dart`, and `test/picked_text_file_test.dart`.
- [ ] Ensure memory efficiency when parsing large (100+ page) statements by releasing PDF documents after extraction.
