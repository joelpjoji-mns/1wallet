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
  createCategory,
  createTransaction,
  deleteCategory,
  updateCategory,
} = require('../src/services/index.ts');
const { emptyState } = require('../src/store/types.ts');

const state = emptyState('category-manager-test', 'INR');

const food = createCategory(state, {
  name: 'Food',
  kind: 'expense',
  icon: 'food-fork-drink',
  color: '#315DA8',
});
const dining = createCategory(state, {
  name: 'Dining out',
  kind: 'expense',
  parentId: food.id,
});
const salary = createCategory(state, {
  name: 'Food',
  kind: 'income',
});

assert.equal(food.isArchived, false);
assert.equal(food.isHiddenInStats, false);
assert.equal(dining.parentId, food.id);
assert.equal(salary.kind, 'income');

assert.throws(
  () => createCategory(state, { name: ' food ', kind: 'expense' }),
  /category already exists in this group/,
);
assert.throws(
  () => createCategory(state, { name: 'DINING OUT', kind: 'expense', parentId: food.id }),
  /category already exists in this group/,
);
assert.throws(
  () => updateCategory(state, dining.id, { parentId: dining.id }),
  /category parent cannot be itself/,
);
assert.throws(
  () => updateCategory(state, food.id, { parentId: dining.id }),
  /category parent cannot be a descendant/,
);
assert.throws(
  () => updateCategory(state, dining.id, { kind: 'income' }),
  /category parent must use the same kind/,
);

const hidden = updateCategory(state, dining.id, { isHiddenInStats: true });
assert.equal(hidden.isHiddenInStats, true);
const shown = updateCategory(state, dining.id, { isHiddenInStats: false });
assert.equal(shown.isHiddenInStats, false);

const bank = createAccount(state, {
  name: 'Salary Bank',
  type: 'bank',
  currency: 'INR',
  openingBalanceMinor: 0,
});
createTransaction(state, {
  type: 'expense',
  accountId: bank.id,
  categoryId: dining.id,
  amountMinor: 50000,
  currency: 'INR',
  occurredAt: '2026-06-09T10:00:00.000Z',
  source: 'manual',
});

assert.equal(deleteCategory(state, dining.id), true);
assert.equal(state.categories.find((item) => item.id === dining.id)?.isArchived, true);
assert.ok(state.transactions.some((item) => item.categoryId === dining.id));

const restored = updateCategory(state, dining.id, { isArchived: false });
assert.equal(restored.isArchived, false);

assert.equal(deleteCategory(state, food.id), true);
assert.equal(state.categories.find((item) => item.id === food.id)?.isArchived, true);

const scratch = createCategory(state, { name: 'Temporary', kind: 'expense' });
assert.equal(deleteCategory(state, scratch.id), true);
assert.equal(state.categories.some((item) => item.id === scratch.id), false);

console.log('category manager service tests passed');
