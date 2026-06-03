import { doc, getDoc, type DocumentData, type Firestore } from 'firebase/firestore';
import { getFirebaseServices } from '../firebase/client';
import {
  APP_UPDATE_PLATFORM,
  DEFAULT_UPDATE_CHANNEL,
  UPDATE_METADATA_ROOT,
  isUpdateChannel,
  type AppUpdateRelease,
  type UpdateApkMetadata,
  type InstalledAppVersion,
  type UpdateChangelog,
  type UpdateChannel,
  type UpdateCheckOutcome,
  type UpdateIosMetadata,
  type UpdateReleaseType,
} from './types';
import { inferReleaseType, isReleaseNewerThanInstalled } from './version';

export async function checkForAppUpdate(
  current: InstalledAppVersion,
  channel: UpdateChannel = DEFAULT_UPDATE_CHANNEL,
): Promise<UpdateCheckOutcome> {
  const checkedAt = new Date().toISOString();
  try {
    const release = await fetchLatestPublishedRelease(channel);
    if (!release) {
      return { status: 'up-to-date', checkedAt, current };
    }
    if (!isReleaseNewerThanInstalled(release, current)) {
      return release.versionCode < current.versionCode
        ? { status: 'ahead-of-channel', checkedAt, current, release }
        : { status: 'up-to-date', checkedAt, current };
    }
    return { status: 'available', checkedAt, current, release };
  } catch (error) {
    if (isPermissionDeniedError(error)) {
      return { status: 'not-configured', message: 'Update channel is not published yet.' };
    }
    return {
      status: 'error',
      checkedAt,
      current,
      message: updateErrorMessage(error),
    };
  }
}

export async function checkForAndroidUpdate(
  current: InstalledAppVersion,
  channel: UpdateChannel = DEFAULT_UPDATE_CHANNEL,
): Promise<UpdateCheckOutcome> {
  return checkForAppUpdate(current, channel);
}

export async function fetchLatestPublishedRelease(
  channel: UpdateChannel = DEFAULT_UPDATE_CHANNEL,
): Promise<AppUpdateRelease | null> {
  const db = getUpdateFirestore();
  return fetchChannelRelease(db, channel);
}

export async function fetchLatestPublishedAndroidRelease(
  channel: UpdateChannel = DEFAULT_UPDATE_CHANNEL,
): Promise<AppUpdateRelease | null> {
  return fetchLatestPublishedRelease(channel);
}

export async function fetchPublishedReleaseByCode(
  versionCode: number,
): Promise<AppUpdateRelease | null> {
  if (!Number.isInteger(versionCode) || versionCode <= 0) return null;
  const db = getUpdateFirestore();
  const releaseRef = doc(
    db,
    UPDATE_METADATA_ROOT,
    APP_UPDATE_PLATFORM,
    'releases',
    String(versionCode),
  );
  const releaseSnapshot = await getDoc(releaseRef);
  if (!releaseSnapshot.exists()) return null;
  return parseReleaseDocument(releaseSnapshot.id, releaseSnapshot.data());
}

export async function fetchPublishedAndroidReleaseByCode(
  versionCode: number,
): Promise<AppUpdateRelease | null> {
  return fetchPublishedReleaseByCode(versionCode);
}

function getUpdateFirestore(): Firestore {
  let services;
  try {
    services = getFirebaseServices();
  } catch (error) {
    throw new Error(updateErrorMessage(error));
  }
  if (!services) throw new Error('Firebase is not configured for update checks.');
  return services.db;
}

async function fetchChannelRelease(db: Firestore, channel: UpdateChannel) {
  const channelRef = doc(db, UPDATE_METADATA_ROOT, APP_UPDATE_PLATFORM, 'channels', channel);
  const channelSnapshot = await getDoc(channelRef);
  if (!channelSnapshot.exists()) return null;

  const data = channelSnapshot.data();
  if (stringValue(data.status) !== 'published') return null;
  const latestVersionCode = numberValue(data.latestVersionCode);
  if (!latestVersionCode) return null;

  const releaseRef = doc(
    db,
    UPDATE_METADATA_ROOT,
    APP_UPDATE_PLATFORM,
    'releases',
    String(latestVersionCode),
  );
  const releaseSnapshot = await getDoc(releaseRef);
  if (!releaseSnapshot.exists()) return null;
  const release = parseReleaseDocument(releaseSnapshot.id, releaseSnapshot.data());
  return release?.channel === channel ? release : null;
}

