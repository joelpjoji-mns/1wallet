-- 0003_rls_policies.sql
-- Owner-scoped Row Level Security policies for Supabase Auth.
-- Service-role and migration connections bypass these policies; normal clients do not.

-- =========================================================================
-- Reference data: readable by every client, writable only by privileged roles.
-- =========================================================================

alter table currencies enable row level security;
alter table exchange_rates enable row level security;

drop policy if exists "reference_read" on currencies;
create policy "reference_read"
  on currencies for select
  using (true);

drop policy if exists "reference_read" on exchange_rates;
create policy "reference_read"
  on exchange_rates for select
  using (true);

-- =========================================================================
-- Direct user-owned rows
-- =========================================================================

drop policy if exists "owner_all" on users;
create policy "owner_all"
  on users for all
  using (id = auth.uid())
  with check (id = auth.uid());

drop policy if exists "owner_all" on user_preferences;
create policy "owner_all"
  on user_preferences for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "owner_all" on devices;
create policy "owner_all"
  on devices for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "owner_all" on accounts;
create policy "owner_all"
  on accounts for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "owner_all" on categories;
create policy "owner_all"
  on categories for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "owner_all" on tags;
create policy "owner_all"
  on tags for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "merchant_read" on merchants;
create policy "merchant_read"
  on merchants for select
  using (user_id is null or user_id = auth.uid());

drop policy if exists "merchant_insert" on merchants;
create policy "merchant_insert"
  on merchants for insert
  with check (user_id = auth.uid());

drop policy if exists "merchant_update" on merchants;
create policy "merchant_update"
  on merchants for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "merchant_delete" on merchants;
create policy "merchant_delete"
  on merchants for delete
  using (user_id = auth.uid());

drop policy if exists "owner_all" on people;
create policy "owner_all"
  on people for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "owner_all" on projects;
create policy "owner_all"
  on projects for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "owner_all" on trips;
create policy "owner_all"
  on trips for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "owner_all" on transactions;
create policy "owner_all"
  on transactions for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "owner_all" on attachments;
create policy "owner_all"
  on attachments for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "owner_all" on budgets;
create policy "owner_all"
  on budgets for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "owner_all" on goals;
create policy "owner_all"
  on goals for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "owner_all" on recurring_templates;
create policy "owner_all"
  on recurring_templates for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "owner_all" on reminders;
create policy "owner_all"
  on reminders for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "owner_all" on subscriptions;
create policy "owner_all"
  on subscriptions for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "owner_all" on rules;
create policy "owner_all"
  on rules for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "owner_all" on import_sources;
create policy "owner_all"
  on import_sources for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "owner_all" on imported_files;
create policy "owner_all"
  on imported_files for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "owner_all" on capture_candidates;
create policy "owner_all"
  on capture_candidates for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "owner_all" on trusted_senders;
create policy "owner_all"
  on trusted_senders for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "owner_all" on reconciliations;
create policy "owner_all"
  on reconciliations for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "owner_all" on sync_cursors;
create policy "owner_all"
  on sync_cursors for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "owner_all" on custom_field_defs;
create policy "owner_all"
  on custom_field_defs for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Audit logs are append-only for clients: owners can read and append safe rows,
-- but cannot update/delete history. Service-role audit triggers still bypass RLS.
drop policy if exists "owner_read" on audit_log;
create policy "owner_read"
  on audit_log for select
  using (user_id = auth.uid());

drop policy if exists "owner_insert" on audit_log;
create policy "owner_insert"
  on audit_log for insert
  with check (user_id = auth.uid());

-- =========================================================================
-- Account-owned child rows
-- =========================================================================

drop policy if exists "owner_all" on account_match_identifiers;
create policy "owner_all"
  on account_match_identifiers for all
  using (
    exists (
      select 1 from accounts a
      where a.id = account_id and a.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from accounts a
      where a.id = account_id and a.user_id = auth.uid()
    )
  );

drop policy if exists "owner_all" on account_message_source_hints;
create policy "owner_all"
  on account_message_source_hints for all
  using (
    exists (
      select 1 from accounts a
      where a.id = account_id and a.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from accounts a
      where a.id = account_id and a.user_id = auth.uid()
    )
  );

