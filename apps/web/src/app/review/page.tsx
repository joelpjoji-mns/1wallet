'use client';

import { formatMoney } from '@1wallet/domain/money';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import type { CSSProperties, ReactElement } from 'react';
import { Card } from '../../components/Card';

export default function ReviewPage(): ReactElement {
  const { state, ready, approveCaptureCandidate, rejectCaptureCandidate, selectors } = useLedger();
  const pending = ready ? selectors.queryCaptureCandidates(state, { status: 'pending' }) : [];

  if (!ready) return <p>Loading…</p>;

  return (
    <div style={{ display: 'grid', gap: tokens.space.lg, maxWidth: 900 }}>
      <Card title="Review queue">
        {pending.length === 0 ? (
          <p style={{ color: tokens.color.inkMuted }}>No captures waiting.</p>
        ) : (
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            <thead>
              <tr style={{ textAlign: 'left', color: tokens.color.inkMuted }}>
                <th>Source</th>
                <th>Merchant</th>
                <th>Account</th>
                <th>Category</th>
                <th>Confidence</th>
                <th style={{ textAlign: 'right' }}>Amount</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {pending.map((candidate) => {
                const account = state.accounts.find(
                  (item) => item.id === candidate.suggestedAccountId,
                );
                const category = state.categories.find(
                  (item) => item.id === candidate.suggestedCategoryId,
                );
                const canApprove = Boolean(
                  candidate.parsedAmount && candidate.suggestedAccountId && candidate.suggestedType,
                );
                return (
                  <tr key={candidate.id} style={{ borderTop: `1px solid ${tokens.color.border}` }}>
                    <td>{candidate.source}</td>
                    <td>{candidate.parsedMerchant ?? 'Unknown'}</td>
                    <td>{account?.name ?? 'Needs review'}</td>
                    <td>{category?.name ?? 'Uncategorized'}</td>
                    <td>{Math.round(candidate.confidence)}%</td>
                    <td style={{ textAlign: 'right', fontVariantNumeric: 'tabular-nums' }}>
                      {candidate.parsedAmount
                        ? formatMoney(candidate.parsedAmount, state.preferences.locale)
                        : '—'}
                    </td>
                    <td
                      style={{ display: 'flex', gap: tokens.space.xs, justifyContent: 'flex-end' }}
                    >
                      <button
                        onClick={() => rejectCaptureCandidate(candidate.id)}
                        style={rejectStyle}
                      >
                        reject
                      </button>
                      <button
                        disabled={!canApprove}
                        onClick={() => approveCaptureCandidate(candidate.id)}
                        style={{ ...approveStyle, opacity: canApprove ? 1 : 0.45 }}
                      >
                        approve
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

const approveStyle: CSSProperties = {
  color: '#fff',
  background: tokens.color.primary,
  border: 'none',
  borderRadius: tokens.radius.sm,
  padding: `${tokens.space.xs}px ${tokens.space.sm}px`,
  cursor: 'pointer',
};

const rejectStyle: CSSProperties = {
  color: tokens.color.overspend,
  background: 'transparent',
  border: 'none',
  cursor: 'pointer',
};
