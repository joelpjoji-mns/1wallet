#!/usr/bin/env node
import { execFileSync } from 'node:child_process';
import { createSign, randomBytes } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = parseArgs(process.argv.slice(2));
const dryRun = args.apply !== 'true';

main().catch((error) => {
  console.error(`QA seed failed: ${error instanceof Error ? error.message : String(error)}`);
  process.exit(1);
});

async function main() {
  const env = loadDotEnv(resolve(repoRoot, '.env.local'));
  const projectId = requiredValue(
    args.project || env.EXPO_PUBLIC_FIREBASE_PROJECT_ID,
    'Firebase project ID',
  );
  const apiKey = requiredValue(env.EXPO_PUBLIC_FIREBASE_API_KEY, 'Firebase API key');
  const targetEmail = args['target-email'] || 'qa@onewallet.test';
  const targetPassword = args['target-password'] || generatePassword();
  const sourceUid = args['source-uid'] || null;
  const sourceEmail = args['source-email'] || null;
  if (!sourceUid && !sourceEmail) {
    throw new Error('Pass --source-uid or --source-email for the Joel source account.');
  }

  const accessToken = await getFirebaseAccessToken();
  const resolvedSourceUid = sourceUid || (await findUserDocByEmail(projectId, accessToken, sourceEmail));
  if (!resolvedSourceUid) {
    throw new Error('Could not resolve source user from Firestore users/{uid} documents.');
  }

  console.log(`Project: ${projectId}`);
  console.log(`Source UID: ${maskId(resolvedSourceUid)}`);
  console.log(`Target email: ${targetEmail}`);
  console.log(`Mode: ${dryRun ? 'dry-run (no writes)' : 'apply (writes enabled)'}`);

  const wallet = await readDocument(
    projectId,
    accessToken,
    `users/${resolvedSourceUid}/wallets/default`,
  );
  const snapshotId = stringField(wallet, 'latestSnapshotId');
  if (!snapshotId) throw new Error('Source wallet has no latestSnapshotId.');
  const snapshot = await readDocument(
    projectId,
    accessToken,
    `users/${resolvedSourceUid}/wallets/default/snapshots/${snapshotId}`,
  );
  const chunks = await listDocuments(
    projectId,
    accessToken,
    `users/${resolvedSourceUid}/wallets/default/snapshots/${snapshotId}/chunks`,
  );
  chunks.sort((left, right) => integerField(left, 'index') - integerField(right, 'index'));
  const expectedChunks = integerField(wallet, 'latestSnapshotChunks');
  if (chunks.length !== expectedChunks) {
    throw new Error(`Source snapshot chunk count mismatch: expected ${expectedChunks}, got ${chunks.length}.`);
  }
  const archiveContent = chunks.map((chunk) => stringField(chunk, 'content')).join('');
  const expectedSize = integerField(wallet, 'latestSnapshotSize');
  if (archiveContent.length !== expectedSize) {
    throw new Error(`Source snapshot size mismatch: expected ${expectedSize}, got ${archiveContent.length}.`);
  }
  const archive = JSON.parse(archiveContent);
  const expectedChecksum = stringField(wallet, 'latestSnapshotChecksum');
  const actualChecksum = checksumLedgerState(archive.ledger);
  if (expectedChecksum !== actualChecksum || archive.checksum !== actualChecksum) {
    throw new Error('Source snapshot checksum mismatch.');
  }

  console.log(
    `Source snapshot OK: ${snapshotId} (${chunks.length} chunk(s), ${archiveContent.length} bytes).`,
  );

  if (dryRun) {
    console.log('Dry run complete. Re-run with --apply to create/sign in QA user and copy data.');
    return;
  }

  const target = await createOrSignInUser(apiKey, targetEmail, targetPassword);
  const now = new Date().toISOString();
  const passwordFile = resolve(repoRoot, '.tmp', 'firebase-qa-user.local.json');
  mkdirSync(dirname(passwordFile), { recursive: true });
  writeFileSync(
    passwordFile,
    `${JSON.stringify(
      {
        projectId,
        targetEmail,
        targetUid: target.localId,
        temporaryPassword: targetPassword,
        updatedAt: now,
      },
      null,
      2,
    )}\n`,
  );

  await writeDocument(projectId, accessToken, `users/${target.localId}`, {
    fields: {
      email: { stringValue: targetEmail },
      displayName: { nullValue: null },
      authProvider: { stringValue: 'password' },
      updatedAt: { timestampValue: now },
    },
  });
  await writeDocument(projectId, accessToken, `users/${target.localId}/wallets/default`, {
    fields: wallet.fields,
  });
  await writeDocument(
    projectId,
    accessToken,
    `users/${target.localId}/wallets/default/snapshots/${snapshotId}`,
    { fields: snapshot.fields },
  );
  for (const chunk of chunks) {
    const chunkId = chunk.name.split('/').pop();
    await writeDocument(
      projectId,
      accessToken,
      `users/${target.localId}/wallets/default/snapshots/${snapshotId}/chunks/${chunkId}`,
      { fields: chunk.fields },
    );
  }

  console.log(`QA user ready: ${targetEmail} (${maskId(target.localId)}).`);
  console.log(`Temporary password saved locally: ${relative(passwordFile)}`);
  console.log('Copied wallet metadata, snapshot, and chunks into the QA user subtree.');
}

