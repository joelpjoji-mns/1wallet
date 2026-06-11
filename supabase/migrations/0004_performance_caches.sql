-- 0004_performance_caches.sql
-- Hot-path indexes, timestamp/audit helpers, and cached account balances.
-- The mobile app remains local-first; these paths keep cloud reads fast at scale.

-- =========================================================================
-- Timestamp helper
-- =========================================================================

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Attach updated_at triggers to mutable tables that expose updated_at.
drop trigger if exists set_users_updated_at on users;
create trigger set_users_updated_at
  before update on users
  for each row execute function public.set_updated_at();

drop trigger if exists set_user_preferences_updated_at on user_preferences;
create trigger set_user_preferences_updated_at
  before update on user_preferences
  for each row execute function public.set_updated_at();

drop trigger if exists set_exchange_rates_updated_at on exchange_rates;
create trigger set_exchange_rates_updated_at
  before update on exchange_rates
  for each row execute function public.set_updated_at();

drop trigger if exists set_categories_updated_at on categories;
create trigger set_categories_updated_at
  before update on categories
  for each row execute function public.set_updated_at();

drop trigger if exists set_accounts_updated_at on accounts;
create trigger set_accounts_updated_at
  before update on accounts
  for each row execute function public.set_updated_at();

drop trigger if exists set_credit_card_settings_updated_at on credit_card_settings;
create trigger set_credit_card_settings_updated_at
  before update on credit_card_settings
  for each row execute function public.set_updated_at();

drop trigger if exists set_loan_settings_updated_at on loan_settings;
create trigger set_loan_settings_updated_at
  before update on loan_settings
  for each row execute function public.set_updated_at();

drop trigger if exists set_budgets_updated_at on budgets;
create trigger set_budgets_updated_at
  before update on budgets
  for each row execute function public.set_updated_at();

drop trigger if exists set_goals_updated_at on goals;
create trigger set_goals_updated_at
  before update on goals
  for each row execute function public.set_updated_at();

drop trigger if exists set_recurring_templates_updated_at on recurring_templates;
create trigger set_recurring_templates_updated_at
  before update on recurring_templates
  for each row execute function public.set_updated_at();

drop trigger if exists set_subscriptions_updated_at on subscriptions;
create trigger set_subscriptions_updated_at
  before update on subscriptions
  for each row execute function public.set_updated_at();

drop trigger if exists set_rules_updated_at on rules;
create trigger set_rules_updated_at
  before update on rules
  for each row execute function public.set_updated_at();

drop trigger if exists set_account_message_source_hints_updated_at on account_message_source_hints;
create trigger set_account_message_source_hints_updated_at
  before update on account_message_source_hints
  for each row execute function public.set_updated_at();

drop trigger if exists set_custom_field_defs_updated_at on custom_field_defs;
create trigger set_custom_field_defs_updated_at
  before update on custom_field_defs
  for each row execute function public.set_updated_at();

-- =========================================================================
-- Audit helper for direct user-owned core tables
-- =========================================================================

create or replace function public.audit_user_owned_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_entity_id uuid;
  v_action text;
  v_diff jsonb;
begin
  v_action = lower(tg_op);

  if tg_op = 'DELETE' then
    v_user_id = old.user_id;
    v_entity_id = old.id;
    v_diff = jsonb_build_object('old', to_jsonb(old) - 'raw_payload');
  elsif tg_op = 'UPDATE' then
    v_user_id = new.user_id;
    v_entity_id = new.id;
    v_diff = jsonb_build_object(
      'old', to_jsonb(old) - 'raw_payload',
      'new', to_jsonb(new) - 'raw_payload'
    );
  else
    v_user_id = new.user_id;
    v_entity_id = new.id;
    v_diff = jsonb_build_object('new', to_jsonb(new) - 'raw_payload');
  end if;

  insert into audit_log (user_id, entity, entity_id, action, diff, source)
  values (v_user_id, tg_table_name, v_entity_id, v_action, v_diff, 'db_trigger');

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

drop trigger if exists audit_accounts_changes on accounts;
create trigger audit_accounts_changes
  after insert or update or delete on accounts
  for each row execute function public.audit_user_owned_change();

drop trigger if exists audit_transactions_changes on transactions;
create trigger audit_transactions_changes
  after insert or update or delete on transactions
  for each row execute function public.audit_user_owned_change();

drop trigger if exists audit_categories_changes on categories;
create trigger audit_categories_changes
  after insert or update or delete on categories
  for each row execute function public.audit_user_owned_change();

