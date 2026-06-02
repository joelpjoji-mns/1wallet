import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = parseArgs(process.argv.slice(2));

if (args['self-test']) {
  runSelfTest();
  process.stdout.write('mobile-release-info self-test passed\n');
  process.exit(0);
}

const appConfig = JSON.parse(readFileSync(resolve(repoRoot, 'apps/mobile/app.json'), 'utf8'));
const buildGradle = readFileSync(resolve(repoRoot, 'apps/mobile/android/app/build.gradle'), 'utf8');
const channel = normalizeChannel(args.channel ?? process.env.ONEWALLET_UPDATE_CHANNEL ?? 'stable');
const sourceVersionName = appConfig.expo?.version;
const sourceVersionCode = readVersionCode(buildGradle) ?? versionCodeFromSemver(sourceVersionName);
const explicitVersionName = args['version-name'] ?? process.env.ONEWALLET_VERSION_NAME;
const explicitVersionCode = args['version-code'] ?? process.env.ONEWALLET_VERSION_CODE;
const versionName = explicitVersionName ?? deriveVersionName(sourceVersionName, channel);
const versionCode = explicitVersionCode
  ? normalizeVersionCode(explicitVersionCode, '--version-code')
  : deriveVersionCode(sourceVersionCode, versionName);

if (!sourceVersionName) throw new Error('Could not read expo.version from apps/mobile/app.json.');
if (!versionName) throw new Error('Could not determine Android versionName.');
if (!versionCode) throw new Error('Could not determine Android versionCode.');
if (channel === 'beta') assertBetaVersion(versionName, versionCode);
if (channel === 'stable') assertStableVersion(versionName, versionCode);

const releaseLabel = releaseDisplayLabel(versionName, channel);
const assetLabel = releaseAssetLabel(versionName, channel);

const info = {
  versionName,
  versionCode: String(versionCode),
  channel,
  tag: `android-${channel}-v${versionName}-${versionCode}`,
  releaseTitle: `1Wallet Android ${releaseLabel} (${versionCode})`,
  prerelease: String(channel === 'beta'),
  latest: String(channel === 'stable'),
  apkFileName: `1wallet-${assetLabel}-arm64-v8a.apk`,
  manifestFileName: `1wallet-${assetLabel}-update-manifest.json`,
};

if (args.output) {
  const lines = Object.entries(info).map(([key, value]) => `${key}=${value}`);
  await appendFile(args.output, `${lines.join('\n')}\n`);
} else {
  process.stdout.write(`${JSON.stringify(info, null, 2)}\n`);
}

function readVersionCode(value) {
  const line = value.split(/\r?\n/).find((item) => item.includes('appVersionCode')) ?? '';
  const match = /'([0-9]+)'/.exec(line);
  return match ? Number(match[1]) : null;
}

function versionCodeFromSemver(version) {
  const match = /^(\d+)\.(\d+)\.(\d+)/.exec(version ?? '');
  if (!match) return null;
  return Number(match[1]) * 1000000 + Number(match[2]) * 10000 + Number(match[3]) * 100;
}

function semverFromVersion(version) {
  const match = /^(\d+)\.(\d+)\.(\d+)/.exec(version ?? '');
  if (!match) return null;
  return {
    major: Number(match[1]),
    minor: Number(match[2]),
    patch: Number(match[3]),
  };
}

function deriveVersionName(sourceVersionName, channel) {
  if (!sourceVersionName) return null;
  if (channel === 'stable') return sourceVersionName;
  if (sourceVersionName.includes('-')) return sourceVersionName;
  return `${sourceVersionName}-beta`;
}

function deriveVersionCode(sourceVersionCode, versionName) {
  return versionCodeFromSemver(versionName) ?? sourceVersionCode ?? null;
}

function assertStableVersion(versionName, versionCode) {
  if (versionName.includes('-')) {
    throw new Error(`Stable releases must use a plain semantic version, not ${versionName}.`);
  }
  const semver = semverFromVersion(versionName);
  if (!semver) throw new Error(`Could not parse semantic version: ${versionName}.`);
  if (semver.patch !== 0 && versionCode !== 1040100) {
    throw new Error(
      `Planned stable releases must end in .0. Use ${semver.major}.${semver.minor + 1}.0 for the next stable release instead of ${versionName}.`,
    );
  }
}

