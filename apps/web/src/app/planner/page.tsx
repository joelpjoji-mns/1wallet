'use client';

import { formatMoney, toMinor } from '@1wallet/domain/money';
import { uid } from '@1wallet/ledger/id';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import type { CSSProperties, FormEvent, ReactElement } from 'react';
import { useState } from 'react';
import { Bar } from '../../components/Bar';
import { Card } from '../../components/Card';

export default function PlannerPage(): ReactElement {
  const { state, ready, mutate, selectors } = useLedger();
  const [budgetCat, setBudgetCat] = useState('');
  const [budgetAmt, setBudgetAmt] = useState('');
  const [goalName, setGoalName] = useState('');
  const [goalAmt, setGoalAmt] = useState('');
  const [goalDate, setGoalDate] = useState('');

  if (!ready) return <p>Loading…</p>;

  const expenseCats = state.categories.filter((c) => c.kind === 'expense' && !c.isArchived);
  const budgets = selectors.budgetStatuses(state);
  const goals = selectors.goalStatuses(state);
  const base = state.preferences.baseCurrency;
  const viewCurrency = selectors.displayCurrency(state);

  const addBudget = async (e: FormEvent) => {
    e.preventDefault();
    const cat = expenseCats.find((c) => c.id === budgetCat);
    const n = Number(budgetAmt.replace(/,/g, ''));
    if (!cat || !n || n <= 0) return;
    await mutate((s) => {
      s.budgets.push({
        id: uid(),
        userId: s.userId,
        name: cat.name,
        period: 'monthly',
        startsOn: new Date().toISOString().slice(0, 10),
        amount: { amountMinor: toMinor(n, base), currency: base },
        rolloverUnused: false,
        carryOverspend: false,
        isPaused: false,
        alertThresholds: [50, 80, 100],
      });
    });
    setBudgetAmt('');
  };

  const addGoal = async (e: FormEvent) => {
    e.preventDefault();
    const n = Number(goalAmt.replace(/,/g, ''));
    if (!goalName.trim() || !n || n <= 0) return;
    await mutate((s) => {
      s.goals.push({
        id: uid(),
        userId: s.userId,
        name: goalName.trim(),
        kind: 'save_up',
        targetAmount: { amountMinor: toMinor(n, base), currency: base },
        targetDate: goalDate || undefined,
        priority: 'medium',
        isPaused: false,
        isCompleted: false,
      });
    });
    setGoalName('');
    setGoalAmt('');
    setGoalDate('');
  };

  return (
    <div style={{ display: 'grid', gap: tokens.space.lg, maxWidth: 900 }}>
      <Card title="New budget">
        <form onSubmit={addBudget} style={{ display: 'flex', gap: tokens.space.sm }}>
          <select
            value={budgetCat}
            onChange={(e) => setBudgetCat(e.target.value)}
            style={inputStyle}
          >
            <option value="">Category…</option>
            {expenseCats.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
          <input
            value={budgetAmt}
            onChange={(e) => setBudgetAmt(e.target.value)}
            placeholder={`Monthly limit (${base})`}
            style={inputStyle}
            inputMode="decimal"
          />
          <button type="submit" style={btnStyle}>
            Add budget
          </button>
        </form>
      </Card>

      <Card title="Budgets">
        {budgets.length === 0 ? (
          <p style={{ color: tokens.color.inkMuted }}>No budgets yet.</p>
        ) : (
          budgets.map((b) => (
            <div key={b.budgetId} style={{ padding: `${tokens.space.sm}px 0` }}>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span>{b.name}</span>
                <span>
                  {formatMoney(
                    selectors.convertMoneyForDisplay(state, b.spent, viewCurrency),
                    state.preferences.locale,
                  )}{' '}
                  /{' '}
                  {formatMoney(
                    selectors.convertMoneyForDisplay(state, b.limit, viewCurrency),
                    state.preferences.locale,
                  )}
                </span>
              </div>
              <Bar share={Math.min(b.share, 1.2)} over={b.isOver} />
            </div>
          ))
        )}
      </Card>

      <Card title="New goal">
        <form
          onSubmit={addGoal}
          style={{ display: 'flex', gap: tokens.space.sm, flexWrap: 'wrap' }}
        >
          <input
            value={goalName}
            onChange={(e) => setGoalName(e.target.value)}
            placeholder="Goal name"
            style={inputStyle}
          />
          <input
            value={goalAmt}
            onChange={(e) => setGoalAmt(e.target.value)}
            placeholder={`Target (${base})`}
            style={inputStyle}
            inputMode="decimal"
          />
          <input
            value={goalDate}
            onChange={(e) => setGoalDate(e.target.value)}
            placeholder="YYYY-MM-DD"
            style={inputStyle}
          />
          <button type="submit" style={btnStyle}>
            Add goal
          </button>
        </form>
      </Card>

      <Card title="Goals">
        {goals.length === 0 ? (
          <p style={{ color: tokens.color.inkMuted }}>No goals yet.</p>
        ) : (
          goals.map((g) => (
            <div key={g.goalId} style={{ padding: `${tokens.space.sm}px 0` }}>
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span>{g.name}</span>
                <span>
                  {formatMoney(
                    selectors.convertMoneyForDisplay(state, g.saved, viewCurrency),
                    state.preferences.locale,
                  )}{' '}
                  /{' '}
                  {formatMoney(
                    selectors.convertMoneyForDisplay(state, g.target, viewCurrency),
                    state.preferences.locale,
                  )}
                </span>
              </div>
              <Bar share={Math.min(g.share, 1)} />
              {g.monthlyRequired && (
                <p style={{ color: tokens.color.inkMuted, margin: '4px 0 0', fontSize: 13 }}>
                  Save{' '}
                  {formatMoney(
                    selectors.convertMoneyForDisplay(state, g.monthlyRequired, viewCurrency),
                    state.preferences.locale,
                  )}{' '}
                  / month
                </p>
              )}
            </div>
          ))
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
  flex: 1,
  minWidth: 140,
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
