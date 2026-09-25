import { useMemo, useState } from 'react';
import { Lock, Plus } from 'lucide-react';
import { useWalletData } from '../context/WalletDataContext';
import { accountBalance, accountBalanceMap, formatMoney } from '../lib/ledgerSelectors';
import { generateId } from '../lib/id';
import type { Account } from '../lib/ledgerTypes';
import { AccountModal, accountToFormValue, type AccountFormValue } from '../components/AccountModal';

export function AccountsPage() {
  const { snapshot, addAccount, updateAccount, archiveAccount } = useWalletData();
  const { accounts, transactions, preferences } = snapshot;
  const locale = preferences.locale || 'en-US';

  const [editing, setEditing] = useState<Account | null>(null);
  const [showModal, setShowModal] = useState(false);
  const [showArchived, setShowArchived] = useState(false);

  const balances = useMemo(() => accountBalanceMap(accounts, transactions), [accounts, transactions]);
  const visible = accounts.filter((a) => showArchived || !a.isArchived);

  const handleSubmit = (value: AccountFormValue) => {
    const openingBalance = {
      amountMinor: Math.round(Number.parseFloat(value.openingBalanceMajor || '0') * 100),
      currency: value.currency,
    };
    const patch = {
      name: value.name,
      type: value.type,
      currency: value.currency,
      openingBalance,
      institution: value.institution || null,
      groupName: value.groupName || null,
      includeInTotals: value.includeInTotals,
      includeInReports: value.includeInReports,
      includeInNetWorth: value.includeInNetWorth,
      showOnHome: value.showOnHome,
    };
    if (value.id) {
      void updateAccount(value.id, patch);
    } else {
      const newAccount: Account = {
        id: generateId('acc'),
        isArchived: false,
        sortOrder: accounts.length,
        ...patch,
      } as Account;
      void addAccount(newAccount);
    }
    setShowModal(false);
    setEditing(null);
  };

  return (
    <div className="section-panel">
      <header className="section-header">
        <div>
          <h1>Accounts</h1>
          <p>Manage wallets, cards, and balances — synced from your real ledger.</p>
        </div>
        <div style={{ display: 'flex', gap: 12 }}>
          <button type="button" className="btn-secondary" onClick={() => setShowArchived((v) => !v)}>
            {showArchived ? 'Hide archived' : 'Show archived'}
          </button>
          <button
            type="button"
            className="btn-primary"
            onClick={() => {
              setEditing(null);
              setShowModal(true);
            }}
          >
            <Plus size={18} /> Add account
          </button>
        </div>
      </header>

      {visible.length === 0 ? (
        <div className="glass-card placeholder-card">
          <p style={{ color: 'var(--text-muted)' }}>No accounts synced yet. Add your first account above.</p>
        </div>
      ) : (
        <div className="dashboard-grid">
          {visible.map((a) => {
            const balance = accountBalance(balances, a);
            const hasEncrypted = !!a.encryptedDetails && Object.keys(a.encryptedDetails).length > 0;
            return (
              <button
                key={a.id}
                type="button"
                className="glass-card"
                style={{ textAlign: 'left', cursor: 'pointer', opacity: a.isArchived ? 0.5 : 1 }}
                onClick={() => {
                  setEditing(a);
                  setShowModal(true);
                }}
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                  <div>
                    <h3 style={{ fontSize: 16, fontWeight: 700 }}>{a.name}</h3>
                    <p style={{ fontSize: 12, color: 'var(--text-muted)', textTransform: 'capitalize' }}>
                      {a.type}
                      {a.institution ? ` · ${a.institution}` : ''}
                      {a.cardLast4 ? ` ···· ${a.cardLast4}` : ''}
                      {a.accountLast4 && !a.cardLast4 ? ` ···· ${a.accountLast4}` : ''}
                    </p>
                  </div>
                  {hasEncrypted && (
                    <span title="Device-encrypted details are unavailable on web" style={{ color: 'var(--text-muted)' }}>
                      <Lock size={16} />
                    </span>
                  )}
                </div>
                <div className="stat-value" style={{ fontSize: 24, marginTop: 12 }}>
                  {formatMoney(balance, locale)}
                </div>
                {a.isArchived && <p style={{ fontSize: 12, color: 'var(--text-muted)' }}>Archived</p>}
              </button>
            );
          })}
        </div>
      )}

      {showModal && (
        <AccountModal
          initial={accountToFormValue(editing ?? undefined)}
          isEditing={editing != null}
          hasEncryptedDetails={!!editing?.encryptedDetails && Object.keys(editing.encryptedDetails).length > 0}
          isArchived={editing?.isArchived}
          onCancel={() => {
            setShowModal(false);
            setEditing(null);
          }}
          onSubmit={handleSubmit}
          onArchiveToggle={
            editing
              ? () => {
                  void archiveAccount(editing.id, !editing.isArchived);
                  setShowModal(false);
                  setEditing(null);
                }
              : undefined
          }
        />
      )}
    </div>
  );
}