drop trigger if exists audit_budgets_changes on budgets;
create trigger audit_budgets_changes
  after insert or update or delete on budgets
  for each row execute function public.audit_user_owned_change();

drop trigger if exists audit_goals_changes on goals;
create trigger audit_goals_changes
  after insert or update or delete on goals
  for each row execute function public.audit_user_owned_change();

drop trigger if exists audit_recurring_templates_changes on recurring_templates;
create trigger audit_recurring_templates_changes
  after insert or update or delete on recurring_templates
  for each row execute function public.audit_user_owned_change();

drop trigger if exists audit_capture_candidates_changes on capture_candidates;
create trigger audit_capture_candidates_changes
  after insert or update or delete on capture_candidates
  for each row execute function public.audit_user_owned_change();

-- =========================================================================
-- Hot-path indexes
-- =========================================================================

create index if not exists transactions_user_status_time_idx
  on transactions (user_id, status, occurred_at desc)
  where deleted_at is null;

create index if not exists transactions_user_source_time_idx
  on transactions (user_id, source, occurred_at desc)
  where source <> 'manual' and deleted_at is null;

create index if not exists transactions_merchant_time_idx
  on transactions (merchant_id, occurred_at desc)
  where merchant_id is not null and deleted_at is null;

create index if not exists transactions_person_time_idx
  on transactions (person_id, occurred_at desc)
  where person_id is not null and deleted_at is null;

create index if not exists transactions_project_time_idx
  on transactions (project_id, occurred_at desc)
  where project_id is not null and deleted_at is null;

create index if not exists transactions_trip_time_idx
  on transactions (trip_id, occurred_at desc)
  where trip_id is not null and deleted_at is null;

create index if not exists transactions_counter_account_time_idx
  on transactions (counter_account_id, occurred_at desc)
  where counter_account_id is not null and deleted_at is null;

create index if not exists capture_candidates_user_status_created_idx
  on capture_candidates (user_id, status, created_at desc);

create index if not exists budget_periods_budget_start_idx
  on budget_periods (budget_id, period_start desc);

create index if not exists loan_schedule_account_due_idx
  on loan_schedule (account_id, due_date);

create index if not exists card_statements_account_due_idx
  on card_statements (account_id, due_date desc);

create index if not exists recurring_templates_user_next_run_idx
  on recurring_templates (user_id, next_run_at)
  where is_paused = false;

create index if not exists reminders_user_trigger_idx
  on reminders (user_id, trigger_at)
  where is_sent = false;

create index if not exists import_sources_user_kind_idx
  on import_sources (user_id, kind);

create index if not exists imported_files_user_created_idx
  on imported_files (user_id, created_at desc);

-- =========================================================================
-- Account balance cache
-- =========================================================================

create table if not exists account_balance_cache (
  account_id              uuid primary key references accounts(id) on delete cascade,
  user_id                 uuid not null references users(id) on delete cascade,
  currency                text not null references currencies(code),
  current_balance_minor   bigint not null default 0,
  cleared_balance_minor   bigint not null default 0,
  scheduled_balance_minor bigint not null default 0,
  refreshed_at            timestamptz not null default now()
);

alter table account_balance_cache enable row level security;

drop policy if exists "owner_read" on account_balance_cache;
create policy "owner_read"
  on account_balance_cache for select
  using (user_id = auth.uid());

drop policy if exists "owner_refresh" on account_balance_cache;
create policy "owner_refresh"
  on account_balance_cache for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create index if not exists account_balance_cache_user_idx
  on account_balance_cache (user_id);

create or replace function public.transaction_account_effect(
  p_account_id uuid,
  p_type transaction_type,
  p_account_id_on_transaction uuid,
  p_counter_account_id uuid,
  p_amount_minor bigint,
  p_counter_amount_minor bigint
)
returns bigint
language sql
immutable
as $$
  select case
    when p_type in ('transfer', 'card_payment', 'loan_repayment')
      and p_account_id_on_transaction = p_account_id
      then -p_amount_minor
    when p_type in ('transfer', 'card_payment', 'loan_repayment')
      and p_counter_account_id = p_account_id
      then coalesce(p_counter_amount_minor, p_amount_minor)
    when p_account_id_on_transaction <> p_account_id then 0
    when p_type in ('income', 'refund', 'interest_in', 'cashback', 'borrowed', 'investment_sell')
      then p_amount_minor
    when p_type in ('expense', 'fee', 'interest_out', 'lent', 'investment_buy')
      then -p_amount_minor
    when p_type = 'adjustment'
      then p_amount_minor
    else 0
  end;
$$;

