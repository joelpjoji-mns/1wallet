# Feature Catalog

This is the implementation-focused feature catalog. It intentionally separates current app behavior from the broader wishlist in `docs/features.md`.

## Accounts

Status: `Implemented`, `QA verified` for main list/reorder/onboarding account, `Needs verification` for every account-type combination.

- Supports cash, bank, credit card, debit card, wallet, prepaid, loan, lent, investment, savings goal, overdraft, crypto, and other account types.
- Each account has its own currency, opening balance, opening date, icon/color, institution, optional nickname, sort order, group name, and notes.
- Visibility flags control totals, budgets, reports, net worth, and Home display.
- Accounts can be archived. Delete is expected to remove unused accounts and archive used accounts so history remains valid.
- Match identifiers and message source hints help SMS/email/notification capture route messages to accounts.
- Loan accounts can store principal, rate, repayment source, repayment schedule, setup mode, and linked planned-payment rule metadata.

Key screens: [pages.md](pages.md) Accounts, New account, Account detail/edit, Loans.

## Transactions And Add Record

Status: `Implemented`, `QA verified` for route visual, selected account, receipt entry, note autocomplete, `Needs verification` for the full matrix.

- Add Record supports expense, income, transfer, adjustment, card payment, loan repayment, pending records, scheduled records, receipt attachments, notes, tags, date/time, category, account, and currency fields.
- Transactions support sources from manual entry, recurring, import, notification, SMS, email, rule, shared, and API paths.
- Transaction statuses are cleared, pending, scheduled, and void.
- Transaction edit and capture edit reuse Add-style selector rows and picker patterns.
- Receipt entry supports file, photo library, and camera paths; OCR extraction is still a known limitation.
- Notes autocomplete can fill repeated merchant or transaction notes from history.

Key screens: Add Record, Transactions, Transaction detail/edit, Capture edit.

## Categories

Status: `Implemented`, `QA verified` for expanded taxonomy fixtures, `Needs verification` for manager editing.

- Categories are hierarchical and typed as expense, income, transfer, or system.
- Categories have icon, color, archive, hidden-in-stats, and sort order fields.
- Archived categories should not appear as primary choices for new records but remain valid for historical transactions.
- Expanded bill, EMI, finance, income, Indian wallet, and UK-style taxonomy entries are seeded for useful categorization.
- SMS/import category matching can use custom rules, default rules, merchant defaults, and category name matching.

Key screens: Categories, Add category picker, Import SMS rules, Review.

## Currencies And FX

Status: `Implemented`, `QA verified` for Currencies screen and visual FX surfaces, `Needs verification` for all save combinations.

- Central catalog supports INR, USD, EUR, GBP, AED, SGD, JPY, AUD, and CAD.
- Default enabled currencies are INR, USD, EUR, and GBP.
- User workflows should use enabled currencies, while the full supported catalog is for add/management flows.
- Display currency is separate from base currency.
- FX rates use `frankfurter.app` and are treated as fresh for one hour.
- Foreign purchase records can store original amount/rate and posted account-currency amount.
- Cross-currency transfers can store counter amount/rate for the destination account.

Key screens: Currencies, Add Record, Transactions, Reports, Home widgets.

## Review Queue And Capture Candidates

Status: `Implemented`, `QA verified` for empty state, back behavior, background SMS review path, `Needs verification` for all candidate edit combinations.

- Capture candidates can come from SMS, email, notification, import, API, and other transaction sources.
- Candidate statuses are pending, approved, rejected, ignored, and auto_posted.
- Candidates carry parsed amount, original amount, merchant, location, notes, payment method, tags, occurred date, suggested account, suggested counter account, suggested category, suggested type, confidence, warnings, and external reference.
- Review keeps cards compact and uses an approval dialog for final fields.
- Approval posts a ledger transaction; rejection/ignore keeps the source trail without posting.

Key screens: Review, Capture edit, Import center, Auto Capture, Notifications.

## Imports And Wallet CSV

Status: `Implemented`, `QA verified` for prior CSV import hardening, `Needs verification` for current release UI path.

- Import center provides entry points for Wallet CSV, SMS import/rules, and review queue.
- Wallet CSV import analyzes file rows, matches or provisions accounts, detects duplicates, identifies transfer pairs, and queues candidates.
- Import batches track source, status, row count, candidate count, duplicate count, transfer pair count, warning count, and file names.
- Re-import should be duplicate-safe through semantic matching and external references.

Key screens: Imports, Import Wallet CSV, Review.

## SMS And Auto Capture

Status: `Implemented`, `QA verified` for parser fixtures, background SMS, duplicate/ignore filters, manual scan, `Known limitation` for Play Store SMS policy.

