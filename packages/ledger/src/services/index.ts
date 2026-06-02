import type { Money } from '@1wallet/domain/money';
import { addMoney, fromMinor, normalizeCurrencyCode, toMinor } from '@1wallet/domain/money';
import type {
  Account,
  AccountLoanDetails,
  AccountMatchIdentifier,
  AccountMatchIdentifierKind,
  AccountMessageHint,
  AccountMessageSourceHints,
  AccountType,
  CaptureCandidate,
  CaptureCandidateStatus,
  Category,
  CategoryKind,
  ImportBatch,
  ImportBatchSource,
  ImportBatchStatus,
  Transaction,
  TransactionAttachment,
  TransactionSource,
  TransactionSplit,
  TransactionType,
  UUID,
} from '@1wallet/domain/types';
import { nowIso, todayIso, uid } from '../id';
import type { ExchangeRateRecord, ExchangeRateSource, LedgerState } from '../store/types';

// ============================================================================
// Accounts
// ============================================================================

export interface CreateAccountInput {
  name: string;
  type: AccountType;
  currency: string;
  openingBalanceMinor: number;
  openingDate?: string;
  icon?: string;
  color?: string;
  institution?: string;
  accountNickname?: string;
  loanDetails?: AccountLoanDetails;
  matchIdentifiers?: AccountMatchIdentifier[];
  messageSourceHints?: AccountMessageSourceHints;
  includeInTotals?: boolean;
  includeInBudgets?: boolean;
  includeInReports?: boolean;
  includeInNetWorth?: boolean;
  showOnHome?: boolean;
  notes?: string;
  groupName?: string;
}

export function createAccount(state: LedgerState, input: CreateAccountInput): Account {
  const now = nowIso();
  const acct: Account = {
    id: uid(),
    userId: state.userId,
    name: input.name,
    type: input.type,
    currency: input.currency,
    icon: input.icon,
    color: input.color,
    institution: input.institution,
    accountNickname: input.accountNickname,
    loanDetails: input.loanDetails,
    matchIdentifiers: input.matchIdentifiers,
    messageSourceHints: input.messageSourceHints,
    openingBalance: { amountMinor: input.openingBalanceMinor, currency: input.currency },
    openingDate: input.openingDate ?? todayIso(),
    includeInTotals: input.includeInTotals ?? true,
    includeInBudgets: input.includeInBudgets ?? true,
    includeInReports: input.includeInReports ?? true,
    includeInNetWorth: input.includeInNetWorth ?? true,
    showOnHome: input.showOnHome ?? true,
    isArchived: false,
    isDefault: state.accounts.length === 0,
    notes: input.notes,
    sortOrder: state.accounts.length,
    groupName: input.groupName,
    createdAt: now,
    updatedAt: now,
  };
  state.accounts.push(acct);
  ensureEnabledCurrency(state, acct.currency);
  return acct;
}

export function updateAccount(
  state: LedgerState,
  id: UUID,
  patch: Partial<CreateAccountInput> & { isArchived?: boolean; sortOrder?: number },
): Account | undefined {
  const acct = state.accounts.find((a) => a.id === id);
  if (!acct) return undefined;
  if (patch.name !== undefined) acct.name = patch.name;
  if (patch.type !== undefined) acct.type = patch.type;
  if (patch.currency !== undefined) {
    acct.currency = patch.currency;
    acct.openingBalance = { ...acct.openingBalance, currency: patch.currency };
    ensureEnabledCurrency(state, patch.currency);
  }
  if (patch.icon !== undefined) acct.icon = patch.icon;
  if (patch.color !== undefined) acct.color = patch.color;
  if (patch.institution !== undefined) acct.institution = patch.institution;
  if (patch.accountNickname !== undefined) acct.accountNickname = patch.accountNickname;
  if (patch.loanDetails !== undefined) acct.loanDetails = patch.loanDetails;
  if (patch.matchIdentifiers !== undefined) acct.matchIdentifiers = patch.matchIdentifiers;
  if (patch.messageSourceHints !== undefined) acct.messageSourceHints = patch.messageSourceHints;
  if (patch.openingBalanceMinor !== undefined) {
    acct.openingBalance = { amountMinor: patch.openingBalanceMinor, currency: acct.currency };
  }
  if (patch.openingDate !== undefined) acct.openingDate = patch.openingDate;
  if (patch.includeInTotals !== undefined) acct.includeInTotals = patch.includeInTotals;
  if (patch.includeInBudgets !== undefined) acct.includeInBudgets = patch.includeInBudgets;
  if (patch.includeInReports !== undefined) acct.includeInReports = patch.includeInReports;
  if (patch.includeInNetWorth !== undefined) acct.includeInNetWorth = patch.includeInNetWorth;
  if (patch.showOnHome !== undefined) acct.showOnHome = patch.showOnHome;
  if (patch.notes !== undefined) acct.notes = patch.notes;
  if (patch.groupName !== undefined) acct.groupName = patch.groupName;
  if (patch.isArchived !== undefined) {
    acct.isArchived = patch.isArchived;
    if (patch.isArchived && patch.showOnHome === undefined) acct.showOnHome = false;
  }
  if (patch.sortOrder !== undefined) acct.sortOrder = patch.sortOrder;
  acct.updatedAt = nowIso();
  return acct;
}

export function deleteAccount(state: LedgerState, id: UUID): boolean {
  // Soft-archive an account if it has transactions; only fully remove if empty.
  const hasTxns = state.transactions.some((t) => t.accountId === id || t.counterAccountId === id);
  if (hasTxns) {
    return updateAccount(state, id, { isArchived: true }) !== undefined;
  }
  const before = state.accounts.length;
  state.accounts = state.accounts.filter((a) => a.id !== id);
  return state.accounts.length < before;
}

export function mergeAcceptedMessageAccountHints(
  state: LedgerState,
  accountId: UUID,
  hints: ReadonlyArray<AccountMessageHint>,
): Account | undefined {
  const account = state.accounts.find((item) => item.id === accountId);
  if (!account || hints.length === 0) return account;

  const matchIdentifiers = [...(account.matchIdentifiers ?? [])];
  const smsSenderIds = [...(account.messageSourceHints?.smsSenderIds ?? [])];
  const emailDomains = [...(account.messageSourceHints?.emailDomains ?? [])];
  const keywords = [...(account.messageSourceHints?.keywords ?? [])];

  for (const hint of hints) {
    if (hint.target === 'match_identifier' && isMatchIdentifierKind(hint.kind)) {
      const normalized = normalizeMessageIdentifierValue(hint.kind, hint.value);
      if (!normalized) continue;
      const exists = matchIdentifiers.some(
        (identifier) =>
          identifier.kind === hint.kind &&
          normalizeMessageIdentifierValue(identifier.kind, identifier.value) === normalized,
      );
      if (!exists) {
        matchIdentifiers.push({
          kind: hint.kind,
          value: normalized,
          label: hint.label,
          verified: hint.verified ?? false,
        });
      }
      continue;
    }

    if (hint.kind === 'sms_sender_id')
      pushUnique(smsSenderIds, normalizeMessageSenderId(hint.value));
    else if (hint.kind === 'email_domain') {
      pushUnique(emailDomains, normalizeMessageEmailDomain(hint.value));
    } else if (hint.kind === 'keyword') {
      pushUnique(keywords, hint.value.trim());
    }
  }

  account.matchIdentifiers = matchIdentifiers.length > 0 ? matchIdentifiers : undefined;
  account.messageSourceHints =
    smsSenderIds.length > 0 || emailDomains.length > 0 || keywords.length > 0
      ? {
          ...(smsSenderIds.length > 0 ? { smsSenderIds } : {}),
          ...(emailDomains.length > 0 ? { emailDomains } : {}),
          ...(keywords.length > 0 ? { keywords } : {}),
        }
      : undefined;
  account.updatedAt = nowIso();
  return account;
}

function isMatchIdentifierKind(
  kind: AccountMessageHint['kind'],
): kind is AccountMatchIdentifierKind {
  return (
    kind === 'account_last4' ||
    kind === 'card_last4' ||
    kind === 'iban_last4' ||
    kind === 'sort_code' ||
    kind === 'upi_vpa' ||
    kind === 'phone_last4' ||
    kind === 'masked_number' ||
    kind === 'customer_ref'
  );
}

function normalizeMessageIdentifierValue(kind: AccountMatchIdentifierKind, value: string): string {
  if (kind === 'upi_vpa') return value.trim().toLowerCase();
  if (kind === 'sort_code') {
    const digits = value.replace(/\D/g, '');
    return digits.length === 6
      ? `${digits.slice(0, 2)}-${digits.slice(2, 4)}-${digits.slice(4, 6)}`
      : '';
  }
  if (kind === 'customer_ref') return value.trim();
  return value.replace(/\D/g, '').slice(-4);
}

function normalizeMessageSenderId(value: string): string {
  return value
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, '');
}

function normalizeMessageEmailDomain(value: string): string {
  const normalized = value.trim().toLowerCase();
  const [, domain = normalized] = normalized.split('@');
  return domain.replace(/^www\./, '');
}

function pushUnique(items: string[], value: string): void {
  const normalized = value.trim();
  if (!normalized) return;
  if (!items.some((item) => item.toLowerCase() === normalized.toLowerCase())) {
    items.push(normalized);
  }
}

// ============================================================================
// Balances
// ============================================================================

const INFLOW_TYPES = new Set<TransactionType>([
  'income',
  'refund',
  'interest_in',
  'cashback',
  'borrowed',
  'investment_sell',
]);
const OUTFLOW_TYPES = new Set<TransactionType>([
  'expense',
  'fee',
  'interest_out',
  'lent',
  'investment_buy',
]);
const TRANSFER_TYPES = new Set<TransactionType>(['transfer', 'card_payment', 'loan_repayment']);

function affectsPostedBalance(transaction: Transaction): boolean {
  return transaction.status !== 'scheduled' && transaction.status !== 'void';
}

function assertTransactionAmount(type: TransactionType, amountMinor: number, action: string): void {
  if (type === 'adjustment') {
    if (amountMinor === 0) throw new Error(`${action}: adjustment amount must be non-zero`);
    return;
  }
  if (amountMinor <= 0) throw new Error(`${action}: amount must be positive`);
}

