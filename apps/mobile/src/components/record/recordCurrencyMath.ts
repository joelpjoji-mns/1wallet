import { fromMinor, normalizeCurrencyCode, toMinor } from '@1wallet/domain/money';
import type { Money } from '@1wallet/domain/money';
import { postedAmountFromOriginal } from '@1wallet/ledger/services';

export interface RecordCurrencyDraft {
  isForeign: boolean;
  purchaseCurrency: string;
  postedCurrency: string;
  originalValue: number;
  fxRate?: number;
  originalAmountMinor?: number;
  postedAmountMinor?: number;
  originalMoney?: Money;
  postedMoney?: Money;
  postedAmountText?: string;
  canConvert: boolean;
  needsRate: boolean;
}

export function resolveRecordCurrencyDraft({
  originalAmountText,
  purchaseCurrency,
  postedCurrency,
  fxRateText,
  suggestedRate,
}: {
  originalAmountText: string;
  purchaseCurrency: string;
  postedCurrency: string;
  fxRateText: string;
  suggestedRate?: number;
}): RecordCurrencyDraft {
  const normalizedPurchaseCurrency = normalizeCurrencyCode(purchaseCurrency);
  const normalizedPostedCurrency = normalizeCurrencyCode(postedCurrency);
  const isForeign = normalizedPurchaseCurrency !== normalizedPostedCurrency;
  const originalValue = numberFromCurrencyText(originalAmountText);
  const typedRate = numberFromCurrencyText(fxRateText);
  const fallbackRate = suggestedRate && suggestedRate > 0 ? suggestedRate : undefined;
  const fxRate = typedRate > 0 ? typedRate : fallbackRate;

  if (!isForeign || originalValue <= 0) {
    return {
      isForeign,
      purchaseCurrency: normalizedPurchaseCurrency,
      postedCurrency: normalizedPostedCurrency,
      originalValue,
      canConvert: false,
      needsRate: false,
    };
  }

  if (!fxRate || fxRate <= 0) {
    return {
      isForeign,
      purchaseCurrency: normalizedPurchaseCurrency,
      postedCurrency: normalizedPostedCurrency,
      originalValue,
      canConvert: false,
      needsRate: true,
    };
  }

  const originalMoney = {
    amountMinor: toMinor(originalValue, normalizedPurchaseCurrency),
    currency: normalizedPurchaseCurrency,
  };
  const postedMoney = postedAmountFromOriginal(originalMoney, normalizedPostedCurrency, fxRate);

  return {
    isForeign,
    purchaseCurrency: normalizedPurchaseCurrency,
    postedCurrency: normalizedPostedCurrency,
    originalValue,
    fxRate,
    originalAmountMinor: originalMoney.amountMinor,
    postedAmountMinor: postedMoney.amountMinor,
    originalMoney,
    postedMoney,
    postedAmountText: trimCurrencyAmount(fromMinor(postedMoney.amountMinor, postedMoney.currency)),
    canConvert: true,
    needsRate: false,
  };
}

export function numberFromCurrencyText(value: string): number {
  const number = Number(value.replace(/,/g, '').trim());
  return Number.isFinite(number) ? number : 0;
}

export function trimCurrencyAmount(value: number): string {
  if (!Number.isFinite(value)) return '';
  return String(Number(value.toFixed(2)));
}

export function trimFxRateValue(value: number): string {
  if (!Number.isFinite(value)) return '';
  return String(Number(value.toFixed(6)));
}
