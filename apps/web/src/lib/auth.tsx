'use client';

import {
  GoogleAuthProvider,
  onAuthStateChanged,
  signInWithPopup,
  signOut as firebaseSignOut,
  type User as FirebaseUser,
} from 'firebase/auth';
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import { auth, isFirebaseConfigured } from './firebase';

export type AuthProviderKind = 'firebase' | 'local';

export type AuthUser = {
  id: string;
  email: string;
  displayName?: string;
  photoUrl?: string;
  provider: AuthProviderKind;
};

type AuthContextValue = {
  user: AuthUser | null;
  loading: boolean;
  error: string | null;
  authProvider: AuthProviderKind;
  googleSignInAvailable: boolean;
  signInWithGoogle: () => Promise<void>;
  signInLocal: (email: string) => Promise<void>;
  signOut: () => Promise<void>;
};

const LOCAL_USER_KEY = '1wallet.auth.user.v1';
const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const configured = useMemo(() => isFirebaseConfigured(), []);
  const firebaseAvailable = configured && Boolean(auth);
  const authProvider: AuthProviderKind = configured ? 'firebase' : 'local';
  const googleSignInAvailable = configured;

  const [user, setUser] = useState<AuthUser | null>(() =>
    firebaseAvailable ? null : readLocalUser(),
  );
  const [loading, setLoading] = useState(firebaseAvailable);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let mounted = true;

    if (firebaseAvailable && auth) {
      const unsubscribe = onAuthStateChanged(
        auth,
        (firebaseUser) => {
          if (!mounted) return;
          setUser(userFromFirebase(firebaseUser));
          setLoading(false);
        },
        (err) => {
          if (!mounted) return;
          setError(err.message);
          setLoading(false);
        },
      );
      return () => {
        mounted = false;
        unsubscribe();
      };
    }

    return () => {
      mounted = false;
    };
  }, [firebaseAvailable]);

  const signInWithGoogle = useCallback(async () => {
    if (!configured || !auth) throw new Error('Firebase is not configured for this build.');

    const provider = new GoogleAuthProvider();
    const result = await signInWithPopup(auth, provider);
    setUser(userFromFirebase(result.user));
  }, [configured]);

  const signInLocal = useCallback(async (email: string) => {
    const localUser: AuthUser = {
      id: `local:${email}`,
      email: email.trim().toLowerCase(),
      provider: 'local',
    };
    localStorage.setItem(LOCAL_USER_KEY, JSON.stringify(localUser));
    setUser(localUser);
  }, []);

  const signOut = useCallback(async () => {
    if (configured && auth) {
      await firebaseSignOut(auth);
    }
    localStorage.removeItem(LOCAL_USER_KEY);
    setUser(null);
  }, [configured]);

  const value = useMemo(
    () => ({
      user,
      loading,
      error,
      authProvider,
      googleSignInAvailable,
      signInWithGoogle,
      signInLocal,
      signOut,
    }),
    [
      user,
      loading,
      error,
      authProvider,
      googleSignInAvailable,
      signInWithGoogle,
      signInLocal,
      signOut,
    ],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const value = useContext(AuthContext);
  if (!value) throw new Error('useAuth must be used within AuthProvider');
  return value;
}

function userFromFirebase(user: FirebaseUser | null): AuthUser | null {
  if (!user) return null;
  return {
    id: user.uid,
    email: user.email ?? 'Google account',
    displayName: user.displayName ?? undefined,
    photoUrl: user.photoURL ?? undefined,
    provider: 'firebase',
  };
}

function readLocalUser(): AuthUser | null {
  if (typeof window === 'undefined') return null;
  try {
    const localUser = localStorage.getItem(LOCAL_USER_KEY);
    return localUser ? (JSON.parse(localUser) as AuthUser) : null;
  } catch (err) {
    console.error(err);
    return null;
  }
}
