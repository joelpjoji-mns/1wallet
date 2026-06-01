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

const { normalizeCurrencyCode } = require('../packages/domain/src/money.ts');
const {
  exportOneWalletArchive,
  summarizeLedgerState,
  validateOneWalletArchive,
} = require('../packages/ledger/src/archive/onewalletArchive.ts');
const {
  analyzeWalletCsvImport,
  isWalletCsvProposalQueueable,
  provisionWalletCsvEntities,
  walletCsvBlockedReason,
  walletCsvProposalsToCaptureInputs,
} = require('../packages/ledger/src/import/walletCsv.ts');
const {
  buildLoanPlannedPaymentInput,
  loanRuleTag,
  syncLoanDetailsFromRule,
} = require('../packages/ledger/src/loans.ts');
const {
  createFutureGenerationRule,
  futureRuleExternalRef,
  futureRuleInterestExternalRef,
  plannedPaymentRuleStats,
  postFutureRuleOccurrence,
} = require('../packages/ledger/src/rules/futureGeneration.ts');
const { seedDefaultCategories } = require('../packages/ledger/src/seed.ts');
const {
  accountBalance,
  approveCaptureCandidate,
  createAccount,
  createCaptureCandidate,
  createImportBatch,
  updateAccount,
  updateImportBatch,
  updateTransaction,
} = require('../packages/ledger/src/services/index.ts');
const { emptyState } = require('../packages/ledger/src/store/types.ts');

const CONFIG_PATH = 'importdata/legacy-migration-config.json';
const LEGACY_TAG = 'legacy-wallet-csv';
const DAY_MS = 24 * 60 * 60 * 1000;

function main() {
  const config = readJson(CONFIG_PATH);
  const now = validDate(config.now) ?? new Date();
  const sourceCsv = config.sourceCsv ?? 'import data/wallet_records (1).csv';
  const content = fs.readFileSync(sourceCsv, 'utf8');
  const file = { fileName: path.basename(sourceCsv), content };
  const state = emptyState(
    config.userId ?? 'firebase:pending-google-user',
    config.baseCurrency ?? 'INR',
  );
  state.preferences.displayCurrency = normalizeCurrencyCode(
    config.displayCurrency ?? config.baseCurrency ?? 'INR',
  );
  state.preferences.locale = config.locale ?? 'en-IN';
  state.preferences.enabledCurrencies = uniqueStrings([
    ...(state.preferences.enabledCurrencies ?? []),
    state.preferences.baseCurrency,
    state.preferences.displayCurrency,
    'GBP',
  ]);
  if (config.profile)
    state.preferences.profile = { ...state.preferences.profile, ...config.profile };

  const categoriesSeeded = seedDefaultCategories(state);
  const provision = provisionWalletCsvEntities(state, [file]);
  const analysis = analyzeWalletCsvImport(state, [file], { now });
  const loanSetups = createLoanAccountsAndRules(state, config.loanAccounts ?? []);
  const seedRuleLinks = createSeedPlannedPaymentRules(state, config.plannedPaymentSeeds ?? []);
  const detectedRuleLinks = createDetectedPlannedPaymentRules(
    state,
    analysis.plannedPayments,
    loanSetups,
    config.detectedPlannedPayments ?? {},
  );

  const importResult = importCsvTransactions(state, analysis, provision, file, {
    detectedCandidates: detectedRuleLinks.linkableCandidates,
    ruleIdsByKey: detectedRuleLinks.ruleIdsByKey,
    loanAccountIdsByKey: detectedRuleLinks.loanAccountIdsByKey,
  });

  const detectedHistoryLinks = linkDetectedPlannedPaymentHistory(
    state,
    detectedRuleLinks.createdRules,
    config.detectedPlannedPayments ?? {},
  );
  const seedHistoryLinks = linkSeedPlannedPaymentHistory(state, seedRuleLinks);
  const loanHistory = reconcileLoanHistory(state, loanSetups, now);
  const accountReconciliation = applyAccountOverrides(state, config.accountOverrides ?? []);
  normalizeAccountSortOrder(state);

  const archive = exportOneWalletArchive(state, {
    source: 'unknown',
    exportedAt: new Date().toISOString(),
  });
  const validation = validateOneWalletArchive(archive);
  const summary = buildSummary(state, archive, validation, {
    categoriesSeeded,
    provision,
    analysis,
    importResult,
    seedRuleLinks,
    detectedRuleLinks,
    detectedHistoryLinks,
    seedHistoryLinks,
    loanHistory,
    accountReconciliation,
  });
  const review = buildReview(state, validation, {
    analysis,
    detectedRuleLinks,
    loanHistory,
    accountReconciliation,
  });

  writeJson(config.outputs?.ledger ?? 'importdata/google-migration-ledger.json', state);
  writeJson(config.outputs?.archive ?? 'importdata/google-migration.onewallet.json', archive, 2);
  writeJson(config.outputs?.summary ?? 'importdata/google-migration-summary.json', summary, 2);
  writeJson(config.outputs?.review ?? 'importdata/google-migration-review.json', review, 2);

  console.log(JSON.stringify(summary, null, 2));
  if (!validation.ok) process.exitCode = 1;
}

