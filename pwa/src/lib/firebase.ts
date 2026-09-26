import { initializeApp } from 'firebase/app';
import { getAuth, GoogleAuthProvider } from 'firebase/auth';

const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID,
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId: import.meta.env.VITE_FIREBASE_APP_ID,
};

// Deliberately does NOT import/initialize `firebase/firestore` here — this
// module is imported eagerly by `AuthContext.tsx` (needed for the
// login/loading screen before any user is signed in), so anything it pulls
// in ends up in the app's critical initial-load bundle. Firestore's runtime
// (and everything built on it — `../lib/walletSync`'s
// `runTransaction`/`onSnapshot`/`getDocs`/etc.) is only ever needed once a
// user is actually signed in and `Workspace`/`WalletDataProvider` render, so
// `db` lives in the sibling `./firestore.ts` module instead, imported only
// from that lazy-loaded side of the app. See `App.tsx`'s doc comment for the
// full chunk-splitting rationale.
export const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const googleProvider = new GoogleAuthProvider();
