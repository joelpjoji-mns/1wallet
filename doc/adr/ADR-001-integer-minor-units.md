# ADR-001: Use Integer Minor Units for Monetary Values

## Context
Standard IEEE 754 floating-point numbers (`double` in Dart, `number` in TypeScript) are incapable of accurately representing base-10 fractional decimals. Arithmetic operations accumulate rounding errors (e.g. `0.1 + 0.2 = 0.30000000000000004`), which can lead to divergent balances, lost fractions of cents, and failed ledger reconciliation.

## Decision
All monetary values across 1Wallet (Flutter core, companion PWA, Firestore payloads, and serialization codecs) are strictly represented as integer minor units:
- `amountMinor` (cents, pence, paise, satoshis).
- 1.00 USD is stored as `100`.
- 1,000 JPY (zero-decimal currency) is stored as `1000`.

Formatting into localized decimal strings occurs exclusively in UI presentation layers via `formatMoney()` or `NumberFormatter`.

## Consequences
### Positive
- Zero floating-point drift or precision loss across hundreds of thousands of transactions.
- Perfect deterministic balance calculations across platforms (Dart, TypeScript, Firestore rules).
- High-performance 64-bit integer addition and subtraction without third-party BigNumber dependencies.

### Negative / Trade-offs
- Developers must never divide or multiply without explicitly considering minor unit scaling.
- User input fields must convert decimal input strings into integers before mutating state.
