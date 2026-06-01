'use client';

import { KVStore, type KVAdapter } from '@1wallet/ledger/store/memory';

const memoryFallback = new Map<string, string>();

const adapter: KVAdapter = {
  getItem(key) {
    if (typeof window === 'undefined') return memoryFallback.get(key) ?? null;
    return window.localStorage.getItem(key);
  },
  setItem(key, value) {
    if (typeof window === 'undefined') {
      memoryFallback.set(key, value);
      return;
    }
    window.localStorage.setItem(key, value);
  },
  removeItem(key) {
    if (typeof window === 'undefined') {
      memoryFallback.delete(key);
      return;
    }
    window.localStorage.removeItem(key);
  },
};

export const ledgerStore = new KVStore(adapter, '1wallet.ledger.v1');
