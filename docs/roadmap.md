# Roadmap

## Recommended build order

Do not try to build everything at once. This product will sprawl if the ledger foundation is not stable first.

Current status: the mobile app already contains substantial Phase 1 through Phase 3 work. Treat this roadmap as the product sequencing map and use `implementation-status.md` plus the QA logs for current proof of implementation.

## Phase 0: Discovery and design

Outcome:

- Finalize product scope
- Lock MVP
- Define navigation and key screens
- Define data model and architecture

Deliverables:

- Product spec
- Technical architecture
- Wireframes for core screens
- Design tokens and UI direction

Estimated effort for one developer:

- Full-time: 1 to 2 weeks
- Part-time: 2 to 4 weeks

## Phase 1: MVP mobile ledger

Outcome:

- A user can sign in, create accounts, log transactions, and see money clearly

Features:

- Auth
- Onboarding
- Accounts
- Manual transactions
- Categories and subcategories
- Transfers
- Dashboard
- Search and filters
- Local-first persistence and future sync boundary

Estimated effort for one developer:

- Full-time: 4 to 6 weeks
- Part-time: 6 to 10 weeks

## Phase 2: Planning and liabilities

Outcome:

- The app becomes more than a tracker and starts helping with decisions

Features:

- Budgets
- Savings goals
- Credit card due tracking
- Loans and EMI schedules
- Debt payoff forecast
- Recurring reminders

Estimated effort for one developer:

- Full-time: 4 to 6 weeks
- Part-time: 6 to 10 weeks

## Phase 3: Automation and review queue

Outcome:

- The app reduces manual entry without corrupting the ledger

Features:

- Android notification capture
- Android native local notifications
- CSV and statement import
- Rules engine
- Review queue
- Reconciliation flow
- Policy-gated local SMS capture for Android builds where that permission model is acceptable

Estimated effort for one developer:

- Full-time: 3 to 5 weeks
- Part-time: 5 to 8 weeks

## Phase 4: Web companion

Outcome:

- Larger-screen workflows become easier than mobile for power tasks

Features:

- Reporting
- Bulk edits
- Import center
- Rules management
- Settings and exports

Estimated effort for one developer:

- Full-time: 3 to 5 weeks
- Part-time: 5 to 8 weeks

## MVP release checklist

- Auth is stable
- Data sync is reliable
- Transfers do not double count
- Card payments do not double count
- Goal progress math is correct
- Loan closure forecast is explainable
- Dashboard numbers match underlying transactions
- Empty states teach the workflow clearly

## Biggest product risks

- Too much scope before ledger stability
- Over-reliance on SMS-based automation
- Weak account and transfer modeling causing broken reports
- Poor review workflow causing mistrust in automation
- Trying to ship mobile and web parity too early

## What to do next

1. Keep high-risk mobile flows covered by focused QA: Add Record, currencies/FX, notifications, automation, imports, account balances, and release startup.
2. Decide the cloud-sync contract before treating the Postgres schema as production truth.
3. Continue mobile visual polish and Android release validation before expanding the web companion.
