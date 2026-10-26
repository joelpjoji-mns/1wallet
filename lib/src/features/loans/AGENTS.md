# `lib/src/features/loans/` — Loans, Debts & Amortization

## 🎯 Role & Overview
Tracks debts and loans (money borrowed from others, money lent to others, bank mortgages/personal loans), including interest rates, tenure, EMI schedules, and payoff projections.

---

## 📜 Key Files

- **`loans_screen.dart`**: Overview of active loans, outstanding balance, monthly EMI amounts, and progress bars towards payoff.
- **`loan_forecast_simulator.dart`**: Mathematical simulator for amortizing loan schedules, simulating extra prepayments, and calculating interest savings.

---

## 🛡️ Critical Invariants & Architecture

1. **Precision in Amortization Math**:
   - Compounding interest and EMI formulas must compute payment breakdowns in integer minor units, distributing rounding residuals to the final payment installment.
2. **Directionality (Lent vs Borrowed)**:
   - Lent loans represent positive assets in net worth; borrowed loans represent liabilities. Calculations must never invert this sign convention.

---

## 🔍 LLM / Developer Checklist

- [ ] Run `test/loans_screen_form_bugfix_test.dart` and `test/loans_screen_opaque_scroll_content_test.dart`.
- [ ] Verify that repayment entries correctly link to an account and deduct the EMI amount from the paying account.
