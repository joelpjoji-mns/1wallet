import 'react-native-url-polyfill/auto';

import {
    createUserWithEmailAndPassword,
    signOut as firebaseSignOut,
    GoogleAuthProvider,
    onAuthStateChanged,
    signInWithCredential,
    signInWithEmailAndPassword,
    type User as FirebaseUser,
} from '@firebase/auth';
import {
    GoogleSignin,
    isErrorWithCode,
    isSuccessResponse,
    statusCodes,
} from '@react-native-google-signin/google-signin';
import { createClient, type Session, type SupabaseClient } from '@supabase/supabase-js';
import * as SecureStore from 'expo-secure-store';
import {
    createContext,
    useCallback,
    useContext,
    useEffect,
    useMemo,
    useState,
    type ReactNode,
} from 'react';
import {
  firebaseGoogleAuthConfig,
  getFirebaseServices,
  googleClientIdForPlatform,
} from './firebase/client';

export type AuthProviderKind = 'firebase' | 'supabase' | 'local';

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
  retry: () => void;
  signIn: (input: AuthInput) => Promise<void>;
  signUp: (input: AuthInput) => Promise<void>;
  signInWithGoogle: () => Promise<void>;
  signOut: () => Promise<void>;
};

type AuthInput = {
  email: string;
  password: string;
};

const LOCAL_USER_KEY = '1wallet.auth.user.v1';
const LOCAL_USERS_KEY = '1wallet.auth.users.v1';
const AuthContext = createContext<AuthContextValue | undefined>(undefined);

type LocalUserRegistry = Record<string, AuthUser>;

export class AccountNotFoundError extends Error {
  readonly email: string;

  constructor(email: string) {
    super('No account found for this email.');
    this.name = 'AccountNotFoundError';
    this.email = email;
  }
}

export function isAccountNotFoundError(err: unknown): err is AccountNotFoundError {
  return (
    err instanceof AccountNotFoundError ||
    (err as { name?: unknown })?.name === 'AccountNotFoundError'
  );
}

const env = globalThis as typeof globalThis & {
  process?: { env?: Record<string, string | undefined> };
};

const supabaseUrl = env.process?.env?.EXPO_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = env.process?.env?.EXPO_PUBLIC_SUPABASE_ANON_KEY;
const debugDataPreviewEnabled =
  typeof __DEV__ !== 'undefined' &&
  __DEV__ &&
  env.process?.env?.EXPO_PUBLIC_ONEWALLET_DEBUG_DATA_PREVIEW === 'true';
const debugDataPreviewUser: AuthUser = {
  id: 'firebase:pending-google-user',
  email: 'migration-preview@local.onewallet',
  displayName: 'Migration preview',
  provider: 'local',
};

const secureStoreAdapter = {
  getItem: (key: string) => SecureStore.getItemAsync(key),
  setItem: (key: string, value: string) => SecureStore.setItemAsync(key, value),
  removeItem: (key: string) => SecureStore.deleteItemAsync(key),
};

const supabase: SupabaseClient | null =
  supabaseUrl && supabaseAnonKey
    ? createClient(supabaseUrl, supabaseAnonKey, {
        auth: {
          storage: secureStoreAdapter,
          autoRefreshToken: true,
          persistSession: true,
          detectSessionInUrl: false,
        },
      })
    : null;

