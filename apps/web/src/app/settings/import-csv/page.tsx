'use client';

import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import Papa from 'papaparse';
import { useRef, useState, type ReactElement } from 'react';
import { Button } from '../../../components/Button';
import { Card } from '../../../components/Card';

export default function ImportCsvPage(): ReactElement {
  const { state, mutate } = useLedger();
  const fileInputRef = useRef<HTMLInputElement>(null);
  
  const [data, setData] = useState<any[]>([]);
  const [columns, setColumns] = useState<string[]>([]);
  const [mapping, setMapping] = useState({ date: '', amount: '', description: '' });

  const handleImport = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    Papa.parse(file, {
      header: true,
      skipEmptyLines: true,
      complete: (results: any) => {
        if (results.meta.fields) {
          setColumns(results.meta.fields);
          setData(results.data);
        }
      },
    });
  };

  const executeImport = async () => {
    if (!mapping.date || !mapping.amount || !mapping.description) {
      alert('Please map all required columns.');
      return;
    }

    try {
      await mutate((draft) => {
        for (const row of data) {
          const dateStr = row[mapping.date];
          const amountStr = row[mapping.amount];
          const descStr = row[mapping.description];
          if (!dateStr || !amountStr) continue;

          draft.transactions.push({
            id: `imported_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
            userId: 'local',
            amount: Math.round(parseFloat(amountStr) * 100) as any,
            baseAmount: Math.round(parseFloat(amountStr) * 100) as any,
            occurredAt: new Date(dateStr).toISOString(),
            notes: descStr || '',
            accountId: draft.accounts[0]?.id || 'default',
            type: parseFloat(amountStr) < 0 ? 'expense' : 'income',
            categoryId: undefined,
            status: 'cleared',
            source: 'import',
            isReimbursable: false,
            isTaxDeductible: false,
            isExcludedFromReports: false,
            createdAt: new Date().toISOString(),
            updatedAt: new Date().toISOString(),
          });
        }
      });
      alert(`Imported ${data.length} transactions successfully!`);
      setData([]);
    } catch (e) {
      console.error(e);
      alert('Failed to import transactions.');
    }
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.lg, width: '100%' }}>
      <h1 style={{ margin: 0, fontSize: 32, fontWeight: 700 }}>Import Bank CSV</h1>

      <Card>
        <p style={{ color: 'var(--color-on-surface-variant)' }}>
          Select a CSV file downloaded from your bank to import transactions in bulk.
        </p>
        
        <div style={{ marginTop: tokens.space.md }}>
          <Button onClick={() => fileInputRef.current?.click()}>Select CSV File</Button>
          <input 
            type="file" 
            accept=".csv" 
            style={{ display: 'none' }} 
            ref={fileInputRef} 
            onChange={handleImport} 
          />
        </div>
      </Card>

      {data.length > 0 && (
        <Card title="Map Columns">
          <p style={{ color: 'var(--color-on-surface-variant)', marginBottom: tokens.space.md }}>
            Found {data.length} rows. Please map the columns to the corresponding fields.
          </p>

          <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.md }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: tokens.space.md }}>
              <span style={{ width: 100, fontWeight: 500 }}>Date</span>
              <select 
                style={{ flex: 1, padding: tokens.space.sm, borderRadius: tokens.radius.sm, border: '1px solid var(--color-outline)' }}
                value={mapping.date}
                onChange={(e) => setMapping(m => ({ ...m, date: e.target.value }))}
              >
                <option value="">Select column...</option>
                {columns.map(c => <option key={c} value={c}>{c}</option>)}
              </select>
            </div>

            <div style={{ display: 'flex', alignItems: 'center', gap: tokens.space.md }}>
              <span style={{ width: 100, fontWeight: 500 }}>Amount</span>
              <select 
                style={{ flex: 1, padding: tokens.space.sm, borderRadius: tokens.radius.sm, border: '1px solid var(--color-outline)' }}
                value={mapping.amount}
                onChange={(e) => setMapping(m => ({ ...m, amount: e.target.value }))}
              >
                <option value="">Select column...</option>
                {columns.map(c => <option key={c} value={c}>{c}</option>)}
              </select>
            </div>

            <div style={{ display: 'flex', alignItems: 'center', gap: tokens.space.md }}>
              <span style={{ width: 100, fontWeight: 500 }}>Description</span>
              <select 
                style={{ flex: 1, padding: tokens.space.sm, borderRadius: tokens.radius.sm, border: '1px solid var(--color-outline)' }}
                value={mapping.description}
                onChange={(e) => setMapping(m => ({ ...m, description: e.target.value }))}
              >
                <option value="">Select column...</option>
                {columns.map(c => <option key={c} value={c}>{c}</option>)}
              </select>
            </div>

            <Button onClick={executeImport} style={{ marginTop: tokens.space.md }}>
              Import {data.length} Transactions
            </Button>
          </div>
        </Card>
      )}
    </div>
  );
}
