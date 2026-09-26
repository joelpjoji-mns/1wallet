// The entire signed-in workspace, isolated into its own module so it can be
// `React.lazy()`-loaded from `App.tsx` — see the doc comment there for why:
// `WalletDataProvider` (and everything it transitively imports —
// `../lib/walletSync`, `firebase/firestore`'s runTransaction/onSnapshot/
// getDocs/etc., `pako`'s gzip/ungzip, `../lib/ledgerCodec`) must never be
// part of the bundle the login screen needs, since a signed-out visitor has
// no use for any of it yet.
import type { LucideIcon } from 'lucide-react';
import { Calendar, LayoutDashboard, LineChart, LogOut, Receipt, Wallet } from 'lucide-react';
import { lazy, Suspense, useState } from 'react';
import { useAuth } from './context/AuthContext';
import { WalletDataProvider, useWalletData } from './context/WalletDataContext';

const AccountsPage = lazy(() =>
  import('./pages/AccountsPage').then((module) => ({ default: module.AccountsPage })),
);
const CalendarPage = lazy(() =>
  import('./pages/CalendarPage').then((module) => ({ default: module.CalendarPage })),
);
const HistoryPage = lazy(() =>
  import('./pages/HistoryPage').then((module) => ({ default: module.HistoryPage })),
);
const HomePage = lazy(() =>
  import('./pages/HomePage').then((module) => ({ default: module.HomePage })),
);
const PlannerPage = lazy(() =>
  import('./pages/PlannerPage').then((module) => ({ default: module.PlannerPage })),
);

type SectionId = 'home' | 'history' | 'calendar' | 'planner' | 'accounts';

type NavItem = {
  id: SectionId;
  name: string;
  description: string;
  icon: LucideIcon;
};

const navItems: NavItem[] = [
  { id: 'home', name: 'Home', description: 'Overview and quick actions', icon: LayoutDashboard },
  { id: 'history', name: 'History', description: 'Browse transactions and receipts', icon: Receipt },
  { id: 'calendar', name: 'Calendar', description: 'Review cashflow by date', icon: Calendar },
  { id: 'planner', name: 'Planner', description: 'Plan budgets, goals, and forecasts', icon: LineChart },
  { id: 'accounts', name: 'Accounts', description: 'Manage wallets, cards, and balances', icon: Wallet },
];

function SyncBadge() {
  const { phase, error } = useWalletData();
  if (phase === 'error' || phase === 'conflict') {
    return <span className="sync-badge sync-badge--error">{error ?? 'Sync issue'}</span>;
  }
  if (phase === 'loading' || phase === 'saving') {
    return <span className="sync-badge">{phase === 'loading' ? 'Loading…' : 'Syncing…'}</span>;
  }
  return <span className="sync-badge sync-badge--ok">Synced</span>;
}

/**
 * The explicit, user-confirmed escape hatch from the `conflict` phase's
 * dead end: `WalletDataContext.persist()` deliberately re-queues a
 * conflicted edit into `PendingSaveGuard` instead of auto-reloading over
 * it (see that handler's doc comment), which correctly protects the edit
 * from ever being silently discarded — but also means nothing in the app
 * could previously *resolve* that state, since `refresh()` is unreachable
 * from any page and this component only ever rendered a small `<span>`
 * badge. Without this banner, a conflicted edit stayed pending forever:
 * `SyncBadge` kept showing the error text, every realtime update and
 * manual `refresh()` kept correctly refusing to touch it, and the user had
 * no way to ever get back to a synced state short of reloading the whole
 * page (which drops the in-memory edit anyway, just without ever telling
 * the user that's what happened).
 *
 * Rendered prominently (not tucked into the sidebar badge) so it's visible
 * regardless of which section the user is on, with `role="alert"` so
 * screen readers announce it as soon as the conflict occurs. The message
 * deliberately does not say the edit is "saved"/"kept" anywhere durable: it
 * only exists in this tab's React state (`snapshot`), never written to
 * `localStorage`/IndexedDB/disk, so reloading or closing this tab loses it
 * exactly like any other unsaved browser form input would.
 *
 * The button's label is explicit about what it does — discards the edit,
 * not "retry" or "sync" — but a single accidental click destroying a
 * financial edit with no way back is still an unacceptably easy mistake,
 * so the label alone is not treated as sufficient confirmation: clicking it
 * opens a native `window.confirm()` prompt, and `discardConflictAndReload()`
 * only ever runs if that second, explicit confirmation is accepted.
 */
function ConflictBanner() {
  const { phase, error, discardConflictAndReload } = useWalletData();
  if (phase !== 'conflict') return null;

  const handleDiscardClick = () => {
    const confirmed = window.confirm(
      'Discard your unsaved edit and load the latest cloud data instead? This cannot be undone — the edit only exists in this tab and will be gone for good.',
    );
    if (!confirmed) return;
    void discardConflictAndReload();
  };

  return (
    <div className="conflict-banner" role="alert" aria-live="assertive">
      <p className="conflict-banner__message">
        {error ?? 'Your wallet changed on another device or tab. Your edit was not saved — it remains visible only in this browser tab and will be lost if you reload or close it before resolving.'}
      </p>
      <button
        type="button"
        className="btn-danger"
        onClick={handleDiscardClick}
      >
        Discard unsaved edit and load cloud
      </button>
    </div>
  );
}

