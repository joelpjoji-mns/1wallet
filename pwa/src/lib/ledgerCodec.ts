// JSON encode/decode helpers that mirror lib/src/data/ledger_codec.dart
// (specifically `_encodeCloudSnapshotData` / `_parseCloudRestoreData` and the
// per-model `*ToJson` / `*FromJson` functions) so the PWA can safely read and
// write the same GZip snapshot blob the Flutter app uses.
//
// Every parser is defensive: unexpected shapes fall back to sane defaults
// (matching the Dart helpers `_string`/`_int`/`_bool`/`_date`/...) instead of
// throwing, and any keys we don't explicitly model are preserved verbatim so
// round-tripping through the web app never silently destroys data written by
// a newer app version.

import {
  type Account,
  type AccountLoanDetails,
  type Category,
  DEFAULT_CURRENCY,
  type Extra,
  type LedgerPreferences,
  type LedgerSnapshot,
  type Money,
  type TransactionAttachment,
  type TransactionRecord,
  emptyLedgerSnapshot,
} from './ledgerTypes.ts';

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function str(value: unknown, fallback = ''): string {
  return typeof value === 'string' ? value : fallback;
}

function nullableStr(value: unknown): string | null {
  return typeof value === 'string' ? value : null;
}

function num_(value: unknown, fallback = 0): number {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string') {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return fallback;
}

function int_(value: unknown, fallback = 0): number {
  return Math.trunc(num_(value, fallback));
}

function nullableNum(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  return null;
}

function bool_(value: unknown, fallback = false): boolean {
  return typeof value === 'boolean' ? value : fallback;
}

function strList(value: unknown, fallback: string[] = []): string[] {
  if (Array.isArray(value)) return value.filter((v): v is string => typeof v === 'string');
  return fallback;
}

function numList(value: unknown): number[] | null {
  if (!Array.isArray(value)) return null;
  const out = value.filter((v): v is number => typeof v === 'number');
  return out.length ? out : null;
}

function stringMap(value: unknown, fallback: Record<string, string> = {}): Record<string, string> {
  if (!isPlainObject(value)) return fallback;
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(value)) {
    if (typeof v === 'string') out[k] = v;
  }
  return out;
}

function isoDate(value: unknown, fallback?: string): string {
  if (typeof value === 'string') {
    const parsed = Date.parse(value);
    if (!Number.isNaN(parsed)) return new Date(parsed).toISOString();
  }
  if (typeof value === 'number') {
    // Firestore Timestamp-like millis, defensive.
    const parsed = new Date(value);
    if (!Number.isNaN(parsed.getTime())) return parsed.toISOString();
  }
  // Firestore `Timestamp` instances (duck-typed, not imported here to keep
  // this module Firestore-independent) show up when decoding documents read
  // directly from Firestore collections rather than our own JSON blob — e.g.
  // the legacy per-document restore fallback in `walletSync.ts`.
  if (value != null && typeof value === 'object') {
    const maybeTimestamp = value as { toDate?: () => Date; toMillis?: () => number };
    if (typeof maybeTimestamp.toDate === 'function') {
      const date = maybeTimestamp.toDate();
      if (date instanceof Date && !Number.isNaN(date.getTime())) return date.toISOString();
    }
    if (typeof maybeTimestamp.toMillis === 'function') {
      const date = new Date(maybeTimestamp.toMillis());
      if (!Number.isNaN(date.getTime())) return date.toISOString();
    }
  }
  return fallback ?? new Date(0).toISOString();
}

/** Splits an object into (knownKeys extracted by caller) + everything else. */
function extraKeys(source: Record<string, unknown>, known: string[]): Extra {
  const extra: Extra = {};
  for (const [k, v] of Object.entries(source)) {
    if (!known.includes(k)) extra[k] = v;
  }
  return extra;
}

function generatedId(prefix: string): string {
  return `${prefix}_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 10)}`;
}

