import { uid } from '@1wallet/ledger/id';
import { seedDefaultCategories } from '@1wallet/ledger/seed';
import type {
  ApproveCaptureCandidateInput,
  CreateAccountInput,
  CreateCaptureCandidateInput,
  CreateCategoryInput,
  CreateImportBatchInput,
  CreateTransactionInput,
  CreateTransactionSplitInput,
  UpdateCaptureCandidateInput,
  UpdateCategoryInput,
  UpdateImportBatchInput,
  UpdateTransactionInput,
  UpdateTransactionSplitInput,
} from '@1wallet/ledger/services';
import {
  accountBalance,
  approveCaptureCandidate,
  budgetStatuses,
  cashflow,
  categoryBreakdown,
  convertMoneyForDisplay,
  createAccount,
  createCaptureCandidate,
  createCategory,
  createImportBatch,
  createTransaction,
  createTransactionSplit,
  cycleDisplayCurrency as cycleLedgerDisplayCurrency,
  deleteAccount,
  deleteCategory,
  deleteTransaction,
  deleteTransactionSplit,
  displayCurrency,
  ensureEnabledCurrency,
  goalStatuses,
  ignoreCaptureCandidate,
  netWorth,
  queryCaptureCandidates,
  queryTransactions,
  rejectCaptureCandidate,
  removeEnabledCurrency,
  setBaseCurrency as setLedgerBaseCurrency,
  setDisplayCurrency as setLedgerDisplayCurrency,
  setRate,
  totalBalance,
  updateAccount,
  updateCaptureCandidate,
  updateCategory,
  updateImportBatch,
  updateTransaction,
  updateTransactionSplit,
} from '@1wallet/ledger/services';
import type { LedgerIndexes } from '@1wallet/ledger/services/indexes';
import { buildLedgerIndexes } from '@1wallet/ledger/services/indexes';
import type { LedgerState, LedgerStore } from '@1wallet/ledger/store/types';
import { emptyState } from '@1wallet/ledger/store/types';
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
import {
  exchangeRateRefreshKey,
  refreshInternetExchangeRates,
  type ExchangeRateRefreshResult,
} from './fxRates';

export { INTERNET_RATE_PROVIDER, refreshInternetExchangeRates } from './fxRates';
export type { ExchangeRateRefreshResult } from './fxRates';

interface LedgerContextValue {
  state: LedgerState;
  indexes: LedgerIndexes;
  ready: boolean;
  error: string | null;
  saveStatus: LedgerSaveStatus;
  saveError: string | null;
  reset: () => Promise<void>;
  resetAndMutate: (mutator: (draft: LedgerState) => void) => Promise<void>;
  replaceLedgerState: (nextState: LedgerState) => Promise<void>;
  reload: () => Promise<void>;
  flushSaves: () => Promise<void>;
  mutate: (mutator: (draft: LedgerState) => void, options?: LedgerMutationOptions) => Promise<void>;

  // Convenience actions
  addAccount: (input: CreateAccountInput) => Promise<void>;
  editAccount: (id: string, patch: Parameters<typeof updateAccount>[2]) => Promise<void>;
  removeAccount: (id: string) => Promise<void>;

  addTransaction: (input: CreateTransactionInput) => Promise<void>;
  editTransaction: (id: string, patch: UpdateTransactionInput) => Promise<void>;
  removeTransaction: (id: string) => Promise<void>;
  addTransactionSplit: (input: CreateTransactionSplitInput) => Promise<void>;
  editTransactionSplit: (id: string, patch: UpdateTransactionSplitInput) => Promise<void>;
  removeTransactionSplit: (id: string) => Promise<void>;

  addCaptureCandidate: (input: CreateCaptureCandidateInput) => Promise<void>;
  editCaptureCandidate: (id: string, patch: UpdateCaptureCandidateInput) => Promise<void>;
  approveCaptureCandidate: (id: string, input?: ApproveCaptureCandidateInput) => Promise<void>;
  approveCaptureCandidates: (
    approvals: ReadonlyArray<{ id: string; input?: ApproveCaptureCandidateInput }>,
  ) => Promise<void>;
  rejectCaptureCandidate: (id: string) => Promise<void>;
  ignoreCaptureCandidate: (id: string) => Promise<void>;