function importCsvTransactions(state, analysis, provision, file, links) {
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
  const inputs = walletCsvProposalsToCaptureInputs(analysis.proposals, batch.id, {
    plannedPayments: links.detectedCandidates,
    ruleIdsByPlannedPaymentKey: links.ruleIdsByKey,
    loanAccountIdsByPlannedPaymentKey: links.loanAccountIdsByKey,
  });
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
      if (failures.length < 25) {
        failures.push({ externalRef: input.externalRef, message: error.message });
      }
    }
  }

  updateImportBatch(state, batch.id, {
    status: failed ? 'partially_posted' : 'posted',
    candidateCount: queued,
    notes: `${approved} transactions posted, ${analysis.summary.blocked} blocked, ${analysis.summary.duplicates} duplicates, ${analysis.summary.transferPairs} transfer pairs.`,
  });

  return { batchId: batch.id, queueable: queueable.length, queued, approved, failed, failures };
}

function createLoanAccountsAndRules(state, loanConfigs) {
  const setups = [];
  for (const loanConfig of loanConfigs) {
    const sourceAccount = findAccountByName(state, loanConfig.repaymentSourceAccount);
    if (!sourceAccount) {
      setups.push({
        config: loanConfig,
        error: `Missing repayment source account ${loanConfig.repaymentSourceAccount}`,
      });
      continue;
    }

    const currency = normalizeCurrencyCode(loanConfig.currency ?? sourceAccount.currency);
    const currentOutstandingMinor = Math.abs(
      loanConfig.currentOutstandingMinor ?? loanConfig.principalMinor ?? 0,
    );
    const nowIso = new Date().toISOString();
    const details = {
      loanKind: loanConfig.loanKind ?? 'other',
      principal: {
        amountMinor: Math.abs(loanConfig.principalMinor ?? currentOutstandingMinor),
        currency,
      },
      disbursedOn: loanConfig.disbursedOn,
      interestRatePercent: loanConfig.interestRatePercent,
      interestRatePeriod: loanConfig.interestRatePeriod ?? 'annual',
      interestMethod: loanConfig.interestMethod ?? 'reducing_balance',
      repaymentSourceAccountId: sourceAccount.id,
      repaymentAmount: { amountMinor: Math.abs(loanConfig.emiMinor ?? 0), currency },
      repaymentStartsOn: loanConfig.repaymentStartsOn,
      repaymentFrequency: 'monthly',
      repaymentInterval: 1,
      repaymentDayOfMonth: loanConfig.dayOfMonth,
      repaymentCount: loanConfig.repaymentCount,
      autoCreateScheduledRecords: true,
      trackingStartsOn: loanConfig.trackingStartsOn ?? loanConfig.repaymentStartsOn,
      paidInstallmentsBeforeTracking: loanConfig.paidInstallmentsBeforeTracking ?? 0,
      setupMode: 'backfill_paid',
      notes: loanConfig.fixedRate
        ? `${loanConfig.name} fixed-rate EMI migration`
        : `${loanConfig.name} EMI migration`,
    };
    const loanAccount = createAccount(state, {
      name: loanConfig.name,
      type: loanConfig.type ?? 'loan',
      currency,
      openingBalanceMinor: -currentOutstandingMinor,
      openingDate: loanConfig.disbursedOn ?? loanConfig.repaymentStartsOn,
      icon: loanConfig.loanKind === 'education' ? 'school-outline' : 'bank-outline',
      color: loanConfig.color ?? (loanConfig.loanKind === 'education' ? '#7C3AED' : '#334155'),
      institution: loanConfig.institution,
      loanDetails: details,
      includeInTotals: loanConfig.includeInTotals ?? false,
      includeInBudgets: false,
      includeInReports: loanConfig.includeInReports ?? false,
      includeInNetWorth: loanConfig.includeInNetWorth ?? false,
      showOnHome: loanConfig.showOnHome ?? true,
      groupName: 'Loans',
      notes: `Migrated loan: ${loanConfig.name}.`,
    });
    if (Number.isFinite(loanConfig.sortOrder)) {
      updateAccount(state, loanAccount.id, { sortOrder: loanConfig.sortOrder });
    }
    const ruleInput = buildLoanPlannedPaymentInput(loanAccount, details, [
      LEGACY_TAG,
      loanRuleTag(loanAccount.id),
    ]);
    if (!ruleInput) {
      setups.push({
        config: loanConfig,
        sourceAccount,
        loanAccount,
        error: 'Could not build loan planned payment rule',
      });
      continue;
    }
    const rule = createFutureGenerationRule(state, {
      ...ruleInput,
      name: loanConfig.ruleName ?? `${loanConfig.name} EMI`,
      startsOn: loanConfig.trackingStartsOn ?? loanConfig.repaymentStartsOn,
      dayOfMonth: loanConfig.dayOfMonth,
      occurrences: loanConfig.repaymentCount,
      skippedOccurrences: uniqueStrings([
        ...(ruleInput.skippedOccurrences ?? []),
        ...(loanConfig.skippedOccurrences ?? []),
      ]),
      notes: details.notes,
      tags: uniqueStrings([...(ruleInput.tags ?? []), LEGACY_TAG, `legacy-loan:${loanConfig.key}`]),
    });
    syncLoanDetailsFromRule(state, rule);
    setups.push({
      config: loanConfig,
      sourceAccount,
      loanAccount,
      rule,
      currentOutstandingMinor,
      createdAt: nowIso,
    });
  }
  return setups;
}

