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

function formatVersionName(baseVersion, runNum) {
  if (runNum === undefined || runNum === null || runNum === '') return baseVersion;
  const match = baseVersion.match(/^(\d+)(?:\.(\d+))?(?:\.(\d+))?$/);
  const baseMajor = match && match[1] !== undefined ? parseInt(match[1], 10) : 2;
  const baseMinor = match && match[2] !== undefined ? parseInt(match[2], 10) : 0;
  const basePatch = match && match[3] !== undefined ? parseInt(match[3], 10) : 0;

  const n = parseInt(runNum, 10);
  if (Number.isNaN(n)) return baseVersion;

  // Schema:
  // - 100 patch versions per minor (00..99, 2-digit padded).
  // - 10 minor versions per major (0..9).
  // - Total 1000 versions per major block.
  // - e.g. 2.0.99 -> 2.1.00; 2.1.49 for run 149; 2.9.99 -> 3.0.00; 9.9.99 -> 10.0.00.
  const baseIndex = baseMajor * 1000 + baseMinor * 100 + basePatch;
  const total = baseIndex + n;

  const major = Math.floor(total / 1000);
  const minor = Math.floor((total % 1000) / 100);
  const patch = total % 100;
  const patchStr = patch < 10 ? `0${patch}` : `${patch}`;

  return `${major}.${minor}.${patchStr}`;
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

const [, pubspecVersionName, pubspecVersionCode] = versionMatch;

// Use pubspecVersionCode as base, add run number to ensure it increments on CI
const versionCode = runNumber ? String(parseInt(pubspecVersionCode, 10) + parseInt(runNumber, 10)) : pubspecVersionCode;
// Use formatVersionName to format patch with leading zero if single digit (e.g. 2.1.01, 2.1.10, 2.1.147)
const versionName = formatVersionName(pubspecVersionName, runNumber);

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
