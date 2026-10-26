# `lib/src/features/accounts/` — Accounts Management

## 🎯 Role & Overview
Handles display, creation, editing, and secure balance details for user financial accounts (Checking, Savings, Cash, Credit Card, Investment).

---

## 📜 Key Files

- **`accounts_screen.dart`**: Primary list view of accounts grouped by type, showing balances, currency tags, and net worth contribution.
- **`account_editor_screen.dart`**: Form for creating or updating accounts (name, type, currency, opening balance, color, icon, credit limit).
- **`secure_account_details_screen.dart`**: Protected view for sensitive account details, credit limits, account numbers/identifiers, and encryption states.

---

## 🛡️ Critical Invariants & Architecture

1. **Opening Balance Handling**:
   - An account's opening balance must be reflected in net balance calculations without double-counting when adjustments or opening balance transactions exist.
2. **Account Deletion Safety**:
   - Deleting an account must warn the user if transactions are associated with it, offering deletion options (cascade delete vs reassigning).
3. **Multi-Currency Accounts**:
   - Each account has an immutable base currency. If transactions in foreign currencies are posted to it, conversion is handled through ledger selectors.

---

## 🔍 LLM / Developer Checklist

- [ ] When modifying account editor forms, ensure integer minor unit conversions for opening balance and credit limits.
- [ ] Check `test/account_delete_flow_test.dart` and `test/account_opening_balance_persistence_test.dart` after modifications.