function createSeedPlannedPaymentRules(state, seeds) {
  const links = [];
  for (const seed of seeds) {
    const account = findAccountByName(state, seed.account);
    const counterAccount = seed.counterAccount
      ? findAccountByName(state, seed.counterAccount)
      : undefined;
    const category = seed.category
      ? findCategoryByName(state, seed.category, seed.type === 'income' ? 'income' : 'expense')
      : undefined;
    if (!account) {
      links.push({ seed, error: `Missing account ${seed.account}` });
      continue;
    }
    const rule = createFutureGenerationRule(state, {
      name: seed.name,
      kind: seed.kind,
      postMode: seed.postMode ?? 'manual',
      type: seed.type,
      accountId: account.id,
      counterAccountId: counterAccount?.id,
      categoryId: category?.id,
      amountMinor: seed.amountMinor,
      currency: seed.currency ?? account.currency,
      frequency: seed.frequency ?? 'monthly',
      interval: seed.interval ?? 1,
      dayOfMonth: seed.dayOfMonth,
      startsOn: seed.startsOn,
      endsOn: seed.endsOn,
      occurrences: seed.occurrences,
      paymentMethod: seed.paymentMethod,
      notes: seed.notes ?? 'Seeded from old-app planned payment screenshot.',
      tags: uniqueStrings([...(seed.tags ?? []), LEGACY_TAG, 'legacy-screenshot-plan']),
      enabled: seed.enabled ?? true,
    });
    links.push({ seed, rule });
  }
  return links;
}

function createDetectedPlannedPaymentRules(state, candidates, loanSetups, options) {
  const includeActivities = new Set(options.includeActivities ?? ['active', 'needs_review']);
  const skipKinds = new Set(options.skipKinds ?? []);
  const createdRules = [];
  const ruleIdsByKey = {};
  const loanAccountIdsByKey = {};
  const linkableCandidates = [];
  const limit = Number.isFinite(options.limit)
    ? Math.max(0, options.limit)
    : Number.POSITIVE_INFINITY;

  for (const candidate of candidates) {
    if (createdRules.length >= limit) break;
    if (!includeActivities.has(candidate.activity)) continue;
    if (skipKinds.has(candidate.kind)) continue;
    if (!candidate.accountId) continue;

    const matchedLoanSetup =
      candidate.type === 'loan_repayment'
        ? findLoanSetupForCandidate(candidate, loanSetups)
        : undefined;
    if (matchedLoanSetup?.rule) {
      ruleIdsByKey[candidate.key] = matchedLoanSetup.rule.id;
      linkableCandidates.push(candidate);
      createdRules.push({ candidate, rule: matchedLoanSetup.rule, source: 'loan' });
      continue;
    }

    if (candidate.type === 'loan_repayment' && !matchedLoanSetup) continue;
    if (
      (candidate.type === 'transfer' || candidate.type === 'card_payment') &&
      !candidate.counterAccountId
    )
      continue;
    const rule = createFutureGenerationRule(state, {
      name: candidate.name,
      kind: candidate.kind,
      postMode: 'manual',
      type: candidate.type,
      accountId: candidate.accountId,
      counterAccountId: candidate.counterAccountId,
      categoryId: candidate.categoryId,
      amountMinor: candidate.latestAmountMinor || candidate.amountMinor,
      currency: candidate.currency,
      frequency: candidate.frequency,
      interval: candidate.interval,
      dayOfMonth: candidate.dayOfMonth,
      startsOn: candidate.startsOn,
      paymentMethod: candidate.paymentMethod,
      notes: `Detected from Wallet CSV. Last seen ${candidate.lastSeenOn}. ${candidate.activityReason}`,
      tags: uniqueStrings([...(candidate.tags ?? []), LEGACY_TAG, `legacy-plan:${candidate.key}`]),
      enabled: true,
    });
    ruleIdsByKey[candidate.key] = rule.id;
    linkableCandidates.push(candidate);
    createdRules.push({ candidate, rule, source: 'detected' });
  }

  return { createdRules, ruleIdsByKey, loanAccountIdsByKey, linkableCandidates };
}

