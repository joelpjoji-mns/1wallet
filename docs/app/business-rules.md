# Business Rules

This file records the ledger and product behavior that should stay stable across UI refactors.

## Money And Currency

- Money is stored as integer minor units plus currency code. Do not use floating point for storage.
- Supported currencies are INR, USD, EUR, GBP, AED, SGD, JPY, AUD, and CAD.
- JPY has 0 minor units; the rest currently use 2 minor units.
- Default enabled currencies are INR, USD, EUR, and GBP.
- `SUPPORTED_CURRENCIES` is the catalog. User-facing workflows should prefer the enabled currency list.
- Display currency is a preference for presentation and reporting. It is separate from base currency.
- FX rates are fresh for one hour. Missing/stale rates should be refreshed before saving foreign purchases where possible.
- If an FX provider is unavailable, the app should preserve user control through manual rate entry or a clear error path.

## Account Rules

- Account types: cash, bank, credit_card, debit_card, wallet, prepaid, loan, lent, investment, savings_goal, overdraft, crypto, other.
- Each account has its own currency and opening balance. Opening balance is not a transaction unless a snapshot/import flow creates adjustment records.
- The first created account can become the default account.
- Include flags affect totals, budgets, reports, net worth, and Home visibility independently.
- Archive is a soft-delete for accounts with history. Empty accounts can be deleted.
- Archived accounts should not clutter default pickers but must remain valid for historical transactions and reports where included.
- Account sort order controls display order and can be changed from the Accounts tab.
- Account match identifiers and message source hints are used only to improve capture routing; they do not change ledger balances directly.

## Transaction Rules

Transaction types:

- expense
- income
- transfer
- refund
- adjustment
- card_payment
- loan_repayment
- lent
- borrowed
- investment_buy
- investment_sell
- fee
- interest_in
- interest_out
- cashback

Statuses:

- `cleared`: affects balances.
- `pending`: visible, but should not affect current cleared balance.
- `scheduled`: future/planned, does not affect current cleared balance until posted/cleared.
- `void`: reversal/cancelled state, should not act like a normal cleared transaction.

Sources:

- manual
- recurring
- import
- notification
- sms
- email
- rule
- shared
- api

Balance impact:

| Type group    | Examples                                                         | Balance behavior when cleared                                   |
| ------------- | ---------------------------------------------------------------- | --------------------------------------------------------------- |
| Inflow        | income, refund, interest_in, cashback, borrowed, investment_sell | Adds to the account balance.                                    |
| Outflow       | expense, fee, interest_out, lent, investment_buy                 | Subtracts from the account balance.                             |
| Transfer-like | transfer, card_payment, loan_repayment                           | Subtracts from source and adds to counter account when present. |
| Adjustment    | adjustment                                                       | Adds or subtracts the signed amount; zero is invalid.           |

Validation rules:

- Transfer-like records need a source account and usually a distinct counter account.
- Expense and income records normally need a category unless a special flow intentionally omits it.
- Amount must be non-zero for saved records.
- Splits should not silently contradict the parent amount in UI flows.
- Payment method, notes, tags, attachments, person/project/trip, reimbursement, and tax flags are metadata; they do not change balance by themselves.

## Currency Transaction Rules

Foreign purchase on an account:

- `originalAmount` stores the purchase currency amount.
- `originalFxRate` stores the conversion rate from original currency to account/posting currency.
- `amount` stores the posted amount in the account currency.
- `baseAmount` stores the base/reporting conversion.

Cross-currency transfer:

- `amount` stores the source-side amount.
- `counterAmount` stores the destination-side amount.
- `counterFxRate` stores the source-to-counter conversion used for the transfer.
- Balances should update in each account's own currency.

Display conversion:

- Home, Reports, and widgets may convert values to display currency using available FX rates.
- Historical transactions should keep their original stored currency fields even when display currency changes.

## Category Rules

- Category kinds are expense, income, transfer, and system.
- Categories can be hierarchical with optional parent ID.
- Names should be unique within the same user and parent.
- Archived categories remain valid for old records but should be hidden from normal new-record choice lists.
- Hidden-in-stats categories remain available but should be excluded from category statistics where requested.

## Capture Candidate Rules

- Capture statuses: pending, approved, rejected, ignored, auto_posted.
- A pending candidate is not a posted transaction.
- Approval creates or links a transaction.
- Rejection/ignore prevents accidental posting but preserves review history where the app keeps it.
- Confidence is advisory. Low confidence should bias toward manual review.
- Warnings should be actionable and should identify missing account/category/rate/date information.
- Duplicate detection should use external reference/raw hash semantics, not only visible merchant text.

## Import Batch Rules

- Import batch sources: wallet_csv, manual_csv, api, notification.
- Import batch statuses: previewed, queued, partially_posted, posted, rolled_back.
- Wallet CSV import should preview before writing many ledger entities.
- Re-importing the same source should not duplicate records.
- Transfer pair detection should prevent double-counting when an export contains both sides of a transfer.

## SMS And Message Capture Rules

- Android SMS capture requires runtime permission and enabled preferences.
- Background capture should only run when `autoCapture.enabled` and SMS background settings allow it.
- Messages must contain transaction-like trigger keywords and must not match security ignore patterns.
- OTP, verification, password, PIN, login, and balance-only messages should be ignored.
- Last-4 fragments can route messages to account match identifiers.
- Category matching precedence is custom rules, default rules, merchant defaults, generic fallback, category name match.
- Ambiguous category matches should queue to Review rather than auto-posting.
- Manual SMS scans should summarize posted/queued/duplicate/ignored counts without exposing a full inbox dump in-app.

## Recurring And Planned Payment Rules

- Recurrence frequencies: daily, weekly, monthly, yearly.
- Rules can have intervals, start date, end date, occurrence count, day-of-month, skipped occurrences, and post mode.
- Post modes are manual or automatic.
- Planned payment kinds include expense, income, transfer, card payment, loan EMI, bill, subscription, savings transfer, and other.
- Forecast occurrences should not move money until confirmed or auto-posted.
- Due scheduled records can become cleared recurring transactions through an explicit due action or automatic post mode.

## Loan Rules

- Loan kinds: personal, home, vehicle, education, business, gold, BNPL, overdraft, lent, other.
- Interest periods: annual or monthly.
- Interest methods: reducing balance, flat, interest only.
- Setup modes: track from next repayment or backfill paid installments.
- Loan repayment can be linked to a planned payment rule.
- Principal and interest split should reduce outstanding loan principal only by the principal portion.
- Forecasts must recalculate when principal, rate, tenure, repayment amount, or repayment frequency changes.

## Notification Rules

- In-app notification inbox should work even when native OS notification permission is denied.
- Native delivery requires Android notification permission and channel/user preference enablement.
- Channels include review queue, scheduled items, budgets, goals, accounts, imports, and activity-style events.
- Read, dismiss, and snooze states should persist.
- Native delivery IDs should be tracked so the same item is not repeatedly delivered.
- Tapping a native notification should route to the relevant screen, usually Review or Notifications.

## Persistence And Lifecycle

- The current runtime is local-first through shared ledger/state packages and local persistence.
- Supabase/Postgres docs describe future cloud sync, not current storage.
- App background/inactive should flush pending saves.
- App resume should reload from store after a short settle period.
- Android home widget sync is debounced and should not block normal UI.
