# Database Schema

This is the target Supabase/Postgres schema for the future cloud-sync backend. The current mobile app is local-first; the active runtime model lives in `packages/ledger/src/store/types.ts` and `packages/ledger/src/services/index.ts`.

Target engine: PostgreSQL 15+ (Supabase compatible).

Conventions:

- All ids are `uuid` primary keys with `gen_random_uuid()` defaults.
- All money is stored in **minor units** (`bigint`), e.g., 1,250.00 INR is `125000`. This avoids floating-point bugs.
- All currencies are 3-letter ISO codes (`text`).
- All timestamps are `timestamptz`.
- All tables include `created_at`, `updated_at`, and `deleted_at` (soft delete) unless noted.
- All user-owned tables include `user_id uuid not null` and are scoped via Postgres RLS.
- Enum types are defined as Postgres `enum`s for stable schemas; flexible "type" lists use `text` + check constraint where iteration is expected.

> Before writing the first production cloud migration, reconcile this target schema with the current local ledger model. Do not assume this file alone is the runtime source of truth.

---

## 1. Identity and preferences

```sql
create table users (
  id              uuid primary key default gen_random_uuid(),
  email           text unique,
  display_name    text,
  avatar_url      text,
  auth_provider   text,           -- google, apple, email
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz
);

create table user_preferences (
  user_id             uuid primary key references users(id) on delete cascade,
  base_currency       text not null default 'INR',
  display_currency    text not null default 'INR',
  enabled_currencies  text[] not null default array['INR'],
  locale              text not null default 'en-IN',
  date_format         text not null default 'dd MMM yyyy',
  number_format       text not null default 'en-IN',
  start_day_of_week   smallint not null default 1,   -- 1 = Monday
  start_day_of_month  smallint not null default 1,
  theme               text not null default 'system',
  accent_color        text not null default 'cobalt',
  density             text not null default 'comfortable',
  app_lock_enabled    boolean not null default false,
  biometric_enabled   boolean not null default false,
  privacy_mode        boolean not null default false,
  default_account_id  uuid,
  default_expense_category_id uuid,
  default_income_category_id  uuid,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create table devices (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references users(id) on delete cascade,
  platform        text not null,            -- ios, android, web
  device_name     text,
  push_token      text,
  last_seen_at    timestamptz not null default now(),
  created_at      timestamptz not null default now()
);
```

---

## 2. Reference data

```sql
create table currencies (
  code            text primary key,         -- ISO 4217, e.g., INR
  name            text not null,
  symbol          text not null,
  minor_units     smallint not null default 2
);

create table exchange_rates (
  base_code       text not null references currencies(code),
  quote_code      text not null references currencies(code),
  rate            numeric(20, 10) not null,
  as_of_date      date not null,
  source          text not null default 'manual',       -- manual, refresh
  provider        text,
  refreshed_at    timestamptz,
  updated_at      timestamptz not null default now(),
  primary key (base_code, quote_code, as_of_date)
);

create table merchants (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid references users(id) on delete cascade,  -- null = global
  name            text not null,
  normalized_name text not null,
  logo_url        text,
  default_category_id uuid,
  created_at      timestamptz not null default now(),
  unique (user_id, normalized_name)
);
```

---

## 3. Categories and tags

```sql
create type category_kind as enum ('expense', 'income', 'transfer', 'system');

create table categories (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references users(id) on delete cascade,
  parent_id       uuid references categories(id) on delete cascade,
  name            text not null,
  kind            category_kind not null,
  icon            text,
  color           text,
  is_archived     boolean not null default false,
  is_hidden_in_stats boolean not null default false,
  sort_order      integer not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (user_id, parent_id, name)
);

create table tags (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references users(id) on delete cascade,
  name            text not null,
  color           text,
  unique (user_id, name)
);

create table transaction_tags (
  transaction_id  uuid not null references transactions(id) on delete cascade,
  tag_id          uuid not null references tags(id) on delete cascade,
  primary key (transaction_id, tag_id)
);
```

---

## 4. Accounts