function linkDetectedPlannedPaymentHistory(state, createdRuleLinks, options) {
  const rewriteExternalRefs = options.rewriteExternalRefs === true;
  const linked = [];
  let total = 0;
  for (const link of createdRuleLinks) {
    if (link.source === 'loan') continue;
    const candidate = link.candidate;
    const rule = link.rule;
    if (!candidate?.sourceRows?.length || !rule) continue;
    let ruleLinked = 0;
    for (const rowRef of candidate.sourceRows) {
      const transaction = transactionForWalletCsvRow(
        state,
        rowRef.fileName,
        rowRef.rowNumber,
        rowRef.pairedRowNumber,
      );
      if (!transaction) continue;
      if (transaction.type !== rule.type) continue;
      transaction.recurringTemplateId = rule.id;
      if (rewriteExternalRefs) {
        const dueOn = rowRef.occurredOn || dateOnly(transaction.occurredAt);
        const externalRef = futureRuleExternalRef(rule.id, dueOn);
        if (
          !state.transactions.some(
            (item) => item.id !== transaction.id && item.externalRef === externalRef,
          )
        ) {
          transaction.externalRef = externalRef;
        }
      }
      transaction.updatedAt = new Date().toISOString();
      ruleLinked += 1;
      total += 1;
    }
    linked.push({ ruleId: rule.id, name: rule.name, source: link.source, linked: ruleLinked });
  }
  return { total, linked };
}

function linkSeedPlannedPaymentHistory(state, seedRuleLinks) {
  const linked = [];
  let total = 0;
  for (const link of seedRuleLinks) {
    if (!link.rule || !link.seed?.historyMatch) continue;
    const matches = transactionsForHistoryMatch(state, link.seed.historyMatch, link.rule);
    for (const transaction of matches) {
      transaction.recurringTemplateId = link.rule.id;
      transaction.updatedAt = new Date().toISOString();
    }
    linked.push({ ruleId: link.rule.id, name: link.rule.name, linked: matches.length });
    total += matches.length;
  }
  return { total, linked };
}

function reconcileLoanHistory(state, loanSetups, now) {
  const results = [];
  for (const setup of loanSetups) {
    if (!setup.rule || !setup.loanAccount || !setup.sourceAccount) {
      results.push({
        key: setup.config?.key,
        name: setup.config?.name,
        error: setup.error ?? 'Loan not configured',
      });
      continue;
    }
    const schedule = buildLoanSchedule(setup.config);
    const matches = findLoanPaymentTransactions(state, setup, now);
    const assigned = assignLoanScheduleRows(matches, schedule, setup.config.maxDateDriftDays ?? 20);
    const principalTotal = assigned.reduce((sum, item) => sum + item.row.principalMinor, 0);
    setup.loanAccount.openingBalance = {
      amountMinor: -(setup.currentOutstandingMinor + principalTotal),
      currency: setup.loanAccount.currency,
    };
    setup.loanAccount.loanDetails = {
      ...setup.loanAccount.loanDetails,
      paidInstallmentsBeforeTracking: assigned.length,
      linkedPlannedPaymentRuleId: setup.rule.id,
    };

    let transformed = 0;
    for (const item of assigned) {
      const transaction = item.transaction;
      const dueOn = item.row.dueOn;
      const externalRef = futureRuleExternalRef(setup.rule.id, dueOn);
      updateTransaction(state, transaction.id, {
        type: 'loan_repayment',
        accountId: setup.sourceAccount.id,
        counterAccountId: setup.loanAccount.id,
        amountMinor: transaction.amount.amountMinor,
        currency: transaction.amount.currency,
        counterAmountMinor: item.row.principalMinor,
        counterCurrency: setup.loanAccount.currency,
        categoryId: null,
        recurringTemplateId: setup.rule.id,
        externalRef,
        notes: transaction.notes ?? `${setup.config.name} EMI`,
        paymentMethod: transaction.paymentMethod ?? 'Auto debit',
        isExcludedFromReports: true,
      });
      const postedTransaction = postFutureRuleOccurrence(
        state,
        setup.rule,
        loanOccurrenceForRow(setup, item.row, transaction),
        {
          amountMinor: transaction.amount.amountMinor,
          currency: transaction.amount.currency,
          occurredAt: transaction.occurredAt,
          paymentMethod: transaction.paymentMethod ?? 'Auto debit',
          notes: transaction.notes ?? `${setup.config.name} EMI`,
          tags: uniqueStrings([
            ...(transaction.tags ?? []),
            LEGACY_TAG,
            `legacy-loan:${setup.config.key}`,
          ]),
          status: transaction.status,
        },
      );
      updateTransaction(state, postedTransaction.id, { isExcludedFromReports: true });
      const interestExternalRef = futureRuleInterestExternalRef(externalRef);
      const interestTransaction = state.transactions.find(
        (candidate) => candidate.externalRef === interestExternalRef,
      );
      if (interestTransaction) {
        updateTransaction(state, interestTransaction.id, { isExcludedFromReports: true });
      }
      transformed += 1;
    }
    syncLoanDetailsFromRule(state, setup.rule);
    results.push({
      key: setup.config.key,
      name: setup.config.name,
      loanAccountId: setup.loanAccount.id,
      ruleId: setup.rule.id,
      matched: matches.length,
      transformed,
      principalBackfilledMinor: principalTotal,
      targetOutstandingMinor: setup.currentOutstandingMinor,
      finalBalance: accountBalance(state, setup.loanAccount.id),
      skippedMatches: matches.length - assigned.length,
    });
  }
  return results;
}

