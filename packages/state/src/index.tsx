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
  mutate: (mutator: (draft: LedgerState) => void) => Promise<void>;

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

const LedgerContext = createContext<LedgerContextValue | undefined>(undefined);

const SAVE_DEBOUNCE_MS = 350;

export interface LedgerProviderProps {
  store: LedgerStore;
  children: ReactNode;
  /** If true, seed default categories on first run. */
  seedOnEmpty?: boolean;
}

export function LedgerProvider({ store, children, seedOnEmpty = true }: LedgerProviderProps) {
  const [state, setState] = useState<LedgerState>(() => emptyState(uid()));
  const indexes = useMemo(
    () => buildLedgerIndexes(state),
    [
      state.accounts,
      state.categories,
      state.exchangeRates,
      state.preferences.baseCurrency,
      state.transactions,
      state.transactionSplits,
    ],
  );
  const [ready, setReady] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saveStatus, setSaveStatus] = useState<LedgerSaveStatus>('idle');
  const [saveError, setSaveError] = useState<string | null>(null);
  const autoRefreshKeyRef = useRef<string | null>(null);
  const stateRef = useRef(state);
  const pendingSaveRef = useRef<LedgerState | null>(null);
  const pendingSaveResolversRef = useRef<SaveResolver[]>([]);
  const saveInFlightRef = useRef<Promise<void> | null>(null);
  const saveDebounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const flushQueuedSaveRef = useRef<() => Promise<void>>(async () => undefined);

  const commitState = useCallback((nextState: LedgerState) => {
    stateRef.current = nextState;
    setState(nextState);
  }, []);

  useEffect(() => {
    stateRef.current = state;
  }, [state]);

  const clearScheduledSave = useCallback(() => {
    if (!saveDebounceRef.current) return;
    clearTimeout(saveDebounceRef.current);
    saveDebounceRef.current = null;
  }, []);

  const scheduleQueuedSave = useCallback(() => {
    clearScheduledSave();
    saveDebounceRef.current = setTimeout(() => {
      saveDebounceRef.current = null;
      void flushQueuedSaveRef.current();
    }, SAVE_DEBOUNCE_MS);
  }, [clearScheduledSave]);

  const flushQueuedSave = useCallback(() => {
    clearScheduledSave();
    if (saveInFlightRef.current) return saveInFlightRef.current;
    if (!pendingSaveRef.current) return Promise.resolve();

    const task = (async () => {
      let lastSaveFailed = false;
      while (pendingSaveRef.current) {
        const stateToSave = pendingSaveRef.current;
        const resolvers = pendingSaveResolversRef.current;
        pendingSaveRef.current = null;
        pendingSaveResolversRef.current = [];
        setSaveStatus('saving');

        try {
          await store.save(stateToSave);
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
  }, [clearScheduledSave, scheduleQueuedSave, store]);

  flushQueuedSaveRef.current = flushQueuedSave;

  const queueSave = useCallback(
    (nextState: LedgerState) =>
      new Promise<void>((resolve, reject) => {
        pendingSaveRef.current = nextState;
        pendingSaveResolversRef.current.push({ resolve, reject });
        if (!saveInFlightRef.current) setSaveStatus('pending');
        scheduleQueuedSave();
      }),
    [scheduleQueuedSave],
  );

  const waitForQueuedSaves = useCallback(async () => {
    clearScheduledSave();
    while (saveInFlightRef.current || pendingSaveRef.current) {
      await flushQueuedSave().catch(() => undefined);
    }
  }, [clearScheduledSave, flushQueuedSave]);

  useEffect(() => () => clearScheduledSave(), [clearScheduledSave]);

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
    async (mutator: (draft: LedgerState) => void) => {
      let draft: LedgerState;
      try {
        setError(null);
        setSaveError(null);
        draft = cloneLedgerState(stateRef.current);
        mutator(draft);
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
      addAccount: (input) => mutate((s) => void createAccount(s, input)),
      editAccount: (id, patch) => mutate((s) => void updateAccount(s, id, patch)),
      removeAccount: (id) => mutate((s) => void deleteAccount(s, id)),
      addTransaction: (input) => mutate((s) => void createTransaction(s, input)),
      editTransaction: (id, patch) => mutate((s) => void updateTransaction(s, id, patch)),
      removeTransaction: (id) => mutate((s) => void deleteTransaction(s, id)),
      addTransactionSplit: (input) => mutate((s) => void createTransactionSplit(s, input)),
      editTransactionSplit: (id, patch) => mutate((s) => void updateTransactionSplit(s, id, patch)),
      removeTransactionSplit: (id) => mutate((s) => void deleteTransactionSplit(s, id)),
      addCaptureCandidate: (input) => mutate((s) => void createCaptureCandidate(s, input)),
      editCaptureCandidate: (id, patch) => mutate((s) => void updateCaptureCandidate(s, id, patch)),
      approveCaptureCandidate: (id, input) =>
        mutate((s) => void approveCaptureCandidate(s, id, input)),
      approveCaptureCandidates: (approvals) =>
        mutate((s) => {
          approvals.forEach(({ id, input }) => {
            approveCaptureCandidate(s, id, input);
          });
        }),
      rejectCaptureCandidate: (id) => mutate((s) => void rejectCaptureCandidate(s, id)),
      ignoreCaptureCandidate: (id) => mutate((s) => void ignoreCaptureCandidate(s, id)),
      addImportBatch: (input) => mutate((s) => void createImportBatch(s, input)),
      editImportBatch: (id, patch) => mutate((s) => void updateImportBatch(s, id, patch)),
      addCategory: (input) => mutate((s) => void createCategory(s, input)),
      editCategory: (id, patch) => mutate((s) => void updateCategory(s, id, patch)),
      removeCategory: (id) => mutate((s) => void deleteCategory(s, id)),
      setBaseCurrency: (currency) => mutate((s) => void setLedgerBaseCurrency(s, currency)),
      setDisplayCurrency: (currency) => mutate((s) => void setLedgerDisplayCurrency(s, currency)),
      cycleDisplayCurrency: () => mutate((s) => void cycleLedgerDisplayCurrency(s)),
      addCurrency: (currency) => mutate((s) => void ensureEnabledCurrency(s, currency)),
      removeCurrency: (currency) => mutate((s) => void removeEnabledCurrency(s, currency)),
      setExchangeRate: (base, quote, rate, asOfDate, options) =>
        mutate((s) => void setRate(s, base, quote, rate, asOfDate, options)),
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

function cloneLedgerState(state: LedgerState): LedgerState {
  return {
    ...state,
    preferences: cloneState(state.preferences),
    accounts: state.accounts.map((account) => ({
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
    })),
    categories: state.categories.map((category) => ({ ...category })),
    transactions: state.transactions.map((transaction) => ({
      ...transaction,
      amount: { ...transaction.amount },
      baseAmount: { ...transaction.baseAmount },
      originalAmount: transaction.originalAmount ? { ...transaction.originalAmount } : undefined,
      counterAmount: transaction.counterAmount ? { ...transaction.counterAmount } : undefined,
      attachments: transaction.attachments?.map((attachment) => ({ ...attachment })),
      tags: transaction.tags ? [...transaction.tags] : undefined,
    })),
    transactionSplits: state.transactionSplits.map((split) => ({
      ...split,
      amount: { ...split.amount },
    })),
    budgets: state.budgets.map((budget) => ({ ...budget })),
    goals: state.goals.map((goal) => ({ ...goal })),
    captureCandidates: state.captureCandidates.map((candidate) => ({
      ...candidate,
      warnings: candidate.warnings ? [...candidate.warnings] : undefined,
      rawPayload: { ...candidate.rawPayload },
    })),
    importBatches: state.importBatches.map((batch) => ({
      ...batch,
      fileNames: [...batch.fileNames],
    })),
    tags: state.tags.map((tag) => ({ ...tag })),
    merchants: state.merchants.map((merchant) => ({ ...merchant })),
    exchangeRates: state.exchangeRates.map((rate) => ({ ...rate })),
  };
}

function errorMessage(err: unknown, fallback: string): string {
  return err instanceof Error && err.message ? err.message : fallback;
}
