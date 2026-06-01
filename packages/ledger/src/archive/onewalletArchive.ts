import type { UUID } from '@1wallet/domain/types';
import { normalizeLedgerState } from '../store/memory';
import type { FutureGenerationRule, LedgerState } from '../store/types';
import { LEDGER_STATE_VERSION } from '../store/types';

export const ONEWALLET_ARCHIVE_FORMAT = 'onewallet.ledger.archive';
export const ONEWALLET_ARCHIVE_VERSION = 1;

export type OneWalletArchiveSummary = {
  accounts: number;
  categories: number;
  transactions: number;
  transactionSplits: number;
  captureCandidates: number;
  importBatches: number;
  plannedPayments: number;
  loanAccounts: number;
  budgets: number;
  goals: number;
  exchangeRates: number;
  currencies: string[];
  dateRange?: { start: string; end: string };
};

export type OneWalletArchiveV1 = {
  format: typeof ONEWALLET_ARCHIVE_FORMAT;
  archiveVersion: typeof ONEWALLET_ARCHIVE_VERSION;
  ledgerStateVersion: number;
  exportedAt: string;
  source?: 'mobile' | 'web' | 'test' | 'unknown';
  summary: OneWalletArchiveSummary;
  ledger: LedgerState;
  checksum: string;
};

export type OneWalletArchiveValidation = {
  ok: boolean;
  errors: string[];
  warnings: string[];
  summary: OneWalletArchiveSummary;
};

export type OneWalletArchiveImportOptions = {
  userId?: UUID;
};

export class OneWalletArchiveError extends Error {
  readonly errors: string[];

  constructor(message: string, errors: string[] = [message]) {
    super(message);
    this.name = 'OneWalletArchiveError';
    this.errors = errors;
  }
}

export function exportOneWalletArchive(
  state: LedgerState,
  options: { exportedAt?: string; source?: OneWalletArchiveV1['source'] } = {},
): OneWalletArchiveV1 {
  const ledger = cloneJson({ ...state, version: LEDGER_STATE_VERSION });
  return {
    format: ONEWALLET_ARCHIVE_FORMAT,
    archiveVersion: ONEWALLET_ARCHIVE_VERSION,
    ledgerStateVersion: LEDGER_STATE_VERSION,
    exportedAt: options.exportedAt ?? new Date().toISOString(),
    source: options.source ?? 'unknown',
    summary: summarizeLedgerState(ledger),
    ledger,
    checksum: checksumLedgerState(ledger),
  };
}

export function parseOneWalletArchive(content: string): OneWalletArchiveV1 {
  let parsed: unknown;
  try {
    parsed = JSON.parse(content);
  } catch (error) {
    throw new OneWalletArchiveError(`Backup file is not valid JSON: ${(error as Error).message}`);
  }

  if (!isRecord(parsed)) {
    throw new OneWalletArchiveError('Backup file is empty or invalid.');
  }
  if (parsed.format !== ONEWALLET_ARCHIVE_FORMAT) {
    throw new OneWalletArchiveError('This is not a 1wallet backup file.');
  }
  if (parsed.archiveVersion !== ONEWALLET_ARCHIVE_VERSION) {
    const version = typeof parsed.archiveVersion === 'number' ? parsed.archiveVersion : 'unknown';
    throw new OneWalletArchiveError(`Unsupported 1wallet backup version: ${version}.`);
  }

  return parsed as OneWalletArchiveV1;
}

export function validateOneWalletArchive(archive: OneWalletArchiveV1): OneWalletArchiveValidation {
  const errors: string[] = [];
  const warnings: string[] = [];
  if (archive.format !== ONEWALLET_ARCHIVE_FORMAT) errors.push('Archive format is not 1wallet.');
  if (archive.archiveVersion !== ONEWALLET_ARCHIVE_VERSION) {
    errors.push(`Archive version ${archive.archiveVersion} is not supported.`);
  }
  if (typeof archive.ledgerStateVersion !== 'number') {
    errors.push('Archive ledger state version is missing.');
  } else if (archive.ledgerStateVersion > LEDGER_STATE_VERSION) {
    errors.push('Archive was created by a newer 1wallet version.');
  }
  if (!isRecord(archive.ledger)) errors.push('Archive does not contain a ledger.');

  const ledger = prepareArchiveLedger(archive.ledger);
  if (!archive.checksum) {
    errors.push('Archive checksum is missing.');
  } else if (archive.checksum !== checksumLedgerState(archive.ledger)) {
    errors.push('Archive checksum does not match the ledger content.');
  }

  validateLedgerReferences(ledger, errors, warnings);
  return { ok: errors.length === 0, errors, warnings, summary: summarizeLedgerState(ledger) };
}

export function ledgerStateFromOneWalletArchive(
  archive: OneWalletArchiveV1,
  options: OneWalletArchiveImportOptions = {},
): LedgerState {
  const validation = validateOneWalletArchive(archive);
  if (!validation.ok) {
    throw new OneWalletArchiveError('Backup file cannot be restored.', validation.errors);
  }
  const ledger = prepareArchiveLedger(archive.ledger);
  if (options.userId) rewriteLedgerUserId(ledger, options.userId);
  return ledger;
}

