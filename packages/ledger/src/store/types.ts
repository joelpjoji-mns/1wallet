import { normalizeCurrencyCode } from '@1wallet/domain/money';
import type {
    Account,
    Budget,
    CaptureCandidate,
    Category,
    Goal,
    ImportBatch,
    Transaction,
    TransactionSplit,
    TransactionType,
    UUID,
} from '@1wallet/domain/types';

export type ExchangeRateSource = 'refresh' | 'manual';

export interface ExchangeRateRecord {
  base: string;
  quote: string;
  rate: number;
  asOfDate: string;
  updatedAt?: string;
  provider?: string;
  source?: ExchangeRateSource;
}

export interface NotificationPreferences {
  enabled: boolean;
  pushEnabled: boolean;
  channels: {
    reviewQueue: boolean;
    scheduled: boolean;
    budgets: boolean;
    goals: boolean;
    accounts: boolean;
    imports: boolean;
  };
  quietHours: {
    enabled: boolean;
    start: string;
    end: string;
  };
  readIds: string[];
  dismissedIds: string[];
  nativeDeliveredIds: string[];
  snoozedUntilById: Record<string, string>;
}

export interface AutoCaptureRunSummary {
  ranAt: string;
  scanned: number;
  recognized: number;
  posted: number;
  queued: number;
  duplicates: number;
  ignored: number;
  unrecognized?: number;
  ignoredReasons?: Record<string, number>;
  lastOutcome?: string;
  lastReason?: string;
}

export interface AutoCaptureSmsPreferences {
  enabled: boolean;
  backgroundEnabled: boolean;
  scanLimit: number;
  triggerKeywords: string[];
  ignoredSenderIds: string[];
  lastRun?: AutoCaptureRunSummary;
}

export interface AutoCapturePreferences {
  enabled: boolean;
  autoPost: boolean;
  autoPostConfidence: number;
  sms: AutoCaptureSmsPreferences;
}

export type FutureGenerationFrequency = 'daily' | 'weekly' | 'monthly' | 'yearly';
export type PlannedPaymentKind = 'income' | 'expense' | 'transfer' | 'adjustment';
export type PlannedPaymentPostMode = 'manual' | 'automatic';

export interface MessageCategoryKeywordRule {
  id: UUID;
  name: string;
  enabled: boolean;
  keywords: string[];
  categoryId: UUID;
  priority: number;
  createdAt: string;
  updatedAt: string;
}

export interface FutureGenerationRule {
  id: UUID;
  name: string;
  enabled: boolean;
  kind?: PlannedPaymentKind;
  postMode?: PlannedPaymentPostMode;
  type: TransactionType;
  accountId: UUID;
  counterAccountId?: UUID;
  categoryId?: UUID;
  amountMinor: number;
  currency: string;
  frequency: FutureGenerationFrequency;
  interval: number;
  dayOfMonth?: number;
  daysOfWeek?: number[];
  startsOn: string;
  endsOn?: string;
  occurrences?: number;
  skippedOccurrences?: string[];
  paymentMethod?: string;
  notes?: string;
  tags?: string[];
  createdAt: string;
  updatedAt: string;
}

export type ThemePreference = 'system' | 'light' | 'dark' | 'amoled';
export type ThemeAccentSource = 'system' | 'custom';

export interface ThemeAccentPreference {
  source: ThemeAccentSource;
  customColor?: string;
}

export type OnboardingUseCase =
  | 'daily_spending'
  | 'budgeting'
  | 'bills_subscriptions'
  | 'cards_loans'
  | 'business_self_employed'
  | 'investments_net_worth';

export interface UserProfilePreferences {
  displayName?: string;
  primaryUseCases: OnboardingUseCase[];
  onboardingCompletedAt?: string;
}

/**
 * The shape of the persisted ledger. This is the single source of truth that
 * gets read/written by storage adapters.
 */
