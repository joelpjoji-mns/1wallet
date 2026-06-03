'use client';

import { formatMoney, toMinor } from '@1wallet/domain/money';
import { uid } from '@1wallet/ledger/id';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import type { FormEvent, ReactElement } from 'react';
import { useState } from 'react';
import { Bar } from '../../components/Bar';
import { Card } from '../../components/Card';
import { Button } from '../../components/Button';
import { Input, Select } from '../../components/Input';

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
    <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.xl, width: '100%' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <h1 style={{ margin: 0, fontSize: 32, fontWeight: 700 }}>Planner</h1>
          <p style={{ margin: 0, color: 'var(--color-on-surface-variant)' }}>
            Set budgets and track your goals.
          </p>
        </div>
      </div>

      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(350px, 1fr))',
          gap: tokens.space.lg,
        }}
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.lg }}>
          <Card title="New Budget">
            <form
              onSubmit={addBudget}
              style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.md }}
            >
              <Select
                label="Category"
                value={budgetCat}
                onChange={(e) => setBudgetCat(e.target.value)}
              >
                <option value="">Select Category…</option>
                {expenseCats.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </Select>
              <Input
                label={`Monthly Limit (${base})`}
                value={budgetAmt}
                onChange={(e) => setBudgetAmt(e.target.value)}
                placeholder="0.00"
                inputMode="decimal"
              />
              <Button type="submit" style={{ alignSelf: 'flex-start' }}>
                Add Budget
              </Button>
            </form>
          </Card>

          <Card title="Budgets">
            {budgets.length === 0 ? (
              <p style={{ color: 'var(--color-on-surface-variant)' }}>No budgets yet.</p>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.md }}>
                {budgets.map((b) => (
                  <div
                    key={b.budgetId}
                    style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.xs }}
                  >
                    <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                      <span style={{ fontWeight: 500 }}>{b.name}</span>
                      <span style={{ fontWeight: 600 }}>
                        {formatMoney(
                          selectors.convertMoneyForDisplay(state, b.spent, viewCurrency),
                          state.preferences.locale,
                        )}{' '}
                        <span style={{ color: 'var(--color-on-surface-variant)', fontWeight: 400 }}>
                          /
                        </span>{' '}
                        {formatMoney(
                          selectors.convertMoneyForDisplay(state, b.limit, viewCurrency),
                          state.preferences.locale,
                        )}
                      </span>
                    </div>
                    <Bar share={Math.min(b.share, 1.2)} over={b.isOver} />
                  </div>
                ))}
              </div>
            )}
          </Card>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.lg }}>
          <Card title="New Goal">
            <form
              onSubmit={addGoal}
              style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.md }}
            >
              <Input
                label="Goal Name"
                value={goalName}
                onChange={(e) => setGoalName(e.target.value)}
                placeholder="e.g. New Car"
              />
              <div
                style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: tokens.space.md }}
              >
                <Input
                  label={`Target Amount (${base})`}
                  value={goalAmt}
                  onChange={(e) => setGoalAmt(e.target.value)}
                  placeholder="0.00"
                  inputMode="decimal"
                />
                <Input
                  label="Target Date"
                  value={goalDate}
                  onChange={(e) => setGoalDate(e.target.value)}
                  placeholder="YYYY-MM-DD"
                  type="date"
                />
              </div>
              <Button type="submit" style={{ alignSelf: 'flex-start' }}>
                Add Goal
              </Button>
            </form>
          </Card>

          <Card title="Goals">
            {goals.length === 0 ? (
              <p style={{ color: 'var(--color-on-surface-variant)' }}>No goals yet.</p>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.md }}>
                {goals.map((g) => (
                  <div
                    key={g.goalId}
                    style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.xs }}
                  >
                    <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                      <span style={{ fontWeight: 500 }}>{g.name}</span>
                      <span style={{ fontWeight: 600 }}>
                        {formatMoney(
                          selectors.convertMoneyForDisplay(state, g.saved, viewCurrency),
                          state.preferences.locale,
                        )}{' '}
                        <span style={{ color: 'var(--color-on-surface-variant)', fontWeight: 400 }}>
                          /
                        </span>{' '}
                        {formatMoney(
                          selectors.convertMoneyForDisplay(state, g.target, viewCurrency),
                          state.preferences.locale,
                        )}
                      </span>
                    </div>
                    <Bar share={Math.min(g.share, 1)} />
                    {g.monthlyRequired && (
                      <span
                        style={{
                          color: 'var(--color-on-surface-variant)',
                          fontSize: tokens.font.size.xs,
                        }}
                      >
                        Save{' '}
                        {formatMoney(
                          selectors.convertMoneyForDisplay(state, g.monthlyRequired, viewCurrency),
                          state.preferences.locale,
                        )}{' '}
                        / month
                      </span>
                    )}
                  </div>
                ))}
              </div>
            )}
          </Card>
        </div>
      </div>
    </div>
  );
}