// ---------------------------------------------------------------------------
// Money
// ---------------------------------------------------------------------------

export function moneyToJson(money: Money): Record<string, unknown> {
  return { amountMinor: money.amountMinor, currency: money.currency };
}

export function moneyFromJson(value: unknown, fallback?: Money): Money {
  const json = isPlainObject(value) ? value : {};
  return {
    amountMinor: int_(json.amountMinor, fallback?.amountMinor ?? 0),
    currency: str(json.currency, fallback?.currency ?? DEFAULT_CURRENCY),
  };
}

// ---------------------------------------------------------------------------
// Account
// ---------------------------------------------------------------------------

const LOAN_DETAILS_KEYS = [
  'loanKind', 'principal', 'repaymentAmount', 'interestRatePercent',
  'repaymentCount', 'repaymentStartsOn', 'repaymentSourceAccountId',
  'recurrenceFrequency', 'recurrenceInterval', 'recurrenceDaysOfWeek',
  'recurrenceDaysOfMonth', 'recurrenceEndDate', 'recurrenceLimit',
  'hideInterestInLedger',
];

function loanDetailsToJson(details: AccountLoanDetails): Record<string, unknown> {
  const extra = extraKeys(details, LOAN_DETAILS_KEYS);
  return {
    ...extra,
    loanKind: details.loanKind ?? null,
    principal: details.principal ? moneyToJson(details.principal) : null,
    repaymentAmount: details.repaymentAmount ? moneyToJson(details.repaymentAmount) : null,
    interestRatePercent: details.interestRatePercent ?? null,
    repaymentCount: details.repaymentCount ?? null,
    repaymentStartsOn: details.repaymentStartsOn ?? null,
    repaymentSourceAccountId: details.repaymentSourceAccountId ?? null,
    recurrenceFrequency: details.recurrenceFrequency ?? 'monthly',
    recurrenceInterval: details.recurrenceInterval ?? 1,
    recurrenceDaysOfWeek: details.recurrenceDaysOfWeek ?? null,
    recurrenceDaysOfMonth: details.recurrenceDaysOfMonth ?? null,
    recurrenceEndDate: details.recurrenceEndDate ?? null,
    recurrenceLimit: details.recurrenceLimit ?? null,
    hideInterestInLedger: details.hideInterestInLedger ?? true,
  };
}

function loanDetailsFromJson(value: unknown, currency: string): AccountLoanDetails | null {
  if (!isPlainObject(value)) return null;
  if (Object.keys(value).length === 0) return null;
  const fallbackMoney: Money = { amountMinor: 0, currency };
  return {
    ...extraKeys(value, LOAN_DETAILS_KEYS),
    loanKind: nullableStr(value.loanKind),
    principal: value.principal == null ? null : moneyFromJson(value.principal, fallbackMoney),
    repaymentAmount:
      value.repaymentAmount == null ? null : moneyFromJson(value.repaymentAmount, fallbackMoney),
    interestRatePercent: nullableNum(value.interestRatePercent),
    repaymentCount: nullableNum(value.repaymentCount),
    repaymentStartsOn: value.repaymentStartsOn == null ? null : isoDate(value.repaymentStartsOn),
    repaymentSourceAccountId: nullableStr(value.repaymentSourceAccountId),
    recurrenceFrequency: str(value.recurrenceFrequency, 'monthly'),
    recurrenceInterval: int_(value.recurrenceInterval, 1),
    recurrenceDaysOfWeek: numList(value.recurrenceDaysOfWeek),
    recurrenceDaysOfMonth: numList(value.recurrenceDaysOfMonth),
    recurrenceEndDate: value.recurrenceEndDate == null ? null : isoDate(value.recurrenceEndDate),
    recurrenceLimit: nullableNum(value.recurrenceLimit),
    hideInterestInLedger: bool_(value.hideInterestInLedger, true),
  };
}

