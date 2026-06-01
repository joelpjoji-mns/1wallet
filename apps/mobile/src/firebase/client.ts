import {
    connectAuthEmulator,
    getAuth,
    initializeAuth,
    type Auth,
    type Persistence,
} from '@firebase/auth';
import AsyncStorage from '@react-native-async-storage/async-storage';
import {
    getApp,
    getApps,
    initializeApp,
    type FirebaseApp,
    type FirebaseOptions,
} from 'firebase/app';
import {
    connectFirestoreEmulator,
    getFirestore,
    initializeFirestore,
    type Firestore,
} from 'firebase/firestore';
import { Platform } from 'react-native';

declare const process: { env: Record<string, string | undefined> };

const publicEnv = {
  firebaseApiKey: process.env.EXPO_PUBLIC_FIREBASE_API_KEY,
  firebaseAuthDomain: process.env.EXPO_PUBLIC_FIREBASE_AUTH_DOMAIN,
  firebaseProjectId: process.env.EXPO_PUBLIC_FIREBASE_PROJECT_ID,
  firebaseStorageBucket: process.env.EXPO_PUBLIC_FIREBASE_STORAGE_BUCKET,
  firebaseMessagingSenderId: process.env.EXPO_PUBLIC_FIREBASE_MESSAGING_SENDER_ID,
  firebaseAppId: process.env.EXPO_PUBLIC_FIREBASE_APP_ID,
  googleAndroidClientId: process.env.EXPO_PUBLIC_GOOGLE_ANDROID_CLIENT_ID,
  googleIosClientId: process.env.EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID,
  googleWebClientId: process.env.EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID,
  firebaseUseEmulator: process.env.EXPO_PUBLIC_FIREBASE_USE_EMULATOR,
  firebaseEmulatorHost: process.env.EXPO_PUBLIC_FIREBASE_EMULATOR_HOST,
  firebaseAuthEmulatorPort: process.env.EXPO_PUBLIC_FIREBASE_AUTH_EMULATOR_PORT,
  firebaseFirestoreEmulatorPort: process.env.EXPO_PUBLIC_FIREBASE_FIRESTORE_EMULATOR_PORT,
};

const REQUIRED_FIREBASE_ENV = [
  'firebaseApiKey',
  'firebaseAuthDomain',
  'firebaseProjectId',
  'firebaseStorageBucket',
  'firebaseMessagingSenderId',
  'firebaseAppId',
] as const;

export type FirebaseServices = {
  app: FirebaseApp;
  auth: Auth;
  db: Firestore;
};

export type FirebaseGoogleAuthConfig = {
  androidClientId?: string;
  iosClientId?: string;
  webClientId?: string;
};

let services: FirebaseServices | null | undefined;
let emulatorsConnected = false;

declare const require: (name: string) => unknown;

const { getReactNativePersistence } = require('@firebase/auth') as {
  getReactNativePersistence(storage: {
    getItem: (key: string) => Promise<string | null>;
    setItem: (key: string, value: string) => Promise<void>;
    removeItem: (key: string) => Promise<void>;
  }): Persistence;
};

export function getFirebaseServices(): FirebaseServices | null {
  if (services !== undefined) return services;

  const options = firebaseOptionsFromEnv();
  if (!options) {
    services = null;
    return services;
  }

  const app = getApps().length > 0 ? getApp() : initializeApp(options);
  const auth = getOrInitializeAuth(app);
  const db = getOrInitializeFirestore(app);

  connectEmulatorsIfRequested(auth, db);
  services = { app, auth, db };
  return services;
}

export function isFirebaseConfigured(): boolean {
  return Boolean(firebaseOptionsFromEnv());
}

export function firebaseGoogleAuthConfig(): FirebaseGoogleAuthConfig {
  const config = {
    androidClientId: value(publicEnv.googleAndroidClientId),
    iosClientId: value(publicEnv.googleIosClientId),
    webClientId: value(publicEnv.googleWebClientId),
  };

  if (isProductionRuntime()) {
    const missing: string[] = [];
    if (!config.webClientId) missing.push('EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID');
    if (Platform.OS === 'android' && !config.androidClientId) {
      missing.push('EXPO_PUBLIC_GOOGLE_ANDROID_CLIENT_ID');
    }
    if (Platform.OS === 'ios' && !config.iosClientId) {
      missing.push('EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID');
    }
    if (missing.length > 0) {
      throw new Error(`Google sign-in production configuration is missing: ${missing.join(', ')}`);
    }
  }

  return config;
}