```sql
create type account_type as enum (
  'cash',
  'bank',
  'credit_card',
  'debit_card',
  'wallet',
  'prepaid',
  'loan',
  'lent',
  'investment',
  'savings_goal',
  'overdraft',
  'crypto',
  'other'
);

create table accounts (
  id                       uuid primary key default gen_random_uuid(),
  user_id                  uuid not null references users(id) on delete cascade,
  name                     text not null,
  type                     account_type not null,
  currency                 text not null references currencies(code),
  icon                     text,
  color                    text,
  institution              text,
  account_nickname         text,            -- last 4 digits or label, never PAN
  opening_balance_minor    bigint not null default 0,
  opening_date             date not null default current_date,
  include_in_totals        boolean not null default true,
  include_in_budgets       boolean not null default true,
  include_in_reports       boolean not null default true,
  include_in_net_worth     boolean not null default true,
  is_archived              boolean not null default false,
  is_default               boolean not null default false,
  notes                    text,
  sort_order               integer not null default 0,
  group_name               text,
  last_reconciled_at       timestamptz,
  last_reconciled_balance_minor bigint,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  deleted_at               timestamptz
);

create index on accounts (user_id, is_archived);

create table account_match_identifiers (
  id              uuid primary key default gen_random_uuid(),
  account_id      uuid not null references accounts(id) on delete cascade,
  kind            text not null, -- account_last4, card_last4, iban_last4, sort_code, upi_vpa
  value           text not null, -- safe fragment only; full account/card numbers are forbidden
  label           text,
  verified        boolean not null default false,
  created_at      timestamptz not null default now(),
  unique (account_id, kind, value)
);

create table account_message_source_hints (
  account_id      uuid primary key references accounts(id) on delete cascade,
  sms_sender_ids  text[] not null default '{}',
  email_domains   text[] not null default '{}',
  keywords        text[] not null default '{}',
  updated_at      timestamptz not null default now()
);
```

### Credit card extension

```sql
create table credit_card_settings (
  account_id          uuid primary key references accounts(id) on delete cascade,
  credit_limit_minor  bigint,
  cycle_start_day     smallint not null,    -- 1..31
  due_day             smallint not null,
  grace_days          smallint not null default 0,
  min_due_percent     numeric(5,2) not null default 5.0,
  apr_percent         numeric(6,3),
  autopay_account_id  uuid references accounts(id),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create table card_statements (
  id                  uuid primary key default gen_random_uuid(),
  account_id          uuid not null references accounts(id) on delete cascade,
  cycle_start         date not null,
  cycle_end           date not null,
  statement_balance_minor bigint not null,
  minimum_due_minor       bigint not null,
  due_date            date not null,
  is_paid             boolean not null default false,
  paid_at             timestamptz,
  created_at          timestamptz not null default now()
);
```

### Loan extension

```sql
create table loan_settings (
  account_id          uuid primary key references accounts(id) on delete cascade,
  principal_minor     bigint not null,
  interest_rate       numeric(6,3) not null,    -- annual percent
  tenure_months       integer not null,
  emi_minor           bigint not null,
  start_date          date not null,
  lender              text,
  emi_account_id      uuid references accounts(id),  -- debit source
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create table loan_schedule (
  id                  uuid primary key default gen_random_uuid(),
  account_id          uuid not null references accounts(id) on delete cascade,
  installment_number  integer not null,
  due_date            date not null,
  principal_minor     bigint not null,
  interest_minor      bigint not null,
  balance_after_minor bigint not null,
  is_paid             boolean not null default false,
  paid_transaction_id uuid,
  unique (account_id, installment_number)
);
```

---

## 5. Transactions

