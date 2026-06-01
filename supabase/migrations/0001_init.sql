-- 0001_init.sql
-- Initial schema for 1wallet. See docs/database-schema.md for the full design.
-- This migration creates the Phase 1 ledger plus scaffolding for planning and automation.

create extension if not exists "pgcrypto";

-- =========================================================================
-- Reference data
-- =========================================================================

create table currencies (
  code        text primary key,
  name        text not null,
  symbol      text not null,
  minor_units smallint not null default 2
);

insert into currencies (code, name, symbol, minor_units) values
  ('INR', 'Indian Rupee', '₹', 2),
  ('USD', 'US Dollar',    '$', 2),
  ('EUR', 'Euro',         '€', 2),
  ('GBP', 'Pound',        '£', 2),
  ('JPY', 'Yen',          '¥', 0),
  ('AED', 'Dirham',       'د.إ', 2),
  ('SGD', 'Sing Dollar',  'S$', 2),
  ('AUD', 'Aus Dollar',   'A$', 2),
  ('CAD', 'Can Dollar',   'C$', 2)
on conflict do nothing;

create table exchange_rates (
  base_code   text not null references currencies(code),
  quote_code  text not null references currencies(code),
  rate        numeric(20, 10) not null,
  as_of_date  date not null,
  source      text not null default 'system',
  primary key (base_code, quote_code, as_of_date)
);

-- =========================================================================
-- Identity
-- =========================================================================

create table users (
  id            uuid primary key default gen_random_uuid(),
  email         text unique,
  display_name  text,
  avatar_url    text,
  auth_provider text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz
);

