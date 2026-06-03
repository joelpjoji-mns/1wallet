import { Platform } from 'react-native';

export type AppUpdatePlatform = 'android' | 'ios';
export const APP_UPDATE_PLATFORM: AppUpdatePlatform = Platform.OS === 'ios' ? 'ios' : 'android';
export const UPDATE_CHANNELS = ['stable', 'beta'] as const;
export type UpdateChannel = (typeof UPDATE_CHANNELS)[number];
export const DEFAULT_UPDATE_CHANNEL: UpdateChannel = 'stable';
export const UPDATE_METADATA_ROOT = 'appUpdates';

export type UpdateReleaseType = 'major' | 'minor' | 'patch';
export type UpdateRequirement = 'mandatory' | 'optional';
export type UpdateArtifactKind = 'apk' | 'app-store' | 'js';

export type InstalledAppVersion = {
  versionName: string;
  versionCode: number;
  runtimeVersion: string;
  platform: AppUpdatePlatform;
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

export type UpdateIosMetadata = {
  appStoreUrl?: string;
  testFlightUrl?: string;
  buildUrl?: string;
  appStoreId?: string;
  bundleIdentifier?: string;
  minimumOsVersion?: string;
};

export type AppUpdateReleaseBase = {
  id: string;
  platform: AppUpdatePlatform;
  channel: UpdateChannel;
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
};

export type AndroidAppUpdateRelease = AppUpdateReleaseBase & {
  platform: 'android';
  apk: UpdateApkMetadata;
};

export type IosAppUpdateRelease = AppUpdateReleaseBase & {
  platform: 'ios';
  ios: UpdateIosMetadata;
};

export type AppUpdateRelease = AndroidAppUpdateRelease | IosAppUpdateRelease;

export type UpdateCheckOutcome =
  | { status: 'not-configured'; message: string }
  | { status: 'up-to-date'; checkedAt: string; current: InstalledAppVersion }
  | {
      status: 'ahead-of-channel';
      checkedAt: string;
      current: InstalledAppVersion;
      release: AppUpdateRelease;
    }
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
  channel: UpdateChannel;
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
  | 'ahead-of-channel'
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
  channel: UpdateChannel;
  current: InstalledAppVersion;
  installedRelease: AppUpdateRelease | null;
  release: AppUpdateRelease | null;
  downloaded: DownloadedUpdate | null;
  download: UpdateDownloadSnapshot | null;
  jsUpdate: JsUpdateStatus;
  lastCheckedAt?: string;
  message?: string;
  error?: string;
};

export function isUpdateChannel(value: unknown): value is UpdateChannel {
  return typeof value === 'string' && UPDATE_CHANNELS.includes(value as UpdateChannel);
}
