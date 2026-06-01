import {
    exportOneWalletArchive,
    ledgerStateFromOneWalletArchive,
    parseOneWalletArchive,
    type OneWalletArchiveSummary,
    type OneWalletArchiveV1,
} from '@1wallet/ledger/archive/onewallet';
import { LEDGER_STATE_VERSION, type LedgerState } from '@1wallet/ledger/store/types';
import { useLedger } from '@1wallet/state';
import {
    collection,
    doc,
    getDoc,
    getDocs,
    orderBy,
    query,
    serverTimestamp,
    writeBatch,
} from 'firebase/firestore';
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
import { AppState } from 'react-native';
import { useAuth } from '../auth';
import { getFirebaseServices } from '../firebase/client';
import {
    loadCloudSyncMetadata,
    saveCloudSyncMetadata,
    savePreRestoreLedgerBackup,
    type CloudSyncMetadata,
} from './storage';

const WALLET_ID = 'default';
const UPLOAD_DEBOUNCE_MS = 2500;
const UPLOAD_RETRY_MS = 120000;
const SNAPSHOT_CHUNK_SIZE = 512 * 1024;

type CloudSyncPhase = 'disabled' | 'idle' | 'checking' | 'restoring' | 'uploading' | 'error';

type CloudWalletDocument = {
  cloudRevision?: number;
  latestSnapshotId?: string;
  latestSnapshotChecksum?: string;
  latestSnapshotChunks?: number;
  latestSnapshotSize?: number;
  ledgerStateVersion?: number;
  summary?: OneWalletArchiveSummary;
};

type CloudSyncContextValue = {
  configured: boolean;
  enabled: boolean;
  phase: CloudSyncPhase;
  error: string | null;
  disabledReason: string | null;
  metadata: CloudSyncMetadata | null;
  pendingUpload: boolean;
  bootstrapComplete: boolean;
  bootstrappedUserId: string | null;
  prepareForLocalClear: () => Promise<void>;
  resumeAfterLocalClear: () => void;
  retryBootstrap: () => void;
};

const CloudSyncContext = createContext<CloudSyncContextValue | undefined>(undefined);