  addImportBatch: (input: CreateImportBatchInput) => Promise<void>;
  editImportBatch: (id: string, patch: UpdateImportBatchInput) => Promise<void>;

  addCategory: (input: CreateCategoryInput) => Promise<void>;
  editCategory: (id: string, patch: UpdateCategoryInput) => Promise<void>;
  removeCategory: (id: string) => Promise<void>;

  setBaseCurrency: (currency: string) => Promise<void>;
  setDisplayCurrency: (currency: string) => Promise<void>;
  cycleDisplayCurrency: () => Promise<void>;
  addCurrency: (currency: string) => Promise<void>;
  removeCurrency: (currency: string) => Promise<void>;
  setExchangeRate: (
    base: string,
    quote: string,
    rate: number,
    asOfDate?: string,
    options?: Parameters<typeof setRate>[5],
  ) => Promise<void>;
  refreshExchangeRates: () => Promise<ExchangeRateRefreshResult>;

  // Selectors (re-exported for convenience)
  selectors: {
    accountBalance: typeof accountBalance;
    displayCurrency: typeof displayCurrency;
    convertMoneyForDisplay: typeof convertMoneyForDisplay;
    totalBalance: typeof totalBalance;
    netWorth: typeof netWorth;
    cashflow: typeof cashflow;
    categoryBreakdown: typeof categoryBreakdown;
    budgetStatuses: typeof budgetStatuses;
    goalStatuses: typeof goalStatuses;
    queryTransactions: typeof queryTransactions;
    queryCaptureCandidates: typeof queryCaptureCandidates;
  };
}

type LedgerSaveStatus = 'idle' | 'pending' | 'saving' | 'error';

type SaveResolver = {
  resolve: () => void;
  reject: (error: unknown) => void;
};

type LedgerMutationSlice =
  | 'preferences'
  | 'accounts'
  | 'categories'
  | 'transactions'
  | 'transactionSplits'
  | 'budgets'
  | 'goals'
  | 'captureCandidates'
  | 'importBatches'
  | 'tags'
  | 'merchants'
  | 'exchangeRates';

type LedgerMutationOptions = {
  slices?: readonly LedgerMutationSlice[];
};

const LedgerContext = createContext<LedgerContextValue | undefined>(undefined);

const SAVE_DEBOUNCE_MS = 350;
const SAVE_IDLE_TIMEOUT_MS = 750;
const SAVE_FORCE_FLUSH_MS = 5000;
const SAVE_QUEUE_WARNING_DEPTH = 8;

type CancelScheduledTask = () => void;

export interface LedgerProviderProps {
  store: LedgerStore;
  children: ReactNode;
  /** If true, seed default categories on first run. */
  seedOnEmpty?: boolean;
}

