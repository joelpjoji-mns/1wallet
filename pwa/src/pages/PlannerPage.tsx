import { useMemo } from 'react';
import { useWalletData } from '../context/WalletDataContext';
import { formatMoney, upcomingTransactions } from '../lib/ledgerSelectors';

/**
 * There is no `budgets`/`goals` collection in the current cloud snapshot
 * schema (see `_encodeCloudSnapshotData` in
 * `lib/src/cloud_sync/cloud_sync_controller.dart` — it only ever writes
 * accounts/categories/transactions/captureCandidates/importBatches/
 * exchangeRates/preferences). Rather than inventing budget/goal figures that
 * don't exist in the synced data, the planner surfaces real forward-looking
 * data that *is* synced: scheduled/recurring transactions and loan payoff
 * details already present on loan accounts.
 */
export function PlannerPage() {
  const { snapshot } = useWalletData();
  const { transactions, accounts, categories, preferences } = snapshot;
  const locale = preferences.locale || 'en-US';

  const categoryById = new Map(categories.map((c) => [c.id, c] as const));
  const accountById = new Map(accounts.map((a) => [a.id, a] as const));

  const upcoming = useMemo(
    () => upcomingTransactions(transactions, new Date().toISOString(), 30),
    [transactions],
  );

  const loanAccounts = accounts.filter((a) => a.type === 'loan' && !a.isArchived && a.loanDetails);

  const recurringUpcomingTotal = upcoming.reduce((sum, t) => {
    return t.type === 'expense' ? sum + Math.abs(t.amount.amountMinor) : sum;
  }, 0);
  const displayCurrency = preferences.displayCurrency || 'USD';

  return (
    <div className="section-panel">
      <header className="section-header">
        <div>
          <h1>Planner</h1>
          <p>Upcoming scheduled payments and loan payoffs from your real ledger.</p>
        </div>
      </header>

      <div className="glass-card" style={{ marginBottom: 20 }}>
        <h3 style={{ color: 'var(--text-muted)', fontSize: '14px', fontWeight: 600, marginBottom: '8px' }}>
          Next 30 days — scheduled outgoings
        </h3>
        <div className="stat-value" style={{ fontSize: 28 }}>
          {formatMoney({ amountMinor: recurringUpcomingTotal, currency: displayCurrency }, locale)}
        </div>
      </div>

      <div className="glass-card" style={{ marginBottom: 20 }}>
        <h3 style={{ marginBottom: 12 }}>Upcoming scheduled transactions</h3>
        {upcoming.length === 0 ? (
          <p style={{ color: 'var(--text-muted)' }}>No scheduled transactions in the next 30 days.</p>
        ) : (
          upcoming.map((t) => (
            <div key={t.id} className="transaction-row">
              <div>
                <div style={{ fontWeight: 600 }}>
                  {t.name || categoryById.get(t.categoryId ?? '')?.name || t.type}
                </div>
                <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>
                  {accountById.get(t.accountId)?.name ?? 'Unknown'} ·{' '}
                  {new Date(t.occurredAt).toLocaleDateString(locale)}
                  {t.recurrenceFrequency ? ` · repeats ${t.recurrenceFrequency}` : ''}
                </div>
              </div>
              <div style={{ fontWeight: 600 }}>{formatMoney(t.amount, locale)}</div>
            </div>
          ))
        )}
      </div>

      <div className="glass-card">
        <h3 style={{ marginBottom: 12 }}>Loan payoff plans</h3>
        {loanAccounts.length === 0 ? (
          <p style={{ color: 'var(--text-muted)' }}>No loan accounts synced.</p>
        ) : (
          loanAccounts.map((a) => {
            const details = a.loanDetails;
            return (
              <div key={a.id} className="transaction-row">
                <div>
                  <div style={{ fontWeight: 600 }}>{a.name}</div>
                  <div style={{ fontSize: 12, color: 'var(--text-muted)' }}>
                    {details?.repaymentCount ? `${details.repaymentCount} payments` : 'Ongoing'}
                    {details?.recurrenceFrequency ? ` · ${details.recurrenceFrequency}` : ''}
                  </div>
                </div>
                <div style={{ fontWeight: 600 }}>
                  {details?.repaymentAmount ? formatMoney(details.repaymentAmount, locale) : '—'}
                </div>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}