const ACCOUNT_KEYS = [
  'id', 'name', 'type', 'currency', 'openingBalance', 'color', 'institution',
  'groupName', 'loanDetails', 'encryptedDetails', 'cardLast4', 'accountLast4',
  'includeInTotals', 'includeInReports', 'includeInNetWorth', 'showOnHome',
  'isArchived', 'sortOrder', 'creditLimit',
];

export function accountToJson(account: Account): Record<string, unknown> {
  const extra = extraKeys(account, ACCOUNT_KEYS);
  return {
    ...extra,
    id: account.id,
    name: account.name,
    type: account.type,
    currency: account.currency,
    openingBalance: moneyToJson(account.openingBalance),
    color: account.color ?? null,
    institution: account.institution ?? null,
    groupName: account.groupName ?? null,
    loanDetails: account.loanDetails ? loanDetailsToJson(account.loanDetails) : null,
    // Opaque device-encrypted blob: never inspect or mutate, only round-trip.
    encryptedDetails: account.encryptedDetails ?? null,
    cardLast4: account.cardLast4 ?? null,
    accountLast4: account.accountLast4 ?? null,
    includeInTotals: account.includeInTotals,
    includeInReports: account.includeInReports,
    includeInNetWorth: account.includeInNetWorth,
    showOnHome: account.showOnHome,
    isArchived: account.isArchived,
    sortOrder: account.sortOrder,
    ...(account.creditLimit !== undefined
      ? { creditLimit: account.creditLimit ? moneyToJson(account.creditLimit) : null }
      : {}),
  };
}

export function accountFromJson(json: unknown): Account {
  const value = isPlainObject(json) ? json : {};
  const currency = str(value.currency, DEFAULT_CURRENCY);
  const encryptedDetailsRaw = value.encryptedDetails;
  return {
    ...extraKeys(value, ACCOUNT_KEYS),
    id: str(value.id, generatedId('acc')),
    name: str(value.name, 'Account'),
    type: str(value.type, 'bank'),
    currency,
    openingBalance: moneyFromJson(value.openingBalance, { amountMinor: 0, currency }),
    color: nullableNum(value.color),
    institution: nullableStr(value.institution),
    groupName: nullableStr(value.groupName),
    cardLast4: nullableStr(value.cardLast4),
    accountLast4: nullableStr(value.accountLast4),
    loanDetails: loanDetailsFromJson(value.loanDetails, currency),
    encryptedDetails: isPlainObject(encryptedDetailsRaw)
      ? (Object.fromEntries(
          Object.entries(encryptedDetailsRaw).filter(([, v]) => typeof v === 'string'),
        ) as Record<string, string>)
      : null,
    includeInTotals: bool_(value.includeInTotals, true),
    includeInReports: bool_(value.includeInReports, true),
    includeInNetWorth: bool_(value.includeInNetWorth, true),
    showOnHome: bool_(value.showOnHome, true),
    isArchived: bool_(value.isArchived, false),
    sortOrder: int_(value.sortOrder, 0),
    creditLimit: value.creditLimit == null ? null : moneyFromJson(value.creditLimit),
  };
}

// ---------------------------------------------------------------------------
// Category
// ---------------------------------------------------------------------------

const CATEGORY_KEYS = ['id', 'name', 'kind', 'color', 'parentId', 'isArchived', 'sortOrder'];

export function categoryToJson(category: Category): Record<string, unknown> {
  return {
    ...extraKeys(category, CATEGORY_KEYS),
    id: category.id,
    name: category.name,
    kind: category.kind,
    color: category.color ?? null,
    parentId: category.parentId ?? null,
    isArchived: category.isArchived,
    sortOrder: category.sortOrder,
  };
}

