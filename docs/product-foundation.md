# Product Foundation

## Product goal

Build a personal finance app that feels as fast as an expense tracker, as useful as a budgeting tool, and as structured as a lightweight money operating system.

Current implementation note: the app is mobile-first and local-first today. Cloud sync remains the planned cross-device path, while the active ledger model lives in shared TypeScript packages.

The app should help a user answer five questions quickly:

1. How much money do I have right now?
2. Where did my money go this month?
3. What bills, cards, EMIs, and loans are coming next?
4. How much do I need to save every month to hit my goal?
5. When will I close a loan or clear a credit card if I stay on track?

## Product principles

- Ledger first: every insight must come from clear underlying transactions.
- Multi-account by default: cash, bank, wallet, card, and loan accounts are first-class.
- Planning plus tracking: the app is not only for recording history, but also for future decisions.
- Review before trust: automated capture should land in a review queue when confidence is not high.
- Serious, not gimmicky: the UI should feel dependable and dense enough for real money management.

## Target user

- Individual user managing personal finances across multiple accounts.
- Heavy need for recurring expense tracking, card due dates, EMIs, and savings targets.
- Wants mobile-first daily use for tracking, planning, reporting, and maintenance.

## Core domains

### 1. Accounts

- Cash account
- Bank account
- Wallet account
- Credit card account
- Loan account
- Savings pot or goal-linked account

Each account needs:

- Name
- Type
- Currency
- Opening balance
- Current balance
- Institution or provider
- Billing cycle metadata for cards
- Interest, tenure, and payoff metadata for loans
- Archive state

### 2. Transactions

Transaction types:

- Expense
- Income
- Transfer
- Refund
- Adjustment
- Credit card payment
- Loan repayment

Transaction fields:

- Amount
- Account
- Merchant or counterparty
- Category
- Subcategory
- Notes
- Tags
- Attachments
- Date and time
- Source: manual, import, notification, SMS, rule, recurring
- Review state

### 3. Categories

- User-defined parent categories
- User-defined subcategories
- Separate defaults for expense and income
- Rules can auto-assign category based on merchant or message pattern

Starter expense categories:

- Food
- Transport
- Shopping
- Bills
- Rent
- Health
- Entertainment
- Travel
- Education
- Gifts
- Debt payments

Starter income categories:

- Salary
- Freelance
- Interest
- Refund
- Other income

### 4. Budgets

- Monthly budget by category
- Optional budget by category group
- Planned versus actual spend
- Remaining amount and burn rate
- Overspend alerts
- Carry-forward support later, not in MVP

### 5. Goals

- Create savings goals with target amount and target date
- Choose funding account or source accounts
- Show required monthly savings
- Show current shortfall or surplus
- Support priority levels: critical, high, medium, low

### 6. Credit cards

- Track current outstanding balance
- Separate statement balance from unbilled spend
- Due date and minimum due
- Payment reminders
- Payoff forecast if user only pays a fixed amount

### 7. Loans and EMIs

- Loan principal, rate, term, EMI, start date
- Auto-generated payment schedule
- Remaining principal estimate
- Early payment simulation
- Estimated closure date
- Priority ordering for multiple debts

### 8. Recurring items and reminders

- Recurring expenses
- Recurring income
- Bill reminders
- EMI reminders
- Subscription reminders

### 9. Reporting and insights

- Monthly income versus expense
- Category breakdown
- Account balances
- Net cash position
- Debt outstanding
- Savings goal progress
- Upcoming dues timeline

## MVP scope

Target product scope:

- Authentication and onboarding
- Manual account creation
- Manual transaction entry
- Income, expense, and transfer support
- Categories and subcategories
- Budgeting by month and category
- Goal tracking with monthly required amount
- Credit card due tracking
- Loan and EMI tracker with closure forecast
- Transaction search and filters
- Dashboard with month summary and upcoming dues
- Local-first storage now; cloud sync later