export function LedgerProvider({ store, children, seedOnEmpty = true }: LedgerProviderProps) {
  const [state, setState] = useState<LedgerState>(() => emptyState(uid()));
  const indexes = useMemo(() => {
    const startedAt = ledgerPerfNow();
    const nextIndexes = buildLedgerIndexes(state);
    warnSlowLedgerOperation('indexes.build', startedAt, 24, {
      accounts: state.accounts.length,
      transactions: state.transactions.length,
      splits: state.transactionSplits.length,
      captureCandidates: state.captureCandidates.length,
    });
    return nextIndexes;
  }, [
    state.accounts,
    state.captureCandidates,
    state.categories,
    state.exchangeRates,
    state.preferences.baseCurrency,
    state.transactions,
    state.transactionSplits,
  ]);
  const [ready, setReady] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saveStatus, setSaveStatus] = useState<LedgerSaveStatus>('idle');
  const [saveError, setSaveError] = useState<string | null>(null);
  const autoRefreshKeyRef = useRef<string | null>(null);
  const stateRef = useRef(state);
  const pendingSaveRef = useRef<LedgerState | null>(null);
  const pendingSaveResolversRef = useRef<SaveResolver[]>([]);
  const pendingSaveQueuedAtRef = useRef<number | null>(null);
  const saveInFlightRef = useRef<Promise<void> | null>(null);
  const saveDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const saveDeadlineRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const saveIdleCancelRef = useRef<CancelScheduledTask | null>(null);
  const flushQueuedSaveRef = useRef<() => Promise<void>>(async () => undefined);

  const commitState = useCallback((nextState: LedgerState) => {
    stateRef.current = nextState;
    setState(nextState);
  }, []);

  useEffect(() => {
    stateRef.current = state;
  }, [state]);

  const clearScheduledSave = useCallback(() => {
    if (saveDebounceRef.current) {
      clearTimeout(saveDebounceRef.current);
      saveDebounceRef.current = null;
    }
    saveIdleCancelRef.current?.();
    saveIdleCancelRef.current = null;
  }, []);

  const clearSaveDeadline = useCallback(() => {
    if (!saveDeadlineRef.current) return;
    clearTimeout(saveDeadlineRef.current);
    saveDeadlineRef.current = null;
  }, []);

  const scheduleSaveDeadline = useCallback(() => {
    if (saveDeadlineRef.current) return;
    saveDeadlineRef.current = setTimeout(() => {
      saveDeadlineRef.current = null;
      if (!pendingSaveRef.current) return;
      warnLedgerMessage('save.queue.deadline_flush', {
        queuedMs:
          pendingSaveQueuedAtRef.current === null
            ? undefined
            : Math.round(Date.now() - pendingSaveQueuedAtRef.current),
        waiters: pendingSaveResolversRef.current.length,
      });
      void flushQueuedSaveRef.current().catch(() => undefined);
    }, SAVE_FORCE_FLUSH_MS);
  }, []);

  const scheduleQueuedSave = useCallback(() => {
    clearScheduledSave();
    saveDebounceRef.current = setTimeout(() => {
      saveDebounceRef.current = null;
      saveIdleCancelRef.current = scheduleLowPriorityTask(() => {
        saveIdleCancelRef.current = null;
        void flushQueuedSaveRef.current();
      }, SAVE_IDLE_TIMEOUT_MS);
    }, SAVE_DEBOUNCE_MS);
  }, [clearScheduledSave]);

  const flushQueuedSave = useCallback(() => {
    clearScheduledSave();
    clearSaveDeadline();
    if (saveInFlightRef.current) return saveInFlightRef.current;
    if (!pendingSaveRef.current) return Promise.resolve();

    const task = (async () => {
      let lastSaveFailed = false;
      while (pendingSaveRef.current) {
        const saveStartedAt = ledgerPerfNow();
        const stateToSave = pendingSaveRef.current;
        const resolvers = pendingSaveResolversRef.current;
        pendingSaveRef.current = null;
        pendingSaveResolversRef.current = [];
        pendingSaveQueuedAtRef.current = null;
        setSaveStatus('saving');

        try {
          await store.save(stateToSave);
          warnSlowLedgerOperation('save.flush', saveStartedAt, 120, {
            accounts: stateToSave.accounts.length,
            transactions: stateToSave.transactions.length,
            waiters: resolvers.length,
          });
          lastSaveFailed = false;
          setSaveError(null);
          resolvers.forEach(({ resolve }) => resolve());
        } catch (err) {
          lastSaveFailed = true;
          setSaveError(errorMessage(err, 'Could not persist your latest wallet changes.'));
          setSaveStatus('error');
          resolvers.forEach(({ reject }) => reject(err));
        }
      }

      if (!lastSaveFailed) setSaveStatus('idle');
    })();

    saveInFlightRef.current = task.finally(() => {
      saveInFlightRef.current = null;
      if (pendingSaveRef.current) scheduleQueuedSave();
    });

    return saveInFlightRef.current;
  }, [clearSaveDeadline, clearScheduledSave, scheduleQueuedSave, store]);

  flushQueuedSaveRef.current = flushQueuedSave;

  const queueSave = useCallback(
    (nextState: LedgerState) =>
      new Promise<void>((resolve, reject) => {
        pendingSaveRef.current = nextState;
        pendingSaveResolversRef.current.push({ resolve, reject });
        pendingSaveQueuedAtRef.current ??= Date.now();
        if (pendingSaveResolversRef.current.length > SAVE_QUEUE_WARNING_DEPTH) {
          warnLedgerMessage('save.queue.depth', {
            waiters: pendingSaveResolversRef.current.length,
            hasInFlightSave: Boolean(saveInFlightRef.current),
          });
        }
        if (!saveInFlightRef.current) setSaveStatus('pending');
        scheduleSaveDeadline();
        scheduleQueuedSave();
      }),
    [scheduleQueuedSave, scheduleSaveDeadline],
  );

  const waitForQueuedSaves = useCallback(async () => {
    clearScheduledSave();
    while (saveInFlightRef.current || pendingSaveRef.current) {
      await flushQueuedSave().catch(() => undefined);
    }
  }, [clearScheduledSave, flushQueuedSave]);

  useEffect(
    () => () => {
      clearScheduledSave();
      clearSaveDeadline();
    },
    [clearSaveDeadline, clearScheduledSave],
  );

  const load = useCallback(async () => {
    try {
      setError(null);
      setSaveError(null);
      await waitForQueuedSaves();
      const loaded = await store.load();
      if (seedOnEmpty && seedDefaultCategories(loaded)) {
        await store.save(loaded);
      }
      pendingSaveRef.current = null;
      pendingSaveQueuedAtRef.current = null;
      pendingSaveResolversRef.current.splice(0).forEach(({ resolve }) => resolve());
      commitState({ ...loaded });
      setSaveStatus('idle');
      setReady(true);
    } catch (err) {
      setReady(false);
      setError(errorMessage(err, 'Could not restore your wallet data.'));
      throw err;
    }
  }, [commitState, store, seedOnEmpty, waitForQueuedSaves]);

  useEffect(() => {
    void load().catch(() => undefined);
  }, [load]);

  useEffect(() => {
    if (!ready || state.preferences.fx?.autoRefresh === false) return;
    const key = exchangeRateRefreshKey(state);
    if (!key || autoRefreshKeyRef.current === key) return;
    autoRefreshKeyRef.current = key;

    let cancelled = false;
    void (async () => {
      try {
        const draft = cloneState(stateRef.current);
        const result = await refreshInternetExchangeRates(draft);
        if (cancelled || !result.refreshed) return;
        const latest = cloneState(stateRef.current);
        latest.exchangeRates = draft.exchangeRates;
        latest.preferences = {
          ...latest.preferences,
          fx: draft.preferences.fx,
        };
        if (!cancelled) {
          commitState(latest);
          void queueSave(latest).catch(() => undefined);
        }
      } catch (err) {
        console.warn('Could not refresh exchange rates from the internet', err);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [commitState, queueSave, ready, state]);

  const mutate = useCallback(
    async (mutator: (draft: LedgerState) => void, options?: LedgerMutationOptions) => {
      let draft: LedgerState;
      try {
        setError(null);
        setSaveError(null);
        const cloneStartedAt = ledgerPerfNow();
        draft = cloneLedgerStateForMutation(stateRef.current, options);
        warnSlowLedgerOperation('state.clone_for_mutation', cloneStartedAt, 24, {
          slices: options?.slices?.join(',') ?? 'all',
          accounts: stateRef.current.accounts.length,
          transactions: stateRef.current.transactions.length,
        });
        const mutateStartedAt = ledgerPerfNow();
        mutator(draft);
        warnSlowLedgerOperation('state.apply_mutation', mutateStartedAt, 16, {
          slices: options?.slices?.join(',') ?? 'all',
        });
      } catch (err) {
        setError(errorMessage(err, 'Could not save your wallet changes.'));
        throw err;
      }

      commitState(draft);
      void queueSave(draft).catch(() => undefined);
    },
    [commitState, queueSave],
  );

  const reset = useCallback(async () => {
    await waitForQueuedSaves();
    await store.clear();
    await load();
  }, [load, store, waitForQueuedSaves]);

  const resetAndMutate = useCallback(
    async (mutator: (draft: LedgerState) => void) => {
      try {
        setError(null);
        setSaveError(null);
        await waitForQueuedSaves();
        const currentState = stateRef.current;
        const draft = emptyState(currentState.userId, currentState.preferences.baseCurrency);
        draft.preferences = cloneState(currentState.preferences);
        if (seedOnEmpty) seedDefaultCategories(draft);
        mutator(draft);
        await store.save(draft);
        commitState(draft);
        setSaveStatus('idle');
        setReady(true);
      } catch (err) {
        setError(errorMessage(err, 'Could not reset your wallet data.'));
        throw err;
      }
    },
    [commitState, seedOnEmpty, store, waitForQueuedSaves],
  );

  const replaceLedgerState = useCallback(
    async (nextState: LedgerState) => {
      try {
        setError(null);
        setSaveError(null);
        await waitForQueuedSaves();
        const replacement = cloneLedgerState(nextState);
        if (seedOnEmpty) seedDefaultCategories(replacement);
        setSaveStatus('saving');
        await store.save(replacement);
        pendingSaveRef.current = null;
        pendingSaveQueuedAtRef.current = null;
        pendingSaveResolversRef.current.splice(0).forEach(({ resolve }) => resolve());
        commitState(replacement);
        setSaveStatus('idle');
        setReady(true);
      } catch (err) {
        setSaveStatus('error');
        setError(errorMessage(err, 'Could not restore your wallet backup.'));
        throw err;
      }
    },
    [commitState, seedOnEmpty, store, waitForQueuedSaves],
  );

  const refreshExchangeRates = useCallback(async () => {
    try {
      setError(null);
      setSaveError(null);
      const draft = cloneState(stateRef.current);
      const result = await refreshInternetExchangeRates(draft);
      if (result.refreshed) {
        const latest = cloneState(stateRef.current);
        latest.exchangeRates = draft.exchangeRates;
        latest.preferences = {
          ...latest.preferences,
          fx: draft.preferences.fx,
        };
        commitState(latest);
        void queueSave(latest).catch(() => undefined);
      }
      return result;
    } catch (err) {
      setError(errorMessage(err, 'Could not refresh exchange rates.'));
      throw err;
    }
  }, [commitState, queueSave]);

  const selectors = useMemo<LedgerContextValue['selectors']>(
    () => ({
      accountBalance,
      displayCurrency,
      convertMoneyForDisplay,
      totalBalance,
      netWorth,
      cashflow,
      categoryBreakdown,
      budgetStatuses,
      goalStatuses,
      queryTransactions,
      queryCaptureCandidates,
    }),
    [],
  );

  const value = useMemo<LedgerContextValue>(
    () => ({
      state,
      indexes,
      ready,
      error,
      saveStatus,
      saveError,
      reload: load,
      flushSaves: waitForQueuedSaves,
      reset,
      resetAndMutate,
      replaceLedgerState,
      mutate,
      addAccount: (input) =>
        mutate((s) => void createAccount(s, input), { slices: ['accounts', 'preferences'] }),
      editAccount: (id, patch) =>
        mutate((s) => void updateAccount(s, id, patch), { slices: ['accounts', 'preferences'] }),
      removeAccount: (id) => mutate((s) => void deleteAccount(s, id), { slices: ['accounts'] }),
      addTransaction: (input) =>
        mutate((s) => void createTransaction(s, input), { slices: ['transactions'] }),
      editTransaction: (id, patch) =>
        mutate((s) => void updateTransaction(s, id, patch), { slices: ['transactions'] }),
      removeTransaction: (id) =>
        mutate((s) => void deleteTransaction(s, id), {
          slices: ['transactions', 'transactionSplits'],
        }),
      addTransactionSplit: (input) =>
        mutate((s) => void createTransactionSplit(s, input), { slices: ['transactionSplits'] }),
      editTransactionSplit: (id, patch) =>
        mutate((s) => void updateTransactionSplit(s, id, patch), {
          slices: ['transactionSplits'],
        }),
      removeTransactionSplit: (id) =>
        mutate((s) => void deleteTransactionSplit(s, id), { slices: ['transactionSplits'] }),
      addCaptureCandidate: (input) =>
        mutate((s) => void createCaptureCandidate(s, input), { slices: ['captureCandidates'] }),
      editCaptureCandidate: (id, patch) =>
        mutate((s) => void updateCaptureCandidate(s, id, patch), {
          slices: ['captureCandidates'],
        }),
      approveCaptureCandidate: (id, input) =>
        mutate((s) => void approveCaptureCandidate(s, id, input), {
          slices: ['accounts', 'transactions', 'captureCandidates'],
        }),
      approveCaptureCandidates: (approvals) =>
        mutate(
          (s) => {
            approvals.forEach(({ id, input }) => {
              approveCaptureCandidate(s, id, input);
            });
          },
          { slices: ['accounts', 'transactions', 'captureCandidates'] },
        ),
      rejectCaptureCandidate: (id) =>
        mutate((s) => void rejectCaptureCandidate(s, id), { slices: ['captureCandidates'] }),
      ignoreCaptureCandidate: (id) =>
        mutate((s) => void ignoreCaptureCandidate(s, id), { slices: ['captureCandidates'] }),
      addImportBatch: (input) =>
        mutate((s) => void createImportBatch(s, input), { slices: ['importBatches'] }),
      editImportBatch: (id, patch) =>
        mutate((s) => void updateImportBatch(s, id, patch), { slices: ['importBatches'] }),
      addCategory: (input) =>
        mutate((s) => void createCategory(s, input), { slices: ['categories'] }),
      editCategory: (id, patch) =>
        mutate((s) => void updateCategory(s, id, patch), { slices: ['categories'] }),
      removeCategory: (id) => mutate((s) => void deleteCategory(s, id), { slices: ['categories'] }),
      setBaseCurrency: (currency) =>
        mutate((s) => void setLedgerBaseCurrency(s, currency), {
          slices: ['preferences', 'transactions'],
        }),
      setDisplayCurrency: (currency) =>
        mutate((s) => void setLedgerDisplayCurrency(s, currency), { slices: ['preferences'] }),
      cycleDisplayCurrency: () =>
        mutate((s) => void cycleLedgerDisplayCurrency(s), { slices: ['preferences'] }),
      addCurrency: (currency) =>
        mutate((s) => void ensureEnabledCurrency(s, currency), { slices: ['preferences'] }),
      removeCurrency: (currency) =>
        mutate((s) => void removeEnabledCurrency(s, currency), { slices: ['preferences'] }),
      setExchangeRate: (base, quote, rate, asOfDate, options) =>
        mutate((s) => void setRate(s, base, quote, rate, asOfDate, options), {
          slices: ['exchangeRates'],
        }),
      refreshExchangeRates,
      selectors,
    }),
    [
      state,
      indexes,
      ready,
      error,
      saveStatus,
      saveError,
      load,
      reset,
      resetAndMutate,
      replaceLedgerState,
      waitForQueuedSaves,
      mutate,
      refreshExchangeRates,
      selectors,
    ],
  );

  return <LedgerContext.Provider value={value}>{children}</LedgerContext.Provider>;
}

export function useLedger(): LedgerContextValue {
  const ctx = useContext(LedgerContext);
  if (!ctx) throw new Error('useLedger: LedgerProvider missing');
  return ctx;
}

function cloneState<T>(s: T): T {
  // Structured clone is available in modern RN and browsers; fall back to JSON.
  const g = globalThis as { structuredClone?: <T>(value: T) => T };
  if (g.structuredClone) return g.structuredClone(s);
  return JSON.parse(JSON.stringify(s)) as T;
}

type IdleRuntime = typeof globalThis & {
  requestIdleCallback?: (
    callback: (deadline: { didTimeout: boolean; timeRemaining: () => number }) => void,
    options?: { timeout?: number },
  ) => number;
  cancelIdleCallback?: (handle: number) => void;
  requestAnimationFrame?: (callback: (time: number) => void) => number;
  cancelAnimationFrame?: (handle: number) => void;
};

function scheduleLowPriorityTask(task: () => void, timeoutMs: number): CancelScheduledTask {
  const runtime = globalThis as IdleRuntime;
  if (runtime.requestIdleCallback) {
    const idleHandle = runtime.requestIdleCallback(task, { timeout: timeoutMs });
    return () => runtime.cancelIdleCallback?.(idleHandle);
  }

  let cancelled = false;
  let frameHandle: number | undefined;
  const timeoutHandle = setTimeout(() => {
    if (cancelled) return;
    if (runtime.requestAnimationFrame) {
      frameHandle = runtime.requestAnimationFrame(() => {
        if (cancelled) return;
        cancelled = true;
        task();
      });
      return;
    }
    cancelled = true;
    task();
  }, timeoutMs);

  return () => {
    cancelled = true;
    clearTimeout(timeoutHandle);
    if (frameHandle !== undefined) runtime.cancelAnimationFrame?.(frameHandle);
  };
}

function cloneLedgerStateForMutation(
  state: LedgerState,
  options?: LedgerMutationOptions,
): LedgerState {
  if (!options?.slices?.length) return cloneLedgerState(state);
  const slices = new Set(options.slices);
  return {
    ...state,
    preferences: slices.has('preferences') ? cloneState(state.preferences) : state.preferences,
    accounts: slices.has('accounts') ? cloneLedgerAccounts(state.accounts) : state.accounts,
    categories: slices.has('categories')
      ? cloneLedgerCategories(state.categories)
      : state.categories,
    transactions: slices.has('transactions')
      ? cloneLedgerTransactions(state.transactions)
      : state.transactions,
    transactionSplits: slices.has('transactionSplits')
      ? cloneLedgerTransactionSplits(state.transactionSplits)
      : state.transactionSplits,
    budgets: slices.has('budgets') ? cloneLedgerBudgets(state.budgets) : state.budgets,
    goals: slices.has('goals') ? cloneLedgerGoals(state.goals) : state.goals,
    captureCandidates: slices.has('captureCandidates')
      ? cloneLedgerCaptureCandidates(state.captureCandidates)
      : state.captureCandidates,
    importBatches: slices.has('importBatches')
      ? cloneLedgerImportBatches(state.importBatches)
      : state.importBatches,
    tags: slices.has('tags') ? cloneLedgerTags(state.tags) : state.tags,
    merchants: slices.has('merchants') ? cloneLedgerMerchants(state.merchants) : state.merchants,
    exchangeRates: slices.has('exchangeRates')
      ? cloneLedgerExchangeRates(state.exchangeRates)
      : state.exchangeRates,
  };
}

function cloneLedgerState(state: LedgerState): LedgerState {
  return {
    ...state,
    preferences: cloneState(state.preferences),
    accounts: cloneLedgerAccounts(state.accounts),
    categories: cloneLedgerCategories(state.categories),
    transactions: cloneLedgerTransactions(state.transactions),
    transactionSplits: cloneLedgerTransactionSplits(state.transactionSplits),
    budgets: cloneLedgerBudgets(state.budgets),
    goals: cloneLedgerGoals(state.goals),
    captureCandidates: cloneLedgerCaptureCandidates(state.captureCandidates),
    importBatches: cloneLedgerImportBatches(state.importBatches),
    tags: cloneLedgerTags(state.tags),
    merchants: cloneLedgerMerchants(state.merchants),
    exchangeRates: cloneLedgerExchangeRates(state.exchangeRates),
  };
}

function cloneLedgerAccounts(accounts: LedgerState['accounts']): LedgerState['accounts'] {
  return accounts.map((account) => ({
    ...account,
    openingBalance: { ...account.openingBalance },
    loanDetails: account.loanDetails
      ? {
          ...account.loanDetails,
          principal: account.loanDetails.principal
            ? { ...account.loanDetails.principal }
            : undefined,
          repaymentAmount: account.loanDetails.repaymentAmount
            ? { ...account.loanDetails.repaymentAmount }
            : undefined,
        }
      : undefined,
    matchIdentifiers: account.matchIdentifiers?.map((identifier) => ({ ...identifier })),
    messageSourceHints: account.messageSourceHints
      ? {
          ...account.messageSourceHints,
          smsSenderIds: account.messageSourceHints.smsSenderIds
            ? [...account.messageSourceHints.smsSenderIds]
            : undefined,
          emailDomains: account.messageSourceHints.emailDomains
            ? [...account.messageSourceHints.emailDomains]
            : undefined,
          keywords: account.messageSourceHints.keywords
            ? [...account.messageSourceHints.keywords]
            : undefined,
        }
      : undefined,
  }));
}

function cloneLedgerCategories(categories: LedgerState['categories']): LedgerState['categories'] {
  return categories.map((category) => ({ ...category }));
}

function cloneLedgerTransactions(
  transactions: LedgerState['transactions'],
): LedgerState['transactions'] {
  return transactions.map((transaction) => ({
    ...transaction,
    amount: { ...transaction.amount },
    baseAmount: { ...transaction.baseAmount },
    originalAmount: transaction.originalAmount ? { ...transaction.originalAmount } : undefined,
    counterAmount: transaction.counterAmount ? { ...transaction.counterAmount } : undefined,
    attachments: transaction.attachments?.map((attachment) => ({ ...attachment })),
    tags: transaction.tags ? [...transaction.tags] : undefined,
  }));
}

function cloneLedgerTransactionSplits(
  splits: LedgerState['transactionSplits'],
): LedgerState['transactionSplits'] {
  return splits.map((split) => ({ ...split, amount: { ...split.amount } }));
}

function cloneLedgerBudgets(budgets: LedgerState['budgets']): LedgerState['budgets'] {
  return budgets.map((budget) => ({ ...budget }));
}

function cloneLedgerGoals(goals: LedgerState['goals']): LedgerState['goals'] {
  return goals.map((goal) => ({ ...goal }));
}

function cloneLedgerCaptureCandidates(
  candidates: LedgerState['captureCandidates'],
): LedgerState['captureCandidates'] {
  return candidates.map((candidate) => ({
    ...candidate,
    parsedAmount: candidate.parsedAmount ? { ...candidate.parsedAmount } : undefined,
    parsedOriginalAmount: candidate.parsedOriginalAmount
      ? { ...candidate.parsedOriginalAmount }
      : undefined,
    parsedCounterAmount: candidate.parsedCounterAmount
      ? { ...candidate.parsedCounterAmount }
      : undefined,
    parsedTags: candidate.parsedTags ? [...candidate.parsedTags] : undefined,
    warnings: candidate.warnings ? [...candidate.warnings] : undefined,
    rawPayload: { ...candidate.rawPayload },
  }));
}

function cloneLedgerImportBatches(
  batches: LedgerState['importBatches'],
): LedgerState['importBatches'] {
  return batches.map((batch) => ({ ...batch, fileNames: [...batch.fileNames] }));
}

function cloneLedgerTags(tags: LedgerState['tags']): LedgerState['tags'] {
  return tags.map((tag) => ({ ...tag }));
}

function cloneLedgerMerchants(merchants: LedgerState['merchants']): LedgerState['merchants'] {
  return merchants.map((merchant) => ({ ...merchant }));
}

function cloneLedgerExchangeRates(
  rates: LedgerState['exchangeRates'],
): LedgerState['exchangeRates'] {
  return rates.map((rate) => ({ ...rate }));
}

function ledgerPerfNow(): number {
  return typeof performance !== 'undefined' && typeof performance.now === 'function'
    ? performance.now()
    : Date.now();
}

function shouldLogLedgerPerformance(): boolean {
  const runtime = globalThis as { __DEV__?: boolean };
  return runtime.__DEV__ === true;
}

function warnSlowLedgerOperation(
  name: string,
  startedAt: number,
  thresholdMs: number,
  details?: Record<string, unknown>,
): number {
  const durationMs = ledgerPerfNow() - startedAt;
  if (shouldLogLedgerPerformance() && durationMs >= thresholdMs) {
    console.warn(`[ledger-perf] ${name} ${durationMs.toFixed(1)}ms`, details ?? '');
  }
  return durationMs;
}

function warnLedgerMessage(name: string, details?: Record<string, unknown>): void {
  if (!shouldLogLedgerPerformance()) return;
  console.warn(`[ledger-perf] ${name}`, details ?? '');
}

function errorMessage(err: unknown, fallback: string): string {
  return err instanceof Error && err.message ? err.message : fallback;
}
