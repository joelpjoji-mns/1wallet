import { APP_NAME } from '@1wallet/config';
import { tokens } from '@1wallet/ui';
import { Roboto, Roboto_Mono } from 'next/font/google';
import type { ReactElement, ReactNode } from 'react';
import { Providers } from '../lib/providers';
import { Sidebar } from '../components/Sidebar';
import { ThemeManager } from '../components/ThemeManager';
import { AuthProvider } from '../lib/auth';
import { CloudSyncProvider } from '../lib/cloudSync';
import { AuthGuard } from '../components/AuthGuard';
import './globals.css';

const roboto = Roboto({
  subsets: ['latin'],
  weight: ['400', '500', '700'],
  variable: '--font-ui',
  display: 'swap',
});
const robotoMono = Roboto_Mono({
  subsets: ['latin'],
  weight: ['400', '500', '700'],
  variable: '--font-numeric',
  display: 'swap',
});

export const metadata = {
  title: `${APP_NAME} - Personal finance`,
  description: 'Personal finance, on your terms.',
};

export default function RootLayout({ children }: { children: ReactNode }): ReactElement {
  return (
    <html lang="en" className={`${roboto.variable} ${robotoMono.variable}`}>
      <body
        style={{
          margin: 0,
          fontFamily: 'var(--font-ui), Roboto, "Helvetica Neue", Arial, sans-serif',
          backgroundColor: 'var(--color-bg, #FBF8F3)',
          color: 'var(--color-on-bg, #1B1B1F)',
          minHeight: '100vh',
          display: 'flex',
          flexDirection: 'column',
        }}
      >
        <Providers>
          <AuthProvider>
            <CloudSyncProvider>
              <ThemeManager />
              <AuthGuard>
                <Shell>{children}</Shell>
              </AuthGuard>
            </CloudSyncProvider>
          </AuthProvider>
        </Providers>
      </body>
    </html>
  );
}

function Shell({ children }: { children: ReactNode }): ReactElement {
  return (
    <div
      style={{ display: 'flex', minHeight: '100vh', flex: 1, backgroundColor: 'var(--color-bg)' }}
    >
      <Sidebar />
      <main
        style={{
          flex: 1,
          padding: tokens.space.xl,
          minWidth: 0,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          overflowY: 'auto',
        }}
        className="hide-scrollbar"
      >
        <div
          style={{
            width: '100%',
            maxWidth: 1100,
            display: 'flex',
            flexDirection: 'column',
            gap: tokens.space.lg,
            flex: 1,
          }}
        >
          {children}
        </div>
      </main>
    </div>
  );
}