export function accountBalance(state: LedgerState, accountId: UUID): Money {
  const acct = state.accounts.find((a) => a.id === accountId);
  if (!acct) return { amountMinor: 0, currency: 'INR' };
  let balance = acct.openingBalance.amountMinor;
  for (const t of state.transactions) {
    if (!affectsPostedBalance(t)) continue;
    if (t.accountId === accountId) {
      const accountAmountMinor = amountInCurrency(state, t.amount, acct.currency);
      if (INFLOW_TYPES.has(t.type)) balance += accountAmountMinor;
      else if (OUTFLOW_TYPES.has(t.type)) balance -= accountAmountMinor;
      else if (TRANSFER_TYPES.has(t.type)) balance -= accountAmountMinor;
      else if (t.type === 'adjustment') balance += accountAmountMinor;
    }
    if (TRANSFER_TYPES.has(t.type) && t.counterAccountId === accountId) {
      balance += transferCounterAmountMinor(state, t, acct.currency);
    }
  }
  return { amountMinor: balance, currency: acct.currency };
}

// ============================================================================
// Transactions
// ============================================================================

export interface CreateTransactionInput {
  type: TransactionType;
  accountId: UUID;
  counterAccountId?: UUID;
  amountMinor: number;
  currency?: string;
  originalAmountMinor?: number;
  originalCurrency?: string;
  originalFxRate?: number;
  counterAmountMinor?: number;
  counterCurrency?: string;
  counterFxRate?: number;
  occurredAt?: string;
  locationLabel?: string;
  categoryId?: UUID;
  merchantId?: UUID;
  notes?: string;
  attachments?: TransactionAttachment[];
  tags?: string[];
  paymentMethod?: string;
  isReimbursable?: boolean;
  isTaxDeductible?: boolean;
  isExcludedFromReports?: boolean;
  fxRate?: number;
  source?: Transaction['source'];
  sourceConfidence?: number;
  captureCandidateId?: UUID;
  originalTransactionId?: UUID;
  recurringTemplateId?: UUID;
  externalRef?: string;
  status?: Transaction['status'];
}

export interface CreateTransactionSplitInput {
  transactionId: UUID;
  amountMinor: number;
  currency?: string;
  categoryId?: UUID;
  notes?: string;
  sortOrder?: number;
}

export interface UpdateTransactionSplitInput {
  amountMinor?: number;
  currency?: string;
  categoryId?: UUID | null;
  notes?: string | null;
  sortOrder?: number;
}

export type UpdateTransactionInput = Omit<
  Partial<CreateTransactionInput>,
  | 'counterAccountId'
  | 'categoryId'
  | 'merchantId'
  | 'locationLabel'
  | 'notes'
  | 'attachments'
  | 'tags'
  | 'paymentMethod'
  | 'captureCandidateId'
  | 'originalTransactionId'
  | 'recurringTemplateId'
  | 'externalRef'
  | 'originalAmountMinor'
  | 'originalCurrency'
  | 'originalFxRate'
  | 'counterAmountMinor'
  | 'counterCurrency'
  | 'counterFxRate'
> & {
  counterAccountId?: UUID | null;
  originalAmountMinor?: number | null;
  originalCurrency?: string | null;
  originalFxRate?: number | null;
  counterAmountMinor?: number | null;
  counterCurrency?: string | null;
  counterFxRate?: number | null;
  categoryId?: UUID | null;
  merchantId?: UUID | null;
  locationLabel?: string | null;
  notes?: string | null;
  attachments?: TransactionAttachment[] | null;
  tags?: string[] | null;
  paymentMethod?: string | null;
  captureCandidateId?: UUID | null;
  originalTransactionId?: UUID | null;
  recurringTemplateId?: UUID | null;
  externalRef?: string | null;
};

export function createTransaction(state: LedgerState, input: CreateTransactionInput): Transaction {
  const acct = state.accounts.find((a) => a.id === input.accountId);
  if (!acct) throw new Error(`createTransaction: account ${input.accountId} not found`);
  const counterAcct = input.counterAccountId
    ? state.accounts.find((a) => a.id === input.counterAccountId)
    : undefined;
  const isTransfer = TRANSFER_TYPES.has(input.type);
  if (isTransfer) {
    if (!input.counterAccountId) {
      throw new Error('createTransaction: counterAccountId required for transfer types');
    }
    if (input.counterAccountId === input.accountId) {
      throw new Error('createTransaction: counterAccountId must differ from accountId');
    }
    if (!counterAcct) throw new Error('createTransaction: counter account not found');
  } else if (input.counterAccountId) {
    throw new Error('createTransaction: counterAccountId only allowed for transfer types');
  }
  assertTransactionAmount(input.type, input.amountMinor, 'createTransaction');

  const currency = normalizeCurrencyCode(input.currency ?? acct.currency);
  assertPostedCurrencyMatchesAccount(currency, acct.currency, 'createTransaction');
  const fxRate = input.fxRate ?? rateBetween(state, currency, state.preferences.baseCurrency);
  const baseAmountMinor = convertMinor(
    input.amountMinor,
    currency,
    state.preferences.baseCurrency,
    fxRate,
  );
  const originalCurrency = input.originalCurrency
    ? normalizeCurrencyCode(input.originalCurrency)
    : undefined;
  const originalAmount =
    input.originalAmountMinor !== undefined && originalCurrency && originalCurrency !== currency
      ? { amountMinor: input.originalAmountMinor, currency: originalCurrency }
      : undefined;
  const originalFxRate = originalAmount
    ? (input.originalFxRate ?? rateBetween(state, originalAmount.currency, currency))
    : undefined;
  const counterAmount = resolveCounterAmount(state, input, currency, counterAcct);

  const now = nowIso();
  const tx: Transaction = {
    id: uid(),
    userId: state.userId,
    type: input.type,
    status: input.status ?? 'cleared',
    source: input.source ?? 'manual',
    accountId: input.accountId,
    counterAccountId: input.counterAccountId,
    amount: { amountMinor: input.amountMinor, currency },
    baseAmount: { amountMinor: baseAmountMinor, currency: state.preferences.baseCurrency },
    fxRate,
    originalAmount,
    originalFxRate,
    counterAmount: counterAmount?.amount,
    counterFxRate: counterAmount?.fxRate,
    categoryId: input.categoryId,
    merchantId: input.merchantId,
    occurredAt: input.occurredAt ?? nowIso(),
    locationLabel: input.locationLabel,
    paymentMethod: input.paymentMethod,
    notes: input.notes,
    attachments: input.attachments,
    tags: input.tags,
    isReimbursable: input.isReimbursable ?? false,
    isTaxDeductible: input.isTaxDeductible ?? false,
    isExcludedFromReports: input.isExcludedFromReports ?? false,
    captureCandidateId: input.captureCandidateId,
    originalTransactionId: input.originalTransactionId,
    recurringTemplateId: input.recurringTemplateId,
    sourceConfidence: input.sourceConfidence,
    externalRef: input.externalRef,
    createdAt: now,
    updatedAt: now,
  };
  state.transactions.push(tx);
  return tx;
}

export function updateTransaction(
  state: LedgerState,
  id: UUID,
  patch: UpdateTransactionInput,
): Transaction | undefined {
  const tx = state.transactions.find((t) => t.id === id);
  if (!tx) return undefined;

  const nextType = patch.type ?? tx.type;
  const nextAccountId = patch.accountId ?? tx.accountId;
  const nextAccount = state.accounts.find((a) => a.id === nextAccountId);
  if (!nextAccount) throw new Error(`updateTransaction: account ${nextAccountId} not found`);

  let nextCounterAccountId =
    patch.counterAccountId === null
      ? undefined
      : patch.counterAccountId !== undefined
        ? patch.counterAccountId
        : tx.counterAccountId;
  const isTransfer = TRANSFER_TYPES.has(nextType);
  if (isTransfer) {
    if (!nextCounterAccountId) {
      throw new Error('updateTransaction: counterAccountId required for transfer types');
    }
    if (nextCounterAccountId === nextAccountId) {
      throw new Error('updateTransaction: counterAccountId must differ from accountId');
    }
  } else {
    nextCounterAccountId = undefined;
  }

  const nextAmountMinor = patch.amountMinor ?? tx.amount.amountMinor;
  assertTransactionAmount(nextType, nextAmountMinor, 'updateTransaction');

  const nextCurrency =
    patch.currency !== undefined
      ? normalizeCurrencyCode(patch.currency)
      : patch.accountId
        ? nextAccount.currency
        : tx.amount.currency;
  assertPostedCurrencyMatchesAccount(nextCurrency, nextAccount.currency, 'updateTransaction');
  const nextFxRate =
    patch.fxRate ?? rateBetween(state, nextCurrency, state.preferences.baseCurrency);
  const nextBaseAmountMinor = convertMinor(
    nextAmountMinor,
    nextCurrency,
    state.preferences.baseCurrency,
    nextFxRate,
  );
  const originalCleared = patch.originalAmountMinor === null || patch.originalCurrency === null;
  const nextOriginalCurrency = originalCleared
    ? undefined
    : patch.originalCurrency !== undefined && patch.originalCurrency !== null
      ? normalizeCurrencyCode(patch.originalCurrency)
      : tx.originalAmount?.currency;
  const nextOriginalAmountMinor = originalCleared
    ? undefined
    : (patch.originalAmountMinor ?? tx.originalAmount?.amountMinor);
  const nextOriginalAmount =
    nextOriginalCurrency &&
    nextOriginalAmountMinor !== undefined &&
    nextOriginalCurrency !== nextCurrency
      ? { amountMinor: nextOriginalAmountMinor, currency: nextOriginalCurrency }
      : undefined;
  const nextOriginalFxRate = nextOriginalAmount
    ? patch.originalFxRate === null
      ? rateBetween(state, nextOriginalAmount.currency, nextCurrency)
      : (patch.originalFxRate ??
        tx.originalFxRate ??
        rateBetween(state, nextOriginalAmount.currency, nextCurrency))
    : undefined;
  const nextCounterAccount = nextCounterAccountId
    ? state.accounts.find((account) => account.id === nextCounterAccountId)
    : undefined;
  const nextCounterAmount = resolveUpdatedCounterAmount(
    state,
    patch,
    tx,
    nextType,
    nextCurrency,
    nextAmountMinor,
    nextCounterAccount,
  );

  tx.type = nextType;
  tx.accountId = nextAccountId;
  tx.counterAccountId = nextCounterAccountId;
  tx.amount = { amountMinor: nextAmountMinor, currency: nextCurrency };
  tx.baseAmount = { amountMinor: nextBaseAmountMinor, currency: state.preferences.baseCurrency };
  tx.fxRate = nextFxRate;
  tx.originalAmount = nextOriginalAmount;
  tx.originalFxRate = nextOriginalFxRate;
  tx.counterAmount = nextCounterAmount?.amount;
  tx.counterFxRate = nextCounterAmount?.fxRate;
  if (patch.occurredAt !== undefined) tx.occurredAt = patch.occurredAt;
  if (patch.locationLabel !== undefined) tx.locationLabel = patch.locationLabel ?? undefined;
  if (isTransfer) tx.categoryId = undefined;
  else if (patch.categoryId !== undefined) tx.categoryId = patch.categoryId ?? undefined;
  if (patch.merchantId !== undefined) tx.merchantId = patch.merchantId ?? undefined;
  if (patch.notes !== undefined) tx.notes = patch.notes ?? undefined;
  if (patch.attachments !== undefined) tx.attachments = patch.attachments ?? undefined;
  if (patch.tags !== undefined) tx.tags = patch.tags ?? undefined;
  if (patch.paymentMethod !== undefined) tx.paymentMethod = patch.paymentMethod ?? undefined;
  if (patch.isReimbursable !== undefined) tx.isReimbursable = patch.isReimbursable;
  if (patch.isTaxDeductible !== undefined) tx.isTaxDeductible = patch.isTaxDeductible;
  if (patch.isExcludedFromReports !== undefined)
    tx.isExcludedFromReports = patch.isExcludedFromReports;
  if (patch.source !== undefined) tx.source = patch.source;
  if (patch.sourceConfidence !== undefined) tx.sourceConfidence = patch.sourceConfidence;
  if (patch.captureCandidateId !== undefined)
    tx.captureCandidateId = patch.captureCandidateId ?? undefined;
  if (patch.originalTransactionId !== undefined)
    tx.originalTransactionId = patch.originalTransactionId ?? undefined;
  if (patch.recurringTemplateId !== undefined)
    tx.recurringTemplateId = patch.recurringTemplateId ?? undefined;
  if (patch.status !== undefined) tx.status = patch.status;
  if (patch.externalRef !== undefined) tx.externalRef = patch.externalRef ?? undefined;
  tx.updatedAt = nowIso();
  return tx;
}

