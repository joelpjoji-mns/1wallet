import type { ExchangeRateRecord, Money } from './ledgerTypes';

/**
 * Converts `amountMinor` in `from` currency into `to` currency using the
 * latest matching rate in `rates` (real synced exchange-rate records — no
 * invented figures). Returns `null` when no usable rate exists so callers can
 * fall back to grouping by currency instead of showing a fabricated total.
 */
export function convertMinor(
  amountMinor: number,
  from: string,
  to: string,
  rates: ExchangeRateRecord[],
): number | null {
  if (from === to) return amountMinor;
  const direct = rates.find(
    (r) => (r as { base?: string }).base === from && (r as { quote?: string }).quote === to,
  ) as { rate?: number } | undefined;
  if (direct?.rate) return Math.round(amountMinor * direct.rate);
  const inverse = rates.find(
    (r) => (r as { base?: string }).base === to && (r as { quote?: string }).quote === from,
  ) as { rate?: number } | undefined;
  if (inverse?.rate) return Math.round(amountMinor / inverse.rate);
  return null;
}

/** Formats an `{ amountMinor, currency }` value as localized currency text. */
export function formatMoney(money: Money | null | undefined, locale = 'en-US'): string {
  if (!money) return '—';
  try {
    return new Intl.NumberFormat(locale, {
      style: 'currency',
      currency: money.currency || 'USD',
      currencyDisplay: 'narrowSymbol',
    }).format(money.amountMinor / 100);
  } catch {
    return `${(money.amountMinor / 100).toFixed(2)} ${money.currency}`;
  }
}

export function sumMoney(values: Money[], currency: string): number {
  return values
    .filter((m) => m.currency === currency)
    .reduce((acc, m) => acc + m.amountMinor, 0);
}

export function formatMinor(amountMinor: number, currency: string, locale = 'en-US'): string {
  return formatMoney({ amountMinor, currency }, locale);
}
