import { useMemo, useState } from 'react';
import { Plus, Search } from 'lucide-react';
import { useWalletData } from '../context/WalletDataContext';
import { formatMoney, sortedTransactions } from '../lib/ledgerSelectors';
import { generateId } from '../lib/id';
import type { TransactionRecord } from '../lib/ledgerTypes';
import {
  TransactionModal,
  transactionToFormValue,
  type TransactionFormValue,
} from '../components/TransactionModal';

export function HistoryPage() {
  const { snapshot, addTransaction, updateTransaction, deleteTransaction, addCategory } = useWalletData();
  const { accounts, categories, transactions, preferences } = snapshot;
  const locale = preferences.locale || 'en-US';

  const [search, setSearch] = useState('');
  const [accountFilter, setAccountFilter] = useState('');
  const [editing, setEditing] = useState<TransactionRecord | null>(null);
  const [showModal, setShowModal] = useState(false);

  const categoryById = useMemo(() => new Map(categories.map((c) => [c.id, c] as const)), [categories]);
  const accountById = useMemo(() => new Map(accounts.map((a) => [a.id, a] as const)), [accounts]);

  const filtered = useMemo(() => {
    const term = search.trim().toLowerCase();
    return sortedTransactions(transactions, { includeScheduled: true }).filter((t) => {
      if (accountFilter && t.accountId !== accountFilter && t.counterAccountId !== accountFilter) {
        return false;
      }
      if (!term) return true;
      const haystack = `${t.name ?? ''} ${t.notes ?? ''} ${categoryById.get(t.categoryId ?? '')?.name ?? ''}`.toLowerCase();
      return haystack.includes(term);
    });
  }, [transactions, search, accountFilter, categoryById]);

  const handleSubmit = (value: TransactionFormValue) => {
    const amountMinor = Math.round(Number.parseFloat(value.amountMajor || '0') * 100);
    const account = accountById.get(value.accountId);
    const currency = account?.currency ?? value.currency;
    const patch: Partial<TransactionRecord> = {
      type: value.type,
      status: value.status,
      accountId: value.accountId,
      counterAccountId: value.type === 'transfer' ? value.counterAccountId || null : null,
      categoryId: value.type === 'transfer' ? null : value.categoryId || null,
      amount: { amountMinor, currency },
      baseAmount: { amountMinor, currency },
      occurredAt: new Date(value.occurredAt).toISOString(),
      name: value.name || null,
      notes: value.notes || null,
      recurrenceFrequency: value.recurrenceFrequency || null,
    };

    if (value.id) {
      void updateTransaction(value.id, patch);
    } else {
      const newTx: TransactionRecord = {
        id: generateId('tx'),
        source: 'manual',
        attachments: [],
        recurrenceInterval: 1,
        isReimbursable: false,
        isTaxDeductible: false,
        isExcludedFromReports: false,
        ...patch,
      } as TransactionRecord;
      void addTransaction(newTx);
    }
    setShowModal(false);
    setEditing(null);
  };

  const handleCreateCategory = (name: string, kind: string): string => {
    const id = generateId('cat');
    void addCategory({ id, name, kind, isArchived: false, sortOrder: categories.length });
    return id;
  };

  return (
    <div className="section-panel">
      <header className="section-header">
        <div>
          <h1>History</h1>
          <p>Browse every synced transaction and receipt.</p>
        </div>
        <button
          type="button"
          className="btn-primary"
          onClick={() => {
            setEditing(null);
            setShowModal(true);
          }}
        >
          <Plus size={18} /> Add transaction
        </button>
      </header>

      <div className="glass-card" style={{ display: 'flex', gap: 12, marginBottom: 20, flexWrap: 'wrap' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flex: 1, minWidth: 220 }}>
          <Search size={18} color="var(--text-muted)" />
          <input
            type="text"
            placeholder="Search name, notes, category…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            style={{ background: 'transparent', border: 'none', color: 'inherit', width: '100%', outline: 'none' }}
          />
        </div>
        <select value={accountFilter} onChange={(e) => setAccountFilter(e.target.value)}>
          <option value="">All accounts</option>
          {accounts.map((a) => (
            <option key={a.id} value={a.id}>
              {a.name}
            </option>
          ))}
        </select>
      </div>

      <div className="glass-card">
        {filtered.length === 0 ? (
          <p style={{ color: 'var(--text-muted)' }}>No transactions match.</p>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column' }}>
            {filtered.map((t) => (
              <button
                key={t.id}
                type="button"
                className="transaction-row"
                style={{ width: '100%', background: 'none', border: 'none', cursor: 'pointer', color: 'inherit', textAlign: 'left' }}
                onClick={() => {
                  setEditing(t);
                  setShowModal(true);
                }}
              >
                <div>
                  <div style={{ fontWeight: 600 }}>
                    {t.name || categoryById.get(t.categoryId ?? '')?.name || t.type}
                  </div>
                  <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                    {accountById.get(t.accountId)?.name ?? 'Unknown'} ·{' '}
                    {new Date(t.occurredAt).toLocaleString(locale)} · {t.status}
                  </div>
                </div>
                <div style={{ fontWeight: 600 }}>{formatMoney(t.amount, locale)}</div>
              </button>
            ))}
          </div>
        )}
      </div>

      {showModal && (
        <TransactionModal
          accounts={accounts}
          categories={categories}
          initial={transactionToFormValue(editing ?? undefined, accounts[0]?.id ?? '')}
          isEditing={editing != null}
          onCancel={() => {
            setShowModal(false);
            setEditing(null);
          }}
          onSubmit={handleSubmit}
          onDelete={
            editing
              ? () => {
                  void deleteTransaction(editing.id);
                  setShowModal(false);
                  setEditing(null);
                }
              : undefined
          }
          onCreateCategory={handleCreateCategory}
        />
      )}
    </div>
  );
}
