# `lib/src/ledger/` — Ledger Selectors & Derived Aggregations

## 🎯 Role & Overview
The computational engine for ledger queries. Contains pure, memoized selector functions that compute account balances, net worth, cash flow summaries, category spending, and sorted transaction lists from `LedgerState`.

---

## 📜 Key Files

- **`ledger_selectors.dart`**:
  - `accountBalance(state, account)`: Computes current balance including opening balance, income, expenses, and transfers.
  - `cashCurrencyBalancesForAccount(state, account)`: Multi-currency cash breakdown.
  - `totalBalance(state)`: Unified balance in base currency.
  - `netWorth(state)`: Returns `({Money total, Money assets, Money liabilities})`.
  - `flowForPeriod(state, range)`: Returns `({Money income, Money expense})` excluding internal transfers.
  - `sortedTransactions(state)`: Cached sorting of transactions by date descending.
  - `activeCategories(state)`, `sortedCategoriesByUsage(state)`: Category hierarchy and frequency queries.
  - `scheduledTransactions(state)`: Active scheduled recurring rules.

---

## 🛡️ Critical Invariants & Architecture

1. **Memoization via `Expando`**:
   - High-throughput selectors (like `sortedTransactions` and `scheduledTransactions`) use Dart `Expando` keyed on `LedgerState` identity to cache sorted lists and avoid repeated $O(N \log N)$ sorting during widget builds.
2. **Double-Entry Balance Formula**:
   - Expense: `sourceDelta = -amountMinor`
   - Income: `sourceDelta = +amountMinor`
   - Transfer: `sourceDelta = -sourceAmountMinor`, `counterDelta = +destinationAmountMinor`
3. **Pure Functions**:
   - Selectors must never mutate arguments or global state.

---

## 🔍 LLM / Developer Checklist

- [ ] Run `test/account_opening_balance_persistence_test.dart` and `test/ledger_persistence_test.dart`.
- [ ] If modifying balance formulas, verify that transfers between different currencies are converted using the recorded transfer rate rather than live market rate.
