import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = parseArgs(process.argv.slice(2));
const appConfig = JSON.parse(readFileSync(resolve(repoRoot, 'apps/mobile/app.json'), 'utf8'));
const buildGradle = readFileSync(resolve(repoRoot, 'apps/mobile/android/app/build.gradle'), 'utf8');
const versionName = appConfig.expo?.version;
const versionCode = readVersionCode(buildGradle) ?? versionCodeFromSemver(versionName);

if (!versionName) throw new Error('Could not read expo.version from apps/mobile/app.json.');
if (!versionCode) throw new Error('Could not determine Android versionCode.');

const info = {
  versionName,
  versionCode: String(versionCode),
  tag: `android-v${versionName}-${versionCode}`,
  apkFileName: `1wallet-${versionName}-${versionCode}-universal.apk`,
  manifestFileName: `1wallet-${versionName}-${versionCode}-update-manifest.json`,
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
