# `lib/src/capture/` — Capture Pipeline & Transaction Message Parsing

## 🎯 Role & Overview
This directory implements the core ingestion engine for extracting structured financial transactions from unstructured messages (SMS texts, banking push notifications, and receipt text). It provides regex pattern extractors, account matching heuristics, and candidate queuing.

---

## 📜 Key Files

- **`message_parser.dart`**:
  - `ParsedTransactionMessage`: Structured result containing amount (in minor units), transaction type (`debit`, `credit`), currency, account identifier/last 4 digits, merchant/vendor name, balance after transaction, and date.
  - Comprehensive regex library for multi-bank financial SMS templates (HDFC, SBI, ICICI, Chase, Wells Fargo, etc.).
- **`capture_pipeline.dart`**:
  - Orchestrates processing of raw messages or OCR text.
  - Performs deduplication against existing ledger records using fuzzy timestamp, amount, and account matching.
  - Produces `CaptureImportResult` with statuses: `queued`, `ignored`, `duplicate`, or `error`.
  - Queues candidates in `CaptureCandidate` for user review in the Review Queue.

---

## 🛡️ Critical Invariants & Architecture

1. **Amount Normalization**:
   - Parsed amounts must be converted directly to integer minor units (`amountMinor`).
   - Currency symbols or codes (`₹`, `$`, `INR`, `USD`) must be mapped to ISO-4217 currency strings.
2. **Deterministic Deduplication**:
   - Duplicate detection prevents double-counting transactions received via both SMS and notification, or re-scanned receipts.
3. **Never Auto-Commit Unchecked Data**:
   - Captured items are staged as `CaptureCandidate` objects in the ledger's review queue. The user retains ultimate approval authority before items enter permanent ledger records.

---

## 🔍 LLM / Developer Checklist

- [ ] When adding new bank regex patterns to `message_parser.dart`, add corresponding unit tests in `test/sms_parser_comprehensive_test.dart` and `test/message_parser_test.dart`.
- [ ] Ensure regex matches handles varied number formats (commas vs periods in decimals: `1,234.50` vs `1.234,50`).
- [ ] Check deduplication thresholds: Ensure slight timestamp variance (within a few minutes) between an SMS and a bank push does not create duplicate entries.