Already implemented mobile surfaces should stay documented through QA evidence rather than moved back into future scope: local ledger, accounts, transactions, transfers, categories, planned records, cards, loans, imports, review queue, widgets, notifications, currencies, and Android automation.

## V1.1 scope

- Android notification-based transaction capture and local native notification delivery
- CSV and bank statement import
- Rule engine for merchant-based categorization
- Reconciliation workflow
- Recurring transactions and bills
- Export to CSV

## V1.2 scope

- Shared household or partner mode
- Subscription detection
- Receipt scan OCR
- AI-assisted categorization and anomaly detection
- Web reporting with deeper analytics

## Explicit non-goals for MVP

- Direct bank login aggregation
- Full multi-user collaboration
- Investment portfolio tracking
- Tax filing workflows
- Automatic SMS ingestion on every platform

## Core workflows

### Onboarding

1. User signs in with Google, Apple later, or email.
2. User selects country, currency, and start-of-month preference.
3. User creates accounts with opening balances.
4. User chooses starter categories.
5. User sets first budgets, cards, loans, and goals.
6. User lands on the dashboard with an empty-state checklist.

### Manual transaction capture

1. Tap quick add.
2. Choose expense, income, or transfer.
3. Enter amount first with the calculator keypad.
4. Pick account.
5. If the merchant charged a different currency than the account, choose purchase currency and let the app show the account-currency equivalent.
6. Pick category and subcategory.
7. Save immediately or expand for status, date, payment method, notes, charges, receipt, and attachment details.

### Assisted transaction capture

1. App receives a candidate transaction from notification, SMS, or import.
2. Parser extracts amount, merchant, timestamp, and account hint.
3. Rule engine suggests account and category.
4. Candidate lands in review queue when confidence is below threshold.
5. User confirms or edits.
6. Transaction posts to ledger.

### Credit card payment flow

1. User records card spend into credit card account.
2. App tracks statement and unbilled balances.
3. When user pays card bill, app records transfer from bank account to credit card account.
4. Dashboard updates due amount and next due date.

### Loan payoff planning

1. User creates loan with principal, interest rate, EMI, and tenure.
2. App builds payment schedule.
3. User can model extra monthly or one-time payments.
4. App recalculates interest saved and closure date.

### Savings goal planning

1. User creates goal with target amount and date.
2. App calculates monthly required contribution.
3. User links one or more funding accounts.
4. App tracks progress and warns when user falls behind.

### Month-end close

1. User reviews uncategorized or unmatched transactions.
2. User reconciles account balances.
3. App highlights overspent budgets and missed targets.
4. User closes month and starts next month with carry-over rules if enabled.

## Mobile information architecture

Bottom navigation:

- Home
- Transactions
- Add
- Planner
- Accounts

Screen responsibilities:

- Home: balances, month summary, due reminders, goal progress, quick actions
- Transactions: feed, search, filters, review queue
- Add: fast manual entry and import shortcuts
- Planner: budgets, goals, cards, loans, bills
- Accounts: balances, account detail, reconciliation

## UI direction

The visual language should feel calm, premium, and operational.

- Tone: trustworthy, clean, slightly dense, not playful
- Layout: strong balance cards on top, compact lists below, clear section hierarchy
- Colors: ink, warm neutral background, emerald for positive, amber for warning, coral for overspend, cobalt for primary actions
- Motion: small, meaningful transitions on add, review, and month close
- Charts: spend by category, income versus expense trend, dues timeline, goal progress
- Typography: strong numeric emphasis for balances and due amounts

## Key screens to design first

1. Onboarding and account setup
2. Home dashboard
3. Add transaction sheet
4. Transaction list and detail
5. Budget overview
6. Goal detail
7. Credit card detail
8. Loan and EMI detail
9. Review queue for automated captures

## Success metrics

- User can finish onboarding in under 5 minutes
- Manual transaction entry in under 10 seconds
- Less than 5 percent of saved transactions need later correction
- User sees all upcoming dues within one screen from home
- User can answer monthly cash flow and debt status without exporting data
