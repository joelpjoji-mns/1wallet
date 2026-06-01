# User Flows

Each flow lists goal, entry points, major steps, variants, success state, and error or edge states.

## Create Account And First Run

Goal: get from fresh install to Home with a usable local ledger.

Entry points: app launch, `/login`, `/signup`, `/onboarding`.

Steps:

1. Startup gate checks secure session and ledger state.
2. New user opens Login in create mode.
3. User enters email/password. If Supabase is not configured, local fallback can create a local user.
4. Onboarding collects profile and use-case preferences.
5. User creates the main account with name, type, currency, and opening balance.
6. User can add extra accounts or skip.
7. Permissions step offers receipt/media/location/SMS/notification-related setup where supported.
8. Finish setup writes ledger preferences and routes to Home.

Success state: Home loads with dashboard widgets, default account, notification bell, and Add FAB.

Variants: returning user login, local fallback login, permission deny/allow, extra account creation.

Known notes: permissions onboarding is functional but visually dense in the 2026-05-30 release pass.

## Add Expense Or Income

Goal: manually post a normal transaction.

Entry points: Home FAB, drawer Add record, transaction/account context actions.

Steps:

1. Open `/add`.
2. Choose Expense or Income.
3. Enter amount with the calculator keypad.
4. Select account.
5. Select category matching the transaction kind.
6. Optionally set date/time, payment method, notes, tags, receipt, and status.
7. Save.

Success state: cleared transaction appears in Transactions and updates relevant account balance.

Variants: pending transaction, scheduled transaction, receipt attachment, note autocomplete, split line items.

Error states: missing amount/account/category, stale FX for foreign purchase, permission denied for receipt action.

## Add Transfer, Card Payment, Or Loan Repayment

Goal: move money between accounts or represent debt repayment.

Entry points: Add Record transfer type, card/loan reminder flows, planned payments.

Steps:

1. Open `/add`.
2. Choose Transfer.
3. Choose transfer purpose: regular transfer, card payment, or loan EMI/repayment.
4. Select source account.
5. Select counter account.
6. Enter amount and, for cross-currency transfer, confirm destination/counter amount and FX rate.
7. Set date/time and status.
8. Save.

Success state: source and counter balances update when cleared; scheduled/pending stays visible without current balance impact.

Variants: INR-to-GBP transfer, bank-to-credit-card payment, bank-to-loan repayment, scheduled future card payment, scheduled EMI.

Error states: same source/counter account, missing counter account, missing FX rate, zero amount.

## Foreign Purchase On A Local Account

Goal: record a purchase made in a foreign currency but posted to an account in another currency.

Example: type 50 GBP on an INR card and show the INR posted value below.

Steps:

1. Open Add Record and choose Expense.
2. Select an INR account.
3. Enter `50` as the main purchase amount.
4. Change purchase currency to GBP.
5. App fetches or reuses a GBP/INR rate if fresh within one hour.
6. UI shows the converted INR posted value below the main amount.
7. Save stores original GBP amount/rate and INR posted amount.

Success state: transaction row and reports can show both original and account/display equivalents.

Error states: missing rate, stale rate refresh failure, unsupported/disabled currency.

## Edit Or Delete Transaction

Goal: correct posted or planned record details.

Entry points: Transactions row, related account/report/calendar row.

Steps:

1. Open `/transaction/[id]`.
2. Edit amount, type, status, account, counter account, category, date/time, currency, notes, payment method, tags, receipt metadata, or flags.
3. Save changes.
4. If deleting, confirm destructive action.

Success state: ledger recalculates balances, lists, widgets, reports, and notifications.

Error states: invalid transfer accounts, missing required category/account, stale FX, delete confirmation cancelled.

## Account Management

Goal: maintain accounts and their reporting visibility.

Entry points: Accounts tab, `/account/new`, `/account/[id]`, onboarding.

Steps:

1. Create or open account.
2. Set type, currency, name, opening balance, institution, icon/color, and notes.
3. Configure include flags and Home visibility.
4. Add match identifiers or message hints if capture routing is needed.
5. Reorder accounts from Accounts tab with drag handles.
6. Archive or delete through confirmation.

Success state: account appears in Home/Accounts/reports according to flags and sort order.

Variants: credit card account, loan account, GBP account, archived account reactivation.

Error states: deleting account with history archives instead; invalid opening balance or duplicate naming constraints.

## Categories And Message Rules

Goal: keep transaction taxonomy useful for entry, reports, and automation.

Entry points: Categories, Add category picker, Import SMS rules.

Steps:

1. Open Categories.
2. Search or browse hierarchy.
3. Create or edit expense/income/transfer/system category.
4. Set parent, icon, color, archive, hidden-in-stats state.
5. In SMS/import rules, map keywords to categories where needed.

Success state: new records and capture candidates can use the category; reports respect hidden/archive rules.

Error states: duplicate name within same parent, archived category no longer available as default new-record option.

## Wallet CSV Import To Review

Goal: bring existing wallet/export data into local ledger safely.

Entry points: Import center, `/import-wallet-csv`.

Steps:

1. Open Import center.
2. Choose Wallet CSV import.
3. Pick CSV file.
4. App analyzes rows, account matches, categories, duplicates, warnings, and transfer pairs.
5. User reviews preview/provisioning summary.
6. Confirm import to create accounts and/or capture candidates.
7. Open Review to approve uncertain candidates.

Success state: data is queued or posted without duplicating repeated imports.

Error states: malformed CSV, unknown account mapping, duplicate rows, unsupported currency, partial import warnings.