```sql
create type transaction_type as enum (
  'expense',
  'income',
  'transfer',
  'refund',
  'adjustment',
  'card_payment',
  'loan_repayment',
  'lent',
  'borrowed',
  'investment_buy',
  'investment_sell',
  'fee',
  'interest_in',
  'interest_out',
  'cashback'
);

create type transaction_status as enum ('cleared', 'pending', 'scheduled', 'void');
create type transaction_source as enum ('manual', 'recurring', 'import', 'notification', 'sms', 'email', 'rule', 'shared', 'api');

create table transactions (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null references users(id) on delete cascade,
  type                 transaction_type not null,
  status               transaction_status not null default 'cleared',
  source               transaction_source not null default 'manual',

  account_id           uuid not null references accounts(id),
  counter_account_id   uuid references accounts(id),  -- for transfers

  amount_minor         bigint not null,               -- always positive, sign derived from type
  currency             text not null references currencies(code),
  base_amount_minor    bigint not null,               -- converted to user's base currency
  fx_rate              numeric(20,10),                -- rate used at booking time
  original_amount_minor bigint,
  original_currency    text references currencies(code), -- merchant/purchase currency when different from account currency
  original_fx_rate     numeric(20,10),
  counter_amount_minor bigint,                        -- destination amount for cross-currency transfers
  counter_currency     text references currencies(code),
  counter_fx_rate      numeric(20,10),

  category_id          uuid references categories(id),
  merchant_id          uuid references merchants(id),

  occurred_at          timestamptz not null,
  posted_at            timestamptz,

  payment_method       text,                          -- upi, card_swipe, online, atm, neft, autopay
  notes                text,
  location_lat         numeric(9,6),
  location_lng         numeric(9,6),
  location_label       text,

  is_reimbursable      boolean not null default false,
  reimbursed_at        timestamptz,
  is_tax_deductible    boolean not null default false,
  is_excluded_from_reports boolean not null default false,

  person_id            uuid references people(id),
  project_id           uuid references projects(id),
  trip_id              uuid references trips(id),

  original_transaction_id uuid references transactions(id),  -- for refunds / linked
  recurring_template_id   uuid references recurring_templates(id),
  capture_candidate_id    uuid references capture_candidates(id),

  source_confidence    numeric(5,2),                  -- 0..100 for non-manual
  external_ref         text,                          -- bank ref, upi ref, etc.

  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz
);

create index on transactions (user_id, occurred_at desc);
create index on transactions (account_id, occurred_at desc);
create index on transactions (category_id);
create index on transactions (status) where status <> 'cleared';
create index on transactions (source) where source <> 'manual';
```

### Splits

```sql
create table transaction_splits (
  id              uuid primary key default gen_random_uuid(),
  transaction_id  uuid not null references transactions(id) on delete cascade,
  category_id     uuid references categories(id),
  amount_minor    bigint not null,
  notes           text,
  sort_order      integer not null default 0
);
```

### Attachments

```sql
create table attachments (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references users(id) on delete cascade,
  transaction_id  uuid references transactions(id) on delete cascade,
  storage_path    text not null,
  mime_type       text,
  byte_size       bigint,
  created_at      timestamptz not null default now()
);
```

### Custom fields

```sql
create table custom_field_defs (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references users(id) on delete cascade,
  key             text not null,
  label           text not null,
  field_type      text not null,           -- text, number, date, boolean
  unique (user_id, key)
);

create table custom_field_values (
  transaction_id  uuid not null references transactions(id) on delete cascade,
  field_id        uuid not null references custom_field_defs(id) on delete cascade,
  value_text      text,
  value_number    numeric(20,4),
  value_date      date,
  value_boolean   boolean,
  primary key (transaction_id, field_id)
);
```

---

## 6. People, projects, trips

```sql
create table people (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references users(id) on delete cascade,
  name            text not null,
  contact_handle  text,
  notes           text,
  unique (user_id, name)
);

create table projects (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references users(id) on delete cascade,
  name            text not null,
  is_active       boolean not null default true,
  unique (user_id, name)
);

create table trips (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references users(id) on delete cascade,
  name            text not null,
  start_date      date,
  end_date        date,
  currency        text references currencies(code),
  unique (user_id, name)
);
```

---

## 7. Budgets

