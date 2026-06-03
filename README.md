# 1wallet

Local-first personal finance app with budgeting, expense tracking, savings goals, credit cards, loans, multi-currency records, and assisted transaction capture.

The mobile app is the active product surface today. The current ledger runs through shared TypeScript packages and local persistence, with Firebase added for Google sign-in, cloud restore, and periodic snapshot sync.

## Product direction

- Mobile-first personal finance app focused on Android delivery.
- Multi-account support for cash, bank accounts, wallets, credit cards, loans, and savings pots.
- Track expenses, income, transfers, budgets, recurring bills, EMIs, and savings goals.
- Assist transaction capture through manual entry, imports, Android notifications, and policy-safe automation.
- Treat automation as a review workflow, not a blind write to the ledger.

## Recommended stack

- Mobile: React Native with Expo development builds and TypeScript
- Current data path: local-first ledger state with shared domain, ledger, state, validation, and UI packages
- Sync/backend path: Firebase Auth and Firestore metadata plus chunked ledger snapshots
- Shared code: Turborepo monorepo with TypeScript packages

## Why this direction

- React Native with Expo keeps Android delivery fast while preserving shared TypeScript business logic.
- Local-first state keeps daily mobile use fast and offline-friendly.
- Firebase handles account identity and restore without making every screen depend on online database reads.

## Important platform constraint

- iPhone apps cannot read the user's SMS inbox directly.
- On Android, automated transaction capture should start with notification parsing and import flows.
- SMS parsing should be treated as optional and reviewed against current Play policy before release.

## Docs

- [docs/app/README.md](docs/app/README.md) — app handbook for current features, pages, flows, scenarios, business rules, and QA status
- [docs/implementation-status.md](docs/implementation-status.md) — current repo status, validation commands, and commit notes
- [docs/product-foundation.md](docs/product-foundation.md) — scope, principles, workflows, UI direction
- [docs/features.md](docs/features.md) — full feature catalog (widgets, multi-currency, exclusions, automation, reports)
- [docs/wireframes.md](docs/wireframes.md) — low-fidelity wireframes for every core screen
- [docs/technical-architecture.md](docs/technical-architecture.md) — stack choice and architecture
- [docs/database-schema.md](docs/database-schema.md) — target cloud data model for the future Supabase path
- [.env.example](.env.example) — public Firebase and Google OAuth environment variables for local setup
- [docs/roadmap.md](docs/roadmap.md) — phased build order

## Layout

```text
apps/
  mobile/           # Expo + React Native app
packages/
  config/           # Shared configuration
  domain/           # Types and money math
  ledger/           # Ledger store, services, imports, capture parsing, loans, rules
  state/            # React provider, local persistence, FX refresh bridge
  ui/               # Design tokens and shared visual language
  validation/       # Zod schemas shared across client and server
supabase/
  migrations/       # Postgres schema migrations
firebase/
  firestore.rules   # User-scoped Firestore access rules
```

## Getting started

Prereqs: Node 20+, pnpm 11+, Android tooling for mobile release builds, and optionally the Supabase CLI for future backend work.

```powershell
pnpm install
pnpm typecheck
pnpm test
pnpm --filter @1wallet/mobile dev   # Expo
# Optional local Firebase emulators after Firebase config is set:
firebase emulators:start
```

## What's next

1. Keep the mobile ledger, Add Record, automation, notifications, and currency flows covered by focused QA runs.
2. Tighten cloud-sync boundaries before moving beyond snapshot restore/upload into full entity-level merge.
3. Continue visual polish and release validation on Android.