## SMS Auto Capture To Review

Goal: convert transaction-like SMS into candidates without blindly writing uncertain ledger records.

Entry points: Auto Capture, Android SMS receiver, manual inbox scan, Import SMS.

Steps:

1. User enables auto capture and grants SMS permission.
2. Incoming SMS triggers native receiver and headless task when background monitoring is enabled.
3. Parser ignores OTP/security/balance-only messages.
4. Parser extracts amount, merchant, date, account hints, transaction type, and category.
5. Duplicate detector checks external reference/raw hash.
6. High-confidence item can auto-post if preferences allow; uncertain item goes to Review.
7. User opens Review, edits candidate if needed, then approves or rejects.

Success state: valid transaction-like SMS appears as posted transaction or review candidate; duplicate/ignored messages do not pollute ledger.

Error states: SMS permission denied, background disabled, ambiguous account/category, parser confidence below threshold, headless task timeout.

## Review Approval

Goal: turn a capture candidate into a trusted ledger transaction.

Entry points: Review, Import center, notification tap, Home review widget/button.

Steps:

1. Open Review.
2. Filter pending/approved/rejected if needed.
3. Select candidate or approve from card.
4. Confirm final fields in approval dialog or open Capture edit.
5. Approve to post; reject/ignore to stop processing.

Success state: transaction is created and linked to candidate; Review count updates.

Error states: missing account, missing category, stale FX, duplicate candidate, back button should close popup before route fallback.

## Planned Payment And Calendar Forecast

Goal: schedule future recurring money events and forecast cashflow.

Entry points: Planned payments, Planner, Calendar, Cards, Loans.

Steps:

1. Open Planned payments.
2. Create new rule with type/kind, amount, account, counter account if needed, category, frequency, start/end, and post mode.
3. Save rule.
4. Forecast occurrences appear in Planned payments, Calendar, Planner, Home widgets, and due notifications.
5. User confirms, skips, edits, disables, or auto-records due occurrences.

Success state: future view reflects planned income/outflow without moving current balances until posted.

Variants: monthly bill, subscription, salary, card payment, EMI, savings transfer, skipped occurrence.

Error states: missing account/category, invalid frequency/day, duplicate demo seed, cross-currency transfer without rate.

## Budget And Goal Planning

Goal: track spending pressure and saving/debt targets.

Entry points: Planner, `/budgets/new`, `/goals/new`, Home widgets.

Steps:

1. Create budget with category, period, amount, rollover/carry settings, and alert thresholds.
2. Create goal with kind, target amount/date, priority, and optional linked category.
3. Add transactions that affect budget/category or goal account.
4. Planner and widgets update progress.
5. Notifications can warn at thresholds where enabled.

Success state: Planner shows on-track/at-risk/over budget and goal progress.

Error states: no category, invalid amount/date, paused budget/goal, excluded transactions.

## Card Due Tracking

Goal: track credit card debt and upcoming payments.

Entry points: Cards, Add Record transfer purpose, Planned payments, Notifications.

Steps:

1. Create or open a credit card account.
2. Schedule card payment manually or through Cards.
3. Planned `card_payment` record appears in widgets, Calendar, Planner, and Notifications.
4. On payment date, mark or post the payment.

Success state: bank balance decreases and card balance receives the payment when cleared.

Error states: missing same-currency payment source, duplicate schedule, scheduled record not posted yet.

## Loan Setup And EMI Forecast

Goal: track loan balance, EMI schedule, and payoff.

Entry points: Loans, New loan, Account detail, Loan forecast.

Steps:

1. Create loan account with principal, disbursal date, rate, method, repayment amount, and schedule.
2. Choose setup mode: track from next or backfill paid installments.
3. Optionally auto-create linked planned payment rule.
4. Loan detail shows next repayment and schedule.
5. Loan forecast compares payoff strategies and extra payment effects.
6. Loan repayment transaction posts principal/interest behavior.

Success state: loan balance and forecast update as repayments post.

Error states: invalid rate/tenure, missing repayment source, wrong currency, principal/interest split mismatch.

## Notifications And Permissions

Goal: keep reminders visible while respecting OS permission choices.

Entry points: Home bell, Notifications, Settings, Device permissions, native notification tap.

Steps:

1. User enables or disables notification channels in Settings.
2. User grants or denies Android POST_NOTIFICATIONS.
3. App creates in-app notifications for due records, review queue, imports, budgets, goals, and account events.
4. Native delivery runs only if permission and preferences allow.
5. User reads, snoozes, or dismisses notifications.

Success state: in-app inbox remains reliable; native notifications deliver only allowed items.

Error states: OS notification denied, channel disabled, quiet hours active, duplicate native delivery ID.

## Theme, Currency, And Settings

Goal: personalize display without corrupting ledger data.

Entry points: Settings, Currencies.

Steps:

1. Change theme mode or accent color.
2. Change display currency or enabled currency list.
3. Refresh exchange rates where needed.
4. Change notification settings or permission shortcuts.
5. Use reset/snapshot actions only after confirmation.

Success state: UI updates without layout overlap; ledger stored amounts remain unchanged.

Error states: FX provider unavailable, permission blocked, destructive reset cancelled.

## Offline And Lifecycle Flow

Goal: keep local-first ledger usable without network.

Steps:

1. User opens app with no network.
2. Manual account/category/transaction operations continue locally.
3. FX refresh and external network actions fail gracefully.
4. App flushes saves on background/inactive.
5. App reloads local store on resume and syncs Android home widgets after debounce.

Success state: local ledger remains available; network-only features communicate clear limitations.
