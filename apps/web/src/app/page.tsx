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
    <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.xl, width: '100%' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <h1 style={{ margin: 0, fontSize: 32, fontWeight: 700 }}>Dashboard</h1>
          <p style={{ margin: 0, color: 'var(--color-on-surface-variant)' }}>
            Welcome back to your overview.
          </p>
        </div>
        <button
          onClick={() => void cycleDisplayCurrency()}
          style={{
            padding: `${tokens.space.sm}px ${tokens.space.md}px`,
            borderRadius: tokens.radius.pill,
            border: `1px solid var(--color-outline-variant)`,
            background: 'var(--color-surface)',
            color: 'var(--color-primary)',
            fontWeight: 700,
            cursor: 'pointer',
            transition: 'background-color 0.2s',
          }}
          onMouseOver={(e) => (e.currentTarget.style.backgroundColor = 'var(--color-surface-high)')}
          onMouseOut={(e) => (e.currentTarget.style.backgroundColor = 'var(--color-surface)')}
        >
          Currency: {viewCurrency}
        </button>
      </div>

      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))',
          gap: tokens.space.lg,
        }}
      >
        <Card>
          <span style={{ color: 'var(--color-on-surface-variant)', fontSize: tokens.font.size.sm }}>
            Total Balance
          </span>
          <span style={{ fontSize: 36, fontWeight: 800 }}>
            {formatMoney(total, state.preferences.locale)}
          </span>
        </Card>

        <Card>
          <span style={{ color: 'var(--color-on-surface-variant)', fontSize: tokens.font.size.sm }}>
            Net Worth
          </span>
          <span style={{ fontSize: 36, fontWeight: 800 }}>
            {formatMoney(nw.total, state.preferences.locale)}
          </span>
          <div
            style={{ display: 'flex', justifyContent: 'space-between', marginTop: tokens.space.sm }}
          >
            <span style={{ fontSize: tokens.font.size.sm, color: 'var(--color-positive)' }}>
              Assets: {formatMoney(nw.assets, state.preferences.locale)}
            </span>
            <span style={{ fontSize: tokens.font.size.sm, color: 'var(--color-warning)' }}>
              Liab: {formatMoney(nw.liabilities, state.preferences.locale)}
            </span>
          </div>
        </Card>

        <Card>
          <span style={{ color: 'var(--color-on-surface-variant)', fontSize: tokens.font.size.sm }}>
            This Month
          </span>
          <div
            style={{ display: 'flex', flexDirection: 'column', gap: 4, marginTop: tokens.space.sm }}
          >
            <div style={{ display: 'flex', justifyContent: 'space-between' }}>
              <span style={{ color: 'var(--color-positive)' }}>
                +{formatMoney(displayFlow.income, state.preferences.locale)}
              </span>
              <span style={{ color: 'var(--color-error)' }}>
                −{formatMoney(displayFlow.expense, state.preferences.locale)}
              </span>
            </div>
            <span
              style={{
                fontWeight: 700,
                color:
                  displayFlow.net.amountMinor >= 0 ? 'var(--color-positive)' : 'var(--color-error)',
              }}
            >
              Net: {formatMoney(displayFlow.net, state.preferences.locale)}
            </span>
          </div>
        </Card>

        <Card>
          <span style={{ color: 'var(--color-on-surface-variant)', fontSize: tokens.font.size.sm }}>
            Review Queue
          </span>
          <span
            style={{
              fontSize: 36,
              fontWeight: 800,
              color: pendingCaptures.length > 0 ? 'var(--color-primary)' : 'inherit',
            }}
          >
            {pendingCaptures.length}
          </span>
          <span style={{ fontSize: tokens.font.size.sm, color: 'var(--color-on-surface-variant)' }}>
            Pending items
          </span>
        </Card>
      </div>

      <div
        style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(350px, 1fr))',
          gap: tokens.space.lg,
        }}
      >
        <Card title="Top Spending">
          {top.length === 0 ? (
            <p style={{ color: 'var(--color-on-surface-variant)' }}>No spending yet.</p>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.md }}>
              {top.map((c) => (
                <div
                  key={c.categoryId ?? c.categoryName}
                  style={{
                    display: 'flex',
                    justifyContent: 'space-between',
                    padding: `${tokens.space.xs}px 0`,
                  }}
                >
                  <span style={{ fontWeight: 500 }}>{c.categoryName}</span>
                  <span style={{ fontWeight: 700 }}>
                    {formatMoney(c.amount, state.preferences.locale)}
                  </span>
                </div>
              ))}
            </div>
          )}
        </Card>

        <Card title="Budgets">
          {budgets.length === 0 ? (
            <p style={{ color: 'var(--color-on-surface-variant)' }}>No active budgets.</p>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.md }}>
              {budgets.map((b) => (
                <div
                  key={b.budgetId}
                  style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.xs }}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                    <span style={{ fontWeight: 500 }}>{b.name}</span>
                    <span
                      style={{
                        color: b.isOver ? 'var(--color-error)' : 'inherit',
                        fontWeight: 600,
                      }}
                    >
                      {Math.round(b.share * 100)}%
                    </span>
                  </div>
                  <Bar share={Math.min(b.share, 1.2)} over={b.isOver} />
                </div>
              ))}
            </div>
          )}
        </Card>

        <Card title="Goals">
          {goals.length === 0 ? (
            <p style={{ color: 'var(--color-on-surface-variant)' }}>No active goals.</p>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.md }}>
              {goals.map((g) => (
                <div
                  key={g.goalId}
                  style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.xs }}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                    <span style={{ fontWeight: 500 }}>{g.name}</span>
                    <span style={{ fontWeight: 600 }}>{Math.round(g.share * 100)}%</span>
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
  );
}
