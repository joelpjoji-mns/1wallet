import type { OneWalletArchiveV1 } from '@1wallet/ledger/archive/onewallet';
import { uid } from '@1wallet/ledger/id';
import * as FileSystem from 'expo-file-system/legacy';

const SYNC_METADATA_VERSION = 1;
const SYNC_DIRECTORY = `${FileSystem.documentDirectory ?? FileSystem.cacheDirectory}1wallet-sync/`;
const SYNC_METADATA_FILE = `${SYNC_DIRECTORY}metadata.json`;
const SYNC_RESTORE_BACKUP_DIRECTORY = `${SYNC_DIRECTORY}pre-restore-backups/`;

export type CloudSyncMetadata = {
  version: typeof SYNC_METADATA_VERSION;
  deviceId: string;
  userId?: string;
  lastCloudRevision?: number;
  lastLocalChecksum?: string;
  lastSnapshotChecksum?: string;
  lastSnapshotPath?: string;
  lastPushedAt?: string;
  lastPulledAt?: string;
  lastRestoreBackupUri?: string;
};

export async function loadCloudSyncMetadata(): Promise<CloudSyncMetadata> {
  await ensureDirectory(SYNC_DIRECTORY);
  const info = await FileSystem.getInfoAsync(SYNC_METADATA_FILE);
  if (!info.exists) return createDefaultMetadata();

  try {
    const parsed = JSON.parse(
      await FileSystem.readAsStringAsync(SYNC_METADATA_FILE),
    ) as Partial<CloudSyncMetadata>;
    return normalizeMetadata(parsed);
  } catch {
    return createDefaultMetadata();
  }
}

export async function saveCloudSyncMetadata(metadata: CloudSyncMetadata): Promise<void> {
  await ensureDirectory(SYNC_DIRECTORY);
  await FileSystem.writeAsStringAsync(
    SYNC_METADATA_FILE,
    JSON.stringify(normalizeMetadata(metadata)),
  );
}

export async function savePreRestoreLedgerBackup(
  userId: string,
  archive: OneWalletArchiveV1,
): Promise<string> {
  await ensureDirectory(SYNC_RESTORE_BACKUP_DIRECTORY);
  const safeUserId = userId.replace(/[^a-zA-Z0-9_-]/g, '_');
  const fileUri = `${SYNC_RESTORE_BACKUP_DIRECTORY}${safeUserId}-${Date.now()}.onewallet.json`;
  await FileSystem.writeAsStringAsync(fileUri, JSON.stringify(archive));
  return fileUri;
}

export async function clearCloudSyncLocalState(): Promise<void> {
  await FileSystem.deleteAsync(SYNC_DIRECTORY, { idempotent: true });
}

function createDefaultMetadata(): CloudSyncMetadata {
  return { version: SYNC_METADATA_VERSION, deviceId: uid() };
}

function normalizeMetadata(value: Partial<CloudSyncMetadata>): CloudSyncMetadata {
  return {
    version: SYNC_METADATA_VERSION,
    deviceId: typeof value.deviceId === 'string' && value.deviceId ? value.deviceId : uid(),
    userId: stringValue(value.userId),
    lastCloudRevision: numberValue(value.lastCloudRevision),
    lastLocalChecksum: stringValue(value.lastLocalChecksum),
    lastSnapshotChecksum: stringValue(value.lastSnapshotChecksum),
    lastSnapshotPath: stringValue(value.lastSnapshotPath),
    lastPushedAt: stringValue(value.lastPushedAt),
    lastPulledAt: stringValue(value.lastPulledAt),
    lastRestoreBackupUri: stringValue(value.lastRestoreBackupUri),
  };
}

function stringValue(value: unknown): string | undefined {
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

function numberValue(value: unknown): number | undefined {
  return typeof value === 'number' && Number.isFinite(value) ? value : undefined;
}

async function ensureDirectory(uri: string): Promise<void> {
  if (!uri.startsWith('file://')) throw new Error('Wallet sync storage is unavailable.');
  const info = await FileSystem.getInfoAsync(uri);
  if (!info.exists) await FileSystem.makeDirectoryAsync(uri, { intermediates: true });
}
