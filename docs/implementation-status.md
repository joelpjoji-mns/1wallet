# Implementation Status

This file separates the current repository state from the broader product, architecture, and schema planning docs.

## Current Product Surface

- Mobile app is the primary working surface under `apps/mobile`.
- Web app exists as a companion surface under `apps/web`, but mobile leads product validation.
- The ledger is local-first today through `@1wallet/ledger` and `@1wallet/state`.
- Supabase/Postgres docs and migrations describe the future cloud-sync target, not the active storage path.
- The current app handbook lives at [app/README.md](app/README.md), with route inventory, feature catalog, user flows, scenario matrices, business rules, and QA status.

## Current Core Capabilities

- Accounts, categories, transactions, transfers, card payments, loan repayments, scheduled records, imports, review queue, widgets, calendar, notifications, and settings are implemented in the mobile app.
- Add Record supports expense, income, transfer, adjustment, pending, scheduled, receipt entry, foreign purchase currency, and account-currency conversion display.
- Currencies are managed through the central domain currency catalog and the user-enabled currency list.
- Exchange rates use `frankfurter.app`; rates are considered fresh for one hour. Add/edit/capture flows refresh stale or missing rates before saving.
- Notification bell opens an inbox-only notification list. Notification settings live in Settings. Native local notifications use `expo-notifications` when permission is granted.
- Android SMS capture exists as a local-only, permission-gated feature. Low-confidence or uncertain captures go to Review.

## Commit Hygiene

- Keep `patches/` committed because `package.json` and `pnpm-lock.yaml` reference the `react-native-get-sms-android` pnpm patch.
- Keep `backups/` out of Git; it contains local device/emulator data dumps.
- Do not commit `.tmp/`, `.tmp-*.json`, `.expo/`, `.turbo/`, `node_modules/`, build outputs, logs, or `*.tsbuildinfo`.

## Validation Commands

```powershell
pnpm --filter @1wallet/mobile typecheck
pnpm --filter @1wallet/ledger --filter @1wallet/state typecheck
pnpm --filter @1wallet/ledger test
pnpm typecheck
pnpm test
pnpm lint
pnpm build
```

For Android release work, use the repo's current Java/Node environment notes from prior QA logs and run a focused route smoke after install.
