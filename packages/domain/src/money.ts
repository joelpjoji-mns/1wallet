/**
 * Money is stored as minor units (bigint-safe integer) plus a 3-letter ISO currency code.
 * Never use floating point for money math.
 */

export type CurrencyCode = string;

export interface Money {
  amountMinor: number;
  currency: CurrencyCode;
}

export interface CurrencyDefinition {
  code: CurrencyCode;
  label: string;
  symbol: string;
  locale: string;
  minorUnits: number;
  icon: string;
}

export const SUPPORTED_CURRENCIES: CurrencyDefinition[] = [
  {
    code: 'INR',
    label: 'Indian rupee',
    symbol: '₹',
    locale: 'en-IN',
    minorUnits: 2,
    icon: 'currency-inr',
  },
  {
    code: 'USD',
    label: 'United States dollar',
    symbol: '$',
    locale: 'en-US',
    minorUnits: 2,
    icon: 'currency-usd',
  },
  {
    code: 'EUR',
    label: 'Euro',
    symbol: '€',
    locale: 'en-IE',
    minorUnits: 2,
    icon: 'currency-eur',
  },
  {
    code: 'GBP',
    label: 'British pound',
    symbol: '£',
    locale: 'en-GB',
    minorUnits: 2,
    icon: 'currency-gbp',
  },
  {
    code: 'AED',
    label: 'UAE dirham',
    symbol: 'د.إ',
    locale: 'en-AE',
    minorUnits: 2,
    icon: 'currency-usd',
  },
  {
    code: 'SGD',
    label: 'Singapore dollar',
    symbol: 'S$',
    locale: 'en-SG',
    minorUnits: 2,
    icon: 'currency-usd',
  },
  {
    code: 'JPY',
    label: 'Japanese yen',
    symbol: '¥',
    locale: 'ja-JP',
    minorUnits: 0,
    icon: 'currency-jpy',
  },
  {
    code: 'AUD',
    label: 'Australian dollar',
    symbol: 'A$',
    locale: 'en-AU',
    minorUnits: 2,
    icon: 'currency-usd',
  },
  {
    code: 'CAD',
    label: 'Canadian dollar',
    symbol: 'C$',
    locale: 'en-CA',
    minorUnits: 2,
    icon: 'currency-usd',
  },
];

export const DEFAULT_ENABLED_CURRENCIES: CurrencyCode[] = ['INR', 'USD', 'EUR', 'GBP'];

export const CURRENCY_MINOR_UNITS: Record<string, number> = {
  INR: 2,
  USD: 2,
  EUR: 2,
  GBP: 2,
  JPY: 0,
  AED: 2,
  SGD: 2,
  AUD: 2,
  CAD: 2,
};

export function normalizeCurrencyCode(currency: CurrencyCode): CurrencyCode {
  return currency.trim().toUpperCase();
}

export function currencyDefinition(currency: CurrencyCode): CurrencyDefinition {
  const code = normalizeCurrencyCode(currency);
  return (
    SUPPORTED_CURRENCIES.find((item) => item.code === code) ?? {
      code,
      label: code,
      symbol: code,
      locale: 'en-US',
      minorUnits: minorUnitsFor(code),
      icon: 'currency-usd',
    }
  );
}

export function minorUnitsFor(currency: CurrencyCode): number {
  return CURRENCY_MINOR_UNITS[normalizeCurrencyCode(currency)] ?? 2;
}

export function toMinor(amount: number, currency: CurrencyCode): number {
  const units = minorUnitsFor(currency);
  const factor = Math.pow(10, units);
  return Math.round(amount * factor);
}

export function fromMinor(amountMinor: number, currency: CurrencyCode): number {
  const units = minorUnitsFor(currency);
  return amountMinor / Math.pow(10, units);
}

export function addMoney(a: Money, b: Money): Money {
  if (a.currency !== b.currency) {
    throw new Error(`addMoney: currency mismatch ${a.currency} vs ${b.currency}`);
  }
  return { amountMinor: a.amountMinor + b.amountMinor, currency: a.currency };
}

export function subMoney(a: Money, b: Money): Money {
  if (a.currency !== b.currency) {
    throw new Error(`subMoney: currency mismatch ${a.currency} vs ${b.currency}`);
  }
  return { amountMinor: a.amountMinor - b.amountMinor, currency: a.currency };
}

export function negateMoney(m: Money): Money {
  return { amountMinor: -m.amountMinor, currency: m.currency };
}

export function convertMoney(m: Money, toCurrency: CurrencyCode, fxRate: number): Money {
  if (m.currency === toCurrency) return m;
  const fromValue = fromMinor(m.amountMinor, m.currency);
  const toValue = fromValue * fxRate;
  return { amountMinor: toMinor(toValue, toCurrency), currency: toCurrency };
}

export function formatMoney(m: Money, locale = 'en-IN'): string {
  const value = fromMinor(m.amountMinor, m.currency);
  return new Intl.NumberFormat(locale, {
    style: 'currency',
    currency: m.currency,
    maximumFractionDigits: minorUnitsFor(m.currency),
  }).format(value);
}
