import { fromMinor, toMinor } from '@1wallet/domain/money';
import type { Account, AccountType, Category, TransactionType, UUID } from '@1wallet/domain/types';
import { DEFAULT_CATEGORY_TAXONOMY } from '../seed';
import { createAccount, createCategory, type CreateCaptureCandidateInput } from '../services/index';
import type {
    FutureGenerationFrequency,
    FutureGenerationRule,
    LedgerState,
    PlannedPaymentKind,
} from '../store/types';

export type WalletCsvType = 'Expense' | 'Income';

export interface WalletCsvFile {
  fileName: string;
  content: string;
}

export interface WalletCsvRawRow {
  account: string;
  category: string;
  currency: string;
  amount: string;
  ref_currency_amount: string;
  type: string;
  payment_type: string;
  note: string;
  date: string;
  transfer: string;
  payee: string;
  labels: string;
}

export interface WalletCsvParsedRow {
  fileName: string;
  rowNumber: number;
  raw: WalletCsvRawRow;
  rawHash: string;
  semanticKey: string;
  accountName: string;
  categoryName: string;
  currency: string;
  amountMinor: number;
  refCurrencyAmount?: number;
  type: WalletCsvType;
  paymentMethod?: string;
  note?: string;
  payee?: string;
  labels: string[];
  occurredAt: string;
  isTransfer: boolean;
  accountId?: UUID;
  accountMatch?: WalletCsvAccountMatch;
  categoryId?: UUID;
  suggestedType: TransactionType;
  confidence: number;
  warnings: string[];
}

export interface WalletCsvAccountMatch {
  accountName: string;
  kind: 'exact' | 'alias' | 'similar';
  reason: string;
  score: number;
}

export interface WalletCsvCandidateProposal {
  key: string;
  semanticKey: string;
  externalRef: string;
  rawHash: string;
  fileNames: string[];
  rowNumbers: number[];
  sourceRow: WalletCsvParsedRow;
  pairedRow?: WalletCsvParsedRow;
  amountMinor: number;
  currency: string;
  suggestedType: TransactionType;
  suggestedAccountId?: UUID;
  suggestedCounterAccountId?: UUID;
  suggestedCategoryId?: UUID;
  parsedFxRate?: number;
  parsedOriginalAmountMinor?: number;
  parsedOriginalCurrency?: string;
  parsedOriginalFxRate?: number;
  parsedMerchant?: string;
  parsedNotes?: string;
  parsedPaymentMethod?: string;
  parsedTags?: string[];
  parsedCounterAmountMinor?: number;
  parsedCounterCurrency?: string;
  parsedCounterFxRate?: number;
  parsedOccurredAt: string;
  confidence: number;
  duplicate: boolean;
  warnings: string[];
}

export interface WalletCsvPlannedPaymentRowRef {
  fileName: string;
  rowNumber: number;
  pairedRowNumber?: number;
  occurredOn: string;
  accountName: string;
  counterAccountName?: string;
  categoryName?: string;
  payee?: string;
  note?: string;
  amountMinor: number;
  currency: string;
}

export type WalletCsvPlannedPaymentActivity =
  | 'active'
  | 'needs_review'
  | 'historical'
  | 'already_created';

export interface WalletCsvPlannedPaymentDetectionOptions {
  now?: Date;
  activeRecentWindowMonths?: number;
  activeLowFrequencyWindowMonths?: number;
}

export interface WalletCsvImportAnalysisOptions extends WalletCsvPlannedPaymentDetectionOptions {}

export interface WalletCsvCaptureLinkOptions {
  plannedPayments?: WalletCsvPlannedPaymentCandidate[];
  ruleIdsByPlannedPaymentKey?: Record<string, UUID>;
  loanAccountIdsByPlannedPaymentKey?: Record<string, UUID>;
}

export interface WalletCsvPlannedPaymentCandidate {
  key: string;
  name: string;
  kind: PlannedPaymentKind;
  type: TransactionType;
  accountName: string;
  accountId?: UUID;
  counterAccountName?: string;
  counterAccountId?: UUID;
  categoryName?: string;
  categoryId?: UUID;
  amountMinor: number;
  latestAmountMinor: number;
  amountMinMinor: number;
  amountMaxMinor: number;
  currency: string;
  frequency: FutureGenerationFrequency;
  interval: number;
  dayOfMonth?: number;
  startsOn: string;
  lastSeenOn: string;
  nextDueOn: string;
  occurrences: number;
  activity: WalletCsvPlannedPaymentActivity;
  activityReason: string;
  matchingRuleId?: UUID;
  matchingRuleName?: string;
  paymentMethod?: string;
  tags?: string[];
  confidence: number;
  sourceRows: WalletCsvPlannedPaymentRowRef[];
  warnings: string[];
}

export interface WalletCsvValueSummary {
  value: string;
  count: number;
}

export interface WalletCsvDateRange {
  start?: string;
  end?: string;
}

export interface WalletCsvFileSummary {
  fileName: string;
  rowCount: number;
  transferRows: number;
  invalidRows: number;
  dateRange: WalletCsvDateRange;
  accounts: WalletCsvValueSummary[];
  categories: WalletCsvValueSummary[];
  currencies: WalletCsvValueSummary[];
  paymentTypes: WalletCsvValueSummary[];
}

export interface WalletCsvProvisionSummary {
  accountsCreated: number;
  categoriesCreated: number;
  accountNames: string[];
  categoryNames: string[];
}

export interface WalletCsvImportAnalysis {
  files: string[];
  rowCount: number;
  parsedRows: WalletCsvParsedRow[];
  proposals: WalletCsvCandidateProposal[];
  plannedPayments: WalletCsvPlannedPaymentCandidate[];
  summary: {
    candidates: number;
    queueable: number;
    blocked: number;
    duplicates: number;
    plannedPayments: number;
    plannedPaymentsActive: number;
    plannedPaymentsNeedsReview: number;
    plannedPaymentsHistorical: number;
    plannedPaymentsAlreadyCreated: number;
    transferPairs: number;
    unpairedTransfers: number;
    unknownAccounts: number;
    unknownCategories: number;
    invalidRows: number;
    warnings: number;
    dateRange: WalletCsvDateRange;
    perFile: WalletCsvFileSummary[];
    accounts: WalletCsvValueSummary[];
    categories: WalletCsvValueSummary[];
    currencies: WalletCsvValueSummary[];
    paymentTypes: WalletCsvValueSummary[];
    payees: WalletCsvValueSummary[];
    labels: WalletCsvValueSummary[];
  };
}

const REQUIRED_HEADERS = [
  'account',
  'category',
  'currency',
  'amount',
  'ref_currency_amount',
  'type',
  'payment_type',
  'note',
  'date',
  'transfer',
  'payee',
  'labels',
] as const;

const ACCOUNT_ALIASES: Record<string, string> = {
  amazonpay: 'amazonpaycreditcard',
  amazonpaycard: 'amazonpaycreditcard',
  amazonpayicici: 'amazonpaycreditcard',
  amazonpayicicicard: 'amazonpaycreditcard',
  axisforex: 'axisforexcard',
  axissupermoney: 'axissupermoneycreditcard',
  bobonecard: 'onecardbob',
  hdfcmoneyback: 'hdfcmoneybackcreditcard',
  hdfcmoneybackcard: 'hdfcmoneybackcreditcard',
  icicicoral: 'icicicoralcreditcard',
  icicicoralcard: 'icicicoralcreditcard',
  onecard: 'onecardbob',
  onecardbankofbaroda: 'onecardbob',
  onecardbob: 'onecardbob',
  sbicashback: 'sbicashbackcreditcard',
  sbicashbackcard: 'sbicashbackcreditcard',
  sbisimplyclick: 'sbisimplyclickcreditcard',
  sbisimplyclickcard: 'sbisimplyclickcreditcard',
  sbisimplyclickcreditcard: 'sbisimplyclickcreditcard',
  simplyclick: 'sbisimplyclickcreditcard',
  swiggyhdfc: 'swiggyhdfccreditcard',
  swiggyhdfccard: 'swiggyhdfccreditcard',
};

const GENERIC_ACCOUNT_TOKENS = new Set([
  'account',
  'bank',
  'card',
  'cc',
  'credit',
  'debit',
  'forex',
  'loan',
  'prepaid',
  'savings',
  'saving',
  'upi',
  'wallet',
]);

const GENERIC_CATEGORY_TOKENS = new Set([
  'and',
  'bill',
  'bills',
  'cash',
  'category',
  'expense',
  'expenses',
  'general',
  'income',
  'misc',
  'miscellaneous',
  'other',
  'others',
  'payment',
  'payments',
  'transfer',
  'uncategorized',
  'withdraw',
  'withdrawal',
]);

const BLOCKING_WARNINGS = new Set([
  'invalid amount',
  'invalid date',
  'unknown type',
  'ambiguous transfer match',
]);

const PLANNED_PAYMENT_MIN_OCCURRENCES = 3;

export function parseWalletCsvFile(file: WalletCsvFile): WalletCsvParsedRow[] {
  const lines = file.content
    .replace(/^\uFEFF/, '')
    .split(/\r?\n/)
    .filter((line) => line.trim().length > 0);
  if (lines.length === 0) return [];
  const headers = parseCsvLine(lines[0] ?? '').map((header) => header.trim());
  const missing = REQUIRED_HEADERS.filter((header) => !headers.includes(header));
  if (missing.length > 0) {
    throw new Error(`Wallet CSV ${file.fileName}: missing headers ${missing.join(', ')}`);
  }

  return lines.slice(1).map((line, index) => {
    const cells = parseCsvLine(line);
    const raw = headers.reduce<Partial<WalletCsvRawRow>>((row, header, cellIndex) => {
      row[header as keyof WalletCsvRawRow] = cells[cellIndex] ?? '';
      return row;
    }, {}) as WalletCsvRawRow;
    return normalizeWalletCsvRow(file.fileName, index + 2, raw);
  });
}

