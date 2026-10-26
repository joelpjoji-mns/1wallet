# `lib/src/features/planner/` — Financial Planning & Envelope Budgeting

## 🎯 Role & Overview
Domain module for monthly budget planning, envelope allocations, discretionary spending targets, and financial goal tracking.

---

## 🏗️ Architectural Purpose & Role
- Integrates with `Category` models to assign monthly spending caps.
- Tracks spending vs budget limits in real time.
- Prepares for future envelope budgeting features and cash reserve projections.

---

## 🛡️ Critical Invariants & Architecture

1. **Budget Time Horizons**:
   - Monthly budgets must align with the user's custom `monthStartDay` preference (defaulting to the 1st of the month).
2. **Rollover Calculations**:
   - If envelope rollover is enabled for a category, unspent amounts from the previous month carry forward into the current month's allowance.

---

## 🔍 LLM / Developer Checklist

- [ ] When implementing or extending planner screens, ensure all budget thresholds use integer minor currency units.
- [ ] Connect planner views to `ledger_selectors.dart` to calculate month-to-date category totals.
