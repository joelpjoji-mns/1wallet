# Supabase

This folder contains the PostgreSQL/Supabase backend migrations for the future 1wallet cloud-sync path. The mobile app remains local-first; Supabase is the normalized sync, backup, reporting, and multi-device backend layer.

## Migration stack

- `migrations/0001_init.sql` — core ledger schema, reference tables, identity, accounts, transactions, planning, automation, audit, and sync cursors.
- `migrations/0002_schema_reconciliation.sql` — reconciles the runnable schema with `docs/database-schema.md` and the runtime ledger model: display/enabled currencies, FX fields, account matching hints, custom fields, and extra integrity checks.
- `migrations/0003_rls_policies.sql` — owner-scoped RLS policies for all user-owned tables, parent-join policies for child tables, and read-only public policies for reference data.
- `migrations/0004_performance_caches.sql` — hot-path indexes, `updated_at` triggers, core audit triggers, `account_balance_cache`, balance refresh functions, and account-summary RPCs.

## Getting started

1. Install the Supabase CLI: <https://supabase.com/docs/guides/cli>.
2. From the repo root, run `supabase init` once if local config is not already present.
3. Run `supabase start` to spin up local Postgres + Studio.
4. Apply migrations with `supabase db reset`.
5. Run the repository validator with `pnpm supabase:validate`.

## Validation

`pnpm supabase:validate` performs a static migration check that does not require Docker or a live database. It verifies that the reconciliation columns/tables, RLS policies, performance indexes, balance cache, and helper functions are present.

For production readiness, also run database-backed checks against a local Supabase instance:

1. `supabase db reset`
2. RLS smoke test with two authenticated users.
3. `EXPLAIN ANALYZE` on Home/account/timeline queries.
4. Synthetic large-ledger seed tests before enabling automatic sync.

## Performance model

Balance and dashboard reads should use `account_balance_cache` and RPC/read-shape helpers instead of recomputing balances over every transaction on each request. Transaction writes refresh affected accounts through triggers. Large reporting queries should be backed by targeted indexes or explicit cache tables/RPCs.

## Security model

All user-owned tables are protected by RLS. Direct user tables use `user_id = auth.uid()`. Child tables without `user_id` are scoped through their parent account, transaction, budget, goal, or custom-field owner. `audit_log` is append-only for normal clients. Sensitive capture payloads should remain redacted/hashed unless a user explicitly opts in to cloud raw-payload sync.

Keep this folder and `docs/database-schema.md` in sync until schema documentation can be generated from migrations.