export function analyzeWalletCsvImport(
  state: LedgerState,
  files: WalletCsvFile[],
  options: WalletCsvImportAnalysisOptions = {},
): WalletCsvImportAnalysis {
  const parsedRows = files.flatMap((file) => parseWalletCsvFile(file));
  const rows = parsedRows.map((row) => matchWalletCsvRow(state, row));
  const proposals = buildWalletCsvProposals(state, rows);
  const plannedPayments = detectWalletCsvPlannedPayments(state, proposals, options);
  const summary = summarizeWalletCsvRows(rows, proposals, plannedPayments);
  return {
    files: files.map((file) => file.fileName),
    rowCount: rows.length,
    parsedRows: rows,
    proposals,
    plannedPayments,
    summary,
  };
}

export function walletCsvProposalsToCaptureInputs(
  proposals: WalletCsvCandidateProposal[],
  importBatchId?: UUID,
  linkOptions: WalletCsvCaptureLinkOptions = {},
): CreateCaptureCandidateInput[] {
  return proposals.filter(isWalletCsvProposalQueueable).map((proposal) => {
    const plannedPaymentLink = plannedPaymentLinkForProposal(proposal, linkOptions);
    const linkedLoanAccountId = plannedPaymentLink?.loanAccountId;
    const linkedLoanIsLent = plannedPaymentLink?.candidate.type === 'income';

    return {
      source: 'import',
      rawPayload: {
        source: 'wallet_csv',
        fileNames: proposal.fileNames,
        rowNumbers: proposal.rowNumbers,
        semanticKey: proposal.semanticKey,
        rawHash: proposal.rawHash,
        externalRef: proposal.externalRef,
        rowRefs: walletCsvProposalRows(proposal).map(walletCsvRowRef),
        rows: proposal.pairedRow
          ? [proposal.sourceRow.raw, proposal.pairedRow.raw]
          : [proposal.sourceRow.raw],
      },
      rawHash: proposal.rawHash,
      parsedAmountMinor: proposal.amountMinor,
      parsedCurrency: proposal.currency,
      parsedFxRate: proposal.parsedFxRate,
      parsedOriginalAmountMinor: proposal.parsedOriginalAmountMinor,
      parsedOriginalCurrency: proposal.parsedOriginalCurrency,
      parsedOriginalFxRate: proposal.parsedOriginalFxRate,
      parsedMerchant: proposal.parsedMerchant,
      parsedNotes: proposal.parsedNotes,
      parsedPaymentMethod: proposal.parsedPaymentMethod,
      parsedTags: proposal.parsedTags,
      parsedCounterAmountMinor: proposal.parsedCounterAmountMinor,
      parsedCounterCurrency: proposal.parsedCounterCurrency,
      parsedCounterFxRate: proposal.parsedCounterFxRate,
      parsedOccurredAt: proposal.parsedOccurredAt,
      suggestedAccountId:
        linkedLoanAccountId && linkedLoanIsLent ? linkedLoanAccountId : proposal.suggestedAccountId,
      suggestedCounterAccountId: linkedLoanAccountId
        ? linkedLoanIsLent
          ? proposal.suggestedAccountId
          : linkedLoanAccountId
        : proposal.suggestedCounterAccountId,
      suggestedCategoryId: linkedLoanAccountId ? undefined : proposal.suggestedCategoryId,
      suggestedType: linkedLoanAccountId ? 'loan_repayment' : proposal.suggestedType,
      suggestedRecurringTemplateId: plannedPaymentLink?.ruleId,
      confidence: proposal.confidence,
      importBatchId,
      externalRef: proposal.externalRef,
      warnings: proposal.warnings,
    };
  });
}

export function summarizeWalletCsvRows(
  rows: WalletCsvParsedRow[],
  proposals: WalletCsvCandidateProposal[],
  plannedPayments: WalletCsvPlannedPaymentCandidate[] = [],
): WalletCsvImportAnalysis['summary'] {
  const transferPairs = proposals.filter(
    (proposal) =>
      Boolean(proposal.pairedRow) &&
      (proposal.suggestedType === 'transfer' || proposal.suggestedType === 'card_payment'),
  ).length;
  const queueable = proposals.filter(isWalletCsvProposalQueueable).length;
  const invalidRows = rows.filter((row) =>
    row.warnings.some((warning) => BLOCKING_WARNINGS.has(warning)),
  ).length;

  return {
    candidates: proposals.length,
    queueable,
    blocked: proposals.length - queueable,
    duplicates: proposals.filter((proposal) => proposal.duplicate).length,
    plannedPayments: plannedPayments.length,
    plannedPaymentsActive: plannedPayments.filter((candidate) => candidate.activity === 'active')
      .length,
    plannedPaymentsNeedsReview: plannedPayments.filter(
      (candidate) => candidate.activity === 'needs_review',
    ).length,
    plannedPaymentsHistorical: plannedPayments.filter(
      (candidate) => candidate.activity === 'historical',
    ).length,
    plannedPaymentsAlreadyCreated: plannedPayments.filter(
      (candidate) => candidate.activity === 'already_created',
    ).length,
    transferPairs,
    unpairedTransfers: rows.filter((row) => row.isTransfer).length - transferPairs * 2,
    unknownAccounts: rows.filter((row) => !row.accountId).length,
    unknownCategories: rows.filter((row) => !row.categoryId && !row.isTransfer).length,
    invalidRows,
    warnings: proposals.reduce((sum, proposal) => sum + proposal.warnings.length, 0),
    dateRange: dateRangeForRows(rows),
    perFile: summarizeFiles(rows),
    accounts: uniqueWalletCsvFieldValues(rows, 'accountName'),
    categories: uniqueWalletCsvFieldValues(rows, 'categoryName'),
    currencies: uniqueWalletCsvFieldValues(rows, 'currency'),
    paymentTypes: uniqueWalletCsvFieldValues(rows, 'paymentMethod'),
    payees: uniqueWalletCsvFieldValues(rows, 'payee'),
    labels: uniqueWalletCsvFieldValues(rows, 'labels'),
  };
}

function plannedPaymentLinkForProposal(
  proposal: WalletCsvCandidateProposal,
  options: WalletCsvCaptureLinkOptions,
):
  | {
      candidate: WalletCsvPlannedPaymentCandidate;
      ruleId: UUID;
      loanAccountId?: UUID;
    }
  | undefined {
  if (!options.plannedPayments?.length || !options.ruleIdsByPlannedPaymentKey) return undefined;
  const candidate = options.plannedPayments.find((plannedPayment) => {
    if (!options.ruleIdsByPlannedPaymentKey?.[plannedPayment.key]) return false;
    return plannedPayment.sourceRows.some((sourceRow) =>
      plannedPaymentSourceRowMatchesProposal(sourceRow, proposal),
    );
  });
  if (!candidate) return undefined;
  const ruleId = options.ruleIdsByPlannedPaymentKey[candidate.key];
  if (!ruleId) return undefined;
  return {
    candidate,
    ruleId,
    loanAccountId: options.loanAccountIdsByPlannedPaymentKey?.[candidate.key],
  };
}

function plannedPaymentSourceRowMatchesProposal(
  sourceRow: WalletCsvPlannedPaymentRowRef,
  proposal: WalletCsvCandidateProposal,
): boolean {
  if (sourceRow.fileName !== proposal.sourceRow.fileName) return false;
  if (sourceRow.rowNumber === proposal.sourceRow.rowNumber) return true;
  if (sourceRow.pairedRowNumber && sourceRow.pairedRowNumber === proposal.pairedRow?.rowNumber) {
    return true;
  }
  return false;
}

export function uniqueWalletCsvFieldValues(
  rows: WalletCsvParsedRow[],
  field: 'accountName' | 'categoryName' | 'currency' | 'paymentMethod' | 'payee' | 'labels',
): WalletCsvValueSummary[] {
  const values = rows.flatMap((row) => {
    if (field === 'labels') return row.labels;
    return [row[field]];
  });
  return countValues(values);
}

export function walletCsvBlockedReason(proposal: WalletCsvCandidateProposal): string | undefined {
  if (isWalletCsvProposalQueueable(proposal)) return undefined;
  if (proposal.duplicate) return 'duplicate import row';
  if (proposal.amountMinor <= 0) return 'invalid amount';
  if (!proposal.suggestedAccountId) return `unknown account: ${proposal.sourceRow.accountName}`;

  const needsCounter =
    proposal.suggestedType === 'transfer' ||
    proposal.suggestedType === 'card_payment' ||
    proposal.suggestedType === 'loan_repayment';
  if (needsCounter && !proposal.suggestedCounterAccountId) return 'missing destination account';

  const blockingWarning = proposal.warnings.find((warning) => BLOCKING_WARNINGS.has(warning));
  return blockingWarning ?? 'needs review';
}

