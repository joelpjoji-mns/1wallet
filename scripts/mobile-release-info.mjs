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
  if (!runNum) return baseVersion;
  const match = baseVersion.match(/^(\d+\.\d+)(?:\.\d+)?$/);
  if (!match) return baseVersion.replace(/\.\d+$/, `.${runNum}`);
  const prefix = match[1];
  const num = parseInt(runNum, 10);
  const patchStr = num < 10 ? `0${num}` : `${num}`;
  return `${prefix}.${patchStr}`;
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
