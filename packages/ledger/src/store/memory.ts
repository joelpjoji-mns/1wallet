import { fromMinor, normalizeCurrencyCode, toMinor } from '@1wallet/domain/money';
import { uid } from '../id';
import type { ExchangeRateRecord, LedgerState, LedgerStore } from './types';
import {
  LEDGER_STATE_VERSION,
  defaultNotificationPreferences,
  emptyState,
  normalizeAutoCapturePreferences,
  normalizeUserProfilePreferences,
} from './types';

const LEGACY_AXIS_FOREX_TOTALS_NOTE =
  'Kept outside INR totals until a real GBP to INR rate is configured.';
const AXIS_FOREX_TOTALS_NOTE = 'Included in INR totals through live GBP to INR rates.';

/**
 * In-memory store. Useful for tests and as the backing primitive that the
 * web (localStorage) and mobile (AsyncStorage) stores wrap.
 */
export class MemoryStore implements LedgerStore {
  private state: LedgerState;

  constructor(initial?: LedgerState) {
    this.state = initial ?? emptyState(uid());
  }

  async load(): Promise<LedgerState> {
    return this.state;
  }

  async save(state: LedgerState): Promise<void> {
    this.state = { ...state, version: LEDGER_STATE_VERSION };
  }

  async clear(): Promise<void> {
    this.state = emptyState(this.state.userId, this.state.preferences.baseCurrency);
  }
}

/**
 * Generic key-value backed store. Pass any adapter that implements get/set.
 * Used by both web (localStorage) and mobile (AsyncStorage).
 */
export interface KVAdapter {
  getItem(key: string): Promise<string | null> | string | null;
  setItem(key: string, value: string): Promise<void> | void;
  removeItem(key: string): Promise<void> | void;
}

export class KVStore implements LedgerStore {
  constructor(
    private readonly kv: KVAdapter,
    private readonly key = '1wallet.ledger.v1',
  ) {}

  async load(): Promise<LedgerState> {
    const raw = await this.kv.getItem(this.key);
    if (!raw) {
      const fresh = emptyState(uid());
      await this.save(fresh);
      return fresh;
    }
    try {
      const parsed = JSON.parse(raw) as LedgerState;
      if (!parsed.version || parsed.version < LEDGER_STATE_VERSION) {
        const migrated = normalizeLedgerState(parsed);
        await this.save(migrated);
        return migrated;
      }
      return parsed;
    } catch {
      const fresh = emptyState(uid());
      await this.save(fresh);
      return fresh;
    }
  }

  async save(state: LedgerState): Promise<void> {
    await this.kv.setItem(this.key, JSON.stringify({ ...state, version: LEDGER_STATE_VERSION }));
  }

  async clear(): Promise<void> {
    await this.kv.removeItem(this.key);
  }
}

