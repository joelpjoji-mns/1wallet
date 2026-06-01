import type { LedgerState } from '@1wallet/ledger/store/types';
import { resolveRecordCurrencyDraft } from './components/record/recordCurrencyMath';
import { freshRateBetween } from './exchangeRateFreshness';

export function resolveRecordCurrencyDraftForState({
  state,
  originalAmountText,
  purchaseCurrency,
  postedCurrency,
  fxRateText,
}: {
  state: LedgerState;
  originalAmountText: string;
  purchaseCurrency: string;
  postedCurrency: string;
  fxRateText: string;
}) {
  return resolveRecordCurrencyDraft({
    originalAmountText,
    purchaseCurrency,
    postedCurrency,
    fxRateText,
    suggestedRate: freshRateBetween(state, purchaseCurrency, postedCurrency),
  });
}
