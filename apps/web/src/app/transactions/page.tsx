'use client';

import { formatMoney, toMinor } from '@1wallet/domain/money';
import type { TransactionType } from '@1wallet/domain/types';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import type { FormEvent, ReactElement } from 'react';
import { useMemo, useState } from 'react';
import { Card } from '../../components/Card';
import { Button } from '../../components/Button';
import { Input, Select } from '../../components/Input';

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
  if (accounts.length === 0)
    return <p style={{ color: 'var(--color-on-surface-variant)' }}>Please add an account first.</p>;

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
    <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.xl, width: '100%' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <h1 style={{ margin: 0, fontSize: 32, fontWeight: 700 }}>Transactions</h1>
          <p style={{ margin: 0, color: 'var(--color-on-surface-variant)' }}>
            Record and manage your spending.
          </p>
        </div>
      </div>

      <div
        style={{ display: 'grid', gridTemplateColumns: '1fr', gap: tokens.space.lg, maxWidth: 900 }}
      >
        <Card title="New Transaction">
          <form
            onSubmit={submit}
            style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.md }}
          >
            <div style={{ display: 'flex', gap: tokens.space.sm, flexWrap: 'wrap' }}>
              {TX_TYPES.map((t) => (
                <Button
                  key={t.id}
                  type="button"
                  variant={type === t.id ? 'primary' : 'secondary'}
                  onClick={() => setType(t.id)}
                  style={{ flex: 1, minWidth: 100 }}
                >
                  {t.label}
                </Button>
              ))}
            </div>

            <div
              style={{
                display: 'grid',
                gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
                gap: tokens.space.md,
              }}
            >
              <Input
                label="Amount"
                placeholder="0.00"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                inputMode="decimal"
              />

              <Select
                label="Account"
                value={accountId || acct?.id || ''}
                onChange={(e) => setAccountId(e.target.value)}
              >
                {accounts.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name} ({a.currency})
                  </option>
                ))}
              </Select>
            </div>

            <div
              style={{
                display: 'grid',
                gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
                gap: tokens.space.md,
              }}
            >
              {type === 'transfer' ? (
                <Select
                  label="To Account"
                  value={counterAccountId}
                  onChange={(e) => setCounterAccountId(e.target.value)}
                >
                  <option value="">Select Account…</option>
                  {accounts
                    .filter((a) => a.id !== (accountId || acct?.id))
                    .map((a) => (
                      <option key={a.id} value={a.id}>
                        {a.name}
                      </option>
                    ))}
                </Select>
              ) : (
                <Select
                  label="Category"
                  value={categoryId}
                  onChange={(e) => setCategoryId(e.target.value)}
                >
                  <option value="">Select Category…</option>
                  {categories.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.name}
                    </option>
                  ))}
                </Select>
              )}

              <Input
                label="Notes (optional)"
                placeholder="What was this for?"
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
              />
            </div>

            <Button type="submit" style={{ alignSelf: 'flex-start', marginTop: tokens.space.sm }}>
              Save Transaction
            </Button>
          </form>
        </Card>

        <Card title={`Recent Transactions (${txns.length})`}>
          {txns.length === 0 ? (
            <p style={{ color: 'var(--color-on-surface-variant)' }}>No transactions yet.</p>
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
                    <th style={{ padding: tokens.space.sm }}>Date</th>
                    <th style={{ padding: tokens.space.sm }}>Type</th>
                    <th style={{ padding: tokens.space.sm }}>Account</th>
                    <th style={{ padding: tokens.space.sm }}>Category</th>
                    <th style={{ padding: tokens.space.sm, textAlign: 'right' }}>Amount</th>
                    <th style={{ padding: tokens.space.sm }} />
                  </tr>
                </thead>
                <tbody>
                  {txns.slice(0, 200).map((t) => {
                    const a = state.accounts.find((x) => x.id === t.accountId);
                    const c = state.categories.find((x) => x.id === t.categoryId);
                    const sign =
                      t.type === 'income' || t.type === 'refund' || t.type === 'cashback'
                        ? '+'
                        : '−';
                    const displayAmount = selectors.convertMoneyForDisplay(
                      state,
                      t.amount,
                      viewCurrency,
                    );
                    return (
                      <tr
                        key={t.id}
                        style={{ borderBottom: '1px solid var(--color-surface-high)' }}
                      >
                        <td style={{ padding: tokens.space.sm }}>
                          {new Date(t.occurredAt).toLocaleDateString()}
                        </td>
                        <td style={{ padding: tokens.space.sm, textTransform: 'capitalize' }}>
                          {t.type}
                        </td>
                        <td style={{ padding: tokens.space.sm }}>{a?.name ?? '—'}</td>
                        <td style={{ padding: tokens.space.sm }}>{c?.name ?? '—'}</td>
                        <td
                          style={{
                            padding: tokens.space.sm,
                            textAlign: 'right',
                            fontVariantNumeric: 'tabular-nums',
                            fontWeight: 600,
                            color: sign === '+' ? 'var(--color-positive)' : 'var(--color-error)',
                          }}
                        >
                          {sign} {formatMoney(t.amount, state.preferences.locale)}
                          {t.amount.currency !== displayAmount.currency ? (
                            <div
                              style={{
                                color: 'var(--color-on-surface-variant)',
                                fontSize: 12,
                                fontWeight: 400,
                              }}
                            >
                              {sign} {formatMoney(displayAmount, state.preferences.locale)}
                            </div>
                          ) : null}
                        </td>
                        <td style={{ padding: tokens.space.sm, textAlign: 'right' }}>
                          <Button
                            variant="ghost"
                            onClick={() => removeTransaction(t.id)}
                            style={{ color: 'var(--color-error)', padding: '4px 8px' }}
                          >
                            Delete
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
