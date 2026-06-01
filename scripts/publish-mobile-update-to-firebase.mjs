import { execFileSync } from 'node:child_process';
import { createSign, randomUUID } from 'node:crypto';
import { existsSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(import.meta.url);
const args = parseArgs(process.argv.slice(2));

const project = requiredValue(args.project, '--project');
const skipUpload = args['skip-upload'] === 'true';
const bucket = skipUpload ? args.bucket : requiredValue(args.bucket, '--bucket');
const apkPath = skipUpload ? null : requiredPath(args.apk, '--apk');
const manifestPath = requiredPath(args.manifest, '--manifest');
const outputPath = args.output ? resolve(repoRoot, args.output) : manifestPath;
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
const createBucketLocation = args['create-bucket-location'];

if (!manifest?.releasePath || !manifest?.channelPath || !manifest?.release || !manifest?.channel) {
  throw new Error('--manifest must contain releasePath, release, channelPath, and channel.');
}

const token = await getFirebaseAccessToken();
const apk = manifest.release.apk ?? {};
const channel = manifest.release.channel ?? manifest.channel.channel ?? 'stable';
const versionCode = manifest.release.versionCode;
const fileName = apk.fileName ?? apkPath.split(/[\\/]/).pop() ?? '1wallet-update.apk';
let objectName;
if (!skipUpload) {
  objectName = `mobile-updates/android/${channel}/${versionCode}/${fileName}`;
  const downloadToken = randomUUID();
  const sizeBytes = statSync(apkPath).size;
  if (createBucketLocation) {
    await ensureBucket({ token, project, bucket, location: createBucketLocation });
  }
  const downloadUrl = await uploadApk({
    token,
    bucket,
    apkPath,
    objectName,
    downloadToken,
  });

  manifest.release.apk = {
    ...apk,
    downloadUrl,
    fileName,
    sizeBytes,
  };
} else if (typeof manifest.release.apk?.downloadUrl !== 'string') {
  throw new Error('--skip-upload requires manifest.release.apk.downloadUrl.');
}

await writeFirestoreDocument({
  token,
  project,
  path: manifest.releasePath,
  data: manifest.release,
});
await writeFirestoreDocument({
  token,
  project,
  path: manifest.channelPath,
  data: manifest.channel,
});
const releaseFeed = buildReleaseFeed(manifest);
await writeFirestoreDocument({
  token,
  project,
  path: releaseFeed.path,
  data: releaseFeed.data,
});

writeFileSync(outputPath, `${JSON.stringify(manifest, null, 2)}\n`);
if (objectName) console.log(`Uploaded ${objectName}`);
console.log(`Wrote ${relative(outputPath)}`);
console.log(`Published ${manifest.releasePath}, ${manifest.channelPath}, and ${releaseFeed.path}`);

async function uploadApk({ token, bucket, apkPath, objectName, downloadToken }) {
  const boundary = `onewallet-${randomUUID()}`;
  const fileBuffer = readFileSync(apkPath);
  const metadata = {
    name: objectName,
    contentType: 'application/vnd.android.package-archive',
    cacheControl: 'public, max-age=300',
    metadata: {
      firebaseStorageDownloadTokens: downloadToken,
    },
  };
  const prefix = Buffer.from(
    `--${boundary}\r\n` +
      'Content-Type: application/json; charset=UTF-8\r\n\r\n' +
      `${JSON.stringify(metadata)}\r\n` +
      `--${boundary}\r\n` +
      'Content-Type: application/vnd.android.package-archive\r\n\r\n',
  );
  const suffix = Buffer.from(`\r\n--${boundary}--\r\n`);
  const response = await fetch(
    `https://storage.googleapis.com/upload/storage/v1/b/${encodeURIComponent(bucket)}/o?uploadType=multipart`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': `multipart/related; boundary=${boundary}`,
      },
      body: Buffer.concat([prefix, fileBuffer, suffix]),
    },
  );
  await assertOk(response, 'upload APK');
  return `https://firebasestorage.googleapis.com/v0/b/${encodeURIComponent(bucket)}/o/${encodeURIComponent(objectName)}?alt=media&token=${downloadToken}`;
}

