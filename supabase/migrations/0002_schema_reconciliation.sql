-- 0002_schema_reconciliation.sql
-- Reconcile the runnable Supabase schema with docs/database-schema.md and
-- the local-first LedgerState runtime model before wiring normalized sync.

-- =========================================================================
-- User preferences and FX metadata
-- =========================================================================

alter table user_preferences
  add column if not exists display_currency text not null default 'INR',
  add column if not exists enabled_currencies text[] not null default array['INR']::text[];

alter table exchange_rates
  add column if not exists provider text,
  add column if not exists refreshed_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'user_preferences_display_currency_fk'
  ) then
    alter table user_preferences
      add constraint user_preferences_display_currency_fk
      foreign key (display_currency) references currencies(code);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'user_preferences_enabled_currencies_nonempty'
  ) then
    alter table user_preferences
      add constraint user_preferences_enabled_currencies_nonempty
      check (coalesce(array_length(enabled_currencies, 1), 0) > 0);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'exchange_rates_positive_rate'
  ) then
    alter table exchange_rates
      add constraint exchange_rates_positive_rate check (rate > 0);
  end if;
end $$;

-- =========================================================================
-- Preference default foreign keys added after accounts/categories exist
-- =========================================================================

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'user_preferences_default_account_fk'
  ) then
    alter table user_preferences
      add constraint user_preferences_default_account_fk
      foreign key (default_account_id) references accounts(id) on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'user_preferences_default_expense_category_fk'
  ) then
    alter table user_preferences
      add constraint user_preferences_default_expense_category_fk
      foreign key (default_expense_category_id) references categories(id) on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'user_preferences_default_income_category_fk'
  ) then
    alter table user_preferences
      add constraint user_preferences_default_income_category_fk
      foreign key (default_income_category_id) references categories(id) on delete set null;
  end if;
end $$;

-- =========================================================================
-- Account matching metadata for capture/rule routing
-- =========================================================================

create table if not exists account_match_identifiers (
  id         uuid primary key default gen_random_uuid(),
  account_id uuid not null references accounts(id) on delete cascade,
  kind       text not null,
  value      text not null,
  label      text,
  verified   boolean not null default false,
  created_at timestamptz not null default now(),
  unique (account_id, kind, value),
  check (length(trim(kind)) > 0),
  check (length(trim(value)) > 0)
);

create table if not exists account_message_source_hints (
  account_id     uuid primary key references accounts(id) on delete cascade,
  sms_sender_ids text[] not null default '{}'::text[],
  email_domains  text[] not null default '{}'::text[],
  keywords       text[] not null default '{}'::text[],
  updated_at     timestamptz not null default now()
);

alter table account_match_identifiers enable row level security;
alter table account_message_source_hints enable row level security;

create index if not exists account_match_identifiers_account_kind_idx
  on account_match_identifiers (account_id, kind);

-- =========================================================================
-- Transaction FX fields documented for purchases/transfers
-- =========================================================================

alter table transactions
  add column if not exists original_amount_minor bigint,
  add column if not exists original_currency text references currencies(code),
  add column if not exists original_fx_rate numeric(20,10),
  add column if not exists counter_amount_minor bigint,
  add column if not exists counter_currency text references currencies(code),
  add column if not exists counter_fx_rate numeric(20,10);

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'transactions_original_amount_positive'
  ) then
    alter table transactions
      add constraint transactions_original_amount_positive
      check (original_amount_minor is null or original_amount_minor > 0);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'transactions_counter_amount_positive'
  ) then
    alter table transactions
      add constraint transactions_counter_amount_positive
      check (counter_amount_minor is null or counter_amount_minor > 0);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'transactions_original_currency_pair'
  ) then
    alter table transactions
      add constraint transactions_original_currency_pair
      check (
        (original_amount_minor is null and original_currency is null)
        or
        (original_amount_minor is not null and original_currency is not null)
      );
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'transactions_counter_currency_pair'
  ) then
    alter table transactions
      add constraint transactions_counter_currency_pair
      check (
        (counter_amount_minor is null and counter_currency is null)
        or
        (counter_amount_minor is not null and counter_currency is not null)
      );
  end if;
end $$;

-- =========================================================================
-- Capture-candidate FX fields and currency references
-- =========================================================================

alter table capture_candidates
  add column if not exists parsed_original_amount_minor bigint,
  add column if not exists parsed_original_currency text references currencies(code),
  add column if not exists parsed_original_fx_rate numeric(20,10);

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'capture_candidates_parsed_currency_fk'
  ) then
    alter table capture_candidates
      add constraint capture_candidates_parsed_currency_fk
      foreign key (parsed_currency) references currencies(code);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'capture_candidates_original_amount_positive'
  ) then
    alter table capture_candidates
      add constraint capture_candidates_original_amount_positive
      check (parsed_original_amount_minor is null or parsed_original_amount_minor > 0);
  end if;
end $$;

-- =========================================================================
-- Custom transaction fields
-- =========================================================================

create table if not exists custom_field_defs (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references users(id) on delete cascade,
  key        text not null,
  label      text not null,
  field_type text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, key),
  check (field_type in ('text', 'number', 'date', 'boolean')),
  check (length(trim(key)) > 0),
  check (length(trim(label)) > 0)
);

create table if not exists custom_field_values (
  transaction_id uuid not null references transactions(id) on delete cascade,
  field_id       uuid not null references custom_field_defs(id) on delete cascade,
  value_text     text,
  value_number   numeric(20,4),
  value_date     date,
  value_boolean  boolean,
  primary key (transaction_id, field_id),
  check (
    (case when value_text is not null then 1 else 0 end) +
    (case when value_number is not null then 1 else 0 end) +
    (case when value_date is not null then 1 else 0 end) +
    (case when value_boolean is not null then 1 else 0 end) <= 1
  )
);

alter table custom_field_defs enable row level security;
alter table custom_field_values enable row level security;

create index if not exists custom_field_defs_user_key_idx
  on custom_field_defs (user_id, key);

-- =========================================================================
-- Extra checks for card/loan extension tables
-- =========================================================================

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'credit_card_settings_cycle_day_range'
  ) then
    alter table credit_card_settings
      add constraint credit_card_settings_cycle_day_range
      check (cycle_start_day between 1 and 31 and due_day between 1 and 31);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'loan_settings_positive_values'
  ) then
    alter table loan_settings
      add constraint loan_settings_positive_values
      check (principal_minor > 0 and interest_rate >= 0 and tenure_months > 0 and emi_minor > 0);
  end if;
end $$;
