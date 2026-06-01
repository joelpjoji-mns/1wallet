# Supabase

This folder will hold migrations and Edge Functions for the backend.

## Getting started

1. Install the Supabase CLI: <https://supabase.com/docs/guides/cli>.
2. From the repo root, run `supabase init` once to create local config (already prepared here).
3. Run `supabase start` to spin up a local Postgres + Studio.
4. Apply the initial migration with `supabase db reset`.

The schema in [migrations/0001_init.sql](migrations/0001_init.sql) is the runnable head of [docs/database-schema.md](../docs/database-schema.md). Keep the doc and the migration in sync until the doc can be generated from the schema.
