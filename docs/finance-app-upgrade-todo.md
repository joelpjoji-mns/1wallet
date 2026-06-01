# Finance App Upgrade Todo

This checklist tracks the mobile-first rebuild requested for 1wallet. Work through it in small validated slices; do not batch risky data migrations with large UI rewrites.

## Phase 1: Add Record And Pickers

- [x] Confirm category edit APIs are present in ledger/state.
- [x] Extract a shared Add-style record selector row for Add Record and Transaction Edit.
- [x] Extract reusable account/category picker overlays from `apps/mobile/app/add.tsx`.
- [x] Replace category picker tree clutter with drill-down navigation by parent/subcategory.
- [x] Keep category search across all levels with breadcrumb results.
- [x] Keep inline add/edit/subcategory actions inside the picker without losing Add Record draft state.
- [x] Make Add Record fast-entry view non-scrolling on normal Android screens.
- [x] Move Account/Category or From/To selectors into compact left/right buttons just above the keypad.
- [x] Add swipeable right-side Details panel with a bookmark-style pull tag so date, payment method, notes, and charges do not push the keypad down.
- [x] Preserve calculator behavior: digits, decimal, clear, backspace, sign, percent, operators, equals.
- [x] Smoke expense, income, transfer, charge, and picker flows on Android.

## Phase 2: Categories

- [x] Enrich default categories with curated parents, subcategories, icons, and colors.
- [x] Backfill missing icons/colors for existing categories without breaking transaction history.
- [x] Add safe known-category parenting where it does not create duplicates.
- [ ] Rework Categories screen into a cleaner drill-down manager.
- [ ] Move row actions behind contextual controls instead of showing every action at once.
- [ ] Validate duplicate prevention, archive/restore, hidden-in-stats, and icon fallback.

## Phase 3: Transactions

- [x] Rebuild transaction edit with Add-style selector buttons and shared pickers.
- [x] Replace Transaction Edit's custom type picker with the shared full-screen option-list picker.
- [x] Move advanced transaction metadata into a details tab or section.
- [x] Replace transaction edit type chips with one compact selector that opens a focused type picker.
- [x] Reuse the full-screen account picker for source account and destination account changes.
- [x] Reuse the drill-down category picker for category changes and inline category creation/editing.
- [x] Keep transaction drafts intact when opening account/category/type pickers.
- [x] Replace transaction list chip clutter with compact selector filters.
- [x] Add full-screen filter sheets for type, account, category, date, and status.
- [x] Add saved filter summaries so the list shows active Type, Account, Category, Date, and Status clearly.
- [x] Improve transaction rows with account path, category breadcrumb, source/status metadata, notes, and transfer direction.
- [x] Rework Calendar into a fixed no-scroll month grid that fits the tab viewport.
- [x] Show each calendar day with green income above red spending and include scheduled records in forecast totals.
- [ ] Verify edit/save/delete updates balances and transaction list rows.

## Phase 4: CSV Import

- [x] Inventory `importdata/wallet_records2023.csv`, `wallet_records2024.csv`, `wallet_records2025.csv`, and `wallet_records2026.csv` before mutating app data.
- [x] Summarize all four Wallet CSV files from `importdata/`.
- [x] Show row counts, date ranges, account names, category names, currencies, payment types, labels, transfer pairs, duplicates, unknowns, and invalid rows.
- [ ] Derive app account names and aliases from CSV data instead of hardcoding guesses.
- [ ] Summarize every CSV column and identify fields not yet mapped into the ledger.
- [ ] Build category mapping against parent/subcategory taxonomy with ambiguous matches surfaced for review.
- [ ] Add account/category mapping before queueing candidates.
- [ ] Replace hardcoded account aliases with preview-scoped or persisted mappings.
- [x] Queue safe rows through the review flow.
- [x] Support importing all four CSV files in one reviewed batch.
- [x] Preserve raw CSV row payloads, row numbers, file names, and external refs for audit/dedup.
- [ ] Handle transfers, card payments, loan payments, fees, refunds, income, and cash movements accurately.
- [x] Add reset-and-import only behind explicit confirmation after preview.
- [ ] Verify repeat imports queue zero duplicates.

## Phase 5: Home Widgets And Charts

- [ ] Add an Expo-compatible SVG chart foundation.
- [ ] Build line/area charts with x-axis labels, y-axis values, grid lines, point markers, and selected value display.
- [ ] Add accurate balance, cashflow, category, debt, and forecast history selectors.
- [ ] Base chart history on actual transactions, opening balances, exchange rates, and account filters; do not use decorative fake lines.
- [ ] Add selectable chart points with exact date/value readouts.
- [ ] Add empty/loading/error chart states with useful recovery actions.
- [ ] Replace simple bars/lines in widgets with real charts where useful.
- [ ] Add home account selection; tap account filters widgets below.
- [ ] Long-press account tile opens account settings.
- [ ] Show an All accounts option and a clear selected-account state on Home.
- [ ] Make every lower Home widget respect the selected account where the metric supports it.
- [ ] Make list-heavy widgets internally scrollable inside stable cards.
- [ ] Let only list-heavy widgets scroll inside the card; keep summary/chart widgets fixed-height.
- [ ] Add widget size modes where useful: compact, medium, wide.
- [ ] Add widgets for debt payoff, loan priority, account history, spending velocity, cash runway, EMI, subscriptions, net worth forecast, import review health, and currency rate watch.
- [ ] Add widgets for forecast center, spending anomaly alerts, refund tracking, recurring income, upcoming bills, travel/FX exposure, and automation inbox.

