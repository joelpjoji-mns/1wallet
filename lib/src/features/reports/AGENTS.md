# `lib/src/features/reports/` — Analytics & Financial Reporting

## 🎯 Role & Overview
Provides visual analytics, spending breakdowns, income vs expense bar charts, category donut charts, and cash flow trends.

---

## 🏗️ Architectural Purpose & Role
- Backed by `fl_chart` for high-performance vector rendering.
- Consumes derived selectors (`flowForPeriod`, `netWorth`, category spending aggregators) to present data across customizable date intervals (This Month, Last Month, Last 90 Days, Year-to-Date, All Time).

---

## 🛡️ Critical Invariants & Architecture

1. **Empty State & Zero-Division Safety**:
   - Charts must render gracefully when there are zero transactions or zero expenses in a period, avoiding `NaN` angles or zero-division crashes.
2. **Transfer Exclusion**:
   - Internal account-to-account transfers must be excluded from income/expense calculations to avoid artificially inflating cash flows.

---

## 🔍 LLM / Developer Checklist

- [ ] Verify chart touch interaction handles (`FlTouchData`) do not trigger frame drops or rebuild the entire screen unnecessarily.
- [ ] Ensure currency symbols and labels in chart tooltips use the user's primary display currency.
