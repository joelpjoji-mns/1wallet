// Mirrors lib/src/data/ledger_models.dart so the PWA can read/write the exact
// same `users/{uid}/wallet_backups/chunk_N` GZip snapshot format the Flutter
// app produces. Keep field names and shapes in lockstep with that file.

export const DEFAULT_CURRENCY = 'USD';

export interface Money {
  amountMinor: number;
  currency: string;
}

/** Anything the PWA doesn't (yet) model explicitly, preserved byte-for-byte. */
export type Extra = Record<string, unknown>;

export interface AccountLoanDetails extends Extra {
  loanKind?: string | null;
  principal?: Money | null;
  repaymentAmount?: Money | null;
  interestRatePercent?: number | null;
  repaymentCount?: number | null;
  repaymentStartsOn?: string | null;
  repaymentSourceAccountId?: string | null;
  recurrenceFrequency?: string;
  recurrenceInterval?: number;
  recurrenceDaysOfWeek?: number[] | null;
  recurrenceDaysOfMonth?: number[] | null;
  recurrenceEndDate?: string | null;
  recurrenceLimit?: number | null;
  hideInterestInLedger?: boolean;
}

export interface Account extends Extra {
  id: string;
  name: string;
  type: string;
  currency: string;
  openingBalance: Money;
  color?: number | null;
  institution?: string | null;
  groupName?: string | null;
  cardLast4?: string | null;
  accountLast4?: string | null;
  loanDetails?: AccountLoanDetails | null;
  /**
   * Device-encrypted secret fields (e.g. card/account numbers). Encrypted with
   * a per-device AES key stored in the OS secure enclave (see
   * lib/src/utils/secure_key_store.dart) — the web app has no access to that
   * key and MUST treat this as an opaque blob: never attempt to decrypt it,
   * never display it, and always round-trip it untouched.
   */
  encryptedDetails?: Record<string, string> | null;
  includeInTotals: boolean;
  includeInReports: boolean;
  includeInNetWorth: boolean;
  showOnHome: boolean;
  isArchived: boolean;
  sortOrder: number;
  creditLimit?: Money | null;
}

export interface Category extends Extra {
  id: string;
  name: string;
  kind: string;
  color?: number | null;
  parentId?: string | null;
  isArchived: boolean;
  sortOrder: number;
}

export interface TransactionAttachment extends Extra {
  id: string;
  source: string;
  name: string;
  uri: string;
  mimeType?: string | null;
}

export interface TransactionRecord extends Extra {
  id: string;
  type: string;
  status: string;
  source: string;
  accountId: string;
  counterAccountId?: string | null;
  amount: Money;
  baseAmount: Money;
  counterAmount?: Money | null;
  originalAmount?: Money | null;
  fxRate?: number | null;
  originalFxRate?: number | null;
  categoryId?: string | null;
  occurredAt: string;
  locationLabel?: string | null;
  paymentMethod?: string | null;
  name?: string | null;
  notes?: string | null;
  importBatchId?: string | null;
  recurrenceFrequency?: string | null;
  recurrenceInterval: number;
  recurrenceDaysOfWeek?: number[] | null;
  recurrenceDaysOfMonth?: number[] | null;
  recurrenceEndDate?: string | null;
  recurrenceLimit?: number | null;
  attachments: TransactionAttachment[];
  isReimbursable: boolean;
  isTaxDeductible: boolean;
  isExcludedFromReports: boolean;
  sourceConfidence?: number | null;
  externalRef?: string | null;
  originalTransactionId?: string | null;
  postMode?: string | null;
}

export interface LedgerPreferences extends Extra {
  baseCurrency: string;
  displayCurrency: string;
  enabledCurrencies: string[];
  locale: string;
  startDayOfMonth: number;
  homeWidgetOrder: string[];
  homeWidgetHidden: string[];
  homeWidgetSizes: Record<string, string>;
  homeWidgetFilters: Record<string, string>;
  futureGenerationRules?: Extra[];
  hideSkippedInHistory: boolean;
}

/** Raw pass-through records the PWA does not edit but must never drop. */
export type CaptureCandidate = Extra;
export type ImportBatch = Extra;
export type ExchangeRateRecord = Extra;

export interface LedgerSnapshot {
  syncSettings: Extra | null;
  preferences: LedgerPreferences;
  accounts: Account[];
  categories: Category[];
  transactions: TransactionRecord[];
  captureCandidates: CaptureCandidate[];
  importBatches: ImportBatch[];
  exchangeRates: ExchangeRateRecord[];
}

export function emptyLedgerSnapshot(): LedgerSnapshot {
  return {
    syncSettings: null,
    preferences: {
      baseCurrency: DEFAULT_CURRENCY,
      displayCurrency: DEFAULT_CURRENCY,
      enabledCurrencies: [DEFAULT_CURRENCY],
      locale: 'en_US',
      startDayOfMonth: 1,
      homeWidgetOrder: [],
      homeWidgetHidden: [],
      homeWidgetSizes: {},
      homeWidgetFilters: {},
      hideSkippedInHistory: false,
    },
    accounts: [],
    categories: [],
    transactions: [],
    captureCandidates: [],
    importBatches: [],
    exchangeRates: [],
  };
}
