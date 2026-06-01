'use client';

import {
    SUPPORTED_CURRENCIES,
    currencyDefinition,
    formatMoney,
    toMinor,
} from '@1wallet/domain/money';
import {
    enabledCurrencies,
    exchangeRateIsStale,
    latestExchangeRate,
    rateBetween,
    setRate,
} from '@1wallet/ledger/services';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { useState, type ReactElement } from 'react';
import { Card } from '../../components/Card';

export default function CurrenciesPage(): ReactElement {
  const {
    state,
    ready,
    mutate,
    setBaseCurrency,
    setDisplayCurrency,
    addCurrency,
    removeCurrency,
    refreshExchangeRates,
  } = useLedger();
  const [editingCurrency, setEditingCurrency] = useState('');
  const [rateDraft, setRateDraft] = useState('');
  const [message, setMessage] = useState('');
  const [refreshing, setRefreshing] = useState(false);

  if (!ready) return <p>Loading...</p>;

  const baseCurrency = state.preferences.baseCurrency;
  const viewCurrency = state.preferences.displayCurrency ?? baseCurrency;
  const currencies = enabledCurrencies(state);
  const rateCurrencies = currencies.filter((currency) => currency !== baseCurrency);

  const saveManualRate = async () => {
    if (!editingCurrency) return;
    const rate = Number(rateDraft.replace(/,/g, '').trim());
    if (!Number.isFinite(rate) || rate <= 0) {
      setMessage('Enter a valid rate.');
      return;
    }
    const now = new Date().toISOString();
    await mutate((draft) => {
      setRate(draft, editingCurrency, baseCurrency, rate, now.slice(0, 10), {
        provider: 'manual',
        source: 'manual',
        updatedAt: now,
      });
    });
    setEditingCurrency('');
    setMessage('Manual rate saved.');
  };

  const refreshRates = async () => {
    if (rateCurrencies.length === 0) {
      setMessage('Add another currency first.');
      return;
    }
    setRefreshing(true);
    try {
      const result = await refreshExchangeRates();
      setMessage(
        result.savedRates > 0
          ? `Exchange rates refreshed for ${result.savedRates} currencies.`
          : 'No exchange rates to refresh.',
      );
    } catch (error) {
      setMessage(`Refresh failed: ${(error as Error).message}`);
    } finally {
      setRefreshing(false);
    }
  };

  return (
    <div style={{ display: 'grid', gap: tokens.space.lg, maxWidth: 820 }}>
      <h1 style={{ margin: 0 }}>Currencies</h1>
      <p style={{ marginTop: -tokens.space.sm, color: tokens.color.inkMuted }}>
        Reports currency, display currency, enabled currencies, exchange rates, and manual
        corrections.
      </p>

      {message ? <p style={{ color: tokens.color.inkMuted }}>{message}</p> : null}

      <Card title="Default and display currencies">
        <label style={{ display: 'grid', gap: tokens.space.xs }}>
          Reports currency
          <select
            value={baseCurrency}
            onChange={(event) => void setBaseCurrency(event.target.value)}
            style={selectStyle}
          >
            {SUPPORTED_CURRENCIES.map((currency) => (
              <option key={currency.code} value={currency.code}>
                {currency.code} - {currency.label}
              </option>
            ))}
          </select>
        </label>
        <label style={{ display: 'grid', gap: tokens.space.xs }}>
          Display currency
          <select
            value={viewCurrency}
            onChange={(event) => void setDisplayCurrency(event.target.value)}
            style={selectStyle}
          >
            {currencies.map((currency) => (
              <option key={currency} value={currency}>
                {currency} - {currencyDefinition(currency).label}
              </option>
            ))}
          </select>
        </label>
        <p style={{ color: tokens.color.inkMuted }}>
          Reports currency rebases saved report totals. Display currency only changes visible
          values.
        </p>
        <p style={{ color: tokens.color.inkMuted }}>
          Last refreshed: {formatRefreshTime(state.preferences.fx?.lastRefreshedAt)}
        </p>
      </Card>

      <Card title="Enabled currencies">
        <div style={{ display: 'grid', gap: tokens.space.sm }}>
          {currencies.map((currency) => (
            <div key={currency} style={rowStyle}>
              <div>
                <strong>{currency}</strong>
                <div style={{ color: tokens.color.inkMuted }}>
                  {currencyDefinition(currency).label}
                </div>
              </div>
              <button
                disabled={currency === baseCurrency}
                onClick={() => void removeCurrency(currency)}
                style={buttonStyle(currency === baseCurrency)}
              >
                {currency === baseCurrency ? 'Default' : 'Remove'}
              </button>
            </div>
          ))}
          <label style={{ display: 'grid', gap: tokens.space.xs }}>
            Add currency
            <select
              defaultValue=""
              onChange={(event) => {
                if (!event.target.value) return;
                void addCurrency(event.target.value);
                event.currentTarget.value = '';
              }}
              style={selectStyle}
            >
              <option value="">Choose currency</option>
              {SUPPORTED_CURRENCIES.map((currency) => (
                <option
                  key={currency.code}
                  value={currency.code}
                  disabled={currencies.includes(currency.code)}
                >
                  {currency.code} - {currency.label}
                </option>
              ))}
            </select>
          </label>
        </div>
      </Card>

      <Card title="Exchange rates">
        <div style={{ display: 'grid', gap: tokens.space.md }}>
          {rateCurrencies.map((currency) => {
            const rate = rateBetween(state, currency, baseCurrency);
            const record =
              latestExchangeRate(state, currency, baseCurrency) ??
              latestExchangeRate(state, baseCurrency, currency);
            const stale = exchangeRateIsStale(record);
            const editing = editingCurrency === currency;
            return (
              <div key={currency} style={{ display: 'grid', gap: tokens.space.sm }}>
                <div style={rowStyle}>
                  <div>
                    <strong>1 {currency}</strong>
                    <div>
                      {formatMoney(
                        { amountMinor: toMinor(rate, baseCurrency), currency: baseCurrency },
                        state.preferences.locale,
                      )}
                    </div>
                    <div style={{ color: stale ? tokens.color.warning : tokens.color.inkMuted }}>
                      {record
                        ? `${record.provider ?? 'manual'} - ${record.asOfDate}${stale ? ' - stale' : ''}`
                        : 'No saved rate yet'}
                    </div>
                  </div>
                  <button
                    onClick={() => {
                      setEditingCurrency(currency);
                      setRateDraft(String(Number(rate.toFixed(6))));
                    }}
                    style={buttonStyle(false)}
                  >
                    Edit
                  </button>
                </div>
                {editing ? (
                  <div style={{ display: 'flex', gap: tokens.space.sm }}>
                    <input
                      value={rateDraft}
                      onChange={(event) => setRateDraft(event.target.value)}
                      style={{ ...selectStyle, flex: 1 }}
                    />
                    <button onClick={() => void saveManualRate()} style={buttonStyle(false)}>
                      Save
                    </button>
                  </div>
                ) : null}
              </div>
            );
          })}
          <button
            disabled={refreshing}
            onClick={() => void refreshRates()}
            style={buttonStyle(false)}
          >
            {refreshing ? 'Refreshing...' : 'Refresh rates'}
          </button>
        </div>
      </Card>
    </div>
  );
}

const selectStyle = {
  padding: tokens.space.sm,
  borderRadius: tokens.radius.md,
  border: `1px solid ${tokens.color.border}`,
  background: '#fff',
};

const rowStyle = {
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'space-between',
  gap: tokens.space.md,
  padding: `${tokens.space.sm}px 0`,
  borderBottom: `1px solid ${tokens.color.border}`,
};

function buttonStyle(disabled: boolean) {
  return {
    padding: `${tokens.space.sm}px ${tokens.space.md}px`,
    borderRadius: tokens.radius.md,
    border: 'none',
    background: disabled ? tokens.color.surface : tokens.color.primary,
    color: disabled ? tokens.color.inkMuted : '#fff',
    fontWeight: 700,
    cursor: disabled ? 'default' : 'pointer',
  };
}

function formatRefreshTime(value?: string): string {
  if (!value) return 'Not refreshed yet';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return 'Not refreshed yet';
  return date.toLocaleString();
}