export function deleteTransaction(state: LedgerState, id: UUID): boolean {
  const before = state.transactions.length;
  state.transactions = state.transactions.filter((t) => t.id !== id);
  state.transactionSplits = state.transactionSplits.filter((split) => split.transactionId !== id);
  return state.transactions.length < before;
}

export function createTransactionSplit(
  state: LedgerState,
  input: CreateTransactionSplitInput,
): TransactionSplit {
  const transaction = state.transactions.find((item) => item.id === input.transactionId);
  if (!transaction)
    throw new Error(`createTransactionSplit: transaction ${input.transactionId} not found`);
  if (input.amountMinor <= 0) throw new Error('createTransactionSplit: amount must be positive');
  const currency = input.currency ?? transaction.amount.currency;
  const now = nowIso();
  const split: TransactionSplit = {
    id: uid(),
    userId: state.userId,
    transactionId: input.transactionId,
    categoryId: input.categoryId,
    amount: { amountMinor: input.amountMinor, currency },
    notes: input.notes,
    sortOrder:
      input.sortOrder ??
      state.transactionSplits.filter((item) => item.transactionId === input.transactionId).length,
    createdAt: now,
    updatedAt: now,
  };
  state.transactionSplits.push(split);
  return split;
}

export function updateTransactionSplit(
  state: LedgerState,
  id: UUID,
  patch: UpdateTransactionSplitInput,
): TransactionSplit | undefined {
  const split = state.transactionSplits.find((item) => item.id === id);
  if (!split) return undefined;
  if (patch.amountMinor !== undefined) {
    if (patch.amountMinor <= 0) throw new Error('updateTransactionSplit: amount must be positive');
    split.amount = {
      amountMinor: patch.amountMinor,
      currency: patch.currency ?? split.amount.currency,
    };
  } else if (patch.currency !== undefined) {
    split.amount = { ...split.amount, currency: patch.currency };
  }
  if (patch.categoryId !== undefined) split.categoryId = patch.categoryId ?? undefined;
  if (patch.notes !== undefined) split.notes = patch.notes ?? undefined;
  if (patch.sortOrder !== undefined) split.sortOrder = patch.sortOrder;
  split.updatedAt = nowIso();
  return split;
}

export function deleteTransactionSplit(state: LedgerState, id: UUID): boolean {
  const before = state.transactionSplits.length;
  state.transactionSplits = state.transactionSplits.filter((item) => item.id !== id);
  return state.transactionSplits.length < before;
}

export function transactionSplits(state: LedgerState, transactionId: UUID): TransactionSplit[] {
  return state.transactionSplits
    .filter((split) => split.transactionId === transactionId)
    .sort((a, b) => a.sortOrder - b.sortOrder);
}

// ============================================================================
// Import batches
// ============================================================================

export interface CreateImportBatchInput {
  source: ImportBatchSource;
  name: string;
  fileNames: string[];
  rowCount: number;
  candidateCount?: number;
  duplicateCount?: number;
  transferPairCount?: number;
  warningCount?: number;
  status?: ImportBatchStatus;
  notes?: string;
}

export interface UpdateImportBatchInput {
  status?: ImportBatchStatus;
  candidateCount?: number;
  duplicateCount?: number;
  transferPairCount?: number;
  warningCount?: number;
  notes?: string | null;
}

export function createImportBatch(state: LedgerState, input: CreateImportBatchInput): ImportBatch {
  const now = nowIso();
  const batch: ImportBatch = {
    id: uid(),
    userId: state.userId,
    source: input.source,
    status: input.status ?? 'previewed',
    name: input.name,
    fileNames: input.fileNames,
    rowCount: input.rowCount,
    candidateCount: input.candidateCount ?? 0,
    duplicateCount: input.duplicateCount ?? 0,
    transferPairCount: input.transferPairCount ?? 0,
    warningCount: input.warningCount ?? 0,
    notes: input.notes,
    createdAt: now,
    updatedAt: now,
  };
  state.importBatches.push(batch);
  return batch;
}

export function updateImportBatch(
  state: LedgerState,
  id: UUID,
  patch: UpdateImportBatchInput,
): ImportBatch | undefined {
  const batch = state.importBatches.find((item) => item.id === id);
  if (!batch) return undefined;
  if (patch.status !== undefined) batch.status = patch.status;
  if (patch.candidateCount !== undefined) batch.candidateCount = patch.candidateCount;
  if (patch.duplicateCount !== undefined) batch.duplicateCount = patch.duplicateCount;
  if (patch.transferPairCount !== undefined) batch.transferPairCount = patch.transferPairCount;
  if (patch.warningCount !== undefined) batch.warningCount = patch.warningCount;
  if (patch.notes !== undefined) batch.notes = patch.notes ?? undefined;
  batch.updatedAt = nowIso();
  return batch;
}

// ============================================================================
// Capture candidates / review queue
// ============================================================================

export type CaptureSource = Extract<
  TransactionSource,
  'notification' | 'sms' | 'email' | 'import' | 'api'
>;

export interface CreateCaptureCandidateInput {
  source: CaptureSource;
  rawPayload: Record<string, unknown>;
  rawHash?: string;
  parsedAmountMinor?: number;
  parsedCurrency?: string;
  parsedFxRate?: number;
  parsedOriginalAmountMinor?: number;
  parsedOriginalCurrency?: string;
  parsedOriginalFxRate?: number;
  parsedCounterAmountMinor?: number;
  parsedCounterCurrency?: string;
  parsedCounterFxRate?: number;
  parsedMerchant?: string;
  parsedLocationLabel?: string;
  parsedNotes?: string;
  parsedPaymentMethod?: string;
  parsedTags?: string[];
  parsedOccurredAt?: string;
  suggestedAccountId?: UUID;
  suggestedCounterAccountId?: UUID;
  suggestedCategoryId?: UUID;
  suggestedType?: TransactionType;
  suggestedRecurringTemplateId?: UUID;
  confidence?: number;
  importBatchId?: UUID;
  externalRef?: string;
  warnings?: string[];
}

export interface UpdateCaptureCandidateInput {
  parsedAmountMinor?: number | null;
  parsedCurrency?: string;
  parsedFxRate?: number | null;
  parsedOriginalAmountMinor?: number | null;
  parsedOriginalCurrency?: string | null;
  parsedOriginalFxRate?: number | null;
  parsedCounterAmountMinor?: number | null;
  parsedCounterCurrency?: string | null;
  parsedCounterFxRate?: number | null;
  parsedMerchant?: string | null;
  parsedLocationLabel?: string | null;
  parsedNotes?: string | null;
  parsedPaymentMethod?: string | null;
  parsedTags?: string[] | null;
  parsedOccurredAt?: string | null;
  suggestedAccountId?: UUID | null;
  suggestedCounterAccountId?: UUID | null;
  suggestedCategoryId?: UUID | null;
  suggestedType?: TransactionType | null;
  suggestedRecurringTemplateId?: UUID | null;
  confidence?: number;
  status?: CaptureCandidateStatus;
  importBatchId?: UUID | null;
  externalRef?: string | null;
  warnings?: string[] | null;
}

export type ApproveCaptureCandidateInput = Partial<CreateTransactionInput> & {
  acceptedMessageHints?: AccountMessageHint[];
};

