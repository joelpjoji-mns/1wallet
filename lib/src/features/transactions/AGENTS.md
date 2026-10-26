# `lib/src/features/transactions/` — Transaction Records & Creation

## 🎯 Role & Overview
Core transaction flow: adding income, expenses, and account transfers; viewing transaction history with search, filtering, and date bucketing; inspecting transaction details and attachments.

---

## 📜 Key Files

| File | Responsibilities |
| :--- | :--- |
| `transactions_screen.dart` | Paginated/grouped list of transactions by date, search bar, category/account filter chips. |
| `add_record_screen.dart` | Primary transaction entry screen supporting quick type toggle (Expense, Income, Transfer), custom numpad/calculator, category picker, account selector, tags, and receipt attachment. |
| `add_record_widgets.dart` | Built-in numeric calculator pad, currency input display, and rounding helpers. |
| `transaction_detail_screen.dart` | Detailed view for inspecting, editing, duplicating, or deleting an existing record. |
| `transaction_row.dart` | Highly optimized transaction row widget rendering category icon, title, notes, and colored amount. |
| `transactions_components.dart` | Filter bottom sheets, search text fields, and empty state cards. |

---

## 🛡️ Critical Invariants & Architecture

1. **Precision Calculator**:
   - The embedded numpad calculator in `add_record_widgets.dart` must evaluate expressions (`+`, `-`, `*`, `/`) with high precision, converting to integer minor units upon entry completion without floating-point errors.
2. **Transfer Logic**:
   - Transfers require both `accountId` (source) and `counterAccountId` (destination). If different currencies are involved, the destination amount is stored in the record's transfer fields.
3. **Optimized Scrolling**:
   - `TransactionRow` widgets must avoid expensive repaints during rapid list scrolling.

---

## 🔍 LLM / Developer Checklist

- [ ] Run `test/add_record_calculator_and_rounding_test.dart` and `test/add_record_flow_test.dart`.
- [ ] Run `test/tags_and_filtered_search_test.dart` when modifying search or filter criteria.