export function categoryFromJson(json: unknown): Category {
  const value = isPlainObject(json) ? json : {};
  return {
    ...extraKeys(value, CATEGORY_KEYS),
    id: str(value.id, generatedId('cat')),
    name: str(value.name, 'Category'),
    kind: str(value.kind, 'expense'),
    color: nullableNum(value.color),
    parentId: nullableStr(value.parentId),
    isArchived: bool_(value.isArchived, false),
    sortOrder: int_(value.sortOrder, 0),
  };
}

// ---------------------------------------------------------------------------
// Transaction
// ---------------------------------------------------------------------------

const ATTACHMENT_KEYS = ['id', 'source', 'name', 'uri', 'mimeType'];

function attachmentToJson(a: TransactionAttachment): Record<string, unknown> {
  return {
    ...extraKeys(a, ATTACHMENT_KEYS),
    id: a.id,
    source: a.source,
    name: a.name,
    uri: a.uri,
    mimeType: a.mimeType ?? null,
  };
}

function attachmentFromJson(json: unknown): TransactionAttachment {
  const value = isPlainObject(json) ? json : {};
  return {
    ...extraKeys(value, ATTACHMENT_KEYS),
    id: str(value.id, generatedId('att')),
    source: str(value.source, 'manual'),
    name: str(value.name),
    uri: str(value.uri),
    mimeType: nullableStr(value.mimeType),
  };
}

const TRANSACTION_KEYS = [
  'id', 'type', 'status', 'source', 'accountId', 'counterAccountId', 'amount',
  'baseAmount', 'counterAmount', 'originalAmount', 'fxRate', 'originalFxRate',
  'categoryId', 'occurredAt', 'locationLabel', 'paymentMethod', 'name',
  'notes', 'importBatchId', 'recurrenceFrequency', 'recurrenceInterval',
  'recurrenceDaysOfWeek', 'recurrenceDaysOfMonth', 'recurrenceEndDate',
  'recurrenceLimit', 'attachments', 'isReimbursable', 'isTaxDeductible',
  'isExcludedFromReports', 'sourceConfidence', 'externalRef',
  'originalTransactionId', 'postMode',
];

export function transactionToJson(t: TransactionRecord): Record<string, unknown> {
  return {
    ...extraKeys(t, TRANSACTION_KEYS),
    id: t.id,
    type: t.type,
    status: t.status,
    source: t.source,
    accountId: t.accountId,
    counterAccountId: t.counterAccountId ?? null,
    amount: moneyToJson(t.amount),
    baseAmount: moneyToJson(t.baseAmount),
    counterAmount: t.counterAmount ? moneyToJson(t.counterAmount) : null,
    originalAmount: t.originalAmount ? moneyToJson(t.originalAmount) : null,
    fxRate: t.fxRate ?? null,
    originalFxRate: t.originalFxRate ?? null,
    categoryId: t.categoryId ?? null,
    occurredAt: t.occurredAt,
    locationLabel: t.locationLabel ?? null,
    paymentMethod: t.paymentMethod ?? null,
    name: t.name ?? null,
    notes: t.notes ?? null,
    importBatchId: t.importBatchId ?? null,
    recurrenceFrequency: t.recurrenceFrequency ?? null,
    recurrenceInterval: t.recurrenceInterval,
    recurrenceDaysOfWeek: t.recurrenceDaysOfWeek ?? null,
    recurrenceDaysOfMonth: t.recurrenceDaysOfMonth ?? null,
    recurrenceEndDate: t.recurrenceEndDate ?? null,
    recurrenceLimit: t.recurrenceLimit ?? null,
    attachments: t.attachments.map(attachmentToJson),
    isReimbursable: t.isReimbursable,
    isTaxDeductible: t.isTaxDeductible,
    isExcludedFromReports: t.isExcludedFromReports,
    sourceConfidence: t.sourceConfidence ?? null,
    externalRef: t.externalRef ?? null,
    originalTransactionId: t.originalTransactionId ?? null,
    postMode: t.postMode ?? null,
  };
}

