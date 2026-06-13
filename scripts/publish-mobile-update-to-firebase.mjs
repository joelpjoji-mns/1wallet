#!/usr/bin/env node
import fs from 'node:fs';

function readArg(name, fallback = undefined) {
  const index = process.argv.indexOf(name);
  return index === -1 ? fallback : process.argv[index + 1] ?? fallback;
}

const project = readArg('--project');
const manifestPath = readArg('--manifest');
const skipUpload = process.argv.includes('--skip-upload');

if (!project) {
  console.error('--project is required.');
  process.exit(1);
}
if (!manifestPath) {
  console.error('--manifest is required.');
  process.exit(1);
}
if (!fs.existsSync(manifestPath)) {
  console.error(`Manifest not found: ${manifestPath}`);
  process.exit(1);
}

const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
for (const key of ['version', 'versionCode', 'channel', 'apk']) {
  if (manifest[key] === undefined || manifest[key] === null) {
    console.error(`Manifest is missing required field: ${key}`);
    process.exit(1);
  }
}

if (skipUpload) {
  console.log(
    `Validated ${manifest.channel} update ${manifest.version} (${manifest.versionCode}) for Firebase project ${project}; upload skipped.`,
  );
  process.exit(0);
}

console.error(
  'Firebase upload is not implemented in this repository script yet. Re-run with --skip-upload or implement Firebase Admin SDK publishing.',
);
process.exit(1);
