import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  throw new Error('Deletion integration tests require isolated Auth and Firestore emulators.');
}
const projectId = 'demo-1wallet-rules';
const app = initializeApp({ projectId }, 'deletion-tests');
const db = getFirestore(app);
const auth = getAuth(app);
const base = `http://127.0.0.1:5001/${projectId}/us-central1`;
after(() => deleteApp(app));
const post = (name, body, token) => fetch(`${base}/${name}`, {
  method: 'POST', headers: { 'content-type': 'application/json',
    ...(token ? { Authorization: `Bearer ${token}` } : {}) },
  body: JSON.stringify(body),
});

test('unauthenticated requests cannot schedule deletion', async () => {
  const response = await post('requestAccountDeletion', {
    receipt: randomBytes(32).toString('base64url'), uid: 'another-owner',
  });
  assert.equal(response.status, 401);
});

test('verified owner deletion removes nested data and auth, with post-auth receipt status', async () => {
  const uid = `deletion-${randomUUID()}`;
  const other = `unrelated-${randomUUID()}`;
  const receipt = randomBytes(32).toString('base64url');
  const email = `${uid}@example.test`;
  await auth.createUser({ uid, email, password: 'SyntheticTestPassword123!' });
  await db.doc(`users/${uid}`).set({ email });
  await db.doc(`users/${uid}/unknown/nested/children/deep`).set({ dummy: true });
  await db.doc(`users/${other}`).set({ email: 'untouched@example.test' });
  const login = await fetch(
    `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo`,
    { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ email, password: 'SyntheticTestPassword123!', returnSecureToken: true }) },
  );
  const { idToken } = await login.json();
  assert.equal(typeof idToken, 'string');
  const response = await post('requestAccountDeletion', { receipt, uid: other }, idToken);
  assert.equal(response.status, 202, await response.text());
  let remoteComplete = false;
  for (let attempt = 0; attempt < 300 && !remoteComplete; attempt++) {
    const status = await post('accountDeletionStatus', { receipt });
    const body = await status.json();
    assert.notEqual(body.status, 'failed');
    remoteComplete = body.remoteComplete === true;
    if (!remoteComplete) await new Promise(resolve => setTimeout(resolve, 100));
  }
  assert.equal(remoteComplete, true);
  assert.equal((await db.doc(`users/${uid}`).get()).exists, false);
  assert.equal((await db.doc(`users/${uid}/unknown/nested/children/deep`).get()).exists, false);
  assert.equal((await db.doc(`users/${other}`).get()).exists, true);
  await assert.rejects(auth.getUser(uid), error => error.code === 'auth/user-not-found');
  const duplicate = await post('deleteAccountWorker', { data: { uid } });
  assert.equal(duplicate.status, 204);
  const wrong = await post('accountDeletionStatus', { receipt: randomBytes(32).toString('base64url') });
  assert.equal(wrong.status, 404);
  const job = await db.doc(`accountDeletionJobs/${uid}`).get();
  assert.equal(job.get('status'), 'complete');
  assert.equal(job.get('receipt'), undefined);
  await db.doc(`users/${other}`).delete();
});