create table user_preferences (
  user_id            uuid primary key references users(id) on delete cascade,
  base_currency      text not null default 'INR' references currencies(code),
  locale             text not null default 'en-IN',
  date_format        text not null default 'dd MMM yyyy',
  number_format      text not null default 'en-IN',
  start_day_of_week  smallint not null default 1,
  start_day_of_month smallint not null default 1,
  theme              text not null default 'system',
  accent_color       text not null default 'cobalt',
  density            text not null default 'comfortable',
  app_lock_enabled   boolean not null default false,
  biometric_enabled  boolean not null default false,
  privacy_mode       boolean not null default false,
  default_account_id          uuid,
  default_expense_category_id uuid,
  default_income_category_id  uuid,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create table devices (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references users(id) on delete cascade,
  platform     text not null,
  device_name  text,
  push_token   text,
  last_seen_at timestamptz not null default now(),
  created_at   timestamptz not null default now()
);

-- =========================================================================
-- Categories, tags, merchants
-- =========================================================================

create type category_kind as enum ('expense', 'income', 'transfer', 'system');

create table categories (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references users(id) on delete cascade,
  parent_id          uuid references categories(id) on delete cascade,
  name               text not null,
  kind               category_kind not null,
  icon               text,
  color              text,
  is_archived        boolean not null default false,
  is_hidden_in_stats boolean not null default false,
  sort_order         integer not null default 0,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create unique index categories_user_parent_name_idx
  on categories (user_id, coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid), name);

create table tags (
  id      uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  name    text not null,
  color   text,
  unique (user_id, name)
);

create table merchants (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid references users(id) on delete cascade,
  name                text not null,
  normalized_name     text not null,
  logo_url            text,
  default_category_id uuid references categories(id),
  created_at          timestamptz not null default now(),
  unique (user_id, normalized_name)
);

-- =========================================================================
-- People, projects, trips
-- =========================================================================

create table people (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references users(id) on delete cascade,
  name           text not null,
  contact_handle text,
  notes          text,
  unique (user_id, name)
);

create table projects (
  id        uuid primary key default gen_random_uuid(),
  user_id   uuid not null references users(id) on delete cascade,
  name      text not null,
  is_active boolean not null default true,
  unique (user_id, name)
);

create table trips (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references users(id) on delete cascade,
  name       text not null,
  start_date date,
  end_date   date,
  currency   text references currencies(code),
  unique (user_id, name)
);

-- =========================================================================
-- Accounts
-- =========================================================================

create type account_type as enum (
  'cash','bank','credit_card','debit_card','wallet','prepaid',
  'loan','lent','investment','savings_goal','overdraft','crypto','other'
);

create table accounts (
  id                            uuid primary key default gen_random_uuid(),
  user_id                       uuid not null references users(id) on delete cascade,
  name                          text not null,
  type                          account_type not null,
  currency                      text not null references currencies(code),
  icon                          text,
  color                         text,
  institution                   text,
  account_nickname              text,
  opening_balance_minor         bigint not null default 0,
  opening_date                  date not null default current_date,
  include_in_totals             boolean not null default true,
  include_in_budgets            boolean not null default true,
  include_in_reports            boolean not null default true,
  include_in_net_worth          boolean not null default true,
  is_archived                   boolean not null default false,
  is_default                    boolean not null default false,
  notes                         text,
  sort_order                    integer not null default 0,
  group_name                    text,
  last_reconciled_at            timestamptz,
  last_reconciled_balance_minor bigint,
  created_at                    timestamptz not null default now(),
  updated_at                    timestamptz not null default now(),
  deleted_at                    timestamptz
);

create index accounts_user_active_idx on accounts (user_id, is_archived);

create table credit_card_settings (
  account_id         uuid primary key references accounts(id) on delete cascade,
  credit_limit_minor bigint,
  cycle_start_day    smallint not null,
  due_day            smallint not null,
  grace_days         smallint not null default 0,
  min_due_percent    numeric(5,2) not null default 5.0,
  apr_percent        numeric(6,3),
  autopay_account_id uuid references accounts(id),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create table loan_settings (
  account_id      uuid primary key references accounts(id) on delete cascade,
  principal_minor bigint not null,
  interest_rate   numeric(6,3) not null,
  tenure_months   integer not null,
  emi_minor       bigint not null,
  start_date      date not null,
  lender          text,
  emi_account_id  uuid references accounts(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
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

-- =========================================================================
-- Transactions
-- =========================================================================

create type transaction_type as enum (
  'expense','income','transfer','refund','adjustment','card_payment','loan_repayment',
  'lent','borrowed','investment_buy','investment_sell','fee','interest_in','interest_out','cashback'
);
create type transaction_status as enum ('cleared','pending','scheduled','void');
create type transaction_source as enum ('manual','recurring','import','notification','sms','email','rule','shared','api');

create table transactions (
  id                       uuid primary key default gen_random_uuid(),
  user_id                  uuid not null references users(id) on delete cascade,
  type                     transaction_type not null,
  status                   transaction_status not null default 'cleared',
  source                   transaction_source not null default 'manual',
  account_id               uuid not null references accounts(id),
  counter_account_id       uuid references accounts(id),
  amount_minor             bigint not null check (amount_minor > 0),
  currency                 text not null references currencies(code),
  base_amount_minor        bigint not null,
  fx_rate                  numeric(20,10),
  category_id              uuid references categories(id),
  merchant_id              uuid references merchants(id),
  occurred_at              timestamptz not null,
  posted_at                timestamptz,
  payment_method           text,
  notes                    text,
  location_lat             numeric(9,6),
  location_lng             numeric(9,6),
  location_label           text,
  is_reimbursable          boolean not null default false,
  reimbursed_at            timestamptz,
  is_tax_deductible        boolean not null default false,
  is_excluded_from_reports boolean not null default false,
  person_id                uuid references people(id),
  project_id               uuid references projects(id),
  trip_id                  uuid references trips(id),
  original_transaction_id  uuid references transactions(id),
  recurring_template_id    uuid,
  capture_candidate_id     uuid,
  source_confidence        numeric(5,2),
  external_ref             text,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  deleted_at               timestamptz,
  check (
    (type in ('transfer','card_payment','loan_repayment') and counter_account_id is not null and counter_account_id <> account_id)
    or
    (type not in ('transfer','card_payment','loan_repayment') and counter_account_id is null)
  )
);

create index transactions_user_time_idx     on transactions (user_id, occurred_at desc);
create index transactions_account_time_idx  on transactions (account_id, occurred_at desc);
create index transactions_category_idx      on transactions (category_id);
create index transactions_status_partial    on transactions (status) where status <> 'cleared';
create index transactions_source_partial    on transactions (source) where source <> 'manual';

create table transaction_tags (
  transaction_id uuid not null references transactions(id) on delete cascade,
  tag_id         uuid not null references tags(id) on delete cascade,
  primary key (transaction_id, tag_id)
);

create table transaction_splits (
  id             uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references transactions(id) on delete cascade,
  category_id    uuid references categories(id),
  amount_minor   bigint not null,
  notes          text,
  sort_order     integer not null default 0
);

create table attachments (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references users(id) on delete cascade,
  transaction_id uuid references transactions(id) on delete cascade,
  storage_path   text not null,
  mime_type      text,
  byte_size      bigint,
  created_at     timestamptz not null default now()
);

-- =========================================================================
-- Card statements
-- =========================================================================

create table card_statements (
  id                      uuid primary key default gen_random_uuid(),
  account_id              uuid not null references accounts(id) on delete cascade,
  cycle_start             date not null,
  cycle_end               date not null,
  statement_balance_minor bigint not null,
  minimum_due_minor       bigint not null,
  due_date                date not null,
  is_paid                 boolean not null default false,
  paid_at                 timestamptz,
  created_at              timestamptz not null default now()
);

-- =========================================================================
-- Budgets and goals
-- =========================================================================

create type budget_period as enum ('weekly','fortnightly','monthly','quarterly','yearly','custom');

create table budgets (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references users(id) on delete cascade,
  name             text not null,
  period           budget_period not null default 'monthly',
  custom_days      integer,
  starts_on        date not null,
  amount_minor     bigint not null,
  currency         text not null references currencies(code),
  rollover_unused  boolean not null default false,
  carry_overspend  boolean not null default false,
  is_paused        boolean not null default false,
  alert_thresholds integer[] not null default array[50,80,100]::integer[],
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create table budget_scopes (
  id          uuid primary key default gen_random_uuid(),
  budget_id   uuid not null references budgets(id) on delete cascade,
  category_id uuid references categories(id) on delete cascade,
  tag_id      uuid references tags(id) on delete cascade,
  account_id  uuid references accounts(id) on delete cascade,
  check (
    (case when category_id is not null then 1 else 0 end) +
    (case when tag_id      is not null then 1 else 0 end) +
    (case when account_id  is not null then 1 else 0 end) = 1
  )
);

create table budget_periods (
  id                uuid primary key default gen_random_uuid(),
  budget_id         uuid not null references budgets(id) on delete cascade,
  period_start      date not null,
  period_end        date not null,
  limit_minor       bigint not null,
  spent_minor       bigint not null default 0,
  rollover_in_minor bigint not null default 0,
  unique (budget_id, period_start)
);

create type goal_kind     as enum ('save_up','pay_off','build_up','recurring');
create type goal_priority as enum ('critical','high','medium','low');

create table goals (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references users(id) on delete cascade,
  name                text not null,
  kind                goal_kind not null default 'save_up',
  target_amount_minor bigint not null,
  target_date         date,
  currency            text not null references currencies(code),
  priority            goal_priority not null default 'medium',
  linked_category_id  uuid references categories(id),
  is_paused           boolean not null default false,
  is_completed        boolean not null default false,
  completed_at        timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create table goal_funding_accounts (
  goal_id    uuid not null references goals(id) on delete cascade,
  account_id uuid not null references accounts(id) on delete cascade,
  primary key (goal_id, account_id)
);

create table goal_contributions (
  id             uuid primary key default gen_random_uuid(),
  goal_id        uuid not null references goals(id) on delete cascade,
  amount_minor   bigint not null,
  occurred_at    timestamptz not null default now(),
  transaction_id uuid references transactions(id),
  notes          text
);

-- =========================================================================
-- Recurring, reminders, subscriptions
-- =========================================================================

create table recurring_templates (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references users(id) on delete cascade,
  template_type       transaction_type not null,
  account_id          uuid not null references accounts(id),
  counter_account_id  uuid references accounts(id),
  category_id         uuid references categories(id),
  merchant_id         uuid references merchants(id),
  amount_minor        bigint not null,
  currency            text not null references currencies(code),
  notes               text,
  rrule               text not null,
  next_run_at         timestamptz,
  end_at              timestamptz,
  occurrences_left    integer,
  auto_post           boolean not null default false,
  remind_before_days  smallint not null default 1,
  is_paused           boolean not null default false,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

alter table transactions
  add constraint transactions_recurring_template_fk
  foreign key (recurring_template_id) references recurring_templates(id) on delete set null;

create table reminders (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references users(id) on delete cascade,
  title         text not null,
  body          text,
  trigger_at    timestamptz not null,
  channel       text not null default 'push',
  related_kind  text,
  related_id    uuid,
  is_sent       boolean not null default false,
  sent_at       timestamptz,
  is_snoozed    boolean not null default false,
  snoozed_until timestamptz,
  created_at    timestamptz not null default now()
);

create table subscriptions (
  id                            uuid primary key default gen_random_uuid(),
  user_id                       uuid not null references users(id) on delete cascade,
  name                          text not null,
  merchant_id                   uuid references merchants(id),
  amount_minor                  bigint not null,
  currency                      text not null references currencies(code),
  billing_cycle                 text not null,
  custom_days                   integer,
  next_billing_at               timestamptz,
  account_id                    uuid references accounts(id),
  category_id                   uuid references categories(id),
  is_active                     boolean not null default true,
  detected_from_transaction_id  uuid references transactions(id),
  created_at                    timestamptz not null default now(),
  updated_at                    timestamptz not null default now()
);

-- =========================================================================
-- Automation
-- =========================================================================

create table rules (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references users(id) on delete cascade,
  name       text not null,
  priority   integer not null default 100,
  is_enabled boolean not null default true,
  conditions jsonb not null,
  actions    jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table import_sources (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references users(id) on delete cascade,
  kind         text not null,
  display_name text not null,
  config       jsonb,
  created_at   timestamptz not null default now()
);

create table imported_files (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references users(id) on delete cascade,
  import_source_id uuid references import_sources(id),
  storage_path     text not null,
  filename         text not null,
  status           text not null default 'parsed',
  rows_parsed      integer not null default 0,
  rows_imported    integer not null default 0,
  error            text,
  created_at       timestamptz not null default now()
);

create table capture_candidates (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null references users(id) on delete cascade,
  source                transaction_source not null,
  raw_payload           jsonb not null,
  raw_hash              text not null,
  parsed_amount_minor   bigint,
  parsed_currency       text,
  parsed_merchant       text,
  parsed_occurred_at    timestamptz,
  suggested_account_id  uuid references accounts(id),
  suggested_category_id uuid references categories(id),
  suggested_type        transaction_type,
  confidence            numeric(5,2) not null default 0,
  status                text not null default 'pending',
  posted_transaction_id uuid references transactions(id),
  reviewed_at           timestamptz,
  created_at            timestamptz not null default now(),
  unique (user_id, raw_hash)
);

alter table transactions
  add constraint transactions_capture_candidate_fk
  foreign key (capture_candidate_id) references capture_candidates(id) on delete set null;

create index capture_pending_idx on capture_candidates (user_id, status) where status = 'pending';

create table trusted_senders (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references users(id) on delete cascade,
  channel            text not null,
  sender_id          text not null,
  is_trusted         boolean not null default true,
  default_account_id uuid references accounts(id),
  created_at         timestamptz not null default now(),
  unique (user_id, channel, sender_id)
);

-- =========================================================================
-- Reconciliation, audit, sync
-- =========================================================================

create table reconciliations (
  id                        uuid primary key default gen_random_uuid(),
  user_id                   uuid not null references users(id) on delete cascade,
  account_id                uuid not null references accounts(id) on delete cascade,
  statement_date            date not null,
  statement_balance_minor   bigint not null,
  computed_balance_minor    bigint not null,
  adjustment_minor          bigint not null default 0,
  adjustment_transaction_id uuid references transactions(id),
  created_at                timestamptz not null default now()
);

create table audit_log (
  id        bigserial primary key,
  user_id   uuid not null references users(id) on delete cascade,
  entity    text not null,
  entity_id uuid,
  action    text not null,
  diff      jsonb,
  source    text,
  created_at timestamptz not null default now()
);

create table sync_cursors (
  user_id   uuid not null references users(id) on delete cascade,
  device_id uuid references devices(id) on delete cascade,
  entity    text not null,
  cursor    timestamptz not null,
  primary key (user_id, device_id, entity)
);

-- =========================================================================
-- RLS baseline (enable; per-table policies are added in a later migration
-- once Supabase auth.uid() mapping is wired up)
-- =========================================================================

alter table users               enable row level security;
alter table user_preferences    enable row level security;
alter table devices             enable row level security;
alter table accounts            enable row level security;
alter table categories          enable row level security;
alter table tags                enable row level security;
alter table merchants           enable row level security;
alter table people              enable row level security;
alter table projects            enable row level security;
alter table trips               enable row level security;
alter table transactions        enable row level security;
alter table transaction_tags    enable row level security;
alter table transaction_splits  enable row level security;
alter table attachments         enable row level security;
alter table credit_card_settings enable row level security;
alter table card_statements     enable row level security;
alter table loan_settings       enable row level security;
alter table loan_schedule       enable row level security;
alter table budgets             enable row level security;
alter table budget_scopes       enable row level security;
alter table budget_periods      enable row level security;
alter table goals               enable row level security;
alter table goal_funding_accounts enable row level security;
alter table goal_contributions  enable row level security;
alter table recurring_templates enable row level security;
alter table reminders           enable row level security;
alter table subscriptions       enable row level security;
alter table rules               enable row level security;
alter table import_sources      enable row level security;
alter table imported_files      enable row level security;
alter table capture_candidates  enable row level security;
alter table trusted_senders     enable row level security;
alter table reconciliations     enable row level security;
alter table audit_log           enable row level security;
alter table sync_cursors        enable row level security;