## Phase 6: Loans And Debts

- [ ] Add account-linked loan metadata model.
- [ ] Support fresh loans and mid-way existing loans.
- [ ] Store principal, current balance, annual interest, EMI, start date, lender, due day, priority, and payoff preferences.
- [ ] Let mid-way loans capture original start date, already-paid installments, current outstanding balance, and remaining tenure.
- [ ] Add recurring EMI/payment templates.
- [ ] Support extra monthly payments and one-time prepayments.
- [ ] Compare avalanche, snowball, custom priority, and close-by-date payoff strategies.
- [ ] Show interest saved, payoff date, months remaining, total interest, next due date, and recommended extra payment.
- [ ] Add debt priority list across loans, credit cards, overdrafts, and borrowed/lent accounts.
- [ ] Support marking loans as closed while preserving history.
- [ ] Add payoff forecast charts and loan/debt home widgets.

## Phase 7: Currency And FX

- [x] Add enabled currencies and FX refresh settings.
- [x] Persist exchange rates through existing ledger FX services.
- [x] Add Currencies screen with base currency, display currency, enabled currencies, last refreshed date, provider, and refresh button.
- [x] Make mobile currency pickers use the central currency catalog and Currencies-managed enabled list.
- [x] Refresh missing or stale exchange rates before add/edit/capture saves; current freshness window is one hour.
- [x] Store stale-rate metadata and display warnings when conversion may be inaccurate.
- [x] Warn when rates are missing or stale.
- [ ] Add a fully swappable/mockable exchange-rate provider abstraction beyond the current `frankfurter.app` bridge.
- [ ] Apply rates consistently in widgets, reports, imports, and account totals.

## Phase 8: Capture And Automation

- [x] Define notification/SMS/manual text parser interface.
- [x] Parse amount, merchant, account hint, type, payment method, date, and confidence into capture candidates.
- [x] Route uncertain automated capture through Review first.
- [x] Implement notification/manual capture before invasive SMS inbox parsing.
- [x] Add Android SMS parsing only behind explicit privacy permission, trusted senders, and an off switch.
- [x] Add SMS parser preview/import surfaces with sample-message style confidence feedback.
- [x] Keep raw SMS/notification payloads local-only and avoid cloud upload.
- [x] Add trusted sender/account hints, parser rules, category rules, and duplicate detection.
- [x] Add native local notification delivery and notification tap routing for important inbox items.
- [ ] Upgrade Rules screen to editable categorization rules.

## Phase 9: Themes And Visual Polish

- [x] Add a reusable full-screen option-list picker for one-of-many mobile choices.
- [x] Replace inline picker piles in Settings/Profile preferences, Onboarding, New Account, New Budget, Dashboard Widgets, Categories, Planner, and Accounts.
- [ ] Add AMOLED theme next to System, Light, and Dark.
- [ ] Audit every screen for text, input, chip, selected, disabled, error, snackbar, and card colors.
- [ ] Audit Add Record, Transaction Edit/List, Categories, CSV Import, Review, Home, Accounts, Account Detail, Planner, Reports, Loans, Recurring, Rules, Settings, Onboarding, Login, and Signup.
- [ ] Add proper app icon, adaptive icon, splash image, and notification icon assets.
- [ ] Remove generic visual placeholders from primary UI.
- [ ] Validate MaterialCommunityIcons names and fallbacks for every persisted account/category icon.
- [ ] Apply Roboto/Roboto Mono consistently to text and numeric values.
- [ ] Validate all screens in Light, Dark, and AMOLED on Android.

## Phase 11: Product Feature Backlog

- [ ] Forecast center for cash runway, net worth forecast, budget risk, and recurring income prediction.
- [ ] Subscription detector and upcoming renewal widget.
- [ ] Merchant intelligence with common category/payment method suggestions.
- [ ] Spend anomaly alerts and unusual transaction review.
- [ ] Refund tracking and expected refund reminders.
- [ ] Travel/FX trip mode with temporary currencies and trip budgets.
- [ ] Privacy screenshot mode for hiding balances.
- [ ] Household/shared budget mode after local-first single-user flows are stable.
- [ ] Receipt attachment plan with local storage first and optional cloud sync later.
- [ ] Goal-aware surplus recommendations: debt payoff, emergency fund, investment, or savings goal.

## Phase 10: Final Validation

- [x] Run `pnpm typecheck`.
- [x] Run `pnpm lint`.
- [x] Run `pnpm build`.
- [ ] Run Expo dependency check under Node 20.
- [x] Verify Android Metro bundle returns HTTP 200.
- [ ] Smoke Add Record, Categories, Transactions, CSV Import, Review, Home widgets, Loans, Currency, Settings, Accounts, Reports, Recurring, Rules, and navigation back behavior.
