// Split out from `./firebase.ts` specifically so `firebase/firestore`'s
// runtime never ends up in the eager/critical-path bundle the login screen
// needs — see that file's doc comment for the full rationale. Only
// `../context/WalletDataContext.tsx` and `./walletSync.ts` (both reachable
// only through `Workspace.tsx`'s lazy `import()`) should import from here.
import { getFirestore } from 'firebase/firestore';
import { app } from './firebase';

export const db = getFirestore(app);
