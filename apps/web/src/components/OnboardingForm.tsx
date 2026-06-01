'use client';

import { toMinor } from '@1wallet/domain/money';
import type { AccountType } from '@1wallet/domain/types';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import type { CSSProperties, FormEvent, ReactElement } from 'react';
import { useState } from 'react';

const TYPES: AccountType[] = ['cash', 'bank', 'credit_card', 'wallet', 'loan', 'investment'];
const CURRENCIES = ['INR', 'USD', 'EUR', 'GBP', 'AED', 'SGD'];
const scheme = tokens.color.md3.light;

export function OnboardingForm(): ReactElement {
  const { mutate } = useLedger();
  const [name, setName] = useState('Main account');
  const [type, setType] = useState<AccountType>('bank');
  const [currency, setCurrency] = useState('INR');
  const [opening, setOpening] = useState('0');

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    const amount = Number(opening.replace(/,/g, '')) || 0;
    await mutate((s) => {
      s.preferences.baseCurrency = currency;
      s.accounts.push({
        id: crypto.randomUUID(),
        userId: s.userId,
        name,
        type,
        currency,
        openingBalance: { amountMinor: toMinor(amount, currency), currency },
        openingDate: new Date().toISOString().slice(0, 10),
        includeInTotals: true,
        includeInBudgets: true,
        includeInReports: true,
        includeInNetWorth: true,
        showOnHome: true,
        isArchived: false,
        isDefault: true,
        sortOrder: 0,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      });
    });
  };

  return (
    <form
      onSubmit={submit}
      style={{
        maxWidth: 480,
        display: 'grid',
        gap: tokens.space.md,
        background: scheme.surfaceContainerLowest,
        border: `1px solid ${scheme.outlineVariant}`,
        borderRadius: tokens.radius.lg,
        padding: tokens.space.xl,
        boxShadow: '0 1px 2px rgba(0,0,0,0.08)',
      }}
    >
      <h1 style={{ margin: 0 }}>Welcome to 1wallet</h1>
      <p style={{ color: scheme.onSurfaceVariant, margin: 0 }}>Add your first account.</p>

      <label>
        Name
        <input value={name} onChange={(e) => setName(e.target.value)} style={inputStyle} required />
      </label>

      <label>
        Type
        <select
          value={type}
          onChange={(e) => setType(e.target.value as AccountType)}
          style={inputStyle}
        >
          {TYPES.map((t) => (
            <option key={t} value={t}>
              {t.replace('_', ' ')}
            </option>
          ))}
        </select>
      </label>

      <label>
        Currency
        <select value={currency} onChange={(e) => setCurrency(e.target.value)} style={inputStyle}>
          {CURRENCIES.map((c) => (
            <option key={c} value={c}>
              {c}
            </option>
          ))}
        </select>
      </label>

      <label>
        Opening balance
        <input
          value={opening}
          onChange={(e) => setOpening(e.target.value)}
          style={inputStyle}
          inputMode="decimal"
        />
      </label>

      <button type="submit" style={btnStyle}>
        Continue
      </button>
    </form>
  );
}

const inputStyle: CSSProperties = {
  display: 'block',
  width: '100%',
  marginTop: 4,
  padding: tokens.space.md,
  fontSize: tokens.font.size.md,
  borderRadius: tokens.radius.md,
  border: `1px solid ${scheme.outline}`,
  background: scheme.surfaceContainerLow,
  color: scheme.onSurface,
};

const btnStyle: CSSProperties = {
  padding: `${tokens.space.md}px ${tokens.space.lg}px`,
  background: scheme.primary,
  color: scheme.onPrimary,
  fontWeight: tokens.font.weight.semibold,
  border: 'none',
  borderRadius: tokens.radius.md,
  cursor: 'pointer',
};