export function summarizeLedgerState(state: LedgerState): OneWalletArchiveSummary {
  const currencies = new Set<string>();
  pushCurrency(currencies, state.preferences.baseCurrency);
  pushCurrency(currencies, state.preferences.displayCurrency);
  state.preferences.enabledCurrencies?.forEach((currency) => pushCurrency(currencies, currency));
  state.accounts.forEach((account) => pushCurrency(currencies, account.currency));
  state.transactions.forEach((transaction) => {
    pushCurrency(currencies, transaction.amount.currency);
    pushCurrency(currencies, transaction.baseAmount.currency);
    pushCurrency(currencies, transaction.originalAmount?.currency);
    pushCurrency(currencies, transaction.counterAmount?.currency);
  });
  state.exchangeRates.forEach((rate) => {
    pushCurrency(currencies, rate.base);
    pushCurrency(currencies, rate.quote);
  });
  const dates = state.transactions
    .map((transaction) => transaction.occurredAt)
    .filter((value) => typeof value === 'string' && value.length > 0)
    .sort();

  return {
    accounts: state.accounts.length,
    categories: state.categories.length,
    transactions: state.transactions.length,
    transactionSplits: state.transactionSplits.length,
    captureCandidates: state.captureCandidates.length,
    importBatches: state.importBatches.length,
    plannedPayments: state.preferences.futureGenerationRules?.length ?? 0,
    loanAccounts: state.accounts.filter(
      (account) => account.type === 'loan' || account.type === 'lent',
    ).length,
    budgets: state.budgets.length,
    goals: state.goals.length,
    exchangeRates: state.exchangeRates.length,
    currencies: Array.from(currencies).sort(),
    ...(dates.length > 0
      ? { dateRange: { start: dates[0]!.slice(0, 10), end: dates[dates.length - 1]!.slice(0, 10) } }
      : {}),
  };
}

function prepareArchiveLedger(value: unknown): LedgerState {
  if (!isRecord(value)) return normalizeLedgerState({});
  const partial = cloneJson(value as Partial<LedgerState>);
  if (!partial.version || partial.version < LEDGER_STATE_VERSION) {
    return normalizeLedgerState(partial);
  }
  return { ...(partial as LedgerState), version: LEDGER_STATE_VERSION };
}

function validateLedgerReferences(state: LedgerState, errors: string[], warnings: string[]): void {
  const accountIds = uniqueIds('account', state.accounts, errors);
  const categoryIds = uniqueIds('category', state.categories, errors);
  const transactionIds = uniqueIds('transaction', state.transactions, errors);
  const captureCandidateIds = uniqueIds('capture candidate', state.captureCandidates, errors);
  const importBatchIds = uniqueIds('import batch', state.importBatches, errors);
  const merchantIds = uniqueIds('merchant', state.merchants, errors);
  const ruleIds = uniqueIds(
    'planned payment',
    state.preferences.futureGenerationRules ?? [],
    errors,
  );

  state.categories.forEach((category) => {
    if (category.parentId && !categoryIds.has(category.parentId)) {
      errors.push(`Category ${category.name} has a missing parent category.`);
    }
  });

  state.transactions.forEach((transaction) => {
    if (!accountIds.has(transaction.accountId)) {
      errors.push(`Transaction ${transaction.id} points to a missing account.`);
    }
    if (transaction.counterAccountId && !accountIds.has(transaction.counterAccountId)) {
      errors.push(`Transaction ${transaction.id} points to a missing counter account.`);
    }
    if (transaction.categoryId && !categoryIds.has(transaction.categoryId)) {
      errors.push(`Transaction ${transaction.id} points to a missing category.`);
    }
    if (transaction.merchantId && !merchantIds.has(transaction.merchantId)) {
      warnings.push(`Transaction ${transaction.id} points to a missing merchant.`);
    }
    if (transaction.recurringTemplateId && !ruleIds.has(transaction.recurringTemplateId)) {
      warnings.push(`Transaction ${transaction.id} points to a missing planned payment.`);
    }
    if (
      transaction.captureCandidateId &&
      !captureCandidateIds.has(transaction.captureCandidateId)
    ) {
      errors.push(`Transaction ${transaction.id} points to a missing capture candidate.`);
    }
    if (
      transaction.originalTransactionId &&
      !transactionIds.has(transaction.originalTransactionId)
    ) {
      errors.push(`Transaction ${transaction.id} points to a missing original transaction.`);
    }
  });

  state.transactionSplits.forEach((split) => {
    if (!transactionIds.has(split.transactionId)) {
      errors.push(`Split ${split.id} points to a missing transaction.`);
    }
    if (split.categoryId && !categoryIds.has(split.categoryId)) {
      errors.push(`Split ${split.id} points to a missing category.`);
    }
  });

  (state.preferences.futureGenerationRules ?? []).forEach((rule) => {
    validateRuleReferences(rule, accountIds, categoryIds, errors);
  });

  state.captureCandidates.forEach((candidate) => {
    validateCaptureCandidateReferences(
      candidate,
      accountIds,
      categoryIds,
      transactionIds,
      ruleIds,
      importBatchIds,
      errors,
      warnings,
    );
  });

  state.goals.forEach((goal) => {
    if (goal.linkedCategoryId && !categoryIds.has(goal.linkedCategoryId)) {
      errors.push(`Goal ${goal.name} points to a missing category.`);
    }
  });

  state.merchants.forEach((merchant) => {
    if (merchant.defaultCategoryId && !categoryIds.has(merchant.defaultCategoryId)) {
      warnings.push(`Merchant ${merchant.name} points to a missing category.`);
    }
  });

  state.accounts.forEach((account) => {
    const details = account.loanDetails;
    if (!details) return;
    if (details.repaymentSourceAccountId && !accountIds.has(details.repaymentSourceAccountId)) {
      errors.push(`Loan account ${account.name} has a missing repayment account.`);
    }
    if (details.linkedPlannedPaymentRuleId && !ruleIds.has(details.linkedPlannedPaymentRuleId)) {
      errors.push(`Loan account ${account.name} has a missing linked planned payment.`);
    }
  });
}

