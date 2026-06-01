export const APP_UPDATE_PLATFORM = 'android';
export const DEFAULT_UPDATE_CHANNEL = 'stable';
export const UPDATE_METADATA_ROOT = 'appUpdates';

export type UpdateReleaseType = 'major' | 'minor' | 'patch';
export type UpdateRequirement = 'mandatory' | 'optional';
export type UpdateArtifactKind = 'apk' | 'js';

export type InstalledAppVersion = {
  versionName: string;
  versionCode: number;
  runtimeVersion: string;
  platform: typeof APP_UPDATE_PLATFORM;
};

export type UpdateChangelog = {
  newFeatures: string[];
  bugFixes: string[];
  notes: string[];
};

export type UpdateApkMetadata = {
  downloadUrl: string;
  fileName: string;
  sizeBytes: number;
  sha256: string;
  architecture: string;
  minSdk?: number;
  estimatedDownloadSeconds?: number;
};

export type AppUpdateRelease = {
  id: string;
  platform: typeof APP_UPDATE_PLATFORM;
  channel: string;
  status: 'published';
  versionName: string;
  versionCode: number;
  runtimeVersion: string;
  releaseType: UpdateReleaseType;
  requirement: UpdateRequirement;
  mandatory: boolean;
  minimumSupportedVersionCode: number;
  publishedAt: string;
  changelog: UpdateChangelog;
  apk: UpdateApkMetadata;
};

export type UpdateCheckOutcome =
  | { status: 'not-configured'; message: string }
  | { status: 'up-to-date'; checkedAt: string; current: InstalledAppVersion }
  | {
      status: 'available';
      checkedAt: string;
      current: InstalledAppVersion;
      release: AppUpdateRelease;
    }
  | { status: 'error'; checkedAt: string; current: InstalledAppVersion; message: string };

export type UpdateDownloadSnapshot = {
  localUri?: string;
  bytesWritten: number;
  bytesExpected: number;
  progress: number;
  etaSeconds?: number;
  speedBytesPerSecond?: number;
};

export type DownloadedUpdate = {
  releaseId: string;
  versionName: string;
  versionCode: number;
  localUri: string;
  fileName: string;
  sizeBytes: number;
  sha256: string;
  downloadedAt: string;
};

export type AppUpdateStatus =
  | 'idle'
  | 'checking'
  | 'up-to-date'
  | 'available'
  | 'downloading'
  | 'downloaded'
  | 'installing'
  | 'js-update-ready'
  | 'cancelled'
  | 'error';

export type JsUpdateStatus =
  | { available: false; downloaded: false; message?: string }
  | { available: true; downloaded: false; message?: string }
  | { available: true; downloaded: true; message?: string };

export type AppUpdateState = {
  status: AppUpdateStatus;
  current: InstalledAppVersion;
  release: AppUpdateRelease | null;
  downloaded: DownloadedUpdate | null;
  download: UpdateDownloadSnapshot | null;
  jsUpdate: JsUpdateStatus;
  lastCheckedAt?: string;
  message?: string;
  error?: string;
};