async function createOrSignInUser(apiKey, email, password) {
  const signUp = await fetchJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${encodeURIComponent(apiKey)}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
    { allowError: true },
  );
  if (!signUp.error) return signUp;
  if (signUp.error.message !== 'EMAIL_EXISTS') {
    throw new Error(`Could not create QA user: ${signUp.error.message}`);
  }

  const signedIn = await fetchJson(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${encodeURIComponent(apiKey)}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
    { allowError: true },
  );
  if (!signedIn.error) return signedIn;
  throw new Error(
    'QA user already exists but the generated/provided password did not sign in. ' +
    'Pass --target-password with the current password, reset it in Firebase Console, or delete the user.',
  );
}

async function findUserDocByEmail(projectId, accessToken, email) {
  const users = await listDocuments(projectId, accessToken, 'users');
  const match = users.find((doc) => stringField(doc, 'email')?.toLowerCase() === email.toLowerCase());
  return match?.name?.split('/').pop() || null;
}

async function readDocument(projectId, accessToken, path) {
  return fetchJson(firestoreUrl(projectId, path), {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
}

async function listDocuments(projectId, accessToken, path) {
  const documents = [];
  let pageToken = '';
  do {
    const url = new URL(firestoreUrl(projectId, path));
    url.searchParams.set('pageSize', '1000');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const response = await fetchJson(url, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    documents.push(...(response.documents || []));
    pageToken = response.nextPageToken || '';
  } while (pageToken);
  return documents;
}

async function writeDocument(projectId, accessToken, path, body) {
  return fetchJson(firestoreUrl(projectId, path), {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
}

function firestoreUrl(projectId, path) {
  return `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(
    projectId,
  )}/databases/(default)/documents/${path}`;
}

function stringField(document, key) {
  const value = document?.fields?.[key];
  if (!value) return null;
  if ('stringValue' in value) return value.stringValue;
  return null;
}

function integerField(document, key) {
  const value = document?.fields?.[key];
  if (!value) return 0;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return Number(value.doubleValue);
  return 0;
}

function checksumLedgerState(state) {
  const input = stableStringify(state);
  let hash = 0x811c9dc5;
  for (let index = 0; index < input.length; index += 1) {
    hash ^= input.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return `fnv1a32:${(hash >>> 0).toString(16).padStart(8, '0')}`;
}

function stableStringify(value) {
  if (Array.isArray(value)) return `[${value.map((item) => stableStringify(item)).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`)
      .join(',')}}`;
  }
  return JSON.stringify(value);
}

function generatePassword() {
  return `Qa-${randomBytes(12).toString('base64url')}!1`;
}

function loadDotEnv(filePath) {
  if (!existsSync(filePath)) return {};
  const result = {};
  for (const line of readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/);
    if (!match) continue;
    result[match[1]] = match[2];
  }
  return result;
}

async function getFirebaseAccessToken() {
  const scopes = [
    'https://www.googleapis.com/auth/cloud-platform',
    'https://www.googleapis.com/auth/firebase',
    'https://www.googleapis.com/auth/datastore',
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
  if (rawBase64?.trim()) return JSON.parse(Buffer.from(rawBase64.trim(), 'base64').toString('utf8'));

  const filePath =
    process.env.FIREBASE_SERVICE_ACCOUNT_FILE || process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (filePath?.trim() && existsSync(filePath.trim())) {
    return JSON.parse(readFileSync(filePath.trim(), 'utf8'));
  }
  return null;
}

async function getServiceAccountAccessToken(credentials, scopes) {
  if (!credentials.client_email || !credentials.private_key) {
    throw new Error('Service account credentials are missing client_email or private_key.');
  }
  const now = Math.floor(Date.now() / 1000);
  const assertion = signJwt(
    { alg: 'RS256', typ: 'JWT' },
    {
      iss: credentials.client_email,
      scope: scopes.join(' '),
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    },
    credentials.private_key,
  );
  const response = await fetchJson('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!response.access_token) throw new Error('Service account did not return an access token.');
  return response.access_token;
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
  if (process.env.APPDATA) {
    candidates.push(join(process.env.APPDATA, 'npm/node_modules/firebase-tools/lib/auth'));
  }
  for (const candidate of candidates) {
    try {
      return require(candidate);
    } catch {
      // Try the next candidate.
    }
  }
  throw new Error('Could not load firebase-tools auth helpers. Install Firebase CLI first.');
}

async function fetchJson(url, options = {}, { allowError = false } = {}) {
  const response = await fetch(url, options);
  const text = await response.text();
  const data = text ? JSON.parse(text) : {};
  if (!response.ok && !allowError) {
    throw new Error(`HTTP ${response.status}: ${text.slice(0, 500)}`);
  }
  return data;
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

function requiredValue(value, label) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new Error(`${label} is required.`);
  }
  return value.trim();
}

function maskId(value) {
  if (!value || value.length <= 8) return value || 'unknown';
  return `${value.slice(0, 4)}…${value.slice(-4)}`;
}

function relative(filePath) {
  return filePath.startsWith(repoRoot) ? filePath.slice(repoRoot.length + 1) : filePath;
}
