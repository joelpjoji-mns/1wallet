# Rule: Financial Invariants & Arithmetic

## Invariants

1. **Integer Minor Units**:
   - Financial balances and amounts must ALWAYS be integers representing minor units (`amountMinor`).
   - $15.50 must be represented as `1550`.
   - Never use floating point (`double` or `number`) for internal financial math or persistence.

2. **Money Struct**:
   - Always pair an amount with its currency code via `Money(amountMinor: ..., currency: ...)`.

3. **Multi-Currency Transfers**:
   - When transferring between accounts with different currencies:
     - `amountMinor` represents the deducted amount in the source account currency.
     - `transferDestinationAmountMinor` represents the credited amount in the counter-account currency.
     - Never overwrite the exchange rate recorded at transaction creation time with a live floating rate.

4. **Formatting**:
   - Formatting into decimals must occur only at UI presentation boundaries using `formatMoney()` or `NumberFormatter`.
