#!/usr/bin/env node
import { createSign } from 'node:crypto';
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
for (const key of ['versionCode', 'channel', 'apk']) {
  if (manifest[key] === undefined || manifest[key] === null) {
    console.error(`Manifest is missing required field: ${key}`);
    process.exit(1);
  }
}
const versionName = manifest.versionName ?? manifest.version;
if (!versionName) {
  console.error('Manifest is missing required field: versionName/version');
  process.exit(1);
}

if (skipUpload) {
  console.log(
    `Validated ${manifest.channel} update ${versionName} (${manifest.versionCode}) for Firebase project ${project}; upload skipped.`,
  );
  process.exit(0);
}

const serviceAccountSource = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
if (!serviceAccountSource) {
  console.error('FIREBASE_SERVICE_ACCOUNT_JSON is required when uploading metadata.');
  process.exit(1);
}

let serviceAccount;
try {
  serviceAccount = JSON.parse(serviceAccountSource);
} catch (error) {
  console.error(`Could not parse FIREBASE_SERVICE_ACCOUNT_JSON: ${error.message}`);
  process.exit(1);
}

function base64Url(input) {
  return Buffer.from(input)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function signJwt(account) {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const payload = {
    iss: account.client_email,
    scope: 'https://www.googleapis.com/auth/datastore',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${base64Url(JSON.stringify(header))}.${base64Url(JSON.stringify(payload))}`;
  const signer = createSign('RSA-SHA256');
  signer.update(unsigned);
  signer.end();
  const signature = signer
    .sign(account.private_key, 'base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
  return `${unsigned}.${signature}`;
}

async function accessToken(account) {
  const assertion = signJwt(account);
  const body = new URLSearchParams({
    grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    assertion,
  });
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body,
  });
  if (!response.ok) {
    throw new Error(`Token request failed (${response.status}): ${await response.text()}`);
  }
  return (await response.json()).access_token;
}

function firestoreValue(value) {
  if (value === null || value === undefined) return { nullValue: null };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') {
    return Number.isInteger(value)
      ? { integerValue: String(value) }
      : { doubleValue: value };
  }
  if (typeof value === 'string') return { stringValue: value };
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(firestoreValue) } };
  }
  if (typeof value === 'object') {
    return {
      mapValue: {
        fields: Object.fromEntries(
          Object.entries(value).map(([key, item]) => [key, firestoreValue(item)]),
        ),
      },
    };
  }
  return { stringValue: String(value) };
}

function firestoreDocument(data) {
  return {
    fields: Object.fromEntries(
      Object.entries(data)
        .filter(([, value]) => value !== undefined)
        .map(([key, value]) => [key, firestoreValue(value)]),
    ),
  };
}

async function patchDocument(token, path, data) {
  const url = `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(project)}/databases/(default)/documents/${path}`;
  const response = await fetch(url, {
    method: 'PATCH',
    headers: {
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify(firestoreDocument(data)),
  });
  if (!response.ok) {
    throw new Error(`Firestore write failed for ${path} (${response.status}): ${await response.text()}`);
  }
}

function normalizeChangelog(source) {
  const nested = source?.changelog ?? {};
  return {
    newFeatures: source?.newFeatures ?? source?.features ?? nested.newFeatures ?? nested.features ?? [],
    bugFixes: source?.bugFixes ?? source?.fixes ?? nested.bugFixes ?? nested.fixes ?? [],
    notes: source?.notes ?? nested.notes ?? [],
  };
}

const versionCode = Number.parseInt(manifest.versionCode, 10);
const channel = String(manifest.channel);
const apk = manifest.apk ?? {};
const publishedAt = manifest.generatedAt ?? new Date().toISOString();
const release = {
  id: String(versionCode),
  platform: manifest.platform ?? 'android',
  channel,
  status: manifest.status ?? 'published',
  versionName,
  version: versionName,
  versionCode,
  runtimeVersion: manifest.runtimeVersion ?? versionName,
  releaseType: manifest.releaseType ?? 'patch',
  requirement: manifest.requirement ?? (manifest.mandatory ? 'mandatory' : 'optional'),
  mandatory: Boolean(manifest.mandatory),
  minimumSupportedVersionCode: manifest.minimumSupportedVersionCode ?? 0,
  publishedAt,
  generatedAt: publishedAt,
  changelog: normalizeChangelog(manifest.changelog ?? manifest),
  apk: {
    fileName: apk.fileName ?? 'update.apk',
    downloadUrl: apk.downloadUrl ?? apk.url ?? '',
    url: apk.url ?? apk.downloadUrl ?? '',
    sizeBytes: apk.sizeBytes ?? 0,
    sha256: apk.sha256 ?? '',
    architecture: apk.architecture ?? '',
    minSdk: apk.minSdk ?? null,
    estimatedDownloadSeconds: apk.estimatedDownloadSeconds ?? null,
  },
};

if (!release.apk.downloadUrl) {
  console.error('Manifest apk.downloadUrl/apk.url is required.');
  process.exit(1);
}

try {
  const token = await accessToken(serviceAccount);
  await patchDocument(token, `appUpdates/android/releases/${versionCode}`, release);
  await patchDocument(token, `appUpdates/android/channels/${channel}`, {
    channel,
    latestVersionCode: versionCode,
    latestReleaseId: String(versionCode),
    versionName,
    updatedAt: publishedAt,
  });
  console.log(
    `Published ${channel} update ${versionName} (${versionCode}) metadata to Firebase project ${project}.`,
  );
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
