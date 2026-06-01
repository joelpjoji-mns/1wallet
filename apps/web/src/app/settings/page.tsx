'use client';

import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import type { ReactElement } from 'react';
import { Card } from '../../components/Card';

export default function SettingsPage(): ReactElement {
  const { state, ready, reset, setBaseCurrency } = useLedger();
  if (!ready) return <p>Loading…</p>;

  return (
    <div style={{ display: 'grid', gap: tokens.space.lg, maxWidth: 700 }}>
      <Card title="Preferences">
        <label style={{ display: 'block' }}>
          Base currency
          <select
            value={state.preferences.baseCurrency}
            onChange={(e) => void setBaseCurrency(e.target.value)}
            style={{
              display: 'block',
              marginTop: 4,
              padding: tokens.space.sm,
              borderRadius: tokens.radius.md,
              border: `1px solid ${tokens.color.border}`,
            }}
          >
            {['INR', 'USD', 'EUR', 'GBP', 'AED', 'SGD', 'JPY'].map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </label>
      </Card>

      <Card title="Data">
        <p style={{ color: tokens.color.inkMuted }}>
          Your ledger is stored locally in your browser. This will be replaced by cloud sync once
          Supabase is wired up.
        </p>
        <button
          onClick={() => {
            if (confirm('Erase everything in this browser?')) void reset();
          }}
          style={{
            padding: `${tokens.space.md}px ${tokens.space.lg}px`,
            background: tokens.color.overspend,
            color: '#fff',
            fontWeight: 600,
            border: 'none',
            borderRadius: tokens.radius.md,
            cursor: 'pointer',
          }}
        >
          Reset ledger
        </button>
      </Card>
    </div>
  );
}
