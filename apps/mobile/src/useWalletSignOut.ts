import { useLedger } from '@1wallet/state';
import { useCallback, useState } from 'react';
import { useAuth } from './auth';
import { useCloudSync } from './cloudSync/LedgerCloudSyncProvider';
import { clearCloudSyncLocalState } from './cloudSync/storage';

export function useWalletSignOut() {
  const { signOut } = useAuth();
  const { reset } = useLedger();
  const { prepareForLocalClear, resumeAfterLocalClear } = useCloudSync();
  const [signingOut, setSigningOut] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const signOutWallet = useCallback(async () => {
    if (signingOut) throw new Error('Sign-out is already in progress.');
    setSigningOut(true);
    setError(null);

    try {
      await prepareForLocalClear();
      await signOut();
      await reset();
      await clearCloudSyncLocalState();
    } catch (err) {
      resumeAfterLocalClear();
      const message = errorMessage(err, 'Could not safely sign out. Your local wallet was kept.');
      setError(message);
      throw new Error(message);
    } finally {
      setSigningOut(false);
    }
  }, [prepareForLocalClear, reset, resumeAfterLocalClear, signOut, signingOut]);

  return { signOutWallet, signingOut, error };
}

function errorMessage(err: unknown, fallback: string): string {
  return err instanceof Error && err.message ? err.message : fallback;
}