- Android SMS capture is local-only and permission gated by READ_SMS/RECEIVE_SMS plus user preferences.
- Headless SMS task parses incoming messages when background monitoring is enabled.
- Trigger keywords gate transaction-like messages.
- OTP, verification, password, PIN, and balance-only messages are ignored.
- Account matching uses last-4 fragments and stored account match identifiers.
- Category matching uses custom rules, default rules, merchant defaults, generic fallback, and category names.
- Manual inbox scan reports posted/queued/duplicate/ignored counts and should not display the full inbox.

Key screens: Auto Capture, Import SMS, Review, Device permissions.

## Notifications

Status: `Implemented`, `QA verified` for Home bell list-only behavior and focused release logs, `Needs verification` for every native delivery/channel combination.

- Notification bell opens the notification inbox, not a settings page.
- Notification settings live in Settings.
- Native local notifications use `expo-notifications` when Android permission is granted.
- Notification preferences include channels such as review queue, scheduled reminders, budgets, goals, accounts, and imports.
- Notifications can be read, dismissed, snoozed, and delivered natively once per tracked delivery ID.

Key screens: Notifications, Settings, Device permissions, Home.

## Recurring And Planned Payments

Status: `Implemented`, `QA verified` for several recurring/card/loan runs, `Needs verification` for full create/edit/detail path after cleanup.

- Future generation rules represent daily, weekly, monthly, and yearly planned payments.
- Rules can represent income, expense, transfer, card payment, loan EMI, bills, subscriptions, savings transfers, and other plans.
- Rules can have manual or automatic post modes.
- Forecast occurrences appear in Calendar, Planner, Home widgets, and Planned payments.
- Due scheduled records can be auto-recorded as cleared recurring transactions.
- Skipped occurrences are supported by planned payment data structures.

Key screens: Planned payments, New planned payment, Planned payment detail/edit, Calendar, Planner.

## Calendar And Planner

Status: `Implemented`, `QA verified` for calendar grid and dense forecast stress, `Needs verification` for every budget/goal operation.

- Calendar combines actual records, scheduled records, and rule-based forecasts by month.
- The month grid uses explicit week rows to avoid Sunday wrapping.
- Planner summarizes budgets, goals, planned payments, upcoming pressure, and planning widgets.
- Budgets support periods, thresholds, rollover, carry overspend, and pause state.
- Goals support save/pay-off/build-up/recurring kinds, target amount/date, priority, pause, and complete state.

Key screens: Calendar, Planner, New budget, New goal, Planned payments.

## Cards

Status: `Implemented`, `QA verified` in scheduled card-payment scenarios, `Needs verification` for current release card UI.

- Credit card accounts can appear in Cards with debt and due/payment planning.
- Card payment records are transfer-like transactions from a source account to the credit card account.
- Scheduled `card_payment` records power reminders, widgets, and due summaries.

Key screens: Cards, Add Record transfer purpose, Planned payments, Notifications.

## Loans And EMI

Status: `Implemented`, `QA verified` for loan tests and some scheduling fixes, `Needs verification` for full loan setup/edit/forecast UI.

- Loan types include personal, home, vehicle, education, business, gold, BNPL, overdraft, lent, and other.
- Interest methods include reducing balance, flat, and interest only.
- Loan setup can track from next repayment or backfill paid installments.
- Loan repayment records can link to planned payment rules.
- Loan forecast can calculate EMI schedule, principal/interest split, payoff timing, and scenario comparison.

Key screens: Loans, New loan, Loan detail/edit, Loan forecast, Add Record loan repayment.

## Reports

Status: `Implemented`, `Needs verification` for current release correctness.

- Reports summarize net worth, cashflow, account balances, and categories.
- Report totals should respect account/report inclusion flags and display currency conversion.
- Transactions can be excluded from reports.

Key screens: Reports, Currencies, Accounts.

## Settings, Theme, Permissions, And Snapshot

Status: `Implemented`, `QA verified` for settings visual pass and permission manifest audits, `Needs verification` for every runtime permission denial path.

- Settings manages theme mode, accent, notification settings, locale/preferences, feature hub shortcuts, reset/destructive actions, and sign-out-adjacent app settings.
- Theme supports system/light/dark/AMOLED-style preferences and Material You dynamic source color when available.
- Device permissions exposes Camera, Photos, Location, and notification permission guidance.
- Wallet snapshot supports local ledger snapshot/reset/restore-style maintenance actions; destructive actions require confirmation and should be tested on demo data.

Key screens: Settings, Device permissions, Wallet snapshot.

## Android Home Widgets

Status: `Partially implemented`, `Known limitation` for OS widget feature completeness.

- Native Android AppWidget providers and JS sync bridge exist in the repo.
- In-app Home widgets are implemented and heavily used.
- OS-level widget behavior should be verified separately before treating it as shipped.
