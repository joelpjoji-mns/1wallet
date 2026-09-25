// Security-rules tests for firebase/firestore.rules, run against the
// Firebase Local Emulator Suite via `firebase emulators:exec`.
//
// Run locally from the repo root:
//   npm --prefix firebase install
//   firebase emulators:exec --only firestore --project demo-1wallet-rules \
//     "node --test firebase/rules.test.mjs"
//
// (Requires the Firebase CLI: `npm install -g firebase-tools`, or `npx
// firebase-tools`.) These tests never touch a real project — they run purely
// against the emulator using the `FIRESTORE_EMULATOR_HOST` env var the
// `emulators:exec` wrapper sets automatically.

import assert from 'node:assert/strict';
import { test, before, after, beforeEach } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { Bytes } from 'firebase/firestore';

const PROJECT_ID = 'demo-1wallet-rules';
const OWNER_UID = 'owner-uid';
const OTHER_UID = 'other-uid';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(new URL('./firestore.rules', import.meta.url), 'utf8'),
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

function ownerDb() {
  return testEnv.authenticatedContext(OWNER_UID).firestore();
}

function otherDb() {
  return testEnv.authenticatedContext(OTHER_UID).firestore();
}

function anonDb() {
  return testEnv.unauthenticatedContext().firestore();
}

test('owner can create their own user profile document', async () => {
  const db = ownerDb();
  await assertSucceeds(
    db.doc(`users/${OWNER_UID}`).set({
      email: 'owner@example.com',
      displayName: 'Owner',
      authProvider: 'google',
      lastWriterDeviceId: 'web-device-1',
    }),
  );
});

test('a different signed-in user cannot read or write another user profile', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(`users/${OWNER_UID}`).set({ email: 'owner@example.com' });
  });

  const other = otherDb();
  await assertFails(other.doc(`users/${OWNER_UID}`).get());
  await assertFails(
    other.doc(`users/${OWNER_UID}`).set({ email: 'hijacked@example.com' }, { merge: true }),
  );
});

test('unauthenticated clients cannot read or write a user profile', async () => {
  const anon = anonDb();
  await assertFails(anon.doc(`users/${OWNER_UID}`).get());
  await assertFails(anon.doc(`users/${OWNER_UID}`).set({ email: 'x@example.com' }));
});

test('user profile accepts valid cloudRevision/ledgerVersion values', async () => {
  const db = ownerDb();
  await assertSucceeds(
    db.doc(`users/${OWNER_UID}`).set({
      email: 'owner@example.com',
      lastWriterDeviceId: 'web-device-1',
      cloudRevision: 0,
      ledgerVersion: 1,
    }),
  );
  await assertSucceeds(
    db.doc(`users/${OWNER_UID}`).set(
      { cloudRevision: 42, ledgerVersion: 7 },
      { merge: true },
    ),
  );
});

test('user profile rejects a non-integer cloudRevision', async () => {
  const db = ownerDb();
  await assertFails(
    db.doc(`users/${OWNER_UID}`).set({ email: 'owner@example.com', cloudRevision: 'not-a-number' }),
  );
});

test('user profile rejects a negative cloudRevision', async () => {
  const db = ownerDb();
  await assertFails(db.doc(`users/${OWNER_UID}`).set({ email: 'owner@example.com', cloudRevision: -1 }));
});

test('user profile rejects a cloudRevision above the int32 ceiling', async () => {
  const db = ownerDb();
  await assertFails(
    db.doc(`users/${OWNER_UID}`).set({ email: 'owner@example.com', cloudRevision: 2147483648 }),
  );
});

test('user profile rejects a non-integer ledgerVersion', async () => {
  const db = ownerDb();
  await assertFails(
    db.doc(`users/${OWNER_UID}`).set({ email: 'owner@example.com', ledgerVersion: { nested: true } }),
  );
});

