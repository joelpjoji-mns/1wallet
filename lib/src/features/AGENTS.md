# `lib/src/features/` — Application Features Overview

## 🎯 Role & Overview
The `features/` directory contains screen-level UI and user workflows for 1Wallet. Each feature represents a cohesive functional domain organized into its own dedicated subdirectory.

---

## 🗂️ Feature Modules Catalog

| Directory | Domain Description | Detailed Guide |
| :--- | :--- | :--- |
| `accounts/` | Account list, creation, editing, and secure details | [accounts/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/features/accounts/AGENTS.md) |
| `calendar/` | Monthly financial calendar & daily forecast projection | [calendar/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/features/calendar/AGENTS.md) |
| `capture/` | Receipt OCR scanning, review queue, SMS reader & diagnostics | [capture/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/features/capture/AGENTS.md) |
| `cards/` | Credit/debit card visualization and payment planning | [cards/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/features/cards/AGENTS.md) |
| `categories/` | Category hierarchy tree, budget allocations & icon picker | [categories/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/features/categories/AGENTS.md) |
| `common/` | Shared scaffolds, pickers, and reusable feature widgets | [common/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/features/common/AGENTS.md) |
| `currencies/` | Multi-currency FX management & primary currency selector | [currencies/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/features/currencies/AGENTS.md) |
| `home/` | Main dashboard, modular widget cards, summary metrics | [home/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/features/home/AGENTS.md) |
| `imports/` | Bank statement import screens (PDF, CSV) | [imports/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/features/imports/AGENTS.md) |
| `launch/` | Brand splash screen and initialization sequence | [launch/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/features/launch/AGENTS.md) |
| `loans/` | Loan management, debt amortization & payoff simulation | [loans/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/features/loans/AGENTS.md) |
| `login/` | Google sign-in and offline-only ("Local Wallet") mode entry | [login/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/features/login/AGENTS.md) |
| `main/` | Main shell, navigation bar, side drawer & navigation rail | [main/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/features/main/AGENTS.md) |
| `notifications/` | Local notifications manager and budget alerts | [notifications/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/features/notifications/AGENTS.md) |
| `onboarding/` | First-run setup wizard and default wallet creation | [onboarding/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/features/onboarding/AGENTS.md) |
| `planner/` | Envelope budgeting and future expense allocations | [planner/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/features/planner/AGENTS.md) |
| `recurring/` | Recurring payment rules, subscriptions & scheduled bills | [recurring/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/features/recurring/AGENTS.md) |
| `reports/` | Financial analytics, spending breakdown & trend charts | [reports/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/features/reports/AGENTS.md) |
| `routes/` | Route definitions and screen factories for GoRouter | [routes/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/features/routes/AGENTS.md) |
| `settings/` | User preferences, data backup/restore, permission setup, offline mode card & Google upgrade flow | [settings/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/features/settings/AGENTS.md) |
| `sync/` | Cloud sync status, manual sync triggers & conflict screen | [sync/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/features/sync/AGENTS.md) |
| `transactions/` | Transaction listing, creation calculator & detail editor | [transactions/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/features/transactions/AGENTS.md) |
| `updates/` | In-app software update checker and release notes modal | [updates/AGENTS.md](file:///c:/Users/Joel/Documents/Github/1wallet/lib/src/features/updates/AGENTS.md) |

---

## 🛡️ Critical Feature Architecture Conventions

1. **Riverpod Consumption**:
   - Use `ConsumerWidget` or `ConsumerStatefulWidget`. Read values using `ref.watch(provider)` for reactive UI, or `ref.read(provider)` in callbacks.
2. **Selectors Over Raw Loops**:
   - Never compute balances or filter transaction lists manually in widget `build()` methods. Always utilize selectors from `lib/src/ledger/ledger_selectors.dart` to maximize caching and minimize unnecessary rebuilds.
3. **Responsive & Adaptive Shell**:
   - Screen layouts must adapt to both portrait mobile phones and wide desktop/tablet screens.
