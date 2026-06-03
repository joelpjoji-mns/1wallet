'use client';

import { formatMoney } from '@1wallet/domain/money';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { useMemo } from 'react';
import { Card } from '../../components/Card';
import { Button } from '../../components/Button';
import type { FutureGenerationRule } from '@1wallet/ledger/store/types';

export default function RecurringPage() {
  const { state, ready, selectors } = useLedger();

  const rules = useMemo(() => {
    if (!ready) return [];
    return state.preferences.futureGenerationRules || [];
  }, [ready, state]);

  const activeRules = rules.filter(r => r.enabled);
  const pausedRules = rules.filter(r => !r.enabled);

  if (!ready) return <p>Loading…</p>;

  const formatRecurrence = (rule: FutureGenerationRule) => {
    const interval = rule.interval || 1;
    if (rule.frequency === 'monthly') {
      return `Every ${interval === 1 ? 'month' : `${interval} months`} on day ${rule.dayOfMonth || 1}`;
    }
    if (rule.frequency === 'weekly') {
      return `Every ${interval === 1 ? 'week' : `${interval} weeks`}`;
    }
    if (rule.frequency === 'yearly') {
      return `Every ${interval === 1 ? 'year' : `${interval} years`}`;
    }
    if (rule.frequency === 'daily') {
      return `Every ${interval === 1 ? 'day' : `${interval} days`}`;
    }
    return 'Custom';
  };

  const getCategoryName = (categoryId?: string) => {
    if (!categoryId) return 'Uncategorized';
    return state.categories.find(c => c.id === categoryId)?.name || 'Unknown';
  };

  const getAccountName = (accountId?: string) => {
    if (!accountId) return 'Unknown';
    return state.accounts.find(a => a.id === accountId)?.name || 'Unknown';
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.lg, width: '100%' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h1 style={{ margin: 0, fontSize: 32, fontWeight: 700 }}>Recurring Plans</h1>
        <Button>Add Plan</Button>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: tokens.space.lg }}>
        <Card>
          <span style={{ color: 'var(--color-on-surface-variant)', fontSize: tokens.font.size.sm }}>Active Plans</span>
          <span style={{ fontSize: 32, fontWeight: 700 }}>{activeRules.length}</span>
        </Card>
        <Card>
          <span style={{ color: 'var(--color-on-surface-variant)', fontSize: tokens.font.size.sm }}>Total Plans</span>
          <span style={{ fontSize: 32, fontWeight: 700 }}>{rules.length}</span>
        </Card>
      </div>

      <Card title="Active Plans">
        {activeRules.length === 0 ? (
          <p style={{ color: 'var(--color-on-surface-variant)' }}>No active recurring plans.</p>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.md, marginTop: tokens.space.md }}>
            {activeRules.map(rule => (
              <div 
                key={rule.id}
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
                <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.xs }}>
                  <span style={{ fontWeight: 600, fontSize: tokens.font.size.lg }}>{rule.name}</span>
                  <span style={{ fontSize: tokens.font.size.sm, color: 'var(--color-on-surface-variant)' }}>
                    {rule.type} • {getCategoryName(rule.categoryId)}
                  </span>
                  <span style={{ fontSize: tokens.font.size.sm, color: 'var(--color-on-surface-variant)' }}>
                    {getAccountName(rule.accountId)} {rule.counterAccountId && `→ ${getAccountName(rule.counterAccountId)}`}
                  </span>
                  {rule.notes && (
                    <span style={{ fontSize: tokens.font.size.sm, fontStyle: 'italic', color: 'var(--color-on-surface-variant)' }}>
                      {rule.notes}
                    </span>
                  )}
                </div>
                
                <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: tokens.space.xs }}>
                  <span style={{ fontWeight: 700, fontSize: tokens.font.size.lg }}>
                    {formatMoney({ amountMinor: rule.amountMinor, currency: rule.currency }, state.preferences.locale)}
                  </span>
                  <span style={{ fontSize: tokens.font.size.sm, color: 'var(--color-on-surface-variant)' }}>
                    {formatRecurrence(rule)}
                  </span>
                  {rule.occurrences && (
                    <span style={{ fontSize: tokens.font.size.sm, color: 'var(--color-primary)' }}>
                      Limit: {rule.occurrences} times
                    </span>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>

      {pausedRules.length > 0 && (
        <Card title="Paused Plans">
          <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.md, marginTop: tokens.space.md }}>
            {pausedRules.map(rule => (
              <div 
                key={rule.id}
                style={{
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center',
                  padding: tokens.space.md,
                  backgroundColor: 'var(--color-surface-low)',
                  borderRadius: tokens.radius.md,
                  border: '1px solid var(--color-outline-variant)',
                  opacity: 0.7
                }}
              >
                <div style={{ display: 'flex', flexDirection: 'column' }}>
                  <span style={{ fontWeight: 600 }}>{rule.name}</span>
                  <span style={{ fontSize: tokens.font.size.sm, color: 'var(--color-on-surface-variant)' }}>
                    Paused • {getCategoryName(rule.categoryId)}
                  </span>
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end' }}>
                  <span style={{ fontWeight: 700 }}>
                    {formatMoney({ amountMinor: rule.amountMinor, currency: rule.currency }, state.preferences.locale)}
                  </span>
                </div>
              </div>
            ))}
          </div>
        </Card>
      )}
    </div>
  );
}
