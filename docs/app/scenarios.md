# Scenario And Combination Matrix

This matrix turns the feature set into concrete combinations for QA, implementation review, and future regression testing.

## Transaction Type x Status x Source

| Type                             | Typical statuses                  | Typical sources                                    | Expected result                                                                   | Coverage                                                |
| -------------------------------- | --------------------------------- | -------------------------------------------------- | --------------------------------------------------------------------------------- | ------------------------------------------------------- |
| expense                          | cleared, pending, scheduled, void | manual, sms, import, notification, recurring, rule | Outflow when cleared; pending/scheduled visible but not current-balance impacting | Scenario rows ADD, SMS, Imports, Transactions.          |
| income                           | cleared, pending, scheduled, void | manual, sms, import, recurring, rule               | Inflow when cleared                                                               | Add Record and recurring scenarios need full matrix QA. |
| transfer                         | cleared, pending, scheduled       | manual, import, recurring, rule                    | Source decreases and destination increases when cleared                           | Transfer and cross-currency scenarios tracked.          |
| card_payment                     | cleared, scheduled                | manual, recurring, rule                            | Source decreases; credit card account receives payment                            | Card payment scenarios fixed and tracked.               |
| loan_repayment                   | cleared, scheduled                | manual, recurring, rule, sms                       | Source decreases; loan principal/interest behavior updates loan view              | Loan EMI scenarios fixed and tracked.                   |
| refund                           | cleared, pending                  | manual, import, sms                                | Inflow/reversal-style behavior                                                    | Needs focused QA.                                       |
| adjustment                       | cleared                           | manual, snapshot/import maintenance                | Signed correction changes balance                                                 | Add adjustment scenario tracked.                        |
| lent / borrowed                  | cleared, pending                  | manual, import                                     | Lent outflow, borrowed inflow                                                     | Needs focused QA.                                       |
| investment_buy / investment_sell | cleared                           | manual, import                                     | Buy outflow, sell inflow                                                          | Planned/low coverage.                                   |
| fee / interest_out               | cleared                           | manual, import, sms                                | Outflow                                                                           | Needs focused QA.                                       |
| interest_in / cashback           | cleared                           | manual, import, sms                                | Inflow                                                                            | Needs focused QA.                                       |

## Account Type x Operation

| Account type                        | Create                      | Edit                                         | Archive/delete                    | Special behavior                      | Coverage                                                         |
| ----------------------------------- | --------------------------- | -------------------------------------------- | --------------------------------- | ------------------------------------- | ---------------------------------------------------------------- |
| cash/bank/wallet/prepaid/debit_card | New account form/onboarding | Metadata, visibility, reorder                | Delete if unused, archive if used | Normal source/destination accounts    | Main account and account reorder verified; per-type pass needed. |
| credit_card                         | New account form            | Card-specific visibility and payment routing | Archive keeps history             | Cards screen and card_payment records | Card scenarios tracked.                                          |
| loan/lent/overdraft                 | New loan/account form       | Loan details and repayment schedule          | Archive keeps schedule/history    | Loan forecast and EMI rules           | Loan tests and scenario rows exist; UI pass needed.              |
| investment/crypto/other             | New account form            | Metadata/report flags                        | Archive/delete                    | Reporting-focused for now             | Needs verification.                                              |
| savings_goal                        | New account or goal flow    | Goal metadata/progress                       | Pause/archive related goal        | Goal progress tracking                | Needs goal workflow QA.                                          |

## Currency And FX Scenarios

| Scenario                 | Input                                                      | Expected result                                              | Coverage                                               |
| ------------------------ | ---------------------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------ |
| Same-currency expense    | INR account, INR amount                                    | Stores amount/base amount; balance changes by amount         | Basic Add scenario.                                    |
| GBP account expense      | GBP account, GBP amount                                    | Stores GBP amount; reports convert to display currency       | Scenario row exists; needs focused QA.                 |
| GBP purchase on INR card | INR account, GBP original amount, fresh/stale GBP-INR rate | Main amount remains GBP; INR posted value shown and stored   | Explicit user-requested flow; implemented and tracked. |
| INR-to-GBP transfer      | INR source, GBP destination, counter rate                  | Source decreases INR; destination increases GBP              | Needs focused cross-currency transfer QA.              |
| Display currency change  | Base INR, display GBP or USD                               | UI totals change display only; stored transactions unchanged | Settings/Currencies scenario.                          |
| FX provider unavailable  | Stale/missing rate and no network                          | Manual rate or clear save-blocking error                     | Needs fault injection.                                 |

## Import Source x Result

| Source                  | Good match                                          | Ambiguous                      | Duplicate                         | Ignored/error                                |
| ----------------------- | --------------------------------------------------- | ------------------------------ | --------------------------------- | -------------------------------------------- |
| Wallet CSV              | Queue/post candidates with account/category mapping | Warning and Review candidate   | Skip or count duplicate rows      | Malformed rows reported in preview           |
| Manual SMS paste/import | Parsed candidate with suggested account/category    | Queue for Review with warnings | Duplicate external ref suppressed | OTP/balance/security ignored                 |
| Background SMS          | Auto-post if high confidence and enabled            | Queue to Review                | Duplicate suppressed              | Permission disabled or ignored sender no-ops |
| Notification/email/API  | Candidate with source metadata                      | Queue for Review               | Duplicate suppressed              | Source-specific error/warning                |

## Capture Confidence x Action

