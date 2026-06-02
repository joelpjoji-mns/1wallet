import { currencyDefinition, formatMoney, toMinor } from '@1wallet/domain/money';
import {
    enabledCurrencies,
    exchangeRateIsStale,
    rateBetween,
    rateRecordForPair,
    setBaseCurrency as setLedgerBaseCurrency,
    setDisplayCurrency as setLedgerDisplayCurrency,
    setRate,
} from '@1wallet/ledger/services';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { useMemo, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { Button, Divider, Snackbar, Text, useTheme } from 'react-native-paper';
import { AppScreen, InfoRow, PremiumTextInput, SectionCard } from '../src/components/AppKit';
import {
    OptionListOverlay,
    OptionSelectorRow,
    type OptionListItem,
} from '../src/components/OptionListOverlay';
import {
    buildSupportedCurrencyOptions,
    currencyOptionIcon,
    currencyOptionLabel,
} from '../src/currencyOptions';

type CurrencyPicker = 'base' | 'display' | 'add' | null;

export default function Currencies() {
  const theme = useTheme();
  const { state, mutate, setDisplayCurrency, addCurrency, removeCurrency, refreshExchangeRates } =
    useLedger();
  const [picker, setPicker] = useState<CurrencyPicker>(null);
  const [editingCurrency, setEditingCurrency] = useState<string | null>(null);
  const [rateDraft, setRateDraft] = useState('');
  const [refreshing, setRefreshing] = useState(false);
  const [snackbar, setSnackbar] = useState<string | null>(null);

  const baseCurrency = state.preferences.baseCurrency;
  const viewCurrency = state.preferences.displayCurrency ?? baseCurrency;
  const currencies = useMemo(() => enabledCurrencies(state), [state]);
  const currencyOptions = useMemo<OptionListItem[]>(
    () => buildSupportedCurrencyOptions([baseCurrency, viewCurrency]),
    [baseCurrency, viewCurrency],
  );
  const addOptions = useMemo(
    () =>
      currencyOptions.map((option) => ({
        ...option,
        disabled: currencies.includes(option.value),
      })),
    [currencies, currencyOptions],
  );
  const displayOptions = useMemo(
    () =>
      currencyOptions.map((option) => ({
        ...option,
        disabled: !currencies.includes(option.value),
      })),
    [currencies, currencyOptions],
  );
  const rateCurrencies = useMemo(
    () => currencies.filter((currency) => currency !== baseCurrency),
    [baseCurrency, currencies],
  );

  const chooseBaseCurrency = async (currency: string) => {
    await mutate(
      (draft) => {
        setLedgerBaseCurrency(draft, currency);
        setLedgerDisplayCurrency(draft, currency);
      },
      { slices: ['preferences', 'transactions'] },
    );
    setSnackbar(`Default currency set to ${currency}`);
  };

  const addEnabledCurrency = async (currency: string) => {
    await addCurrency(currency);
    setSnackbar(`${currency} added`);
  };

  const chooseDisplayCurrency = async (currency: string) => {
    await setDisplayCurrency(currency);
    setSnackbar(`Display currency set to ${currency}`);
  };

  const remove = async (currency: string) => {
    await removeCurrency(currency);
    setSnackbar(`${currency} removed if it is not in use`);
  };

  const beginEditRate = (currency: string) => {
    setEditingCurrency(currency);
    setRateDraft(trimRate(rateBetween(state, currency, baseCurrency)));
  };

  const saveManualRate = async () => {
    if (!editingCurrency) return;
    const rate = Number(rateDraft.replace(/,/g, '').trim());
    if (!Number.isFinite(rate) || rate <= 0) {
      setSnackbar('Enter a valid rate');
      return;
    }
    const asOfDate = new Date().toISOString().slice(0, 10);
    const updatedAt = new Date().toISOString();
    await mutate(
      (draft) => {
        setRate(draft, editingCurrency, baseCurrency, rate, asOfDate, {
          source: 'manual',
          provider: 'manual',
          updatedAt,
        });
      },
      { slices: ['exchangeRates'] },
    );
    setEditingCurrency(null);
    setSnackbar('Manual rate saved');
  };

  const refreshRates = async () => {
    const targets = rateCurrencies;
    if (targets.length === 0) {
      setSnackbar('Add another currency first');
      return;
    }
    setRefreshing(true);
    try {
      const result = await refreshExchangeRates();
      setSnackbar(
        result.savedRates > 0
          ? `Exchange rates refreshed for ${result.savedRates} currencies`
          : 'No exchange rates to refresh',
      );
    } catch (error) {
      setSnackbar(`Refresh failed: ${(error as Error).message}`);
    } finally {
      setRefreshing(false);
    }
  };

  return (
    <>
      <AppScreen
        title="Currencies"
        back={false}
        drawer
        subtitle="Maintain your default currency, enabled currencies, and exchange rates."
        actions={[{ icon: 'refresh', label: 'Refresh rates', onPress: () => void refreshRates() }]}
      >
        <SectionCard
          title="Default currency"
          subtitle="Reports and stored base totals use this currency."
        >
          <OptionSelectorRow
            label="Default"
            value={currencyOptionLabel(baseCurrency)}
            description="Changing this rebases saved transaction totals"
            icon={currencyOptionIcon(baseCurrency)}
            onPress={() => setPicker('base')}
          />
          <OptionSelectorRow
            label="Display"
            value={currencyOptionLabel(viewCurrency)}
            description="Switches app values without changing saved records"
            icon={currencyOptionIcon(viewCurrency)}
            onPress={() => setPicker('display')}
          />
          <InfoRow
            icon="clock-outline"
            label="Last refreshed"
            value={formatRefreshTime(state.preferences.fx?.lastRefreshedAt)}
          />
        </SectionCard>

        <SectionCard
          title="Enabled currencies"
          subtitle="Use these in accounts, records, imports, and exchange-rate refreshes."
          actionLabel="Add"
          actionIcon="plus"
          onAction={() => setPicker('add')}
        >
          {currencies.map((currency, index) => {
            const definition = currencyDefinition(currency);
            const isBase = currency === baseCurrency;
            return (
              <View key={currency}>
                <View style={styles.currencyRow}>
                  <View style={styles.currencyCopy}>
                    <Text variant="titleSmall">{currencyOptionLabel(currency)}</Text>
                    <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                      {definition.symbol} · {definition.label}
                    </Text>
                  </View>
                  <Button
                    compact
                    mode={isBase ? 'contained-tonal' : 'text'}
                    disabled={isBase}
                    onPress={() => void remove(currency)}
                  >
                    {isBase ? 'Default' : 'Remove'}
                  </Button>
                </View>
                {index < currencies.length - 1 ? <Divider /> : null}
              </View>
            );
          })}
        </SectionCard>

        <SectionCard
          title="Exchange rates"
          subtitle={`Rates against ${baseCurrency}. Edit any rate if the bank posted a different value.`}
        >
          {rateCurrencies.length === 0 ? (
            <Text variant="bodyMedium" style={{ color: theme.colors.onSurfaceVariant }}>
              Add another currency to track exchange rates.
            </Text>
          ) : (
            rateCurrencies.map((currency, index) => {
              const rateRecord = rateRecordForPair(state, currency, baseCurrency);
              const rate = rateBetween(state, currency, baseCurrency);
              const stale = exchangeRateIsStale(rateRecord);
              const isEditing = editingCurrency === currency;
              return (
                <View key={currency}>
                  <View style={styles.rateRow}>
                    <View style={styles.currencyCopy}>
                      <Text variant="titleSmall">1 {currency}</Text>
                      <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                        {formatMoney(
                          { amountMinor: toMinor(rate, baseCurrency), currency: baseCurrency },
                          state.preferences.locale,
                        )}
                      </Text>
                      <Text
                        variant="labelSmall"
                        style={{
                          color: stale ? theme.colors.secondary : theme.colors.onSurfaceVariant,
                        }}
                      >
                        {rateRecord
                          ? `${rateRecord.provider ?? 'manual'} · ${rateRecord.asOfDate}${stale ? ' · stale' : ''}`
                          : 'No saved rate yet'}
                      </Text>
                    </View>
                    <Button compact mode="contained-tonal" onPress={() => beginEditRate(currency)}>
                      Edit
                    </Button>
                  </View>
                  {isEditing ? (
                    <View style={styles.editRateRow}>
                      <PremiumTextInput
                        label={`1 ${currency} in ${baseCurrency}`}
                        value={rateDraft}
                        onChangeText={setRateDraft}
                        keyboardType="decimal-pad"
                        style={styles.rateInput}
                      />
                      <Button mode="contained" onPress={() => void saveManualRate()}>
                        Save
                      </Button>
                    </View>
                  ) : null}
                  {index < rateCurrencies.length - 1 ? <Divider /> : null}
                </View>
              );
            })
          )}
          <Button
            mode="contained-tonal"
            icon="refresh"
            loading={refreshing}
            disabled={refreshing}
            onPress={() => void refreshRates()}
          >
            Refresh rates
          </Button>
        </SectionCard>
      </AppScreen>

      <OptionListOverlay
        visible={picker === 'base'}
        title="Default currency"
        options={currencyOptions}
        selectedValue={baseCurrency}
        searchPlaceholder="Search currencies"
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          setPicker(null);
          void chooseBaseCurrency(option.value);
        }}
      />
      <OptionListOverlay
        visible={picker === 'display'}
        title="Display currency"
        options={displayOptions}
        selectedValue={viewCurrency}
        searchPlaceholder="Search enabled currencies"
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          if (option.disabled) return;
          setPicker(null);
          void chooseDisplayCurrency(option.value);
        }}
      />
      <OptionListOverlay
        visible={picker === 'add'}
        title="Add currency"
        options={addOptions}
        searchPlaceholder="Search currencies"
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          if (option.disabled) return;
          setPicker(null);
          void addEnabledCurrency(option.value);
        }}
      />
      <Snackbar visible={Boolean(snackbar)} onDismiss={() => setSnackbar(null)} duration={2400}>
        {snackbar}
      </Snackbar>
    </>
  );
}

function formatRefreshTime(value?: string): string {
  if (!value) return 'Not refreshed yet';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return 'Not refreshed yet';
  return date.toLocaleString();
}

function trimRate(value: number): string {
  return String(Number(value.toFixed(6)));
}

const styles = StyleSheet.create({
  currencyRow: {
    minHeight: 64,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.md,
    paddingVertical: tokens.space.sm,
  },
  rateRow: {
    minHeight: 76,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.md,
    paddingVertical: tokens.space.sm,
  },
  currencyCopy: { flex: 1, minWidth: 0, gap: 2 },
  editRateRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.sm,
    paddingBottom: tokens.space.sm,
  },
  rateInput: { flex: 1 },
});
