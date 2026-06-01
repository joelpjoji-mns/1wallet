'use client';

import { formatMoney, toMinor } from '@1wallet/domain/money';
import type { AccountType } from '@1wallet/domain/types';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import type { CSSProperties, FormEvent, ReactElement } from 'react';
import { useState } from 'react';
import { Card } from '../../components/Card';

const TYPES: AccountType[] = [
  'cash',
  'bank',
  'credit_card',
  'wallet',
  'loan',
  'investment',
  'savings_goal',
  'other',
];
const CURRENCIES = ['INR', 'USD', 'EUR', 'GBP', 'AED', 'SGD', 'JPY'];

export default function AccountsPage(): ReactElement {
  const { state, ready, addAccount, editAccount, removeAccount, selectors } = useLedger();
  const [name, setName] = useState('');
  const [type, setType] = useState<AccountType>('bank');
  const [currency, setCurrency] = useState(state.preferences.baseCurrency);
  const [opening, setOpening] = useState('0');

  if (!ready) return <p>Loading…</p>;
  const viewCurrency = selectors.displayCurrency(state);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (!name.trim()) return;
    const n = Number(opening.replace(/,/g, '')) || 0;
    await addAccount({
      name: name.trim(),
      type,
      currency,
      openingBalanceMinor: toMinor(n, currency),
    });
    setName('');
    setOpening('0');
  };

  return (
    <div style={{ display: 'grid', gap: tokens.space.lg, maxWidth: 900 }}>
      <Card title="Add account">
        <form
          onSubmit={submit}
          style={{
            display: 'grid',
            gridTemplateColumns: '2fr 1fr 1fr 1fr auto',
            gap: tokens.space.sm,
          }}
        >
          <input
            placeholder="Name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            style={inputStyle}
          />
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
          <select value={currency} onChange={(e) => setCurrency(e.target.value)} style={inputStyle}>
            {CURRENCIES.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
          <input
            placeholder="Opening"
            value={opening}
            onChange={(e) => setOpening(e.target.value)}
            inputMode="decimal"
            style={inputStyle}
          />
          <button type="submit" style={btnStyle}>
            Add
          </button>
        </form>
      </Card>

      <Card title={`Accounts (${state.accounts.filter((a) => !a.isArchived).length})`}>
        {state.accounts.length === 0 ? (
          <p style={{ color: tokens.color.inkMuted }}>No accounts yet.</p>
        ) : (
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            <thead>
              <tr style={{ textAlign: 'left', color: tokens.color.inkMuted }}>
                <th>Name</th>
                <th>Type</th>
                <th>Currency</th>
                <th style={{ textAlign: 'right' }}>Balance</th>
                <th>Totals</th>
                <th>Net worth</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {state.accounts.map((a) => {
                const b = selectors.accountBalance(state, a.id);
                const displayBalance = selectors.convertMoneyForDisplay(state, b, viewCurrency);
                return (
                  <tr
                    key={a.id}
                    style={{
                      borderTop: `1px solid ${tokens.color.border}`,
                      opacity: a.isArchived ? 0.5 : 1,
                    }}
                  >
                    <td>{a.name}</td>
                    <td>{a.type.replace('_', ' ')}</td>
                    <td>{a.currency}</td>
                    <td style={{ textAlign: 'right', fontVariantNumeric: 'tabular-nums' }}>
                      {formatMoney(b, state.preferences.locale)}
                      {b.currency !== displayBalance.currency ? (
                        <div style={{ color: tokens.color.inkMuted, fontSize: 12 }}>
                          {formatMoney(displayBalance, state.preferences.locale)}
                        </div>
                      ) : null}
                    </td>
                    <td>
                      <input
                        type="checkbox"
                        checked={a.includeInTotals}
                        onChange={(e) => editAccount(a.id, { includeInTotals: e.target.checked })}
                      />
                    </td>
                    <td>
                      <input
                        type="checkbox"
                        checked={a.includeInNetWorth}
                        onChange={(e) => editAccount(a.id, { includeInNetWorth: e.target.checked })}
                      />
                    </td>
                    <td>
                      <button
                        onClick={() => removeAccount(a.id)}
                        style={{
                          color: tokens.color.overspend,
                          background: 'transparent',
                          border: 'none',
                          cursor: 'pointer',
                        }}
                      >
                        {a.isArchived ? 'remove' : 'archive'}
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </Card>
    </div>
  );
}

const inputStyle: CSSProperties = {
  padding: tokens.space.md,
  fontSize: tokens.font.size.md,
  borderRadius: tokens.radius.md,
  border: `1px solid ${tokens.color.border}`,
  background: tokens.color.surface,
};

const btnStyle: CSSProperties = {
  padding: `${tokens.space.md}px ${tokens.space.lg}px`,
  background: tokens.color.primary,
  color: '#fff',
  fontWeight: 600,
  border: 'none',
  borderRadius: tokens.radius.md,
  cursor: 'pointer',
};
