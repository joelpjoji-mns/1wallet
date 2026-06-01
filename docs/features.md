# Feature Catalog

This catalog goes wider than the MVP. It is the long-form feature list the product can grow into. Use it as a menu, not a checklist. The MVP is defined in [product-foundation.md](product-foundation.md).

Reference signals: BudgetBakers Wallet, YNAB, Money Lover, Spendee, Monefy, Mint-style trackers, MoneyManager, Goodbudget, Buxfer, Firefly III.

## 1. Accounts

### Account types

- Cash
- Bank account (checking, savings)
- Credit card
- Debit card (tied to bank)
- Wallet (Paytm, GPay, PhonePe, PayPal, etc.)
- Prepaid card or gift card
- Loan account (received)
- Lent account (money you lent to someone)
- Investment account (manual valuation only at first)
- Savings goal account
- Overdraft account
- Crypto account (manual)
- Other / custom

### Per-account settings

- Name, icon, color
- Account type
- Currency (per account, not global)
- Opening balance and opening date
- Current balance (computed)
- Institution / bank name
- Last 4 digits or nickname (no full card numbers)
- SMS sender IDs, email domains, UPI IDs, and other safe matching hints for automated capture
- Notes
- Include or exclude from totals
- Include or exclude from budgets
- Include or exclude from reports
- Include or exclude from net worth
- Archive / hide
- Default account flag
- Reconciliation cursor (last reconciled date and balance)
- Statement cycle (cards): cycle start day, due day, grace days, min due percent
- Loan metadata: principal, interest rate, tenure, EMI, start date, lender
- Display order

### Account features

- Multi-currency: each account has its own currency
- Currency management screen for reports currency, display currency, enabled currencies, refresh status, and manual exchange-rate corrections
- Main balance display-currency switch that cycles enabled currencies and updates visible values without rebasing records
- Exchange rates can be refreshed from a provider and manually overridden when bank-posted rates differ
- Account groups (e.g., "My Cards", "Family", "Business")
- Linked accounts (e.g., card linked to bank for auto-payment tracking)
- Account sharing (later) for shared/joint accounts
- Per-account transaction templates
- Per-account default category

## 2. Transactions

### Transaction types

- Expense
- Income
- Transfer between own accounts
- Credit card payment (typed transfer)
- Loan repayment (principal + interest split)
- Refund (linked to original expense)
- Adjustment / opening balance / reconciliation
- Lent money (creates a receivable)
- Borrowed money (creates a payable)
- Investment buy / sell (manual)
- Fee / charge
- Interest earned / paid
- Cashback / reward
- Split with people (group expense)

### Transaction fields

- Amount
- Posted currency and amount (matches the account currency for balance correctness)
- Original purchase amount and currency for foreign spends, e.g. GBP merchant charge posted to an INR card
- Exchange rate used at transaction time, editable when the bank posts a different value
- Counter amount and counter exchange rate for transfers between accounts with different currencies
- Date and time
- Account
- Counter account (for transfers)
- Category
- Subcategory
- Multiple tags (free-form labels)
- Merchant / payee
- Payment method (UPI, card swipe, online, ATM, cheque, NEFT, IMPS, wire, autopay)
- Notes
- Attachments (photos, PDFs, receipts)
- Location (optional, with map pin)
- Status: cleared, pending, scheduled
- Source: manual, recurring, import, notification, SMS, rule, shared
- Confidence score (for auto-captured items)
- Linked transactions (refund-of, split-of, reimbursement-of)
- Reimbursable flag and reimbursement state
- Tax-deductible flag
- Excluded from reports flag
- Person involved (for lend/borrow/split)
- Group / trip (for travel-style grouping)
- Project (for personal projects or freelance gigs)
- Custom fields (user-defined key/value)
- Recurrence rule (if templated)
- Reminder timestamps

### Transaction operations

