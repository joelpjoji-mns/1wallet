import type { CurrencyCode, Money } from './money';

export type UUID = string;

export type AccountType =
  | 'cash'
  | 'bank'
  | 'credit_card'
  | 'debit_card'
  | 'wallet'
  | 'prepaid'
  | 'loan'
  | 'lent'
  | 'investment'
  | 'savings_goal'
  | 'overdraft'
  | 'crypto'
  | 'other';

export type TransactionType =
  | 'expense'
  | 'income'
  | 'transfer'
  | 'refund'
  | 'adjustment'
  | 'card_payment'
  | 'loan_repayment'
  | 'lent'
  | 'borrowed'
  | 'investment_buy'
  | 'investment_sell'
  | 'fee'
  | 'interest_in'
  | 'interest_out'
  | 'cashback';

export type TransactionStatus = 'cleared' | 'pending' | 'scheduled' | 'void';

export type TransactionSource =
  | 'manual'
  | 'recurring'
  | 'import'
  | 'notification'
  | 'sms'
  | 'email'
  | 'rule'
  | 'shared'
  | 'api';

export type AccountMatchIdentifierKind =
  | 'account_last4'
  | 'card_last4'
  | 'iban_last4'
  | 'sort_code'
  | 'upi_vpa'
  | 'phone_last4'
  | 'masked_number'
  | 'customer_ref';

export interface AccountMatchIdentifier {
  kind: AccountMatchIdentifierKind;
  value: string;
  label?: string;
  verified?: boolean;
}

export interface AccountMessageSourceHints {
  smsSenderIds?: string[];
  emailDomains?: string[];
  keywords?: string[];
}

export type AccountMessageHintKind =
  | AccountMatchIdentifierKind
  | 'sms_sender_id'
  | 'email_domain'
  | 'keyword';

export type AccountMessageHintTarget = 'match_identifier' | 'source_hint';

export interface AccountMessageHint {
  id?: string;
  kind: AccountMessageHintKind;
  target: AccountMessageHintTarget;
  value: string;
  label?: string;
  source?: 'message' | 'sender' | 'email' | 'manual';
  existing?: boolean;
  verified?: boolean;
}

export type LoanKind =
  | 'personal'
  | 'home'
  | 'vehicle'
  | 'education'
  | 'business'
  | 'gold'
  | 'bnpl'
  | 'overdraft'
  | 'lent'
  | 'other';

export type LoanInterestRatePeriod = 'annual' | 'monthly';
export type LoanInterestMethod = 'reducing_balance' | 'flat' | 'interest_only';
export type LoanTrackingSetupMode = 'track_from_next' | 'backfill_paid';
export type RecurrenceFrequency = 'daily' | 'weekly' | 'monthly' | 'yearly';

export interface AccountLoanDetails {
  loanKind?: LoanKind;
  principal?: Money;
  disbursedOn?: string;
  interestRatePercent?: number;
  interestRatePeriod?: LoanInterestRatePeriod;
  interestMethod?: LoanInterestMethod;
  repaymentSourceAccountId?: UUID;
  repaymentAmount?: Money;
  repaymentStartsOn?: string;
  repaymentFrequency?: RecurrenceFrequency;
  repaymentInterval?: number;
  repaymentDayOfMonth?: number;
  repaymentCount?: number;
  repaymentEndsOn?: string;
  autoCreateScheduledRecords?: boolean;
  linkedPlannedPaymentRuleId?: UUID;
  trackingStartsOn?: string;
  paidInstallmentsBeforeTracking?: number;
  setupMode?: LoanTrackingSetupMode;
  notes?: string;
}

export type CaptureCandidateStatus =
  | 'pending'
  | 'approved'
  | 'rejected'
  | 'ignored'
  | 'auto_posted';

export type CategoryKind = 'expense' | 'income' | 'transfer' | 'system';