export function LedgerCloudSyncProvider({ children }: { children: ReactNode }) {
  const services = useMemo(() => getFirebaseServices(), []);
  const { user } = useAuth();
  const { state, ready, replaceLedgerState, flushSaves } = useLedger();
  const [metadata, setMetadata] = useState<CloudSyncMetadata | null>(null);
  const [phase, setPhase] = useState<CloudSyncPhase>('disabled');
  const [error, setError] = useState<string | null>(null);
  const [pendingUpload, setPendingUpload] = useState(false);
  const [bootstrappedUserId, setBootstrappedUserId] = useState<string | null>(null);
  const [bootstrapRetryKey, setBootstrapRetryKey] = useState(0);
  const metadataRef = useRef<CloudSyncMetadata | null>(null);
  const latestStateRef = useRef(state);
  const pendingUploadRef = useRef(false);
  const bootstrappedUserRef = useRef<string | null>(null);
  const bootstrapInFlightRef = useRef<Promise<void> | null>(null);
  const uploadTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const retryTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const uploadInFlightRef = useRef<Promise<void> | null>(null);
  const localClearInProgressRef = useRef(false);
  const phaseRef = useRef<CloudSyncPhase>(phase);
  latestStateRef.current = state;
  pendingUploadRef.current = pendingUpload;
  phaseRef.current = phase;

  const enabled = Boolean(services && user?.provider === 'firebase');
  const disabledReason = !services
    ? 'Cloud sync is not configured.'
    : user?.provider !== 'firebase'
      ? 'Sign in with Google to enable sync.'
      : null;

  const clearUploadTimers = useCallback(() => {
    if (uploadTimerRef.current) {
      clearTimeout(uploadTimerRef.current);
      uploadTimerRef.current = null;
    }
    if (retryTimerRef.current) {
      clearInterval(retryTimerRef.current);
      retryTimerRef.current = null;
    }
  }, []);

  const persistMetadata = useCallback(async (nextMetadata: CloudSyncMetadata) => {
    metadataRef.current = nextMetadata;
    setMetadata(nextMetadata);
    await saveCloudSyncMetadata(nextMetadata);
  }, []);

  const ensureMetadata = useCallback(async () => {
    if (metadataRef.current) return metadataRef.current;
    const loaded = await loadCloudSyncMetadata();
    metadataRef.current = loaded;
    setMetadata(loaded);
    return loaded;
  }, []);

  const readCloudWallet = useCallback(
    async (uid: string): Promise<CloudWalletDocument | null> => {
      if (!services) return null;
      const snapshot = await getDoc(doc(services.db, 'users', uid, 'wallets', WALLET_ID));
      return snapshot.exists() ? (snapshot.data() as CloudWalletDocument) : null;
    },
    [services],
  );

  const restoreCloudSnapshot = useCallback(
    async (wallet: CloudWalletDocument, uid: string, currentMetadata: CloudSyncMetadata) => {
      if (!services || !wallet.latestSnapshotId) return currentMetadata;
      setPhase('restoring');
      setError(null);

      const localArchive = exportOneWalletArchive(latestStateRef.current, { source: 'mobile' });
      const shouldKeepLocalBackup =
        walletHasUserData(latestStateRef.current) &&
        localArchive.checksum !== wallet.latestSnapshotChecksum;
      const backupUri = shouldKeepLocalBackup
        ? await savePreRestoreLedgerBackup(uid, localArchive)
        : currentMetadata.lastRestoreBackupUri;

      const archive = parseOneWalletArchive(await readFirestoreSnapshot(uid, wallet));
      assertCloudSnapshotMatchesWallet(archive, wallet);
      const restored = ledgerStateFromOneWalletArchive(archive, { userId: uid });
      await replaceLedgerState(restored);

      const now = new Date().toISOString();
      const nextMetadata: CloudSyncMetadata = {
        ...currentMetadata,
        userId: uid,
        lastCloudRevision: wallet.cloudRevision,
        lastLocalChecksum: archive.checksum,
        lastSnapshotChecksum: archive.checksum,
        lastSnapshotPath: wallet.latestSnapshotId,
        lastPulledAt: now,
        lastRestoreBackupUri: backupUri,
      };
      await persistMetadata(nextMetadata);
      setPhase('idle');
      return nextMetadata;
    },
    [persistMetadata, replaceLedgerState, services],
  );

  const uploadSnapshot = useCallback(
    async (reason: 'auto' | 'seed') => {
      if (!services || !user || user.provider !== 'firebase') return;
      if (!ready) return;
      if (uploadInFlightRef.current) return uploadInFlightRef.current;

      const task = (async () => {
        const stateToUpload = ledgerStateForCloudUser(latestStateRef.current, user.id);
        if (!walletHasUserData(stateToUpload)) {
          setPendingUpload(false);
          return;
        }

        const currentMetadata = await ensureMetadata();
        const archive = exportOneWalletArchive(stateToUpload, { source: 'mobile' });
        if (reason === 'auto' && currentMetadata.lastLocalChecksum === archive.checksum) {
          setPendingUpload(false);
          return;
        }

        setPendingUpload(false);
        setPhase('uploading');
        setError(null);
        if (reason === 'seed') {
          await flushSaves();
        } else {
          void flushSaves().catch(() => undefined);
        }

        const now = new Date().toISOString();
        const revision = Date.now();
        const snapshotId = `${revision}-${currentMetadata.deviceId}`;
        const snapshotContent = JSON.stringify(archive);
        const chunks = chunkString(snapshotContent, SNAPSHOT_CHUNK_SIZE);
        const snapshotDocument = doc(
          services.db,
          'users',
          user.id,
          'wallets',
          WALLET_ID,
          'snapshots',
          snapshotId,
        );

        const batch = writeBatch(services.db);
        batch.set(snapshotDocument, {
          snapshotId,
          checksum: archive.checksum,
          chunks: chunks.length,
          size: snapshotContent.length,
          reason,
          ledgerStateVersion: archive.ledgerStateVersion,
          summary: archive.summary,
          writerDeviceId: currentMetadata.deviceId,
          createdAt: serverTimestamp(),
        });
        chunks.forEach((content, index) => {
          batch.set(doc(snapshotDocument, 'chunks', String(index).padStart(5, '0')), {
            index,
            content,
          });
        });
        batch.set(
          doc(services.db, 'users', user.id),
          {
            email: user.email,
            displayName: user.displayName ?? null,
            authProvider: 'google',
            updatedAt: serverTimestamp(),
          },
          { merge: true },
        );
        batch.set(
          doc(services.db, 'users', user.id, 'wallets', WALLET_ID),
          {
            walletId: WALLET_ID,
            cloudRevision: revision,
            latestSnapshotId: snapshotId,
            latestSnapshotChecksum: archive.checksum,
            latestSnapshotChunks: chunks.length,
            latestSnapshotSize: snapshotContent.length,
            ledgerStateVersion: archive.ledgerStateVersion,
            summary: archive.summary,
            lastWriterDeviceId: currentMetadata.deviceId,
            lastWriterAt: now,
            updatedAt: serverTimestamp(),
          },
          { merge: true },
        );
        await batch.commit();

        await persistMetadata({
          ...currentMetadata,
          userId: user.id,
          lastCloudRevision: revision,
          lastLocalChecksum: archive.checksum,
          lastSnapshotChecksum: archive.checksum,
          lastSnapshotPath: snapshotId,
          lastPushedAt: now,
        });
        setPhase('idle');
      })().catch((err) => {
        setPendingUpload(true);
        setPhase('error');
        setError(errorMessage(err, 'Could not sync your wallet to Firebase.'));
        throw err;
      });

      uploadInFlightRef.current = task.finally(() => {
        uploadInFlightRef.current = null;
      });
      return uploadInFlightRef.current;
    },
    [ensureMetadata, flushSaves, persistMetadata, ready, services, user],
  );

  const bootstrap = useCallback(async () => {
    if (!enabled || !services || !user || !ready) return;
    if (bootstrappedUserRef.current === user.id) return;
    if (bootstrapInFlightRef.current) return bootstrapInFlightRef.current;

    const task = (async () => {
      try {
        setBootstrappedUserId(null);
        setPhase('checking');
        setError(null);
        let currentMetadata = await ensureMetadata();
        if (currentMetadata.userId !== user.id) {
          currentMetadata = {
            version: currentMetadata.version,
            deviceId: currentMetadata.deviceId,
            userId: user.id,
          };
          await persistMetadata(currentMetadata);
        }

        const wallet = await readCloudWallet(user.id);
        if (wallet?.latestSnapshotId) {
          await restoreCloudSnapshot(wallet, user.id, currentMetadata);
        } else if (walletHasUserData(latestStateRef.current)) {
          await uploadSnapshot('seed');
        } else {
          setPhase('idle');
        }
        bootstrappedUserRef.current = user.id;
        setBootstrappedUserId(user.id);
      } catch (err) {
        bootstrappedUserRef.current = null;
        setBootstrappedUserId(null);
        setPhase('error');
        setError(errorMessage(err, 'Could not prepare sync.'));
        throw err;
      }
    })();

    bootstrapInFlightRef.current = task.finally(() => {
      bootstrapInFlightRef.current = null;
    });
    return bootstrapInFlightRef.current;
  }, [
    enabled,
    ensureMetadata,
    persistMetadata,
    readCloudWallet,
    ready,
    restoreCloudSnapshot,
    services,
    uploadSnapshot,
    user,
  ]);

  const retryBootstrap = useCallback(() => {
    bootstrappedUserRef.current = null;
    setBootstrappedUserId(null);
    setError(null);
    setBootstrapRetryKey((value) => value + 1);
  }, []);

  const prepareForLocalClear = useCallback(async () => {
    localClearInProgressRef.current = true;
    clearUploadTimers();

    try {
      await flushSaves();
      if (!enabled || !services || !user || user.provider !== 'firebase' || !ready) {
        setPendingUpload(false);
        return;
      }

      if (bootstrapInFlightRef.current) await bootstrapInFlightRef.current;
      if (bootstrappedUserRef.current !== user.id) await bootstrap();
      if (uploadInFlightRef.current) await uploadInFlightRef.current;
      clearUploadTimers();
      await uploadSnapshot('auto');
      setPendingUpload(false);
    } catch (err) {
      localClearInProgressRef.current = false;
      throw err;
    }
  }, [bootstrap, clearUploadTimers, enabled, flushSaves, ready, services, uploadSnapshot, user]);

  const resumeAfterLocalClear = useCallback(() => {
    localClearInProgressRef.current = false;
  }, []);

  useEffect(() => {
    if (!enabled) {
      clearUploadTimers();
      localClearInProgressRef.current = false;
      metadataRef.current = null;
      setMetadata(null);
      bootstrappedUserRef.current = null;
      setBootstrappedUserId(null);
      setPhase('disabled');
      return;
    }
    if (bootstrappedUserRef.current && bootstrappedUserRef.current !== user?.id) {
      bootstrappedUserRef.current = null;
      setBootstrappedUserId(null);
    }
    void bootstrap().catch(() => undefined);
  }, [bootstrap, bootstrapRetryKey, clearUploadTimers, enabled, user?.id]);

  useEffect(() => {
    if (!enabled || !ready || !user) return;
    if (localClearInProgressRef.current) return;
    if (bootstrappedUserRef.current !== user.id) return;
    if (phaseRef.current === 'restoring' || phaseRef.current === 'checking') return;

    setPendingUpload(true);
    if (uploadTimerRef.current) clearTimeout(uploadTimerRef.current);
    uploadTimerRef.current = setTimeout(() => {
      uploadTimerRef.current = null;
      void uploadSnapshot('auto').catch(() => undefined);
    }, UPLOAD_DEBOUNCE_MS);

    return () => {
      if (!uploadTimerRef.current) return;
      clearTimeout(uploadTimerRef.current);
      uploadTimerRef.current = null;
    };
  }, [enabled, ready, state, uploadSnapshot, user]);

  useEffect(() => {
    if (!enabled || !ready || !user || bootstrappedUserRef.current !== user.id) return;
    if (localClearInProgressRef.current) return;
    if (!pendingUpload) return;

    retryTimerRef.current = setInterval(() => {
      if (!pendingUploadRef.current) return;
      if (phaseRef.current === 'checking' || phaseRef.current === 'restoring') return;
      void uploadSnapshot('auto').catch(() => undefined);
    }, UPLOAD_RETRY_MS);

    return () => {
      if (!retryTimerRef.current) return;
      clearInterval(retryTimerRef.current);
      retryTimerRef.current = null;
    };
  }, [enabled, pendingUpload, ready, uploadSnapshot, user]);

  useEffect(() => {
    const subscription = AppState.addEventListener('change', (status) => {
      if (localClearInProgressRef.current) return;
      if (status !== 'background' && status !== 'inactive' && status !== 'active') return;
      if (status === 'active' && !pendingUploadRef.current) return;
      if (status !== 'active' && !pendingUploadRef.current && !uploadTimerRef.current) return;
      if (uploadTimerRef.current) {
        clearTimeout(uploadTimerRef.current);
        uploadTimerRef.current = null;
      }
      void uploadSnapshot('auto').catch(() => undefined);
    });
    return () => subscription.remove();
  }, [uploadSnapshot]);

  const value = useMemo<CloudSyncContextValue>(
    () => ({
      configured: Boolean(services),
      enabled,
      phase,
      error,
      disabledReason,
      metadata,
      pendingUpload,
      bootstrapComplete: !enabled || Boolean(user && bootstrappedUserId === user.id),
      bootstrappedUserId,
      prepareForLocalClear,
      resumeAfterLocalClear,
      retryBootstrap,
    }),
    [
      bootstrappedUserId,
      disabledReason,
      enabled,
      error,
      metadata,
      pendingUpload,
      phase,
      prepareForLocalClear,
      resumeAfterLocalClear,
      retryBootstrap,
      services,
      user,
    ],
  );

  return <CloudSyncContext.Provider value={value}>{children}</CloudSyncContext.Provider>;
}