export function provisionWalletCsvEntities(
  state: LedgerState,
  files: WalletCsvFile[],
): WalletCsvProvisionSummary {
  const rows = files.flatMap((file) => parseWalletCsvFile(file));
  const accountNames: string[] = [];
  const categoryNames: string[] = [];

  for (const accountName of unique(rows.map((row) => row.accountName)).filter(Boolean)) {
    if (findAccount(state.accounts, accountName)) continue;
    const accountRows = rows.filter(
      (row) => normalizeName(row.accountName) === normalizeName(accountName),
    );
    const currency =
      mostCommon(accountRows.map((row) => row.currency)) ?? state.preferences.baseCurrency;
    createAccount(state, {
      name: accountName,
      type: inferWalletCsvAccountType(accountName),
      currency,
      openingBalanceMinor: 0,
      icon: inferWalletCsvAccountIcon(accountName),
      color: inferWalletCsvAccountColor(accountName),
      institution: inferWalletCsvInstitution(accountName),
      notes: `Created from Wallet CSV import. Original Wallet account label: ${accountName}.`,
    });
    accountNames.push(accountName);
  }

  const categoryKeys = new Set<string>();
  for (const row of rows) {
    if (row.isTransfer || !row.categoryName) continue;
    const kind = categoryKindFor(row);
    const key = normalizeName(row.categoryName);
    if (categoryKeys.has(key) || findCategory(state.categories, row.categoryName)) continue;
    createCategory(state, {
      name: row.categoryName,
      kind,
      icon: kind === 'income' ? 'arrow-down-circle-outline' : 'shape-outline',
      color: kind === 'income' ? '#22C55E' : '#64748B',
    });
    categoryKeys.add(key);
    categoryNames.push(row.categoryName);
  }

  return {
    accountsCreated: accountNames.length,
    categoriesCreated: categoryNames.length,
    accountNames,
    categoryNames,
  };
}

export function isWalletCsvProposalQueueable(proposal: WalletCsvCandidateProposal): boolean {
  const needsCounter =
    proposal.suggestedType === 'transfer' ||
    proposal.suggestedType === 'card_payment' ||
    proposal.suggestedType === 'loan_repayment';
  const hasBlockingWarning = proposal.warnings.some((warning) => BLOCKING_WARNINGS.has(warning));
  return (
    !proposal.duplicate &&
    proposal.amountMinor > 0 &&
    Boolean(proposal.suggestedAccountId) &&
    (!needsCounter || Boolean(proposal.suggestedCounterAccountId)) &&
    !hasBlockingWarning
  );
}

function normalizeWalletCsvRow(
  fileName: string,
  rowNumber: number,
  raw: WalletCsvRawRow,
): WalletCsvParsedRow {
  const currency = raw.currency.trim().toUpperCase();
  const amount = Number(raw.amount.replace(/,/g, '').trim());
  const refCurrencyAmount = parseOptionalAmount(raw.ref_currency_amount);
  const type = normalizeCsvType(raw.type);
  const occurredAt = normalizeDate(raw.date);
  const isTransfer = raw.transfer.trim().toLowerCase() === 'true';
  const categoryName = raw.category.trim();
  const warnings: string[] = [];
  if (!Number.isFinite(amount) || amount <= 0) warnings.push('invalid amount');
  if (raw.ref_currency_amount.trim() && refCurrencyAmount === undefined) {
    warnings.push('invalid reference amount');
  }
  if (!occurredAt) warnings.push('invalid date');
  if (!type) warnings.push('unknown type');

  return {
    fileName,
    rowNumber,
    raw,
    rawHash: stableHash(REQUIRED_HEADERS.map((header) => raw[header]).join('|')),
    semanticKey: semanticRowKey({
      account: raw.account,
      category: raw.category,
      currency,
      amountMinor: Number.isFinite(amount) ? toMinor(amount, currency) : 0,
      type: type ?? raw.type,
      isTransfer,
      occurredAt,
      payee: raw.payee,
    }),
    accountName: raw.account.trim(),
    categoryName,
    currency,
    amountMinor: Number.isFinite(amount) ? toMinor(amount, currency) : 0,
    refCurrencyAmount,
    type: type ?? 'Expense',
    paymentMethod: clean(raw.payment_type),
    note: clean(raw.note),
    payee: clean(raw.payee),
    labels: splitLabels(raw.labels),
    occurredAt: occurredAt ?? new Date(0).toISOString(),
    isTransfer,
    suggestedType: categorySuggestsFee(categoryName)
      ? 'fee'
      : type === 'Income'
        ? 'income'
        : 'expense',
    confidence: warnings.length > 0 ? 45 : 70,
    warnings,
  };
}

function matchWalletCsvRow(state: LedgerState, row: WalletCsvParsedRow): WalletCsvParsedRow {
  const accountMatch = findAccountMatch(state.accounts, row.accountName);
  const account = accountMatch?.account;
  const category = row.isTransfer ? undefined : findCategory(state.categories, row.categoryName);
  const warnings = [...row.warnings];
  if (!account) warnings.push(`unknown account: ${row.accountName}`);
  if (accountMatch && accountMatch.kind !== 'exact') {
    warnings.push(
      `account ${accountMatch.kind} match: ${row.accountName} -> ${accountMatch.account.name}`,
    );
  }
  if (!row.isTransfer && !category) warnings.push(`unknown category: ${row.categoryName}`);
  return {
    ...row,
    accountId: accountMatch?.account.id,
    accountMatch: accountMatch
      ? {
          accountName: accountMatch.account.name,
          kind: accountMatch.kind,
          reason: accountMatch.reason,
          score: accountMatch.score,
        }
      : undefined,
    categoryId: category?.id,
    confidence: clamp(
      row.confidence + accountConfidenceBoost(accountMatch) + (category || row.isTransfer ? 10 : 0),
      0,
      95,
    ),
    warnings,
  };
}

function buildWalletCsvProposals(
  state: LedgerState,
  rows: WalletCsvParsedRow[],
): WalletCsvCandidateProposal[] {
  const transferRows = rows.filter((row) => row.isTransfer);
  const pairedKeys = new Set<string>();
  const proposals: WalletCsvCandidateProposal[] = [];

  for (const expense of transferRows.filter((row) => row.type === 'Expense')) {
    if (pairedKeys.has(rowKey(expense))) continue;
    const matches = transferRows.filter(
      (candidate) =>
        candidate.type === 'Income' &&
        !pairedKeys.has(rowKey(candidate)) &&
        transferRowsMatch(expense, candidate, state.preferences.baseCurrency),
    );
    if (matches.length > 1) {
      expense.warnings = unique([...expense.warnings, 'ambiguous transfer match']);
      for (const match of matches) {
        match.warnings = unique([...match.warnings, 'ambiguous transfer match']);
      }
      continue;
    }
    const income = matches[0];
    if (!income) continue;
    pairedKeys.add(rowKey(expense));
    pairedKeys.add(rowKey(income));
    proposals.push(buildPairedTransferProposal(state, expense, income));
  }

  for (const row of rows) {
    if (pairedKeys.has(rowKey(row))) continue;
    proposals.push(buildSingleRowProposal(state, row));
  }

  const seenRefs = new Set<string>();
  return proposals.map((proposal) => {
    const duplicateInSelection = seenRefs.has(proposal.externalRef);
    seenRefs.add(proposal.externalRef);
    const duplicate = duplicateInSelection || hasDuplicate(state, proposal);
    return {
      ...proposal,
      duplicate,
      warnings: duplicate
        ? unique([
            ...proposal.warnings,
            duplicateInSelection ? 'duplicate import row' : 'already imported',
          ])
        : proposal.warnings,
    };
  });
}

export function detectWalletCsvPlannedPayments(
  state: LedgerState,
  proposals: WalletCsvCandidateProposal[],
  options: WalletCsvPlannedPaymentDetectionOptions = {},
): WalletCsvPlannedPaymentCandidate[] {
  const groups = new Map<string, WalletCsvCandidateProposal[]>();
  for (const proposal of proposals) {
    if (!canDetectPlannedPayment(proposal)) continue;
    const key = plannedPaymentGroupKey(proposal);
    const group = groups.get(key) ?? [];
    group.push(proposal);
    groups.set(key, group);
  }

  return [...groups.values()]
    .map((group) => buildWalletCsvPlannedPaymentCandidate(state, group, options))
    .filter((candidate): candidate is WalletCsvPlannedPaymentCandidate => Boolean(candidate))
    .sort(
      (left, right) =>
        plannedPaymentActivitySort(left.activity) - plannedPaymentActivitySort(right.activity) ||
        right.confidence - left.confidence ||
        left.nextDueOn.localeCompare(right.nextDueOn) ||
        left.name.localeCompare(right.name),
    );
}

function canDetectPlannedPayment(proposal: WalletCsvCandidateProposal): boolean {
  if (proposal.amountMinor <= 0) return false;
  if (proposal.warnings.some((warning) => BLOCKING_WARNINGS.has(warning))) return false;
  if (proposal.suggestedType === 'adjustment' || proposal.suggestedType === 'refund') {
    return false;
  }
  if (proposal.suggestedType === 'transfer' && !proposal.suggestedCounterAccountId) return false;
  return true;
}