test('user profile rejects a ledgerVersion of 0 (out of the 1..1000 range)', async () => {
  const db = ownerDb();
  await assertFails(db.doc(`users/${OWNER_UID}`).set({ email: 'owner@example.com', ledgerVersion: 0 }));
});

test('user profile rejects a ledgerVersion above 1000', async () => {
  const db = ownerDb();
  await assertFails(db.doc(`users/${OWNER_UID}`).set({ email: 'owner@example.com', ledgerVersion: 1001 }));
});


test('owner can write a valid wallet_backups chunk document', async () => {
  const db = ownerDb();
  await assertSucceeds(
    db
      .doc(`users/${OWNER_UID}/wallet_backups/chunk_0`)
      .set({
        index: 0,
        data: Bytes.fromUint8Array(new TextEncoder().encode('gzip-bytes-placeholder')),
        updatedAt: new Date(),
      }),
  );
});

test('wallet_backups chunk write rejects unknown fields', async () => {
  const db = ownerDb();
  await assertFails(
    db
      .doc(`users/${OWNER_UID}/wallet_backups/chunk_0`)
      .set({
        index: 0,
        data: Bytes.fromUint8Array(new TextEncoder().encode('gzip-bytes-placeholder')),
        updatedAt: new Date(),
        extraField: 'not allowed',
      }),
  );
});

test('wallet_backups chunk write rejects an empty blob', async () => {
  const db = ownerDb();
  // Firestore's own per-field byte cap (~1,048,487 bytes) is actually
  // tighter than the rule's 1MB ceiling, so an "oversized" blob is rejected
  // by the transport layer before rules ever evaluate it. The empty-blob
  // case below is the boundary the rules layer itself actually enforces
  // (`data.data.size() > 0`).
  await assertFails(
    db.doc(`users/${OWNER_UID}/wallet_backups/chunk_0`).set({
      index: 0,
      data: Bytes.fromUint8Array(new Uint8Array(0)),
      updatedAt: new Date(),
    }),
  );
});

test('another signed-in user cannot read or write into the owner wallet_backups collection', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .doc(`users/${OWNER_UID}/wallet_backups/chunk_0`)
      .set({
        index: 0,
        data: Bytes.fromUint8Array(new TextEncoder().encode('seed')),
        updatedAt: new Date(),
      });
  });

  const other = otherDb();
  await assertFails(other.collection(`users/${OWNER_UID}/wallet_backups`).get());
  await assertFails(
    other.doc(`users/${OWNER_UID}/wallet_backups/chunk_1`).set({
      index: 1,
      data: Bytes.fromUint8Array(new TextEncoder().encode('malicious')),
      updatedAt: new Date(),
    }),
  );
});

test('wallet_backups chunk write rejects a chunk missing required fields', async () => {
  const db = ownerDb();
  await assertFails(db.doc(`users/${OWNER_UID}/wallet_backups/chunk_0`).set({ index: 0 }));
});

test('owner can delete their own trailing wallet_backups chunks (pruning)', async () => {
  const db = ownerDb();
  await assertSucceeds(
    db.doc(`users/${OWNER_UID}/wallet_backups/chunk_1`).set({
      index: 1,
      data: Bytes.fromUint8Array(new TextEncoder().encode('gzip-bytes')),
      updatedAt: new Date(),
    }),
  );
  await assertSucceeds(db.doc(`users/${OWNER_UID}/wallet_backups/chunk_1`).delete());
});

test('owner can read, create, update, and delete their own transactions', async () => {
  const db = ownerDb();
  const ref = db.doc(`users/${OWNER_UID}/transactions/tx1`);
  await assertSucceeds(ref.set({ amountMinor: 1000, currency: 'USD' }));
  await assertSucceeds(ref.get());
  await assertSucceeds(ref.set({ amountMinor: 2000, currency: 'USD' }, { merge: true }));
  await assertSucceeds(ref.delete());
});

