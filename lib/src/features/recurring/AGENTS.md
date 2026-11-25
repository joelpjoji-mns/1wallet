# `lib/src/features/recurring/` — Recurring Transactions & Subscriptions

## 🎯 Role & Overview
Manages scheduled and recurring financial rules (`FutureGenerationRule`), such as monthly subscriptions, rent, salaries, utilities, and loan repayments.

---

## 📜 Key Files

- **`recurring_screen.dart`**:
  - Tabbed or categorized list of recurring rules (Active, Paused, Completed).
  - Displays cadence, amount, linked account, next execution date, and quick actions to post, skip, or edit.

---

## 🛡️ Critical Invariants & Architecture

1. **Recurrence Cadence Math**:
   - Recurrence calculation handles intervals (daily, weekly, bi-weekly, monthly, quarterly, yearly) and end-of-month adjustments (e.g., February 28/29 or 30-day months).
2. **Post Modes**:
   - Automatic post vs Manual approval mode.
   - Posting a recurring occurrence creates a concrete `TransactionRecord` with `recurringRuleId` linked, updating the rule's `occurrences` count and next due date.
3. **Skipped Occurrences**:
   - Skipping an occurrence must store the skipped date in `skippedOccurrences` without altering other future schedule dates.
4. **Payment Summary**:
   - Planned details aggregate actual posted/cleared history with `recurringPlanPaymentSummary`, excluding skipped and unpaid records. Original currencies remain separate rather than being added or converted at current rates.
   - Count-limited plans show occurrence progress, while ongoing/date-ended plans show totals without a guessed monetary ceiling. Loan-backed plans retain their existing principal/payoff progress.

---

## 🔍 LLM / Developer Checklist

- [ ] Check `test/recurring_plan_amount_update_test.dart` and `test/recurring_hide_skipped_and_rounding_test.dart`.
- [ ] Ensure editing a recurring rule's amount gives the user the choice between updating future occurrences only or updating historical records.
