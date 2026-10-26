# `lib/src/features/calendar/` — Financial Calendar & Forecast

## 🎯 Role & Overview
Provides a calendar-based perspective on finances, visualizing past spending per day and forecasting future balance trends based on scheduled recurring rules.

---

## 📜 Key Files

- **`calendar_screen.dart`**: Interactive month/week calendar view with day-selection tiles, daily totals, and expense markers.
- **`calendar_forecast.dart`**: Projection engine that merges historical balances with pending recurring bills to forecast daily ending balances up to 90 days out.

---

## 🛡️ Critical Invariants & Architecture

1. **Date Timezone Invariants**:
   - Date calculations must normalize to calendar days (midnight local time) to prevent timezone drift across DST transitions or cross-day shifts.
2. **Forecast Projection Isolation**:
   - Simulated forecast transactions are ephemeral projections; they must never be saved into permanent `LedgerState.records`.

---

## 🔍 LLM / Developer Checklist

- [ ] Verify month-to-month navigation semantics and screen reader accessibility (`calendar_month_navigation_a11y_test.dart`).
- [ ] Ensure that days with zero transactions display clean empty state indicators rather than throwing null assertions.
