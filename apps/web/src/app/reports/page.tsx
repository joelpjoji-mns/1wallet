'use client';

import { formatMoney } from '@1wallet/domain/money';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { useMemo } from 'react';
import { Card } from '../../components/Card';

export default function ReportsPage() {
  const { state, ready, selectors } = useLedger();

  const viewCurrency = useMemo(() => ready ? selectors.displayCurrency(state) : state?.preferences?.baseCurrency, [ready, selectors, state]);

  const flow = useMemo(() => ready ? selectors.cashflow(state) : null, [ready, selectors, state]);
  
  const topCategories = useMemo(() => {
    if (!ready) return [];
    return selectors.categoryBreakdown(state).map(category => ({
      ...category,
      displayAmount: selectors.convertMoneyForDisplay(state, category.amount, viewCurrency!)
    })).slice(0, 10);
  }, [ready, selectors, state, viewCurrency]);

  const netWorth = useMemo(() => ready ? selectors.netWorth(state, viewCurrency!) : null, [ready, selectors, state, viewCurrency]);

  if (!ready || !flow || !netWorth) return <p>Loading…</p>;

  const displayIncome = selectors.convertMoneyForDisplay(state, flow.income, viewCurrency!);
  const displayExpense = selectors.convertMoneyForDisplay(state, flow.expense, viewCurrency!);
  const displayNet = selectors.convertMoneyForDisplay(state, flow.net, viewCurrency!);

  const maxCategoryAmount = topCategories.length > 0 ? Math.max(...topCategories.map(c => Math.abs(c.displayAmount.amountMinor))) : 1;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.lg, width: '100%' }}>
      <h1 style={{ margin: 0, fontSize: 32, fontWeight: 700 }}>Reports</h1>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))', gap: tokens.space.lg }}>
        
        {/* Net Worth Report */}
        <Card title="Net Worth Overview">
          <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.md }}>
            <span style={{ fontSize: 40, fontWeight: 800 }}>
              {formatMoney(netWorth.total, state.preferences.locale)}
            </span>
            <div style={{ display: 'flex', gap: tokens.space.lg }}>
              <div style={{ display: 'flex', flexDirection: 'column' }}>
                <span style={{ color: 'var(--color-on-surface-variant)', fontSize: tokens.font.size.sm }}>Assets</span>
                <span style={{ fontWeight: 600, color: 'var(--color-positive)' }}>{formatMoney(netWorth.assets, state.preferences.locale)}</span>
              </div>
              <div style={{ display: 'flex', flexDirection: 'column' }}>
                <span style={{ color: 'var(--color-on-surface-variant)', fontSize: tokens.font.size.sm }}>Liabilities</span>
                <span style={{ fontWeight: 600, color: 'var(--color-warning)' }}>{formatMoney(netWorth.liabilities, state.preferences.locale)}</span>
              </div>
            </div>
          </div>
        </Card>

        {/* Cashflow Report */}
        <Card title="Cashflow (This Month)">
          <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.md }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <span style={{ fontWeight: 600 }}>Income</span>
              <span style={{ color: 'var(--color-positive)', fontWeight: 700 }}>
                +{formatMoney(displayIncome, state.preferences.locale)}
              </span>
            </div>
            <div style={{ width: '100%', height: 8, backgroundColor: 'var(--color-surface-high)', borderRadius: 4, overflow: 'hidden' }}>
              <div style={{ width: '100%', height: '100%', backgroundColor: 'var(--color-positive)' }} />
            </div>

            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: tokens.space.sm }}>
              <span style={{ fontWeight: 600 }}>Expenses</span>
              <span style={{ color: 'var(--color-error)', fontWeight: 700 }}>
                −{formatMoney(displayExpense, state.preferences.locale)}
              </span>
            </div>
            <div style={{ width: '100%', height: 8, backgroundColor: 'var(--color-surface-high)', borderRadius: 4, overflow: 'hidden' }}>
              <div style={{ width: `${Math.min(100, (Math.abs(displayExpense.amountMinor) / (Math.abs(displayIncome.amountMinor) || 1)) * 100)}%`, height: '100%', backgroundColor: 'var(--color-error)' }} />
            </div>

            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: tokens.space.md, paddingTop: tokens.space.md, borderTop: '1px solid var(--color-outline-variant)' }}>
              <span style={{ fontWeight: 700 }}>Net Savings</span>
              <span style={{ fontWeight: 800, color: displayNet.amountMinor >= 0 ? 'var(--color-positive)' : 'var(--color-error)' }}>
                {formatMoney(displayNet, state.preferences.locale)}
              </span>
            </div>
          </div>
        </Card>
      </div>

      <Card title="Top Categories (Expenses)">
        {topCategories.length === 0 ? (
          <p style={{ color: 'var(--color-on-surface-variant)' }}>No spending data to report.</p>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.md }}>
            {topCategories.map(cat => (
              <div key={cat.categoryId ?? cat.categoryName} style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.xs }}>
                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span>{cat.categoryName}</span>
                  <span style={{ fontWeight: 600 }}>{formatMoney(cat.displayAmount, state.preferences.locale)}</span>
                </div>
                <div style={{ width: '100%', height: 6, backgroundColor: 'var(--color-surface-high)', borderRadius: 3, overflow: 'hidden' }}>
                  <div 
                    style={{ 
                      width: `${(Math.abs(cat.displayAmount.amountMinor) / maxCategoryAmount) * 100}%`, 
                      height: '100%', 
                      backgroundColor: 'var(--color-primary)' 
                    }} 
                  />
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>
    </div>
  );
}
