import { createHash } from 'node:crypto';
import { existsSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = parseArgs(process.argv.slice(2));
const apk = requiredPath(args.apk, '--apk');
const versionName = requiredValue(args.version, '--version');
const versionCode = numberValue(
  args['version-code'] ?? versionCodeFromSemver(versionName),
  '--version-code',
);
const downloadUrl = requiredValue(args.url, '--url');
const channel = args.channel ?? 'stable';
const releaseType = args['release-type'] ?? inferReleaseType(versionName);
const mandatory = args.mandatory === 'true';
const runtimeVersion = args.runtime ?? versionName;
const minimumSupportedVersionCode = Number(args['minimum-supported-version-code'] ?? 0);
const architecture = args.architecture ?? 'arm64-v8a';
const publishedAt = args['published-at'] ?? new Date().toISOString();
const fileName = args['file-name'] ?? apk.split(/[\\/]/).pop() ?? '1wallet-update.apk';
const outputPath = args.output ? resolve(repoRoot, args.output) : null;
const changelog = args['changelog-json'] ? readChangelogFile(args['changelog-json']) : null;
const releasePath = `appUpdates/android/releases/${versionCode}`;
const channelPath = `appUpdates/android/channels/${channel}`;

if (!['major', 'minor', 'patch'].includes(releaseType)) {
  throw new Error('--release-type must be one of major, minor, patch.');
}
if (!['stable', 'beta'].includes(channel)) {
  throw new Error('--channel must be one of stable, beta.');
}
if (!Number.isInteger(minimumSupportedVersionCode) || minimumSupportedVersionCode < 0) {
  throw new Error('--minimum-supported-version-code must be a non-negative integer.');
}

const sizeBytes = statSync(apk).size;
const sha256 = createHash('sha256').update(readFileSync(apk)).digest('hex');
const release = {
  platform: 'android',
  channel,
  status: 'published',
  versionName,
  versionCode,
  runtimeVersion,
  releaseType,
  mandatory,
  requirement: mandatory ? 'mandatory' : 'optional',
  minimumSupportedVersionCode,
  publishedAt,
  changelog: {
    newFeatures: [...(changelog?.newFeatures ?? []), ...listValues(args.feature)],
    bugFixes: [...(changelog?.bugFixes ?? []), ...listValues(args.fix)],
    notes: [...(changelog?.notes ?? []), ...listValues(args.note)],
  },
  apk: {
    downloadUrl,
    fileName,
    sizeBytes,
    sha256,
    architecture,
    minSdk: Number(args['min-sdk'] ?? 24),
    estimatedDownloadSeconds: args.eta ? Number(args.eta) : undefined,
  },
};
const releaseFeed = buildReleaseFeed(release, releasePath);
const manifest = {
  releasePath,
  release,
  channelPath,
  channel: {
    platform: 'android',
    channel,
    status: 'published',
    latestVersionCode: versionCode,
    updatedAt: publishedAt,
  },
  releaseFeedPath: releaseFeed.path,
  releaseFeed: releaseFeed.data,
};

const json = `${JSON.stringify(manifest, null, 2)}\n`;
if (outputPath) {
  writeFileSync(outputPath, json);
  console.log(`Wrote ${relative(outputPath)}`);
} else {
  process.stdout.write(json);
}

function parseArgs(values) {
  const result = {};
  for (let index = 0; index < values.length; index += 1) {
    const raw = values[index];
    if (!raw?.startsWith('--')) continue;
    const key = raw.slice(2);
    const next = values[index + 1];
    if (next === undefined || next.startsWith('--')) {
      result[key] = 'true';
      continue;
    }
    if (result[key] === undefined) {
      result[key] = next;
    } else if (Array.isArray(result[key])) {
      result[key].push(next);
    } else {
      result[key] = [result[key], next];
    }
    index += 1;
  }
  return result;
}

function requiredPath(value, label) {
  const raw = requiredValue(value, label);
  const filePath = resolve(repoRoot, raw);
  if (!existsSync(filePath)) throw new Error(`${label} does not exist: ${raw}`);
  return filePath;
}

function requiredValue(value, label) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new Error(`${label} is required.`);
  }
  return value.trim();
}

function numberValue(value, label) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0)
    throw new Error(`${label} must be a positive integer.`);
  return parsed;
}

function versionCodeFromSemver(version) {
  const match = /^(\d+)\.(\d+)\.(\d+)/.exec(version);
  if (!match) return undefined;
  return Number(match[1]) * 1000000 + Number(match[2]) * 10000 + Number(match[3]) * 100;
}

function inferReleaseType(version) {
  const match = /^(\d+)\.(\d+)\.(\d+)/.exec(version);
  if (!match) return 'patch';
  if (Number(match[3]) > 0) return 'patch';
  if (Number(match[2]) > 0) return 'minor';
  return 'major';
}

function listValues(value) {
  if (Array.isArray(value))
    return value
      .map(String)
      .flatMap(splitLines)
      .map((item) => item.trim())
      .map(stripBullet)
      .filter(Boolean);
  if (typeof value === 'string' && value.trim())
    return splitLines(value)
      .map((item) => item.trim())
      .map(stripBullet)
      .filter(Boolean);
  return [];
}

function buildReleaseFeed(release, releasePath) {
  const id = releaseFeedId(release.versionCode, release.channel, release.versionName);
  return {
    path: `appUpdates/android/releaseFeed/${id}`,
    data: {
      platform: release.platform,
      channel: release.channel,
      status: release.status,
      versionName: release.versionName,
      versionCode: release.versionCode,
      releasePath,
      publishedAt: release.publishedAt,
      title: `1Wallet Android ${release.versionName} ${release.channel === 'beta' ? 'Beta' : 'Stable'} (${release.versionCode})`,
    },
  };
}

function releaseFeedId(versionCode, channel, versionName) {
  const maxVersionCode = 999999999;
  const parsedVersionCode = numberValue(versionCode, 'release feed versionCode');
  if (parsedVersionCode >= maxVersionCode) {
    throw new Error('release feed versionCode is too high for descending sort key.');
  }
  const sortKey = String(maxVersionCode - parsedVersionCode).padStart(9, '0');
  return `${sortKey}-${parsedVersionCode}-${safeDocIdPart(channel)}-${safeDocIdPart(versionName)}`;
}

function safeDocIdPart(value) {
  return String(value ?? 'unknown')
    .replace(/[^A-Za-z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80);
}

function readChangelogFile(value) {
  const filePath = requiredPath(value, '--changelog-json');
  const raw = JSON.parse(readFileSync(filePath, 'utf8'));
  return {
    newFeatures: listValues(raw.newFeatures),
    bugFixes: listValues(raw.bugFixes),
    notes: listValues(raw.notes),
  };
}

function splitLines(value) {
  return String(value)
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
}

function stripBullet(value) {
  return value
    .replace(/^[-*]\s+/, '')
    .replace(/^- \[[ xX]\]\s+/, '')
    .trim();
}

function relative(filePath) {
  return filePath.startsWith(repoRoot) ? filePath.slice(repoRoot.length + 1) : filePath;
}
