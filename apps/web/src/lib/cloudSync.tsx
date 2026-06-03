'use client';

import {
  exportOneWalletArchive,
  ledgerStateFromOneWalletArchive,
  parseOneWalletArchive,
} from '@1wallet/ledger/archive/onewallet';
import type { OneWalletArchiveSummary } from '@1wallet/ledger/archive/onewallet';
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
import { useAuth } from './auth';
import { db } from './firebase';

const WALLET_ID = 'default';
const UPLOAD_DEBOUNCE_MS = 2500;
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

type CloudSyncMetadata = {
  userId: string;
  deviceId: string;
  lastLocalChecksum?: string;
  lastSnapshotChecksum?: string;
  lastSnapshotPath?: string;
  lastCloudRevision?: number;
};

type CloudSyncContextValue = {
  enabled: boolean;
  phase: CloudSyncPhase;
  error: string | null;
  pendingUpload: boolean;
};

const CloudSyncContext = createContext<CloudSyncContextValue | undefined>(undefined);

export function CloudSyncProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  const { state, ready, replaceLedgerState } = useLedger();

  const [phase, setPhase] = useState<CloudSyncPhase>('disabled');
  const [error, setError] = useState<string | null>(null);
  const [pendingUpload, setPendingUpload] = useState(false);

  const enabled = Boolean(db && user?.provider === 'firebase');

  const latestStateRef = useRef(state);
  const uploadTimerRef = useRef<NodeJS.Timeout | null>(null);
  const bootstrappedRef = useRef(false);

  useEffect(() => {
    latestStateRef.current = state;
  }, [state]);

  const ensureDeviceId = useCallback(() => {
    let deviceId = localStorage.getItem('1wallet.sync.deviceId');
    if (!deviceId) {
      deviceId = Math.random().toString(36).substring(2, 15);
      localStorage.setItem('1wallet.sync.deviceId', deviceId);
    }
    return deviceId;
  }, []);

  const getMetadata = useCallback((): CloudSyncMetadata => {
    const raw = localStorage.getItem('1wallet.sync.metadata');
    if (raw) return JSON.parse(raw);
    return { userId: user?.id ?? '', deviceId: ensureDeviceId() };
  }, [user, ensureDeviceId]);

  const persistMetadata = useCallback((newMeta: CloudSyncMetadata) => {
    localStorage.setItem('1wallet.sync.metadata', JSON.stringify(newMeta));
  }, []);

  const bootstrap = useCallback(async () => {
    if (!enabled || !user || !db || !ready) return;
    if (bootstrappedRef.current) return;

    setPhase('checking');
    try {
      const walletRef = doc(db, 'users', user.id, 'wallets', WALLET_ID);
      const snapshot = await getDoc(walletRef);
      const wallet = snapshot.exists() ? (snapshot.data() as CloudWalletDocument) : null;

      const localArchive = exportOneWalletArchive(latestStateRef.current, { source: 'web' });
      const currentMeta = getMetadata();

      if (wallet?.latestSnapshotId) {
        if (wallet.latestSnapshotChecksum !== localArchive.checksum) {
          // Restore
          setPhase('restoring');
          const chunksRef = collection(
            db,
            'users',
            user.id,
            'wallets',
            WALLET_ID,
            'snapshots',
            wallet.latestSnapshotId,
            'chunks',
          );
          const chunkDocs = await getDocs(query(chunksRef, orderBy('index')));
          const content = chunkDocs.docs.map((d) => d.data().content).join('');

          const archive = parseOneWalletArchive(content);
          const restored = ledgerStateFromOneWalletArchive(archive, { userId: user.id });
          await replaceLedgerState(restored);

          persistMetadata({
            ...currentMeta,
            userId: user.id,
            lastLocalChecksum: archive.checksum,
            lastSnapshotChecksum: archive.checksum,
            lastSnapshotPath: wallet.latestSnapshotId,
          });
        }
      }

      bootstrappedRef.current = true;
      setPhase('idle');
    } catch (err) {
      console.error(err);
      setError((err as Error).message);
      setPhase('error');
    }
  }, [enabled, user, ready, getMetadata, persistMetadata, replaceLedgerState]);

  useEffect(() => {
    if (enabled && ready && !bootstrappedRef.current) {
      bootstrap();
    }
  }, [enabled, ready, bootstrap]);

  const uploadSnapshot = useCallback(async () => {
    if (!enabled || !user || !db || !ready || !bootstrappedRef.current) return;

    try {
      setPendingUpload(false);
      setPhase('uploading');

      const stateToUpload = latestStateRef.current;
      const archive = exportOneWalletArchive(stateToUpload, { source: 'web' });
      const currentMeta = getMetadata();

      if (currentMeta.lastLocalChecksum === archive.checksum) {
        setPhase('idle');
        return;
      }

      const revision = Date.now();
      const snapshotId = `${revision}-${currentMeta.deviceId}`;
      const content = JSON.stringify(archive);

      const chunks: string[] = [];
      for (let i = 0; i < content.length; i += SNAPSHOT_CHUNK_SIZE) {
        chunks.push(content.slice(i, i + SNAPSHOT_CHUNK_SIZE));
      }

      const snapshotRef = doc(db, 'users', user.id, 'wallets', WALLET_ID, 'snapshots', snapshotId);
      const batch = writeBatch(db);

      batch.set(snapshotRef, {
        snapshotId,
        checksum: archive.checksum,
        chunks: chunks.length,
        size: content.length,
        reason: 'auto',
        ledgerStateVersion: archive.ledgerStateVersion,
        summary: archive.summary,
        writerDeviceId: currentMeta.deviceId,
        createdAt: serverTimestamp(),
      });

      chunks.forEach((chunk, index) => {
        batch.set(doc(snapshotRef, 'chunks', String(index).padStart(5, '0')), {
          index,
          content: chunk,
        });
      });

      batch.set(
        doc(db, 'users', user.id, 'wallets', WALLET_ID),
        {
          walletId: WALLET_ID,
          cloudRevision: revision,
          latestSnapshotId: snapshotId,
          latestSnapshotChecksum: archive.checksum,
          latestSnapshotChunks: chunks.length,
          latestSnapshotSize: content.length,
          ledgerStateVersion: archive.ledgerStateVersion,
          summary: archive.summary,
          lastWriterDeviceId: currentMeta.deviceId,
          updatedAt: serverTimestamp(),
        },
        { merge: true },
      );

      await batch.commit();

      persistMetadata({
        ...currentMeta,
        lastLocalChecksum: archive.checksum,
        lastSnapshotChecksum: archive.checksum,
        lastSnapshotPath: snapshotId,
        lastCloudRevision: revision,
      });

      setPhase('idle');
    } catch (err) {
      console.error(err);
      setError((err as Error).message);
      setPhase('error');
    }
  }, [enabled, user, ready, getMetadata, persistMetadata]);

  useEffect(() => {
    if (!enabled || !ready || !bootstrappedRef.current) return;

    setPendingUpload(true);
    if (uploadTimerRef.current) clearTimeout(uploadTimerRef.current);

    uploadTimerRef.current = setTimeout(() => {
      uploadSnapshot();
    }, UPLOAD_DEBOUNCE_MS);

    return () => {
      if (uploadTimerRef.current) clearTimeout(uploadTimerRef.current);
    };
  }, [state, enabled, ready, uploadSnapshot]);

  const value = useMemo(
    () => ({
      enabled,
      phase,
      error,
      pendingUpload,
    }),
    [enabled, phase, error, pendingUpload],
  );

  return <CloudSyncContext.Provider value={value}>{children}</CloudSyncContext.Provider>;
}

export function useCloudSync() {
  const value = useContext(CloudSyncContext);
  if (!value) throw new Error('useCloudSync must be used within CloudSyncProvider');
  return value;
}