function buildWalletCsvPlannedPaymentCandidate(
  state: LedgerState,
  group: WalletCsvCandidateProposal[],
  options: WalletCsvPlannedPaymentDetectionOptions,
): WalletCsvPlannedPaymentCandidate | undefined {
  const sorted = [...group].sort((left, right) =>
    left.parsedOccurredAt.localeCompare(right.parsedOccurredAt),
  );
  const dates = unique(sorted.map((proposal) => dateOnly(proposal.parsedOccurredAt)));
  const cadence = plannedPaymentCadence(dates);
  if (!cadence) return undefined;

  const first = sorted[0];
  const last = sorted[sorted.length - 1];
  if (!first || !last) return undefined;

  const account = last.suggestedAccountId
    ? state.accounts.find((item) => item.id === last.suggestedAccountId)
    : undefined;
  const category = last.suggestedCategoryId
    ? state.categories.find((item) => item.id === last.suggestedCategoryId)
    : undefined;
  const counterAccount = last.suggestedCounterAccountId
    ? state.accounts.find((item) => item.id === last.suggestedCounterAccountId)
    : undefined;
  const identity = mostCommon(sorted.map(plannedPaymentIdentity)) ?? plannedPaymentIdentity(last);
  const text = [identity, last.sourceRow.categoryName, last.sourceRow.note, last.sourceRow.payee]
    .filter(Boolean)
    .join(' ');
  const warnings = plannedPaymentWarnings(last);
  const plannedKeywordBoost = plannedPaymentKeywordBoost(text);
  const amounts = sorted.map((proposal) => proposal.amountMinor);
  const amountMinMinor = Math.min(...amounts);
  const amountMaxMinor = Math.max(...amounts);
  const amountWarnings = plannedPaymentVariationWarnings(sorted, amountMinMinor, amountMaxMinor);
  const confidence = clamp(
    cadence.confidence +
      Math.min(14, (dates.length - PLANNED_PAYMENT_MIN_OCCURRENCES) * 3) +
      (identity ? 4 : 0) +
      plannedKeywordBoost -
      warnings.length * 6,
    0,
    96,
  );
  if (confidence < 62) return undefined;

  const baseCandidate: Omit<
    WalletCsvPlannedPaymentCandidate,
    'activity' | 'activityReason' | 'matchingRuleId' | 'matchingRuleName'
  > = {
    key: stableHash(`planned:${plannedPaymentGroupKey(last)}:${dates.join('|')}`),
    name: plannedPaymentName(last, account, counterAccount, category, identity),
    kind: plannedPaymentKind(last, text, account, counterAccount),
    type: last.suggestedType,
    accountName: account?.name ?? last.sourceRow.accountName,
    accountId: last.suggestedAccountId,
    counterAccountName: counterAccount?.name ?? last.pairedRow?.accountName,
    counterAccountId: last.suggestedCounterAccountId,
    categoryName:
      category?.name ?? (last.sourceRow.isTransfer ? undefined : last.sourceRow.categoryName),
    categoryId: last.suggestedCategoryId,
    amountMinor: last.amountMinor,
    latestAmountMinor: last.amountMinor,
    amountMinMinor,
    amountMaxMinor,
    currency: last.currency,
    frequency: cadence.frequency,
    interval: cadence.interval,
    dayOfMonth: cadence.dayOfMonth,
    startsOn: dates[0]!,
    lastSeenOn: dates[dates.length - 1]!,
    nextDueOn: nextPlannedPaymentDueOn(dates[dates.length - 1]!, cadence),
    occurrences: dates.length,
    paymentMethod: mostCommon(sorted.map((proposal) => proposal.parsedPaymentMethod ?? '')),
    tags: unique(sorted.flatMap((proposal) => proposal.parsedTags ?? [])),
    confidence,
    sourceRows: sorted.map(walletCsvPlannedPaymentRowRef),
    warnings: unique([...warnings, ...amountWarnings]),
  };

  const matchingRule = findMatchingPlannedPaymentRule(state, baseCandidate);
  if (matchingRule) {
    return {
      ...baseCandidate,
      activity: 'already_created',
      activityReason: `Already matches ${matchingRule.name}`,
      matchingRuleId: matchingRule.id,
      matchingRuleName: matchingRule.name,
    };
  }

  const activity = plannedPaymentActivity(baseCandidate, options);

  return {
    ...baseCandidate,
    activity: activity.activity,
    activityReason: activity.reason,
  };
}

function plannedPaymentGroupKey(proposal: WalletCsvCandidateProposal): string {
  const identity = plannedPaymentIdentity(proposal);
  const identityKey = normalizeName(identity);
  const categoryKey =
    proposal.suggestedCategoryId ?? normalizeName(proposal.sourceRow.categoryName);
  const paymentMethodKey = normalizeName(proposal.parsedPaymentMethod ?? '');
  if (proposal.suggestedType === 'transfer' || proposal.suggestedType === 'card_payment') {
    return [
      proposal.suggestedType,
      proposal.suggestedAccountId ?? normalizeName(proposal.sourceRow.accountName),
      proposal.suggestedCounterAccountId ?? normalizeName(proposal.pairedRow?.accountName ?? ''),
      proposal.currency,
      identityKey,
      paymentMethodKey,
    ].join('|');
  }

  const genericIdentity = isGenericPlannedPaymentIdentity(identityKey || categoryKey);
  return [
    proposal.suggestedType,
    proposal.currency,
    categoryKey,
    identityKey || categoryKey,
    paymentMethodKey,
    genericIdentity
      ? (proposal.suggestedAccountId ?? normalizeName(proposal.sourceRow.accountName))
      : '',
  ].join('|');
}

function plannedPaymentIdentity(proposal: WalletCsvCandidateProposal): string {
  if (proposal.suggestedType === 'transfer' || proposal.suggestedType === 'card_payment') {
    return (
      proposal.pairedRow?.accountName ?? proposal.parsedMerchant ?? proposal.sourceRow.categoryName
    );
  }
  return proposal.sourceRow.payee ?? proposal.parsedMerchant ?? proposal.sourceRow.categoryName;
}

function plannedPaymentName(
  proposal: WalletCsvCandidateProposal,
  account?: Account,
  counterAccount?: Account,
  category?: Category,
  identity = plannedPaymentIdentity(proposal),
): string {
  if (proposal.suggestedType === 'transfer' || proposal.suggestedType === 'card_payment') {
    const destination = counterAccount?.name ?? proposal.pairedRow?.accountName ?? 'Transfer';
    return `${account?.name ?? proposal.sourceRow.accountName} -> ${destination}`;
  }
  return identity || category?.name || proposal.sourceRow.categoryName || 'Payment';
}

function plannedPaymentActivitySort(activity: WalletCsvPlannedPaymentActivity): number {
  if (activity === 'active') return 0;
  if (activity === 'needs_review') return 1;
  if (activity === 'already_created') return 2;
  return 3;
}

function plannedPaymentVariationWarnings(
  proposals: WalletCsvCandidateProposal[],
  amountMinMinor: number,
  amountMaxMinor: number,
): string[] {
  const warnings: string[] = [];
  if (amountMinMinor !== amountMaxMinor) warnings.push('amount changed over time');
  const accounts = unique(proposals.map((proposal) => proposal.sourceRow.accountName));
  if (accounts.length > 1) warnings.push('account changed over time');
  const categories = unique(proposals.map((proposal) => proposal.sourceRow.categoryName));
  if (categories.length > 1) warnings.push('category changed over time');
  return warnings;
}

function plannedPaymentActivity(
  candidate: Omit<
    WalletCsvPlannedPaymentCandidate,
    'activity' | 'activityReason' | 'matchingRuleId' | 'matchingRuleName'
  >,
  options: WalletCsvPlannedPaymentDetectionOptions,
): { activity: WalletCsvPlannedPaymentActivity; reason: string } {
  const now = startOfUtcDay(options.now ?? new Date());
  const lastSeen = parseDateOnlyUtc(candidate.lastSeenOn);
  const nextDue = parseDateOnlyUtc(candidate.nextDueOn);
  if (!lastSeen || !nextDue) {
    return { activity: 'needs_review', reason: 'Could not verify last seen date' };
  }

  const lowFrequency = candidate.frequency === 'yearly' || candidate.interval >= 3;
  const activeWindowMonths = lowFrequency
    ? (options.activeLowFrequencyWindowMonths ?? 12)
    : (options.activeRecentWindowMonths ?? 6);
  const activeCutoff = addUtcMonthsCopy(now, -activeWindowMonths);
  if (lastSeen >= activeCutoff) {
    return {
      activity: 'active',
      reason: `Last seen within ${activeWindowMonths} months`,
    };
  }

  if (lowFrequency) {
    const reviewStart = addUtcMonthsCopy(now, -6);
    const reviewEnd = addUtcMonthsCopy(now, 12);
    if (nextDue >= reviewStart && nextDue <= reviewEnd) {
      return {
        activity: 'needs_review',
        reason: 'Low-frequency plan may have been skipped recently',
      };
    }
  }

  return {
    activity: 'historical',
    reason: `Last seen outside ${activeWindowMonths}-month active window`,
  };
}

function findMatchingPlannedPaymentRule(
  state: LedgerState,
  candidate: Omit<
    WalletCsvPlannedPaymentCandidate,
    'activity' | 'activityReason' | 'matchingRuleId' | 'matchingRuleName'
  >,
): FutureGenerationRule | undefined {
  const candidateName = normalizeName(candidate.name);
  return (state.preferences.futureGenerationRules ?? []).find((rule) => {
    if (rule.frequency !== candidate.frequency || rule.interval !== candidate.interval)
      return false;
    if (plannedPaymentRuleKind(rule) !== candidate.kind) return false;
    if (candidate.dayOfMonth && rule.dayOfMonth) {
      if (Math.abs(candidate.dayOfMonth - rule.dayOfMonth) > 3) return false;
    }
    if (candidate.counterAccountId && rule.counterAccountId !== candidate.counterAccountId) {
      return false;
    }
    if (candidate.categoryId && rule.categoryId && candidate.categoryId !== rule.categoryId) {
      return false;
    }
    const ruleName = normalizeName(rule.name);
    return Boolean(
      ruleName &&
      candidateName &&
      (ruleName === candidateName ||
        ruleName.includes(candidateName) ||
        candidateName.includes(ruleName)),
    );
  });
}

