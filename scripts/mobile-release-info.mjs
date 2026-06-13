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

const channel = readArg('--channel', 'stable');
const outputFile = readArg('--output', process.env.GITHUB_OUTPUT);
const pubspecPath = path.resolve(__dirname, '..', 'pubspec.yaml');
const pubspec = fs.readFileSync(pubspecPath, 'utf8');
const versionMatch = pubspec.match(/^version:\s*([^+\s]+)\+(\d+)\s*$/m);

if (!versionMatch) {
  console.error('Unable to read `version: x.y.z+build` from pubspec.yaml.');
  process.exit(1);
}

const [, versionName, versionCode] = versionMatch;
const isBeta = channel === 'beta';
const suffix = isBeta ? '-beta' : '';
const values = {
  versionName,
  versionCode,
  apkFileName: `1wallet-arm64-v8a-${versionName}-${channel}.apk`,
  tag: `android-${versionName}${suffix}`,
  releaseTitle: `1Wallet Android ${versionName}${isBeta ? ' beta' : ''}`,
  prerelease: isBeta ? 'true' : 'false',
  channel,
  manifestFileName: `mobile-update-${versionName}-${channel}.json`,
};

writeOutput(outputFile, values);
