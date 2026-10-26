# `lib/src/features/capture/` — Ingestion Screens, OCR & Review Queue

## 🎯 Role & Overview
Provides UI for capturing expenses from paper receipts (via camera/gallery OCR), managing incoming financial SMS messages, configuring capture sources, and triaging the `CaptureCandidate` review queue.

---

## 📜 Key Files

| File | Responsibilities |
| :--- | :--- |
| `receipt_ocr.dart` | Camera/gallery image picker and Google ML Kit Text Recognition integration. Extracts merchant, date, and grand total. |
| `review_queue_screen.dart` | Interactive queue where pending candidates can be accepted (converting into a `TransactionRecord`), edited, or discarded. |
| `capture_detail_screen.dart` | Deep-dive screen to inspect a single capture candidate's extracted fields and raw source text. |
| `sms_capture_screen.dart` | UI for scanning device SMS inbox and reviewing detected banking texts. |
| `sms_inbox_reader.dart` | Platform integration to read Android SMS inbox with permission handling. |
| `sms_spooler.dart` & `notification_spooler.dart` | Ingestion background queues buffering incoming messages before parsing. |
| `notification_apps_screen.dart` | Whitelist configuration for selecting which financial app push notifications are listened to. |
| `capture_settings_screen.dart` | Configuration toggles for auto-extraction, sensitivity, and OCR languages. |
| `capture_diagnostics.dart` & `capture_diagnostics_screen.dart` | Diagnostic log viewer for debugging parsing failures and regex misses. |

---

## 🛡️ Critical Invariants & Architecture

1. **User Confirmation Safety**:
   - Items in the review queue are never silently committed without user action or explicit automated rules configured by the user.
2. **Permission Guarding**:
   - SMS and Notification listeners require explicit runtime permissions. The UI must handle denied, permanently denied, or restricted permission states gracefully.

---

## 🔍 LLM / Developer Checklist

- [ ] Run `test/capture_pipeline_test.dart` and `test/receipt_ocr_test.dart` when updating extraction logic.
- [ ] Confirm that OCR fallback heuristics handle blurred receipts or missing decimal points safely without crashing.