function plannedPaymentRuleKind(rule: FutureGenerationRule): PlannedPaymentKind {
  const rawKind = rule.kind as string | undefined;
  if (
    rawKind === 'income' ||
    rawKind === 'expense' ||
    rawKind === 'transfer' ||
    rawKind === 'adjustment'
  ) {
    return rawKind;
  }
  if (rawKind === 'card_payment' || rawKind === 'loan_emi' || rawKind === 'savings_transfer') {
    return 'transfer';
  }
  if (rule.type === 'income' || rule.type === 'refund' || rule.type === 'cashback') {
    return 'income';
  }
  if (rule.type === 'transfer' || rule.type === 'card_payment' || rule.type === 'loan_repayment') {
    return 'transfer';
  }
  if (rule.type === 'adjustment') return 'adjustment';
  return 'expense';
}

function isGenericPlannedPaymentIdentity(normalized: string): boolean {
  return new Set([
    'bill',
    'bills',
    'cashback',
    'emi',
    'expense',
    'income',
    'lending',
    'loan',
    'loans',
    'maintenance',
    'payment',
    'salary',
  ]).has(normalized);
}

function plannedPaymentKind(
  proposal: WalletCsvCandidateProposal,
  text: string,
  account?: Account,
  counterAccount?: Account,
): PlannedPaymentKind {
  const normalized = normalizeName(text);
  if (proposal.suggestedType === 'card_payment') return 'transfer';
  if (
    proposal.suggestedType === 'loan_repayment' ||
    account?.type === 'loan' ||
    counterAccount?.type === 'loan' ||
    normalized.includes('loan') ||
    normalized.includes('emi')
  ) {
    return 'transfer';
  }
  if (proposal.suggestedType === 'transfer') {
    return 'transfer';
  }
  if (proposal.suggestedType === 'income') return 'income';
  if (proposal.suggestedType === 'adjustment') return 'adjustment';
  if (proposal.suggestedType === 'expense' || proposal.suggestedType === 'fee') return 'expense';
  return 'expense';
}

function plannedPaymentWarnings(proposal: WalletCsvCandidateProposal): string[] {
  const warnings: string[] = [];
  if (!proposal.suggestedAccountId)
    warnings.push(`unknown account: ${proposal.sourceRow.accountName}`);
  if (!proposal.sourceRow.isTransfer && !proposal.suggestedCategoryId) {
    warnings.push(`unknown category: ${proposal.sourceRow.categoryName}`);
  }
  if (
    (proposal.suggestedType === 'transfer' || proposal.suggestedType === 'card_payment') &&
    !proposal.suggestedCounterAccountId
  ) {
    warnings.push('missing destination account');
  }
  return warnings;
}

function plannedPaymentKeywordBoost(text: string): number {
  const normalized = normalizeName(text);
  if (normalized.includes('emi') || normalized.includes('loan')) return 10;
  if (recurringSubscriptionKeyword(normalized)) return 8;
  if (plannedBillKeyword(normalized)) return 6;
  if (normalized.includes('salary') || normalized.includes('rent')) return 5;
  return 0;
}

function recurringSubscriptionKeyword(normalized: string): boolean {
  return [
    'netflix',
    'spotify',
    'prime',
    'hotstar',
    'youtube',
    'icloud',
    'googleone',
    'subscription',
  ].some((keyword) => normalized.includes(keyword));
}

function plannedBillKeyword(normalized: string): boolean {
  return [
    'bill',
    'rent',
    'insurance',
    'electricity',
    'broadband',
    'internet',
    'mobile',
    'recharge',
    'maintenance',
  ].some((keyword) => normalized.includes(keyword));
}

type PlannedPaymentCadence = {
  frequency: FutureGenerationFrequency;
  interval: number;
  dayOfMonth?: number;
  confidence: number;
};

function plannedPaymentCadence(dates: string[]): PlannedPaymentCadence | undefined {
  if (dates.length < PLANNED_PAYMENT_MIN_OCCURRENCES) return undefined;
  const parsed = dates
    .map((date) => new Date(`${date}T00:00:00.000Z`))
    .filter((date) => !Number.isNaN(date.getTime()))
    .sort((left, right) => left.getTime() - right.getTime());
  if (parsed.length < PLANNED_PAYMENT_MIN_OCCURRENCES) return undefined;

  const dayIntervals = consecutiveIntervals(parsed, daysBetween);
  const monthIntervals = consecutiveIntervals(parsed, monthDifference).filter((value) => value > 0);
  if (
    dayIntervals.length >= 3 &&
    everyNear(dayIntervals, 7, 2) &&
    parsed.length >= PLANNED_PAYMENT_MIN_OCCURRENCES + 1
  ) {
    return { frequency: 'weekly', interval: 1, confidence: 73 };
  }

  const days = parsed.map((date) => date.getUTCDate());
  const dayOfMonth = Math.round(median(days));
  const sameDayRatio = days.filter((day) => Math.abs(day - dayOfMonth) <= 3).length / days.length;
  if (
    monthIntervals.length >= 2 &&
    monthIntervals.every((interval) => interval >= 1 && interval <= 3) &&
    sameDayRatio >= 0.7
  ) {
    return {
      frequency: 'monthly',
      interval: Math.max(1, Math.round(median(monthIntervals))),
      dayOfMonth,
      confidence: sameDayRatio >= 0.9 ? 78 : 70,
    };
  }

  if (dayIntervals.length >= 2 && everyNear(dayIntervals, 365, 35)) {
    return { frequency: 'yearly', interval: 1, confidence: 68, dayOfMonth };
  }

  return undefined;
}

function walletCsvPlannedPaymentRowRef(
  proposal: WalletCsvCandidateProposal,
): WalletCsvPlannedPaymentRowRef {
  return {
    fileName: proposal.sourceRow.fileName,
    rowNumber: proposal.sourceRow.rowNumber,
    pairedRowNumber: proposal.pairedRow?.rowNumber,
    occurredOn: dateOnly(proposal.parsedOccurredAt),
    accountName: proposal.sourceRow.accountName,
    counterAccountName: proposal.pairedRow?.accountName,
    categoryName: proposal.sourceRow.isTransfer ? undefined : proposal.sourceRow.categoryName,
    payee: proposal.sourceRow.payee,
    note: proposal.sourceRow.note,
    amountMinor: proposal.amountMinor,
    currency: proposal.currency,
  };
}

function nextPlannedPaymentDueOn(lastSeenOn: string, cadence: PlannedPaymentCadence): string {
  const date = new Date(`${lastSeenOn}T00:00:00.000Z`);
  if (Number.isNaN(date.getTime())) return lastSeenOn;
  if (cadence.frequency === 'weekly') date.setUTCDate(date.getUTCDate() + 7 * cadence.interval);
  else if (cadence.frequency === 'monthly')
    addUtcMonths(date, cadence.interval, cadence.dayOfMonth);
  else if (cadence.frequency === 'yearly')
    date.setUTCFullYear(date.getUTCFullYear() + cadence.interval);
  else date.setUTCDate(date.getUTCDate() + cadence.interval);
  return date.toISOString().slice(0, 10);
}

function addUtcMonths(date: Date, months: number, preferredDay?: number): void {
  const targetMonth = date.getUTCMonth() + months;
  const targetYear = date.getUTCFullYear() + Math.floor(targetMonth / 12);
  const normalizedMonth = ((targetMonth % 12) + 12) % 12;
  const day = preferredDay ?? date.getUTCDate();
  const maxDay = daysInUtcMonth(targetYear, normalizedMonth);
  date.setUTCFullYear(targetYear, normalizedMonth, Math.min(day, maxDay));
}

function daysInUtcMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
}

function dateOnly(value: string): string {
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? value.slice(0, 10) : parsed.toISOString().slice(0, 10);
}

function parseDateOnlyUtc(value: string): Date | undefined {
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return Number.isNaN(parsed.getTime()) ? undefined : parsed;
}

function startOfUtcDay(value: Date): Date {
  return new Date(Date.UTC(value.getUTCFullYear(), value.getUTCMonth(), value.getUTCDate()));
}

function addUtcMonthsCopy(value: Date, months: number): Date {
  const copy = new Date(value.getTime());
  addUtcMonths(copy, months, copy.getUTCDate());
  return copy;
}

function consecutiveIntervals<T>(items: T[], distance: (left: T, right: T) => number): number[] {
  const intervals: number[] = [];
  for (let index = 1; index < items.length; index += 1) {
    intervals.push(distance(items[index - 1]!, items[index]!));
  }
  return intervals;
}

function daysBetween(left: Date, right: Date): number {
  const msPerDay = 24 * 60 * 60 * 1000;
  return Math.round((right.getTime() - left.getTime()) / msPerDay);
}

function monthDifference(left: Date, right: Date): number {
  return (
    (right.getUTCFullYear() - left.getUTCFullYear()) * 12 + right.getUTCMonth() - left.getUTCMonth()
  );
}

function everyNear(values: number[], expected: number, tolerance: number): boolean {
  return values.every((value) => Math.abs(value - expected) <= tolerance);
}

