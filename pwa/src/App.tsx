import type { LucideIcon } from 'lucide-react';
import { Calendar, LayoutDashboard, LineChart, LogIn, LogOut, Receipt, Wallet } from 'lucide-react';
import { useState } from 'react';
import { signInWithPopup } from 'firebase/auth';
import { auth, googleProvider } from './lib/firebase';
import { AuthProvider, useAuth } from './context/AuthContext';
import { WalletDataProvider, useWalletData } from './context/WalletDataContext';
import { AccountsPage } from './pages/AccountsPage';
import { CalendarPage } from './pages/CalendarPage';
import { HistoryPage } from './pages/HistoryPage';
import { HomePage } from './pages/HomePage';
import { PlannerPage } from './pages/PlannerPage';

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

function LoginScreen() {
  const [signingIn, setSigningIn] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleLogin = async () => {
    setSigningIn(true);
    setError(null);
    try {
      await signInWithPopup(auth, googleProvider);
    } catch (e) {
      console.error(e);
      setError('Sign-in was cancelled or failed. Please try again.');
    } finally {
      setSigningIn(false);
    }
  };

  return (
    <div className="login-container">
      <div className="glass-card login-box">
        <div style={{ marginBottom: '24px' }}>
          <Wallet size={48} color="var(--primary)" style={{ margin: '0 auto' }} />
        </div>
        <h1 style={{ fontSize: '28px', marginBottom: '8px' }}>1Wallet Web</h1>
        <p style={{ color: 'var(--text-muted)', marginBottom: '32px' }}>Sign in to access your dashboard</p>
        <button className="btn-primary" onClick={handleLogin} disabled={signingIn} style={{ width: '100%' }}>
          <LogIn size={20} /> {signingIn ? 'Signing in…' : 'Continue with Google'}
        </button>
        {error && <p style={{ color: '#f87171', marginTop: 16, fontSize: 14 }}>{error}</p>}
      </div>
    </div>
  );
}

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

function Workspace() {
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
    <WalletDataProvider>
      <div className="app-container">
        <Sidebar activeSection={activeSection} onSectionChange={setActiveSection} />
        <main className={`main-content ${activeSection === 'home' ? 'with-home-island' : ''}`}>{content}</main>
        {activeSection === 'home' ? (
          <HomeBottomIsland activeSection={activeSection} onSectionChange={setActiveSection} />
        ) : null}
      </div>
    </WalletDataProvider>
  );
}

function AppShell() {
  const { user, loading } = useAuth();

  if (loading) {
    return <div className="login-container">Loading...</div>;
  }

  if (!user) {
    return <LoginScreen />;
  }

  return <Workspace />;
}

function App() {
  return (
    <AuthProvider>
      <AppShell />
    </AuthProvider>
  );
}

export default App;