// Deterministic regression for the atomic check-and-claim-and-write
// transaction `claimAndWriteSnapshot()` in `pwa/src/lib/walletSync.ts` uses
// to guard `users/{uid}` + chunk writes together. Mirrors its conflict logic
// (`hasWriteConflict()` in `pwa/src/lib/walletSyncGuards.ts`) exactly,
// including that it has **no exemption for a matching `lastWriterDeviceId`**
// — an earlier version of this check incorrectly skipped the conflict
// whenever the cloud's last writer matched the caller's own device id, which
// silently broke down for two browser *tabs* of the same device (they share
// one device id), letting the second tab's write through even though the
// first tab had already moved the cloud state forward.
function claimAndWriteSnapshotForTest(db, uid) {
  const ref = db.doc(`users/${uid}`);
  const chunkRef = db.doc(`users/${uid}/wallet_backups/chunk_0`);

  return async function claim(deviceId, expectedMeta, chunkContent) {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const data = snap.exists ? snap.data() : {};
      const cloudUpdatedAt = data.updatedAt;
      const cloudUpdatedAtMs =
        cloudUpdatedAt && typeof cloudUpdatedAt.toMillis === 'function' ? cloudUpdatedAt.toMillis() : null;
      const cloudRevision = typeof data.cloudRevision === 'number' ? data.cloudRevision : null;

      const conflict =
        cloudRevision != null && expectedMeta.cloudRevision != null
          ? cloudRevision !== expectedMeta.cloudRevision
          : cloudUpdatedAtMs != null &&
            (expectedMeta.updatedAtMs == null || cloudUpdatedAtMs > expectedMeta.updatedAtMs);

      if (conflict) {
        throw new Error('WalletSyncConflictError: stale expectedMeta');
      }

      const nextRevision = (cloudRevision ?? 0) + 1;
      tx.set(
        ref,
        { updatedAt: new Date(), lastWriterDeviceId: deviceId, cloudRevision: nextRevision },
        { merge: true },
      );
      tx.set(chunkRef, {
        index: 0,
        data: Bytes.fromUint8Array(new TextEncoder().encode(chunkContent)),
        updatedAt: new Date(),
      });
    });
  };
}

test('optimistic-concurrency transaction rejects a different-device writer using a stale baseline', async () => {
  const db = ownerDb();
  const claim = claimAndWriteSnapshotForTest(db, OWNER_UID);
  const staleExpectedMeta = { updatedAtMs: null, cloudRevision: null };

  // Device A's baseline matches the (empty) current cloud state, so its
  // transaction succeeds and claims the write slot + writes its chunk.
  await assert.doesNotReject(claim('device-A', staleExpectedMeta, 'device-A-snapshot'));

  const metaAfterA = await db.doc(`users/${OWNER_UID}`).get();
  assert.equal(metaAfterA.data().lastWriterDeviceId, 'device-A');
  assert.equal(metaAfterA.data().cloudRevision, 1);

  // Device B raced using the *same* now-stale baseline captured before A's
  // write landed. Its transaction must see A's newer revision and reject
  // deterministically.
  await assert.rejects(
    claim('device-B', staleExpectedMeta, 'device-B-snapshot'),
    /WalletSyncConflictError/,
  );

  // Device B's rejected attempt must not have written anything at all —
  // neither the metadata NOR the chunk it tried to write alongside it.
  const metaAfterB = await db.doc(`users/${OWNER_UID}`).get();
  assert.equal(metaAfterB.data().lastWriterDeviceId, 'device-A');
  assert.equal(metaAfterB.data().cloudRevision, 1);
  const chunkAfterB = await db.doc(`users/${OWNER_UID}/wallet_backups/chunk_0`).get();
  assert.equal(new TextDecoder().decode(chunkAfterB.data().data.toUint8Array()), 'device-A-snapshot');
});

