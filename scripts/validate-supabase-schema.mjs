import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..');
const migrationsDir = path.join(repoRoot, 'supabase', 'migrations');

const requiredMigrationFiles = [
  '0001_init.sql',
  '0002_schema_reconciliation.sql',
  '0003_rls_policies.sql',
  '0004_performance_caches.sql',
];

const failures = [];
const migrationSources = [];

for (const file of requiredMigrationFiles) {
  const filePath = path.join(migrationsDir, file);
  if (!existsSync(filePath)) {
    failures.push(`Missing migration: ${file}`);
    continue;
  }
  migrationSources.push(readFileSync(filePath, 'utf8'));
}

const sql = migrationSources.join('\n\n').toLowerCase();

function requirePattern(label, pattern) {
  if (!pattern.test(sql)) failures.push(label);
}

function escaped(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function requireTable(table) {
  requirePattern(
    `Missing table definition for ${table}`,
    new RegExp(`create\\s+table\\s+(if\\s+not\\s+exists\\s+)?${escaped(table)}\\b`, 'i'),
  );
}

function requireColumn(table, column) {
  requirePattern(
    `Missing column ${table}.${column}`,
    new RegExp(`\\b${escaped(column)}\\b`, 'i'),
  );
}

function requirePolicy(table) {
  requirePattern(
    `Missing policy creation for ${table}`,
    new RegExp(`create\\s+policy[\\s\\S]+?on\\s+${escaped(table)}\\b`, 'i'),
  );
}

function requireIndex(indexName) {
  requirePattern(
    `Missing index ${indexName}`,
    new RegExp(`create\\s+index\\s+if\\s+not\\s+exists\\s+${escaped(indexName)}\\b`, 'i'),
  );
}

for (const table of [
  'account_match_identifiers',
  'account_message_source_hints',
  'custom_field_defs',
  'custom_field_values',
  'account_balance_cache',
]) {
  requireTable(table);
}

for (const [table, columns] of Object.entries({
  user_preferences: ['display_currency', 'enabled_currencies'],
  exchange_rates: ['provider', 'refreshed_at', 'updated_at'],
  transactions: [
    'original_amount_minor',
    'original_currency',
    'original_fx_rate',
    'counter_amount_minor',
    'counter_currency',
    'counter_fx_rate',
  ],
  capture_candidates: [
    'parsed_original_amount_minor',
    'parsed_original_currency',
    'parsed_original_fx_rate',
  ],
})) {
  for (const column of columns) requireColumn(table, column);
}

for (const table of [
  'users',
  'user_preferences',
  'accounts',
  'categories',
  'transactions',
  'transaction_tags',
  'transaction_splits',
  'budgets',
  'budget_scopes',
  'budget_periods',
  'goals',
  'goal_funding_accounts',
  'capture_candidates',
  'account_match_identifiers',
  'account_message_source_hints',
  'custom_field_defs',
  'custom_field_values',
  'audit_log',
  'sync_cursors',
  'account_balance_cache',
]) {
  requirePolicy(table);
}

for (const indexName of [
  'transactions_user_status_time_idx',
  'transactions_user_source_time_idx',
  'transactions_counter_account_time_idx',
  'capture_candidates_user_status_created_idx',
  'budget_periods_budget_start_idx',
  'loan_schedule_account_due_idx',
  'account_balance_cache_user_idx',
]) {
  requireIndex(indexName);
}

for (const fnName of [
  'set_updated_at',
  'audit_user_owned_change',
  'transaction_account_effect',
  'recompute_account_balance',
  'refresh_account_balance_from_transaction',
  'refresh_account_balance_from_account',
  'recompute_all_account_balances',
  'get_account_summaries',
]) {
  requirePattern(
    `Missing function ${fnName}`,
    new RegExp(`create\\s+or\\s+replace\\s+function\\s+public\\.${escaped(fnName)}\\b`, 'i'),
  );
}

for (const phrase of [
  'alter table currencies enable row level security',
  'alter table exchange_rates enable row level security',
  'alter table account_balance_cache enable row level security',
]) {
  requirePattern(`Missing RLS enablement: ${phrase}`, new RegExp(escaped(phrase), 'i'));
}

if (failures.length > 0) {
  console.error('Supabase schema validation failed:');
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log('Supabase schema validation passed.');
console.log(`Checked ${requiredMigrationFiles.length} migrations for reconciliation, RLS, indexes, cache, and helper functions.`);
