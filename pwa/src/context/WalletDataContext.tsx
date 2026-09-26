import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { doc, onSnapshot } from 'firebase/firestore';
import { db } from '../lib/firestore';
import { useAuth } from './AuthContext';
import {
  claimAndWriteSnapshot,
  cloudMetaFromUserDoc,
  downloadSnapshot,
  WalletSyncConflictError,
  WalletSyncRevisionOverflowError,
  WalletSyncTooLargeError,
  WalletSyncUnstableError,
  type CloudMeta,
} from '../lib/walletSync';
import { shouldAcceptCloudLoad, shouldAutoLoadOnRemoteChange } from '../lib/walletSyncGuards';
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
  /**
   * The only safe, explicit way out of the `conflict` phase: irrevocably
   * discards the currently-held unsynced local edit — which exists only in
   * this tab's in-memory `snapshot` state, never written to durable
   * storage, so it's already one reload/tab-close away from being lost
   * unannounced — and loads the verified current cloud snapshot, exactly
   * like a normal load. Never merges or silently reapplies the discarded
   * edit. The caller (`Workspace.tsx`'s `ConflictBanner`) requires its own
   * explicit user confirmation (a native `window.confirm()` prompt) before
   * calling this, since a single accidental click destroying a financial
   * edit with no way back is too easy a mistake otherwise — see the doc
   * comment on `persist()`'s `WalletSyncConflictError` handler for why
   * nothing *automatic* is safe here either.
   */
  discardConflictAndReload: () => Promise<void>;
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
  updatedAtToken: null,
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

  const commitSnapshot = useCallback((next: LedgerSnapshot) => {
    snapshotRef.current = next;
    setSnapshot(next);
  }, []);

  const load = useCallback(async (uid: string, generation: number) => {
    setPhase('loading');
    setError(null);
    try {
      // `downloadSnapshot` returns `{ snapshot, meta }` captured
      // version-consistently in one call (see its doc comment) — no
      // separate `readCloudMeta()` call here. A previous version did
      // `Promise.all([downloadSnapshot(uid), readCloudMeta(uid)])`, two
      // independent round-trips that could straddle an atomic snapshot
      // write: the chunk query could return old content while the parallel
      // metadata read returned the new `cloudRevision`, poisoning the
      // baseline this provider would later trust for its own writes.
      const downloaded = await downloadSnapshot(uid);
      if (loadGenerationRef.current !== generation || activeUidRef.current !== uid) {
        // A newer load/uid-switch has started since this one began; this
        // result is stale and must never be applied.
        return;
      }
      const incoming = downloaded.snapshot;
      // `downloaded.snapshot` is already version-consistently verified (see
      // `downloadSnapshot`'s doc comment) to accurately describe one
      // specific cloud revision — it is the current cloud state by
      // definition, not a heuristic guess, so a legitimate cross-device
      // deletion (fewer transactions, or zero) must be allowed through. The
      // only thing left worth protecting is *this* client's own unsynced
      // local edits: a save that's still debounced/pending, or actively
      // mid-flight, hasn't reached the cloud yet, so blindly applying the
      // incoming snapshot here would silently discard it. `shouldAcceptCloudLoad()`
      // in `walletSyncGuards.ts` — mirroring the Flutter client's
      // `shouldAcceptCloudRestore()` byte-for-byte — replaces the previous
      // count/timestamp heuristic (`isIncomingSnapshotSafer()`, still kept
      // for a possible future local-backup-file restore path) with exactly
      // this version-aware check. See `walletSyncGuards.test.ts` for the
      // regression coverage, including the cross-device-deletion scenario
      // this replaced heuristic used to permanently block.
      const hasUnsyncedLocalChanges = saveGuardRef.current.hasPending() || savingSelfRef.current;
      if (!shouldAcceptCloudLoad({ hasUnsyncedLocalChanges })) {
        // Deliberately leave `snapshot` and `lastKnownMetaRef` untouched: the
        // stale baseline means the pending/in-flight save's own conflict
        // check (in `persist()`) will correctly detect it's out of date
        // against the live cloud state once it actually commits, and drive
        // the existing conflict-reload flow from there.
        setError(
          'Cloud sync conflict: local changes have not been uploaded yet. Local data kept; upload will retry automatically.',
        );
        setPhase('idle');
        return;
      }
      commitSnapshot(incoming);
      lastKnownMetaRef.current = downloaded.meta;
      setPhase('idle');
    } catch (e) {
      if (loadGenerationRef.current !== generation || activeUidRef.current !== uid) return;
      if (e instanceof WalletSyncUnstableError) {
        // The account is being written to faster than we can read it
        // consistently (see `downloadSnapshot`'s doc comment) — surface
        // distinctly rather than silently applying a possibly-inconsistent
        // read.
        setError(e.message);
        setPhase('error');
        return;
      }
      setError(e instanceof Error ? e.message : 'Failed to load wallet data.');
      setPhase('error');
    }
  }, [commitSnapshot]);

  /** Bumps the load generation and starts a fresh load for `uid`, invalidating any in-flight one. */
  const startLoad = useCallback(
    (uid: string) => {
      loadGenerationRef.current += 1;
      void load(uid, loadGenerationRef.current);
    },
    [load],
  );

  useLayoutEffect(() => {
    // Any uid change — including signing out *and* a direct account switch
    // from one signed-in user straight to another — invalidates in-flight
    // loads and drops any debounced save queued for the previous user.
    //
    // Critically, this must *also* immediately clear `snapshot` and the
    // cloud-metadata baseline for a direct A→B switch, not just on sign-out.
    // Previously the reset only happened in the `!user` branch below, so a
    // direct switch left `snapshotRef.current` holding user A's transactions
    // while `load()` fetched user B's data — leaving user A's private
    // financial data visible on screen for the entire in-flight load (see
    // `uidSwitchRender.test.ts` for that regression). `load()`'s acceptance
    // check is now `shouldAcceptCloudLoad()` (version-aware, not
    // content-based — see its doc comment in `walletSyncGuards.ts`), so a
    // stale leftover snapshot from a previous user can no longer cause B's
    // load to be *rejected* the way the old content-heuristic could; this
    // reset is purely about the visual leak, not load acceptance — see
    // `uidSwitchGuard.test.ts` for that history and the current guard's
    // regression coverage.
    //
    // This is `useLayoutEffect` (not `useEffect`) as defense-in-depth: it
    // flushes synchronously after DOM mutations but *before* the browser
    // paints, so even if this provider were ever rendered without the
    // `key={user.uid}` remount guard in `Workspace.tsx` (the actual primary
    // fix — that guard makes this whole reset redundant for a
    // same-instance uid change, since a keyed remount can never observe the
    // old uid and new uid within one component instance), there would
    // still be no visible frame showing the new user alongside the
    // previous user's data. See `Workspace.tsx`'s `Workspace` component for
    // why keying is preferred over relying on effect timing alone, and
    // `uidSwitchGuard.test.ts` / `uidSwitchRender.test.ts` for the
    // regressions.
    loadGenerationRef.current += 1;
    activeUidRef.current = user?.uid ?? null;
    if (saveTimerRef.current) {
      clearTimeout(saveTimerRef.current);
      saveTimerRef.current = null;
    }
    saveGuardRef.current.setActiveUid(user?.uid ?? null);

    // Update the ref synchronously (not just via `setSnapshot`, which only
    // takes effect on the next render) so `load()` — even if it somehow ran
    // before this render committed — can never observe the previous user's
    // snapshot.
    //
    // oxlint flags this as `react(set-state-in-effect)` ("derive the value
    // during render... use an effect only when synchronizing with an
    // external system"). Deliberately not restructured into React's
    // "adjust state during render" alternative pattern here: this effect
    // also performs several other side effects tightly coupled to the exact
    // same uid transition (bumping `loadGenerationRef`, clearing
    // `saveTimerRef`'s pending timer, `saveGuardRef.current.setActiveUid()`,
    // and starting the actual network `load()` below) that are genuine,
    // real side effects on external systems (a timer, a class-based guard
    // object, a Firestore fetch) — not pure state derivation — so they
    // correctly belong in an effect. Splitting just the `setSnapshot`/
    // `setError` calls out into a separate render-time branch (comparing a
    // tracked "last uid this render reflects" state) while leaving the rest
    // here would fragment one atomic, well-tested reset across two
    // different mechanisms for no behavioral benefit, since — per the
    // comment above — this whole reset is already unreachable in practice
    // (a `key={user?.uid}`-remounted instance's `useState` initializers
    // already start at these exact reset values) and exists purely as an
    // inert defense-in-depth backstop. Confirmed via `git log`/prior review
    // that this warning predates the current PWA sync-hardening work; left
    // as a reviewed, accepted exception rather than risking new bugs in a
    // heavily regression-tested reset path (`uidSwitchGuard.test.ts`,
    // `uidSwitchRender.test.ts`, `pendingSaveRaceGuard.test.ts`) for a
    // cosmetic lint fix with no user-visible effect.
    commitSnapshot(emptyLedgerSnapshot());
    lastKnownMetaRef.current = EMPTY_CLOUD_META;
    setError(null);

    if (!user) {
      setPhase('idle');
      return;
    }
    startLoad(user.uid);
  }, [user, startLoad, commitSnapshot]);

  // Unmount: cancel any pending timer/save so nothing fires after teardown.
  useEffect(
    () => () => {
      if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
      saveGuardRef.current.clear();
    },
    [],
  );

  // Real-time: if another device pushes a newer snapshot, refresh ours —
  // unless we have our own unsynced local changes (a debounced-but-not-yet-
  // sent edit, or one actively mid-flight), in which case an auto-reload
  // here would race that edit and silently discard it before its own
  // `persist()`/conflict handling ever runs. See `shouldAutoLoadOnRemoteChange()`
  // in `walletSyncGuards.ts` and `pendingSaveRaceGuard.test.ts` for the
  // regression this specifically guards against.
  useEffect(() => {
    if (!user) return;
    const uid = user.uid;
    const unsub = onSnapshot(doc(db, 'users', uid), (snap) => {
      if (activeUidRef.current !== uid) return; // stale listener from a previous user
      if (!snap.exists()) return;
      const data = snap.data();
      // Reuses the exact same field parsing (`cloudMetaFromUserDoc`) the
      // atomic write's own conflict check uses. No `lastWriterDeviceId`
      // exemption either — a change from *any* writer (including this
      // device's other tabs) since our last known baseline means we're
      // stale and should refresh, *unless* we have our own unsynced edit to
      // protect first (see `shouldAutoLoadOnRemoteChange`'s doc comment).
      const cloud = cloudMetaFromUserDoc(data, lastKnownMetaRef.current.chunkCount);
      const hasUnsyncedLocalChanges = saveGuardRef.current.hasPending() || savingSelfRef.current;
      if (
        shouldAutoLoadOnRemoteChange({ cloud, baseline: lastKnownMetaRef.current, hasUnsyncedLocalChanges })
      ) {
        startLoad(uid);
      }
    });
    return () => unsub();
  }, [user, startLoad]);

  const persist = useCallback(
    async (uid: string, next: LedgerSnapshot, profile: PendingSavePayload['profile']) => {
      setPhase('saving');
      setError(null);
      try {
        savingSelfRef.current = true;
        // The conflict baseline MUST be the cloud state this client's
        // in-memory `snapshot` (i.e. `next`, before this call's edits) is
        // actually known to be consistent with — captured at the last
        // successful `load()`/`persist()` — not a value re-read fresh right
        // before this write attempt.
        //
        // An earlier version of this line did exactly that ("read as fresh
        // as possible to minimize spurious conflicts"), which introduced a
        // false-negative: if another writer commits *between* this client's
        // last load and this fresh pre-write read, the fresh read already
        // reflects that other writer's revision, so `expectedMeta` ends up
        // "matching" the live state the transaction re-reads at commit —
        // even though this client's in-memory ledger was never built from
        // that revision and knows nothing about the changes in it. The
        // conflict check then reports "no conflict" and this client's
        // (older-in-substance) ledger silently overwrites the other
        // writer's commit. Flutter's `CloudSyncController.uploadSnapshot()`
        // hit the identical bug with its own fresh-baseline read and fixed
        // it by using `CloudSyncMetadata.lastCloudRevision` — the state
        // persisted at the last successful push/pull — instead; this
        // mirrors that fix. The transaction's own live re-read at commit
        // time remains the authoritative safety net either way, but only
        // catches races that happen *after* this baseline is captured, so
        // the baseline itself must already be correct.
        const expectedMeta = lastKnownMetaRef.current;
        // `claimAndWriteSnapshot` atomically re-verifies `expectedMeta`
        // against the cloud state and writes the user-doc metadata *and*
        // every chunk set/delete together in one Firestore transaction —
        // closing the window a separate meta-transaction + chunk-batch pair
        // would leave open. It throws `WalletSyncConflictError` (nothing
        // written) if another writer moved the cloud state since
        // `expectedMeta` was observed, or `WalletSyncTooLargeError` (nothing
        // written) if this wallet is too large to write as one atomic
        // commit. The Flutter client implements the matching
        // baseline-from-last-sync/compare-cloudRevision/write-atomically
        // protocol (see `lib/src/cloud_sync/cloud_sync_write_guard.dart` and
        // `CloudSyncMetadata`), so this is a formally shared cross-client
        // protocol, not just a same-origin safeguard — see
        // `firebase/README.md` for the full contract.
        //
        // `claimAndWriteSnapshot` now returns the exact `CloudMeta` its
        // transaction committed (built from the `Timestamp.now()` it wrote,
        // not a value re-read from the server afterward) — adopted directly
        // as the new baseline. A prior version issued a separate
        // `readCloudMeta(uid)` call right after the commit to fetch that
        // baseline; if another writer's commit landed in the gap between
        // this transaction committing and that follow-up read, the
        // follow-up read would return *that other writer's*
        // revision/timestamp, and this client would wrongly adopt it as "my
        // own last-known-good baseline" — poisoning the very next write's
        // conflict check into a false "no conflict".
        const meta = await claimAndWriteSnapshot(uid, next, profile, expectedMeta);
        if (activeUidRef.current === uid) {
          lastKnownMetaRef.current = meta;
          setPhase('idle');
        }
      } catch (e) {
        if (activeUidRef.current !== uid) return; // user switched away mid-save; nothing to report
        if (e instanceof WalletSyncConflictError) {
          // Deliberately do NOT auto-reload here: an earlier version called
          // `startLoad(uid)` immediately, which — once the download
          // resolved — would find no pending save left to protect it (this
          // failed attempt's payload was already dequeued by `scheduleSave`'s
          // `take()` before `persist()` ran) and so `shouldAcceptCloudLoad`
          // would happily apply the fresh cloud snapshot, silently
          // overwriting `next` — the very edit the error message claimed
          // the user should "reapply". Instead, re-queue `next` as pending
          // so it keeps protecting itself: any realtime update
          // (`shouldAutoLoadOnRemoteChange`) or manual `refresh()`
          // (`shouldAcceptCloudLoad`) will now correctly refuse to discard
          // it, exactly like a normal not-yet-sent debounced edit would.
          // `next` is re-queued verbatim — no merge/patch/reconciliation
          // with the (unknown, not re-read here) live cloud state is ever
          // attempted. This handler has no information about what actually
          // changed remotely, so any kind of automatic merge of financial
          // data (account balances, transaction lists, amounts) would be
          // guesswork with real money on the line; retaining the user's
          // exact edit untouched and requiring an explicit reload +
          // re-apply is the only safe option. `next` is left visible in
          // `snapshot` untouched. Resolving the conflict (reloading the
          // real current cloud state and letting the user decide whether
          // to reapply their edit) is deferred to an explicit future
          // action rather than done automatically. See
          // `pendingSaveRaceGuard.test.ts` for the regression.
          saveGuardRef.current.schedule(uid, { snapshot: next, profile });
          setPhase('conflict');
          setError(
            'Your wallet changed on another device or tab. Your edit was not saved — it remains visible only in this browser tab (in memory, not saved to this device) and will be lost if you reload or close this tab before resolving. Choose "Discard unsaved edit and load cloud" to load the latest data (this discards your edit), then reapply it if still needed.',
          );
          return;
        }
        if (e instanceof WalletSyncTooLargeError) {
          setPhase('error');
          setError(e.message);
          return;
        }
        if (e instanceof WalletSyncRevisionOverflowError) {
          // Distinct, explicit failure surfaced by `nextCloudRevision()`
          // before any write is attempted — see its doc comment in
          // `walletSyncGuards.ts` — rather than letting an opaque
          // Firestore rules-permission-denied rejection reach the user.
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
    [],
  );

  const scheduleSave = useCallback(
    (next: LedgerSnapshot) => {
      if (!user) return; // no signed-in user to bind this save to; drop it
      commitSnapshot(next);
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
    [user, persist, commitSnapshot],
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

  const discardConflictAndReload = useCallback(async () => {
    if (!user) return;
    const uid = user.uid;
    if (activeUidRef.current !== uid) return; // stale action from a previous user's UI
    // Explicit, user-confirmed discard: irrevocably drop the conflicted
    // local edit — `saveGuardRef.current.clear()` removes it without ever
    // reading/merging its content — and pull the verified current cloud
    // snapshot fresh via the normal `load()` path. This is the only exit
    // from the `conflict` phase: nothing else (a realtime update, a plain
    // `refresh()`) can discard this edit on its own, by design — see
    // `shouldAcceptCloudLoad`'s and `persist()`'s `WalletSyncConflictError`
    // handler's doc comments. Clearing any stray timer too, though none
    // should exist here (the conflict handler never re-arms the debounce
    // timer, only `saveGuardRef`) — matches the same defensive pattern used
    // on a uid switch.
    saveGuardRef.current.clear();
    if (saveTimerRef.current) {
      clearTimeout(saveTimerRef.current);
      saveTimerRef.current = null;
    }
    setError(null);
    startLoad(uid);
  }, [user, startLoad]);

  const value = useMemo<WalletDataContextValue>(
    () => ({
      snapshot,
      phase,
      error,
      refresh,
      discardConflictAndReload,
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
      discardConflictAndReload,
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
