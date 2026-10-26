# Rule: Riverpod State Management & Selectors

## Invariants

1. **State Immutability**:
   - `LedgerState` is strictly immutable. Never mutate lists (`records`, `accounts`, `categories`) in place.
   - All mutations must create new instances via `.copyWith(...)` and mark `unsyncedChanges = true`.

2. **Selectors Over Raw Widget Computations**:
   - Never iterate through transactions or sum balances directly inside widget `build()` methods.
   - Always call pure selectors from `lib/src/ledger/ledger_selectors.dart` (e.g. `accountBalance`, `flowForPeriod`, `netWorth`, `sortedTransactions`).
   - Selectors utilize `Expando` memoization to guarantee $O(1)$ amortized lookups on rebuild.

3. **Provider Scoping**:
   - Widgets consume providers via `ConsumerWidget` or `ConsumerStatefulWidget`.
   - Use `ref.watch()` for reactive view updates and `ref.read()` inside user action callbacks.
