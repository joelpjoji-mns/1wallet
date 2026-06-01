'use client';

import { formatMoney, toMinor } from '@1wallet/domain/money';
import type { TransactionType } from '@1wallet/domain/types';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import type { CSSProperties, FormEvent, ReactElement } from 'react';
import { useMemo, useState } from 'react';
import { Card } from '../../components/Card';

const TX_TYPES: { id: TransactionType; label: string }[] = [
  { id: 'expense', label: 'Expense' },
  { id: 'income', label: 'Income' },
  { id: 'transfer', label: 'Transfer' },
];

export default function TransactionsPage(): ReactElement {
  const { state, ready, addTransaction, removeTransaction, selectors } = useLedger();
  const [type, setType] = useState<TransactionType>('expense');
  const [accountId, setAccountId] = useState<string>('');
  const [counterAccountId, setCounterAccountId] = useState<string>('');
  const [categoryId, setCategoryId] = useState<string>('');
  const [amount, setAmount] = useState('');
  const [notes, setNotes] = useState('');

  const txns = useMemo(
    () => (ready ? selectors.queryTransactions(state) : []),
    [ready, state, selectors],
  );
  const accounts = state.accounts.filter((a) => !a.isArchived);
  const acct = accounts.find((a) => a.id === accountId) ?? accounts[0];
  const categories = state.categories.filter(
    (c) => !c.isArchived && c.kind === (type === 'income' ? 'income' : 'expense'),
  );

  if (!ready) return <p>Loading…</p>;
  if (accounts.length === 0) return <p>Add an account first.</p>;
  const viewCurrency = selectors.displayCurrency(state);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    const n = Number(amount.replace(/,/g, ''));
    if (!n || n <= 0 || !acct) return;
    await addTransaction({
      type,
      accountId: acct.id,
      counterAccountId: type === 'transfer' ? counterAccountId || undefined : undefined,
      amountMinor: toMinor(n, acct.currency),
      currency: acct.currency,
      categoryId: type === 'transfer' ? undefined : categoryId || undefined,
      notes: notes || undefined,
      occurredAt: new Date().toISOString(),
    });
    setAmount('');
    setNotes('');
  };

  return (
    <div style={{ display: 'grid', gap: tokens.space.lg, maxWidth: 900 }}>
      <Card title="Add transaction">
        <form onSubmit={submit} style={{ display: 'grid', gap: tokens.space.sm }}>
          <div style={{ display: 'flex', gap: tokens.space.sm }}>
            {TX_TYPES.map((t) => (
              <button
                key={t.id}
                type="button"
                onClick={() => setType(t.id)}
                style={{
                  padding: `${tokens.space.sm}px ${tokens.space.md}px`,
                  borderRadius: tokens.radius.pill,
                  border: `1px solid ${type === t.id ? tokens.color.primary : tokens.color.border}`,
                  background: type === t.id ? tokens.color.primary : tokens.color.surface,
                  color: type === t.id ? '#fff' : tokens.color.ink,
                  cursor: 'pointer',
                }}
              >
                {t.label}
              </button>
            ))}
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: tokens.space.sm }}>
            <input
              placeholder="Amount"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              inputMode="decimal"
              style={inputStyle}
            />
            <select
              value={accountId || acct?.id || ''}
              onChange={(e) => setAccountId(e.target.value)}
              style={inputStyle}
            >
              {accounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name} ({a.currency})
                </option>
              ))}
            </select>
          </div>
          {type === 'transfer' ? (
            <select
              value={counterAccountId}
              onChange={(e) => setCounterAccountId(e.target.value)}
              style={inputStyle}
            >
              <option value="">To account…</option>
              {accounts
                .filter((a) => a.id !== (accountId || acct?.id))
                .map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name}
                  </option>
                ))}
            </select>
          ) : (
            <select
              value={categoryId}
              onChange={(e) => setCategoryId(e.target.value)}
              style={inputStyle}
            >
              <option value="">Category…</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          )}
          <input
            placeholder="Notes (optional)"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            style={inputStyle}
          />
          <button type="submit" style={btnStyle}>
            Save transaction
          </button>
        </form>
      </Card>

      <Card title={`Transactions (${txns.length})`}>
        {txns.length === 0 ? (
          <p style={{ color: tokens.color.inkMuted }}>No transactions yet.</p>
        ) : (
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            <thead>
              <tr style={{ textAlign: 'left', color: tokens.color.inkMuted }}>
                <th>Date</th>
                <th>Type</th>
                <th>Account</th>
                <th>Category</th>
                <th style={{ textAlign: 'right' }}>Amount</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {txns.slice(0, 200).map((t) => {
                const a = state.accounts.find((x) => x.id === t.accountId);
                const c = state.categories.find((x) => x.id === t.categoryId);
                const sign =
                  t.type === 'income' || t.type === 'refund' || t.type === 'cashback' ? '+' : '−';
                const displayAmount = selectors.convertMoneyForDisplay(
                  state,
                  t.amount,
                  viewCurrency,
                );
                return (
                  <tr key={t.id} style={{ borderTop: `1px solid ${tokens.color.border}` }}>
                    <td>{new Date(t.occurredAt).toLocaleDateString()}</td>
                    <td>{t.type}</td>
                    <td>{a?.name ?? '—'}</td>
                    <td>{c?.name ?? '—'}</td>
                    <td
                      style={{
                        textAlign: 'right',
                        fontVariantNumeric: 'tabular-nums',
                        color: sign === '+' ? tokens.color.positive : tokens.color.overspend,
                      }}
                    >
                      {sign} {formatMoney(t.amount, state.preferences.locale)}
                      {t.amount.currency !== displayAmount.currency ? (
                        <div style={{ color: tokens.color.inkMuted, fontSize: 12 }}>
                          {sign} {formatMoney(displayAmount, state.preferences.locale)}
                        </div>
                      ) : null}
                    </td>
                    <td>
                      <button
                        onClick={() => removeTransaction(t.id)}
                        style={{
                          color: tokens.color.overspend,
                          background: 'transparent',
                          border: 'none',
                          cursor: 'pointer',
                        }}
                      >
                        delete
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
