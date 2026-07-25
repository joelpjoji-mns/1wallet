import { useState, useEffect } from 'react';
import { LayoutDashboard, Receipt, Calendar, LineChart, Wallet, LogIn, Bell, Search } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import { auth, googleProvider } from './firebase';
import { signInWithPopup, onAuthStateChanged } from 'firebase/auth';
import type { User } from 'firebase/auth';

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
  const handleLogin = async () => {
    try {
      await signInWithPopup(auth, googleProvider);
    } catch (e) {
      console.error(e);
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
        <button className="btn-primary" onClick={handleLogin} style={{ width: '100%' }}>
          <LogIn size={20} /> Continue with Google
        </button>
      </div>
    </div>
  );
}

function Sidebar({ activeSection, onSectionChange }: { activeSection: SectionId; onSectionChange: (section: SectionId) => void }) {
  return (
    <div className="sidebar">
      <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '40px', padding: '0 16px' }}>
        <div style={{ width: 40, height: 40, borderRadius: 12, background: 'var(--primary)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <Wallet size={24} color="white" />
        </div>
        <h2 style={{ fontSize: '20px', fontWeight: 800 }}>1Wallet</h2>
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
            <span style={{ fontWeight: 'bold' }}>{auth.currentUser?.displayName?.[0] || 'U'}</span>
          </div>
          <div style={{ flex: 1, overflow: 'hidden' }}>
            <div style={{ fontWeight: 600, fontSize: '14px', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
              {auth.currentUser?.displayName || 'User'}
            </div>
            <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>My Wallet</div>
          </div>
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

function Dashboard() {
  return (
    <div style={{ maxWidth: '1400px', margin: '0 auto' }}>
      <header style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '32px' }}>
        <div>
          <h1 style={{ fontSize: '28px', fontWeight: 800 }}>Overview</h1>
          <p style={{ color: 'var(--text-muted)' }}>Welcome back! Here's your financial summary.</p>
        </div>
        <div style={{ display: 'flex', gap: '16px' }}>
          <button style={{ background: 'var(--glass)', border: '1px solid var(--border)', color: 'white', width: 44, height: 44, borderRadius: 12, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}>
            <Search size={20} />
          </button>
          <button style={{ background: 'var(--glass)', border: '1px solid var(--border)', color: 'white', width: 44, height: 44, borderRadius: 12, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}>
            <Bell size={20} />
          </button>
        </div>
      </header>

      <div className="dashboard-grid">
        <div className="glass-card" style={{ gridColumn: '1 / -1', background: 'linear-gradient(135deg, rgba(59, 130, 246, 0.2), rgba(30, 41, 59, 0.8))' }}>
          <h3 style={{ color: 'var(--text-muted)', fontSize: '14px', textTransform: 'uppercase', letterSpacing: '1px', fontWeight: 600 }}>Total Balance</h3>
          <div className="stat-value">$12,450.00</div>
          <p style={{ color: '#4ade80', fontSize: '14px', display: 'flex', alignItems: 'center', gap: '4px' }}>
            ↑ $450.00 (3.2%) this month
          </p>
        </div>

        <div className="glass-card">
          <h3 style={{ color: 'var(--text-muted)', fontSize: '14px', fontWeight: 600, marginBottom: '16px' }}>Recent Transactions</h3>
          <div style={{ display: 'flex', flexDirection: 'column' }}>
            {[1, 2, 3].map(i => (
              <div key={i} className="transaction-row">
                <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
                  <div style={{ width: 40, height: 40, borderRadius: 12, background: 'var(--glass)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    <Receipt size={20} color="var(--primary)" />
                  </div>
                  <div>
                    <div style={{ fontWeight: 600 }}>Groceries</div>
                    <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>Credit Card • Today</div>
                  </div>
                </div>
                <div style={{ fontWeight: 600 }}>-$84.20</div>
              </div>
            ))}
          </div>
        </div>

        <div className="glass-card">
          <h3 style={{ color: 'var(--text-muted)', fontSize: '14px', fontWeight: 600, marginBottom: '16px' }}>Top Categories</h3>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
            <div>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px', fontSize: '14px' }}>
                <span>Housing</span>
                <span style={{ fontWeight: 600 }}>$1,200.00</span>
              </div>
              <div style={{ height: 6, background: 'var(--glass)', borderRadius: 3, overflow: 'hidden' }}>
                <div style={{ width: '45%', height: '100%', background: 'var(--primary)', borderRadius: 3 }} />
              </div>
            </div>
            <div>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px', fontSize: '14px' }}>
                <span>Food & Dining</span>
                <span style={{ fontWeight: 600 }}>$450.00</span>
              </div>
              <div style={{ height: 6, background: 'var(--glass)', borderRadius: 3, overflow: 'hidden' }}>
                <div style={{ width: '25%', height: '100%', background: '#f59e0b', borderRadius: 3 }} />
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

function PlaceholderScreen({ item }: { item: NavItem }) {
  return (
    <div className="section-panel">
      <header className="section-header">
        <div>
          <h1>{item.name}</h1>
          <p>{item.description}</p>
        </div>
      </header>

      <div className="glass-card placeholder-card">
        <div className="placeholder-icon">
          <item.icon size={28} />
        </div>
        <div>
          <h2>{item.name} workspace</h2>
          <p>The sidebar now keeps this shell in place and swaps only the middle content.</p>
        </div>
      </div>
    </div>
  );
}

function App() {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [activeSection, setActiveSection] = useState<SectionId>('home');

  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, (user) => {
      setUser(user);
      setLoading(false);
    });
    return () => unsubscribe();
  }, []);

  if (loading) {
    return <div className="login-container">Loading...</div>;
  }

  if (!user) {
    return <LoginScreen />;
  }

  const activeNavItem = navItems.find(item => item.id === activeSection) ?? navItems[0]!;

  return (
    <div className="app-container">
      <Sidebar activeSection={activeSection} onSectionChange={setActiveSection} />
      <main className={`main-content ${activeSection === 'home' ? 'with-home-island' : ''}`}>
        {activeSection === 'home' ? <Dashboard /> : <PlaceholderScreen item={activeNavItem} />}
      </main>
      {activeSection === 'home' ? (
        <HomeBottomIsland activeSection={activeSection} onSectionChange={setActiveSection} />
      ) : null}
    </div>
  );
}

export default App;
