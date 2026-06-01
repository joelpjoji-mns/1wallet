'use client';

import { formatMoney } from '@1wallet/domain/money';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import type { ReactElement } from 'react';
import { Bar } from '../components/Bar';
import { Card } from '../components/Card';
import { OnboardingForm } from '../components/OnboardingForm';

export default function Home(): ReactElement {
  const { state, ready, selectors, cycleDisplayCurrency } = useLedger();
  if (!ready) return <p>Loading…</p>;
  if (state.accounts.length === 0) return <OnboardingForm />;

  const viewCurrency = selectors.displayCurrency(state);
  const total = selectors.totalBalance(state, viewCurrency);
  const nw = selectors.netWorth(state, viewCurrency);
  const flow = selectors.cashflow(state);
  const displayFlow = {
    income: selectors.convertMoneyForDisplay(state, flow.income, viewCurrency),
    expense: selectors.convertMoneyForDisplay(state, flow.expense, viewCurrency),
    net: selectors.convertMoneyForDisplay(state, flow.net, viewCurrency),
  };
  const top = selectors
    .categoryBreakdown(state)
    .map((category) => ({
      ...category,
      amount: selectors.convertMoneyForDisplay(state, category.amount, viewCurrency),
    }))
    .slice(0, 6);
  const budgets = selectors.budgetStatuses(state);
  const goals = selectors.goalStatuses(state);
  const pendingCaptures = selectors.queryCaptureCandidates(state, { status: 'pending' });

  return (
    <div style={{ display: 'grid', gap: tokens.space.lg, maxWidth: 1100 }}>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: tokens.space.lg }}>
        <Card title="Total balance">
          <button onClick={() => void cycleDisplayCurrency()} style={currencyButtonStyle}>
            {viewCurrency}
          </button>
          <p style={{ fontSize: 32, margin: 0, fontWeight: 700 }}>
            {formatMoney(total, state.preferences.locale)}
          </p>
        </Card>
        <Card title="Net worth">
          <p style={{ fontSize: 32, margin: 0, fontWeight: 700 }}>
            {formatMoney(nw.total, state.preferences.locale)}
          </p>
          <p style={{ color: tokens.color.inkMuted, margin: 0 }}>
            Assets {formatMoney(nw.assets, state.preferences.locale)} · Liab{' '}
            {formatMoney(nw.liabilities, state.preferences.locale)}
          </p>
        </Card>
        <Card title="This month">
          <p style={{ margin: 0, color: tokens.color.positive }}>
            +{formatMoney(displayFlow.income, state.preferences.locale)}
          </p>
          <p style={{ margin: 0, color: tokens.color.overspend }}>
            −{formatMoney(displayFlow.expense, state.preferences.locale)}
          </p>
          <p
            style={{
              margin: 0,
              fontWeight: 700,
              color:
                displayFlow.net.amountMinor >= 0 ? tokens.color.positive : tokens.color.overspend,
            }}
          >
            Net {formatMoney(displayFlow.net, state.preferences.locale)}
          </p>
        </Card>
        <Card title="Review queue">
          <p style={{ fontSize: 32, margin: 0, fontWeight: 700 }}>{pendingCaptures.length}</p>
          <p style={{ color: tokens.color.inkMuted, margin: 0 }}>capture candidates waiting</p>
        </Card>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: tokens.space.lg }}>
        <Card title="Top categories">
          {top.length === 0 ? (
            <p style={{ color: tokens.color.inkMuted }}>No spending yet.</p>
          ) : (
            top.map((c) => (
              <div
                key={c.categoryId ?? c.categoryName}
                style={{
                  display: 'flex',
                  justifyContent: 'space-between',
                  padding: `${tokens.space.sm}px 0`,
                  borderBottom: `1px solid ${tokens.color.border}`,
                }}
              >
                <span>{c.categoryName}</span>
                <strong>{formatMoney(c.amount, state.preferences.locale)}</strong>
              </div>
            ))
          )}
        </Card>

        <Card title="Budgets">
          {budgets.length === 0 ? (
            <p style={{ color: tokens.color.inkMuted }}>No budgets yet.</p>
          ) : (
            budgets.map((b) => (
              <div key={b.budgetId} style={{ padding: `${tokens.space.sm}px 0` }}>
                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span>{b.name}</span>
                  <span style={{ color: b.isOver ? tokens.color.overspend : tokens.color.ink }}>
                    {Math.round(b.share * 100)}%
                  </span>
                </div>
                <Bar share={Math.min(b.share, 1.2)} over={b.isOver} />
              </div>
            ))
          )}
        </Card>

        <Card title="Goals">
          {goals.length === 0 ? (
            <p style={{ color: tokens.color.inkMuted }}>No goals yet.</p>
          ) : (
            goals.map((g) => (
              <div key={g.goalId} style={{ padding: `${tokens.space.sm}px 0` }}>
                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span>{g.name}</span>
                  <span>{Math.round(g.share * 100)}%</span>
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
    </div>
  );
}

const currencyButtonStyle = {
  float: 'right' as const,
  padding: `${tokens.space.xs}px ${tokens.space.sm}px`,
  borderRadius: tokens.radius.pill,
  border: `1px solid ${tokens.color.border}`,
  background: tokens.color.surface,
  color: tokens.color.primary,
  fontWeight: 700,
  cursor: 'pointer',
};