export function isGoogleSignInConfigured(): boolean {
  return Boolean(googleClientIdForPlatform(firebaseGoogleAuthConfig()));
}

export function googleClientIdForPlatform(config: FirebaseGoogleAuthConfig): string | undefined {
  if (Platform.OS === 'android') return config.androidClientId;
  if (Platform.OS === 'ios') return config.iosClientId;
  return config.webClientId;
}

function firebaseOptionsFromEnv(): FirebaseOptions | null {
  const missing = REQUIRED_FIREBASE_ENV.filter((key) => !value(publicEnv[key]));
  if (missing.length > 0) {
    if (isProductionRuntime()) {
      throw new Error(
        `Firebase production configuration is missing: ${missing
          .map((key) => envNameForPublicKey(key))
          .join(', ')}`,
      );
    }
    return null;
  }

  const apiKey = value(publicEnv.firebaseApiKey);
  const projectId = value(publicEnv.firebaseProjectId);
  const appId = value(publicEnv.firebaseAppId);
  if (!apiKey || !projectId || !appId) return null;

  return {
    apiKey,
    projectId,
    appId,
    authDomain: value(publicEnv.firebaseAuthDomain),
    storageBucket: value(publicEnv.firebaseStorageBucket),
    messagingSenderId: value(publicEnv.firebaseMessagingSenderId),
  };
}

function getOrInitializeAuth(app: FirebaseApp): Auth {
  try {
    return initializeAuth(app, {
      persistence: getReactNativePersistence(AsyncStorage),
    });
  } catch {
    return getAuth(app);
  }
}

function getOrInitializeFirestore(app: FirebaseApp): Firestore {
  try {
    return initializeFirestore(app, { ignoreUndefinedProperties: true });
  } catch {
    return getFirestore(app);
  }
}

function connectEmulatorsIfRequested(auth: Auth, db: Firestore): void {
  if (emulatorsConnected || value(publicEnv.firebaseUseEmulator) !== 'true') return;
  if (isProductionRuntime()) {
    throw new Error('Firebase emulators cannot be enabled in a production build.');
  }
  emulatorsConnected = true;

  const host = value(publicEnv.firebaseEmulatorHost) ?? '10.0.2.2';
  connectAuthEmulator(
    auth,
    `http://${host}:${numberValue(publicEnv.firebaseAuthEmulatorPort, 9099)}`,
    {
      disableWarnings: true,
    },
  );
  connectFirestoreEmulator(db, host, numberValue(publicEnv.firebaseFirestoreEmulatorPort, 8080));
}

function value(raw: string | undefined): string | undefined {
  return raw && raw.trim() ? raw.trim() : undefined;
}

function numberValue(input: string | undefined, fallback: number): number {
  const raw = value(input);
  if (!raw) return fallback;
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function isProductionRuntime(): boolean {
  return typeof __DEV__ === 'undefined' || !__DEV__;
}

function envNameForPublicKey(key: (typeof REQUIRED_FIREBASE_ENV)[number]): string {
  switch (key) {
    case 'firebaseApiKey':
      return 'EXPO_PUBLIC_FIREBASE_API_KEY';
    case 'firebaseAuthDomain':
      return 'EXPO_PUBLIC_FIREBASE_AUTH_DOMAIN';
    case 'firebaseProjectId':
      return 'EXPO_PUBLIC_FIREBASE_PROJECT_ID';
    case 'firebaseStorageBucket':
      return 'EXPO_PUBLIC_FIREBASE_STORAGE_BUCKET';
    case 'firebaseMessagingSenderId':
      return 'EXPO_PUBLIC_FIREBASE_MESSAGING_SENDER_ID';
    case 'firebaseAppId':
      return 'EXPO_PUBLIC_FIREBASE_APP_ID';
  }
}
