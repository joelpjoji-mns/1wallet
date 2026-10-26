# `lib/src/features/currencies/` — Multi-Currency & FX Exchange

## 🎯 Role & Overview
Handles multi-currency settings, FX exchange rate display, rate caching, base currency selection, and manual rate overrides.

---

## 📜 Key Files

- **`currencies_screen.dart`**:
  - Displays primary display currency, active currencies in use across accounts, and the latest exchange rates against base currency.
  - Allows manual rate overrides and triggers online rate sync.

---

## 🛡️ Critical Invariants & Architecture

1. **Base Currency Anchor**:
   - Every wallet has a single default base currency (e.g. `USD`, `EUR`, `INR`). All portfolio totals and net worth metrics are converted into this anchor currency for uniform display.
2. **Deterministic FX Conversion**:
   - `amountMinor` converted to base currency uses: `(sourceMinor * rate) ~/ rateScale`.
   - Division by zero or negative FX rates must be prevented.

---

## 🔍 LLM / Developer Checklist

- [ ] Check `test/cash_account_multi_currency_test.dart`.
- [ ] Confirm that currency formatting obeys locale-specific conventions (e.g. lakh/crore formatting in `en_IN` vs standard hundreds in `en_US`).