function median(values: number[]): number {
  const sorted = [...values].sort((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  if (sorted.length === 0) return 0;
  if (sorted.length % 2 === 1) return sorted[middle]!;
  return (sorted[middle - 1]! + sorted[middle]!) / 2;
}

function buildPairedTransferProposal(
  state: LedgerState,
  sourceRow: WalletCsvParsedRow,
  destinationRow: WalletCsvParsedRow,
): WalletCsvCandidateProposal {
  const sourceAccount = sourceRow.accountId
    ? state.accounts.find((account) => account.id === sourceRow.accountId)
    : undefined;
  const destinationAccount = destinationRow.accountId
    ? state.accounts.find((account) => account.id === destinationRow.accountId)
    : undefined;
  const type: TransactionType =
    destinationAccount?.type === 'credit_card' ? 'card_payment' : 'transfer';
  const counterAmount = parsedCounterAmount(sourceRow, destinationRow);
  const parsedFxRate = referenceFxRate(sourceRow, state.preferences.baseCurrency);
  const semanticKey = stableHash(
    `transfer:${sourceRow.semanticKey}->${destinationRow.semanticKey}`,
  );
  const rawHash = stableHash(`transfer:${sourceRow.rawHash}:${destinationRow.rawHash}`);
  const warnings = [...sourceRow.warnings, ...destinationRow.warnings, 'paired transfer'];
  if (counterAmount) warnings.push('paired cross-currency transfer');
  if (!sourceAccount || !destinationAccount) warnings.push('transfer needs account review');
  if (sourceAccount?.type === 'credit_card' && destinationAccount?.type !== 'credit_card') {
    warnings.push('credit-card source transfer may be a cash advance');
  }
  return {
    key: semanticKey,
    semanticKey,
    externalRef: `wallet-csv:${semanticKey}`,
    rawHash,
    fileNames: unique([sourceRow.fileName, destinationRow.fileName]),
    rowNumbers: [sourceRow.rowNumber, destinationRow.rowNumber],
    sourceRow,
    pairedRow: destinationRow,
    amountMinor: sourceRow.amountMinor,
    currency: sourceRow.currency,
    suggestedType: type,
    suggestedAccountId: sourceRow.accountId,
    suggestedCounterAccountId: destinationRow.accountId,
    parsedFxRate,
    parsedMerchant: destinationRow.accountName,
    parsedNotes: mergeNotes(sourceRow, destinationRow),
    parsedPaymentMethod: sourceRow.paymentMethod ?? destinationRow.paymentMethod,
    parsedTags: unique(['Wallet CSV', 'Transfer', ...sourceRow.labels, ...destinationRow.labels]),
    parsedCounterAmountMinor: counterAmount?.amountMinor,
    parsedCounterCurrency: counterAmount?.currency,
    parsedCounterFxRate: counterAmount?.fxRate,
    parsedOccurredAt: sourceRow.occurredAt,
    confidence: clamp(Math.min(sourceRow.confidence, destinationRow.confidence) + 5, 0, 98),
    duplicate: false,
    warnings: unique(warnings),
  };
}

function buildSingleRowProposal(
  state: LedgerState,
  row: WalletCsvParsedRow,
): WalletCsvCandidateProposal {
  const rawHash = stableHash(`row:${row.rawHash}`);
  const semanticKey = row.semanticKey;
  const warnings = [...row.warnings];
  if (row.isTransfer) warnings.push('unpaired transfer needs destination/source review');
  const category = row.categoryId
    ? state.categories.find((item) => item.id === row.categoryId)
    : undefined;
  const account = row.accountId
    ? state.accounts.find((item) => item.id === row.accountId)
    : undefined;
  const amount = walletCsvPostedAmount(state, row, account);
  return {
    key: semanticKey,
    semanticKey,
    externalRef: `wallet-csv:${semanticKey}`,
    rawHash,
    fileNames: [row.fileName],
    rowNumbers: [row.rowNumber],
    sourceRow: row,
    amountMinor: amount.amountMinor,
    currency: amount.currency,
    suggestedType: row.isTransfer ? 'transfer' : row.suggestedType,
    suggestedAccountId: row.accountId,
    suggestedCategoryId: row.isTransfer ? undefined : row.categoryId,
    parsedFxRate: amount.parsedFxRate,
    parsedOriginalAmountMinor: amount.parsedOriginalAmountMinor,
    parsedOriginalCurrency: amount.parsedOriginalCurrency,
    parsedOriginalFxRate: amount.parsedOriginalFxRate,
    parsedMerchant: row.payee || category?.name || row.categoryName,
    parsedNotes: mergeNotes(row),
    parsedPaymentMethod: row.paymentMethod,
    parsedTags: unique(['Wallet CSV', ...row.labels]),
    parsedOccurredAt: row.occurredAt,
    confidence: row.isTransfer ? Math.min(row.confidence, 55) : row.confidence,
    duplicate: false,
    warnings: unique(warnings),
  };
}

function hasDuplicate(state: LedgerState, proposal: WalletCsvCandidateProposal): boolean {
  return (
    state.transactions.some((transaction) => transaction.externalRef === proposal.externalRef) ||
    state.captureCandidates.some(
      (candidate) =>
        candidate.rawHash === proposal.rawHash || candidate.externalRef === proposal.externalRef,
    ) ||
    state.transactions.some((transaction) => transactionLooksLikeProposal(transaction, proposal))
  );
}

function transactionLooksLikeProposal(
  transaction: {
    accountId: UUID;
    counterAccountId?: UUID;
    type: TransactionType;
    amount: { amountMinor: number; currency: string };
    categoryId?: UUID;
    occurredAt: string;
  },
  proposal: WalletCsvCandidateProposal,
): boolean {
  if (!proposal.suggestedAccountId) return false;
  if (transaction.accountId !== proposal.suggestedAccountId) return false;
  if (transaction.type !== proposal.suggestedType) return false;
  if (transaction.amount.amountMinor !== proposal.amountMinor) return false;
  if (transaction.amount.currency !== proposal.currency) return false;
  if (!timestampsNear(transaction.occurredAt, proposal.parsedOccurredAt, 60000)) return false;
  if (
    proposal.suggestedCounterAccountId &&
    transaction.counterAccountId !== proposal.suggestedCounterAccountId
  )
    return false;
  if (proposal.suggestedCategoryId && transaction.categoryId !== proposal.suggestedCategoryId)
    return false;
  return true;
}

function parseCsvLine(line: string): string[] {
  const cells: string[] = [];
  let value = '';
  let quoted = false;
  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    const next = line[index + 1];
    if (char === '"') {
      if (quoted && next === '"') {
        value += '"';
        index += 1;
      } else {
        quoted = !quoted;
      }
      continue;
    }
    if (char === ';' && !quoted) {
      cells.push(value);
      value = '';
      continue;
    }
    value += char;
  }
  cells.push(value);
  return cells.map((cell) => cell.trim());
}

function normalizeCsvType(type: string): WalletCsvType | undefined {
  const normalized = type.trim().toLowerCase();
  if (normalized === 'expense') return 'Expense';
  if (normalized === 'income') return 'Income';
  return undefined;
}

function parseOptionalAmount(value: string): number | undefined {
  const trimmed = value.replace(/,/g, '').trim();
  if (!trimmed) return undefined;
  const parsed = Number(trimmed);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : undefined;
}

function normalizeDate(value: string): string | undefined {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return undefined;
  return parsed.toISOString();
}

function timestampSecond(value?: string): string {
  if (!value) return 'invalid-date';
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return 'invalid-date';
  parsed.setMilliseconds(0);
  return parsed.toISOString();
}

function timestampsNear(left: string, right: string, toleranceMs: number): boolean {
  const leftMs = new Date(left).getTime();
  const rightMs = new Date(right).getTime();
  if (Number.isNaN(leftMs) || Number.isNaN(rightMs)) return false;
  return Math.abs(leftMs - rightMs) <= toleranceMs;
}

function transferRowsMatch(
  expense: WalletCsvParsedRow,
  income: WalletCsvParsedRow,
  baseCurrency: string,
): boolean {
  if (!timestampsNear(income.occurredAt, expense.occurredAt, 5000)) return false;
  if (income.currency === expense.currency && income.amountMinor === expense.amountMinor) {
    return true;
  }
  const expenseRefMinor = referenceAmountMinor(expense, baseCurrency);
  const incomeRefMinor = referenceAmountMinor(income, baseCurrency);
  return expenseRefMinor !== undefined && expenseRefMinor === incomeRefMinor;
}

function referenceAmountMinor(row: WalletCsvParsedRow, baseCurrency: string): number | undefined {
  return row.refCurrencyAmount === undefined
    ? undefined
    : toMinor(row.refCurrencyAmount, baseCurrency);
}

function referenceFxRate(row: WalletCsvParsedRow, baseCurrency: string): number | undefined {
  if (
    row.currency === baseCurrency ||
    row.refCurrencyAmount === undefined ||
    row.amountMinor <= 0
  ) {
    return undefined;
  }
  const amount = fromMinor(row.amountMinor, row.currency);
  if (amount <= 0) return undefined;
  return row.refCurrencyAmount / amount;
}

function walletCsvPostedAmount(
  state: LedgerState,
  row: WalletCsvParsedRow,
  account?: Account,
): {
  amountMinor: number;
  currency: string;
  parsedFxRate?: number;
  parsedOriginalAmountMinor?: number;
  parsedOriginalCurrency?: string;
  parsedOriginalFxRate?: number;
} {
  const baseCurrency = state.preferences.baseCurrency;
  const referenceFx = referenceFxRate(row, baseCurrency);
  const accountCurrency = account?.currency;
  if (!referenceFx || !accountCurrency)
    return { amountMinor: row.amountMinor, currency: row.currency };

  if (accountCurrency === row.currency) {
    return {
      amountMinor: row.amountMinor,
      currency: row.currency,
      parsedFxRate: referenceFx,
    };
  }

  if (accountCurrency === baseCurrency) {
    return {
      amountMinor: referenceAmountMinor(row, baseCurrency) ?? row.amountMinor,
      currency: accountCurrency,
      parsedOriginalAmountMinor: row.amountMinor,
      parsedOriginalCurrency: row.currency,
      parsedOriginalFxRate: referenceFx,
    };
  }

  return { amountMinor: row.amountMinor, currency: row.currency };
}

function parsedCounterAmount(
  sourceRow: WalletCsvParsedRow,
  destinationRow: WalletCsvParsedRow,
): { amountMinor: number; currency: string; fxRate: number } | undefined {
  if (sourceRow.currency === destinationRow.currency) return undefined;
  if (sourceRow.amountMinor <= 0 || destinationRow.amountMinor <= 0) return undefined;
  const sourceAmount = fromMinor(sourceRow.amountMinor, sourceRow.currency);
  const destinationAmount = fromMinor(destinationRow.amountMinor, destinationRow.currency);
  if (sourceAmount <= 0 || destinationAmount <= 0) return undefined;
  return {
    amountMinor: destinationRow.amountMinor,
    currency: destinationRow.currency,
    fxRate: destinationAmount / sourceAmount,
  };
}

function clean(value: string): string | undefined {
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function splitLabels(labels: string): string[] {
  return labels
    .split(/[|,]/)
    .map((label) => label.trim())
    .filter(Boolean);
}

function findAccount(accounts: Account[], name: string): Account | undefined {
  return findAccountMatch(accounts, name)?.account;
}

type AccountMatchResult = {
  account: Account;
  kind: WalletCsvAccountMatch['kind'];
  reason: string;
  score: number;
};

function findAccountMatch(accounts: Account[], name: string): AccountMatchResult | undefined {
  const normalized = normalizeName(name);
  if (!normalized) return undefined;

  const exact = accounts.find((account) => normalizeName(account.name) === normalized);
  if (exact) {
    return { account: exact, kind: 'exact', reason: 'same normalized account name', score: 1 };
  }

  const alias = ACCOUNT_ALIASES[normalized];
  if (alias) {
    const aliasMatch = accounts.find((account) => normalizeName(account.name) === alias);
    if (aliasMatch) {
      return {
        account: aliasMatch,
        kind: 'alias',
        reason: `alias ${normalized} -> ${alias}`,
        score: 0.96,
      };
    }
  }

  const candidates = accounts
    .map((account) => ({ account, score: accountNameSimilarity(name, account.name) }))
    .filter((candidate) => candidate.score >= 0.86)
    .sort((left, right) => right.score - left.score);
  const best = candidates[0];
  if (!best) return undefined;
  const next = candidates[1];
  if (next && best.score - next.score < 0.07) return undefined;
  return {
    account: best.account,
    kind: 'similar',
    reason: `name similarity ${Math.round(best.score * 100)}%`,
    score: best.score,
  };
}

function accountConfidenceBoost(match?: AccountMatchResult): number {
  if (!match) return 0;
  if (match.kind === 'exact') return 15;
  if (match.kind === 'alias') return 12;
  return 8;
}

function findCategory(
  categories: Category[],
  name: string,
  kind?: Category['kind'],
): Category | undefined {
  return findCategoryMatch(categories, name, kind)?.category;
}

type CategoryMatchResult = {
  category: Category;
  kind: 'exact' | 'taxonomy' | 'similar';
  reason: string;
  score: number;
};

function findCategoryMatch(
  categories: Category[],
  name: string,
  kind?: Category['kind'],
): CategoryMatchResult | undefined {
  const normalized = normalizeName(name);
  if (!normalized) return undefined;

  const eligible = categories.filter((category) =>
    kind ? categoryAppliesToKind(category, kind) : !category.isArchived,
  );
  const exact = eligible.find((category) => normalizeName(category.name) === normalized);
  if (exact) return { category: exact, kind: 'exact', reason: 'same category name', score: 1 };

  const template = taxonomyTemplateForCategoryName(name, kind);
  if (template) {
    const taxonomyMatch = eligible.find(
      (category) => normalizeName(category.name) === normalizeName(template.name),
    );
    if (taxonomyMatch) {
      return {
        category: taxonomyMatch,
        kind: 'taxonomy',
        reason: `default taxonomy match: ${name} -> ${template.name}`,
        score: 0.96,
      };
    }
  }

  const candidates = eligible
    .map((category) => ({ category, score: categoryNameSimilarity(name, category.name) }))
    .filter((candidate) => candidate.score >= 0.78)
    .sort((left, right) => right.score - left.score);
  const crossKind = kind ? findCrossKindCategoryMatch(categories, name, kind) : undefined;
  const best = candidates[0];
  if (!best) return crossKind;
  const next = candidates[1];
  if (next && best.score === next.score) return crossKind;
  if (next && best.score - next.score < 0.08 && best.score < 0.92) return crossKind;
  return {
    category: best.category,
    kind: 'similar',
    reason: `category similarity ${Math.round(best.score * 100)}%`,
    score: best.score,
  };
}

function findCrossKindCategoryMatch(
  categories: Category[],
  name: string,
  kind: Category['kind'],
): CategoryMatchResult | undefined {
  const normalized = normalizeName(name);
  const eligible = categories.filter(
    (category) => !category.isArchived && !categoryAppliesToKind(category, kind),
  );

  const exactMatches = eligible.filter((category) => normalizeName(category.name) === normalized);
  const exactMatch = exactMatches[0];
  if (exactMatches.length === 1 && exactMatch) {
    return {
      category: exactMatch,
      kind: 'exact',
      reason: 'same category name across Wallet CSV type',
      score: 0.94,
    };
  }

  const taxonomyMatches: Category[] = [];
  for (const template of taxonomyTemplatesForCategoryName(name)) {
    const match = eligible.find(
      (category) => normalizeName(category.name) === normalizeName(template.name),
    );
    if (match && !taxonomyMatches.some((category) => category.id === match.id)) {
      taxonomyMatches.push(match);
    }
  }

  const taxonomyMatch = taxonomyMatches[0];
  if (taxonomyMatches.length === 1 && taxonomyMatch) {
    return {
      category: taxonomyMatch,
      kind: 'taxonomy',
      reason: `default taxonomy match across Wallet CSV type: ${name} -> ${taxonomyMatch.name}`,
      score: 0.9,
    };
  }

  return undefined;
}

function categoryAppliesToKind(category: Category, kind: Category['kind']): boolean {
  return !category.isArchived && (category.kind === kind || category.kind === 'system');
}

function taxonomyTemplateForCategoryName(name: string, kind?: Category['kind']) {
  return taxonomyTemplatesForCategoryName(name, kind)[0];
}

function taxonomyTemplatesForCategoryName(name: string, kind?: Category['kind']) {
  const normalized = normalizeName(name);
  return DEFAULT_CATEGORY_TAXONOMY.filter(
    (template) =>
      (kind === undefined || template.kind === kind || template.kind === 'system') &&
      (normalizeName(template.name) === normalized ||
        (template.aliases ?? []).some((alias) => normalizeName(alias) === normalized)),
  );
}

function categoryKindFor(row: WalletCsvParsedRow): Category['kind'] {
  return row.type === 'Income' ? 'income' : 'expense';
}

function categorySuggestsFee(category: string): boolean {
  const normalized = normalizeName(category);
  return normalized.includes('charge') || normalized.includes('fee');
}

function normalizeName(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]/g, '');
}

