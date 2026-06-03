'use client';

import { tokens } from '@1wallet/ui';
import { useRouter } from 'next/navigation';
import type { ReactElement } from 'react';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { useAuth } from '../../lib/auth';

export default function LoginPage(): ReactElement {
  const { signInWithGoogle, signInLocal, googleSignInAvailable } = useAuth();
  const router = useRouter();

  const handleGoogle = async () => {
    try {
      await signInWithGoogle();
      router.push('/');
    } catch (e) {
      console.error(e);
      alert('Failed to sign in with Google.');
    }
  };

  const handleLocal = async () => {
    try {
      await signInLocal('local-user@example.com');
      router.push('/');
    } catch (e) {
      console.error(e);
      alert('Failed to enter local mode.');
    }
  };

  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        flex: 1,
        width: '100%',
      }}
    >
      <div style={{ maxWidth: 400, width: '100%', display: 'flex', flexDirection: 'column', gap: tokens.space.xl }}>
        <div style={{ textAlign: 'center' }}>
          <h1 style={{ fontSize: 32, fontWeight: 700, margin: '0 0 8px' }}>Welcome Back</h1>
          <p style={{ color: 'var(--color-on-surface-variant)', margin: 0 }}>
            Sign in to synchronize your ledger across all devices.
          </p>
        </div>

        <Card>
          <div style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.lg, padding: tokens.space.sm }}>
            {googleSignInAvailable ? (
              <Button onClick={handleGoogle} style={{ padding: tokens.space.lg }}>
                Sign in with Google
              </Button>
            ) : (
              <p style={{ color: 'var(--color-on-surface-variant)', textAlign: 'center' }}>
                Firebase is not configured.
              </p>
            )}

            <div style={{ display: 'flex', alignItems: 'center', gap: tokens.space.md }}>
              <hr style={{ flex: 1, border: 'none', borderTop: '1px solid var(--color-outline-variant)' }} />
              <span style={{ color: 'var(--color-on-surface-variant)', fontSize: 12 }}>OR</span>
              <hr style={{ flex: 1, border: 'none', borderTop: '1px solid var(--color-outline-variant)' }} />
            </div>

            <Button variant="secondary" onClick={handleLocal}>
              Continue in Local Mode
            </Button>
            
            <p style={{ margin: 0, fontSize: 12, color: 'var(--color-on-surface-variant)', textAlign: 'center' }}>
              Local mode saves data only to this browser and does not synchronize with the cloud.
            </p>
          </div>
        </Card>
      </div>
    </div>
  );
}
