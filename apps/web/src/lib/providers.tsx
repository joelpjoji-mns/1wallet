'use client';

import { LedgerProvider } from '@1wallet/state';
import type { ReactElement, ReactNode } from 'react';
import { ledgerStore } from './storage';

export function Providers({ children }: { children: ReactNode }): ReactElement {
  return <LedgerProvider store={ledgerStore}>{children}</LedgerProvider>;
}