export interface LedgerState {
  version: number;
  userId: UUID;
  preferences: {
    baseCurrency: string;
    displayCurrency?: string;
    enabledCurrencies?: string[];
    locale: string;
    startDayOfMonth: number;
    profile?: UserProfilePreferences;
    theme: ThemePreference;
    themeAccent?: ThemeAccentPreference;
    fx?: {
      provider?: string;
      lastRefreshedAt?: string;
      autoRefresh?: boolean;
    };
    notifications?: NotificationPreferences;
    homeWidgets?: {
      order: string[];
      hidden: string[];
      sizes: Record<string, 'compact' | 'medium' | 'wide'>;
      filters?: Record<
        string,
        'today' | 'thisWeek' | 'thisMonth' | 'lastMonth' | 'thisYear' | 'allTime'
      >;
    };
    futureGenerationRules?: FutureGenerationRule[];
    messageCategoryRules?: MessageCategoryKeywordRule[];
    autoCapture?: AutoCapturePreferences;
  };
  accounts: Account[];
  categories: Category[];
  transactions: Transaction[];
  transactionSplits: TransactionSplit[];
  budgets: Budget[];
  goals: Goal[];
  captureCandidates: CaptureCandidate[];
  importBatches: ImportBatch[];
  tags: { id: UUID; name: string; color?: string }[];
  merchants: { id: UUID; name: string; normalizedName: string; defaultCategoryId?: UUID }[];
  exchangeRates: ExchangeRateRecord[];
}

export interface LedgerStore {
  load(): Promise<LedgerState>;
  save(state: LedgerState): Promise<void>;
  clear(): Promise<void>;
}

export const LEDGER_STATE_VERSION = 14;

export function emptyState(userId: UUID, baseCurrency = 'INR'): LedgerState {
  const normalizedBaseCurrency = normalizeCurrencyCode(baseCurrency);
  const defaultEnabledCurrencies = [normalizedBaseCurrency];
  return {
    version: LEDGER_STATE_VERSION,
    userId,
    preferences: {
      baseCurrency: normalizedBaseCurrency,
      displayCurrency: normalizedBaseCurrency,
      enabledCurrencies: defaultEnabledCurrencies,
      locale: 'en-IN',
      startDayOfMonth: 1,
      profile: defaultUserProfilePreferences(),
      theme: 'system',
      themeAccent: { source: 'system' },
      fx: { provider: 'frankfurter.app', autoRefresh: true },
      notifications: defaultNotificationPreferences(),
      autoCapture: defaultAutoCapturePreferences(),
      homeWidgets: { order: [], hidden: [], sizes: {}, filters: {} },
      futureGenerationRules: [],
      messageCategoryRules: [],
    },
    accounts: [],
    categories: [],
    transactions: [],
    transactionSplits: [],
    budgets: [],
    goals: [],
    captureCandidates: [],
    importBatches: [],
    tags: [],
    merchants: [],
    exchangeRates: [],
  };
}

export function defaultUserProfilePreferences(): UserProfilePreferences {
  return { primaryUseCases: [] };
}

export function normalizeUserProfilePreferences(
  profile?: Partial<UserProfilePreferences>,
): UserProfilePreferences {
  const displayName = normalizeDisplayName(profile?.displayName);
  return {
    ...(displayName ? { displayName } : {}),
    primaryUseCases: normalizeOnboardingUseCases(profile?.primaryUseCases),
    onboardingCompletedAt:
      typeof profile?.onboardingCompletedAt === 'string'
        ? profile.onboardingCompletedAt
        : undefined,
  };
}

export const DEFAULT_AUTO_CAPTURE_TRIGGER_KEYWORDS = [
  'credited',
  'debited',
  'credit',
  'debit',
  'paid',
  'spent',
  'purchase',
  'received',
  'refund',
  'cashback',
  'withdrawn',
  'charged',
  'deducted',
  'auto debit',
  'upi',
  'imps',
  'neft',
  'rtgs',
  'pos',
  'atm',
  'card transaction',
  'INR',
  'Rs',
  '₹',
  'GBP',
  '£',
  'USD',
  '$',
] as const;

export function defaultAutoCapturePreferences(): AutoCapturePreferences {
  return {
    enabled: true,
    autoPost: true,
    autoPostConfidence: 82,
    sms: {
      enabled: true,
      backgroundEnabled: true,
      scanLimit: 200,
      triggerKeywords: [...DEFAULT_AUTO_CAPTURE_TRIGGER_KEYWORDS],
      ignoredSenderIds: [],
    },
  };
}

