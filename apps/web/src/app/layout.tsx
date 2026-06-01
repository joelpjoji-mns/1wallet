import { APP_NAME } from '@1wallet/config';
import { tokens } from '@1wallet/ui';
import { Roboto, Roboto_Mono } from 'next/font/google';
import type { ReactElement, ReactNode } from 'react';
import { Providers } from '../lib/providers';

const scheme = tokens.color.md3.light;
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
          background: scheme.background,
          color: scheme.onBackground,
          minHeight: '100vh',
        }}
      >
        <Providers>
          <Shell>{children}</Shell>
        </Providers>
      </body>
    </html>
  );
}

function Shell({ children }: { children: ReactNode }): ReactElement {
  return (
    <div style={{ display: 'flex', minHeight: '100vh' }}>
      <aside
        style={{
          width: 236,
          padding: tokens.space.lg,
          borderRight: `1px solid ${scheme.outlineVariant}`,
          background: scheme.surfaceContainerLow,
        }}
      >
        <h2 style={{ margin: 0, marginBottom: tokens.space.lg }}>1wallet</h2>
        <nav style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.sm }}>
          <NavLink href="/">Home</NavLink>
          <NavLink href="/transactions">Transactions</NavLink>
          <NavLink href="/accounts">Accounts</NavLink>
          <NavLink href="/currencies">Currencies</NavLink>
          <NavLink href="/planner">Planner</NavLink>
          <NavLink href="/review">Review Queue</NavLink>
          <NavLink href="/settings">Settings</NavLink>
        </nav>
      </aside>
      <main style={{ flex: 1, padding: tokens.space.xl, minWidth: 0 }}>{children}</main>
    </div>
  );
}

function NavLink({ href, children }: { href: string; children: ReactNode }): ReactElement {
  return (
    <a
      href={href}
      style={{
        color: scheme.onSurface,
        textDecoration: 'none',
        padding: `${tokens.space.md}px ${tokens.space.md}px`,
        borderRadius: tokens.radius.lg,
        fontWeight: tokens.font.weight.semibold,
      }}
    >
      {children}
    </a>
  );
}