export function useCloudSync() {
  const value = useContext(CloudSyncContext);
  if (!value) throw new Error('useCloudSync must be used within LedgerCloudSyncProvider');
  return value;
}

function walletHasUserData(state: LedgerState): boolean {
  return (
    state.accounts.length > 0 ||
    state.transactions.length > 0 ||
    state.transactionSplits.length > 0 ||
    state.captureCandidates.length > 0 ||
    state.importBatches.length > 0 ||
    state.budgets.length > 0 ||
    state.goals.length > 0 ||
    (state.preferences.futureGenerationRules?.length ?? 0) > 0
  );
}

function ledgerStateForCloudUser(state: LedgerState, userId: string): LedgerState {
  const archive = exportOneWalletArchive(state, { source: 'mobile' });
  return ledgerStateFromOneWalletArchive(archive, { userId });
}

async function readFirestoreSnapshot(uid: string, wallet: CloudWalletDocument): Promise<string> {
  const services = getFirebaseServices();
  if (!services || !wallet.latestSnapshotId) throw new Error('Firebase snapshot is unavailable.');
  const chunkSnapshots = await getDocs(
    query(
      collection(
        services.db,
        'users',
        uid,
        'wallets',
        WALLET_ID,
        'snapshots',
        wallet.latestSnapshotId,
        'chunks',
      ),
      orderBy('index'),
    ),
  );
  if (
    typeof wallet.latestSnapshotChunks === 'number' &&
    chunkSnapshots.docs.length !== wallet.latestSnapshotChunks
  ) {
    throw new Error('Cloud wallet backup is missing one or more chunks.');
  }

  const chunks = chunkSnapshots.docs.map((snapshot) => snapshot.data().content);
  if (chunks.some((value) => typeof value !== 'string')) {
    throw new Error('Cloud wallet backup contains an invalid chunk.');
  }
  const content = (chunks as string[]).join('');
  if (!content) throw new Error('Cloud wallet backup is empty.');
  if (
    typeof wallet.latestSnapshotSize === 'number' &&
    content.length !== wallet.latestSnapshotSize
  ) {
    throw new Error('Cloud wallet backup size does not match its metadata.');
  }
  return content;
}

function assertCloudSnapshotMatchesWallet(
  archive: OneWalletArchiveV1,
  wallet: CloudWalletDocument,
): void {
  if (
    wallet.latestSnapshotChecksum &&
    archive.checksum &&
    archive.checksum !== wallet.latestSnapshotChecksum
  ) {
    throw new Error('Cloud wallet backup checksum does not match its metadata.');
  }
  if (
    typeof wallet.ledgerStateVersion === 'number' &&
    archive.ledgerStateVersion !== wallet.ledgerStateVersion
  ) {
    throw new Error('Cloud wallet backup version does not match its metadata.');
  }
  if (archive.ledgerStateVersion > LEDGER_STATE_VERSION) {
    throw new Error('Cloud wallet backup was created by a newer 1wallet version.');
  }
}

function chunkString(value: string, chunkSize: number): string[] {
  const chunks: string[] = [];
  for (let index = 0; index < value.length; index += chunkSize) {
    chunks.push(value.slice(index, index + chunkSize));
  }
  return chunks.length > 0 ? chunks : [''];
}

function errorMessage(err: unknown, fallback: string): string {
  return err instanceof Error && err.message ? err.message : fallback;
}
