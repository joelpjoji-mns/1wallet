import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = parseArgs(process.argv.slice(2));
const appConfig = JSON.parse(readFileSync(resolve(repoRoot, 'apps/mobile/app.json'), 'utf8'));
const buildGradle = readFileSync(resolve(repoRoot, 'apps/mobile/android/app/build.gradle'), 'utf8');
const channel = normalizeChannel(args.channel ?? process.env.ONEWALLET_UPDATE_CHANNEL ?? 'stable');
const sourceVersionName = appConfig.expo?.version;
const sourceVersionCode = readVersionCode(buildGradle) ?? versionCodeFromSemver(sourceVersionName);
const betaNumber = normalizeBetaNumber(
  args['beta-number'] ?? process.env.ONEWALLET_BETA_NUMBER ?? '1',
);
const explicitVersionName = args['version-name'] ?? process.env.ONEWALLET_VERSION_NAME;
const explicitVersionCode = args['version-code'] ?? process.env.ONEWALLET_VERSION_CODE;
const versionName =
  explicitVersionName ?? deriveVersionName(sourceVersionName, channel, betaNumber);
const versionCode = explicitVersionCode
  ? normalizeVersionCode(explicitVersionCode, '--version-code')
  : deriveVersionCode(sourceVersionCode, versionName, channel, betaNumber);

if (!sourceVersionName) throw new Error('Could not read expo.version from apps/mobile/app.json.');
if (!versionCode) throw new Error('Could not determine Android versionCode.');

const info = {
  versionName,
  versionCode: String(versionCode),
  channel,
  tag: `android-${channel}-v${versionName}-${versionCode}`,
  releaseTitle: `1Wallet Android ${versionName} ${channel === 'beta' ? 'Beta' : 'Stable'} (${versionCode})`,
  prerelease: String(channel === 'beta'),
  latest: String(channel === 'stable'),
  apkFileName: `1wallet-${versionName}-${channel}-arm64-v8a.apk`,
  manifestFileName: `1wallet-${versionName}-${channel}-update-manifest.json`,
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

function deriveVersionName(sourceVersionName, channel, betaNumber) {
  if (!sourceVersionName) return null;
  if (channel === 'stable' || sourceVersionName.includes('-')) return sourceVersionName;
  return `${sourceVersionName}-beta.${betaNumber}`;
}

function deriveVersionCode(sourceVersionCode, versionName, channel, betaNumber) {
  const baseVersionCode = sourceVersionCode ?? versionCodeFromSemver(versionName);
  if (!baseVersionCode) return null;
  if (channel === 'stable') return baseVersionCode;
  const betaVersionCode = baseVersionCode - 100 + betaNumber;
  if (betaVersionCode <= 0 || betaVersionCode >= baseVersionCode) {
    throw new Error(
      'Could not derive a safe beta versionCode below the target stable versionCode.',
    );
  }
  return betaVersionCode;
}

function normalizeVersionCode(value, label) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`${label} must be a positive integer.`);
  }
  return parsed;
}

function normalizeBetaNumber(value) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 99) {
    throw new Error('--beta-number must be an integer from 1 to 99.');
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