```sql
create type budget_period as enum ('weekly', 'fortnightly', 'monthly', 'quarterly', 'yearly', 'custom');

create table budgets (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references users(id) on delete cascade,
  name            text not null,
  period          budget_period not null default 'monthly',
  custom_days     integer,
  starts_on       date not null,
  amount_minor    bigint not null,
  currency        text not null references currencies(code),
  rollover_unused boolean not null default false,
  carry_overspend boolean not null default false,
  is_paused       boolean not null default false,
  alert_thresholds integer[] not null default '{50,80,100}',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table budget_scopes (
  budget_id       uuid not null references budgets(id) on delete cascade,
  category_id     uuid references categories(id) on delete cascade,
  tag_id          uuid references tags(id) on delete cascade,
  account_id      uuid references accounts(id) on delete cascade,
  -- exactly one of category_id, tag_id, account_id is set
  check (
    (category_id is not null)::int +
    (tag_id is not null)::int +
    (account_id is not null)::int = 1
  )
);

create table budget_periods (
  id              uuid primary key default gen_random_uuid(),
  budget_id       uuid not null references budgets(id) on delete cascade,
  period_start    date not null,
  period_end      date not null,
  limit_minor     bigint not null,
  spent_minor     bigint not null default 0,
  rollover_in_minor bigint not null default 0,
  unique (budget_id, period_start)
);
```

---

## 8. Goals

```sql
create type goal_kind as enum ('save_up', 'pay_off', 'build_up', 'recurring');
create type goal_priority as enum ('critical', 'high', 'medium', 'low');

create table goals (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references users(id) on delete cascade,
  name            text not null,
  kind            goal_kind not null default 'save_up',
  target_amount_minor bigint not null,
  target_date     date,
  currency        text not null references currencies(code),
  priority        goal_priority not null default 'medium',
  linked_category_id uuid references categories(id),
  is_paused       boolean not null default false,
  is_completed    boolean not null default false,
  completed_at    timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table goal_funding_accounts (
  goal_id         uuid not null references goals(id) on delete cascade,
  account_id      uuid not null references accounts(id) on delete cascade,
  primary key (goal_id, account_id)
);

create table goal_contributions (
  id              uuid primary key default gen_random_uuid(),
  goal_id         uuid not null references goals(id) on delete cascade,
  amount_minor    bigint not null,
  occurred_at     timestamptz not null default now(),
  transaction_id  uuid references transactions(id),
  notes           text
);
```

---

## 9. Recurring and reminders

```sql
create table recurring_templates (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references users(id) on delete cascade,
  template_type   transaction_type not null,
  account_id      uuid not null references accounts(id),
  counter_account_id uuid references accounts(id),
  category_id     uuid references categories(id),
  merchant_id     uuid references merchants(id),
  amount_minor    bigint not null,
  currency        text not null references currencies(code),
  notes           text,
  rrule           text not null,                 -- iCal RRULE string
  next_run_at     timestamptz,
  end_at          timestamptz,
  occurrences_left integer,
  auto_post       boolean not null default false,
  remind_before_days smallint not null default 1,
  is_paused       boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table reminders (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references users(id) on delete cascade,
  title           text not null,
  body            text,
  trigger_at      timestamptz not null,
  channel         text not null default 'push',  -- push, email, both
  related_kind    text,                          -- bill, emi, budget, goal, statement
  related_id      uuid,
  is_sent         boolean not null default false,
  sent_at         timestamptz,
  is_snoozed      boolean not null default false,
  snoozed_until   timestamptz,
  created_at      timestamptz not null default now()
);
```

---

## 10. Subscriptions

```sql
create table subscriptions (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references users(id) on delete cascade,
  name            text not null,
  merchant_id     uuid references merchants(id),
  amount_minor    bigint not null,
  currency        text not null references currencies(code),
  billing_cycle   text not null,                 -- monthly, yearly, weekly, custom
  custom_days     integer,
  next_billing_at timestamptz,
  account_id      uuid references accounts(id),
  category_id     uuid references categories(id),
  is_active       boolean not null default true,
  detected_from_transaction_id uuid references transactions(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
```

---

## 11. Automation: rules, captures, imports