export function normalizeAutoCapturePreferences(
  preferences?: Partial<AutoCapturePreferences>,
): AutoCapturePreferences {
  const defaults = defaultAutoCapturePreferences();
  const sms = preferences?.sms;
  return {
    ...defaults,
    ...(preferences ?? {}),
    autoPostConfidence: clampAutoPostConfidence(preferences?.autoPostConfidence),
    sms: {
      ...defaults.sms,
      ...(sms ?? {}),
      scanLimit: clampSmsScanLimit(sms?.scanLimit),
      triggerKeywords: normalizePreferenceList(sms?.triggerKeywords, defaults.sms.triggerKeywords),
      ignoredSenderIds: normalizePreferenceList(sms?.ignoredSenderIds, []),
      lastRun: normalizeRunSummary(sms?.lastRun),
    },
  };
}

export function defaultNotificationPreferences(): NotificationPreferences {
  return {
    enabled: true,
    pushEnabled: false,
    channels: {
      reviewQueue: false,
      scheduled: true,
      budgets: true,
      goals: true,
      accounts: false,
      imports: false,
    },
    quietHours: { enabled: false, start: '22:00', end: '07:00' },
    readIds: [],
    dismissedIds: [],
    nativeDeliveredIds: [],
    snoozedUntilById: {},
  };
}

function clampAutoPostConfidence(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) return 82;
  return Math.max(0, Math.min(100, Math.round(value)));
}

function clampSmsScanLimit(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) return 200;
  return Math.max(25, Math.min(1000, Math.round(value)));
}

function normalizePreferenceList(values: unknown, fallback: string[]): string[] {
  if (!Array.isArray(values)) return [...fallback];
  const seen = new Set<string>();
  const normalized: string[] = [];
  for (const value of values) {
    if (typeof value !== 'string') continue;
    const item = value.replace(/\s+/g, ' ').trim().slice(0, 64);
    const key = item.toLowerCase();
    if (!item || seen.has(key)) continue;
    seen.add(key);
    normalized.push(item);
  }
  return normalized.length > 0 ? normalized : [...fallback];
}

function normalizeDisplayName(value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;
  const normalized = value.replace(/\s+/g, ' ').trim().slice(0, 80);
  return normalized || undefined;
}

function normalizeOnboardingUseCases(values: unknown): OnboardingUseCase[] {
  if (!Array.isArray(values)) return [];
  const allowed = new Set<OnboardingUseCase>([
    'daily_spending',
    'budgeting',
    'bills_subscriptions',
    'cards_loans',
    'business_self_employed',
    'investments_net_worth',
  ]);
  const seen = new Set<OnboardingUseCase>();
  for (const value of values) {
    if (typeof value !== 'string' || !allowed.has(value as OnboardingUseCase)) continue;
    seen.add(value as OnboardingUseCase);
  }
  return [...seen];
}

function normalizeRunSummary(value: unknown): AutoCaptureRunSummary | undefined {
  if (!value || typeof value !== 'object') return undefined;
  const summary = value as Partial<AutoCaptureRunSummary>;
  if (typeof summary.ranAt !== 'string') return undefined;
  return {
    ranAt: summary.ranAt,
    scanned: nonNegativeInteger(summary.scanned),
    recognized: nonNegativeInteger(summary.recognized),
    posted: nonNegativeInteger(summary.posted),
    queued: nonNegativeInteger(summary.queued),
    duplicates: nonNegativeInteger(summary.duplicates),
    ignored: nonNegativeInteger(summary.ignored),
    unrecognized: nonNegativeInteger(summary.unrecognized),
    ignoredReasons: normalizeReasonCounts(summary.ignoredReasons),
    lastOutcome: typeof summary.lastOutcome === 'string' ? summary.lastOutcome : undefined,
    lastReason: typeof summary.lastReason === 'string' ? summary.lastReason : undefined,
  };
}

function normalizeReasonCounts(value: unknown): Record<string, number> | undefined {
  if (!value || typeof value !== 'object') return undefined;
  const counts: Record<string, number> = {};
  for (const [key, count] of Object.entries(value as Record<string, unknown>)) {
    const normalizedKey = key.replace(/\s+/g, ' ').trim().slice(0, 80);
    const normalizedCount = nonNegativeInteger(count);
    if (!normalizedKey || normalizedCount === 0) continue;
    counts[normalizedKey] = normalizedCount;
  }
  return Object.keys(counts).length > 0 ? counts : undefined;
}

function nonNegativeInteger(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) ? Math.max(0, Math.round(value)) : 0;
}