- Quick add (amount-first flow)
- Detailed add
- Duplicate transaction
- Convert between expense / income / transfer
- Split a transaction across multiple categories
- Split a transaction across multiple people
- Bulk edit (category, tag, account)
- Bulk delete
- Bulk mark as cleared / reconciled
- Move between accounts
- Merge two transactions (e.g., auto + manual duplicate)
- Undo last change
- Search with operators (amount range, date range, category, tag, account, merchant, note text, source)
- Saved filters

## 3. Categories and tags

- Two-level: category and subcategory
- Separate trees for expense and income
- Custom icon and color per category
- Reorder, hide, archive categories
- Merge categories (move all transactions to another)
- Per-category default tags
- Per-category default account
- Per-category budget linkage
- Hidden categories (still selectable but not shown in stats)
- Tags as a flat, multi-select layer over categories
- Tag suggestions based on merchant
- Tag-based reports

## 4. Budgets

- Monthly budgets per category
- Weekly, fortnightly, quarterly, yearly, or custom-period budgets
- Group budgets (one budget across multiple categories)
- Per-account budgets (e.g., cash-only budget)
- Envelope budgeting mode (YNAB-style) as optional
- Rollover unused amount to next period
- Carry overspend to next period
- Budget templates (copy from previous month)
- Multi-month budget plans
- Budget for tags
- Budget alerts at 50%, 80%, 100%, and overspend
- Daily safe-to-spend computation
- Forecast end-of-period spend based on burn rate
- Pause budget (e.g., vacation month)

## 5. Goals

- Savings goal: target amount + target date
- Linked funding accounts
- Required monthly / weekly contribution
- Manual or automatic contribution logging
- Progress chart
- Priority: critical, high, medium, low
- Goal types:
  - Save up (e.g., laptop)
  - Pay off (e.g., card balance)
  - Build up balance (e.g., emergency fund)
  - Recurring goal (e.g., yearly insurance premium)
- Linked to category (e.g., all "Vacation" tagged spend pulls from goal)
- Goal completion celebration
- Goal pause / archive
- Shared goals (later)

## 6. Credit cards

- Statement cycle setup
- Statement balance vs. unbilled spend
- Minimum due
- Total due
- Due date and reminders
- Auto-pay setup tracking
- Payoff plan if paying fixed amount monthly
- Interest projection if paying minimum
- Reward category mapping (optional)
- Card limit and utilization meter
- Multiple cards comparison view

## 7. Loans and EMIs

- Loan principal, interest rate, tenure, EMI, start date
- Auto-generated amortization schedule
- Principal vs. interest split per EMI
- Outstanding balance projection
- Extra payment simulator (one-time and recurring)
- Refinance simulator
- Estimated closure date with and without prepayment
- Multi-loan payoff plan (avalanche / snowball strategy)
- Debt priority ordering
- Loan-to-account mapping (where EMI is debited)

## 8. Recurring and reminders

- Recurring transactions (daily, weekly, monthly, custom)
- Recurring rule end date or end-count
- Auto-post or post-after-confirm
- Bill reminders with snooze
- EMI reminders
- Subscription tracking with renewal alerts
- Income reminders (e.g., expected freelance invoice)
- Unusual-day reminders (next month has 28 vs 31 days)
- Pre-due reminders (e.g., 3 days before)

## 9. Multi-currency

- Per-account currency
- Per-transaction currency override
- Central supported-currency catalog, with app workflows using the user-enabled currency list except onboarding and currency management
- Exchange rate fetch with manual override; transaction add/edit/capture flows refresh missing or stale pairs before saving
- Exchange rates are considered fresh for one hour for save-time conversion and stale-rate warnings
- Historical rate stored on transaction
- Base currency for reports (user setting)
- Display currency for viewing the whole app in another enabled currency without changing stored report/base amounts
- Foreign purchase display in Add Record: selected merchant currency remains the main amount, with account-currency equivalent shown below
- Multi-base currency mode (e.g., INR for daily, USD for investments)
- Currency conversion in transfers
- FX gain / loss tracking on revaluation (later)
- Country detection on travel to suggest local currency

## 10. Automation and capture

### Manual entry assistance

