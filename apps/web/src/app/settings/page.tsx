'use client';

import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import type { ReactElement } from 'react';
import { useState, useRef } from 'react';
import { Card } from '../../components/Card';
import { Button } from '../../components/Button';
import { Select } from '../../components/Input';
import { Modal } from '../../components/Modal';
import { useCloudSync } from '../../lib/cloudSync';
import { useAuth } from '../../lib/auth';
import { Input } from '../../components/Input';

export default function SettingsPage(): ReactElement {
  const { state, ready, reset, setBaseCurrency, mutate } = useLedger();
  const { phase, enabled } = useCloudSync();
  const { user, signOut } = useAuth();
  const [isBackupModalOpen, setIsBackupModalOpen] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  if (!ready) return <p>Loading…</p>;

  const handleExport = () => {
    const dataStr = 'data:text/json;charset=utf-8,' + encodeURIComponent(JSON.stringify(state));
    const downloadAnchorNode = document.createElement('a');
    downloadAnchorNode.setAttribute('href', dataStr);
    downloadAnchorNode.setAttribute(
      'download',
      `1wallet_backup_${new Date().toISOString().split('T')[0]}.json`,
    );
    document.body.appendChild(downloadAnchorNode);
    downloadAnchorNode.click();
    downloadAnchorNode.remove();
  };

  const handleImport = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = async (event) => {
      try {
        const json = JSON.parse(event.target?.result as string);
        // Extremely simple import, replaces whole state
        if (confirm('This will replace your entire ledger with the imported data. Are you sure?')) {
          await mutate((draft) => {
            Object.assign(draft, json);
          });
          alert('Import successful');
        }
      } catch (err) {
        alert('Invalid backup file');
      }
    };
    reader.readAsText(file);
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.lg, width: '100%' }}>
      <h1 style={{ margin: 0, fontSize: 32, fontWeight: 700 }}>Settings</h1>

      <div style={{ display: 'grid', gap: tokens.space.lg, maxWidth: 700 }}>
        <Card title="Preferences">
          <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.md }}>
            <Select
              label="Base Currency"
              value={state.preferences.baseCurrency}
              onChange={(e) => void setBaseCurrency(e.target.value)}
            >
              {['INR', 'USD', 'EUR', 'GBP', 'AED', 'SGD', 'JPY'].map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </Select>

            <Select
              label="Theme"
              value={state.preferences.theme || 'system'}
              onChange={(e) =>
                void mutate(
                  (draft) => {
                    draft.preferences.theme = e.target.value as any;
                  },
                  { slices: ['preferences'] },
                )
              }
            >
              <option value="system">System Default</option>
              <option value="light">Light Mode</option>
              <option value="dark">Dark Mode</option>
              <option value="amoled">True Black (AMOLED)</option>
            </Select>

            <Select
              label="Accent Color Style"
              value={state.preferences.themeAccent?.source || 'system'}
              onChange={(e) =>
                void mutate(
                  (draft) => {
                    draft.preferences.themeAccent = {
                      ...draft.preferences.themeAccent,
                      source: e.target.value as any,
                    };
                  },
                  { slices: ['preferences'] },
                )
              }
            >
              <option value="system">System Default</option>
              <option value="custom">Custom Color</option>
            </Select>

            {state.preferences.themeAccent?.source === 'custom' && (
              <Input
                label="Custom Hex Color"
                type="color"
                value={state.preferences.themeAccent?.customColor || '#000000'}
                onChange={(e) =>
                  void mutate(
                    (draft) => {
                      draft.preferences.themeAccent = {
                        source: 'custom',
                        customColor: e.target.value,
                      };
                    },
                    { slices: ['preferences'] },
                  )
                }
              />
            )}
          </div>
        </Card>

        <Card title="Data Backup & Sync">
          {enabled ? (
            <>
              <p style={{ color: 'var(--color-on-surface-variant)', margin: 0 }}>
                You are signed in as <strong>{user?.email}</strong>.
              </p>
              <p style={{ color: 'var(--color-on-surface-variant)', margin: '8px 0 0' }}>
                Cloud Sync Status: <strong style={{ textTransform: 'capitalize' }}>{phase}</strong>
              </p>
              <div style={{ display: 'flex', gap: tokens.space.md, marginTop: tokens.space.md }}>
                <Button variant="secondary" onClick={() => void signOut()}>
                  Sign Out
                </Button>
              </div>
            </>
          ) : (
            <>
              <p style={{ color: 'var(--color-on-surface-variant)', margin: 0 }}>
                Your ledger is stored locally in your browser. You can manually export your data for
                safekeeping or import a backup.
              </p>
              <div style={{ display: 'flex', gap: tokens.space.md, marginTop: tokens.space.md }}>
                <Button onClick={handleExport}>Export Backup</Button>
                <Button variant="secondary" onClick={() => fileInputRef.current?.click()}>
                  Import Backup
                </Button>
                <Button
                  variant="secondary"
                  onClick={() => {
                    window.location.href = '/settings/import-csv';
                  }}
                >
                  Import Bank CSV
                </Button>
                <input
                  type="file"
                  accept=".json"
                  style={{ display: 'none' }}
                  ref={fileInputRef}
                  onChange={handleImport}
                />
              </div>
            </>
          )}
        </Card>

        <Card title="Danger Zone">
          <p style={{ color: 'var(--color-on-surface-variant)', margin: 0 }}>
            Permanently delete all your data. This action cannot be undone unless you have a backup.
          </p>
          <div style={{ marginTop: tokens.space.md }}>
            <Button
              variant="danger"
              onClick={() => {
                if (confirm('Erase everything in this browser?')) void reset();
              }}
            >
              Reset Ledger
            </Button>
          </div>
        </Card>
      </div>
    </div>
  );
}