```sql
create table rules (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references users(id) on delete cascade,
  name            text not null,
  priority        integer not null default 100,
  is_enabled      boolean not null default true,
  conditions      jsonb not null,                -- normalized rule AST
  actions         jsonb not null,                -- { category, tag, account, exclude_from_reports, ... }
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table import_sources (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references users(id) on delete cascade,
  kind            text not null,                 -- csv, statement_pdf, app_export
  display_name    text not null,
  config          jsonb,
  created_at      timestamptz not null default now()
);

create table imported_files (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references users(id) on delete cascade,
  import_source_id uuid references import_sources(id),
  storage_path    text not null,
  filename        text not null,
  status          text not null default 'parsed',  -- uploaded, parsed, failed, applied
  rows_parsed     integer not null default 0,
  rows_imported   integer not null default 0,
  error           text,
  created_at      timestamptz not null default now()
);

create table capture_candidates (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references users(id) on delete cascade,
  source              transaction_source not null,   -- notification, sms, email, import, api
  raw_payload         jsonb not null,                -- never store full SMS body in cloud unless user consents
  raw_hash            text not null,                 -- for dedupe
  parsed_amount_minor bigint,
  parsed_currency     text,
  parsed_original_amount_minor bigint,
  parsed_original_currency text,
  parsed_original_fx_rate numeric(20,10),
  parsed_merchant     text,
  parsed_occurred_at  timestamptz,
  suggested_account_id uuid references accounts(id),
  suggested_category_id uuid references categories(id),
  suggested_type      transaction_type,
  confidence          numeric(5,2) not null default 0,
  status              text not null default 'pending',  -- pending, approved, rejected, ignored, auto_posted
  posted_transaction_id uuid references transactions(id),
  reviewed_at         timestamptz,
  created_at          timestamptz not null default now(),
  unique (user_id, raw_hash)
);

create table trusted_senders (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references users(id) on delete cascade,
  channel         text not null,                 -- sms, notification, email
  sender_id       text not null,                 -- e.g., 'HDFCBK', 'com.hdfc.app', 'alerts@hdfc.com'
  is_trusted      boolean not null default true,
  default_account_id uuid references accounts(id),
  created_at      timestamptz not null default now(),
  unique (user_id, channel, sender_id)
);
```

---

## 12. Reconciliation

```sql
create table reconciliations (
  id                      uuid primary key default gen_random_uuid(),
  user_id                 uuid not null references users(id) on delete cascade,
  account_id              uuid not null references accounts(id) on delete cascade,
  statement_date          date not null,
  statement_balance_minor bigint not null,
  computed_balance_minor  bigint not null,
  adjustment_minor        bigint not null default 0,
  adjustment_transaction_id uuid references transactions(id),
  created_at              timestamptz not null default now()
);
```

---

## 13. Sharing (later)

```sql
create table workspaces (
  id              uuid primary key default gen_random_uuid(),
  owner_user_id   uuid not null references users(id) on delete cascade,
  name            text not null,
  created_at      timestamptz not null default now()
);

create table workspace_members (
  workspace_id    uuid not null references workspaces(id) on delete cascade,
  user_id         uuid not null references users(id) on delete cascade,
  role            text not null default 'editor',     -- owner, editor, viewer
  joined_at       timestamptz not null default now(),
  primary key (workspace_id, user_id)
);
```

Note: Initial release scopes all tables to `user_id`. Workspace columns are added later behind a feature flag without breaking single-user flows.

---

## 14. Audit and sync

```sql
create table audit_log (
  id              bigserial primary key,
  user_id         uuid not null references users(id) on delete cascade,
  entity          text not null,                  -- transactions, accounts, ...
  entity_id       uuid,
  action          text not null,                  -- create, update, delete, restore
  diff            jsonb,
  source          text,                           -- ui, api, rule, importer
  created_at      timestamptz not null default now()
);

create table sync_cursors (
  user_id         uuid not null references users(id) on delete cascade,
  device_id       uuid references devices(id) on delete cascade,
  entity          text not null,
  cursor          timestamptz not null,
  primary key (user_id, device_id, entity)
);
```

---

## 15. Derived views