function loanOccurrenceForRow(setup, row, transaction) {
  return {
    ruleId: setup.rule.id,
    dueOn: row.dueOn,
    occurredAt: transaction.occurredAt,
    externalRef: futureRuleExternalRef(setup.rule.id, row.dueOn),
    type: 'loan_repayment',
    accountId: setup.sourceAccount.id,
    counterAccountId: setup.loanAccount.id,
    amountMinor: row.paymentMinor,
    currency: transaction.amount.currency,
    principalAmountMinor: row.principalMinor,
    principalCurrency: setup.loanAccount.currency,
    interestAmountMinor: row.interestMinor,
    interestCurrency: transaction.amount.currency,
    loanAccountId: setup.loanAccount.id,
    loanIsLent: false,
    counterAmountMinor: row.principalMinor,
    counterCurrency: setup.loanAccount.currency,
    paymentMethod: transaction.paymentMethod ?? 'Auto debit',
    notes: transaction.notes ?? `${setup.config.name} EMI`,
    tags: uniqueStrings([
      ...(transaction.tags ?? []),
      LEGACY_TAG,
      `legacy-loan:${setup.config.key}`,
    ]),
  };
}

function findLoanPaymentTransactions(state, setup, now) {
  const config = setup.config;
  const sourceAccount = setup.sourceAccount;
  const toleranceMinor = config.amountToleranceMinor ?? 100;
  const startDate = dateOnly(config.repaymentStartsOn ?? config.trackingStartsOn ?? '1900-01-01');
  const endDate = dateOnly(now.toISOString());
  const matches = [];
  for (const transaction of state.transactions) {
    if (transaction.status !== 'cleared' && transaction.status !== 'pending') continue;
    if (transaction.accountId !== sourceAccount.id) continue;
    if (!['expense', 'fee', 'loan_repayment'].includes(transaction.type)) continue;
    if (Math.abs(transaction.amount.amountMinor - config.emiMinor) > toleranceMinor) continue;
    const occurredOn = dateOnly(transaction.occurredAt);
    if (occurredOn < startDate || occurredOn > endDate) continue;
    if (
      !config.allowAmountOnlyMatch &&
      !textMatchesTerms(transactionText(transaction), config.matchTerms ?? [])
    )
      continue;
    if (transaction.counterAccountId && transaction.counterAccountId !== setup.loanAccount.id)
      continue;
    matches.push(transaction);
  }
  return matches.sort((left, right) => left.occurredAt.localeCompare(right.occurredAt));
}