create or replace function public.recompute_account_balance(p_account_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account accounts%rowtype;
  v_cleared_delta bigint;
  v_scheduled_delta bigint;
begin
  select * into v_account
  from accounts
  where id = p_account_id
    and deleted_at is null;

  if not found then
    delete from account_balance_cache where account_id = p_account_id;
    return;
  end if;

  select coalesce(sum(public.transaction_account_effect(
    v_account.id,
    t.type,
    t.account_id,
    t.counter_account_id,
    t.amount_minor,
    t.counter_amount_minor
  )), 0)
  into v_cleared_delta
  from transactions t
  where t.deleted_at is null
    and t.status = 'cleared'
    and t.status <> 'void'
    and (t.account_id = v_account.id or t.counter_account_id = v_account.id);

  select coalesce(sum(public.transaction_account_effect(
    v_account.id,
    t.type,
    t.account_id,
    t.counter_account_id,
    t.amount_minor,
    t.counter_amount_minor
  )), 0)
  into v_scheduled_delta
  from transactions t
  where t.deleted_at is null
    and t.status = 'scheduled'
    and (t.account_id = v_account.id or t.counter_account_id = v_account.id);

  insert into account_balance_cache (
    account_id,
    user_id,
    currency,
    current_balance_minor,
    cleared_balance_minor,
    scheduled_balance_minor,
    refreshed_at
  ) values (
    v_account.id,
    v_account.user_id,
    v_account.currency,
    v_account.opening_balance_minor + v_cleared_delta,
    v_account.opening_balance_minor + v_cleared_delta,
    v_scheduled_delta,
    now()
  )
  on conflict (account_id) do update set
    user_id = excluded.user_id,
    currency = excluded.currency,
    current_balance_minor = excluded.current_balance_minor,
    cleared_balance_minor = excluded.cleared_balance_minor,
    scheduled_balance_minor = excluded.scheduled_balance_minor,
    refreshed_at = excluded.refreshed_at;
end;
$$;

create or replace function public.refresh_account_balance_from_transaction()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform public.recompute_account_balance(old.account_id);
    if old.counter_account_id is not null then
      perform public.recompute_account_balance(old.counter_account_id);
    end if;
  end if;

  if tg_op in ('INSERT', 'UPDATE') then
    perform public.recompute_account_balance(new.account_id);
    if new.counter_account_id is not null then
      perform public.recompute_account_balance(new.counter_account_id);
    end if;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

create or replace function public.refresh_account_balance_from_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    delete from account_balance_cache where account_id = old.id;
    return old;
  end if;

  perform public.recompute_account_balance(new.id);
  return new;
end;
$$;

drop trigger if exists refresh_account_balance_transactions on transactions;
create trigger refresh_account_balance_transactions
  after insert or update or delete on transactions
  for each row execute function public.refresh_account_balance_from_transaction();

drop trigger if exists refresh_account_balance_accounts on accounts;
create trigger refresh_account_balance_accounts
  after insert or update of opening_balance_minor, currency, user_id, deleted_at
  or delete on accounts
  for each row execute function public.refresh_account_balance_from_account();

create or replace function public.recompute_all_account_balances(p_user_id uuid default auth.uid())
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
  v_account_id uuid;
begin
  if p_user_id is null then
    raise exception 'A user id is required to recompute balances.';
  end if;

  if auth.uid() is not null and p_user_id <> auth.uid() then
    raise exception 'Cannot recompute balances for another user.';
  end if;

  for v_account_id in
    select id from accounts where user_id = p_user_id and deleted_at is null
  loop
    perform public.recompute_account_balance(v_account_id);
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

create or replace function public.get_account_summaries(p_user_id uuid default auth.uid())
returns table (
  account_id uuid,
  name text,
  type account_type,
  currency text,
  color text,
  current_balance_minor bigint,
  cleared_balance_minor bigint,
  scheduled_balance_minor bigint,
  is_archived boolean,
  sort_order integer
)
language sql
stable
security invoker
as $$
  select
    a.id as account_id,
    a.name,
    a.type,
    a.currency,
    a.color,
    coalesce(c.current_balance_minor, a.opening_balance_minor) as current_balance_minor,
    coalesce(c.cleared_balance_minor, a.opening_balance_minor) as cleared_balance_minor,
    coalesce(c.scheduled_balance_minor, 0) as scheduled_balance_minor,
    a.is_archived,
    a.sort_order
  from accounts a
  left join account_balance_cache c on c.account_id = a.id
  where a.user_id = p_user_id
    and a.deleted_at is null
  order by a.sort_order, a.name;
$$;
