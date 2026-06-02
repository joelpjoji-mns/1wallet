import type { OneWalletArchiveV1 } from '@1wallet/ledger/archive/onewallet';
import { uid } from '@1wallet/ledger/id';
import * as FileSystem from 'expo-file-system/legacy';

const SYNC_METADATA_VERSION = 1;
const SYNC_DIRECTORY = `${FileSystem.documentDirectory ?? FileSystem.cacheDirectory}1wallet-sync/`;
const SYNC_METADATA_FILE = `${SYNC_DIRECTORY}metadata.json`;
const SYNC_RESTORE_BACKUP_DIRECTORY = `${SYNC_DIRECTORY}pre-restore-backups/`;
const RESTORE_BACKUPS_TO_KEEP = 1;

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

export type CloudSyncStorageMaintenanceResult = {
  removedBytes: number;
  removedFiles: number;
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
  await prunePreRestoreBackups({ userId }).catch(() => undefined);
  const safeUserId = userId.replace(/[^a-zA-Z0-9_-]/g, '_');
  const fileUri = `${SYNC_RESTORE_BACKUP_DIRECTORY}${safeUserId}-${Date.now()}.onewallet.json`;
  await FileSystem.writeAsStringAsync(fileUri, JSON.stringify(archive));
  await prunePreRestoreBackups({ keepUri: fileUri, userId }).catch(() => undefined);
  return fileUri;
}

export async function clearCloudSyncLocalState(): Promise<void> {
  await FileSystem.deleteAsync(SYNC_DIRECTORY, { idempotent: true });
}

export async function compactCloudSyncStorage(): Promise<CloudSyncStorageMaintenanceResult> {
  const metadata = await loadCloudSyncMetadata().catch(() => null);
  return prunePreRestoreBackups({ keepUri: metadata?.lastRestoreBackupUri });
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

async function prunePreRestoreBackups({
  keepUri,
  userId,
}: {
  keepUri?: string;
  userId?: string;
} = {}): Promise<CloudSyncStorageMaintenanceResult> {
  const directoryInfo = await FileSystem.getInfoAsync(SYNC_RESTORE_BACKUP_DIRECTORY);
  if (!directoryInfo.exists) return { removedBytes: 0, removedFiles: 0 };

  const safeUserId = userId?.replace(/[^a-zA-Z0-9_-]/g, '_');
  const entries = await FileSystem.readDirectoryAsync(SYNC_RESTORE_BACKUP_DIRECTORY);
  const backups = await Promise.all(
    entries
      .filter((name) => name.endsWith('.onewallet.json'))
      .filter((name) => !safeUserId || name.startsWith(`${safeUserId}-`))
      .map(async (name) => {
        const uri = `${SYNC_RESTORE_BACKUP_DIRECTORY}${name}`;
        const info = await FileSystem.getInfoAsync(uri).catch(() => null);
        return {
          name,
          uri,
          modifiedAt: info?.exists
            ? ((info as { modificationTime?: number }).modificationTime ?? 0)
            : 0,
          size: info?.exists ? ((info as { size?: number }).size ?? 0) : 0,
        };
      }),
  );

  const keep = new Set<string>();
  if (keepUri) keep.add(keepUri);
  backups
    .filter((backup) => !keep.has(backup.uri))
    .sort((left, right) => right.modifiedAt - left.modifiedAt)
    .slice(0, RESTORE_BACKUPS_TO_KEEP)
    .forEach((backup) => keep.add(backup.uri));

  let removedBytes = 0;
  let removedFiles = 0;
  for (const backup of backups) {
    if (keep.has(backup.uri)) continue;
    await FileSystem.deleteAsync(backup.uri, { idempotent: true }).catch(() => undefined);
    removedBytes += backup.size;
    removedFiles += 1;
  }
  return { removedBytes, removedFiles };
}