function assignLoanScheduleRows(transactions, schedule, maxDateDriftDays) {
  const usedRows = new Set();
  const assigned = [];
  for (const transaction of transactions) {
    const occurredOn = parseDateOnly(dateOnly(transaction.occurredAt));
    if (!occurredOn) continue;
    let bestRow;
    let bestDiff = Number.POSITIVE_INFINITY;
    for (const row of schedule) {
      if (usedRows.has(row.installment)) continue;
      const dueDate = parseDateOnly(row.dueOn);
      const diff = dueDate ? Math.abs(daysBetween(occurredOn, dueDate)) : Number.POSITIVE_INFINITY;
      if (diff < bestDiff) {
        bestDiff = diff;
        bestRow = row;
      }
    }
    if (!bestRow || bestDiff > maxDateDriftDays) continue;
    usedRows.add(bestRow.installment);
    assigned.push({ transaction, row: bestRow, dateDriftDays: bestDiff });
  }
  return assigned;
}

function buildLoanSchedule(config) {
  const rows = [];
  const principalMinor = Math.abs(config.principalMinor ?? config.currentOutstandingMinor ?? 0);
  const paymentMinor = Math.abs(config.emiMinor ?? 0);
  const count = Math.min(Math.max(config.repaymentCount ?? 0, 0), 1200);
  const monthlyRate = Math.max(config.interestRatePercent ?? 0, 0) / 100 / 12;
  const startsOn = parseDateOnly(config.trackingStartsOn ?? config.repaymentStartsOn);
  if (!startsOn || principalMinor <= 0 || paymentMinor <= 0 || count <= 0) return rows;
  let balanceMinor = principalMinor;
  for (let installment = 1; installment <= count; installment += 1) {
    const dueOn = toDateOnly(
      addMonthsClamped(startsOn, installment - 1, config.dayOfMonth ?? startsOn.getDate()),
    );
    const interestBase = config.interestMethod === 'flat' ? principalMinor : balanceMinor;
    const interestMinor = Math.max(0, Math.round(interestBase * monthlyRate));
    const amountDueMinor = balanceMinor + interestMinor;
    const paymentForRowMinor = Math.min(paymentMinor, amountDueMinor);
    const principalForRowMinor = Math.max(
      0,
      Math.min(paymentForRowMinor - interestMinor, balanceMinor),
    );
    balanceMinor = Math.max(0, amountDueMinor - paymentForRowMinor);
    rows.push({
      installment,
      dueOn,
      paymentMinor: paymentForRowMinor,
      interestMinor,
      principalMinor: principalForRowMinor,
      balanceAfterMinor: balanceMinor,
    });
    if (balanceMinor <= 0) break;
  }
  return rows;
}

function applyAccountOverrides(state, overrides) {
  const results = [];
  for (const override of overrides) {
    const account = findAccountByName(state, override.matchName);
    if (!account) {
      results.push({ matchName: override.matchName, error: 'Account not found' });
      continue;
    }
    updateAccount(state, account.id, {
      name: override.name ?? account.name,
      type: override.type ?? account.type,
      icon: override.icon ?? account.icon,
      color: override.color ?? account.color,
      institution: override.institution ?? account.institution,
      sortOrder: override.sortOrder ?? account.sortOrder,
      includeInTotals: override.includeInTotals ?? account.includeInTotals,
      includeInBudgets: override.includeInBudgets ?? account.includeInBudgets,
      includeInReports: override.includeInReports ?? account.includeInReports,
      includeInNetWorth: override.includeInNetWorth ?? account.includeInNetWorth,
      showOnHome: override.showOnHome ?? account.showOnHome,
      groupName: override.groupName ?? account.groupName,
      notes: override.notes ?? account.notes,
    });
    const before = accountBalance(state, account.id);
    let openingDeltaMinor = 0;
    if (override.targetBalanceMinor !== null && override.targetBalanceMinor !== undefined) {
      openingDeltaMinor = override.targetBalanceMinor - before.amountMinor;
      account.openingBalance = {
        amountMinor: account.openingBalance.amountMinor + openingDeltaMinor,
        currency: account.currency,
      };
      account.updatedAt = new Date().toISOString();
    }
    const after = accountBalance(state, account.id);
    results.push({
      accountId: account.id,
      name: account.name,
      type: account.type,
      currency: account.currency,
      sortOrder: account.sortOrder,
      targetBalanceMinor: override.targetBalanceMinor,
      beforeBalanceMinor: before.amountMinor,
      openingDeltaMinor,
      finalBalanceMinor: after.amountMinor,
    });
  }
  return results;
}

function normalizeAccountSortOrder(state) {
  state.accounts.sort(
    (left, right) => left.sortOrder - right.sortOrder || left.name.localeCompare(right.name),
  );
  state.accounts.forEach((account, index) => {
    account.sortOrder = index;
  });
}

