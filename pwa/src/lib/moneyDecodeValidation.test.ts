import { test } from 'node:test';
import assert from 'node:assert/strict';
import { moneyFromJson } from './ledgerCodec.ts';

test('money decoding rejects corrupt or fractional minor units', () => {
  for (const amountMinor of ['bad', 1.5, Number.NaN, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => moneyFromJson({ amountMinor, currency: 'USD' }), /integer/);
  }
  assert.deepEqual(moneyFromJson({ amountMinor: '123', currency: 'USD' }),
    { amountMinor: 123, currency: 'USD' });
});
