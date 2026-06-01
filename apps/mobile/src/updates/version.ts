import Constants from 'expo-constants';
import { Platform } from 'react-native';
import {
    APP_UPDATE_PLATFORM,
    type AppUpdateRelease,
    type InstalledAppVersion,
    type UpdateReleaseType,
} from './types';

const FALLBACK_VERSION_NAME = '1.2.0';
const FALLBACK_VERSION_CODE = 1020000;
const FALLBACK_RUNTIME_VERSION = '1.2.0';

type Semver = {
  major: number;
  minor: number;
  patch: number;
};

export function getInstalledAppVersion(): InstalledAppVersion {
  const nativeVersion = normalizeVersionName(Constants.nativeAppVersion);
  const configVersion = normalizeVersionName(Constants.expoConfig?.version);
  const versionName = nativeVersion ?? configVersion ?? FALLBACK_VERSION_NAME;
  const nativeBuildVersion = parseVersionCode(Constants.nativeBuildVersion);
  const versionCode =
    nativeBuildVersion ?? semverToVersionCode(versionName) ?? FALLBACK_VERSION_CODE;
  const runtimeVersion = runtimeVersionFromConstants() ?? versionName ?? FALLBACK_RUNTIME_VERSION;

  return {
    versionName,
    versionCode,
    runtimeVersion,
    platform: APP_UPDATE_PLATFORM,
  };
}

export function parseSemver(input: string | null | undefined): Semver | null {
  if (!input) return null;
  const match = input.trim().match(/^(\d+)\.(\d+)\.(\d+)(?:[-+][0-9A-Za-z.-]+)?$/);
  if (!match) return null;
  const major = Number(match[1]);
  const minor = Number(match[2]);
  const patch = Number(match[3]);
  if (![major, minor, patch].every((value) => Number.isInteger(value) && value >= 0)) return null;
  return { major, minor, patch };
}

export function compareSemver(left: string, right: string): number {
  const leftSemver = parseSemver(left);
  const rightSemver = parseSemver(right);
  if (!leftSemver || !rightSemver) return left.localeCompare(right);
  return (
    compareNumber(leftSemver.major, rightSemver.major) ||
    compareNumber(leftSemver.minor, rightSemver.minor) ||
    compareNumber(leftSemver.patch, rightSemver.patch)
  );
}

export function semverToVersionCode(versionName: string | null | undefined): number | null {
  const semver = parseSemver(versionName);
  if (!semver) return null;
  return semver.major * 1000000 + semver.minor * 10000 + semver.patch * 100;
}

export function inferReleaseType(currentVersion: string, nextVersion: string): UpdateReleaseType {
  const current = parseSemver(currentVersion);
  const next = parseSemver(nextVersion);
  if (!current || !next) return 'patch';
  if (next.major > current.major) return 'major';
  if (next.minor > current.minor) return 'minor';
  return 'patch';
}

export function isReleaseNewerThanInstalled(
  release: AppUpdateRelease,
  installed: InstalledAppVersion,
): boolean {
  if (release.versionCode !== installed.versionCode)
    return release.versionCode > installed.versionCode;
  return compareSemver(release.versionName, installed.versionName) > 0;
}

export function isReleaseRuntimeCompatible(
  release: AppUpdateRelease,
  installed: InstalledAppVersion,
): boolean {
  return !release.runtimeVersion || release.runtimeVersion === installed.runtimeVersion;
}

export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return 'Unknown';
  const units = ['B', 'KB', 'MB', 'GB'];
  let value = bytes;
  let unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  const decimals = unitIndex === 0 || value >= 100 ? 0 : 1;
  return `${value.toFixed(decimals)} ${units[unitIndex]}`;
}

export function formatEta(seconds: number | null | undefined): string {
  if (!seconds || !Number.isFinite(seconds) || seconds <= 0) return 'Estimating';
  if (seconds < 60) return `${Math.max(1, Math.round(seconds))} sec`;
  const minutes = Math.floor(seconds / 60);
  const remainingSeconds = Math.round(seconds % 60);
  if (minutes < 60)
    return remainingSeconds > 0 ? `${minutes} min ${remainingSeconds} sec` : `${minutes} min`;
  const hours = Math.floor(minutes / 60);
  const remainingMinutes = minutes % 60;
  return remainingMinutes > 0 ? `${hours} hr ${remainingMinutes} min` : `${hours} hr`;
}

export function formatReleaseType(type: UpdateReleaseType): string {
  switch (type) {
    case 'major':
      return 'Major update';
    case 'minor':
      return 'Minor update';
    case 'patch':
      return 'Patch update';
  }
}

export function progressPercent(progress: number | null | undefined): string {
  if (!Number.isFinite(progress ?? NaN)) return '0%';
  return `${Math.max(0, Math.min(100, Math.round((progress ?? 0) * 100)))}%`;
}

function normalizeVersionName(value: string | null | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

function parseVersionCode(value: string | null | undefined): number | null {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

function runtimeVersionFromConstants(): string | null {
  const expoRuntimeVersion = Constants.expoConfig?.runtimeVersion;
  if (typeof expoRuntimeVersion === 'string' && expoRuntimeVersion.trim()) {
    return expoRuntimeVersion.trim();
  }
  if (Platform.OS === 'android' || Platform.OS === 'ios') {
    return (
      normalizeVersionName(Constants.nativeAppVersion) ??
      normalizeVersionName(Constants.expoConfig?.version)
    );
  }
  return FALLBACK_RUNTIME_VERSION;
}

function compareNumber(left: number, right: number): number {
  if (left === right) return 0;
  return left > right ? 1 : -1;
}