function validateCaptureCandidateReferences(
  candidate: LedgerState['captureCandidates'][number],
  accountIds: Set<string>,
  categoryIds: Set<string>,
  transactionIds: Set<string>,
  ruleIds: Set<string>,
  importBatchIds: Set<string>,
  errors: string[],
  warnings: string[],
): void {
  if (candidate.suggestedAccountId && !accountIds.has(candidate.suggestedAccountId)) {
    errors.push(`Capture candidate ${candidate.id} points to a missing account.`);
  }
  if (candidate.suggestedCounterAccountId && !accountIds.has(candidate.suggestedCounterAccountId)) {
    errors.push(`Capture candidate ${candidate.id} points to a missing counter account.`);
  }
  if (candidate.suggestedCategoryId && !categoryIds.has(candidate.suggestedCategoryId)) {
    errors.push(`Capture candidate ${candidate.id} points to a missing category.`);
  }
  if (candidate.postedTransactionId && !transactionIds.has(candidate.postedTransactionId)) {
    errors.push(`Capture candidate ${candidate.id} points to a missing posted transaction.`);
  }
  if (
    candidate.suggestedRecurringTemplateId &&
    !ruleIds.has(candidate.suggestedRecurringTemplateId)
  ) {
    warnings.push(`Capture candidate ${candidate.id} points to a missing planned payment.`);
  }
  if (candidate.importBatchId && !importBatchIds.has(candidate.importBatchId)) {
    errors.push(`Capture candidate ${candidate.id} points to a missing import batch.`);
  }
}

function validateRuleReferences(
  rule: FutureGenerationRule,
  accountIds: Set<string>,
  categoryIds: Set<string>,
  errors: string[],
): void {
  if (!accountIds.has(rule.accountId)) {
    errors.push(`Planned payment ${rule.name} points to a missing account.`);
  }
  if (rule.counterAccountId && !accountIds.has(rule.counterAccountId)) {
    errors.push(`Planned payment ${rule.name} points to a missing counter account.`);
  }
  if (rule.categoryId && !categoryIds.has(rule.categoryId)) {
    errors.push(`Planned payment ${rule.name} points to a missing category.`);
  }
}

function uniqueIds(
  label: string,
  items: ReadonlyArray<{ id: string }>,
  errors: string[],
): Set<string> {
  const ids = new Set<string>();
  for (const item of items) {
    if (!item.id) {
      errors.push(`A ${label} is missing an id.`);
      continue;
    }
    if (ids.has(item.id)) errors.push(`Duplicate ${label} id ${item.id}.`);
    ids.add(item.id);
  }
  return ids;
}

function rewriteLedgerUserId(state: LedgerState, userId: UUID): void {
  state.userId = userId;
  state.accounts.forEach((item) => (item.userId = userId));
  state.categories.forEach((item) => (item.userId = userId));
  state.transactions.forEach((item) => (item.userId = userId));
  state.transactionSplits.forEach((item) => (item.userId = userId));
  state.budgets.forEach((item) => (item.userId = userId));
  state.goals.forEach((item) => (item.userId = userId));
  state.captureCandidates.forEach((item) => (item.userId = userId));
  state.importBatches.forEach((item) => (item.userId = userId));
}

function checksumLedgerState(state: unknown): string {
  const input = stableStringify(state);
  let hash = 0x811c9dc5;
  for (let index = 0; index < input.length; index += 1) {
    hash ^= input.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return `fnv1a32:${(hash >>> 0).toString(16).padStart(8, '0')}`;
}

function stableStringify(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map((item) => stableStringify(item)).join(',')}]`;
  if (isRecord(value)) {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`)
      .join(',')}}`;
  }
  return JSON.stringify(value);
}

function cloneJson<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function pushCurrency(currencies: Set<string>, currency: string | undefined): void {
  if (currency) currencies.add(currency.toUpperCase());
}
