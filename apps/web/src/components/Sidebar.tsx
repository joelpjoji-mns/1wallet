'use client';

import { tokens } from '@1wallet/ui';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import type { ReactNode } from 'react';

export function Sidebar() {
  const pathname = usePathname();

  return (
    <aside
      style={{
        width: 250,
        padding: tokens.space.xl,
        borderRight: '1px solid var(--color-outline-variant)',
        backgroundColor: 'var(--color-surface-low)',
        display: 'flex',
        flexDirection: 'column',
        gap: tokens.space.xl,
      }}
    >
      <div style={{ padding: `0 ${tokens.space.md}px` }}>
        <h1 style={{ margin: 0, fontSize: 24, fontWeight: 700, color: 'var(--color-primary)' }}>1wallet</h1>
      </div>
      
      <nav style={{ display: 'flex', flexDirection: 'column', gap: tokens.space.sm, flex: 1 }}>
        <NavLink href="/" active={pathname === '/'}>Dashboard</NavLink>
        <NavLink href="/transactions" active={pathname?.startsWith('/transactions')}>Transactions</NavLink>
        <NavLink href="/accounts" active={pathname?.startsWith('/accounts')}>Accounts</NavLink>
        <NavLink href="/categories" active={pathname?.startsWith('/categories')}>Categories</NavLink>
        <NavLink href="/loans" active={pathname?.startsWith('/loans')}>Loans</NavLink>
        <NavLink href="/recurring" active={pathname?.startsWith('/recurring')}>Recurring</NavLink>
        <NavLink href="/planner" active={pathname?.startsWith('/planner')}>Planner</NavLink>
        <NavLink href="/reports" active={pathname?.startsWith('/reports')}>Reports</NavLink>
        <NavLink href="/review" active={pathname?.startsWith('/review')}>Review Queue</NavLink>
      </nav>

      <div style={{ marginTop: 'auto' }}>
        <NavLink href="/settings" active={pathname?.startsWith('/settings')}>Settings</NavLink>
      </div>
    </aside>
  );
}

function NavLink({ href, active, children }: { href: string; active?: boolean; children: ReactNode }) {
  return (
    <Link
      href={href}
      style={{
        color: active ? 'var(--color-on-primary)' : 'var(--color-on-surface)',
        backgroundColor: active ? 'var(--color-primary)' : 'transparent',
        textDecoration: 'none',
        padding: `${tokens.space.md}px ${tokens.space.lg}px`,
        borderRadius: tokens.radius.pill,
        fontWeight: tokens.font.weight.semibold,
        transition: 'all 0.2s',
      }}
      onMouseEnter={(e) => {
        if (!active) e.currentTarget.style.backgroundColor = 'var(--color-outline-variant)';
      }}
      onMouseLeave={(e) => {
        if (!active) e.currentTarget.style.backgroundColor = 'transparent';
      }}
    >
      {children}
    </Link>
  );
}