export function createCaptureCandidate(
  state: LedgerState,
  input: CreateCaptureCandidateInput,
): CaptureCandidate {
  const rawHash = input.rawHash ?? deriveRawHash(input.source, input.rawPayload);
  const existing = state.captureCandidates.find(
    (candidate) =>
      candidate.rawHash === rawHash ||
      (input.externalRef !== undefined && candidate.externalRef === input.externalRef),
  );
  if (existing) return existing;

  const currency = input.parsedCurrency ?? state.preferences.baseCurrency;
  const candidate: CaptureCandidate = {
    id: uid(),
    userId: state.userId,
    source: input.source,
    rawPayload: input.rawPayload,
    rawHash,
    parsedAmount:
      input.parsedAmountMinor !== undefined
        ? { amountMinor: input.parsedAmountMinor, currency }
        : undefined,
    parsedFxRate: input.parsedFxRate,
    parsedOriginalAmount:
      input.parsedOriginalAmountMinor !== undefined && input.parsedOriginalCurrency
        ? {
            amountMinor: input.parsedOriginalAmountMinor,
            currency: normalizeCurrencyCode(input.parsedOriginalCurrency),
          }
        : undefined,
    parsedOriginalFxRate: input.parsedOriginalFxRate,
    parsedCounterAmount:
      input.parsedCounterAmountMinor !== undefined && input.parsedCounterCurrency
        ? {
            amountMinor: input.parsedCounterAmountMinor,
            currency: normalizeCurrencyCode(input.parsedCounterCurrency),
          }
        : undefined,
    parsedCounterFxRate: input.parsedCounterFxRate,
    parsedMerchant: input.parsedMerchant,
    parsedLocationLabel: input.parsedLocationLabel,
    parsedNotes: input.parsedNotes,
    parsedPaymentMethod: input.parsedPaymentMethod,
    parsedTags: input.parsedTags,
    parsedOccurredAt: input.parsedOccurredAt,
    suggestedAccountId: input.suggestedAccountId,
    suggestedCounterAccountId: input.suggestedCounterAccountId,
    suggestedCategoryId: input.suggestedCategoryId,
    suggestedType: input.suggestedType,
    suggestedRecurringTemplateId: input.suggestedRecurringTemplateId,
    confidence: clampConfidence(input.confidence ?? 0),
    status: 'pending',
    importBatchId: input.importBatchId,
    externalRef: input.externalRef,
    warnings: input.warnings,
    createdAt: nowIso(),
  };
  state.captureCandidates.push(candidate);
  return candidate;
}

export function updateCaptureCandidate(
  state: LedgerState,
  id: UUID,
  patch: UpdateCaptureCandidateInput,
): CaptureCandidate | undefined {
  const candidate = state.captureCandidates.find((item) => item.id === id);
  if (!candidate) return undefined;
  if (patch.parsedAmountMinor !== undefined) {
    candidate.parsedAmount =
      patch.parsedAmountMinor === null
        ? undefined
        : {
            amountMinor: patch.parsedAmountMinor,
            currency:
              patch.parsedCurrency ??
              candidate.parsedAmount?.currency ??
              state.preferences.baseCurrency,
          };
  } else if (patch.parsedCurrency !== undefined && candidate.parsedAmount) {
    candidate.parsedAmount = { ...candidate.parsedAmount, currency: patch.parsedCurrency };
  }
  if (patch.parsedFxRate !== undefined) {
    candidate.parsedFxRate = patch.parsedFxRate ?? undefined;
  }
  if (patch.parsedOriginalAmountMinor !== undefined) {
    candidate.parsedOriginalAmount =
      patch.parsedOriginalAmountMinor === null || patch.parsedOriginalCurrency === null
        ? undefined
        : {
            amountMinor: patch.parsedOriginalAmountMinor,
            currency:
              patch.parsedOriginalCurrency ??
              candidate.parsedOriginalAmount?.currency ??
              candidate.parsedAmount?.currency ??
              state.preferences.baseCurrency,
          };
  } else if (patch.parsedOriginalCurrency !== undefined) {
    candidate.parsedOriginalAmount =
      patch.parsedOriginalCurrency === null || !candidate.parsedOriginalAmount
        ? undefined
        : { ...candidate.parsedOriginalAmount, currency: patch.parsedOriginalCurrency };
  }
  if (patch.parsedOriginalFxRate !== undefined) {
    candidate.parsedOriginalFxRate = patch.parsedOriginalFxRate ?? undefined;
  }
  if (patch.parsedCounterAmountMinor !== undefined) {
    candidate.parsedCounterAmount =
      patch.parsedCounterAmountMinor === null || patch.parsedCounterCurrency === null
        ? undefined
        : {
            amountMinor: patch.parsedCounterAmountMinor,
            currency:
              patch.parsedCounterCurrency ??
              candidate.parsedCounterAmount?.currency ??
              state.preferences.baseCurrency,
          };
  } else if (patch.parsedCounterCurrency !== undefined) {
    candidate.parsedCounterAmount =
      patch.parsedCounterCurrency === null || !candidate.parsedCounterAmount
        ? undefined
        : { ...candidate.parsedCounterAmount, currency: patch.parsedCounterCurrency };
  }
  if (patch.parsedCounterFxRate !== undefined) {
    candidate.parsedCounterFxRate = patch.parsedCounterFxRate ?? undefined;
  }
  if (patch.parsedMerchant !== undefined)
    candidate.parsedMerchant = patch.parsedMerchant ?? undefined;
  if (patch.parsedLocationLabel !== undefined)
    candidate.parsedLocationLabel = patch.parsedLocationLabel ?? undefined;
  if (patch.parsedNotes !== undefined) candidate.parsedNotes = patch.parsedNotes ?? undefined;
  if (patch.parsedPaymentMethod !== undefined)
    candidate.parsedPaymentMethod = patch.parsedPaymentMethod ?? undefined;
  if (patch.parsedTags !== undefined) candidate.parsedTags = patch.parsedTags ?? undefined;
  if (patch.parsedOccurredAt !== undefined)
    candidate.parsedOccurredAt = patch.parsedOccurredAt ?? undefined;
  if (patch.suggestedAccountId !== undefined)
    candidate.suggestedAccountId = patch.suggestedAccountId ?? undefined;
  if (patch.suggestedCounterAccountId !== undefined)
    candidate.suggestedCounterAccountId = patch.suggestedCounterAccountId ?? undefined;
  if (patch.suggestedCategoryId !== undefined)
    candidate.suggestedCategoryId = patch.suggestedCategoryId ?? undefined;
  if (patch.suggestedType !== undefined) candidate.suggestedType = patch.suggestedType ?? undefined;
  if (patch.suggestedRecurringTemplateId !== undefined) {
    candidate.suggestedRecurringTemplateId = patch.suggestedRecurringTemplateId ?? undefined;
  }
  if (patch.confidence !== undefined) candidate.confidence = clampConfidence(patch.confidence);
  if (patch.importBatchId !== undefined) candidate.importBatchId = patch.importBatchId ?? undefined;
  if (patch.externalRef !== undefined) candidate.externalRef = patch.externalRef ?? undefined;
  if (patch.warnings !== undefined) candidate.warnings = patch.warnings ?? undefined;
  if (patch.status !== undefined) {
    candidate.status = patch.status;
    if (patch.status !== 'pending') candidate.reviewedAt = nowIso();
  }
  return candidate;
}

export function approveCaptureCandidate(
  state: LedgerState,
  id: UUID,
  input: ApproveCaptureCandidateInput = {},
): Transaction {
  const { acceptedMessageHints, ...transactionInput } = input;
  const candidate = state.captureCandidates.find((item) => item.id === id);
  if (!candidate) throw new Error(`approveCaptureCandidate: candidate ${id} not found`);
  if (candidate.status !== 'pending') {
    throw new Error('approveCaptureCandidate: candidate has already been reviewed');
  }

  const accountId = transactionInput.accountId ?? candidate.suggestedAccountId;
  if (!accountId) throw new Error('approveCaptureCandidate: accountId is required');
  const account = state.accounts.find((item) => item.id === accountId);
  if (!account) throw new Error('approveCaptureCandidate: account not found');
  const type = transactionInput.type ?? candidate.suggestedType ?? 'expense';
  const amountMinor = transactionInput.amountMinor ?? candidate.parsedAmount?.amountMinor;
  if (amountMinor === undefined || (type === 'adjustment' ? amountMinor === 0 : amountMinor <= 0)) {
    throw new Error('approveCaptureCandidate: parsed amount is required');
  }
  const counterAccountId = transactionInput.counterAccountId ?? candidate.suggestedCounterAccountId;
  if (TRANSFER_TYPES.has(type) && !counterAccountId) {
    throw new Error('approveCaptureCandidate: counterAccountId is required for transfers');
  }
  const occurredAt = transactionInput.occurredAt ?? candidate.parsedOccurredAt ?? nowIso();
  if (Number.isNaN(new Date(occurredAt).getTime())) {
    throw new Error('approveCaptureCandidate: valid occurredAt is required');
  }
  const parsedCurrency = normalizeCurrencyCode(
    transactionInput.currency ?? candidate.parsedAmount?.currency ?? account.currency,
  );
  const currency = normalizeCurrencyCode(account.currency);
  const parsedOriginalFxRate =
    transactionInput.originalFxRate ??
    candidate.parsedOriginalFxRate ??
    (parsedCurrency !== currency ? rateBetween(state, parsedCurrency, currency) : undefined);
  const parsedFxRate =
    transactionInput.fxRate ?? (parsedCurrency === currency ? candidate.parsedFxRate : undefined);
  const postedAmountMinor =
    parsedCurrency === currency
      ? amountMinor
      : convertMinor(amountMinor, parsedCurrency, currency, parsedOriginalFxRate ?? 1);
  const originalAmountMinor =
    transactionInput.originalAmountMinor ??
    candidate.parsedOriginalAmount?.amountMinor ??
    (parsedCurrency !== currency ? amountMinor : undefined);
  const originalCurrency =
    transactionInput.originalCurrency ??
    candidate.parsedOriginalAmount?.currency ??
    (parsedCurrency !== currency ? parsedCurrency : undefined);
  const parsedCounterAmount = TRANSFER_TYPES.has(type) ? candidate.parsedCounterAmount : undefined;
  const counterAmountMinor =
    transactionInput.counterAmountMinor ?? parsedCounterAmount?.amountMinor;
  const counterCurrency = transactionInput.counterCurrency ?? parsedCounterAmount?.currency;
  const counterFxRate = transactionInput.counterFxRate ?? candidate.parsedCounterFxRate;
  const externalRef = transactionInput.externalRef ?? candidate.externalRef;
  if (
    externalRef &&
    state.transactions.some((transaction) => transaction.externalRef === externalRef)
  ) {
    throw new Error('approveCaptureCandidate: transaction was already imported');
  }

  const transaction = createTransaction(state, {
    ...transactionInput,
    type,
    accountId,
    counterAccountId,
    amountMinor: postedAmountMinor,
    currency,
    originalAmountMinor,
    originalCurrency,
    originalFxRate: originalAmountMinor !== undefined ? parsedOriginalFxRate : undefined,
    fxRate: parsedFxRate,
    counterAmountMinor,
    counterCurrency,
    counterFxRate,
    occurredAt,
    categoryId: transactionInput.categoryId ?? candidate.suggestedCategoryId,
    locationLabel: transactionInput.locationLabel ?? candidate.parsedLocationLabel,
    paymentMethod: transactionInput.paymentMethod ?? candidate.parsedPaymentMethod,
    notes: transactionInput.notes ?? candidate.parsedNotes,
    attachments:
      transactionInput.attachments ??
      attachmentsFromCapturePayload(candidate.rawPayload, candidate.createdAt),
    tags: transactionInput.tags ?? candidate.parsedTags,
    recurringTemplateId:
      transactionInput.recurringTemplateId ?? candidate.suggestedRecurringTemplateId,
    externalRef,
    source: candidate.source,
    sourceConfidence: candidate.confidence,
    captureCandidateId: candidate.id,
  });

  candidate.status = 'approved';
  candidate.postedTransactionId = transaction.id;
  candidate.reviewedAt = nowIso();
  if (acceptedMessageHints?.length) {
    mergeAcceptedMessageAccountHints(state, accountId, acceptedMessageHints);
  }
  return transaction;
}