async function ensureBucket({ token, project, bucket, location }) {
  const existing = await fetch(
    `https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(bucket)}`,
    {
      headers: { Authorization: `Bearer ${token}` },
    },
  );
  if (existing.ok) return;
  if (existing.status !== 404) await assertOk(existing, `check bucket ${bucket}`);

  const response = await fetch(
    `https://storage.googleapis.com/storage/v1/b?project=${encodeURIComponent(project)}`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        name: bucket,
        location,
        storageClass: 'STANDARD',
      }),
    },
  );
  if (response.status === 409) return;
  await assertOk(response, `create bucket ${bucket}`);
}

async function writeFirestoreDocument({ token, project, path, data }) {
  const documentPath = path.split('/').map(encodeURIComponent).join('/');
  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(project)}/databases/(default)/documents/${documentPath}`,
    {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ fields: toFirestoreFields(data) }),
    },
  );
  await assertOk(response, `write ${path}`);
}

function toFirestoreFields(data) {
  return Object.fromEntries(
    Object.entries(data)
      .filter(([, value]) => value !== undefined)
      .map(([key, value]) => [key, toFirestoreValue(key, value)]),
  );
}

function toFirestoreValue(key, value) {
  if ((key === 'publishedAt' || key === 'updatedAt') && typeof value === 'string') {
    return { timestampValue: value };
  }
  if (value === null) return { nullValue: null };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') {
    if (Number.isInteger(value)) return { integerValue: String(value) };
    return { doubleValue: value };
  }
  if (typeof value === 'string') return { stringValue: value };
  if (Array.isArray(value)) {
    return {
      arrayValue: {
        values: value.map((item) => toFirestoreValue('', item)),
      },
    };
  }
  if (typeof value === 'object') return { mapValue: { fields: toFirestoreFields(value) } };
  throw new Error(`Unsupported Firestore value for ${key}.`);
}

function buildReleaseFeed(manifest) {
  if (manifest.releaseFeedPath && manifest.releaseFeed) {
    return {
      path: manifest.releaseFeedPath,
      data: manifest.releaseFeed,
    };
  }
  const release = manifest.release;
  const id = releaseFeedId(release.versionCode, release.channel, release.versionName);
  return {
    path: `appUpdates/android/releaseFeed/${id}`,
    data: {
      platform: release.platform ?? 'android',
      channel: release.channel,
      status: release.status,
      versionName: release.versionName,
      versionCode: release.versionCode,
      releasePath: manifest.releasePath,
      publishedAt: release.publishedAt,
      title: `1Wallet Android ${release.versionName} ${release.channel === 'beta' ? 'Beta' : 'Stable'} (${release.versionCode})`,
    },
  };
}

function releaseFeedId(versionCode, channel, versionName) {
  const maxVersionCode = 999999999;
  const parsedVersionCode = Number(versionCode);
  if (!Number.isInteger(parsedVersionCode) || parsedVersionCode <= 0) {
    throw new Error('release feed versionCode must be a positive integer.');
  }
  if (parsedVersionCode >= maxVersionCode) {
    throw new Error('release feed versionCode is too high for descending sort key.');
  }
  const sortKey = String(maxVersionCode - parsedVersionCode).padStart(9, '0');
  return `${sortKey}-${parsedVersionCode}-${safeDocIdPart(channel)}-${safeDocIdPart(versionName)}`;
}

function safeDocIdPart(value) {
  return String(value ?? 'unknown')
    .replace(/[^A-Za-z0-9._-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80);
}

async function getFirebaseAccessToken() {
  const scopes = [
    'https://www.googleapis.com/auth/cloud-platform',
    'https://www.googleapis.com/auth/firebase',
  ];
  const serviceAccount = loadServiceAccountCredentials();
  if (serviceAccount) return getServiceAccountAccessToken(serviceAccount, scopes);

  const auth = loadFirebaseAuth();
  const account = auth.getGlobalDefaultAccount?.();
  const refreshToken = account?.tokens?.refresh_token;
  if (!refreshToken) throw new Error('Firebase CLI is not logged in. Run `firebase login` first.');
  const accessToken = await auth.getAccessToken(refreshToken, scopes);
  if (!accessToken?.access_token) throw new Error('Firebase CLI did not return an access token.');
  return accessToken.access_token;
}

function loadServiceAccountCredentials() {
  const rawJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (rawJson?.trim()) return JSON.parse(rawJson);

  const rawBase64 = process.env.FIREBASE_SERVICE_ACCOUNT_JSON_BASE64;
  if (rawBase64?.trim())
    return JSON.parse(Buffer.from(rawBase64.trim(), 'base64').toString('utf8'));

  const filePath =
    process.env.FIREBASE_SERVICE_ACCOUNT_FILE || process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (filePath?.trim() && existsSync(filePath.trim())) {
    return JSON.parse(readFileSync(filePath.trim(), 'utf8'));
  }
  return null;
}

async function getServiceAccountAccessToken(credentials, scopes) {
  if (!credentials.client_email || !credentials.private_key) {
    throw new Error(
      'Firebase service account credentials are missing client_email or private_key.',
    );
  }
  const now = Math.floor(Date.now() / 1000);
  const assertion = signJwt(
    {
      alg: 'RS256',
      typ: 'JWT',
    },
    {
      iss: credentials.client_email,
      scope: scopes.join(' '),
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    },
    credentials.private_key,
  );
  const body = new URLSearchParams({
    grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    assertion,
  });
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  await assertOk(response, 'create Firebase service account access token');
  const token = await response.json();
  if (!token.access_token)
    throw new Error('Firebase service account did not return an access token.');
  return token.access_token;
}

function signJwt(header, payload, privateKey) {
  const signingInput = `${base64Url(JSON.stringify(header))}.${base64Url(JSON.stringify(payload))}`;
  const signature = createSign('RSA-SHA256').update(signingInput).sign(privateKey);
  return `${signingInput}.${base64Url(signature)}`;
}

function base64Url(value) {
  return Buffer.from(value)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function loadFirebaseAuth() {
  const candidates = ['firebase-tools/lib/auth'];
  try {
    const globalRoot = execFileSync('npm', ['root', '-g'], { encoding: 'utf8' }).trim();
    if (globalRoot) candidates.push(join(globalRoot, 'firebase-tools/lib/auth'));
  } catch {
    // Keep trying the other known locations.
  }
  if (process.env.APPDATA)
    candidates.push(join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/auth'));
  for (const candidate of candidates) {
    try {
      return require(candidate);
    } catch {
      // Try the next candidate.
    }
  }
  throw new Error('Could not load firebase-tools auth helpers. Install Firebase CLI first.');
}

async function assertOk(response, label) {
  if (response.ok) return;
  const text = await response.text();
  throw new Error(`${label} failed with HTTP ${response.status}: ${text.slice(0, 500)}`);
}

function parseArgs(values) {
  const result = {};
  for (let index = 0; index < values.length; index += 1) {
    const raw = values[index];
    if (!raw?.startsWith('--')) continue;
    const key = raw.slice(2);
    const next = values[index + 1];
    if (next === undefined || next.startsWith('--')) {
      result[key] = 'true';
      continue;
    }
    result[key] = next;
    index += 1;
  }
  return result;
}

function requiredPath(value, label) {
  const raw = requiredValue(value, label);
  const filePath = resolve(repoRoot, raw);
  if (!existsSync(filePath)) throw new Error(`${label} does not exist: ${raw}`);
  return filePath;
}

function requiredValue(value, label) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new Error(`${label} is required.`);
  }
  return value.trim();
}

function relative(filePath) {
  return filePath.startsWith(repoRoot) ? filePath.slice(repoRoot.length + 1) : filePath;
}
