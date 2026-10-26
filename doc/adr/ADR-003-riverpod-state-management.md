# ADR-003: StateNotifier & Expando-Memoized Riverpod Selectors

## Context
A financial ledger application performs frequent derived calculations: summing balances across accounts, consolidating foreign exchange portfolios, computing category budget depletion, and filtering transactions by date range. Re-evaluating these computations during every UI frame causes micro-stutter and high battery consumption.

## Decision
1. Adopt `flutter_riverpod` (v2.6.1+) with `StateNotifier<LedgerState>`.
2. Encapsulate all derived calculations in pure selector functions inside `lib/src/ledger/ledger_selectors.dart`.
3. Utilize Dart's native `Expando` keyed on the immutable `LedgerState` instance to memoize expensive sorting and aggregation results:
   ```dart
   final _sortedTransactionsExpando = Expando<List<TransactionRecord>>();
   List<TransactionRecord> sortedTransactions(LedgerState state) {
     return _sortedTransactionsExpando[state] ??= List.unmodifiable(...);
   }
   ```

## Consequences
### Positive
- Sub-millisecond UI re-renders: Cached selectors return instantly if `LedgerState` identity hasn't changed.
- Compile-time safety: Riverpod avoids runtime `BuildContext` dependency lookups and prevents missing provider exceptions.
- Pure functions make unit testing extremely straightforward without mocking Flutter UI widgets.

### Negative / Trade-offs
- Every state update must create a new immutable instance (`copyWith`) to correctly invalidate the `Expando` cache.