function parseReleaseDocument(id: string, data: DocumentData): AppUpdateRelease | null {
  const versionName = stringValue(data.versionName);
  const versionCode = numberValue(data.versionCode);
  if (!versionName || !versionCode) return null;

  const status = stringValue(data.status);
  if (status !== 'published') return null;

  const platform = stringValue(data.platform) ?? APP_UPDATE_PLATFORM;
  if (platform !== APP_UPDATE_PLATFORM) return null;
  if (platform !== 'android' && platform !== 'ios') return null;

  const channel = updateChannelValue(data.channel) ?? DEFAULT_UPDATE_CHANNEL;
  const runtimeVersion = stringValue(data.runtimeVersion) ?? versionName;
  const mandatory = booleanValue(data.mandatory) ?? stringValue(data.requirement) === 'mandatory';
  const releaseType = releaseTypeValue(data.releaseType) ?? inferReleaseType('0.0.0', versionName);
  const minimumSupportedVersionCode = numberValue(data.minimumSupportedVersionCode) ?? 0;
  const publishedAt = timestampValue(data.publishedAt) ?? new Date().toISOString();
  const requirement = mandatory ? ('mandatory' as const) : ('optional' as const);

  const base = {
    id,
    platform,
    channel,
    status: 'published' as const,
    versionName,
    versionCode,
    runtimeVersion,
    releaseType,
    requirement,
    mandatory,
    minimumSupportedVersionCode,
    publishedAt,
    changelog: parseChangelog(data.changelog),
  };

  if (platform === 'android') {
    const apk = parseApkMetadata(data.apk);
    if (!apk) return null;
    return { ...base, platform: 'android', apk };
  }

  const ios = parseIosMetadata(data.ios);
  if (!ios) return null;
  return { ...base, platform: 'ios', ios };
}

function updateChannelValue(value: unknown): UpdateChannel | null {
  return isUpdateChannel(value) ? value : null;
}

function parseApkMetadata(value: unknown): UpdateApkMetadata | null {
  if (!isRecord(value)) return null;
  const downloadUrl = stringValue(value.downloadUrl);
  const fileName = stringValue(value.fileName) ?? '1wallet-update.apk';
  const sizeBytes = numberValue(value.sizeBytes);
  const sha256 = normalizeSha256(stringValue(value.sha256));
  const architecture = stringValue(value.architecture) ?? 'universal';
  if (!downloadUrl || !isHttpUrl(downloadUrl) || !sizeBytes || !sha256) return null;

  return {
    downloadUrl,
    fileName,
    sizeBytes,
    sha256,
    architecture,
    minSdk: numberValue(value.minSdk) ?? undefined,
    estimatedDownloadSeconds: numberValue(value.estimatedDownloadSeconds) ?? undefined,
  };
}

function parseIosMetadata(value: unknown): UpdateIosMetadata | null {
  if (!isRecord(value)) return null;
  const appStoreUrl = stringValue(value.appStoreUrl) ?? undefined;
  const testFlightUrl = stringValue(value.testFlightUrl) ?? undefined;
  const buildUrl = stringValue(value.buildUrl) ?? undefined;
  if (![appStoreUrl, testFlightUrl, buildUrl].some((url) => url && isHttpUrl(url))) return null;

  return {
    appStoreUrl: appStoreUrl && isHttpUrl(appStoreUrl) ? appStoreUrl : undefined,
    testFlightUrl: testFlightUrl && isHttpUrl(testFlightUrl) ? testFlightUrl : undefined,
    buildUrl: buildUrl && isHttpUrl(buildUrl) ? buildUrl : undefined,
    appStoreId: stringValue(value.appStoreId) ?? undefined,
    bundleIdentifier: stringValue(value.bundleIdentifier) ?? undefined,
    minimumOsVersion: stringValue(value.minimumOsVersion) ?? undefined,
  };
}

function parseChangelog(value: unknown): UpdateChangelog {
  if (!isRecord(value)) return { newFeatures: [], bugFixes: [], notes: [] };
  return {
    newFeatures: stringList(value.newFeatures),
    bugFixes: stringList(value.bugFixes),
    notes: stringList(value.notes),
  };
}

function updateErrorMessage(error: unknown): string {
  if (error instanceof Error && error.message.trim()) return error.message;
  return 'Error updating app. Please try again later.';
}

function isPermissionDeniedError(error: unknown): boolean {
  if (!isRecord(error)) return false;
  return (
    error.code === 'permission-denied' || error.message === 'Missing or insufficient permissions.'
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function stringValue(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function numberValue(value: unknown): number | null {
  const parsed =
    typeof value === 'number' ? value : typeof value === 'string' ? Number(value) : NaN;
  return Number.isFinite(parsed) && parsed > 0 ? Math.trunc(parsed) : null;
}

function booleanValue(value: unknown): boolean | null {
  return typeof value === 'boolean' ? value : null;
}

function stringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => (typeof item === 'string' ? item.trim() : ''))
    .filter((item) => item.length > 0)
    .slice(0, 20);
}

function releaseTypeValue(value: unknown): UpdateReleaseType | null {
  return value === 'major' || value === 'minor' || value === 'patch' ? value : null;
}

function timestampValue(value: unknown): string | null {
  if (typeof value === 'string' && value.trim()) return value.trim();
  if (isRecord(value) && typeof value.toDate === 'function') {
    const date = value.toDate() as Date;
    return Number.isNaN(date.getTime()) ? null : date.toISOString();
  }
  return null;
}

function normalizeSha256(value: string | null): string | null {
  if (!value) return null;
  const normalized = value.replace(/^sha256:/i, '').toLowerCase();
  return /^[0-9a-f]{64}$/.test(normalized) ? normalized : null;
}

function isHttpUrl(value: string): boolean {
  return /^https?:\/\//i.test(value);
}
