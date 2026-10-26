# `pwa/src/components/` — PWA UI Components & Modals

## 🎯 Role & Overview
Contains shared React UI components for the companion PWA, including transaction creation/editor modals, account management modals, and form elements.

---

## 📜 Key Files

- **`AccountModal.tsx`**: Modal for creating or editing accounts (name, type, currency, opening balance, color).
- **`TransactionModal.tsx`**: Modal for logging income, expenses, and transfers with category pickers, account selectors, and date pickers.

---

## 🛡️ Critical Invariants & Architecture

1. **Integer Minor Unit Inputs**:
   - Currency input fields must accept decimal text from users (e.g. `25.50`) and convert directly to integer minor units (`2550`) before committing to the wallet context.
2. **Transfer Invariant**:
   - Disallow selecting the same account as both source and destination in transfers.

---

## 🔍 LLM / Developer Checklist

- [ ] Verify accessibility attributes (ARIA roles, keyboard escape dismissal) on modals.
- [ ] Confirm modal forms clear dirty states upon cancellation.