export function AuthProvider({ children }: { children: ReactNode }) {
  const firebaseServices = useMemo(() => getFirebaseServices(), []);
  const authProvider: AuthProviderKind = debugDataPreviewEnabled
    ? 'local'
    : firebaseServices
      ? 'firebase'
      : supabase
        ? 'supabase'
        : 'local';
  const googleConfig = useMemo(() => firebaseGoogleAuthConfig(), []);
  const nativeGoogleSignInAvailable = Boolean(
    !debugDataPreviewEnabled &&
    firebaseServices &&
    googleConfig.webClientId &&
    googleClientIdForPlatform(googleConfig),
  );
  const [user, setUser] = useState<AuthUser | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [retryKey, setRetryKey] = useState(0);

  useEffect(() => {
    if (!nativeGoogleSignInAvailable) return;
    GoogleSignin.configure({
      webClientId: googleConfig.webClientId,
      iosClientId: googleConfig.iosClientId,
      offlineAccess: false,
      scopes: ['profile', 'email'],
    });
  }, [googleConfig.iosClientId, googleConfig.webClientId, nativeGoogleSignInAvailable]);

  useEffect(() => {
    let mounted = true;
    setLoading(true);
    setError(null);

    if (debugDataPreviewEnabled) {
      setUser(debugDataPreviewUser);
      setLoading(false);
      return () => {
        mounted = false;
      };
    }

    if (firebaseServices) {
      const unsubscribe = onAuthStateChanged(
        firebaseServices.auth,
        (firebaseUser) => {
          if (!mounted) return;
          setUser(userFromFirebase(firebaseUser));
          setLoading(false);
        },
        (err) => {
          if (!mounted) return;
          setError(errorMessage(err, 'Could not restore your Firebase sign-in session.'));
          setLoading(false);
        },
      );
      return () => {
        mounted = false;
        unsubscribe();
      };
    }

    async function loadSession() {
      try {
        if (supabase) {
          const { data, error } = await supabase.auth.getSession();
          if (error) throw error;
          if (mounted) setUser(userFromSession(data.session));
          return;
        }

        const localUser = await SecureStore.getItemAsync(LOCAL_USER_KEY);
        if (localUser) {
          const restoredUser = normalizeStoredLocalUser(JSON.parse(localUser) as AuthUser);
          await rememberLocalUser(restoredUser);
          if (mounted) setUser(restoredUser);
        }
      } catch (err) {
        if (mounted) setError(errorMessage(err, 'Could not restore your sign-in session.'));
      } finally {
        if (mounted) setLoading(false);
      }
    }

    loadSession();

    const subscription = supabase?.auth.onAuthStateChange((_event, session) => {
      setUser(userFromSession(session));
      setLoading(false);
    });

    return () => {
      mounted = false;
      subscription?.data.subscription.unsubscribe();
    };
  }, [firebaseServices, retryKey]);

  const retry = useCallback(() => {
    setRetryKey((value) => value + 1);
  }, []);

  const signIn = useCallback(
    async ({ email, password }: AuthInput) => {
      const normalizedEmail = normalizeEmail(email);
      validateAuthInput(normalizedEmail, password);

      if (firebaseServices) {
        try {
          const credential = await signInWithEmailAndPassword(
            firebaseServices.auth,
            normalizedEmail,
            password,
          );
          setUser(userFromFirebase(credential.user));
          return;
        } catch (err) {
          if (isAccountNotFoundAuthError(err)) throw new AccountNotFoundError(normalizedEmail);
          throw err;
        }
      }

      if (supabase) {
        const { data, error } = await supabase.auth.signInWithPassword({
          email: normalizedEmail,
          password,
        });
        if (error) {
          if (isAccountNotFoundAuthError(error)) throw new AccountNotFoundError(normalizedEmail);
          throw error;
        }
        const sessionUser = userFromSession(data.session);
        if (!sessionUser) throw new AccountNotFoundError(normalizedEmail);
        setUser(sessionUser);
        return;
      }

      const localUser = await readLocalUser(normalizedEmail);
      if (!localUser) throw new AccountNotFoundError(normalizedEmail);
      await SecureStore.setItemAsync(LOCAL_USER_KEY, JSON.stringify(localUser));
      setUser(localUser);
    },
    [firebaseServices],
  );

  const signUp = useCallback(
    async ({ email, password }: AuthInput) => {
      const normalizedEmail = normalizeEmail(email);
      validateAuthInput(normalizedEmail, password);

      if (firebaseServices) {
        const credential = await createUserWithEmailAndPassword(
          firebaseServices.auth,
          normalizedEmail,
          password,
        );
        setUser(userFromFirebase(credential.user));
        return;
      }

      if (supabase) {
        const { data, error } = await supabase.auth.signUp({
          email: normalizedEmail,
          password,
        });
        if (error) throw error;
        setUser(userFromSession(data.session) ?? userFromSupabase(data.user));
        return;
      }

      const localUser = localUserFromEmail(normalizedEmail);
      await rememberLocalUser(localUser);
      setUser(localUser);
    },
    [firebaseServices],
  );

  const signInWithGoogle = useCallback(async () => {
    if (!firebaseServices) throw new Error('Firebase is not configured for this build.');
    if (!nativeGoogleSignInAvailable)
      throw new Error('Google sign-in client IDs are not configured.');

    let idToken: string | null | undefined;
    try {
      await GoogleSignin.hasPlayServices({ showPlayServicesUpdateDialog: true });
      const result = await GoogleSignin.signIn();
      if (!isSuccessResponse(result)) throw new Error('Google sign-in was cancelled.');
      idToken = result.data.idToken;
    } catch (err) {
      if (isErrorWithCode(err)) {
        if (err.code === statusCodes.SIGN_IN_CANCELLED) {
          throw new Error('Google sign-in was cancelled.');
        }
        if (err.code === statusCodes.IN_PROGRESS) {
          throw new Error('Google sign-in is already in progress.');
        }
        if (err.code === statusCodes.PLAY_SERVICES_NOT_AVAILABLE) {
          throw new Error('Google Play services is not available or needs an update.');
        }
      }
      throw err;
    }

    if (!idToken) throw new Error('Google did not return an identity token.');

    const credential = GoogleAuthProvider.credential(idToken);
    const userCredential = await signInWithCredential(firebaseServices.auth, credential);
    setUser(userFromFirebase(userCredential.user));
  }, [firebaseServices, nativeGoogleSignInAvailable]);

  const signOut = useCallback(async () => {
    if (firebaseServices) await firebaseSignOut(firebaseServices.auth);
    else if (supabase) await supabase.auth.signOut();
    if (nativeGoogleSignInAvailable) {
      await GoogleSignin.signOut().catch(() => undefined);
    }
    await SecureStore.deleteItemAsync(LOCAL_USER_KEY);
    setUser(null);
  }, [firebaseServices, nativeGoogleSignInAvailable]);

  const value = useMemo(
    () => ({
      user,
      loading,
      error,
      authProvider,
      googleSignInAvailable: authProvider === 'firebase' && nativeGoogleSignInAvailable,
      retry,
      signIn,
      signUp,
      signInWithGoogle,
      signOut,
    }),
    [
      authProvider,
      error,
      loading,
      nativeGoogleSignInAvailable,
      retry,
      signIn,
      signInWithGoogle,
      signOut,
      signUp,
      user,
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
  const providerEmail = user.providerData.find((item) => item.email)?.email;
  const providerName = user.providerData.find((item) => item.displayName)?.displayName;
  const providerPhoto = user.providerData.find((item) => item.photoURL)?.photoURL;
  return {
    id: user.uid,
    email: user.email ?? providerEmail ?? 'Google account',
    displayName: user.displayName ?? providerName ?? undefined,
    photoUrl: user.photoURL ?? providerPhoto ?? undefined,
    provider: 'firebase',
  };
}

function userFromSession(session: Session | null): AuthUser | null {
  if (!session?.user?.email) return null;
  return { id: session.user.id, email: session.user.email, provider: 'supabase' };
}

function userFromSupabase(user: { id: string; email?: string } | null): AuthUser | null {
  if (!user?.email) return null;
  return { id: user.id, email: user.email, provider: 'supabase' };
}

function localUserFromEmail(email: string): AuthUser {
  return { id: `local:${email}`, email, provider: 'local' };
}

function normalizeStoredLocalUser(user: AuthUser): AuthUser {
  return { ...user, provider: user.provider ?? 'local' };
}

function normalizeEmail(email: string) {
  return email.trim().toLowerCase();
}

function validateAuthInput(email: string, password: string) {
  if (!email.includes('@')) throw new Error('Enter a valid email address.');
  if (password.length < 6) throw new Error('Password must be at least 6 characters.');
}

async function readLocalUser(email: string): Promise<AuthUser | null> {
  const registry = await readLocalUserRegistry();
  const registeredUser = registry[email];
  if (registeredUser) return normalizeStoredLocalUser(registeredUser);

  const legacyUser = await SecureStore.getItemAsync(LOCAL_USER_KEY);
  if (!legacyUser) return null;
  try {
    const parsed = normalizeStoredLocalUser(JSON.parse(legacyUser) as AuthUser);
    if (normalizeEmail(parsed.email) !== email) return null;
    await rememberLocalUser(parsed);
    return parsed;
  } catch {
    return null;
  }
}

async function rememberLocalUser(user: AuthUser) {
  const registry = await readLocalUserRegistry();
  registry[normalizeEmail(user.email)] = normalizeStoredLocalUser(user);
  await SecureStore.setItemAsync(LOCAL_USERS_KEY, JSON.stringify(registry));
  await SecureStore.setItemAsync(LOCAL_USER_KEY, JSON.stringify(normalizeStoredLocalUser(user)));
}

async function readLocalUserRegistry(): Promise<LocalUserRegistry> {
  const raw = await SecureStore.getItemAsync(LOCAL_USERS_KEY);
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw) as LocalUserRegistry;
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch {
    return {};
  }
}

function isAccountNotFoundAuthError(err: unknown): boolean {
  const code = (err as { code?: unknown })?.code;
  if (code === 'auth/user-not-found' || code === 'auth/wrong-password') return true;
  if (code === 'auth/invalid-credential' || code === 'auth/invalid-login-credentials') return true;

  const message = errorMessage(err, '').toLowerCase();
  return (
    message.includes('invalid login credentials') ||
    message.includes('user not found') ||
    message.includes('no user found') ||
    message.includes('account not found')
  );
}

function errorMessage(err: unknown, fallback: string): string {
  const code = (err as { code?: unknown })?.code;
  if (typeof code === 'string') {
    if (code === 'auth/email-already-in-use') return 'This email is already registered.';
    if (code === 'auth/operation-not-allowed') return 'This sign-in method is not enabled yet.';
    if (code === 'auth/network-request-failed') return 'Network connection failed. Try again.';
  }
  return err instanceof Error && err.message ? err.message : fallback;
}