- Amount keypad with calculator
- Recent merchants and categories
- Merchant autocomplete with logos
- Quick category buttons based on history
- Voice entry
- Photo of receipt to attach
- Receipt scanner with OCR (later)

### Import-based capture

- CSV import with column mapping
- Bank statement import (PDF / Excel)
- Bank-specific parsers
- Wallet export import (Money Lover, Wallet by BB, Monefy, Mint exports)
- Duplicate detection on import
- Import history with undo

### Notification capture (Android)

- Read transactional notifications from bank apps and UPI apps
- Match to account by sender, app, or pattern
- Confidence scoring
- Auto-post above threshold, queue below threshold
- Per-app enable/disable
- Native local notifications for due items and important inbox items when Android notification permission is granted

### SMS capture (Android)

- Optional and policy-gated
- Local parsing only; no raw SMS uploaded
- Read-only SMS access; 1wallet is not the default SMS app and does not show an all-SMS inbox
- Auto Capture sidebar surface for SMS now and email later
- Configurable trigger keywords decide which SMS are transaction-like before parsing
- Per-sender enable/disable
- Bank-specific templates with regex
- Confidence scoring and review queue
- High-confidence categorized matches can auto-post; uncertain matches stay in Review
- Auto-detect account from last 4 digits
- Auto-detect merchant from message body
- Auto-detect category from rules
- Auto-detect transfer vs. expense
- Ignore OTP, balance enquiry, marketing, ads

### Email capture (later)

- Forwarded receipt parsing (Gmail label or forwarding address)

### Rules engine

- IF merchant contains X THEN category = Y
- IF amount > N AND category = Food THEN tag = "dining out"
- IF account = HDFC THEN currency = INR
- Rule priority and conflicts
- Test rule on history
- Disable / enable rule

### Review queue

- All low-confidence and auto-captured items land here
- Approve, edit, reject
- Bulk approve
- Sender/app trust learning over time

## 11. Reporting and insights

### Dashboards

- Today summary
- This month summary
- Net worth widget
- Cash flow widget (income vs expense)
- Upcoming dues widget
- Top categories widget
- Top merchants widget
- Goal progress widget
- Debt outstanding widget
- Recent transactions widget
- Account balances widget
- Subscription cost widget
- Foreign currency exposure widget

### Charts

- Pie chart: category breakdown
- Donut chart: account share
- Bar chart: monthly income vs expense
- Line chart: net worth over time
- Line chart: account balance over time
- Stacked bar: category trend over months
- Heatmap: spend by day of month
- Sankey: where money flows (income -> categories)
- Calendar view: spend per day
- Treemap: category and subcategory weight

### Reports

- Monthly statement (per account or all)
- Category report (per period)
- Subcategory drilldown
- Tag report
- Merchant report
- Project / trip report
- People report (who owes whom)
- Cash flow report
- Net worth report
- Debt report
- Subscription report
- Tax-deductible report
- Custom report builder with filters and grouping

### Insights (later, AI-assisted)

- Spend anomaly detection
- Subscription drift detection ("Netflix went up")
- Recurring detection from history
- Forecast next month's spend
- Suggest budget cuts
- Goal pace warnings
- Cashflow gap warnings ("you may run short on day 24")

## 12. Widgets

### In-app widgets (dashboard cards)

- Balance card (per account or total)
- Net worth card
- Cashflow card
- Budget burn card
- Top categories
- Top merchants
- Upcoming dues
- Goal progress
- Debt payoff progress
- Subscriptions card
- Recent transactions
- Foreign currency exposure
- Reminders / scheduled
- Last reconciliation status
- Quick add shortcut

### Mobile home-screen widgets (OS-level)

- Quick add transaction (tap to open add sheet)
- Today's spend
- This month's spend vs budget
- Net worth
- Next bill / EMI due
- Top category for the month
- Recent 3 transactions
- Goal progress

### Web dashboard widgets

- Same as in-app, but with drag-and-drop layout and more density

## 13. Search and filters