function assertBetaVersion(versionName, versionCode) {
  const semver = semverFromVersion(versionName);
  if (!semver) throw new Error(`Could not parse semantic version: ${versionName}.`);
  if (!/-beta$/.test(versionName)) {
    throw new Error(`Beta releases must use the form 1.4.2-beta, not ${versionName}.`);
  }
  if (semver.patch === 0) {
    throw new Error(
      `Beta releases must target a patch version greater than 0. Use ${semver.major}.${semver.minor}.1-beta or later instead of ${semver.major}.${semver.minor}.0-beta.`,
    );
  }
  if (versionCode < 1040200) {
    throw new Error(
      'The next beta must be 1.4.2-beta / 1040200 or later because stable 1.4.1 / 1040100 is already published.',
    );
  }
}

function releaseDisplayLabel(versionName, channel) {
  if (channel === 'beta') return `${versionName.replace(/-beta$/, '')} Beta`;
  return `${versionName} Stable`;
}

function releaseAssetLabel(versionName, channel) {
  if (channel === 'beta' && /-beta$/.test(versionName)) return versionName;
  return `${versionName}-${channel}`;
}

function runSelfTest() {
  const rescueVersionName = deriveVersionName('1.4.1', 'stable');
  const rescueVersionCode = deriveVersionCode(1040100, rescueVersionName);
  if (rescueVersionName !== '1.4.1' || rescueVersionCode !== 1040100) {
    throw new Error('Expected rescue stable 1.4.1 to produce versionCode 1040100.');
  }

  const stableVersionName = deriveVersionName('1.5.0', 'stable');
  const stableVersionCode = deriveVersionCode(1050000, stableVersionName);
  if (stableVersionName !== '1.5.0' || stableVersionCode !== 1050000) {
    throw new Error('Expected planned stable 1.5.0 to produce versionCode 1050000.');
  }

  assertThrows(() => assertBetaVersion(deriveVersionName('1.4.0', 'beta'), 1040000), '1.4.0 beta');
  assertThrows(() => assertBetaVersion(deriveVersionName('1.4.1', 'beta'), 1040100), '1.4.1 beta');
  assertThrows(() => assertStableVersion('1.5.0-beta', 1050000), 'stable prerelease');
  assertThrows(() => assertStableVersion('1.4.2', 1040200), 'planned stable patch');

  const betaVersionName = deriveVersionName('1.4.2', 'beta');
  const betaVersionCode = deriveVersionCode(1040200, betaVersionName);
  assertBetaVersion(betaVersionName, betaVersionCode);
  if (betaVersionName !== '1.4.2-beta' || betaVersionCode !== 1040200) {
    throw new Error('Expected beta 1.4.2 to produce 1.4.2-beta / 1040200.');
  }
}

function assertThrows(callback, label) {
  try {
    callback();
  } catch {
    return;
  }
  throw new Error(`Expected ${label} derivation to fail.`);
}

function normalizeVersionCode(value, label) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`${label} must be a positive integer.`);
  }
  return parsed;
}

function normalizeChannel(value) {
  const channel = String(value ?? '')
    .trim()
    .toLowerCase();
  if (channel === 'stable' || channel === 'beta') return channel;
  throw new Error(`Unsupported update channel: ${value}. Expected stable or beta.`);
}

function parseArgs(values) {
  const result = {};
  for (let index = 0; index < values.length; index += 1) {
    const raw = values[index];
    if (!raw?.startsWith('--')) continue;
    const key = raw.slice(2);
    const next = values[index + 1];
    if (!next || next.startsWith('--')) {
      result[key] = 'true';
      continue;
    }
    result[key] = next;
    index += 1;
  }
  return result;
}

async function appendFile(filePath, content) {
  const { appendFile } = await import('node:fs/promises');
  await appendFile(filePath, content);
}
