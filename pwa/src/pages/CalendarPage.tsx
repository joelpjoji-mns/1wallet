import { useMemo, useState } from 'react';
import { ChevronLeft, ChevronRight } from 'lucide-react';
import { useWalletData } from '../context/WalletDataContext';
import { dailyCashflow, formatMoney } from '../lib/ledgerSelectors';

function isoDateKey(year: number, monthIndex: number, day: number): string {
  const d = new Date(year, monthIndex, day);
  const pad = (n: number) => n.toString().padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export function CalendarPage() {
  const { snapshot } = useWalletData();
  const { transactions, preferences } = snapshot;
  const locale = preferences.locale || 'en-US';
  const displayCurrency = preferences.displayCurrency || 'USD';

  const [cursor, setCursor] = useState(() => {
    const now = new Date();
    return new Date(now.getFullYear(), now.getMonth(), 1);
  });

  const cashflow = useMemo(() => dailyCashflow(transactions), [transactions]);

  const year = cursor.getFullYear();
  const month = cursor.getMonth();
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const firstWeekday = new Date(year, month, 1).getDay();

  const [selectedDate, setSelectedDate] = useState<string | null>(null);

  const dayCells = useMemo(() => {
    const cells: (number | null)[] = Array.from({ length: firstWeekday }, () => null);
    for (let d = 1; d <= daysInMonth; d++) cells.push(d);
    return cells;
  }, [firstWeekday, daysInMonth]);

  const monthTotals = useMemo(() => {
    let income = 0;
    let expense = 0;
    for (let d = 1; d <= daysInMonth; d++) {
      const bucket = cashflow.get(isoDateKey(year, month, d));
      if (bucket) {
        income += bucket.incomeMinor;
        expense += bucket.expenseMinor;
      }
    }
    return { income, expense };
  }, [cashflow, daysInMonth, year, month]);

  const selectedTransactions = selectedDate
    ? transactions.filter((t) => t.occurredAt.slice(0, 10) === selectedDate)
    : [];

  return (
    <div className="section-panel">
      <header className="section-header">
        <div>
          <h1>Calendar</h1>
          <p>Real daily cashflow computed from your synced transactions.</p>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <button type="button" className="icon-btn" onClick={() => setCursor(new Date(year, month - 1, 1))} aria-label="Previous month">
            <ChevronLeft size={18} />
          </button>
          <strong>{cursor.toLocaleDateString(locale, { month: 'long', year: 'numeric' })}</strong>
          <button type="button" className="icon-btn" onClick={() => setCursor(new Date(year, month + 1, 1))} aria-label="Next month">
            <ChevronRight size={18} />
          </button>
        </div>
      </header>

      <div className="glass-card" style={{ marginBottom: 20, display: 'flex', gap: 32 }}>
        <div>
          <div style={{ fontSize: 12, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Income</div>
          <div style={{ fontSize: 22, fontWeight: 700, color: '#4ade80' }}>
            {formatMoney({ amountMinor: monthTotals.income, currency: displayCurrency }, locale)}
          </div>
        </div>
        <div>
          <div style={{ fontSize: 12, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Expense</div>
          <div style={{ fontSize: 22, fontWeight: 700, color: '#f87171' }}>
            {formatMoney({ amountMinor: monthTotals.expense, currency: displayCurrency }, locale)}
          </div>
        </div>
        <div>
          <div style={{ fontSize: 12, color: 'var(--text-muted)', textTransform: 'uppercase' }}>Net</div>
          <div style={{ fontSize: 22, fontWeight: 700 }}>
            {formatMoney({ amountMinor: monthTotals.income - monthTotals.expense, currency: displayCurrency }, locale)}
          </div>
        </div>
      </div>

      <div className="glass-card">
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 8, marginBottom: 8 }}>
          {['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].map((d) => (
            <div key={d} style={{ textAlign: 'center', fontSize: 12, color: 'var(--text-muted)', fontWeight: 700 }}>
              {d}
            </div>
          ))}
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 8 }}>
          {dayCells.map((day, i) => {
            if (day == null) return <div key={`empty-${i}`} />;
            const key = isoDateKey(year, month, day);
            const bucket = cashflow.get(key);
            const net = bucket ? bucket.incomeMinor - bucket.expenseMinor : 0;
            return (
              <button
                key={key}
                type="button"
                onClick={() => setSelectedDate(key)}
                style={{
                  aspectRatio: '1',
                  borderRadius: 10,
                  border: selectedDate === key ? '1px solid var(--primary)' : '1px solid var(--border)',
                  background: bucket ? 'var(--glass)' : 'transparent',
                  color: 'inherit',
                  cursor: 'pointer',
                  display: 'flex',
                  flexDirection: 'column',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: 2,
                  padding: 4,
                }}
              >
                <span style={{ fontSize: 12, fontWeight: 700 }}>{day}</span>
                {bucket && (
                  <span style={{ fontSize: 9, color: net >= 0 ? '#4ade80' : '#f87171' }}>
                    {net >= 0 ? '+' : ''}
                    {(net / 100).toFixed(0)}
                  </span>
                )}
              </button>
            );
          })}
        </div>
      </div>

      {selectedDate && (
        <div className="glass-card" style={{ marginTop: 20 }}>
          <h3 style={{ marginBottom: 12 }}>{new Date(selectedDate).toLocaleDateString(locale, { dateStyle: 'full' })}</h3>
          {selectedTransactions.length === 0 ? (
            <p style={{ color: 'var(--text-muted)' }}>No transactions on this day.</p>
          ) : (
            selectedTransactions.map((t) => (
              <div key={t.id} className="transaction-row">
                <span>{t.name || t.type}</span>
                <span>{formatMoney(t.amount, locale)}</span>
              </div>
            ))
          )}
        </div>
      )}
    </div>
  );
}
