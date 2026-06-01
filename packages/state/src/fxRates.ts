import { normalizeCurrencyCode } from '@1wallet/domain/money';
import { enabledCurrencies, setRate } from '@1wallet/ledger/services';
import type { LedgerState } from '@1wallet/ledger/store/types';

export const INTERNET_RATE_PROVIDER = 'frankfurter.app';

export interface ExchangeRateRefreshResult {
  refreshed: boolean;
  provider: string;
  baseCurrency: string;
  targets: string[];
  asOfDate?: string;
  updatedAt?: string;
  savedRates: number;
  exchangeRates?: LedgerState['exchangeRates'];
}

export function exchangeRateRefreshTargets(state: LedgerState): string[] {
  const baseCurrency = normalizeCurrencyCode(state.preferences.baseCurrency);
  const currencies = new Set<string>();
  for (const currency of enabledCurrencies(state)) {
    const normalized = normalizeCurrencyCode(currency);
    if (normalized && normalized !== baseCurrency) currencies.add(normalized);
  }
  return Array.from(currencies).sort();
}

export function exchangeRateRefreshKey(state: LedgerState): string | undefined {
  const targets = exchangeRateRefreshTargets(state);
  if (targets.length === 0) return undefined;
  return `${normalizeCurrencyCode(state.preferences.baseCurrency)}:${targets.join(',')}`;
}

export async function refreshInternetExchangeRates(
  state: LedgerState,
): Promise<ExchangeRateRefreshResult> {
  const baseCurrency = normalizeCurrencyCode(state.preferences.baseCurrency);
  const targets = exchangeRateRefreshTargets(state);
  if (targets.length === 0) {
    return {
      refreshed: false,
      provider: INTERNET_RATE_PROVIDER,
      baseCurrency,
      targets,
      savedRates: 0,
    };
  }

  const response = await fetch(
    `https://api.frankfurter.app/latest?from=${encodeURIComponent(baseCurrency)}&to=${encodeURIComponent(
      targets.join(','),
    )}`,
  );
  if (!response.ok) throw new Error(`Exchange rate fetch failed: HTTP ${response.status}`);

  const data = (await response.json()) as { date?: string; rates?: Record<string, number> };
  const asOfDate = data.date ?? new Date().toISOString().slice(0, 10);
  const updatedAt = new Date().toISOString();
  let savedRates = 0;

  for (const [quote, rate] of Object.entries(data.rates ?? {})) {
    if (Number.isFinite(rate) && rate > 0) {
      setRate(state, baseCurrency, quote, rate, asOfDate, {
        source: 'refresh',
        provider: INTERNET_RATE_PROVIDER,
        updatedAt,
      });
      savedRates += 1;
    }
  }

  if (savedRates === 0) throw new Error('Exchange rate fetch returned no usable rates');

  state.preferences.fx = {
    ...state.preferences.fx,
    provider: INTERNET_RATE_PROVIDER,
    autoRefresh: true,
    lastRefreshedAt: updatedAt,
  };

  return {
    refreshed: true,
    provider: INTERNET_RATE_PROVIDER,
    baseCurrency,
    targets,
    asOfDate,
    updatedAt,
    savedRates,
    exchangeRates: state.exchangeRates.map((rate) => ({ ...rate })),
  };
}
