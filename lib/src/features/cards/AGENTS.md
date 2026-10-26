# `lib/src/features/cards/` — Payment Cards Management

## 🎯 Role & Overview
Visualizes user debit and credit cards, tracks billing cycles, statement generation dates, due dates, and credit utilization percentages.

---

## 📜 Key Files

- **`cards_screen.dart`**:
  - Horizontal swipeable carousel of visual card widgets (`CreditCardView`).
  - Summarizes card utilization, available limit, next payment due date, and recent transactions linked to the selected card.

---

## 🛡️ Critical Invariants & Architecture

1. **Credit Utilization Invariant**:
   - Utilization is calculated as `(currentBalanceMinor / creditLimitMinor) * 100`.
   - Edge cases where limit is zero or negative must be guarded to avoid division-by-zero errors.
2. **Security**:
   - Full card numbers (PAN) and CVVs must never be stored. Only card nicknames, brand icons, and last 4 digits are kept in `Account` models.

---

## 🔍 LLM / Developer Checklist

- [ ] Verify that card color and gradient themes render legibly with white and dark text.
- [ ] Run `test/cards_new_account_initial_type_test.dart` and `test/credit_card_and_recurrence_enhancements_test.dart`.
