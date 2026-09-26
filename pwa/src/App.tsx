import { LogIn, Wallet } from 'lucide-react';
import { lazy, Suspense, useState } from 'react';
import { signInWithPopup } from 'firebase/auth';
import { auth, googleProvider } from './lib/firebase';
import { AuthProvider, useAuth } from './context/AuthContext';

// `Workspace` (everything rendered once a user is signed in) is lazy-loaded
// as its own chunk specifically so the login screen's critical path never
// has to fetch it — `Workspace.tsx` statically imports `WalletDataProvider`
// from `./context/WalletDataContext`, which transitively pulls in
// `../lib/walletSync` (Firestore `runTransaction`/`onSnapshot`/`getDocs`/
// etc., plus `pako`'s gzip/ungzip and `../lib/ledgerCodec`) — none of which
// a signed-out visitor needs. An earlier version of this file statically
// imported `WalletDataProvider`/`useWalletData` directly (only the five
// individual *pages* were lazy), so that entire dependency graph still
// loaded eagerly as part of the initial bundle regardless of sign-in state,
// showing up as a >500KB `WalletDataContext-*.js` chunk fetched immediately
// on every page load, login screen included. Moving the dynamic `import()`
// boundary up to wrap the whole signed-in workspace (rather than only its
// individual pages) means that chunk — and everything under it — is now
// only ever requested after `AppShell` actually renders `<Workspace />`,
// i.e. after a real signed-in `user` exists.
const Workspace = lazy(() => import('./Workspace').then((module) => ({ default: module.Workspace })));

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

function AppShell() {
  const { user, loading } = useAuth();

  if (loading) {
    return <div className="login-container">Loading...</div>;
  }

  if (!user) {
    return <LoginScreen />;
  }

  return (
    <Suspense fallback={<div className="login-container">Loading...</div>}>
      <Workspace />
    </Suspense>
  );
}

function App() {
  return (
    <AuthProvider>
      <AppShell />
    </AuthProvider>
  );
}

export default App;