function buildSummary(state, archive, validation, details) {
  const archiveSummary = summarizeLedgerState(state);
  const loanSummary = details.loanHistory.map((loan) => ({
    key: loan.key,
    name: loan.name,
    matched: loan.matched ?? 0,
    transformed: loan.transformed ?? 0,
    finalBalance: loan.finalBalance,
    error: loan.error,
  }));
  return {
    ok: validation.ok,
    outputs: {
      ledger: 'importdata/google-migration-ledger.json',
      archive: 'importdata/google-migration.onewallet.json',
      summary: 'importdata/google-migration-summary.json',
      review: 'importdata/google-migration-review.json',
    },
    validation: {
      errors: validation.errors,
      warnings: validation.warnings,
      checksum: archive.checksum,
    },
    archive: archiveSummary,
    csv: {
      rows: details.analysis.rowCount,
      proposals: details.analysis.proposals.length,
      queueable: details.analysis.summary.queueable,
      blocked: details.analysis.summary.blocked,
      duplicates: details.analysis.summary.duplicates,
      transferPairs: details.analysis.summary.transferPairs,
      detectedPlannedPayments: details.analysis.plannedPayments.length,
      provision: details.provision,
      categoriesSeeded: details.categoriesSeeded,
      import: details.importResult,
    },
    plannedPayments: {
      totalRules: state.preferences.futureGenerationRules?.length ?? 0,
      seedRules: details.seedRuleLinks.filter((link) => link.rule).length,
      detectedRules: details.detectedRuleLinks.createdRules.filter(
        (link) => link.source === 'detected',
      ).length,
      loanRules: details.loanHistory.filter((loan) => !loan.error).length,
      loanCandidateLinks: details.detectedRuleLinks.createdRules.filter(
        (link) => link.source === 'loan',
      ).length,
      detectedHistoryLinked: details.detectedHistoryLinks.total,
      seedHistoryLinked: details.seedHistoryLinks.total,
    },
    loans: loanSummary,
    accounts: state.accounts.map((account) => ({
      name: account.name,
      type: account.type,
      currency: account.currency,
      balance: accountBalance(state, account.id),
      sortOrder: account.sortOrder,
    })),
  };
}

function buildReview(state, validation, details) {
  const blocked = details.analysis.proposals
    .filter((proposal) => !isWalletCsvProposalQueueable(proposal))
    .map((proposal) => ({
      reason: walletCsvBlockedReason(proposal),
      rowNumbers: proposal.rowNumbers,
      account: proposal.sourceRow.accountName,
      category: proposal.sourceRow.categoryName,
      type: proposal.suggestedType,
      amountMinor: proposal.amountMinor,
      currency: proposal.currency,
      occurredAt: proposal.parsedOccurredAt,
      payee: proposal.sourceRow.payee,
      note: proposal.sourceRow.note,
      warnings: proposal.warnings,
      duplicate: proposal.duplicate,
    }));
  return {
    validation,
    blockedRows: blocked,
    detectedPlannedPayments: details.analysis.plannedPayments.map((candidate) => ({
      key: candidate.key,
      name: candidate.name,
      kind: candidate.kind,
      type: candidate.type,
      accountName: candidate.accountName,
      counterAccountName: candidate.counterAccountName,
      categoryName: candidate.categoryName,
      amountMinor: candidate.latestAmountMinor,
      currency: candidate.currency,
      frequency: candidate.frequency,
      interval: candidate.interval,
      dayOfMonth: candidate.dayOfMonth,
      startsOn: candidate.startsOn,
      lastSeenOn: candidate.lastSeenOn,
      nextDueOn: candidate.nextDueOn,
      activity: candidate.activity,
      activityReason: candidate.activityReason,
      confidence: candidate.confidence,
      warnings: candidate.warnings,
      sourceRows: candidate.sourceRows.slice(0, 20),
      linkedRuleId: details.detectedRuleLinks.ruleIdsByKey[candidate.key],
    })),
    loanHistory: details.loanHistory,
    accountReconciliation: details.accountReconciliation,
    finalAccountBalances: state.accounts.map((account) => ({
      accountId: account.id,
      name: account.name,
      type: account.type,
      currency: account.currency,
      openingBalance: account.openingBalance,
      finalBalance: accountBalance(state, account.id),
      sortOrder: account.sortOrder,
    })),
    ruleStats: (state.preferences.futureGenerationRules ?? []).map((rule) => ({
      ruleId: rule.id,
      name: rule.name,
      kind: rule.kind,
      type: rule.type,
      amountMinor: rule.amountMinor,
      currency: rule.currency,
      startsOn: rule.startsOn,
      occurrences: rule.occurrences,
      stats: plannedPaymentRuleStats(state, rule),
    })),
  };
}