```sql
-- Account balances are derived, not stored
create view account_balances as
select
  a.id as account_id,
  a.user_id,
  a.currency,
  a.opening_balance_minor
    + coalesce(sum(
        case t.type
          when 'income'         then  t.amount_minor
          when 'refund'         then  t.amount_minor
          when 'interest_in'    then  t.amount_minor
          when 'cashback'       then  t.amount_minor
          when 'borrowed'       then  t.amount_minor
          when 'expense'        then -t.amount_minor
          when 'fee'            then -t.amount_minor
          when 'interest_out'   then -t.amount_minor
          when 'lent'           then -t.amount_minor
          when 'investment_buy' then -t.amount_minor
          when 'investment_sell'then  t.amount_minor
          when 'adjustment'     then  t.amount_minor   -- signed by caller convention
          else 0
        end
      ), 0)
    + coalesce((select sum(
        case
          when tr.account_id = a.id         then -tr.amount_minor   -- outflow
          when tr.counter_account_id = a.id then  tr.amount_minor   -- inflow
          else 0
        end
      ) from transactions tr
      where tr.user_id = a.user_id
        and tr.type in ('transfer','card_payment','loan_repayment')
        and (tr.account_id = a.id or tr.counter_account_id = a.id)
        and tr.deleted_at is null), 0)
    as current_balance_minor
from accounts a
left join transactions t
  on t.account_id = a.id
 and t.deleted_at is null
 and t.type not in ('transfer','card_payment','loan_repayment')
where a.deleted_at is null
group by a.id;
```

Note: this view is a starting point. For production, materialize balances per account and refresh on transaction write to keep dashboard reads fast.

---

## 16. Row Level Security baseline

```sql
alter table accounts        enable row level security;
alter table transactions    enable row level security;
alter table categories      enable row level security;
alter table budgets         enable row level security;
alter table goals           enable row level security;
-- repeat for every user-scoped table

create policy "owner can read"   on accounts for select using (user_id = auth.uid());
create policy "owner can write"  on accounts for all    using (user_id = auth.uid()) with check (user_id = auth.uid());
-- repeat the pattern for every user-scoped table
```

---

## 17. Integrity rules to enforce in application code

- Transfers must set both `account_id` and `counter_account_id` and they must be different.
- Non-transfer types must leave `counter_account_id` null.
- `amount_minor` is always positive; sign is implied by `type`.
- `amount_minor` and `currency` represent the account-posted amount and drive account balances.
- `base_currency` is the reports/storage currency; `display_currency` is a non-destructive view preference and must not rewrite transaction amounts.
- Foreign purchases store the merchant/purchase amount in `original_amount_minor` and `original_currency`, while `base_amount_minor` remains the reporting-currency equivalent.
- Cross-currency transfers store destination-account value in `counter_amount_minor` and `counter_currency`; destination balances use the counter amount.
- `capture_candidates` raw payloads should be redacted or hashed for non-trusted senders.
- Soft delete (`deleted_at`) is preferred; never hard-delete a transaction without recording an audit entry.
- Excluded accounts (`include_in_totals = false`) still produce transactions that participate in their own account history but are filtered out of totals, net worth, and reports.

---

## 18. Indexing hot paths

- `transactions (user_id, occurred_at desc)` — feeds the timeline.
- `transactions (account_id, occurred_at desc)` — feeds account detail.
- `transactions (category_id, occurred_at desc)` — feeds category reports.
- Partial index on `transactions (status)` where status is not `cleared` — feeds review and scheduled lists.
- `capture_candidates (user_id, status)` where status = `pending` — feeds the review queue.
- `budget_periods (budget_id, period_start desc)` — feeds budget views.
- `loan_schedule (account_id, due_date)` — feeds EMI views.

---

## 19. Future-proofing notes

- Investments, FX gain/loss, and shared workspaces are scaffolded but intentionally lightweight in MVP.
- The `rules.conditions` and `rules.actions` fields are `jsonb` so the rule engine can evolve without schema churn.
- `capture_candidates.raw_payload` is `jsonb` so multiple capture sources can share a single review queue.
- `audit_log` is append-only and not subject to soft delete.