function Sidebar({
  activeSection,
  onSectionChange,
}: {
  activeSection: SectionId;
  onSectionChange: (section: SectionId) => void;
}) {
  const { user, signOutUser } = useAuth();

  return (
    <div className="sidebar">
      <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '24px', padding: '0 16px' }}>
        <div style={{ width: 40, height: 40, borderRadius: 12, background: 'var(--primary)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <Wallet size={24} color="white" />
        </div>
        <h2 style={{ fontSize: '20px', fontWeight: 800 }}>1Wallet</h2>
      </div>

      <div style={{ padding: '0 16px', marginBottom: '20px' }}>
        <SyncBadge />
      </div>

      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: '8px' }}>
        {navItems.map(item => (
          <button
            key={item.id}
            type="button"
            className={`nav-item ${activeSection === item.id ? 'active' : ''}`}
            onClick={() => onSectionChange(item.id)}
            aria-current={activeSection === item.id ? 'page' : undefined}
          >
            <item.icon size={20} />
            {item.name}
          </button>
        ))}
      </div>

      <div style={{ marginTop: 'auto', paddingTop: '24px', borderTop: '1px solid var(--border)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          <div style={{ width: 40, height: 40, borderRadius: '50%', background: 'var(--glass)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <span style={{ fontWeight: 'bold' }}>{user?.displayName?.[0] || 'U'}</span>
          </div>
          <div style={{ flex: 1, overflow: 'hidden' }}>
            <div style={{ fontWeight: 600, fontSize: '14px', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
              {user?.displayName || 'User'}
            </div>
            <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>My Wallet</div>
          </div>
          <button className="icon-btn" onClick={() => void signOutUser()} aria-label="Sign out" title="Sign out">
            <LogOut size={18} />
          </button>
        </div>
      </div>
    </div>
  );
}

function HomeBottomIsland({ activeSection, onSectionChange }: { activeSection: SectionId; onSectionChange: (section: SectionId) => void }) {
  return (
    <nav className="home-bottom-island" aria-label="Home quick navigation">
      <div className="home-bottom-island__track">
        {navItems.map(item => (
          <button
            key={item.id}
            type="button"
            className={`home-bottom-island__item ${activeSection === item.id ? 'active' : ''}`}
            onClick={() => onSectionChange(item.id)}
            aria-pressed={activeSection === item.id}
          >
            <item.icon size={22} />
            {item.name}
          </button>
        ))}
      </div>
    </nav>
  );
}

export function Workspace() {
  const { user } = useAuth();
  const [activeSection, setActiveSection] = useState<SectionId>('home');

  const content = (() => {
    switch (activeSection) {
      case 'home':
        return <HomePage />;
      case 'history':
        return <HistoryPage />;
      case 'calendar':
        return <CalendarPage />;
      case 'planner':
        return <PlannerPage />;
      case 'accounts':
        return <AccountsPage />;
      default:
        return null;
    }
  })();

  return (
    // `key={user?.uid}` is the primary fix for a privacy bug: `AuthProvider`
    // can switch directly from signed-in user A to signed-in user B while
    // this component itself stays mounted (only its `user` prop/context
    // value changes), and `WalletDataProvider`'s own `snapshot` state is only
    // reset by an *effect*, which runs after React commits/paints — so one
    // render (and potentially one visible frame) could show `user=B` in the
    // header/sidebar alongside `snapshot` still holding user A's accounts
    // and transactions. Keying by uid forces React to fully unmount the old
    // `WalletDataProvider` instance (and every descendant that reads wallet
    // data) and mount a brand-new one *synchronously as part of the same
    // reconciliation pass* whenever the uid changes — the new instance's
    // `snapshot` state is always freshly initialized to
    // `emptyLedgerSnapshot()` via `useState`, so there is structurally no
    // render where `user.uid` has changed but `snapshot` hasn't. This is
    // stronger than any effect-based reset (including `useLayoutEffect`,
    // which still runs *after* the render that key-based unmounting
    // prevents from ever happening at all). The existing unmount cleanup in
    // `WalletDataProvider` (which cancels any pending debounced-save timer
    // and clears `PendingSaveGuard`) still fires normally when the old
    // instance is torn down, so an in-flight save for the old user is never
    // left dangling. See `uidSwitchRender.test.ts` for the regression
    // (it reads this file's source directly to guard against this key
    // being silently removed).
    <WalletDataProvider key={user?.uid ?? 'signed-out'}>
      <div className="app-container">
        <Sidebar activeSection={activeSection} onSectionChange={setActiveSection} />
        <main className={`main-content ${activeSection === 'home' ? 'with-home-island' : ''}`}>
          <ConflictBanner />
          <Suspense fallback={<p role="status">Loading section…</p>}>{content}</Suspense>
        </main>
        {activeSection === 'home' ? (
          <HomeBottomIsland activeSection={activeSection} onSectionChange={setActiveSection} />
        ) : null}
      </div>
    </WalletDataProvider>
  );
}