export function rejectCaptureCandidate(state: LedgerState, id: UUID): boolean {
  return markCaptureCandidate(state, id, 'rejected');
}

export function ignoreCaptureCandidate(state: LedgerState, id: UUID): boolean {
  return markCaptureCandidate(state, id, 'ignored');
}

function attachmentsFromCapturePayload(
  rawPayload: Record<string, unknown>,
  createdAt: string,
): TransactionAttachment[] | undefined {
  if (rawPayload.kind !== 'receipt_attachment') return undefined;
  const uri = typeof rawPayload.uri === 'string' ? rawPayload.uri : undefined;
  const name = typeof rawPayload.fileName === 'string' ? rawPayload.fileName : undefined;
  if (!uri || !name) return undefined;

  return [
    {
      id: uid(),
      name,
      uri,
      mimeType: typeof rawPayload.mimeType === 'string' ? rawPayload.mimeType : undefined,
      size: typeof rawPayload.size === 'number' ? rawPayload.size : undefined,
      width: typeof rawPayload.width === 'number' ? rawPayload.width : undefined,
      height: typeof rawPayload.height === 'number' ? rawPayload.height : undefined,
      source: captureAttachmentSource(rawPayload.source),
      createdAt,
    },
  ];
}

function captureAttachmentSource(value: unknown): TransactionAttachment['source'] {
  if (value === 'camera' || value === 'library' || value === 'file' || value === 'import') {
    return value;
  }
  return 'import';
}

function markCaptureCandidate(
  state: LedgerState,
  id: UUID,
  status: Extract<CaptureCandidateStatus, 'rejected' | 'ignored'>,
): boolean {
  const candidate = state.captureCandidates.find((item) => item.id === id);
  if (!candidate) return false;
  if (candidate.status !== 'pending') return false;
  candidate.status = status;
  candidate.reviewedAt = nowIso();
  return true;
}

// ============================================================================
// Categories
// ============================================================================

export interface CreateCategoryInput {
  name: string;
  kind: CategoryKind;
  parentId?: UUID;
  icon?: string;
  color?: string;
}

export interface UpdateCategoryInput {
  name?: string;
  kind?: CategoryKind;
  parentId?: UUID | null;
  icon?: string | null;
  color?: string | null;
  isArchived?: boolean;
  isHiddenInStats?: boolean;
  sortOrder?: number;
}

export function createCategory(state: LedgerState, input: CreateCategoryInput): Category {
  assertValidCategoryParent(state, undefined, input.kind, input.parentId);
  assertUniqueCategoryName(state, input.name, input.kind, input.parentId);
  const cat: Category = {
    id: uid(),
    userId: state.userId,
    parentId: input.parentId,
    name: input.name,
    kind: input.kind,
    icon: input.icon,
    color: input.color,
    isArchived: false,
    isHiddenInStats: false,
    sortOrder: state.categories.length,
  };
  state.categories.push(cat);
  return cat;
}

export function updateCategory(
  state: LedgerState,
  id: UUID,
  patch: UpdateCategoryInput,
): Category | undefined {
  const category = state.categories.find((item) => item.id === id);
  if (!category) return undefined;

  const nextKind = patch.kind ?? category.kind;
  const nextParentId =
    patch.parentId === null
      ? undefined
      : patch.parentId !== undefined
        ? patch.parentId
        : category.parentId;
  const nextName = patch.name !== undefined ? patch.name.trim() : category.name;

  if (!nextName) throw new Error('updateCategory: name is required');
  assertValidCategoryParent(state, id, nextKind, nextParentId);
  assertUniqueCategoryName(state, nextName, nextKind, nextParentId, id);
  assertKindChangeAllowed(state, category, nextKind);

  category.name = nextName;
  category.kind = nextKind;
  category.parentId = nextParentId;
  if (patch.icon !== undefined) category.icon = patch.icon ?? undefined;
  if (patch.color !== undefined) category.color = patch.color ?? undefined;
  if (patch.isArchived !== undefined) category.isArchived = patch.isArchived;
  if (patch.isHiddenInStats !== undefined) category.isHiddenInStats = patch.isHiddenInStats;
  if (patch.sortOrder !== undefined) category.sortOrder = patch.sortOrder;
  return category;
}

export function deleteCategory(state: LedgerState, id: UUID): boolean {
  const hasChildren = state.categories.some((c) => c.parentId === id);
  const inUse = state.transactions.some((t) => t.categoryId === id);
  if (hasChildren || inUse) {
    const cat = state.categories.find((c) => c.id === id);
    if (cat) cat.isArchived = true;
    return cat !== undefined;
  }
  const before = state.categories.length;
  state.categories = state.categories.filter((c) => c.id !== id);
  return state.categories.length < before;
}

function assertValidCategoryParent(
  state: LedgerState,
  categoryId: UUID | undefined,
  kind: CategoryKind,
  parentId: UUID | undefined,
): void {
  if (!parentId) return;
  if (parentId === categoryId) throw new Error('category parent cannot be itself');
  const parent = state.categories.find((item) => item.id === parentId);
  if (!parent) throw new Error('category parent not found');
  if (parent.kind !== kind) throw new Error('category parent must use the same kind');
  if (categoryId && categoryHasAncestor(state, parentId, categoryId)) {
    throw new Error('category parent cannot be a descendant');
  }
}

function assertUniqueCategoryName(
  state: LedgerState,
  name: string,
  kind: CategoryKind,
  parentId: UUID | undefined,
  exceptId?: UUID,
): void {
  const normalized = name.trim().toLowerCase();
  if (!normalized) throw new Error('category name is required');
  const duplicate = state.categories.find(
    (item) =>
      item.id !== exceptId &&
      item.kind === kind &&
      item.parentId === parentId &&
      item.name.trim().toLowerCase() === normalized,
  );
  if (duplicate) throw new Error('category already exists in this group');
}

function assertKindChangeAllowed(
  state: LedgerState,
  category: Category,
  nextKind: CategoryKind,
): void {
  if (category.kind === nextKind) return;
  const hasChildren = state.categories.some((item) => item.parentId === category.id);
  const inUse = state.transactions.some((item) => item.categoryId === category.id);
  const inSplits = state.transactionSplits.some((item) => item.categoryId === category.id);
  if (hasChildren || inUse || inSplits) {
    throw new Error('used or parent categories cannot change kind');
  }
}

function categoryHasAncestor(state: LedgerState, categoryId: UUID, ancestorId: UUID): boolean {
  let current = state.categories.find((item) => item.id === categoryId);
  const seen = new Set<UUID>();
  while (current?.parentId) {
    if (current.parentId === ancestorId) return true;
    if (seen.has(current.parentId)) return true;
    seen.add(current.parentId);
    current = state.categories.find((item) => item.id === current?.parentId);
  }
  return false;
}

// ============================================================================
// FX
// ============================================================================

export function postedAmountFromOriginal(
  originalAmount: Money,
  postedCurrency: string,
  fxRate: number,
): Money {
  const normalizedPostedCurrency = normalizeCurrencyCode(postedCurrency);
  if (normalizeCurrencyCode(originalAmount.currency) === normalizedPostedCurrency) {
    return { amountMinor: originalAmount.amountMinor, currency: normalizedPostedCurrency };
  }
  if (!Number.isFinite(fxRate) || fxRate <= 0) {
    throw new Error('postedAmountFromOriginal: fxRate must be positive');
  }
  return {
    amountMinor: convertMinor(
      originalAmount.amountMinor,
      originalAmount.currency,
      normalizedPostedCurrency,
      fxRate,
    ),
    currency: normalizedPostedCurrency,
  };
}

export function rateBetween(state: LedgerState, base: string, quote: string): number {
  const normalizedBase = normalizeCurrencyCode(base);
  const normalizedQuote = normalizeCurrencyCode(quote);
  const resolved = resolvedRateBetween(state, normalizedBase, normalizedQuote);
  if (resolved !== undefined) return resolved;
  return 1; // best-effort fallback; UI should warn
}

function resolvedRateBetween(
  state: LedgerState,
  normalizedBase: string,
  normalizedQuote: string,
): number | undefined {
  if (normalizedBase === normalizedQuote) return 1;
  const directRate = directRateBetween(state, normalizedBase, normalizedQuote);
  if (directRate !== undefined) return directRate;

  for (const pivot of ratePivotCurrencies(state)) {
    if (pivot === normalizedBase || pivot === normalizedQuote) continue;
    const baseToPivot = directRateBetween(state, normalizedBase, pivot);
    if (baseToPivot === undefined) continue;
    const pivotToQuote = directRateBetween(state, pivot, normalizedQuote);
    if (pivotToQuote !== undefined) return baseToPivot * pivotToQuote;
  }
  return undefined;
}

function directRateBetween(
  state: LedgerState,
  normalizedBase: string,
  normalizedQuote: string,
): number | undefined {
  const direct = latestExchangeRate(state, normalizedBase, normalizedQuote);
  if (direct) return direct.rate;
  const inverse = latestExchangeRate(state, normalizedQuote, normalizedBase);
  if (inverse && inverse.rate !== 0) return 1 / inverse.rate;
  return undefined;
}

function ratePivotCurrencies(state: LedgerState): string[] {
  const currencies = new Set<string>();
  currencies.add(normalizeCurrencyCode(state.preferences.baseCurrency));
  for (const rate of state.exchangeRates) {
    currencies.add(normalizeCurrencyCode(rate.base));
    currencies.add(normalizeCurrencyCode(rate.quote));
  }
  return Array.from(currencies).filter(Boolean);
}