export function normalizeLedgerState(state: Partial<LedgerState>): LedgerState {
  // Patch missing fields from older local ledgers while preserving user data.
  const fresh = emptyState(state.userId ?? uid(), state.preferences?.baseCurrency);
  const notificationDefaults = defaultNotificationPreferences();
  const previousNotifications = state.preferences?.notifications;
  const accounts = (state.accounts ?? []).map((account) => {
    const migratedAccount = {
      ...account,
      showOnHome: account.showOnHome ?? !account.isArchived,
    };
    if (!isLegacySnapshotAxisForexCard(migratedAccount)) return migratedAccount;
    return {
      ...migratedAccount,
      includeInTotals: true,
      includeInNetWorth: true,
      notes: migratedAccount.notes?.replace(LEGACY_AXIS_FOREX_TOTALS_NOTE, AXIS_FOREX_TOTALS_NOTE),
    };
  });
  const exchangeRates = (state.exchangeRates ?? [])
    .filter((rate) => !isSeedExchangeRateRecord(rate))
    .map((rate) => ({
      ...rate,
      base: normalizeCurrencyCode(rate.base),
      quote: normalizeCurrencyCode(rate.quote),
      updatedAt: rate.updatedAt ?? rate.asOfDate,
      provider: rate.provider ?? 'manual',
      source: rate.source === 'refresh' ? 'refresh' : 'manual',
    })) satisfies ExchangeRateRecord[];
  const baseCurrency = normalizeCurrencyCode(
    state.preferences?.baseCurrency ?? fresh.preferences.baseCurrency,
  );
  const transactions = removeGeneratedScheduledTransactions(
    repairForeignPostedAmounts(state.transactions ?? [], baseCurrency, exchangeRates),
  );
  const displayCurrency = normalizeCurrencyCode(state.preferences?.displayCurrency ?? baseCurrency);
  const enabledCurrencies = collectEnabledCurrencies(
    state,
    accounts,
    exchangeRates,
    displayCurrency,
  );
  return {
    ...fresh,
    ...state,
    accounts,
    exchangeRates,
    transactions,
    preferences: {
      ...fresh.preferences,
      ...(state.preferences ?? {}),
      baseCurrency,
      displayCurrency,
      enabledCurrencies,
      fx: {
        ...fresh.preferences.fx,
        ...(state.preferences?.fx ?? {}),
        provider:
          state.preferences?.fx?.provider && state.preferences.fx.provider !== 'manual'
            ? state.preferences.fx.provider
            : (fresh.preferences.fx?.provider ?? 'frankfurter.app'),
        autoRefresh: true,
      },
      notifications: {
        ...notificationDefaults,
        ...(previousNotifications ?? {}),
        channels: {
          ...notificationDefaults.channels,
          ...(previousNotifications?.channels ?? {}),
        },
        quietHours: {
          ...notificationDefaults.quietHours,
          ...(previousNotifications?.quietHours ?? {}),
        },
        snoozedUntilById: previousNotifications?.snoozedUntilById ?? {},
        readIds: previousNotifications?.readIds ?? [],
        dismissedIds: previousNotifications?.dismissedIds ?? [],
        nativeDeliveredIds: previousNotifications?.nativeDeliveredIds ?? [],
      },
      profile: normalizeUserProfilePreferences(state.preferences?.profile),
      autoCapture: normalizeAutoCapturePreferences(state.preferences?.autoCapture),
      homeWidgets: {
        ...fresh.preferences.homeWidgets,
        ...(state.preferences?.homeWidgets ?? {}),
      },
      futureGenerationRules: state.preferences?.futureGenerationRules ?? [],
      messageCategoryRules: state.preferences?.messageCategoryRules ?? [],
    },
    transactionSplits: state.transactionSplits ?? [],
    importBatches: state.importBatches ?? [],
    version: LEDGER_STATE_VERSION,
  } as LedgerState;
}

function isLegacySnapshotAxisForexCard(account: LedgerState['accounts'][number]): boolean {
  return (
    account.name.toLowerCase() === 'axis forex card' &&
    normalizeCurrencyCode(account.currency) === 'GBP' &&
    Boolean(account.notes?.includes(LEGACY_AXIS_FOREX_TOTALS_NOTE))
  );
}

function isSeedExchangeRateRecord(rate: unknown): boolean {
  return (
    typeof rate === 'object' && rate !== null && (rate as { source?: unknown }).source === 'seed'
  );
}

function removeGeneratedScheduledTransactions(
  transactions: LedgerState['transactions'],
): LedgerState['transactions'] {
  return transactions.filter((transaction) => {
    if (transaction.status !== 'scheduled') return true;
    if (transaction.source === 'rule') return false;
    if (transaction.externalRef?.startsWith('future-rule-v1:')) return false;
    if (transaction.externalRef?.startsWith('recurring-schedule-v1:')) return false;
    return true;
  });
}

function repairForeignPostedAmounts(
  transactions: LedgerState['transactions'],
  baseCurrency: string,
  exchangeRates: ExchangeRateRecord[],
): LedgerState['transactions'] {
  return transactions.map((transaction) => {
    if (
      !transaction.originalAmount ||
      !transaction.originalFxRate ||
      transaction.originalFxRate <= 0
    ) {
      return transaction;
    }
    const amountCurrency = normalizeCurrencyCode(transaction.amount.currency);
    const originalCurrency = normalizeCurrencyCode(transaction.originalAmount.currency);
    if (amountCurrency === originalCurrency) return transaction;

    const postedValue = Math.abs(fromMinor(transaction.amount.amountMinor, amountCurrency));
    const originalValue = Math.abs(
      fromMinor(transaction.originalAmount.amountMinor, originalCurrency),
    );
    if (!nearlyEqual(postedValue, originalValue)) return transaction;

    const sign = transaction.amount.amountMinor < 0 ? -1 : 1;
    const repairedAmountMinor =
      sign * toMinor(originalValue * transaction.originalFxRate, amountCurrency);
    if (repairedAmountMinor === transaction.amount.amountMinor) return transaction;

    return {
      ...transaction,
      amount: { amountMinor: repairedAmountMinor, currency: amountCurrency },
      baseAmount: repairedBaseAmount(
        transaction,
        repairedAmountMinor,
        amountCurrency,
        baseCurrency,
        exchangeRates,
      ),
    };
  });
}