function accountNameSimilarity(left: string, right: string): number {
  const leftNormalized = normalizeName(left);
  const rightNormalized = normalizeName(right);
  if (!leftNormalized || !rightNormalized) return 0;
  if (
    leftNormalized.length >= 6 &&
    rightNormalized.includes(leftNormalized) &&
    rightNormalized.length - leftNormalized.length <= 16
  ) {
    return 0.9;
  }
  if (
    rightNormalized.length >= 6 &&
    leftNormalized.includes(rightNormalized) &&
    leftNormalized.length - rightNormalized.length <= 16
  ) {
    return 0.9;
  }

  const leftTokens = meaningfulAccountTokens(left);
  const rightTokens = meaningfulAccountTokens(right);
  const shared = leftTokens.filter((token) => rightTokens.includes(token));
  if (shared.length >= 2) {
    const coverage = shared.length / Math.max(leftTokens.length, rightTokens.length, 1);
    return Math.max(0.86, 0.78 + coverage * 0.18);
  }

  const distance = levenshteinDistance(leftNormalized, rightNormalized);
  const similarity = 1 - distance / Math.max(leftNormalized.length, rightNormalized.length, 1);
  return similarity >= 0.86 ? similarity : 0;
}

function categoryNameSimilarity(left: string, right: string): number {
  const leftNormalized = normalizeName(left);
  const rightNormalized = normalizeName(right);
  if (!leftNormalized || !rightNormalized) return 0;

  const leftIsGeneric = GENERIC_CATEGORY_TOKENS.has(leftNormalized);
  const rightIsGeneric = GENERIC_CATEGORY_TOKENS.has(rightNormalized);
  if (!leftIsGeneric && !rightIsGeneric) {
    if (
      leftNormalized.length >= 5 &&
      rightNormalized.includes(leftNormalized) &&
      rightNormalized.length - leftNormalized.length <= 18
    ) {
      return rightNormalized.startsWith(leftNormalized) ? 0.92 : 0.9;
    }
    if (
      rightNormalized.length >= 5 &&
      leftNormalized.includes(rightNormalized) &&
      leftNormalized.length - rightNormalized.length <= 18
    ) {
      return leftNormalized.startsWith(rightNormalized) ? 0.92 : 0.9;
    }
  }

  const leftTokens = meaningfulCategoryTokens(left);
  const rightTokens = meaningfulCategoryTokens(right);
  const shared = leftTokens.filter((token) => rightTokens.includes(token));
  if (shared.length > 0) {
    const coverage = shared.length / Math.max(leftTokens.length, rightTokens.length, 1);
    const strongToken = shared.some((token) => token.length >= 5);
    if (coverage >= 0.5 || strongToken) return Math.max(0.8, 0.72 + coverage * 0.2);
  }

  const distance = levenshteinDistance(leftNormalized, rightNormalized);
  const similarity = 1 - distance / Math.max(leftNormalized.length, rightNormalized.length, 1);
  return similarity >= 0.82 ? similarity : 0;
}