| Confidence/state                      | Expected app behavior                                 | Example                                                                |
| ------------------------------------- | ----------------------------------------------------- | ---------------------------------------------------------------------- |
| High confidence and autoPost enabled  | Post automatically and link candidate as auto_posted  | Clear debit SMS with account last-4 and strong merchant/category rule. |
| High confidence and autoPost disabled | Queue pending candidate                               | Conservative default review flow.                                      |
| Medium confidence                     | Queue pending candidate with suggested fields         | Amount/merchant parsed, category uncertain.                            |
| Low confidence                        | Queue with warnings or ignore if non-transaction-like | Generic debit without account/category context.                        |
| Security/balance-only                 | Ignore                                                | OTP, PIN, verification, available balance.                             |
| Duplicate                             | Count/report duplicate, no new candidate              | Same SMS from background plus manual scan.                             |

## Recurrence Frequency x Post Mode

| Frequency | Manual post                                           | Automatic post                           | Edge cases                          |
| --------- | ----------------------------------------------------- | ---------------------------------------- | ----------------------------------- |
| Daily     | Forecast every interval days; user confirms due items | Due items can clear automatically        | Weekend/skip behavior needs QA.     |
| Weekly    | Forecast selected weekly cadence                      | Auto-post on due date                    | Skipped occurrence list.            |
| Monthly   | Bills, subscriptions, salary, EMI, card due           | Auto-record due action or automatic mode | Day-of-month beyond shorter months. |
| Yearly    | Annual insurance/tax/subscription                     | Automatic yearly posting if enabled      | Leap-year/date rollover.            |

## Notification Channel x User Action

| Channel             | Open                                         | Read            | Dismiss                   | Snooze                    | Native delivery                      |
| ------------------- | -------------------------------------------- | --------------- | ------------------------- | ------------------------- | ------------------------------------ |
| Review queue        | Opens Review                                 | Marks item read | Removes from active inbox | Remind later if supported | Requires permission/channel enabled. |
| Scheduled/reminders | Opens Notifications or relevant planned item | Marks read      | Hides item                | Defers reminder           | Due labels for bills/cards/loans.    |
| Budgets/goals       | Opens Planner                                | Marks read      | Hides item                | Defers reminder           | Threshold-based.                     |
| Imports             | Opens Review/Imports                         | Marks read      | Hides item                | Defers if supported       | Import warnings/candidates.          |
| Accounts/activity   | Opens related screen                         | Marks read      | Hides item                | Usually not needed        | Lower priority.                      |

## Permission State x Feature Availability

| Permission state                  | Receipt camera              | Photo attach                   | SMS capture                                        | Native notifications                     | Expected UX                       |
| --------------------------------- | --------------------------- | ------------------------------ | -------------------------------------------------- | ---------------------------------------- | --------------------------------- |
| Granted                           | Works                       | Works                          | Background/manual read works if preference enabled | Native delivery works if channel enabled | Normal flow.                      |
| Denied                            | Show request/error          | Show request/error             | Prompt or explain disabled state                   | In-app inbox still works                 | No crash; actionable message.     |
| Blocked/do not ask                | Open app settings guidance  | Open settings guidance         | Open settings guidance                             | Open settings guidance                   | Device permissions page explains. |
| Not available/platform restricted | Hide or explain unsupported | Picker fallback where possible | Local-only Android feature                         | In-app only                              | Avoid false promises.             |

## UI State x Screen Checks

| State                     | Screens                                                 | Expected result                                                 |
| ------------------------- | ------------------------------------------------------- | --------------------------------------------------------------- |
| Empty ledger              | Home, Transactions, Planner, Calendar, Accounts         | Helpful empty states and primary setup actions.                 |
| Dense ledger              | Home, Transactions, Calendar, Planner, Reports          | No text overlap, no stuck loading, responsive scrolling/search. |
| Long labels               | Accounts, Categories, Currencies, Settings, Add pickers | Ellipsis or wrap without layout break.                          |
| Bottom gesture navigation | Add, tabs, drawers, modals                              | Buttons/keypad remain reachable above Android gesture bar.      |
| Dark/theme/accent change  | All major screens                                       | Contrast remains readable; no one-note accidental theme.        |
| Offline                   | Add, accounts, categories, reports, FX                  | Local actions work; network-only FX refresh reports failure.    |
| Back gesture              | Drawer, Add, Review dialog, pickers, root tabs          | Visible layer dismisses first; root exits to launcher.          |

## Concrete Regression Examples

1. Create INR bank account, GBP prepaid account, and INR credit card. Add GBP 50 purchase on INR card. Expected: GBP original shown, INR equivalent stored, no account-currency mismatch.
2. Import same Wallet CSV twice. Expected: second pass reports duplicates and does not double-create transactions.
3. Send debit SMS and then run manual inbox scan. Expected: one candidate or transaction, duplicate count increases on scan.
4. Send OTP-only SMS. Expected: ignored, no Review candidate.
5. Create monthly card payment rule. Expected: Calendar/Planner/Home/Notifications show scheduled payment; balance moves only when cleared.
6. Create reducing-balance loan and post EMI. Expected: principal reduces loan balance; interest does not reduce principal.
7. Archive used account. Expected: account leaves normal active lists but historical transactions/reports remain valid.
8. Change display currency. Expected: totals convert; stored transaction currency fields remain unchanged.
9. Deny notification permission. Expected: in-app inbox still works and native delivery is skipped gracefully.
10. Press Android Back inside Review approval dialog. Expected: dialog closes before route fallback.
