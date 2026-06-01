import { formatMoney, normalizeCurrencyCode, toMinor } from '@1wallet/domain/money';
import { tokens } from '@1wallet/ui';
import { useEffect, useMemo, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { Button, HelperText, Text, TextInput, useTheme } from 'react-native-paper';
import {
    buildEnabledCurrencyOptions,
    currencyOptionIcon,
    currencyOptionLabel,
} from '../../currencyOptions';
import { InfoRow, PremiumTextInput } from '../AppKit';
import { OptionListOverlay } from '../OptionListOverlay';
import {
    numberFromCurrencyText,
    resolveRecordCurrencyDraft,
    trimFxRateValue,
} from './recordCurrencyMath';
import { RecordSelectorRow } from './RecordSelectorRow';

export function RecordCurrencyFields({
  accountCurrency,
  baseCurrency,
  enabledCurrencies,
  locale,
  postedAmount,
  onPostedAmountChange,
  originalCurrency,
  onOriginalCurrencyChange,
  originalAmount,
  onOriginalAmountChange,
  fxRate,
  onFxRateChange,
  suggestedRate,
}: {
  accountCurrency?: string;
  baseCurrency: string;
  enabledCurrencies: string[];
  locale: string;
  postedAmount: string;
  onPostedAmountChange: (value: string) => void;
  originalCurrency: string;
  onOriginalCurrencyChange: (value: string) => void;
  originalAmount: string;
  onOriginalAmountChange: (value: string) => void;
  fxRate: string;
  onFxRateChange: (value: string) => void;
  suggestedRate?: number;
}) {
  const theme = useTheme();
  const [pickerVisible, setPickerVisible] = useState(false);
  const postedCurrency = normalizeCurrencyCode(accountCurrency ?? baseCurrency);
  const purchaseCurrency = normalizeCurrencyCode(originalCurrency || postedCurrency);
  const isForeign = purchaseCurrency !== postedCurrency;
  const postedNumber = numberFromCurrencyText(postedAmount);
  const rateNumber = numberFromCurrencyText(fxRate);
  const conversion = useMemo(
    () =>
      resolveRecordCurrencyDraft({
        originalAmountText: originalAmount,
        purchaseCurrency,
        postedCurrency,
        fxRateText: fxRate,
        suggestedRate,
      }),
    [fxRate, originalAmount, postedCurrency, purchaseCurrency, suggestedRate],
  );
  const canApply = Boolean(conversion.postedAmountText);
  const options = useMemo(
    () =>
      buildEnabledCurrencyOptions(enabledCurrencies, [
        purchaseCurrency,
        postedCurrency,
        baseCurrency,
      ]),
    [baseCurrency, enabledCurrencies, postedCurrency, purchaseCurrency],
  );

  useEffect(() => {
    if (!conversion.postedAmountText || conversion.postedAmountMinor === undefined) return;
    const currentPostedMinor = toMinor(numberFromCurrencyText(postedAmount), postedCurrency);
    if (currentPostedMinor !== conversion.postedAmountMinor) {
      onPostedAmountChange(conversion.postedAmountText);
    }
  }, [
    conversion.postedAmountMinor,
    conversion.postedAmountText,
    onPostedAmountChange,
    postedAmount,
    postedCurrency,
  ]);

  const applySuggestedRate = () => {
    if (!suggestedRate || suggestedRate <= 0) return;
    onFxRateChange(trimFxRateValue(suggestedRate));
  };

  const applyConversion = () => {
    if (!canApply) return;
    if (conversion.fxRate && rateNumber <= 0) {
      onFxRateChange(trimFxRateValue(conversion.fxRate));
    }
    if (conversion.postedAmountText) onPostedAmountChange(conversion.postedAmountText);
  };

  return (
    <View style={styles.wrapper}>
      <RecordSelectorRow
        icon={currencyOptionIcon(purchaseCurrency)}
        label="Purchase currency"
        value={currencyOptionLabel(purchaseCurrency, ' - ')}
        supporting={
          isForeign
            ? `Original amount, saved against ${postedCurrency}`
            : `Same as ${postedCurrency} account`
        }
        onPress={() => setPickerVisible(true)}
      />

      {isForeign ? (
        <View style={styles.foreignFields}>
          <View style={styles.fieldRow}>
            <PremiumTextInput
              label={`Original amount (${purchaseCurrency})`}
              value={originalAmount}
              onChangeText={onOriginalAmountChange}
              keyboardType="decimal-pad"
              style={styles.field}
              left={<TextInput.Icon icon="cash" />}
            />
            <PremiumTextInput
              label={`1 ${purchaseCurrency} = ${postedCurrency}`}
              value={fxRate}
              onChangeText={onFxRateChange}
              keyboardType="decimal-pad"
              style={styles.field}
              left={<TextInput.Icon icon="swap-horizontal" />}
            />
          </View>
          <View style={styles.buttonRow}>
            <Button
              mode="outlined"
              icon="refresh"
              disabled={!suggestedRate}
              onPress={applySuggestedRate}
            >
              Latest rate
            </Button>
            <Button
              mode="contained-tonal"
              icon="calculator"
              disabled={!canApply}
              onPress={applyConversion}
            >
              Use conversion
            </Button>
          </View>
          <InfoRow
            icon="credit-card-outline"
            label="Posted to account"
            value={
              conversion.needsRate
                ? 'Needs exchange rate'
                : conversion.postedMoney
                  ? formatMoney(conversion.postedMoney, locale)
                  : formatPostedAmount(postedNumber, postedCurrency, locale)
            }
          />
          <HelperText type="error" visible={conversion.needsRate}>
            Enter a {purchaseCurrency} to {postedCurrency} rate before saving this record.
          </HelperText>
          {baseCurrency !== postedCurrency ? (
            <HelperText type="info" visible>
              Reports still use your default currency: {baseCurrency}.
            </HelperText>
          ) : null}
        </View>
      ) : (
        <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
          The record amount is saved directly in {postedCurrency}. Choose a different purchase
          currency when the card or bank posts one currency but the merchant charged another.
        </Text>
      )}

      <OptionListOverlay
        visible={pickerVisible}
        title="Purchase currency"
        options={options}
        selectedValue={purchaseCurrency}
        searchPlaceholder="Search currencies"
        onDismiss={() => setPickerVisible(false)}
        onSelect={(option) => {
          onOriginalCurrencyChange(option.value);
          setPickerVisible(false);
        }}
      />
    </View>
  );
}

function formatPostedAmount(amount: number, currency: string, locale: string): string {
  return formatMoney({ amountMinor: toMinor(amount, currency), currency }, locale);
}

const styles = StyleSheet.create({
  wrapper: { gap: tokens.space.sm },
  foreignFields: { gap: tokens.space.sm },
  fieldRow: { flexDirection: 'row', gap: tokens.space.sm },
  field: { flex: 1 },
  buttonRow: { flexDirection: 'row', flexWrap: 'wrap', gap: tokens.space.sm },
});
