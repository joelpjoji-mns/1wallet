'use client';

import { formatMoney, toMinor } from '@1wallet/domain/money';
import type { AccountType } from '@1wallet/domain/types';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import type { FormEvent, ReactElement } from 'react';
import { useState } from 'react';
import { Card } from '../../components/Card';
import { Button } from '../../components/Button';
import { Input, Select } from '../../components/Input';

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
  const [currency, setCurrency] = useState(state?.preferences?.baseCurrency || 'USD');
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
    <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.xl, width: '100%' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <h1 style={{ margin: 0, fontSize: 32, fontWeight: 700 }}>Accounts</h1>
          <p style={{ margin: 0, color: 'var(--color-on-surface-variant)' }}>
            Manage your accounts and balances.
          </p>
        </div>
      </div>

      <div
        style={{
          display: 'grid',
          gridTemplateColumns: '1fr',
          gap: tokens.space.lg,
          maxWidth: 1000,
        }}
      >
        <Card title="Add Account">
          <form
            onSubmit={submit}
            style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
              gap: tokens.space.md,
              alignItems: 'end',
            }}
          >
            <Input
              label="Account Name"
              placeholder="e.g. Chase Checking"
              value={name}
              onChange={(e) => setName(e.target.value)}
            />
            <Select
              label="Type"
              value={type}
              onChange={(e) => setType(e.target.value as AccountType)}
            >
              {TYPES.map((t) => (
                <option key={t} value={t}>
                  {t.replace('_', ' ').replace(/\b\w/g, (l) => l.toUpperCase())}
                </option>
              ))}
            </Select>
            <Select label="Currency" value={currency} onChange={(e) => setCurrency(e.target.value)}>
              {CURRENCIES.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </Select>
            <Input
              label="Opening Balance"
              placeholder="0.00"
              value={opening}
              onChange={(e) => setOpening(e.target.value)}
              inputMode="decimal"
            />
            <Button type="submit" style={{ height: 44 }}>
              Add Account
            </Button>
          </form>
        </Card>

        <Card title={`Accounts (${state.accounts.filter((a) => !a.isArchived).length})`}>
          {state.accounts.length === 0 ? (
            <p style={{ color: 'var(--color-on-surface-variant)' }}>No accounts yet.</p>
          ) : (
            <div style={{ overflowX: 'auto' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse', minWidth: 600 }}>
                <thead>
                  <tr
                    style={{
                      textAlign: 'left',
                      color: 'var(--color-on-surface-variant)',
                      borderBottom: '1px solid var(--color-outline-variant)',
                    }}
                  >
                    <th style={{ padding: tokens.space.sm }}>Name</th>
                    <th style={{ padding: tokens.space.sm }}>Type</th>
                    <th style={{ padding: tokens.space.sm, textAlign: 'right' }}>Balance</th>
                    <th style={{ padding: tokens.space.sm, textAlign: 'center' }}>In Totals</th>
                    <th style={{ padding: tokens.space.sm, textAlign: 'center' }}>In Net Worth</th>
                    <th style={{ padding: tokens.space.sm }} />
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
                          borderBottom: '1px solid var(--color-surface-high)',
                          opacity: a.isArchived ? 0.5 : 1,
                        }}
                      >
                        <td style={{ padding: tokens.space.sm, fontWeight: 500 }}>{a.name}</td>
                        <td style={{ padding: tokens.space.sm, textTransform: 'capitalize' }}>
                          {a.type.replace('_', ' ')}
                        </td>
                        <td
                          style={{
                            padding: tokens.space.sm,
                            textAlign: 'right',
                            fontVariantNumeric: 'tabular-nums',
                            fontWeight: 600,
                          }}
                        >
                          {formatMoney(b, state.preferences.locale)}
                          {b.currency !== displayBalance.currency ? (
                            <div
                              style={{
                                color: 'var(--color-on-surface-variant)',
                                fontSize: 12,
                                fontWeight: 400,
                              }}
                            >
                              {formatMoney(displayBalance, state.preferences.locale)}
                            </div>
                          ) : null}
                        </td>
                        <td style={{ padding: tokens.space.sm, textAlign: 'center' }}>
                          <input
                            type="checkbox"
                            checked={a.includeInTotals}
                            onChange={(e) =>
                              editAccount(a.id, { includeInTotals: e.target.checked })
                            }
                            style={{
                              width: 18,
                              height: 18,
                              cursor: 'pointer',
                              accentColor: 'var(--color-primary)',
                            }}
                          />
                        </td>
                        <td style={{ padding: tokens.space.sm, textAlign: 'center' }}>
                          <input
                            type="checkbox"
                            checked={a.includeInNetWorth}
                            onChange={(e) =>
                              editAccount(a.id, { includeInNetWorth: e.target.checked })
                            }
                            style={{
                              width: 18,
                              height: 18,
                              cursor: 'pointer',
                              accentColor: 'var(--color-primary)',
                            }}
                          />
                        </td>
                        <td style={{ padding: tokens.space.sm, textAlign: 'right' }}>
                          <Button
                            variant="ghost"
                            onClick={() => removeAccount(a.id)}
                            style={{
                              color: a.isArchived ? 'var(--color-primary)' : 'var(--color-error)',
                              padding: '4px 8px',
                            }}
                          >
                            {a.isArchived ? 'Restore' : 'Archive'}
                          </Button>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      </div>
    </div>
  );
}