export function setRate(
  state: LedgerState,
  base: string,
  quote: string,
  rate: number,
  asOfDate = todayIso(),
  options: { provider?: string; source?: ExchangeRateSource; updatedAt?: string } = {},
): void {
  const normalizedBase = normalizeCurrencyCode(base);
  const normalizedQuote = normalizeCurrencyCode(quote);
  if (normalizedBase === normalizedQuote) return;
  if (!Number.isFinite(rate) || rate <= 0) throw new Error('setRate: rate must be positive');
  const existing = state.exchangeRates.find(
    (r) => r.base === normalizedBase && r.quote === normalizedQuote && r.asOfDate === asOfDate,
  );
  const next: ExchangeRateRecord = {
    base: normalizedBase,
    quote: normalizedQuote,
    rate,
    asOfDate,
    updatedAt: options.updatedAt ?? nowIso(),
    provider: options.provider ?? 'manual',
    source: options.source ?? 'manual',
  };
  if (existing) Object.assign(existing, next);
  else state.exchangeRates.push(next);
  ensureEnabledCurrency(state, normalizedBase);
  ensureEnabledCurrency(state, normalizedQuote);
}

export function latestExchangeRate(
  state: LedgerState,
  base: string,
  quote: string,
): ExchangeRateRecord | undefined {
  const normalizedBase = normalizeCurrencyCode(base);
  const normalizedQuote = normalizeCurrencyCode(quote);
  return state.exchangeRates
    .filter((rate) => rate.base === normalizedBase && rate.quote === normalizedQuote)
    .sort((left, right) => rateTimestamp(right) - rateTimestamp(left))[0];
}

export function rateRecordForPair(
  state: LedgerState,
  base: string,
  quote: string,
): ExchangeRateRecord | undefined {
  const direct = latestExchangeRate(state, base, quote);
  const inverse = latestExchangeRate(state, quote, base);
  if (!direct) return inverse;
  if (!inverse) return direct;
  return rateTimestamp(direct) >= rateTimestamp(inverse) ? direct : inverse;
}

export function hasExplicitRate(state: LedgerState, base: string, quote: string): boolean {
  const normalizedBase = normalizeCurrencyCode(base);
  const normalizedQuote = normalizeCurrencyCode(quote);
  return resolvedRateBetween(state, normalizedBase, normalizedQuote) !== undefined;
}

export function enabledCurrencies(state: LedgerState): string[] {
  const currencies = new Set<string>();
  ensureCurrencySetValue(currencies, state.preferences.baseCurrency);
  ensureCurrencySetValue(currencies, state.preferences.displayCurrency);
  for (const currency of state.preferences.enabledCurrencies ?? []) {
    ensureCurrencySetValue(currencies, currency);
  }
  for (const account of state.accounts) ensureCurrencySetValue(currencies, account.currency);
  for (const transaction of state.transactions) {
    ensureCurrencySetValue(currencies, transaction.amount.currency);
    ensureCurrencySetValue(currencies, transaction.baseAmount.currency);
    ensureCurrencySetValue(currencies, transaction.originalAmount?.currency);
    ensureCurrencySetValue(currencies, transaction.counterAmount?.currency);
  }
  return Array.from(currencies);
}

export function displayCurrency(state: LedgerState): string {
  return normalizeCurrencyCode(state.preferences.displayCurrency ?? state.preferences.baseCurrency);
}

export function setDisplayCurrency(state: LedgerState, currency: string): void {
  const normalized = normalizeCurrencyCode(currency);
  if (!normalized) throw new Error('setDisplayCurrency: currency is required');
  state.preferences.displayCurrency = normalized;
  state.preferences.enabledCurrencies = enabledCurrencies(state);
}

export function cycleDisplayCurrency(state: LedgerState): string {
  const currencies = enabledCurrencies(state);
  if (currencies.length === 0) {
    setDisplayCurrency(state, state.preferences.baseCurrency);
    return displayCurrency(state);
  }
  const current = displayCurrency(state);
  const currentIndex = currencies.indexOf(current);
  const next = currencies[(currentIndex + 1) % currencies.length] ?? state.preferences.baseCurrency;
  setDisplayCurrency(state, next);
  return next;
}

export function convertMoneyForDisplay(
  state: LedgerState,
  money: Money,
  currency = displayCurrency(state),
): Money {
  const normalizedCurrency = normalizeCurrencyCode(currency);
  if (normalizeCurrencyCode(money.currency) === normalizedCurrency) {
    return { amountMinor: money.amountMinor, currency: normalizedCurrency };
  }
  return {
    amountMinor: convertMinor(
      money.amountMinor,
      money.currency,
      normalizedCurrency,
      rateBetween(state, money.currency, normalizedCurrency),
    ),
    currency: normalizedCurrency,
  };
}

export function ensureEnabledCurrency(state: LedgerState, currency: string): void {
  const normalized = normalizeCurrencyCode(currency);
  const currencies = enabledCurrencies(state);
  if (!currencies.includes(normalized)) currencies.push(normalized);
  state.preferences.enabledCurrencies = currencies;
}

export function removeEnabledCurrency(state: LedgerState, currency: string): void {
  const normalized = normalizeCurrencyCode(currency);
  if (normalized === normalizeCurrencyCode(state.preferences.baseCurrency)) return;
  if (normalized === displayCurrency(state)) {
    state.preferences.displayCurrency = state.preferences.baseCurrency;
  }
  const used = currencyIsInUse(state, normalized);
  if (used) return;
  state.preferences.enabledCurrencies = enabledCurrencies(state).filter(
    (item) => item !== normalized,
  );
}

export function setBaseCurrency(state: LedgerState, currency: string): void {
  const nextBase = normalizeCurrencyCode(currency);
  if (!nextBase) throw new Error('setBaseCurrency: currency is required');
  state.preferences.baseCurrency = nextBase;
  if (!state.preferences.displayCurrency) state.preferences.displayCurrency = nextBase;
  ensureEnabledCurrency(state, nextBase);
  for (const transaction of state.transactions) {
    const rate = rateBetween(state, transaction.amount.currency, nextBase);
    transaction.fxRate = rate;
    transaction.baseAmount = {
      amountMinor: convertMinor(
        transaction.amount.amountMinor,
        transaction.amount.currency,
        nextBase,
        rate,
      ),
      currency: nextBase,
    };
    transaction.updatedAt = nowIso();
  }
}

export const EXCHANGE_RATE_FRESH_MS = 1000 * 60 * 60;

export function exchangeRateIsStale(
  rate: ExchangeRateRecord | undefined,
  now = new Date(),
  maxAgeMs = EXCHANGE_RATE_FRESH_MS,
): boolean {
  if (!rate) return true;
  const timestamp = rateTimestamp(rate);
  if (!timestamp) return true;
  return now.getTime() - timestamp > maxAgeMs;
}

export function exchangeRatePairIsStale(
  state: LedgerState,
  base: string,
  quote: string,
  now = new Date(),
): boolean {
  if (normalizeCurrencyCode(base) === normalizeCurrencyCode(quote)) return false;
  return exchangeRateIsStale(rateRecordForPair(state, base, quote), now);
}

function assertPostedCurrencyMatchesAccount(
  currency: string,
  accountCurrency: string,
  action: string,
): void {
  if (normalizeCurrencyCode(currency) !== normalizeCurrencyCode(accountCurrency)) {
    throw new Error(`${action}: posted amount currency must match account currency`);
  }
}

function amountInCurrency(state: LedgerState, money: Money, currency: string): number {
  const normalizedCurrency = normalizeCurrencyCode(currency);
  if (normalizeCurrencyCode(money.currency) === normalizedCurrency) return money.amountMinor;
  return convertMinor(
    money.amountMinor,
    money.currency,
    normalizedCurrency,
    rateBetween(state, money.currency, normalizedCurrency),
  );
}

function transferCounterAmountMinor(
  state: LedgerState,
  transaction: Transaction,
  accountCurrency: string,
): number {
  if (transaction.counterAmount) {
    return amountInCurrency(state, transaction.counterAmount, accountCurrency);
  }
  return amountInCurrency(state, transaction.amount, accountCurrency);
}

function resolveCounterAmount(
  state: LedgerState,
  input: CreateTransactionInput,
  sourceCurrency: string,
  counterAccount?: Account,
): { amount: Money; fxRate: number } | undefined {
  if (!counterAccount || !TRANSFER_TYPES.has(input.type)) return undefined;
  const counterCurrency = normalizeCurrencyCode(input.counterCurrency ?? counterAccount.currency);
  assertPostedCurrencyMatchesAccount(counterCurrency, counterAccount.currency, 'createTransaction');
  const rate =
    input.counterFxRate ??
    (hasExplicitRate(state, sourceCurrency, counterCurrency)
      ? rateBetween(state, sourceCurrency, counterCurrency)
      : undefined);

  if (input.counterAmountMinor !== undefined) {
    return {
      amount: { amountMinor: input.counterAmountMinor, currency: counterCurrency },
      fxRate: rate ?? rateBetween(state, sourceCurrency, counterCurrency),
    };
  }
  if (sourceCurrency === counterCurrency) return undefined;
  if (rate === undefined) {
    throw new Error(
      'createTransaction: cross-currency transfer needs a destination amount or rate',
    );
  }
  return {
    amount: {
      amountMinor: convertMinor(input.amountMinor, sourceCurrency, counterCurrency, rate),
      currency: counterCurrency,
    },
    fxRate: rate,
  };
}