drop policy if exists "owner_all" on credit_card_settings;
create policy "owner_all"
  on credit_card_settings for all
  using (
    exists (
      select 1 from accounts a
      where a.id = account_id and a.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from accounts a
      where a.id = account_id and a.user_id = auth.uid()
    )
  );

drop policy if exists "owner_all" on card_statements;
create policy "owner_all"
  on card_statements for all
  using (
    exists (
      select 1 from accounts a
      where a.id = account_id and a.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from accounts a
      where a.id = account_id and a.user_id = auth.uid()
    )
  );

drop policy if exists "owner_all" on loan_settings;
create policy "owner_all"
  on loan_settings for all
  using (
    exists (
      select 1 from accounts a
      where a.id = account_id and a.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from accounts a
      where a.id = account_id and a.user_id = auth.uid()
    )
  );

drop policy if exists "owner_all" on loan_schedule;
create policy "owner_all"
  on loan_schedule for all
  using (
    exists (
      select 1 from accounts a
      where a.id = account_id and a.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from accounts a
      where a.id = account_id and a.user_id = auth.uid()
    )
  );

-- =========================================================================
-- Transaction-owned child rows
-- =========================================================================

drop policy if exists "owner_all" on transaction_splits;
create policy "owner_all"
  on transaction_splits for all
  using (
    exists (
      select 1 from transactions t
      where t.id = transaction_id and t.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from transactions t
      where t.id = transaction_id and t.user_id = auth.uid()
    )
  );

drop policy if exists "owner_all" on transaction_tags;
create policy "owner_all"
  on transaction_tags for all
  using (
    exists (
      select 1 from transactions t
      where t.id = transaction_id and t.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from transactions t
      where t.id = transaction_id and t.user_id = auth.uid()
    )
    and exists (
      select 1 from tags tg
      where tg.id = tag_id and tg.user_id = auth.uid()
    )
  );

drop policy if exists "owner_all" on custom_field_values;
create policy "owner_all"
  on custom_field_values for all
  using (
    exists (
      select 1 from transactions t
      where t.id = transaction_id and t.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from transactions t
      where t.id = transaction_id and t.user_id = auth.uid()
    )
    and exists (
      select 1 from custom_field_defs d
      where d.id = field_id and d.user_id = auth.uid()
    )
  );

-- =========================================================================
-- Budget and goal child rows
-- =========================================================================

drop policy if exists "owner_all" on budget_scopes;
create policy "owner_all"
  on budget_scopes for all
  using (
    exists (
      select 1 from budgets b
      where b.id = budget_id and b.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from budgets b
      where b.id = budget_id and b.user_id = auth.uid()
    )
    and (
      category_id is null
      or exists (select 1 from categories c where c.id = category_id and c.user_id = auth.uid())
    )
    and (
      tag_id is null
      or exists (select 1 from tags tg where tg.id = tag_id and tg.user_id = auth.uid())
    )
    and (
      account_id is null
      or exists (select 1 from accounts a where a.id = account_id and a.user_id = auth.uid())
    )
  );

drop policy if exists "owner_all" on budget_periods;
create policy "owner_all"
  on budget_periods for all
  using (
    exists (
      select 1 from budgets b
      where b.id = budget_id and b.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from budgets b
      where b.id = budget_id and b.user_id = auth.uid()
    )
  );

drop policy if exists "owner_all" on goal_funding_accounts;
create policy "owner_all"
  on goal_funding_accounts for all
  using (
    exists (
      select 1 from goals g
      where g.id = goal_id and g.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from goals g
      where g.id = goal_id and g.user_id = auth.uid()
    )
    and exists (
      select 1 from accounts a
      where a.id = account_id and a.user_id = auth.uid()
    )
  );

drop policy if exists "owner_all" on goal_contributions;
create policy "owner_all"
  on goal_contributions for all
  using (
    exists (
      select 1 from goals g
      where g.id = goal_id and g.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from goals g
      where g.id = goal_id and g.user_id = auth.uid()
    )
    and (
      transaction_id is null
      or exists (select 1 from transactions t where t.id = transaction_id and t.user_id = auth.uid())
    )
  );