function repairedBaseAmount(
  transaction: LedgerState['transactions'][number],
  amountMinor: number,
  amountCurrency: string,
  baseCurrency: string,
  exchangeRates: ExchangeRateRecord[],
) {
  const normalizedBaseCurrency = normalizeCurrencyCode(baseCurrency);
  if (amountCurrency === normalizedBaseCurrency) {
    return { amountMinor, currency: normalizedBaseCurrency };
  }
  const rate =
    transaction.fxRate && transaction.fxRate > 0
      ? transaction.fxRate
      : rateBetweenExchangeRates(exchangeRates, amountCurrency, normalizedBaseCurrency);
  return {
    amountMinor: toMinor(fromMinor(amountMinor, amountCurrency) * rate, normalizedBaseCurrency),
    currency: normalizedBaseCurrency,
  };
}

function rateBetweenExchangeRates(
  exchangeRates: ExchangeRateRecord[],
  base: string,
  quote: string,
): number {
  const normalizedBase = normalizeCurrencyCode(base);
  const normalizedQuote = normalizeCurrencyCode(quote);
  if (normalizedBase === normalizedQuote) return 1;
  const direct = latestExchangeRate(exchangeRates, normalizedBase, normalizedQuote);
  if (direct) return direct.rate;
  const inverse = latestExchangeRate(exchangeRates, normalizedQuote, normalizedBase);
  if (inverse && inverse.rate !== 0) return 1 / inverse.rate;
  return 1;
}

function latestExchangeRate(
  exchangeRates: ExchangeRateRecord[],
  base: string,
  quote: string,
): ExchangeRateRecord | undefined {
  return exchangeRates
    .filter((rate) => rate.base === base && rate.quote === quote)
    .sort((left, right) => rateTimestamp(right) - rateTimestamp(left))[0];
}

function rateTimestamp(rate: ExchangeRateRecord): number {
  return Date.parse(rate.updatedAt ?? rate.asOfDate) || 0;
}

function nearlyEqual(left: number, right: number): boolean {
  return Math.abs(left - right) < 0.000001;
}

function collectEnabledCurrencies(
  state: Partial<LedgerState>,
  accounts: NonNullable<LedgerState['accounts']>,
  exchangeRates: ExchangeRateRecord[],
  displayCurrency?: string,
): string[] {
  const currencies = new Set<string>();
  const add = (currency?: string) => {
    const normalized = currency ? normalizeCurrencyCode(currency) : '';
    if (normalized) currencies.add(normalized);
  };
  add(state.preferences?.baseCurrency);
  add(displayCurrency);
  add(state.preferences?.displayCurrency);
  for (const currency of state.preferences?.enabledCurrencies ?? []) add(currency);
  for (const account of accounts) {
    add(account.currency);
    add(account.openingBalance?.currency);
  }
  for (const transaction of state.transactions ?? []) {
    add(transaction.amount?.currency);
    add(transaction.baseAmount?.currency);
    add(transaction.originalAmount?.currency);
    add(transaction.counterAmount?.currency);
  }
  for (const split of state.transactionSplits ?? []) add(split.amount?.currency);
  for (const budget of state.budgets ?? []) add(budget.amount?.currency);
  for (const goal of state.goals ?? []) add(goal.targetAmount?.currency);
  for (const candidate of state.captureCandidates ?? []) add(candidate.parsedAmount?.currency);
  for (const rate of exchangeRates) {
    add(rate.base);
    add(rate.quote);
  }
  return Array.from(currencies);
}
