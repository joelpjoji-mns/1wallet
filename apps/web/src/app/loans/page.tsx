'use client';

import { formatMoney } from '@1wallet/domain/money';
import { buildLoanPayoffProjection } from '@1wallet/ledger/loans';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { useMemo } from 'react';
import { Card } from '../../components/Card';

export default function LoansPage() {
  const { state, ready, selectors } = useLedger();

  const activeLoans = useMemo(() => {
    if (!ready) return [];
    return state.accounts.filter((a) => !a.isArchived && (a.type === 'loan' || a.type === 'overdraft' || a.type === 'lent'));
  }, [ready, state.accounts]);

  const projection = useMemo(() => {
    if (!ready) return null;
    return buildLoanPayoffProjection(state);
  }, [ready, state]);

  if (!ready) return <p>Loading…</p>;

  const viewCurrency = selectors.displayCurrency(state);
  
  // Calculate total outstanding
  let totalOutstandingMinor = 0;
  activeLoans.forEach(loan => {
    const balance = selectors.accountBalance(state, loan.id);
    const converted = selectors.convertMoneyForDisplay(state, { amountMinor: Math.abs(balance.amountMinor), currency: balance.currency }, viewCurrency);
    totalOutstandingMinor += converted.amountMinor;
  });

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.lg, width: '100%' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h1 style={{ margin: 0, fontSize: 32, fontWeight: 700 }}>Loans & EMI</h1>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: tokens.space.lg }}>
        <Card>
          <span style={{ color: 'var(--color-on-surface-variant)', fontSize: tokens.font.size.sm }}>Total Loans</span>
          <span style={{ fontSize: 32, fontWeight: 700 }}>{activeLoans.length}</span>
        </Card>
        <Card>
          <span style={{ color: 'var(--color-on-surface-variant)', fontSize: tokens.font.size.sm }}>Total Outstanding</span>
          <span style={{ fontSize: 32, fontWeight: 700, color: 'var(--color-warning)' }}>
            {formatMoney({ amountMinor: totalOutstandingMinor, currency: viewCurrency }, state.preferences.locale)}
          </span>
        </Card>
        <Card>
          <span style={{ color: 'var(--color-on-surface-variant)', fontSize: tokens.font.size.sm }}>Forecast Interest</span>
          <span style={{ fontSize: 32, fontWeight: 700 }}>
            {projection ? formatMoney(selectors.convertMoneyForDisplay(state, projection.totalInterest, viewCurrency), state.preferences.locale) : '0'}
          </span>
        </Card>
        <Card>
          <span style={{ color: 'var(--color-on-surface-variant)', fontSize: tokens.font.size.sm }}>All loans close on</span>
          <span style={{ fontSize: 24, fontWeight: 700, marginTop: 8 }}>
            {projection?.normalClosesOn ? new Date(projection.normalClosesOn).toLocaleDateString() : 'Needs EMI setup'}
          </span>
        </Card>
      </div>

      <Card title="Loan Accounts">
        {activeLoans.length === 0 ? (
          <p style={{ color: 'var(--color-on-surface-variant)' }}>No loans tracked yet.</p>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.md, marginTop: tokens.space.md }}>
            {activeLoans.map(loan => {
              const balance = selectors.accountBalance(state, loan.id);
              const plan = projection?.loans.find(p => p.account.id === loan.id);
              
              return (
                <div 
                  key={loan.id}
                  style={{
                    display: 'flex',
                    justifyContent: 'space-between',
                    alignItems: 'center',
                    padding: tokens.space.md,
                    backgroundColor: 'var(--color-surface)',
                    borderRadius: tokens.radius.md,
                    border: '1px solid var(--color-outline-variant)'
                  }}
                >
                  <div style={{ display: 'flex', flexDirection: 'column' }}>
                    <span style={{ fontWeight: 600 }}>{loan.name}</span>
                    <span style={{ fontSize: tokens.font.size.sm, color: 'var(--color-on-surface-variant)' }}>
                      {loan.type} • {loan.currency}
                    </span>
                  </div>
                  
                  <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end' }}>
                    <span style={{ fontWeight: 700 }}>
                      {formatMoney({ amountMinor: Math.abs(balance.amountMinor), currency: balance.currency }, state.preferences.locale)}
                    </span>
                    <span style={{ fontSize: tokens.font.size.sm, color: 'var(--color-on-surface-variant)' }}>
                      Outstanding
                    </span>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </Card>
    </div>
  );
}