- Global search (amount, merchant, note, tag, category)
- Filter by date range with presets
- Filter by amount range
- Filter by account, category, tag, person, project
- Filter by source (manual, SMS, notification, import)
- Filter by status (cleared, pending, scheduled, excluded)
- Saved searches
- Smart lists ("Last week's food", "Unreviewed", "Above 5000 INR")

## 14. Reconciliation

- Per-account reconciliation flow
- Statement balance entry
- Match cleared transactions
- Flag missing transactions
- Auto-suggest adjustment entry
- Reconciliation history

## 15. Sharing and collaboration (later)

- Shared wallet (couple / family)
- Per-user roles: owner, editor, viewer
- Shared categories and budgets
- Personal vs shared transactions
- Group / trip mode for travel splitting
- Settle-up calculations (Splitwise-style)
- Comments on transactions

## 16. Security and privacy

- Biometric / PIN lock on app open
- Auto-lock after inactivity
- Per-account hide-amounts toggle
- Privacy mode (blur amounts in app preview)
- Encrypted local storage
- 2FA on account login
- Session management
- Device list with revoke
- Export all data
- Delete account and data
- Audit log of sensitive actions

## 17. Settings and customization

- Theme: light, dark, system
- Accent color
- Compact vs comfortable density
- Start day of week
- Start day of month
- Number format and grouping
- Date format
- Default account, default category
- First-screen choice
- Notifications config per category
- Data export schedule
- Backup destination (cloud / local)
- Language

## 18. Notifications

- Home bell opens the notification inbox only; notification configuration belongs in Settings
- Notification rows can be dismissed without changing the underlying ledger item
- Bill due reminder
- Budget threshold reached
- Large transaction alert
- Unusual spend alert
- Goal milestone
- Statement available
- Sync issues
- Review queue has items
- Currency exchange rate alert (optional)
- Weekly recap
- Monthly recap

## 19. Import / export and interoperability

- CSV export (filtered)
- Excel export
- PDF report export
- JSON full export
- iCal export of due dates
- Webhook out (later) on transaction events
- Public API (later)
- Apple Shortcuts / Siri intent
- Android intents and Tasker support
- Wear OS / Watch quick add (later)

## 20. Platform integrations

- Google Drive backup
- iCloud backup
- Dropbox backup
- Calendar reminders
- Contacts (for people involved)
- Maps (for location)
- Camera (for receipts)
- Files / Photos (attachments)

## 21. Onboarding extras

- Country and currency picker
- Pre-built category packs
- Bank parser pack selection
- Sample data load (for demo / preview)
- Restore from previous backup at first launch

## 22. Localization

- Multiple UI languages
- Locale-aware number, date, currency formatting
- Right-to-left layout support
- Region-specific category packs (e.g., India: UPI, Mutual fund SIP)

## 23. Accessibility

- Screen reader labels for amounts and categories
- High-contrast theme
- Larger text mode
- Color-blind safe palettes
- Reduced motion mode
- Voice input

## 24. Performance and reliability

- Offline-first
- Background sync
- Conflict resolution
- Sync status indicator
- Crash-safe writes
- Rollback on failed sync

## 25. Power-user features

- Keyboard shortcuts (web)
- Command palette (web)
- Bulk operations
- Smart import (paste a line, parse it)
- Custom dashboards
- Custom report builder
- Webhooks and API (later)
- Multi-profile (personal, business, side project)

## Differentiators worth shipping

These are the features that move this app from "yet another tracker" to genuinely useful:

- Multi-currency that actually respects per-account currency
- Loan and EMI forecasting with prepayment simulator
- Review queue for automation, not blind auto-add
- Multi-account transfers and card payments modeled correctly
- Strong reconciliation flow
- Project / trip / person grouping on top of categories
- Real net worth over time, not just monthly spend
- Cashflow gap warnings before the user runs short
- Mobile home-screen widgets that are actually useful

## Explicit anti-features

- Do not auto-aggregate bank accounts via screen scraping
- Do not import raw SMS to the cloud
- Do not show ads inside the financial workflows
- Do not silently auto-post low-confidence captures
- Do not require a subscription for the core ledger