function meaningfulCategoryTokens(value: string): string[] {
  return value
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .map((token) => token.trim())
    .filter((token) => token.length > 1 && !GENERIC_CATEGORY_TOKENS.has(token));
}

function meaningfulAccountTokens(value: string): string[] {
  return value
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .map((token) => token.trim())
    .filter((token) => token.length > 1 && !GENERIC_ACCOUNT_TOKENS.has(token));
}

function levenshteinDistance(left: string, right: string): number {
  const previous = Array.from({ length: right.length + 1 }, (_, index) => index);
  for (let leftIndex = 0; leftIndex < left.length; leftIndex += 1) {
    const current = [leftIndex + 1];
    for (let rightIndex = 0; rightIndex < right.length; rightIndex += 1) {
      current[rightIndex + 1] = Math.min(
        current[rightIndex]! + 1,
        previous[rightIndex + 1]! + 1,
        previous[rightIndex]! + (left[leftIndex] === right[rightIndex] ? 0 : 1),
      );
    }
    previous.splice(0, previous.length, ...current);
  }
  return previous[right.length] ?? 0;
}

function walletCsvProposalRows(proposal: WalletCsvCandidateProposal): WalletCsvParsedRow[] {
  return proposal.pairedRow ? [proposal.sourceRow, proposal.pairedRow] : [proposal.sourceRow];
}

function walletCsvRowRef(row: WalletCsvParsedRow) {
  return {
    fileName: row.fileName,
    rowNumber: row.rowNumber,
    accountName: row.accountName,
    matchedAccountName: row.accountMatch?.accountName,
    accountMatchKind: row.accountMatch?.kind,
    categoryName: row.categoryName,
    currency: row.currency,
    amount: row.raw.amount,
    refCurrencyAmount: row.refCurrencyAmount,
    type: row.type,
    payee: row.payee,
    note: row.note,
  };
}

function semanticRowKey(input: {
  account: string;
  category: string;
  currency: string;
  amountMinor: number;
  type: string;
  isTransfer: boolean;
  occurredAt?: string;
  payee: string;
}): string {
  return stableHash(
    [
      normalizeName(input.account),
      normalizeName(input.category),
      input.currency.toUpperCase(),
      String(input.amountMinor),
      normalizeName(input.type),
      input.isTransfer ? 'transfer' : 'record',
      timestampSecond(input.occurredAt),
      normalizeName(input.payee),
    ].join('|'),
  );
}

function rowKey(row: WalletCsvParsedRow): string {
  return `${row.fileName}:${row.rowNumber}`;
}

function mergeNotes(...rows: WalletCsvParsedRow[]): string | undefined {
  const parts = rows
    .flatMap((row) => [row.note, row.payee ? `Payee: ${row.payee}` : undefined])
    .filter(Boolean);
  return parts.length > 0 ? unique(parts as string[]).join('\n') : undefined;
}

function summarizeFiles(rows: WalletCsvParsedRow[]): WalletCsvFileSummary[] {
  return unique(rows.map((row) => row.fileName))
    .sort((left, right) => left.localeCompare(right))
    .map((fileName) => {
      const fileRows = rows.filter((row) => row.fileName === fileName);
      return {
        fileName,
        rowCount: fileRows.length,
        transferRows: fileRows.filter((row) => row.isTransfer).length,
        invalidRows: fileRows.filter((row) =>
          row.warnings.some((warning) => BLOCKING_WARNINGS.has(warning)),
        ).length,
        dateRange: dateRangeForRows(fileRows),
        accounts: uniqueWalletCsvFieldValues(fileRows, 'accountName'),
        categories: uniqueWalletCsvFieldValues(fileRows, 'categoryName'),
        currencies: uniqueWalletCsvFieldValues(fileRows, 'currency'),
        paymentTypes: uniqueWalletCsvFieldValues(fileRows, 'paymentMethod'),
      };
    });
}

function dateRangeForRows(rows: WalletCsvParsedRow[]): WalletCsvDateRange {
  const times = rows
    .filter((row) => !row.warnings.includes('invalid date'))
    .map((row) => new Date(row.occurredAt).getTime())
    .filter((time) => !Number.isNaN(time));
  if (times.length === 0) return {};
  return {
    start: new Date(Math.min(...times)).toISOString(),
    end: new Date(Math.max(...times)).toISOString(),
  };
}

function countValues(values: Array<string | undefined>): WalletCsvValueSummary[] {
  const counts = new Map<string, number>();
  for (const value of values) {
    const label = value?.trim();
    if (!label) continue;
    counts.set(label, (counts.get(label) ?? 0) + 1);
  }
  return [...counts.entries()]
    .map(([value, count]) => ({ value, count }))
    .sort((left, right) => right.count - left.count || left.value.localeCompare(right.value));
}

function mostCommon(values: string[]): string | undefined {
  return countValues(values)[0]?.value;
}

export function inferWalletCsvAccountType(name: string): AccountType {
  const normalized = normalizeName(name);
  if (normalized.includes('creditcard') || normalized.includes('credit')) return 'credit_card';
  if (
    normalized.includes('onecard') ||
    normalized.includes('americanexpress') ||
    normalized.includes('amex') ||
    normalized.includes('diners') ||
    normalized.endsWith('cc') ||
    (normalized.endsWith('card') && !normalized.includes('debit'))
  ) {
    return 'credit_card';
  }
  if (normalized.includes('debitcard') || normalized.includes('debit')) return 'debit_card';
  if (normalized.includes('forex') || normalized.includes('prepaid')) return 'prepaid';
  if (
    normalized.includes('wallet') ||
    normalized.includes('upilite') ||
    normalized.includes('paytm') ||
    normalized.includes('phonepe') ||
    normalized.includes('gpay') ||
    normalized.includes('googlepay') ||
    normalized === 'amazonpay'
  ) {
    return 'wallet';
  }
  if (normalized.includes('loan')) return 'loan';
  if (
    normalized.includes('mutualfund') ||
    normalized.includes('demat') ||
    normalized.includes('stock')
  ) {
    return 'investment';
  }
  if (normalized.includes('cash')) return 'cash';
  return 'bank';
}

function inferWalletCsvAccountIcon(name: string): string {
  const type = inferWalletCsvAccountType(name);
  if (type === 'credit_card') return 'credit-card-outline';
  if (type === 'wallet') return 'wallet-outline';
  if (type === 'prepaid') return 'card-bulleted-outline';
  if (type === 'loan') return 'bank-transfer-out';
  if (type === 'cash') return 'cash';
  return 'bank-outline';
}

function inferWalletCsvAccountColor(name: string): string {
  const normalized = normalizeName(name);
  if (normalized.includes('hdfc')) return '#004C8F';
  if (normalized.includes('icici')) return '#B45309';
  if (normalized.includes('axis')) return '#8C1D40';
  if (normalized.includes('sbi')) return '#0EA5E9';
  if (normalized.includes('amazonpay')) return '#0F766E';
  if (normalized.includes('onecard')) return '#111827';
  const type = inferWalletCsvAccountType(name);
  if (type === 'credit_card') return '#7C3AED';
  if (type === 'wallet') return '#0891B2';
  if (type === 'prepaid') return '#F97316';
  if (type === 'loan') return '#DC2626';
  if (type === 'cash') return '#16A34A';
  return '#2563EB';
}

export function inferWalletCsvInstitution(name: string): string | undefined {
  const normalized = normalizeName(name);
  if (
    normalized.includes('onecard') &&
    (normalized.includes('bob') || normalized.includes('baroda'))
  ) {
    return 'Bank of Baroda';
  }
  if (normalized.includes('hdfc')) return 'HDFC Bank';
  if (normalized.includes('icici')) return 'ICICI Bank';
  if (normalized.includes('axis')) return 'Axis Bank';
  if (normalized.includes('sbi')) return 'SBI';
  if (normalized.includes('bob') || normalized.includes('baroda')) return 'Bank of Baroda';
  if (normalized.includes('kotak')) return 'Kotak Mahindra Bank';
  if (normalized.includes('idfc')) return 'IDFC FIRST Bank';
  if (normalized.includes('yesbank')) return 'YES Bank';
  if (normalized.includes('paytm')) return 'Paytm';
  if (normalized.includes('phonepe')) return 'PhonePe';
  if (normalized.includes('gpay') || normalized.includes('googlepay')) return 'Google Pay';
  if (normalized.includes('amazonpay')) return 'Amazon Pay';
  if (normalized.includes('onecard')) return 'OneCard';
  return undefined;
}

function unique<T>(items: T[]): T[] {
  return items.filter((item, index, all) => all.indexOf(item) === index);
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function stableHash(input: string): string {
  let hash = 2166136261;
  for (let index = 0; index < input.length; index += 1) {
    hash ^= input.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16).padStart(8, '0');
}
