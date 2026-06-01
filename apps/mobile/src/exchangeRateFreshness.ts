import { exchangeRatePairIsStale, hasExplicitRate, rateBetween } from '@1wallet/ledger/services';
import type { LedgerState } from '@1wallet/ledger/store/types';
import type { ExchangeRateRefreshResult } from '@1wallet/state';

export type RefreshExchangeRates = () => Promise<ExchangeRateRefreshResult>;

export async function refreshRatesForPairIfStale(
  state: LedgerState,
  refreshExchangeRates: RefreshExchangeRates,
  base: string,
  quote: string,
): Promise<LedgerState> {
  if (!exchangeRatePairIsStale(state, base, quote)) return state;
  const result = await refreshExchangeRates();
  return stateWithExchangeRates(state, result);
}

export function stateWithExchangeRates(
  state: LedgerState,
  result: ExchangeRateRefreshResult,
): LedgerState {
  if (!result.exchangeRates) return state;
  return {
    ...state,
    exchangeRates: result.exchangeRates.map((rate) => ({ ...rate })),
    preferences: {
      ...state.preferences,
      fx: {
        ...state.preferences.fx,
        provider: result.provider,
        autoRefresh: true,
        lastRefreshedAt: result.updatedAt ?? state.preferences.fx?.lastRefreshedAt,
      },
    },
  };
}

export function freshRateBetween(
  state: LedgerState,
  base: string,
  quote: string,
): number | undefined {
  return hasExplicitRate(state, base, quote) ? rateBetween(state, base, quote) : undefined;
}
