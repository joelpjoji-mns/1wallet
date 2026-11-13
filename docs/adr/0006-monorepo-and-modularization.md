# ADR 0006: Monorepo Architecture and Package Modularization

## Status
Accepted

## Context
1Wallet consists of:
1. The primary Flutter mobile and desktop application (`lib/`).
2. The companion Progressive Web App (`pwa/`), built with React, TypeScript, and Vite.
3. Backend Firebase rules, cloud functions, and emulator integration tests (`firebase/`).
4. In-app update and release scripts (`scripts/`).

Currently, core domain concepts (such as integer money formatting and currency arithmetic) and design components (such as glassmorphism cards and tokens) reside within the Flutter app's `lib/src/` directory. Extracting these into standalone, reusable packages will improve modularity, simplify independent unit testing, and enable code reuse across platforms.

## Decision
We adopt **Melos** as our monorepo management tool for the multi-package ecosystem:

1. **Monorepo Structure**:
   - `apps/one_wallet_flutter`: Root Flutter application (transition path from current root).
   - `pwa`: React 19 companion web app.
   - `packages/one_wallet_money`: Lightweight Dart package for integer minor-unit money arithmetic, currency codes, exchange rate conversions, and zero-float formatting.
   - `packages/one_wallet_design_system`: Extracted design tokens, glass containers, typography, and theme controllers.
2. **Phase-Gated Migration**:
   - In Step 0 / Phase 6, we establish the `melos.yaml` configuration and directory scaffolding without disrupting existing paths or breaking CI builds.
   - Package extraction will proceed incrementally, ensuring that every package has independent test coverage and documentation.
3. **Unified Scripting**:
   - Melos coordinates workspace-wide tasks: `melos run test`, `melos run analyze`, `melos run format`.

## Consequences
- Clean boundary between pure domain logic (money/ledger) and UI presentation.
- Independent versioning and testing of packages.
- Zero breaking changes to existing root build paths during the transition period.