export interface Account {
  id: UUID;
  userId: UUID;
  name: string;
  type: AccountType;
  currency: CurrencyCode;
  icon?: string;
  color?: string;
  institution?: string;
  accountNickname?: string;
  loanDetails?: AccountLoanDetails;
  matchIdentifiers?: AccountMatchIdentifier[];
  messageSourceHints?: AccountMessageSourceHints;
  openingBalance: Money;
  openingDate: string;
  includeInTotals: boolean;
  includeInBudgets: boolean;
  includeInReports: boolean;
  includeInNetWorth: boolean;
  showOnHome: boolean;
  isArchived: boolean;
  isDefault: boolean;
  notes?: string;
  sortOrder: number;
  groupName?: string;
  createdAt: string;
  updatedAt: string;
}

export interface Category {
  id: UUID;
  userId: UUID;
  parentId?: UUID;
  name: string;
  kind: CategoryKind;
  icon?: string;
  color?: string;
  isArchived: boolean;
  isHiddenInStats: boolean;
  sortOrder: number;
}

export interface Transaction {
  id: UUID;
  userId: UUID;
  type: TransactionType;
  status: TransactionStatus;
  source: TransactionSource;
  accountId: UUID;
  counterAccountId?: UUID;
  amount: Money;
  baseAmount: Money;
  fxRate?: number;
  originalAmount?: Money;
  originalFxRate?: number;
  counterAmount?: Money;
  counterFxRate?: number;
  categoryId?: UUID;
  merchantId?: UUID;
  occurredAt: string;
  locationLabel?: string;
  paymentMethod?: string;
  notes?: string;
  attachments?: TransactionAttachment[];
  tags?: string[];
  personId?: UUID;
  projectId?: UUID;
  tripId?: UUID;
  isReimbursable: boolean;
  isTaxDeductible: boolean;
  isExcludedFromReports: boolean;
  originalTransactionId?: UUID;
  recurringTemplateId?: UUID;
  captureCandidateId?: UUID;
  sourceConfidence?: number;
  externalRef?: string;
  createdAt: string;
  updatedAt: string;
}

export interface TransactionAttachment {
  id: UUID;
  name: string;
  uri: string;
  mimeType?: string;
  size?: number;
  width?: number;
  height?: number;
  source: 'camera' | 'library' | 'file' | 'import';
  createdAt: string;
}

export interface TransactionSplit {
  id: UUID;
  userId: UUID;
  transactionId: UUID;
  categoryId?: UUID;
  amount: Money;
  notes?: string;
  sortOrder: number;
  createdAt: string;
  updatedAt: string;
}

export type ImportBatchSource = 'wallet_csv' | 'manual_csv' | 'api' | 'notification';
export type ImportBatchStatus =
  | 'previewed'
  | 'queued'
  | 'partially_posted'
  | 'posted'
  | 'rolled_back';

export interface ImportBatch {
  id: UUID;
  userId: UUID;
  source: ImportBatchSource;
  status: ImportBatchStatus;
  name: string;
  fileNames: string[];
  rowCount: number;
  candidateCount: number;
  duplicateCount: number;
  transferPairCount: number;
  warningCount: number;
  notes?: string;
  createdAt: string;
  updatedAt: string;
}

export interface Budget {
  id: UUID;
  userId: UUID;
  name: string;
  period: 'weekly' | 'fortnightly' | 'monthly' | 'quarterly' | 'yearly' | 'custom';
  customDays?: number;
  startsOn: string;
  amount: Money;
  rolloverUnused: boolean;
  carryOverspend: boolean;
  isPaused: boolean;
  alertThresholds: number[];
}

export interface Goal {
  id: UUID;
  userId: UUID;
  name: string;
  kind: 'save_up' | 'pay_off' | 'build_up' | 'recurring';
  targetAmount: Money;
  targetDate?: string;
  priority: 'critical' | 'high' | 'medium' | 'low';
  linkedCategoryId?: UUID;
  isPaused: boolean;
  isCompleted: boolean;
}

export interface CaptureCandidate {
  id: UUID;
  userId: UUID;
  source: TransactionSource;
  rawPayload: Record<string, unknown>;
  rawHash: string;
  parsedAmount?: Money;
  parsedFxRate?: number;
  parsedOriginalAmount?: Money;
  parsedOriginalFxRate?: number;
  parsedCounterAmount?: Money;
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
  confidence: number;
  status: CaptureCandidateStatus;
  postedTransactionId?: UUID;
  importBatchId?: UUID;
  externalRef?: string;
  warnings?: string[];
  reviewedAt?: string;
  createdAt: string;
}
