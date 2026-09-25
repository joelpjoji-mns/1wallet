import { useMemo } from 'react';
import { Receipt } from 'lucide-react';
import { useWalletData } from '../context/WalletDataContext';
import {
  accountBalance,
  accountBalanceMap,
  formatMoney,
  sortedTransactions,
} from '../lib/ledgerSelectors';

/** Real home dashboard: totals and recents are computed only from synced data. */
export function HomePage() {
  const { snapshot } = useWalletData();
  const { accounts, transactions, categories, preferences } = snapshot;
  const displayCurrency = preferences.displayCurrency || 'USD';
  const locale = preferences.locale || 'en-US';

  const balances = useMemo(() => accountBalanceMap(accounts, transactions), [accounts, transactions]);

  const activeAccounts = accounts.filter((a) => !a.isArchived && a.includeInTotals);

  const totalsByCurrency = useMemo(() => {
    const totals = new Map<string, number>();
    for (const account of activeAccounts) {
      const balance = accountBalance(balances, account);
      totals.set(balance.currency, (totals.get(balance.currency) ?? 0) + balance.amountMinor);
    }
    return totals;
  }, [activeAccounts, balances]);

  const recent = useMemo(
    () => sortedTransactions(transactions, { includeScheduled: false }).slice(0, 6),
    [transactions],
  );

  const now = new Date();
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1).getTime();
  const categoryById = useMemo(() => new Map(categories.map((c) => [c.id, c] as const)), [categories]);

  const topCategories = useMemo(() => {
    const spend = new Map<string, number>();
    for (const t of transactions) {
      if (t.type !== 'expense') continue;
      if (Date.parse(t.occurredAt) < monthStart) continue;
      if (!t.categoryId) continue;
      spend.set(t.categoryId, (spend.get(t.categoryId) ?? 0) + Math.abs(t.amount.amountMinor));
    }
    return [...spend.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 4)
      .map(([categoryId, amountMinor]) => ({
        category: categoryById.get(categoryId),
        amountMinor,
      }));
  }, [transactions, monthStart, categoryById]);

  const maxCategorySpend = topCategories[0]?.amountMinor || 1;

  return (
    <div style={{ maxWidth: '1400px', margin: '0 auto' }}>
      <header style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '32px' }}>
        <div>
          <h1 style={{ fontSize: '28px', fontWeight: 800 }}>Overview</h1>
          <p style={{ color: 'var(--text-muted)' }}>
            {accounts.length === 0
              ? 'No wallet data synced yet — add an account to get started.'
              : "Here's your real, synced financial summary."}
          </p>
        </div>
      </header>

      <div className="dashboard-grid">
        <div
          className="glass-card"
          style={{ gridColumn: '1 / -1', background: 'linear-gradient(135deg, rgba(59, 130, 246, 0.2), rgba(30, 41, 59, 0.8))' }}
        >
          <h3 style={{ color: 'var(--text-muted)', fontSize: '14px', textTransform: 'uppercase', letterSpacing: '1px', fontWeight: 600 }}>
            Total Balance
          </h3>
          {totalsByCurrency.size === 0 ? (
            <div className="stat-value" style={{ fontSize: '20px' }}>
              No accounts yet
            </div>
          ) : (
            [...totalsByCurrency.entries()].map(([currency, amountMinor]) => (
              <div className="stat-value" key={currency}>
                {formatMoney({ amountMinor, currency }, locale)}
              </div>
            ))
          )}
        </div>

        <div className="glass-card">
          <h3 style={{ color: 'var(--text-muted)', fontSize: '14px', fontWeight: 600, marginBottom: '16px' }}>
            Recent Transactions
          </h3>
          {recent.length === 0 ? (
            <p style={{ color: 'var(--text-muted)' }}>No transactions yet.</p>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column' }}>
              {recent.map((t) => (
                <div key={t.id} className="transaction-row">
                  <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
                    <div style={{ width: 40, height: 40, borderRadius: 12, background: 'var(--glass)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                      <Receipt size={20} color="var(--primary)" />
                    </div>
                    <div>
                      <div style={{ fontWeight: 600 }}>
                        {t.name || categoryById.get(t.categoryId ?? '')?.name || t.type}
                      </div>
                      <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                        {accounts.find((a) => a.id === t.accountId)?.name ?? 'Unknown account'} ·{' '}
                        {new Date(t.occurredAt).toLocaleDateString(locale)}
                      </div>
                    </div>
                  </div>
                  <div style={{ fontWeight: 600 }}>{formatMoney(t.amount, locale)}</div>
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="glass-card">
          <h3 style={{ color: 'var(--text-muted)', fontSize: '14px', fontWeight: 600, marginBottom: '16px' }}>
            Top Categories (this month)
          </h3>
          {topCategories.length === 0 ? (
            <p style={{ color: 'var(--text-muted)' }}>No categorized spending yet this month.</p>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              {topCategories.map(({ category, amountMinor }) => (
                <div key={category?.id ?? 'uncategorized'}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px', fontSize: '14px' }}>
                    <span>{category?.name ?? 'Uncategorized'}</span>
                    <span style={{ fontWeight: 600 }}>{formatMoney({ amountMinor, currency: displayCurrency }, locale)}</span>
                  </div>
                  <div style={{ height: 6, background: 'var(--glass)', borderRadius: 3, overflow: 'hidden' }}>
                    <div
                      style={{
                        width: `${Math.min(100, (amountMinor / maxCategorySpend) * 100)}%`,
                        height: '100%',
                        background: 'var(--primary)',
                        borderRadius: 3,
                      }}
                    />
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
