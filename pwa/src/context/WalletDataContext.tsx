import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { doc, onSnapshot } from 'firebase/firestore';
import { db } from '../lib/firebase';
import { useAuth } from './AuthContext';
import {
  claimAndWriteSnapshot,
  downloadSnapshot,
  readCloudMeta,
  WalletSyncConflictError,
  WalletSyncTooLargeError,
  type CloudMeta,
} from '../lib/walletSync';
import { isIncomingSnapshotSafer } from '../lib/ledgerCodec';
import { PendingSaveGuard } from '../lib/pendingSaveGuard';
import {
  emptyLedgerSnapshot,
  type Account,
  type Category,
  type LedgerSnapshot,
  type TransactionRecord,
} from '../lib/ledgerTypes';

type SyncPhase = 'idle' | 'loading' | 'saving' | 'error' | 'conflict';

interface WalletDataContextValue {
  snapshot: LedgerSnapshot;
  phase: SyncPhase;
  error: string | null;
  refresh: () => Promise<void>;
  addAccount: (account: Account) => Promise<void>;
  /** Never accepts `encryptedDetails` edits — those stay device-encrypted only. */
  updateAccount: (id: string, patch: Partial<Omit<Account, 'id' | 'encryptedDetails'>>) => Promise<void>;
  archiveAccount: (id: string, archived: boolean) => Promise<void>;
  addCategory: (category: Category) => Promise<void>;
  updateCategory: (id: string, patch: Partial<Omit<Category, 'id'>>) => Promise<void>;
  addTransaction: (transaction: TransactionRecord) => Promise<void>;
  updateTransaction: (id: string, patch: Partial<Omit<TransactionRecord, 'id'>>) => Promise<void>;
  deleteTransaction: (id: string) => Promise<void>;
}

const WalletDataContext = createContext<WalletDataContextValue | undefined>(undefined);

const SAVE_DEBOUNCE_MS = 1200;

const EMPTY_CLOUD_META: CloudMeta = {
  updatedAtMs: null,
  lastWriterDeviceId: null,
  cloudRevision: null,
  chunkCount: 0,
};

interface PendingSavePayload {
  snapshot: LedgerSnapshot;
  profile: { email: string | null; displayName: string | null };
}