// The actual bug this whole follow-up exists to fix: two browser *tabs* of
// the *same* device (and therefore the *same* `lastWriterDeviceId`) racing
// on a stale baseline. A `lastWriterDeviceId`-exempted check would let tab B
// through because "the last writer was me" — but tab B's in-memory baseline
// is just as stale as an entirely different device's would be, and must be
// rejected identically.
test('optimistic-concurrency transaction rejects a same-device second tab racing on a stale baseline', async () => {
  const db = ownerDb();
  const claim = claimAndWriteSnapshotForTest(db, OWNER_UID);
  const sharedDeviceId = 'shared-browser-profile-device-id';
  const staleExpectedMeta = { updatedAtMs: null, cloudRevision: null };

  // Tab A (this device) writes first and succeeds.
  await assert.doesNotReject(claim(sharedDeviceId, staleExpectedMeta, 'tab-A-snapshot'));

  const metaAfterTabA = await db.doc(`users/${OWNER_UID}`).get();
  assert.equal(metaAfterTabA.data().lastWriterDeviceId, sharedDeviceId);
  assert.equal(metaAfterTabA.data().cloudRevision, 1);

  // Tab B (same device, same deviceId) is still holding the *original*
  // stale baseline — it never saw tab A's write. Even though
  // `lastWriterDeviceId` on the cloud now matches *its own* device id too,
  // this must still be rejected: the conflict check no longer special-cases
  // "the last writer was this same device".
  await assert.rejects(
    claim(sharedDeviceId, staleExpectedMeta, 'tab-B-snapshot'),
    /WalletSyncConflictError/,
    'a same-device second tab racing on a stale baseline must be rejected, not silently allowed through',
  );

  // Confirm tab B's rejected attempt wrote nothing — tab A's data survives
  // untouched.
  const metaAfterTabB = await db.doc(`users/${OWNER_UID}`).get();
  assert.equal(metaAfterTabB.data().cloudRevision, 1);
  const chunkAfterTabB = await db.doc(`users/${OWNER_UID}/wallet_backups/chunk_0`).get();
  assert.equal(new TextDecoder().decode(chunkAfterTabB.data().data.toUint8Array()), 'tab-A-snapshot');
});

test('optimistic-concurrency transaction: metadata and chunk writes commit atomically together', async () => {
  const db = ownerDb();
  const claim = claimAndWriteSnapshotForTest(db, OWNER_UID);

  await claim('device-A', { updatedAtMs: null, cloudRevision: null }, 'atomic-snapshot');

  // Both the meta bump and the chunk write must be visible together — this
  // is what replaces the old design's separate meta-transaction +
  // chunk-batch pair, which left a window where `updatedAt` claimed a new
  // snapshot existed before its chunks were actually written.
  const meta = await db.doc(`users/${OWNER_UID}`).get();
  const chunk = await db.doc(`users/${OWNER_UID}/wallet_backups/chunk_0`).get();
  assert.ok(meta.exists);
  assert.ok(chunk.exists);
  assert.equal(meta.data().cloudRevision, 1);
  assert.equal(new TextDecoder().decode(chunk.data().data.toUint8Array()), 'atomic-snapshot');
});

test('appUpdates release docs are publicly gettable but not listable or writable', async () => {
  const validRelease = {
    id: 'r1',
    platform: 'android',
    channel: 'stable',
    status: 'published',
    versionName: '1.0.0',
    versionCode: 1,
    runtimeVersion: '1.0.0',
    releaseType: 'patch',
    mandatory: false,
    requirement: 'optional',
    minimumSupportedVersionCode: 0,
    publishedAt: new Date().toISOString(),
    changelog: { newFeatures: [], bugFixes: [], notes: [] },
    apk: {
      downloadUrl: 'https://example.com/app.apk',
      fileName: 'app.apk',
      sizeBytes: 12345,
      sha256: 'a'.repeat(64),
      architecture: 'universal',
    },
  };

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc('appUpdates/android/releases/r1').set(validRelease);
  });

  const anon = anonDb();
  await assertSucceeds(anon.doc('appUpdates/android/releases/r1').get());
  await assertFails(anon.collection('appUpdates/android/releases').get());
  await assertFails(anon.doc('appUpdates/android/releases/r1').set(validRelease));
});