function resolveUpdatedCounterAmount(
  state: LedgerState,
  patch: UpdateTransactionInput,
  transaction: Transaction,
  nextType: TransactionType,
  sourceCurrency: string,
  sourceAmountMinor: number,
  counterAccount?: Account,
): { amount: Money; fxRate: number } | undefined {
  if (!counterAccount || !TRANSFER_TYPES.has(nextType)) return undefined;
  const cleared = patch.counterAmountMinor === null || patch.counterCurrency === null;
  const counterCurrency = cleared
    ? normalizeCurrencyCode(counterAccount.currency)
    : normalizeCurrencyCode(
        patch.counterCurrency ?? transaction.counterAmount?.currency ?? counterAccount.currency,
      );
  assertPostedCurrencyMatchesAccount(counterCurrency, counterAccount.currency, 'updateTransaction');
  const rate =
    patch.counterFxRate === null
      ? undefined
      : (patch.counterFxRate ??
        transaction.counterFxRate ??
        (hasExplicitRate(state, sourceCurrency, counterCurrency)
          ? rateBetween(state, sourceCurrency, counterCurrency)
          : undefined));

  if (!cleared && patch.counterAmountMinor !== undefined && patch.counterAmountMinor !== null) {
    return {
      amount: { amountMinor: patch.counterAmountMinor, currency: counterCurrency },
      fxRate: rate ?? rateBetween(state, sourceCurrency, counterCurrency),
    };
  }
  if (
    !cleared &&
    transaction.counterAmount &&
    patch.amountMinor === undefined &&
    patch.counterCurrency === undefined
  ) {
    return {
      amount: transaction.counterAmount,
      fxRate:
        transaction.counterFxRate ??
        rateBetween(state, sourceCurrency, transaction.counterAmount.currency),
    };
  }
  if (sourceCurrency === counterCurrency) return undefined;
  if (rate === undefined) {
    throw new Error(
      'updateTransaction: cross-currency transfer needs a destination amount or rate',
    );
  }
  return {
    amount: {
      amountMinor: convertMinor(sourceAmountMinor, sourceCurrency, counterCurrency, rate),
      currency: counterCurrency,
    },
    fxRate: rate,
  };
}

function convertMinor(
  amountMinor: number,
  fromCurrency: string,
  toCurrency: string,
  rate: number,
): number {
  const normalizedFrom = normalizeCurrencyCode(fromCurrency);
  const normalizedTo = normalizeCurrencyCode(toCurrency);
  if (normalizedFrom === normalizedTo) return amountMinor;
  return toMinor(fromMinor(amountMinor, normalizedFrom) * rate, normalizedTo);
}

function rateTimestamp(rate: ExchangeRateRecord): number {
  const value = rate.updatedAt ?? rate.asOfDate;
  const timestamp = new Date(value).getTime();
  return Number.isNaN(timestamp) ? 0 : timestamp;
}

function ensureCurrencySetValue(currencies: Set<string>, currency?: string): void {
  const normalized = currency ? normalizeCurrencyCode(currency) : '';
  if (normalized) currencies.add(normalized);
}

function currencyIsInUse(state: LedgerState, currency: string): boolean {
  const normalized = normalizeCurrencyCode(currency);
  return (
    state.accounts.some((account) => normalizeCurrencyCode(account.currency) === normalized) ||
    state.transactions.some(
      (transaction) =>
        normalizeCurrencyCode(transaction.amount.currency) === normalized ||
        normalizeCurrencyCode(transaction.baseAmount.currency) === normalized ||
        normalizeCurrencyCode(transaction.originalAmount?.currency ?? '') === normalized ||
        normalizeCurrencyCode(transaction.counterAmount?.currency ?? '') === normalized,
    ) ||
    state.transactionSplits.some(
      (split) => normalizeCurrencyCode(split.amount.currency) === normalized,
    )
  );
}

// ============================================================================
// Net worth and totals (base currency)
// ============================================================================

export interface NetWorth {
  total: Money;
  assets: Money;
  liabilities: Money;
}

const LIABILITY_TYPES = new Set<AccountType>(['credit_card', 'loan', 'overdraft']);

export function netWorth(state: LedgerState, currency = state.preferences.baseCurrency): NetWorth {
  const base = normalizeCurrencyCode(currency);
  let assets = 0;
  let liabilities = 0;
  for (const a of state.accounts) {
    if (!a.includeInNetWorth) continue;
    const bal = accountBalance(state, a.id);
    const inBase = Math.round(bal.amountMinor * rateBetween(state, bal.currency, base));
    if (LIABILITY_TYPES.has(a.type)) liabilities += inBase;
    else assets += inBase;
  }
  return {
    assets: { amountMinor: assets, currency: base },
    liabilities: { amountMinor: liabilities, currency: base },
    total: { amountMinor: assets + liabilities, currency: base }, // liabilities are usually negative balances already
  };
}

export function totalBalance(state: LedgerState, currency = state.preferences.baseCurrency): Money {
  const base = normalizeCurrencyCode(currency);
  let total = 0;
  for (const a of state.accounts) {
    if (!a.includeInTotals) continue;
    const bal = accountBalance(state, a.id);
    total += Math.round(bal.amountMinor * rateBetween(state, bal.currency, base));
  }
  return { amountMinor: total, currency: base };
}

export function totalBalanceForAccounts(
  state: LedgerState,
  accountIds: Iterable<UUID>,
  currency = state.preferences.baseCurrency,
): Money {
  const base = normalizeCurrencyCode(currency);
  const selectedAccountIds = new Set(accountIds);
  let total = 0;
  for (const account of state.accounts) {
    if (!selectedAccountIds.has(account.id)) continue;
    const balance = accountBalance(state, account.id);
    total += Math.round(balance.amountMinor * rateBetween(state, balance.currency, base));
  }
  return { amountMinor: total, currency: base };
}

export function projectedBalanceForAccountsThroughDate(
  state: LedgerState,
  accountIds: Iterable<UUID>,
  through: Date,
  currency = state.preferences.baseCurrency,
): Money {
  const base = normalizeCurrencyCode(currency);
  const selectedAccountIds = new Set(accountIds);
  let balance = totalBalanceForAccounts(state, selectedAccountIds, base).amountMinor;

  for (const transaction of state.transactions) {
    if (transaction.status !== 'scheduled') continue;
    if (transaction.isExcludedFromReports) continue;
    if (!selectedAccountIds.has(transaction.accountId)) continue;
    const occurredAt = new Date(transaction.occurredAt);
    if (Number.isNaN(occurredAt.getTime()) || occurredAt >= through) continue;

    const amount = Math.abs(
      Math.round(
        transaction.baseAmount.amountMinor *
          rateBetween(state, transaction.baseAmount.currency, base),
      ),
    );
    if (INFLOW_TYPES.has(transaction.type)) balance += amount;
    else if (
      OUTFLOW_TYPES.has(transaction.type) ||
      transaction.type === 'card_payment' ||
      transaction.type === 'loan_repayment'
    ) {
      balance -= amount;
    }
  }

  return { amountMinor: balance, currency: base };
}

// ============================================================================
// Cashflow / dashboard
// ============================================================================

export interface CashflowSummary {
  periodStart: string;
  periodEnd: string;
  income: Money;
  expense: Money;
  net: Money;
}

export function monthRange(date = new Date(), startDayOfMonth = 1): { start: Date; end: Date } {
  const y = date.getFullYear();
  const m = date.getMonth();
  const start = new Date(y, m, startDayOfMonth, 0, 0, 0, 0);
  if (date < start) start.setMonth(start.getMonth() - 1);
  const end = new Date(start);
  end.setMonth(end.getMonth() + 1);
  return { start, end };
}

export function cashflow(state: LedgerState, ref = new Date()): CashflowSummary {
  const { start, end } = monthRange(ref, state.preferences.startDayOfMonth);
  const base = state.preferences.baseCurrency;
  let income = 0;
  let expense = 0;
  for (const t of state.transactions) {
    if (!affectsPostedBalance(t)) continue;
    if (t.isExcludedFromReports) continue;
    const acct = state.accounts.find((a) => a.id === t.accountId);
    if (!acct || !acct.includeInReports) continue;
    const when = new Date(t.occurredAt);
    if (when < start || when >= end) continue;
    const amount = t.baseAmount.amountMinor;
    if (INFLOW_TYPES.has(t.type)) income += amount;
    else if (OUTFLOW_TYPES.has(t.type)) expense += amount;
  }
  return {
    periodStart: start.toISOString().slice(0, 10),
    periodEnd: end.toISOString().slice(0, 10),
    income: { amountMinor: income, currency: base },
    expense: { amountMinor: expense, currency: base },
    net: { amountMinor: income - expense, currency: base },
  };
}

function reportingAllocations(
  state: LedgerState,
  transaction: Transaction,
): { categoryId?: UUID; amountBaseMinor: number }[] {
  const splits = state.transactionSplits.filter((split) => split.transactionId === transaction.id);
  return reportingAllocationsFromSplits(state, transaction, splits);
}

function reportingAllocationsFromSplits(
  state: LedgerState,
  transaction: Transaction,
  splits: TransactionSplit[],
): { categoryId?: UUID; amountBaseMinor: number }[] {
  if (splits.length === 0) {
    return [
      { categoryId: transaction.categoryId, amountBaseMinor: transaction.baseAmount.amountMinor },
    ];
  }

  const base = state.preferences.baseCurrency;
  const allocations = splits.map((split) => ({
    categoryId: split.categoryId ?? transaction.categoryId,
    amountBaseMinor: Math.round(
      split.amount.amountMinor * rateBetween(state, split.amount.currency, base),
    ),
  }));
  const allocated = allocations.reduce((sum, split) => sum + split.amountBaseMinor, 0);
  const remainder = transaction.baseAmount.amountMinor - allocated;
  if (remainder > 0) {
    allocations.push({ categoryId: transaction.categoryId, amountBaseMinor: remainder });
  }
  return allocations;
}

function splitsByTransaction(splits: TransactionSplit[]): Map<UUID, TransactionSplit[]> {
  const result = new Map<UUID, TransactionSplit[]>();
  for (const split of splits) {
    const transactionSplits = result.get(split.transactionId);
    if (transactionSplits) transactionSplits.push(split);
    else result.set(split.transactionId, [split]);
  }
  return result;
}

export interface CategoryBreakdownItem {
  categoryId?: UUID;
  categoryName: string;
  amount: Money;
  share: number; // 0..1
}

export function categoryBreakdown(
  state: LedgerState,
  ref = new Date(),
  kind: 'expense' | 'income' = 'expense',
): CategoryBreakdownItem[] {
  const { start, end } = monthRange(ref, state.preferences.startDayOfMonth);
  const base = state.preferences.baseCurrency;
  const types = kind === 'expense' ? OUTFLOW_TYPES : INFLOW_TYPES;
  const byCat = new Map<string, number>();
  let total = 0;
  for (const t of state.transactions) {
    if (!affectsPostedBalance(t)) continue;
    if (t.isExcludedFromReports) continue;
    if (!types.has(t.type)) continue;
    const acct = state.accounts.find((a) => a.id === t.accountId);
    if (!acct || !acct.includeInReports) continue;
    const when = new Date(t.occurredAt);
    if (when < start || when >= end) continue;
    for (const allocation of reportingAllocations(state, t)) {
      const key = allocation.categoryId ?? '__none';
      byCat.set(key, (byCat.get(key) ?? 0) + allocation.amountBaseMinor);
      total += allocation.amountBaseMinor;
    }
  }
  const items: CategoryBreakdownItem[] = [];
  for (const [key, amt] of byCat) {
    const cat = key === '__none' ? undefined : state.categories.find((c) => c.id === key);
    items.push({
      categoryId: cat?.id,
      categoryName: cat?.name ?? 'Uncategorized',
      amount: { amountMinor: amt, currency: base },
      share: total > 0 ? amt / total : 0,
    });
  }
  return items.sort((a, b) => b.amount.amountMinor - a.amount.amountMinor);
}