export function transactionFromJson(json: unknown): TransactionRecord {
  const value = isPlainObject(json) ? json : {};
  const amount = moneyFromJson(value.amount);
  return {
    ...extraKeys(value, TRANSACTION_KEYS),
    id: str(value.id, generatedId('tx')),
    type: str(value.type, 'expense'),
    status: str(value.status, 'cleared'),
    source: str(value.source, 'manual'),
    accountId: str(value.accountId, ''),
    counterAccountId: nullableStr(value.counterAccountId),
    amount,
    baseAmount: moneyFromJson(value.baseAmount, amount),
    counterAmount: value.counterAmount == null ? null : moneyFromJson(value.counterAmount, amount),
    originalAmount:
      value.originalAmount == null ? null : moneyFromJson(value.originalAmount, amount),
    fxRate: nullableNum(value.fxRate),
    originalFxRate: nullableNum(value.originalFxRate),
    categoryId: nullableStr(value.categoryId),
    occurredAt: isoDate(value.occurredAt),
    locationLabel: nullableStr(value.locationLabel),
    paymentMethod: nullableStr(value.paymentMethod),
    name: nullableStr(value.name),
    notes: nullableStr(value.notes),
    importBatchId: nullableStr(value.importBatchId),
    recurrenceFrequency: nullableStr(value.recurrenceFrequency),
    recurrenceInterval: int_(value.recurrenceInterval, 1),
    recurrenceDaysOfWeek: numList(value.recurrenceDaysOfWeek),
    recurrenceDaysOfMonth: numList(value.recurrenceDaysOfMonth),
    recurrenceEndDate: value.recurrenceEndDate == null ? null : isoDate(value.recurrenceEndDate),
    recurrenceLimit: nullableNum(value.recurrenceLimit),
    attachments: Array.isArray(value.attachments) ? value.attachments.map(attachmentFromJson) : [],
    isReimbursable: bool_(value.isReimbursable, false),
    isTaxDeductible: bool_(value.isTaxDeductible, false),
    isExcludedFromReports: bool_(value.isExcludedFromReports, false),
    sourceConfidence: nullableNum(value.sourceConfidence),
    externalRef: nullableStr(value.externalRef),
    originalTransactionId: nullableStr(value.originalTransactionId),
    postMode: nullableStr(value.postMode),
  };
}

// ---------------------------------------------------------------------------
// Preferences (kept mostly opaque; the PWA reads a handful of fields today)
// ---------------------------------------------------------------------------

const PREFERENCES_KEYS = [
  'baseCurrency', 'displayCurrency', 'enabledCurrencies', 'locale',
  'startDayOfMonth', 'homeWidgetOrder', 'homeWidgetHidden', 'homeWidgetSizes',
  'homeWidgetFilters', 'homeWidgets', 'futureGenerationRules',
  'hideSkippedInHistory',
];

export function preferencesToJson(p: LedgerPreferences): Record<string, unknown> {
  return {
    ...extraKeys(p, PREFERENCES_KEYS),
    baseCurrency: p.baseCurrency,
    displayCurrency: p.displayCurrency,
    enabledCurrencies: p.enabledCurrencies,
    locale: p.locale,
    startDayOfMonth: p.startDayOfMonth,
    homeWidgetOrder: p.homeWidgetOrder,
    homeWidgetHidden: p.homeWidgetHidden,
    homeWidgetSizes: p.homeWidgetSizes,
    homeWidgetFilters: p.homeWidgetFilters,
    homeWidgets: {
      order: p.homeWidgetOrder,
      hidden: p.homeWidgetHidden,
      sizes: p.homeWidgetSizes,
      filters: p.homeWidgetFilters,
    },
    ...(p.futureGenerationRules ? { futureGenerationRules: p.futureGenerationRules } : {}),
    hideSkippedInHistory: p.hideSkippedInHistory,
  };
}

