# `lib/src/utils/` — Cryptography, Currency & Math Utilities

## 🎯 Role & Overview
Provides shared algorithmic and platform utilities: AES-256 encryption, secure keystore access, currency and number formatting, recurrence math, and web reloading stubs.

---

## 📜 Key Files

| File | Responsibilities |
| :--- | :--- |
| `secure_key_store.dart` | Key storage backed by `flutter_secure_storage` with thread-safe concurrency locks and retry logic. |
| `currency_utils.dart` | ISO currency code lookups, currency symbols, and precision conversion helpers. |
| `number_formatter.dart` | High-performance number and currency formatting supporting multi-region numbering formats (Western, Indian Lakh/Crore). |
| `recurrence_utils.dart` | Calculation routines for finding next occurrence dates given cadence, interval, day of month, or day of week rules. |
| `app_reload.dart`, `stub_reload.dart`, `web_reload.dart` | Cross-platform utilities for triggering application reloads upon locale, theme, or user switch. |

---

## 🛡️ Critical Invariants & Architecture

1. **Integer Arithmetic**:
   - Number formatters and currency helpers operate on integer minor units (`int amountMinor`). Never cast to double for intermediate arithmetic.
2. **Key Store Concurrency**:
   - `SecureKeyStore` incorporates retry loops and concurrency protection to prevent platform channel deadlocks on Android and iOS keychain accesses.

---

## 🔍 LLM / Developer Checklist

- [ ] Run `test/secure_key_store_concurrency_test.dart`, `test/secure_key_store_retry_test.dart`, `test/number_formatter_overflow_test.dart`, `test/encrypt_test.dart`, and `test/decrypt_test.dart`.
- [ ] Confirm that currency formatting never drops cents/minor units unless explicit rounding flags are supplied.
