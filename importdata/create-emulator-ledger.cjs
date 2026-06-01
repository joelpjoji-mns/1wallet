const Module = require('node:module');
const fs = require('node:fs');
const path = require('node:path');

const originalResolveFilename = Module._resolveFilename;
Module._resolveFilename = function resolveWorkspaceSources(request, parent, isMain, options) {
  const workspaceSource = {
    '@1wallet/domain': './packages/domain/src/index.ts',
    '@1wallet/domain/money': './packages/domain/src/money.ts',
    '@1wallet/domain/types': './packages/domain/src/types.ts',
    '@1wallet/validation': './packages/validation/src/index.ts',
  }[request];
  if (workspaceSource) return path.resolve(process.cwd(), workspaceSource);
  return originalResolveFilename.call(this, request, parent, isMain, options);
};

require('sucrase/register');

const { emptyState } = require('../packages/ledger/src/store/types.ts');
const {
  analyzeWalletCsvImport,
  isWalletCsvProposalQueueable,
  provisionWalletCsvEntities,
  walletCsvProposalsToCaptureInputs,
} = require('../packages/ledger/src/import/walletCsv.ts');
const {
  approveCaptureCandidate,
  createCaptureCandidate,
  createImportBatch,
  updateImportBatch,
} = require('../packages/ledger/src/services/index.ts');

const content = fs.readFileSync('import data/wallet_records (1).csv', 'utf8');
const file = { fileName: 'wallet_records (1).csv', content };
const userId = 'local:emulator-import@1wallet.local';
const state = emptyState(userId, 'INR');

const provision = provisionWalletCsvEntities(state, [file]);
const analysis = analyzeWalletCsvImport(state, [file]);
const queueable = analysis.proposals.filter(isWalletCsvProposalQueueable);
const batch = createImportBatch(state, {
  source: 'wallet_csv',
  status: 'queued',
  name: file.fileName,
  fileNames: analysis.files,
  rowCount: analysis.rowCount,
  candidateCount: queueable.length,
  duplicateCount: analysis.summary.duplicates,
  transferPairCount: analysis.summary.transferPairs,
  warningCount: analysis.summary.warnings,
  notes: `${provision.accountsCreated} accounts and ${provision.categoriesCreated} categories created. ${analysis.summary.queueable} queueable, ${analysis.summary.blocked} blocked, ${analysis.summary.duplicates} duplicates, ${analysis.summary.transferPairs} transfer pairs.`,
});

const inputs = walletCsvProposalsToCaptureInputs(analysis.proposals, batch.id);
let queued = 0;
let approved = 0;
let failed = 0;
const failures = [];

for (const input of inputs) {
  const before = state.captureCandidates.length;
  const candidate = createCaptureCandidate(state, input);
  if (state.captureCandidates.length > before) queued += 1;
  try {
    approveCaptureCandidate(state, candidate.id);
    approved += 1;
  } catch (error) {
    failed += 1;
    if (failures.length < 10)
      failures.push({ externalRef: input.externalRef, message: error.message });
  }
}

updateImportBatch(state, batch.id, {
  status: failed ? 'partially_posted' : 'posted',
  candidateCount: queued,
  notes: `${provision.accountsCreated} accounts and ${provision.categoriesCreated} categories created. ${approved} transactions posted, ${analysis.summary.blocked} blocked, ${analysis.summary.duplicates} duplicates, ${analysis.summary.transferPairs} transfer pairs.`,
});

const summary = {
  provision,
  rows: analysis.rowCount,
  proposals: analysis.proposals.length,
  queueable: queueable.length,
  queued,
  approved,
  failed,
  blocked: analysis.summary.blocked,
  duplicates: analysis.summary.duplicates,
  transferPairs: analysis.summary.transferPairs,
  plannedPayments: analysis.summary.plannedPayments,
  transactions: state.transactions.length,
  captureCandidates: state.captureCandidates.length,
  accounts: state.accounts.length,
  categories: state.categories.length,
  failures,
};

fs.mkdirSync('importdata', { recursive: true });
fs.writeFileSync('importdata/emulator-ledger-imported.json', JSON.stringify(state));
fs.writeFileSync(
  'importdata/emulator-ledger-import-summary.json',
  JSON.stringify(summary, null, 2),
);
console.log(JSON.stringify(summary, null, 2));