export function preferencesFromJson(json: unknown): LedgerPreferences {
  const value = isPlainObject(json) ? json : {};
  return {
    ...extraKeys(value, PREFERENCES_KEYS),
    baseCurrency: str(value.baseCurrency, DEFAULT_CURRENCY),
    displayCurrency: str(value.displayCurrency, DEFAULT_CURRENCY),
    enabledCurrencies: strList(value.enabledCurrencies, [DEFAULT_CURRENCY]),
    locale: str(value.locale, 'en_US'),
    startDayOfMonth: int_(value.startDayOfMonth, 1),
    homeWidgetOrder: strList(value.homeWidgetOrder),
    homeWidgetHidden: strList(value.homeWidgetHidden),
    homeWidgetSizes: stringMap(value.homeWidgetSizes),
    homeWidgetFilters: stringMap(value.homeWidgetFilters),
    futureGenerationRules: Array.isArray(value.futureGenerationRules)
      ? (value.futureGenerationRules as Extra[])
      : undefined,
    hideSkippedInHistory: bool_(value.hideSkippedInHistory, false),
  };
}

// ---------------------------------------------------------------------------
// Whole-snapshot encode/decode — mirrors `_encodeCloudSnapshotData` /
// `_parseCloudRestoreData` in cloud_sync_controller.dart exactly.
// ---------------------------------------------------------------------------

export function encodeSnapshot(snapshot: LedgerSnapshot): Record<string, unknown> {
  return {
    syncSettings: snapshot.syncSettings,
    preferences: preferencesToJson(snapshot.preferences),
    accounts: snapshot.accounts.map(accountToJson),
    categories: snapshot.categories.map(categoryToJson),
    transactions: snapshot.transactions.map(transactionToJson),
    captureCandidates: snapshot.captureCandidates,
    importBatches: snapshot.importBatches,
    exchangeRates: snapshot.exchangeRates,
  };
}

export function decodeSnapshot(json: unknown): LedgerSnapshot {
  const value = isPlainObject(json) ? json : {};
  const empty = emptyLedgerSnapshot();
  return {
    syncSettings: isPlainObject(value.syncSettings) ? (value.syncSettings as Extra) : null,
    preferences: value.preferences !== undefined
      ? preferencesFromJson(value.preferences)
      : empty.preferences,
    accounts: Array.isArray(value.accounts) ? value.accounts.map(accountFromJson) : [],
    categories: Array.isArray(value.categories) ? value.categories.map(categoryFromJson) : [],
    transactions: Array.isArray(value.transactions)
      ? value.transactions.map(transactionFromJson)
      : [],
    captureCandidates: Array.isArray(value.captureCandidates)
      ? (value.captureCandidates as Extra[])
      : [],
    importBatches: Array.isArray(value.importBatches) ? (value.importBatches as Extra[]) : [],
    exchangeRates: Array.isArray(value.exchangeRates) ? (value.exchangeRates as Extra[]) : [],
  };
}

/**
 * Mirrors `LedgerState.isIncomingLedgerSafer` in ledger_models.dart: guards
 * against an empty/outdated remote snapshot silently destroying data that is
 * newer or more complete locally.
 */
export function isIncomingSnapshotSafer(
  local: LedgerSnapshot,
  incoming: LedgerSnapshot,
): boolean {
  if (incoming.transactions.length === 0 && local.transactions.length > 0) return false;
  if (incoming.transactions.length < local.transactions.length) return false;

  const byRecency = (a: TransactionRecord, b: TransactionRecord) =>
    Date.parse(b.occurredAt) - Date.parse(a.occurredAt);
  const localTop = [...local.transactions].sort(byRecency).slice(0, 5);
  const incomingTop = [...incoming.transactions].sort(byRecency).slice(0, 5);

  for (let i = 0; i < localTop.length; i++) {
    if (i >= incomingTop.length) break;
    if (Date.parse(localTop[i].occurredAt) > Date.parse(incomingTop[i].occurredAt)) {
      return false;
    }
  }
  return true;
}