function transactionForWalletCsvRow(state, fileName, rowNumber, pairedRowNumber) {
  for (const candidate of state.captureCandidates) {
    const rows = Array.isArray(candidate.rawPayload?.rowRefs) ? candidate.rawPayload.rowRefs : [];
    const matches = rows.some(
      (rowRef) =>
        rowRef.fileName === fileName &&
        (rowRef.rowNumber === rowNumber || rowRef.rowNumber === pairedRowNumber),
    );
    if (!matches || !candidate.postedTransactionId) continue;
    const transaction = state.transactions.find(
      (item) => item.id === candidate.postedTransactionId,
    );
    if (transaction) return transaction;
  }
  return undefined;
}

function transactionsForHistoryMatch(state, match, rule) {
  const account = match.account ? findAccountByName(state, match.account) : undefined;
  const category = match.category
    ? findCategoryByName(state, match.category, rule.type === 'income' ? 'income' : 'expense')
    : undefined;
  const toleranceMinor = match.amountToleranceMinor ?? 100;
  return state.transactions.filter((transaction) => {
    if (transaction.recurringTemplateId) return false;
    if (transaction.type !== rule.type) return false;
    if (account && transaction.accountId !== account.id) return false;
    if (category && transaction.categoryId !== category.id) return false;
    if (
      match.amountMinor !== undefined &&
      Math.abs(transaction.amount.amountMinor - match.amountMinor) > toleranceMinor
    )
      return false;
    const occurredOn = dateOnly(transaction.occurredAt);
    if (match.from && occurredOn < match.from) return false;
    if (match.to && occurredOn > match.to) return false;
    if (
      match.textIncludes?.length &&
      !textMatchesTerms(transactionText(transaction), match.textIncludes)
    )
      return false;
    return true;
  });
}

function findLoanSetupForCandidate(candidate, loanSetups) {
  return loanSetups.find((setup) => {
    if (!setup.rule || !setup.sourceAccount) return false;
    const config = setup.config;
    const amountMatch =
      Math.abs((candidate.latestAmountMinor || candidate.amountMinor) - config.emiMinor) <=
      (config.amountToleranceMinor ?? 100);
    const accountMatch =
      normalizeName(candidate.accountName) === normalizeName(setup.sourceAccount.name);
    const text = normalizeName(
      [
        candidate.name,
        candidate.categoryName,
        candidate.counterAccountName,
        ...candidate.sourceRows.flatMap((row) => [row.note, row.payee]),
      ]
        .filter(Boolean)
        .join(' '),
    );
    const termMatch = (config.matchTerms ?? []).some((term) => text.includes(normalizeName(term)));
    return amountMatch && accountMatch && (termMatch || config.allowAmountOnlyMatch === true);
  });
}

function findAccountByName(state, name) {
  const normalized = normalizeName(name);
  return state.accounts.find((account) => normalizeName(account.name) === normalized);
}

function findCategoryByName(state, name, kind) {
  const normalized = normalizeName(name);
  return state.categories.find(
    (category) => normalizeName(category.name) === normalized && (!kind || category.kind === kind),
  );
}

function transactionText(transaction) {
  return [transaction.notes, transaction.paymentMethod, transaction.tags?.join(' ')]
    .filter(Boolean)
    .join(' ');
}

function textMatchesTerms(text, terms) {
  const normalizedText = normalizeName(text);
  return terms.some((term) => normalizedText.includes(normalizeName(term)));
}

function normalizeName(value) {
  return String(value ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '')
    .trim();
}

function uniqueStrings(values) {
  return Array.from(new Set(values.filter(Boolean).map(String)));
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function writeJson(filePath, value, spaces = 0) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(value, null, spaces));
}

function validDate(value) {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? undefined : date;
}

function dateOnly(value) {
  if (value instanceof Date) return toDateOnly(value);
  const match = /^(\d{4}-\d{2}-\d{2})/.exec(String(value ?? ''));
  if (match) return match[1];
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? '' : toDateOnly(date);
}

function parseDateOnly(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(value ?? ''));
  if (!match) return undefined;
  return new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
}

function toDateOnly(date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

function addMonthsClamped(date, months, dayOfMonth) {
  const next = new Date(date);
  next.setDate(1);
  next.setMonth(next.getMonth() + months);
  next.setDate(
    Math.min(dayOfMonth, new Date(next.getFullYear(), next.getMonth() + 1, 0).getDate()),
  );
  return next;
}

function daysBetween(left, right) {
  const leftDay = new Date(left.getFullYear(), left.getMonth(), left.getDate()).getTime();
  const rightDay = new Date(right.getFullYear(), right.getMonth(), right.getDate()).getTime();
  return Math.round((rightDay - leftDay) / DAY_MS);
}

main();
