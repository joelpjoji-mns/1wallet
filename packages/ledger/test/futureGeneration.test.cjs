const Module = require('node:module');
const path = require('node:path');

const originalResolveFilename = Module._resolveFilename;
Module._resolveFilename = function resolveWorkspaceSources(request, parent, isMain, options) {
  const workspaceSource = {
    '@1wallet/domain': '../../domain/src/index.ts',
    '@1wallet/domain/money': '../../domain/src/money.ts',
    '@1wallet/domain/types': '../../domain/src/types.ts',
    '@1wallet/validation': '../../validation/src/index.ts',
  }[request];
  if (workspaceSource) return path.resolve(__dirname, workspaceSource);
  return originalResolveFilename.call(this, request, parent, isMain, options);
};

require('sucrase/register');

const assert = require('node:assert/strict');
const {
  createAccount,
  createFutureGenerationRule,
  emptyState,
  futureRuleOccurrenceDates,
} = require('../src/index.ts');

function localDate(value) {
  const [year, month, day] = value.split('-').map(Number);
  return new Date(year, month - 1, day);
}

function makeWeeklyRule(input) {
  const state = emptyState('future-rule-user', 'INR');
  const account = createAccount(state, {
    name: 'Bank',
    type: 'bank',
    currency: 'INR',
    openingBalanceMinor: 0,
  });
  return createFutureGenerationRule(state, {
    name: 'Weekly bill',
    type: 'expense',
    accountId: account.id,
    amountMinor: 10000,
    currency: 'INR',
    frequency: 'weekly',
    interval: 1,
    startsOn: '2026-06-01',
    ...input,
  });
}

function dueDates(rule, now, horizonEnd) {
  return futureRuleOccurrenceDates(rule, {
    now: localDate(now),
    horizonEnd: localDate(horizonEnd),
    maxOccurrences: 20,
    includeSkipped: true,
  });
}

const mondayTuesdayRule = makeWeeklyRule({ daysOfWeek: [2, 1] });
assert.deepEqual(mondayTuesdayRule.daysOfWeek, [1, 2]);
assert.deepEqual(dueDates(mondayTuesdayRule, '2026-06-01', '2026-06-16'), [
  '2026-06-01',
  '2026-06-02',
  '2026-06-08',
  '2026-06-09',
  '2026-06-15',
  '2026-06-16',
]);

const midWeekRule = makeWeeklyRule({ startsOn: '2026-06-03', daysOfWeek: [1, 2] });
assert.deepEqual(dueDates(midWeekRule, '2026-06-03', '2026-06-17'), [
  '2026-06-08',
  '2026-06-09',
  '2026-06-15',
  '2026-06-16',
]);

const fortnightlyRule = makeWeeklyRule({ interval: 2, daysOfWeek: [1, 2] });
assert.deepEqual(dueDates(fortnightlyRule, '2026-06-01', '2026-06-30'), [
  '2026-06-01',
  '2026-06-02',
  '2026-06-15',
  '2026-06-16',
  '2026-06-29',
  '2026-06-30',
]);

const limitedRule = makeWeeklyRule({ daysOfWeek: [1, 2], occurrences: 3 });
assert.deepEqual(dueDates(limitedRule, '2026-06-01', '2026-06-30'), [
  '2026-06-01',
  '2026-06-02',
  '2026-06-08',
]);

const legacyRule = makeWeeklyRule({ startsOn: '2026-06-03' });
assert.equal(legacyRule.daysOfWeek, undefined);
assert.deepEqual(dueDates(legacyRule, '2026-06-03', '2026-06-17'), [
  '2026-06-03',
  '2026-06-10',
  '2026-06-17',
]);

console.log('futureGeneration tests passed');
