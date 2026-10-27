import { test } from 'node:test';
import assert from 'node:assert/strict';
import { canClaimDeletion, executeDeletion, receiptHash, sameReceipt } from '../lib/deletion-job.js';

test('auth is removed only after recursive wallet deletion succeeds', async () => {
  const seen = [];
  await executeDeletion({
    stage: async value => { seen.push(value); },
    removeWallet: async () => { seen.push('wallet-removed'); },
    removeAuth: async () => { seen.push('auth-removed'); },
  });
  assert.deepEqual(seen, ['firestore', 'wallet-removed', 'auth', 'auth-removed', 'complete']);
});

test('a wallet deletion failure cannot remove credentials or report completion', async () => {
  const seen = [];
  await assert.rejects(executeDeletion({
    stage: async value => { seen.push(value); },
    removeWallet: async () => { throw new Error('injected-storage-failure'); },
    removeAuth: async () => { seen.push('auth-removed'); },
  }), /injected-storage-failure/);
  assert.deepEqual(seen, ['firestore']);
});

test('receipt validation and comparison do not accept malformed capabilities', () => {
  assert.throws(() => receiptHash('short'), /invalid-receipt/);
  const hash = receiptHash('A'.repeat(43));
  assert.equal(hash.length, 64);
  assert.equal(sameReceipt(hash, hash), true);
  assert.equal(sameReceipt(hash, receiptHash('B'.repeat(43))), false);
});

test('active leases cannot be stolen, expired work resumes, and completion is terminal', () => {
  assert.throws(() => canClaimDeletion('firestore', 101, 100), /already-running/);
  assert.equal(canClaimDeletion('firestore', 100, 100), true);
  assert.equal(canClaimDeletion('failed', 0, 100), true);
  assert.equal(canClaimDeletion('complete', 0, 100), false);
  assert.throws(() => canClaimDeletion('unknown', 0, 100), /invalid-job-stage/);
});

test('credential deletion failure never publishes completion and can be retried idempotently', async () => {
  const stages = [];
  let fail = true;
  const effects = {
    stage: async value => { stages.push(value); },
    removeWallet: async () => {},
    removeAuth: async () => { if (fail) throw new Error('injected-auth-failure'); },
  };
  await assert.rejects(executeDeletion(effects), /injected-auth-failure/);
  assert.deepEqual(stages, ['firestore', 'auth']);
  fail = false;
  await executeDeletion(effects);
  assert.equal(stages.at(-1), 'complete');
});
