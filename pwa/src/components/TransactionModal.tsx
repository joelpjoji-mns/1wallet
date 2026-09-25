import { X } from 'lucide-react';
import { useState } from 'react';
import type { Account, TransactionRecord } from '../lib/ledgerTypes';

export interface TransactionFormValue {
  id?: string;
  type: string;
  status: string;
  accountId: string;
  counterAccountId: string;
  categoryId: string;
  amountMajor: string;
  currency: string;
  occurredAt: string;
  name: string;
  notes: string;
  recurrenceFrequency: string;
}

function toDatetimeLocal(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  const pad = (n: number) => n.toString().padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function transactionToFormValue(t?: TransactionRecord, defaultAccountId = ''): TransactionFormValue {
  if (!t) {
    return {
      type: 'expense',
      status: 'cleared',
      accountId: defaultAccountId,
      counterAccountId: '',
      categoryId: '',
      amountMajor: '',
      currency: 'USD',
      occurredAt: toDatetimeLocal(new Date().toISOString()),
      name: '',
      notes: '',
      recurrenceFrequency: '',
    };
  }
  return {
    id: t.id,
    type: t.type,
    status: t.status,
    accountId: t.accountId,
    counterAccountId: t.counterAccountId ?? '',
    categoryId: t.categoryId ?? '',
    amountMajor: (Math.abs(t.amount.amountMinor) / 100).toString(),
    currency: t.amount.currency,
    occurredAt: toDatetimeLocal(t.occurredAt),
    name: t.name ?? '',
    notes: t.notes ?? '',
    recurrenceFrequency: t.recurrenceFrequency ?? '',
  };
}

interface Props {
  accounts: Account[];
  categories: { id: string; name: string; kind: string }[];
  initial: TransactionFormValue;
  isEditing: boolean;
  onCancel: () => void;
  onSubmit: (value: TransactionFormValue) => void;
  onDelete?: () => void;
  onCreateCategory: (name: string, kind: string) => string;
}

export function TransactionModal({
  accounts,
  categories,
  initial,
  isEditing,
  onCancel,
  onSubmit,
  onDelete,
  onCreateCategory,
}: Props) {
  const [value, setValue] = useState<TransactionFormValue>(initial);
  const [newCategoryName, setNewCategoryName] = useState('');

  const activeAccounts = accounts.filter((a) => !a.isArchived);
  const categoryKind = value.type === 'income' ? 'income' : 'expense';
  const availableCategories = categories.filter((c) => c.kind === categoryKind);

  const set = <K extends keyof TransactionFormValue>(key: K, v: TransactionFormValue[K]) =>
    setValue((prev) => ({ ...prev, [key]: v }));

  const handleAccountChange = (id: string) => {
    const acc = accounts.find((a) => a.id === id);
    set('accountId', id);
    if (acc) set('currency', acc.currency);
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    let categoryId = value.categoryId;
    if (value.type !== 'transfer' && newCategoryName.trim()) {
      categoryId = onCreateCategory(newCategoryName.trim(), categoryKind);
    }
    onSubmit({ ...value, categoryId });
  };

  return (
    <div className="modal-backdrop" role="dialog" aria-modal="true">
      <form className="glass-card modal-card" onSubmit={handleSubmit}>
        <div className="modal-header">
          <h2>{isEditing ? 'Edit transaction' : 'Add transaction'}</h2>
          <button type="button" className="icon-btn" onClick={onCancel} aria-label="Close">
            <X size={18} />
          </button>
        </div>

        <div className="segmented">
          {['expense', 'income', 'transfer'].map((t) => (
            <button
              key={t}
              type="button"
              className={`segmented__item ${value.type === t ? 'active' : ''}`}
              onClick={() => set('type', t)}
            >
              {t[0]!.toUpperCase() + t.slice(1)}
            </button>
          ))}
        </div>

        <label className="field">
          <span>Amount</span>
          <input
            required
            type="number"
            min="0"
            step="0.01"
            inputMode="decimal"
            value={value.amountMajor}
            onChange={(e) => set('amountMajor', e.target.value)}
            placeholder="0.00"
          />
        </label>

        <label className="field">
          <span>{value.type === 'transfer' ? 'From account' : 'Account'}</span>
          <select required value={value.accountId} onChange={(e) => handleAccountChange(e.target.value)}>
            <option value="" disabled>
              Select account
            </option>
            {activeAccounts.map((a) => (
              <option key={a.id} value={a.id}>
                {a.name}
              </option>
            ))}
          </select>
        </label>

        {value.type === 'transfer' && (
          <label className="field">
            <span>To account</span>
            <select
              required
              value={value.counterAccountId}
              onChange={(e) => set('counterAccountId', e.target.value)}
            >
              <option value="" disabled>
                Select account
              </option>
              {activeAccounts
                .filter((a) => a.id !== value.accountId)
                .map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name}
                  </option>
                ))}
            </select>
          </label>
        )}

        {value.type !== 'transfer' && (
          <label className="field">
            <span>Category</span>
            <select value={value.categoryId} onChange={(e) => set('categoryId', e.target.value)}>
              <option value="">Uncategorized</option>
              {availableCategories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
            <input
              type="text"
              placeholder="Or create a new category…"
              value={newCategoryName}
              onChange={(e) => setNewCategoryName(e.target.value)}
              style={{ marginTop: 8 }}
            />
          </label>
        )}

        <label className="field">
          <span>Name / payee</span>
          <input type="text" value={value.name} onChange={(e) => set('name', e.target.value)} />
        </label>

        <label className="field">
          <span>Date &amp; time</span>
          <input
            required
            type="datetime-local"
            value={value.occurredAt}
            onChange={(e) => set('occurredAt', e.target.value)}
          />
        </label>

        <label className="field">
          <span>Status</span>
          <select value={value.status} onChange={(e) => set('status', e.target.value)}>
            <option value="cleared">Cleared</option>
            <option value="scheduled">Scheduled</option>
            <option value="planned">Planned</option>
          </select>
        </label>

        <label className="field">
          <span>Repeats</span>
          <select
            value={value.recurrenceFrequency}
            onChange={(e) => set('recurrenceFrequency', e.target.value)}
          >
            <option value="">Does not repeat</option>
            <option value="daily">Daily</option>
            <option value="weekly">Weekly</option>
            <option value="monthly">Monthly</option>
            <option value="yearly">Yearly</option>
          </select>
        </label>

        <label className="field">
          <span>Notes</span>
          <textarea value={value.notes} onChange={(e) => set('notes', e.target.value)} rows={2} />
        </label>

        <div className="modal-actions">
          {isEditing && onDelete && (
            <button type="button" className="btn-danger" onClick={onDelete}>
              Delete
            </button>
          )}
          <div style={{ flex: 1 }} />
          <button type="button" className="btn-secondary" onClick={onCancel}>
            Cancel
          </button>
          <button type="submit" className="btn-primary">
            Save
          </button>
        </div>
      </form>
    </div>
  );
}