// ============================================================================
// Budgets
// ============================================================================

export interface BudgetStatus {
  budgetId: UUID;
  name: string;
  limit: Money;
  spent: Money;
  remaining: Money;
  share: number; // 0..1+
  isOver: boolean;
}

export function budgetStatuses(state: LedgerState, ref = new Date()): BudgetStatus[] {
  const { start, end } = monthRange(ref, state.preferences.startDayOfMonth);
  const accountsById = new Map(state.accounts.map((account) => [account.id, account]));
  const categoryIdByName = new Map<string, UUID>();
  for (const category of state.categories) {
    if (!categoryIdByName.has(category.name)) categoryIdByName.set(category.name, category.id);
  }
  const splitsByTransactionId = splitsByTransaction(state.transactionSplits);
  const spentByCategoryId = new Map<UUID, number>();
  let totalSpent = 0;

  for (const transaction of state.transactions) {
    if (!affectsPostedBalance(transaction)) continue;
    if (transaction.isExcludedFromReports) continue;
    if (!OUTFLOW_TYPES.has(transaction.type)) continue;
    const account = accountsById.get(transaction.accountId);
    if (!account?.includeInBudgets) continue;
    const when = new Date(transaction.occurredAt);
    if (when < start || when >= end) continue;

    for (const allocation of reportingAllocationsFromSplits(
      state,
      transaction,
      splitsByTransactionId.get(transaction.id) ?? [],
    )) {
      totalSpent += allocation.amountBaseMinor;
      if (allocation.categoryId) {
        spentByCategoryId.set(
          allocation.categoryId,
          (spentByCategoryId.get(allocation.categoryId) ?? 0) + allocation.amountBaseMinor,
        );
      }
    }
  }

  const result: BudgetStatus[] = [];
  for (const b of state.budgets) {
    if (b.isPaused) continue;
    // For MVP, treat each budget as monthly and scoped to its name == category name.
    // The richer scope (budget_scopes) lands later.
    const scopedCategoryId = categoryIdByName.get(b.name);
    const spent = scopedCategoryId ? (spentByCategoryId.get(scopedCategoryId) ?? 0) : totalSpent;
    const remaining = b.amount.amountMinor - spent;
    result.push({
      budgetId: b.id,
      name: b.name,
      limit: b.amount,
      spent: { amountMinor: spent, currency: b.amount.currency },
      remaining: { amountMinor: remaining, currency: b.amount.currency },
      share: b.amount.amountMinor > 0 ? spent / b.amount.amountMinor : 0,
      isOver: spent > b.amount.amountMinor,
    });
  }
  return result;
}

// ============================================================================
// Goals
// ============================================================================

export interface GoalStatus {
  goalId: UUID;
  name: string;
  target: Money;
  saved: Money;
  share: number;
  monthlyRequired?: Money;
}

export function goalStatuses(state: LedgerState, ref = new Date()): GoalStatus[] {
  const inflowByCategoryId = new Map<UUID, number>();
  for (const transaction of state.transactions) {
    if (!affectsPostedBalance(transaction)) continue;
    if (!transaction.categoryId) continue;
    if (!INFLOW_TYPES.has(transaction.type)) continue;
    inflowByCategoryId.set(
      transaction.categoryId,
      (inflowByCategoryId.get(transaction.categoryId) ?? 0) + transaction.baseAmount.amountMinor,
    );
  }

  const result: GoalStatus[] = [];
  for (const g of state.goals) {
    if (g.isCompleted) continue;
    // MVP: "saved" is approximated as sum of inflows tagged with category linkedCategoryId
    // or sum of all balances when no linked category.
    const saved = g.linkedCategoryId ? (inflowByCategoryId.get(g.linkedCategoryId) ?? 0) : 0;
    let monthlyRequired: Money | undefined;
    if (g.targetDate) {
      const months = Math.max(1, monthsBetween(ref, new Date(g.targetDate)));
      monthlyRequired = {
        amountMinor: Math.max(0, Math.round((g.targetAmount.amountMinor - saved) / months)),
        currency: g.targetAmount.currency,
      };
    }
    result.push({
      goalId: g.id,
      name: g.name,
      target: g.targetAmount,
      saved: { amountMinor: saved, currency: g.targetAmount.currency },
      share: g.targetAmount.amountMinor > 0 ? saved / g.targetAmount.amountMinor : 0,
      monthlyRequired,
    });
  }
  return result;
}

function monthsBetween(a: Date, b: Date): number {
  return (b.getFullYear() - a.getFullYear()) * 12 + (b.getMonth() - a.getMonth());
}

// ============================================================================
// Loan amortization
// ============================================================================

export interface AmortizationRow {
  installment: number;
  dueDate: string;
  principal: Money;
  interest: Money;
  balanceAfter: Money;
}

export function amortize(
  principalMinor: number,
  annualRatePercent: number,
  tenureMonths: number,
  startDate = new Date(),
  currency = 'INR',
): { emiMinor: number; schedule: AmortizationRow[] } {
  const r = annualRatePercent / 100 / 12;
  const P = principalMinor;
  const n = tenureMonths;
  const emiMinor =
    r === 0
      ? Math.round(P / n)
      : Math.round((P * r * Math.pow(1 + r, n)) / (Math.pow(1 + r, n) - 1));
  const schedule: AmortizationRow[] = [];
  let balance = P;
  for (let i = 1; i <= n; i++) {
    const interest = Math.round(balance * r);
    const principal = Math.min(emiMinor - interest, balance);
    balance -= principal;
    const due = new Date(startDate);
    due.setMonth(due.getMonth() + i);
    schedule.push({
      installment: i,
      dueDate: due.toISOString().slice(0, 10),
      principal: { amountMinor: principal, currency },
      interest: { amountMinor: interest, currency },
      balanceAfter: { amountMinor: Math.max(0, balance), currency },
    });
  }
  return { emiMinor, schedule };
}

export function simulatePrepayment(
  principalMinor: number,
  annualRatePercent: number,
  emiMinor: number,
  extraMonthlyMinor = 0,
  oneTimePrepayMinor = 0,
  currency = 'INR',
): { monthsToClose: number; totalInterest: Money } {
  const r = annualRatePercent / 100 / 12;
  let balance = Math.max(0, principalMinor - oneTimePrepayMinor);
  let totalInterest = 0;
  let months = 0;
  while (balance > 0 && months < 1200) {
    const interest = Math.round(balance * r);
    const principal = Math.min(emiMinor + extraMonthlyMinor - interest, balance);
    if (principal <= 0) {
      // emi too low to cover interest
      return { monthsToClose: Infinity, totalInterest: { amountMinor: 0, currency } };
    }
    balance -= principal;
    totalInterest += interest;
    months++;
  }
  return { monthsToClose: months, totalInterest: { amountMinor: totalInterest, currency } };
}

// ============================================================================
// Sums / search
// ============================================================================

export interface TransactionFilter {
  accountId?: UUID;
  categoryId?: UUID;
  from?: string;
  to?: string;
  type?: TransactionType;
  text?: string;
  source?: Transaction['source'];
  status?: Transaction['status'];
}

export function queryTransactions(state: LedgerState, f: TransactionFilter = {}): Transaction[] {
  return state.transactions
    .filter((t) => {
      if (f.accountId && t.accountId !== f.accountId && t.counterAccountId !== f.accountId)
        return false;
      if (f.categoryId && t.categoryId !== f.categoryId) return false;
      if (f.type && t.type !== f.type) return false;
      if (f.source && t.source !== f.source) return false;
      if (f.status && t.status !== f.status) return false;
      if (f.from && t.occurredAt < f.from) return false;
      if (f.to && t.occurredAt > f.to) return false;
      if (f.text) {
        const hay = `${t.notes ?? ''} ${t.tags?.join(' ') ?? ''}`.toLowerCase();
        if (!hay.includes(f.text.toLowerCase())) return false;
      }
      return true;
    })
    .sort((a, b) => (a.occurredAt < b.occurredAt ? 1 : -1));
}

export interface CaptureCandidateFilter {
  source?: CaptureSource;
  status?: CaptureCandidateStatus;
}

export function queryCaptureCandidates(
  state: LedgerState,
  filter: CaptureCandidateFilter = {},
): CaptureCandidate[] {
  return state.captureCandidates
    .filter((candidate) => {
      if (filter.source && candidate.source !== filter.source) return false;
      if (filter.status && candidate.status !== filter.status) return false;
      return true;
    })
    .sort((left, right) => (left.createdAt < right.createdAt ? 1 : -1));
}

export function sumMoney(amounts: Money[]): Money {
  if (amounts.length === 0) return { amountMinor: 0, currency: 'INR' };
  const currency = amounts[0]!.currency;
  return amounts.reduce((acc, m) => addMoney(acc, m), { amountMinor: 0, currency });
}

export function formatBalance(m: Money, locale = 'en-IN'): string {
  return new Intl.NumberFormat(locale, {
    style: 'currency',
    currency: m.currency,
    maximumFractionDigits: 0,
  }).format(fromMinor(m.amountMinor, m.currency));
}

function clampConfidence(value: number): number {
  return Math.max(0, Math.min(100, value));
}

function deriveRawHash(source: CaptureSource, rawPayload: Record<string, unknown>): string {
  return `${source}:${hashString(stableStringify(rawPayload))}`;
}

function stableStringify(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map((item) => stableStringify(item)).join(',')}]`;
  const record = value as Record<string, unknown>;
  return `{${Object.keys(record)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${stableStringify(record[key])}`)
    .join(',')}}`;
}

function hashString(value: string): string {
  let hash = 2166136261;
  for (const character of value) {
    hash ^= character.charCodeAt(0);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(36);
}
