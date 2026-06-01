import { useLedger } from '@1wallet/state';
import { Redirect } from 'expo-router';
import { useEffect, useState } from 'react';
import { useAuth } from '../src/auth';
import { useCloudSync } from '../src/cloudSync/LedgerCloudSyncProvider';
import { BrandedLoadingState, RecoveryState } from '../src/components/Brand';

export default function Index() {
  const { state, ready, error: ledgerError, mutate, reload, reset } = useLedger();
  const { user, loading, error: authError, retry: retryAuth } = useAuth();
  const cloudSync = useCloudSync();
  const [syncError, setSyncError] = useState<string | null>(null);
  const [syncRetryKey, setSyncRetryKey] = useState(0);
  const userId = user?.id;
  const hasLocalWalletData = state.accounts.length > 0;

  useEffect(() => {
    if (!ready || !userId || state.userId === userId) {
      return;
    }

    let active = true;
    setSyncError(null);

    void withTimeout(
      mutate((draft) => {
        draft.userId = userId;
      }),
      15000,
      'Preparing your wallet is taking longer than expected.',
    ).catch((err) => {
      if (!active) return;
      setSyncError(err instanceof Error ? err.message : 'Could not prepare your wallet.');
    });

    return () => {
      active = false;
    };
  }, [mutate, ready, state.userId, syncRetryKey, userId]);

  if (authError) {
    return (
      <RecoveryState
        title="Sign-in needs attention"
        body={authError}
        actionLabel="Try again"
        onAction={retryAuth}
      />
    );
  }

  if (ledgerError) {
    return (
      <RecoveryState
        title="Wallet data needs attention"
        body={ledgerError}
        actionLabel="Try again"
        onAction={() => void reload()}
        secondaryActionLabel="Reset local wallet"
        onSecondaryAction={() => void reset()}
      />
    );
  }

  if (syncError) {
    return (
      <RecoveryState
        title="Wallet setup paused"
        body={syncError}
        actionLabel="Try again"
        onAction={() => {
          setSyncError(null);
          setSyncRetryKey((value) => value + 1);
        }}
        secondaryActionLabel="Reset local wallet"
        onSecondaryAction={() => void reset()}
      />
    );
  }

  if (ready && hasLocalWalletData && loading) {
    return <Redirect href="/(tabs)/home" />;
  }

  if (loading) {
    return <BrandedLoadingState stage="session" message="Checking your secure session" />;
  }

  if (!ready) {
    return <BrandedLoadingState stage="wallet" message="Restoring your wallet" />;
  }

  if (userId && state.userId !== userId) {
    return <BrandedLoadingState stage="sync" message="Linking your wallet to this sign-in" />;
  }

  if (!user) return <Redirect href={'/login' as never} />;
  if (!hasLocalWalletData && cloudSync.enabled && !cloudSync.bootstrapComplete) {
    if (cloudSync.phase === 'error') {
      return (
        <RecoveryState
          title="Cloud restore paused"
          body={cloudSync.error ?? 'Could not restore your Firebase wallet.'}
          actionLabel="Try again"
          onAction={cloudSync.retryBootstrap}
        />
      );
    }

    return <BrandedLoadingState stage="sync" message="Restoring your cloud wallet" />;
  }
  if (!hasLocalWalletData) return <Redirect href="/onboarding" />;
  return <Redirect href="/(tabs)/home" />;
}

function withTimeout<T>(promise: Promise<T>, timeoutMs: number, message: string): Promise<T> {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error(message)), timeoutMs);
    promise.then(
      (value) => {
        clearTimeout(timeout);
        resolve(value);
      },
      (err) => {
        clearTimeout(timeout);
        reject(err);
      },
    );
  });
}
