#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function readArg(name, fallback = undefined) {
  const index = process.argv.indexOf(name);
  return index === -1 ? fallback : process.argv[index + 1] ?? fallback;
}

function writeOutput(file, values) {
  const lines = Object.entries(values).map(([key, value]) => `${key}=${value}`);
  if (file) {
    fs.appendFileSync(file, `${lines.join('\n')}\n`, 'utf8');
  } else {
    console.log(lines.join('\n'));
  }
}

function formatVersionInfo(baseVersion, runNum, startRun = 155) {
  const match = baseVersion.match(/^(\d+)(?:\.(\d+))?(?:\.(\d+))?$/);
  const baseMajor = match && match[1] !== undefined ? parseInt(match[1], 10) : 2;
  const baseMinor = match && match[2] !== undefined ? parseInt(match[2], 10) : 2;
  const basePatch = match && match[3] !== undefined ? parseInt(match[3], 10) : 0;

  const n = runNum !== undefined && runNum !== null && runNum !== ''
    ? Math.max(0, parseInt(runNum, 10) - startRun)
    : 0;

  // 4-digit code (e.g. 2200 for 2.2.00, 2201 for 2.2.01, 2300 for 2.3.00, 3000 for 3.0.00)
  const baseIndex = baseMajor * 1000 + baseMinor * 100 + basePatch;
  const total = baseIndex + n;

  const major = Math.floor(total / 1000);
  const minor = Math.floor((total % 1000) / 100);
  const patch = total % 100;
  const patchStr = patch < 10 ? `0${patch}` : `${patch}`;

  const versionName = `${major}.${minor}.${patchStr}`;
  // Android OS versionCode must stay > 2102151 to allow install without downgrade failure.
  // 2,100,000 + 4-digit code gives 2102200 for 2.2.00!
  const versionCode = String(2100000 + total);

  return { versionName, versionCode, buildNumber: total };
}

const runNumber = readArg('--run-number');
const outputFile = readArg('--output', process.env.GITHUB_OUTPUT);
const pubspecPath = path.resolve(__dirname, '..', 'pubspec.yaml');
const pubspec = fs.readFileSync(pubspecPath, 'utf8');
const versionMatch = pubspec.match(/^version:\s*([^+\s]+)\+(\d+)\s*$/m);

if (!versionMatch) {
  console.error('Unable to read `version: x.y.z+build` from pubspec.yaml.');
  process.exit(1);
}

const [, pubspecVersionName] = versionMatch;
const startRunEnv = parseInt(readArg('--start-run', process.env.ONEWALLET_START_RUN || '155'), 10);
const { versionName, versionCode } = formatVersionInfo(pubspecVersionName, runNumber, startRunEnv);

const channel = 'stable';
const values = {
  versionName,
  versionCode,
  apkFileName: `1wallet-arm64-v8a-${versionName}-${channel}.apk`,
  tag: `android-${versionName}`,
  releaseTitle: `1Wallet Android ${versionName}`,
  prerelease: 'false',
  channel,
  manifestFileName: `mobile-update-${versionName}-${channel}.json`,
};

writeOutput(outputFile, values);
