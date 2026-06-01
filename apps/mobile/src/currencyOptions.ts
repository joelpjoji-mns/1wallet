import {
    SUPPORTED_CURRENCIES,
    currencyDefinition,
    normalizeCurrencyCode,
} from '@1wallet/domain/money';
import { resolveAppIconName } from './components/AppKit';
import type { OptionListItem } from './components/OptionListOverlay';

export function buildCurrencyOptions(currencies: Iterable<string>): OptionListItem[] {
  const seen = new Set<string>();
  const options: OptionListItem[] = [];

  for (const currency of currencies) {
    const code = normalizeCurrencyCode(currency);
    if (!code || seen.has(code)) continue;
    seen.add(code);
    options.push(currencyOption(code));
  }

  return options;
}

export function buildEnabledCurrencyOptions(
  enabledCurrencies: Iterable<string>,
  priorityCurrencies: Iterable<string> = [],
): OptionListItem[] {
  return buildCurrencyOptions([...priorityCurrencies, ...enabledCurrencies]);
}

export function buildSupportedCurrencyOptions(
  priorityCurrencies: Iterable<string> = [],
): OptionListItem[] {
  return buildCurrencyOptions([
    ...priorityCurrencies,
    ...SUPPORTED_CURRENCIES.map((currency) => currency.code),
  ]);
}

export function currencyOption(currency: string): OptionListItem {
  const definition = currencyDefinition(currency);
  return {
    value: definition.code,
    label: definition.code,
    description: definition.label,
    icon: resolveAppIconName(definition.icon, 'currency-usd'),
  };
}

export function currencyOptionLabel(currency: string, separator = ' · '): string {
  const definition = currencyDefinition(currency);
  return `${definition.code}${separator}${definition.label}`;
}

export function currencyOptionIcon(currency: string) {
  return resolveAppIconName(currencyDefinition(currency).icon, 'currency-usd');
}

export function optionLabel<TValue extends string>(
  options: readonly OptionListItem<TValue>[],
  value: TValue,
): string {
  return options.find((option) => option.value === value)?.label ?? value;
}

export function optionTitle(option: OptionListItem): string {
  return option.description ? `${option.label} - ${option.description}` : option.label;
}
