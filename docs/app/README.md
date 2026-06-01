# 1wallet App Handbook

This handbook is the current-state map for the 1wallet app. It is meant to answer: what the app does, which UI pages exist, how users move through the product, which combinations matter, what rules the ledger follows, and what has been tested.

Mobile Android is the primary source of truth. The web app and Supabase schema are documented as companion or future-sync surfaces unless a page explicitly says otherwise.

## How To Read This Set

- [pages.md](pages.md) lists every mobile route, major entry point, shared overlay, modal, drawer item, and tab.
- [features.md](features.md) catalogs the shipped and planned product features by domain.
- [business-rules.md](business-rules.md) explains ledger behavior, account rules, currencies, imports, SMS capture, recurring rules, loans, and notifications.
- [flows.md](flows.md) describes end-to-end user flows from onboarding through Add Record, imports, review, planning, loans, settings, and recovery states.
- [scenarios.md](scenarios.md) gives combination matrices and edge cases for QA and implementation planning.
- [qa-status.md](qa-status.md) connects the docs to scenario IDs, run-log rows, screenshots, validation commands, and known QA limitations.

## Status Language

Use these labels consistently across the handbook:

- `Implemented`: the app has a working implementation in source.
- `Partially implemented`: useful behavior exists, but a meaningful piece is incomplete.
- `Planned`: the product docs describe the feature, but current source does not provide the full workflow.
- `QA verified`: a scenario or release run log has evidence.
- `Needs verification`: implementation exists but needs a focused manual or automated pass.
- `Known limitation`: intentionally called out gap, policy constraint, tooling limitation, or unsupported integration.

## Source Of Truth

- Mobile route source: `apps/mobile/app/**`.
- Root navigation: `apps/mobile/app/_layout.tsx`.
- Bottom tabs: `apps/mobile/app/(tabs)/_layout.tsx`.
- Drawer sections: `apps/mobile/src/components/AppDrawer.tsx`.
- Domain model: `packages/domain/src/types.ts` and `packages/domain/src/money.ts`.
- Ledger rules: `packages/ledger/src/**`.
- Runtime state: `packages/state/src/index.tsx`.
- QA scenario catalog: `docs/mobile-qa-scenarios.csv`.
- QA run evidence: `docs/mobile-qa-run-log.csv`.
- Source inventory: `docs/code-inventory.csv`.

## Related Docs

- [../implementation-status.md](../implementation-status.md) gives the short current-state summary and validation commands.
- [../product-foundation.md](../product-foundation.md) records product principles and scope.
- [../features.md](../features.md) is the broad legacy feature catalog, including aspirational items.
- [../technical-architecture.md](../technical-architecture.md) explains stack choices and architecture.
- [../wireframes.md](../wireframes.md) contains low-fidelity screen sketches.
- [../cleanup-audit.md](../cleanup-audit.md) is maintenance and release-validation history, not a product spec.

## Maintenance Rule

When a route, feature, or business rule changes, update the matching handbook page in the same pull request. When a release QA pass adds screenshots or run-log rows, update [qa-status.md](qa-status.md) if coverage or limitations changed.