export function WalletDataProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  const [snapshot, setSnapshot] = useState<LedgerSnapshot>(emptyLedgerSnapshot());
  const [phase, setPhase] = useState<SyncPhase>('idle');
  const [error, setError] = useState<string | null>(null);

  // Full baseline of what we last observed in the cloud (updatedAt,
  // cloudRevision, lastWriterDeviceId, and — crucially — the exact
  // wallet_backups chunk count from that same read), so a subsequent write's
  // atomic conflict check can compute an exact stale-chunk prune range
  // without needing a query inside the transaction. See `claimAndWriteSnapshot`
  // in `walletSync.ts` for why that matters.
  const lastKnownMetaRef = useRef<CloudMeta>(EMPTY_CLOUD_META);
  const snapshotRef = useRef(snapshot);
  snapshotRef.current = snapshot;
  const saveTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const savingSelfRef = useRef(false);

  // Binds every debounced save to the uid that was active when it was
  // scheduled, so switching users (sign-out / sign-in as someone else)
  // before the debounce timer fires can never upload the new user's
  // snapshot to the old user's uid (or vice versa) — see
  // `pendingSaveGuard.test.ts` for the regression coverage.
  const saveGuardRef = useRef(new PendingSaveGuard<PendingSavePayload>());

  // Guards against a stale `load()` call (from a previous uid, or an older
  // realtime/refresh trigger for the *same* uid) applying its result after a
  // newer one has already started — classic "ignore out-of-order async
  // response" pattern.
  const loadGenerationRef = useRef(0);
  const activeUidRef = useRef<string | null>(null);

  const load = useCallback(async (uid: string, generation: number) => {
    setPhase('loading');
    setError(null);
    try {
      const [downloaded, meta] = await Promise.all([downloadSnapshot(uid), readCloudMeta(uid)]);
      if (loadGenerationRef.current !== generation || activeUidRef.current !== uid) {
        // A newer load/uid-switch has started since this one began; this
        // result is stale and must never be applied.
        return;
      }
      const incoming = downloaded.snapshot;
      const current = snapshotRef.current;
      // Extra defense-in-depth on top of the device/timestamp check in
      // `persist()`: never let a load path (initial fetch or realtime
      // refresh) replace non-empty local state with an emptier/older-looking
      // remote snapshot — mirrors `LedgerState.isIncomingLedgerSafer` in
      // lib/src/data/ledger_models.dart.
      if (current.transactions.length > 0 && !isIncomingSnapshotSafer(current, incoming)) {
        setPhase('idle');
        return;
      }
      setSnapshot(incoming);
      // Prefer the chunk count tied directly to what we just decoded
      // (`downloaded.chunkCount`) over `meta`'s separately-fetched count —
      // both come from near-simultaneous reads, but only the former is
      // guaranteed consistent with the snapshot now in memory.
      lastKnownMetaRef.current = { ...meta, chunkCount: downloaded.chunkCount };
      setPhase('idle');
    } catch (e) {
      if (loadGenerationRef.current !== generation || activeUidRef.current !== uid) return;
      setError(e instanceof Error ? e.message : 'Failed to load wallet data.');
      setPhase('error');
    }
  }, []);

  /** Bumps the load generation and starts a fresh load for `uid`, invalidating any in-flight one. */
  const startLoad = useCallback(
    (uid: string) => {
      loadGenerationRef.current += 1;
      void load(uid, loadGenerationRef.current);
    },
    [load],
  );

  useEffect(() => {
    // Any uid change (including signing out) invalidates in-flight loads and
    // drops any debounced save queued for the previous user — continuing to
    // apply either after the active user changed is exactly the class of bug
    // this whole effect exists to prevent.
    loadGenerationRef.current += 1;
    activeUidRef.current = user?.uid ?? null;
    if (saveTimerRef.current) {
      clearTimeout(saveTimerRef.current);
      saveTimerRef.current = null;
    }
    saveGuardRef.current.setActiveUid(user?.uid ?? null);

    if (!user) {
      setSnapshot(emptyLedgerSnapshot());
      lastKnownMetaRef.current = EMPTY_CLOUD_META;
      setPhase('idle');
      setError(null);
      return;
    }
    startLoad(user.uid);
  }, [user, startLoad]);

  // Unmount: cancel any pending timer/save so nothing fires after teardown.
  useEffect(
    () => () => {
      if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
      saveGuardRef.current.clear();
    },
    [],
  );

  // Real-time: if another device pushes a newer snapshot, refresh ours —
  // unless we are mid-save ourselves, in which case our own write will
  // update `lastKnownMetaRef` when it lands.
  useEffect(() => {
    if (!user) return;
    const uid = user.uid;
    const unsub = onSnapshot(doc(db, 'users', uid), (snap) => {
      if (activeUidRef.current !== uid) return; // stale listener from a previous user
      if (!snap.exists() || savingSelfRef.current) return;
      const data = snap.data();
      const updatedAt = data.updatedAt;
      const updatedAtMs =
        updatedAt && typeof updatedAt.toMillis === 'function' ? updatedAt.toMillis() : null;
      const cloudRevision = typeof data.cloudRevision === 'number' ? data.cloudRevision : null;
      const baseline = lastKnownMetaRef.current;
      // No `lastWriterDeviceId` exemption here either — a change from *any*
      // writer (including this device's other tabs) since our last known
      // baseline means we're stale and should refresh.
      const changed =
        cloudRevision != null && baseline.cloudRevision != null
          ? cloudRevision !== baseline.cloudRevision
          : updatedAtMs != null && (baseline.updatedAtMs == null || updatedAtMs > baseline.updatedAtMs);
      if (changed) {
        startLoad(uid);
      }
    });
    return () => unsub();
  }, [user, startLoad]);

  const persist = useCallback(
    async (uid: string, next: LedgerSnapshot, profile: PendingSavePayload['profile']) => {
      setPhase('saving');
      setError(null);
      const expectedMeta = lastKnownMetaRef.current;
      try {
        savingSelfRef.current = true;
        // `claimAndWriteSnapshot` atomically re-verifies `expectedMeta`
        // against the cloud state and writes the user-doc metadata *and*
        // every chunk set/delete together in one Firestore transaction —
        // closing the window a separate meta-transaction + chunk-batch pair
        // would leave open. It throws `WalletSyncConflictError` (nothing
        // written) if another writer moved the cloud state since
        // `expectedMeta` was observed, or `WalletSyncTooLargeError` (nothing
        // written) if this wallet is too large to write as one atomic
        // commit — see its doc comment for exactly what is and isn't
        // guaranteed against the Flutter client specifically.
        await claimAndWriteSnapshot(uid, next, profile, expectedMeta);
        const freshMeta = await readCloudMeta(uid);
        if (activeUidRef.current === uid) {
          lastKnownMetaRef.current = freshMeta;
          setPhase('idle');
        }
      } catch (e) {
        if (activeUidRef.current !== uid) return; // user switched away mid-save; nothing to report
        if (e instanceof WalletSyncConflictError) {
          setPhase('conflict');
          setError('Your wallet changed on another device or tab. Reloading the latest data — please reapply your edit.');
          startLoad(uid);
          return;
        }
        if (e instanceof WalletSyncTooLargeError) {
          setPhase('error');
          setError(e.message);
          return;
        }
        setError(e instanceof Error ? e.message : 'Failed to sync your wallet.');
        setPhase('error');
      } finally {
        savingSelfRef.current = false;
      }
    },
    [startLoad],
  );

  const scheduleSave = useCallback(
    (next: LedgerSnapshot) => {
      if (!user) return; // no signed-in user to bind this save to; drop it
      setSnapshot(next);
      saveGuardRef.current.schedule(user.uid, {
        snapshot: next,
        profile: { email: user.email, displayName: user.displayName },
      });
      if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
      saveTimerRef.current = setTimeout(() => {
        saveTimerRef.current = null;
        const pending = saveGuardRef.current.take();
        // `take()` returns null if the active uid changed since this save
        // was scheduled — e.g. the user signed out or switched accounts
        // before the debounce elapsed. Dropping it here (rather than firing
        // against whatever uid/snapshot happen to be current now) is exactly
        // the fix for the cross-user upload bug this guard exists for.
        if (!pending) return;
        void persist(pending.uid, pending.payload.snapshot, pending.payload.profile);
      }, SAVE_DEBOUNCE_MS);
    },
    [user, persist],
  );

  const addAccount = useCallback(
    async (account: Account) => {
      scheduleSave({ ...snapshotRef.current, accounts: [...snapshotRef.current.accounts, account] });
    },
    [scheduleSave],
  );

  const updateAccount = useCallback(
    async (id: string, patch: Partial<Omit<Account, 'id' | 'encryptedDetails'>>) => {
      const current = snapshotRef.current;
      scheduleSave({
        ...current,
        accounts: current.accounts.map((a) => (a.id === id ? { ...a, ...patch } : a)),
      });
    },
    [scheduleSave],
  );

  const archiveAccount = useCallback(
    async (id: string, archived: boolean) => {
      await updateAccount(id, { isArchived: archived });
    },
    [updateAccount],
  );

  const addCategory = useCallback(
    async (category: Category) => {
      scheduleSave({ ...snapshotRef.current, categories: [...snapshotRef.current.categories, category] });
    },
    [scheduleSave],
  );

  const updateCategory = useCallback(
    async (id: string, patch: Partial<Omit<Category, 'id'>>) => {
      const current = snapshotRef.current;
      scheduleSave({
        ...current,
        categories: current.categories.map((c) => (c.id === id ? { ...c, ...patch } : c)),
      });
    },
    [scheduleSave],
  );

  const addTransaction = useCallback(
    async (transaction: TransactionRecord) => {
      scheduleSave({
        ...snapshotRef.current,
        transactions: [...snapshotRef.current.transactions, transaction],
      });
    },
    [scheduleSave],
  );

  const updateTransaction = useCallback(
    async (id: string, patch: Partial<Omit<TransactionRecord, 'id'>>) => {
      const current = snapshotRef.current;
      scheduleSave({
        ...current,
        transactions: current.transactions.map((t) => (t.id === id ? { ...t, ...patch } : t)),
      });
    },
    [scheduleSave],
  );

  const deleteTransaction = useCallback(
    async (id: string) => {
      const current = snapshotRef.current;
      scheduleSave({
        ...current,
        transactions: current.transactions.filter((t) => t.id !== id),
      });
    },
    [scheduleSave],
  );

  const refresh = useCallback(async () => {
    if (user) startLoad(user.uid);
  }, [user, startLoad]);

  const value = useMemo<WalletDataContextValue>(
    () => ({
      snapshot,
      phase,
      error,
      refresh,
      addAccount,
      updateAccount,
      archiveAccount,
      addCategory,
      updateCategory,
      addTransaction,
      updateTransaction,
      deleteTransaction,
    }),
    [
      snapshot,
      phase,
      error,
      refresh,
      addAccount,
      updateAccount,
      archiveAccount,
      addCategory,
      updateCategory,
      addTransaction,
      updateTransaction,
      deleteTransaction,
    ],
  );

  return <WalletDataContext.Provider value={value}>{children}</WalletDataContext.Provider>;
}

export function useWalletData(): WalletDataContextValue {
  const ctx = useContext(WalletDataContext);
  if (!ctx) throw new Error('useWalletData must be used within WalletDataProvider');
  return ctx;
}
