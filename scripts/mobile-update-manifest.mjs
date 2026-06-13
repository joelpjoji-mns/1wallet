#!/usr/bin/env node
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

function readArg(name, fallback = undefined) {
  const index = process.argv.indexOf(name);
  return index === -1 ? fallback : process.argv[index + 1] ?? fallback;
}

function boolArg(name) {
  const index = process.argv.indexOf(name);
  if (index === -1) return false;
  const next = process.argv[index + 1];
  return next === undefined || next.startsWith('--') ? true : next === 'true';
}

function requiredArg(name) {
  const value = readArg(name);
  if (!value) {
    console.error(`${name} is required.`);
    process.exit(1);
  }
  return value;
}

const apkPath = requiredArg('--apk');
const version = requiredArg('--version');
const versionCode = requiredArg('--version-code');
const url = requiredArg('--url');
const fileName = requiredArg('--file-name');
const architecture = requiredArg('--architecture');
const channel = requiredArg('--channel');
const changelogPath = requiredArg('--changelog-json');
const outputPath = requiredArg('--output');
const releaseType = readArg('--release-type', 'patch');
const mandatory = boolArg('--mandatory');

if (!fs.existsSync(apkPath)) {
  console.error(`APK not found: ${apkPath}`);
  process.exit(1);
}
if (!fs.existsSync(changelogPath)) {
  console.error(`Changelog JSON not found: ${changelogPath}`);
  process.exit(1);
}

const apk = fs.readFileSync(apkPath);
const changelogSource = JSON.parse(fs.readFileSync(changelogPath, 'utf8'));
const changelog = {
  newFeatures: changelogSource.newFeatures ?? changelogSource.features ?? changelogSource.changelog?.newFeatures ?? changelogSource.changelog?.features ?? [],
  bugFixes: changelogSource.bugFixes ?? changelogSource.fixes ?? changelogSource.changelog?.bugFixes ?? changelogSource.changelog?.fixes ?? [],
  notes: changelogSource.notes ?? changelogSource.changelog?.notes ?? [],
};
const manifest = {
  versionName: version,
  version,
  versionCode: Number.parseInt(versionCode, 10),
  platform: 'android',
  channel,
  status: 'published',
  releaseType,
  requirement: mandatory ? 'mandatory' : 'optional',
  mandatory,
  minimumSupportedVersionCode: 0,
  runtimeVersion: version,
  apk: {
    fileName,
    downloadUrl: url,
    url,
    sizeBytes: apk.length,
    sha256: createHash('sha256').update(apk).digest('hex'),
    architecture,
  },
  changelog,
  generatedAt: new Date().toISOString(),
};

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
console.log(`Wrote update manifest to ${outputPath}.`);
