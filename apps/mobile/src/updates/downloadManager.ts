import * as FileSystem from 'expo-file-system/legacy';
import { sha256File } from './nativeInstaller';
import type { AndroidAppUpdateRelease, DownloadedUpdate, UpdateDownloadSnapshot } from './types';

const UPDATE_CACHE_DIRECTORY = `${FileSystem.cacheDirectory ?? FileSystem.documentDirectory}1wallet-updates/`;
const MIN_FREE_SPACE_BUFFER_BYTES = 50 * 1024 * 1024;

export class UpdateDownloadCancelledError extends Error {
  constructor() {
    super('Update cancelled');
    this.name = 'UpdateDownloadCancelledError';
  }
}

export class UpdateDownloadError extends Error {
  constructor(message = 'Error updating app. Please try again later.') {
    super(message);
    this.name = 'UpdateDownloadError';
  }
}

export type UpdateDownloadTask = {
  promise: Promise<DownloadedUpdate>;
  cancel: () => Promise<void>;
};

export function createApkDownloadTask(
  release: AndroidAppUpdateRelease,
  onProgress: (progress: UpdateDownloadSnapshot) => void,
): UpdateDownloadTask {
  let cancelled = false;
  let download: ReturnType<typeof FileSystem.createDownloadResumable> | null = null;
  const startedAt = Date.now();

  const promise = (async () => {
    await ensureUpdateCacheDirectory();
    await ensureEnoughStorage(release.apk.sizeBytes);
    const localUri = updateApkLocalUri(release);
    await FileSystem.deleteAsync(localUri, { idempotent: true });

    download = FileSystem.createDownloadResumable(
      release.apk.downloadUrl,
      localUri,
      {},
      ({ totalBytesWritten, totalBytesExpectedToWrite }) => {
        const bytesExpected =
          totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : release.apk.sizeBytes;
        const elapsedSeconds = Math.max(0.5, (Date.now() - startedAt) / 1000);
        const speedBytesPerSecond = totalBytesWritten / elapsedSeconds;
        const remainingBytes = Math.max(0, bytesExpected - totalBytesWritten);
        const etaSeconds =
          speedBytesPerSecond > 0 ? remainingBytes / speedBytesPerSecond : undefined;
        onProgress({
          localUri,
          bytesWritten: totalBytesWritten,
          bytesExpected,
          progress: bytesExpected > 0 ? Math.min(1, totalBytesWritten / bytesExpected) : 0,
          etaSeconds,
          speedBytesPerSecond,
        });
      },
    );

    const result = await download.downloadAsync();
    if (cancelled || !result) throw new UpdateDownloadCancelledError();
    if (result.status < 200 || result.status >= 300) {
      throw new UpdateDownloadError(`Update download failed with HTTP ${result.status}.`);
    }

    const info = await FileSystem.getInfoAsync(localUri);
    if (!info.exists) throw new UpdateDownloadError('Update file was not saved on this device.');
    if (release.apk.sizeBytes > 0 && Math.abs((info.size ?? 0) - release.apk.sizeBytes) > 1024) {
      await removeDownloadedUpdate(localUri);
      throw new UpdateDownloadError('Update file size did not match the release metadata.');
    }

    const actualHash = await sha256File(localUri);
    if (actualHash !== release.apk.sha256.toLowerCase()) {
      await removeDownloadedUpdate(localUri);
      throw new UpdateDownloadError('Update checksum did not match the release metadata.');
    }

    return {
      releaseId: release.id,
      channel: release.channel,
      versionName: release.versionName,
      versionCode: release.versionCode,
      localUri,
      fileName: release.apk.fileName,
      sizeBytes: info.size ?? release.apk.sizeBytes,
      sha256: actualHash,
      downloadedAt: new Date().toISOString(),
    };
  })();

  return {
    promise,
    cancel: async () => {
      cancelled = true;
      await download?.cancelAsync().catch(() => undefined);
      await removeDownloadedUpdate(updateApkLocalUri(release));
    },
  };
}

export async function removeDownloadedUpdate(localUri?: string | null): Promise<void> {
  if (!localUri) return;
  await FileSystem.deleteAsync(localUri, { idempotent: true }).catch(() => undefined);
}

export async function clearUpdateDownloadCache(): Promise<void> {
  await FileSystem.deleteAsync(UPDATE_CACHE_DIRECTORY, { idempotent: true }).catch(() => undefined);
}

export function updateApkLocalUri(release: AndroidAppUpdateRelease): string {
  const fileName = sanitizeFileName(release.apk.fileName || `1wallet-${release.versionName}.apk`);
  return `${UPDATE_CACHE_DIRECTORY}${release.versionCode}-${fileName}`;
}

async function ensureUpdateCacheDirectory(): Promise<void> {
  if (!UPDATE_CACHE_DIRECTORY.startsWith('file://')) {
    throw new UpdateDownloadError('Update storage is unavailable on this device.');
  }
  const info = await FileSystem.getInfoAsync(UPDATE_CACHE_DIRECTORY);
  if (!info.exists) {
    await FileSystem.makeDirectoryAsync(UPDATE_CACHE_DIRECTORY, { intermediates: true });
  }
}

async function ensureEnoughStorage(sizeBytes: number): Promise<void> {
  const freeBytes = await FileSystem.getFreeDiskStorageAsync().catch(() => null);
  if (!freeBytes) return;
  const requiredBytes = sizeBytes + MIN_FREE_SPACE_BUFFER_BYTES;
  if (freeBytes < requiredBytes) {
    throw new UpdateDownloadError('Not enough storage space to download this update.');
  }
}

function sanitizeFileName(value: string): string {
  const sanitized = value.replace(/[^a-zA-Z0-9._-]/g, '-').replace(/-+/g, '-');
  return sanitized.endsWith('.apk') ? sanitized : `${sanitized}.apk`;
}
