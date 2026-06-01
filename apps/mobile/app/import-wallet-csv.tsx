import { formatMoney, fromMinor, toMinor } from '@1wallet/domain/money';
import type {
    AccountLoanDetails,
    AccountType,
    LoanInterestMethod,
    LoanInterestRatePeriod,
    LoanKind,
} from '@1wallet/domain/types';
import type {
    WalletCsvFile,
    WalletCsvImportAnalysis,
    WalletCsvPlannedPaymentCandidate,
    WalletCsvProvisionSummary,
    WalletCsvValueSummary,
} from '@1wallet/ledger/import/walletCsv';
import {
    analyzeWalletCsvImport,
    inferWalletCsvAccountType,
    inferWalletCsvInstitution,
    isWalletCsvProposalQueueable,
    provisionWalletCsvEntities,
    walletCsvBlockedReason,
    walletCsvProposalsToCaptureInputs,
} from '@1wallet/ledger/import/walletCsv';
import { buildLoanPlannedPaymentInput } from '@1wallet/ledger/loans';
import {
    createFutureGenerationRule,
    type CreateFutureGenerationRuleInput,
} from '@1wallet/ledger/rules/futureGeneration';
import {
    createAccount,
    createCaptureCandidate,
    createImportBatch,
    updateAccount,
} from '@1wallet/ledger/services';
import type { LedgerState } from '@1wallet/ledger/store/types';
import { useLedger } from '@1wallet/state';
import * as DocumentPicker from 'expo-document-picker';
import * as FileSystem from 'expo-file-system/legacy';
import { router } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import {
    ActivityIndicator,
    Button,
    Chip,
    Dialog,
    Divider,
    Portal,
    Snackbar,
    Text,
    TextInput,
    useTheme,
} from 'react-native-paper';
import {
    accountIconForType,
    accountTypeLabel,
    resolveAccountIconVisual,
} from '../src/accountOptions';
import {
    AppScreen,
    EmptyState,
    InfoRow,
    InlineMeta,
    PremiumTextInput,
    SectionCard,
} from '../src/components/AppKit';
import { DateOnlyPickerField } from '../src/components/DateOnlyPickerField';
import { recurrenceCadenceLabel } from '../src/loans/loanUtils';
import { PlannedPaymentEditor } from '../src/plannedPayments/PlanEditor';
import {
    draftFromWalletCsvPlannedPayment,
    futureRuleInputFromDraft,
    type PlannedPaymentDraft,
} from '../src/plannedPayments/planDraft';
import { transactionTypeLabel } from '../src/transactionTypes';

const HEADER_HINT =
  'account;category;currency;amount;ref_currency_amount;type;payment_type;note;date;transfer;payee;labels';

type QueueResult = {
  queued: number;
  skipped: number;
  queueable: number;
  provision?: WalletCsvProvisionSummary;
  analysis: WalletCsvImportAnalysis;
};

type WalletCsvAnalysisState = WalletCsvImportAnalysis | { error: string } | null;

type WalletCsvProvisionPreview = {
  accounts: Array<{
    name: string;
    count: number;
    typeLabel: string;
    currencyLabel: string;
    institution?: string;
  }>;
  categories: Array<{
    key: string;
    name: string;
    count: number;
    kindLabel: string;
  }>;
};

const EMPTY_PROVISION_PREVIEW: WalletCsvProvisionPreview = { accounts: [], categories: [] };

type LoanImportAccountType = Extract<AccountType, 'loan' | 'lent'>;

type LoanImportDraft = {
  name: string;
  institution: string;
  accountType: LoanImportAccountType;
  loanKind: LoanKind;
  principalText: string;
  outstandingText: string;
  emiText: string;
  remainingInstallmentsText: string;
  loanStartedOn: string;
  nextEmiOn: string;
  rateText: string;
  ratePeriod: LoanInterestRatePeriod;
  interestMethod: LoanInterestMethod;
};

type StagedPlanInputs = Record<string, CreateFutureGenerationRuleInput>;
type StagedLoanDrafts = Record<string, LoanImportDraft>;

type WalletCsvApprovalLinks = {
  ruleIdsByPlannedPaymentKey: Record<string, string>;
  loanAccountIdsByPlannedPaymentKey: Record<string, string>;
};

export default function ImportWalletCsv() {
  const theme = useTheme();
  const { state, mutate, resetAndMutate } = useLedger();
  const [fileName, setFileName] = useState('wallet_records.csv');
  const [csvText, setCsvText] = useState('');
  const [pasteVisible, setPasteVisible] = useState(false);
  const [pickedFiles, setPickedFiles] = useState<WalletCsvFile[]>([]);
  const [pickBusy, setPickBusy] = useState(false);
  const [fileLoadError, setFileLoadError] = useState<string | null>(null);
  const [provisionBusy, setProvisionBusy] = useState(false);
  const [lastProvision, setLastProvision] = useState<WalletCsvProvisionSummary | null>(null);
  const [analysisBusy, setAnalysisBusy] = useState(false);
  const [analysis, setAnalysis] = useState<WalletCsvAnalysisState>(null);
  const [resetImportVisible, setResetImportVisible] = useState(false);
  const [importBusy, setImportBusy] = useState(false);
  const planBusy = importBusy;
  const [approvedPlanRuleIds, setApprovedPlanRuleIds] = useState<Record<string, string>>({});
  const [approvedLoanAccountIds, setApprovedLoanAccountIds] = useState<Record<string, string>>({});
  const [stagedPlanInputs, setStagedPlanInputs] = useState<StagedPlanInputs>({});
  const [stagedLoanDrafts, setStagedLoanDrafts] = useState<StagedLoanDrafts>({});
  const [skippedPlanKeys, setSkippedPlanKeys] = useState<Record<string, true>>({});
  const [editingPlanKey, setEditingPlanKey] = useState<string | null>(null);
  const [editingPlanDraft, setEditingPlanDraft] = useState<PlannedPaymentDraft | null>(null);
  const [loanDraftKey, setLoanDraftKey] = useState<string | null>(null);
  const [loanDraft, setLoanDraft] = useState<LoanImportDraft | null>(null);
  const [snackbar, setSnackbar] = useState<string | null>(null);

  const sourceFiles = useMemo<WalletCsvFile[]>(() => {
    if (pickedFiles.length > 0) return pickedFiles;
    if (!csvText.trim()) return [];
    return [{ fileName: fileName.trim() || 'wallet_records.csv', content: csvText }];
  }, [csvText, fileName, pickedFiles]);

  useEffect(() => {
    if (sourceFiles.length === 0) {
      setAnalysis(null);
      setAnalysisBusy(false);
      return;
    }

    let cancelled = false;
    setAnalysis(null);
    setAnalysisBusy(true);
    const timer = setTimeout(() => {
      try {
        const nextAnalysis = analyzeWalletCsvImport(state, sourceFiles);
        if (!cancelled) setAnalysis(nextAnalysis);
      } catch (error) {
        if (!cancelled) setAnalysis({ error: (error as Error).message });
      } finally {
        if (!cancelled) setAnalysisBusy(false);
      }
    }, 80);

    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [sourceFiles, state]);

  const validAnalysis = analysis && !('error' in analysis) ? analysis : null;
  const queueable = validAnalysis?.proposals.filter(isWalletCsvProposalQueueable) ?? [];
  const skipped = validAnalysis ? validAnalysis.proposals.length - queueable.length : 0;
  const accountAuditRows = useMemo(
    () => (validAnalysis ? buildAccountAuditRows(state, validAnalysis) : []),
    [state, validAnalysis],
  );
  const provisionPreview = useMemo(
    () => (validAnalysis ? buildProvisionPreview(validAnalysis) : EMPTY_PROVISION_PREVIEW),
    [validAnalysis],
  );
  const hasMissingSetup =
    provisionPreview.accounts.length > 0 || provisionPreview.categories.length > 0;
  const reviewablePlannedPayments = useMemo(
    () =>
      (validAnalysis?.plannedPayments ?? []).filter(
        (candidate) => candidate.activity === 'active' || candidate.activity === 'needs_review',
      ),
    [validAnalysis],
  );
  const pendingPlannedPayments = reviewablePlannedPayments.filter(
    (candidate) =>
      !isLoanPlannedPaymentCandidate(candidate) &&
      !approvedPlanRuleIds[candidate.key] &&
      !stagedPlanInputs[candidate.key] &&
      !skippedPlanKeys[candidate.key],
  );
  const pendingLoanCandidates = reviewablePlannedPayments.filter(
    (candidate) =>
      isLoanPlannedPaymentCandidate(candidate) &&
      !approvedPlanRuleIds[candidate.key] &&
      !stagedLoanDrafts[candidate.key] &&
      !skippedPlanKeys[candidate.key],
  );
  const currentPlannedPayment = pendingPlannedPayments[0];
  const currentLoanCandidate = pendingLoanCandidates[0];
  const plannedPaymentReviewComplete = pendingPlannedPayments.length === 0;
  const loanReviewComplete = pendingLoanCandidates.length === 0;
  const canQueueRecords = !hasMissingSetup && plannedPaymentReviewComplete && loanReviewComplete;

  useEffect(() => {
    setLastProvision(null);
    setApprovedPlanRuleIds({});
    setApprovedLoanAccountIds({});
    setStagedPlanInputs({});
    setStagedLoanDrafts({});
    setSkippedPlanKeys({});
    setEditingPlanKey(null);
    setEditingPlanDraft(null);
    setLoanDraftKey(null);
    setLoanDraft(null);
  }, [sourceFiles]);

  useEffect(() => {
    if (!editingPlanKey) return;
    const stillExists = reviewablePlannedPayments.some(
      (candidate) => candidate.key === editingPlanKey,
    );
    if (!stillExists) {
      setEditingPlanKey(null);
      setEditingPlanDraft(null);
    }
  }, [editingPlanKey, reviewablePlannedPayments]);

  useEffect(() => {
    if (!currentLoanCandidate) {
      setLoanDraftKey(null);
      setLoanDraft(null);
      return;
    }
    if (loanDraftKey === currentLoanCandidate.key && loanDraft) return;
    setLoanDraftKey(currentLoanCandidate.key);
    setLoanDraft(defaultLoanImportDraft(state, currentLoanCandidate));
  }, [currentLoanCandidate?.key]);

  const pickCsvFiles = async () => {
    if (pickBusy) return;
    setPickBusy(true);
    setFileLoadError(null);
    setSnackbar('Opening file picker...');
    try {
      const result = await DocumentPicker.getDocumentAsync({
        type: '*/*',
        multiple: false,
        copyToCacheDirectory: true,
      });
      if (result.canceled) {
        setSnackbar('File selection cancelled');
        return;
      }
      setSnackbar('Reading selected CSV...');
      const files = await Promise.all(
        result.assets.map(async (asset) => ({
          fileName: asset.name || asset.uri.split('/').pop() || 'wallet_records.csv',
          content: await FileSystem.readAsStringAsync(asset.uri),
        })),
      );
      if (files.length === 0) {
        setFileLoadError('The Android file picker did not return a file.');
        setSnackbar('No CSV file was returned by the picker.');
        return;
      }
      setPickedFiles(files);
      setCsvText('');
      setPasteVisible(false);
      setLastProvision(null);
      setSnackbar(`${files[0]?.fileName ?? 'Wallet CSV'} loaded. Preparing preview...`);
    } catch (error) {
      setPickedFiles([]);
      setAnalysis(null);
      setLastProvision(null);
      const message = (error as Error).message;
      setFileLoadError(message);
      setSnackbar(`Could not read CSV: ${message}`);
    } finally {
      setPickBusy(false);
    }
  };

  const queueImport = async () => {
    if (!validAnalysis || queueable.length === 0 || !canQueueRecords) return;
    let result: QueueResult | undefined;
    let stagedLinks: WalletCsvApprovalLinks | undefined;
    setImportBusy(true);
    try {
      await mutate((draft) => {
        stagedLinks = createStagedWalletCsvApprovals(
          draft,
          validAnalysis.plannedPayments,
          stagedPlanInputs,
          stagedLoanDrafts,
        );
        result = queueWalletCsvAnalysis(draft, validAnalysis, sourceFiles, undefined, {
          plannedPayments: validAnalysis.plannedPayments,
          ruleIdsByPlannedPaymentKey: {
            ...approvedPlanRuleIds,
            ...stagedLinks.ruleIdsByPlannedPaymentKey,
          },
          loanAccountIdsByPlannedPaymentKey: {
            ...approvedLoanAccountIds,
            ...stagedLinks.loanAccountIdsByPlannedPaymentKey,
          },
        });
      });
      if (result) {
        if (stagedLinks) {
          setApprovedPlanRuleIds((current) => ({
            ...current,
            ...stagedLinks!.ruleIdsByPlannedPaymentKey,
          }));
          setApprovedLoanAccountIds((current) => ({
            ...current,
            ...stagedLinks!.loanAccountIdsByPlannedPaymentKey,
          }));
        }
        setStagedPlanInputs({});
        setStagedLoanDrafts({});
        setSnackbar(`${result.queued} new rows queued; ${result.skipped} skipped`);
      }
    } catch (error) {
      setSnackbar(`Import failed: ${(error as Error).message}`);
    } finally {
      setImportBusy(false);
    }
  };

  const startEditingPlannedPayment = (candidate: WalletCsvPlannedPaymentCandidate) => {
    setEditingPlanKey(candidate.key);
    setEditingPlanDraft(draftFromWalletCsvPlannedPayment(state, candidate));
  };

  const skipPlannedPayment = (candidate: WalletCsvPlannedPaymentCandidate) => {
    setSkippedPlanKeys((current) => ({ ...current, [candidate.key]: true }));
    if (editingPlanKey === candidate.key) {
      setEditingPlanKey(null);
      setEditingPlanDraft(null);
    }
    if (loanDraftKey === candidate.key) {
      setLoanDraftKey(null);
      setLoanDraft(null);
    }
  };

  const approvePlannedPayment = async (
    candidate: WalletCsvPlannedPaymentCandidate,
    draftOverride?: PlannedPaymentDraft,
  ) => {
    if (planBusy) return;
    const planDraft = draftOverride ?? draftFromWalletCsvPlannedPayment(state, candidate);
    const result = futureRuleInputFromDraft(state, planDraft);
    if (!result.ok) {
      setSnackbar(result.message);
      return;
    }

    const stagedInput: CreateFutureGenerationRuleInput = {
      ...result.input,
      tags: uniqueStrings([...(result.input.tags ?? []), 'Wallet CSV', 'Imported plan']),
    };
    setStagedPlanInputs((current) => ({ ...current, [candidate.key]: stagedInput }));
    setSkippedPlanKeys((current) => {
      const next = { ...current };
      delete next[candidate.key];
      return next;
    });
    setEditingPlanKey(null);
    setEditingPlanDraft(null);
    setSnackbar(`${candidate.name} plan staged`);
  };

  const updateLoanDraftField = <TKey extends keyof LoanImportDraft>(
    key: TKey,
    value: LoanImportDraft[TKey],
  ) => {
    setLoanDraft((current) => (current ? { ...current, [key]: value } : current));
  };

  const approveLoanCandidate = async (candidate: WalletCsvPlannedPaymentCandidate) => {
    if (planBusy) return;
    const draft = loanDraft ?? defaultLoanImportDraft(state, candidate);
    const buildResult = buildLoanImportAccountDraft(state, candidate, draft);
    if (!buildResult.ok) {
      setSnackbar(buildResult.message);
      return;
    }

    setStagedLoanDrafts((current) => ({ ...current, [candidate.key]: draft }));
    setSkippedPlanKeys((current) => {
      const next = { ...current };
      delete next[candidate.key];
      return next;
    });
    setLoanDraftKey(null);
    setLoanDraft(null);
    setSnackbar(`${buildResult.cleanName} loan staged`);
  };

  const createMissingSetup = async () => {
    if (!validAnalysis || sourceFiles.length === 0 || !hasMissingSetup) return;
    setProvisionBusy(true);
    setSnackbar('Creating Wallet accounts and categories...');
    let provision: WalletCsvProvisionSummary | undefined;
    try {
      await mutate((draft) => {
        provision = provisionWalletCsvEntities(draft, sourceFiles);
      });
      if (provision) {
        setLastProvision(provision);
        setSnackbar(
          `${provision.accountsCreated} accounts and ${provision.categoriesCreated} categories created. Refreshing preview...`,
        );
      }
    } catch (error) {
      setSnackbar(`Setup creation failed: ${(error as Error).message}`);
    } finally {
      setProvisionBusy(false);
    }
  };

  const resetAndQueueImport = async () => {
    if (!validAnalysis || validAnalysis.proposals.length === 0) return;
    setResetImportVisible(false);
    setImportBusy(true);
    let result: QueueResult | undefined;
    try {
      await resetAndMutate((draft) => {
        const provision = provisionWalletCsvEntities(draft, sourceFiles);
        const resetAnalysis = analyzeWalletCsvImport(draft, sourceFiles);
        const stagedLinks = createStagedWalletCsvApprovals(
          draft,
          resetAnalysis.plannedPayments,
          stagedPlanInputs,
          stagedLoanDrafts,
        );
        result = queueWalletCsvAnalysis(draft, resetAnalysis, sourceFiles, provision, {
          plannedPayments: resetAnalysis.plannedPayments,
          ruleIdsByPlannedPaymentKey: stagedLinks.ruleIdsByPlannedPaymentKey,
          loanAccountIdsByPlannedPaymentKey: stagedLinks.loanAccountIdsByPlannedPaymentKey,
        });
      });
      if (result) {
        setStagedPlanInputs({});
        setStagedLoanDrafts({});
        setSnackbar(
          `${result.queued} queued after reset; ${result.provision?.accountsCreated ?? 0} accounts and ${result.provision?.categoriesCreated ?? 0} categories created`,
        );
        router.push('/review' as never);
      }
    } catch (error) {
      setSnackbar(`Reset import failed: ${(error as Error).message}`);
    } finally {
      setImportBusy(false);
    }
  };

  return (
    <>
      <AppScreen
        title="Wallet CSV import"
        subtitle="Pick one Wallet CSV export, preview matches, skip duplicates, then queue safe rows for review."
        actions={[
          {
            icon: 'robot-outline',
            label: 'Review',
            onPress: () => router.push('/review' as never),
          },
        ]}
      >
        <SectionCard
          title="CSV source"
          subtitle="Choose one Wallet export file. The app previews it first, then queues safe rows for Review."
        >
          <Button
            mode="contained"
            icon="file-upload-outline"
            loading={pickBusy}
            disabled={pickBusy || importBusy || provisionBusy}
            onPress={() => void pickCsvFiles()}
          >
            {pickedFiles.length > 0 ? 'Choose different CSV file' : 'Pick CSV file'}
          </Button>
          {pickedFiles.length > 0 ? (
            <View style={styles.loadedFiles}>
              <InlineMeta numberOfLines={2} items={pickedFiles.map((file) => file.fileName)} />
              <Button
                compact
                mode="text"
                onPress={() => {
                  setPickedFiles([]);
                  setLastProvision(null);
                }}
              >
                Clear file
              </Button>
            </View>
          ) : null}
          {pickedFiles.length === 0 ? (
            <>
              <Button
                compact
                mode="text"
                icon={pasteVisible ? 'chevron-up' : 'clipboard-text-outline'}
                onPress={() => setPasteVisible((visible) => !visible)}
              >
                {pasteVisible ? 'Hide paste fallback' : 'Paste CSV text instead'}
              </Button>
              {pasteVisible ? (
                <>
                  <PremiumTextInput
                    label="File name"
                    value={fileName}
                    onChangeText={setFileName}
                    left={<TextInput.Icon icon="file-table-outline" />}
                  />
                  <PremiumTextInput
                    label="CSV content"
                    value={csvText}
                    onChangeText={setCsvText}
                    placeholder={HEADER_HINT}
                    multiline
                    numberOfLines={9}
                    style={styles.csvInput}
                  />
                </>
              ) : null}
            </>
          ) : null}
        </SectionCard>

        {fileLoadError ? (
          <SectionCard title="File load error" subtitle="The selected file could not be read.">
            <InfoRow
              icon="alert-circle-outline"
              label="Read error"
              value={fileLoadError}
              tone="danger"
            />
          </SectionCard>
        ) : null}

        {analysis && 'error' in analysis ? (
          <SectionCard title="Parser error">
            <InfoRow
              icon="alert-circle-outline"
              label="Problem"
              value={analysis.error}
              tone="danger"
            />
          </SectionCard>
        ) : null}

        {analysisBusy ? (
          <SectionCard title="Preparing preview" subtitle="The file is loaded and being checked.">
            <View style={styles.loadingRow}>
              <ActivityIndicator animating />
              <Text variant="bodyMedium">
                Reading rows, matching accounts, and pairing transfers...
              </Text>
            </View>
          </SectionCard>
        ) : null}

        {validAnalysis ? (
          <>
            <SectionCard title="Preview" subtitle="No ledger records are posted from this screen.">
              <InfoRow
                icon="file-document-outline"
                label="Rows"
                value={String(validAnalysis.rowCount)}
              />
              <InfoRow
                icon="calendar-range"
                label="Date range"
                value={formatDateRange(validAnalysis.summary.dateRange)}
              />
              <InfoRow
                icon="inbox-arrow-down-outline"
                label="Review candidates"
                value={String(validAnalysis.summary.candidates)}
              />
              <InfoRow
                icon="check-circle-outline"
                label="Safe to queue"
                value={String(validAnalysis.summary.queueable)}
                tone={queueable.length ? 'positive' : 'warning'}
              />
              <InfoRow
                icon="close-octagon-outline"
                label="Blocked"
                value={String(validAnalysis.summary.blocked)}
                tone={validAnalysis.summary.blocked ? 'warning' : 'positive'}
              />
              <InfoRow
                icon="alert-circle-outline"
                label="Invalid rows"
                value={String(validAnalysis.summary.invalidRows)}
                tone={validAnalysis.summary.invalidRows ? 'warning' : 'positive'}
              />
              <InfoRow
                icon="swap-horizontal"
                label="Transfer pairs"
                value={String(validAnalysis.summary.transferPairs)}
                tone="positive"
              />
              <InfoRow
                icon="alert-outline"
                label="Unpaired transfers"
                value={String(validAnalysis.summary.unpairedTransfers)}
                tone={validAnalysis.summary.unpairedTransfers ? 'warning' : 'positive'}
              />
              <InfoRow
                icon="content-duplicate"
                label="Duplicates skipped"
                value={String(validAnalysis.summary.duplicates)}
                tone={validAnalysis.summary.duplicates ? 'warning' : 'positive'}
              />
              <InfoRow
                icon="calendar-clock-outline"
                label="Active plans found"
                value={String(validAnalysis.summary.plannedPaymentsActive)}
                tone={validAnalysis.summary.plannedPaymentsActive ? 'positive' : 'warning'}
              />
              <InfoRow
                icon="calendar-alert-outline"
                label="Plans needing review"
                value={String(validAnalysis.summary.plannedPaymentsNeedsReview)}
                tone={validAnalysis.summary.plannedPaymentsNeedsReview ? 'warning' : 'positive'}
              />
              <InfoRow
                icon="calendar-remove-outline"
                label="Old plans hidden"
                value={String(validAnalysis.summary.plannedPaymentsHistorical)}
                tone={validAnalysis.summary.plannedPaymentsHistorical ? 'warning' : 'positive'}
              />
              <InfoRow
                icon="skip-next-outline"
                label="Blocked or skipped"
                value={String(skipped)}
                tone={skipped ? 'warning' : 'positive'}
              />
              <InfoRow
                icon="bank-off"
                label="Unknown accounts"
                value={String(validAnalysis.summary.unknownAccounts)}
                tone={validAnalysis.summary.unknownAccounts ? 'warning' : 'positive'}
              />
              <InfoRow
                icon="shape-outline"
                label="Unknown categories"
                value={String(validAnalysis.summary.unknownCategories)}
                tone={validAnalysis.summary.unknownCategories ? 'warning' : 'positive'}
              />
            </SectionCard>

            {hasMissingSetup || lastProvision ? (
              <SectionCard
                title={hasMissingSetup ? 'Create missing Wallet setup' : 'Wallet setup ready'}
                subtitle={
                  hasMissingSetup
                    ? 'Create these Wallet accounts and categories first, then the preview refreshes.'
                    : 'The preview has been refreshed against the created Wallet setup.'
                }
              >
                {hasMissingSetup ? (
                  <>
                    <InfoRow
                      icon="bank-plus"
                      label="Accounts to create"
                      value={String(provisionPreview.accounts.length)}
                      tone={provisionPreview.accounts.length ? 'warning' : 'positive'}
                    />
                    <InfoRow
                      icon="shape-plus-outline"
                      label="Categories to create"
                      value={String(provisionPreview.categories.length)}
                      tone={provisionPreview.categories.length ? 'warning' : 'positive'}
                    />
                    <Button
                      mode="contained"
                      icon="bank-plus"
                      loading={provisionBusy}
                      disabled={provisionBusy || importBusy || analysisBusy}
                      onPress={() => void createMissingSetup()}
                    >
                      Create {provisionPreview.accounts.length} accounts and{' '}
                      {provisionPreview.categories.length} categories
                    </Button>
                    {provisionPreview.accounts.length > 0 ? (
                      <View style={styles.provisionGroup}>
                        <Text variant="titleSmall">Accounts</Text>
                        {provisionPreview.accounts.slice(0, 12).map((account, index) => (
                          <View key={account.name}>
                            <View style={styles.accountAuditHeader}>
                              <Text
                                variant="titleSmall"
                                numberOfLines={1}
                                style={styles.proposalTitle}
                              >
                                {account.name}
                              </Text>
                              <Text variant="labelLarge" numberOfLines={1} style={styles.countText}>
                                {account.count} rows
                              </Text>
                            </View>
                            <InfoRow
                              icon="shape-outline"
                              label="Type and currency"
                              value={`${account.typeLabel} · ${account.currencyLabel}`}
                            />
                            <InfoRow
                              icon="bank-outline"
                              label="Institution"
                              value={account.institution ?? 'Not inferred'}
                            />
                            {index < Math.min(provisionPreview.accounts.length, 12) - 1 ? (
                              <Divider />
                            ) : null}
                          </View>
                        ))}
                        {provisionPreview.accounts.length > 12 ? (
                          <Text
                            variant="bodySmall"
                            style={{ color: theme.colors.onSurfaceVariant }}
                          >
                            Showing 12 of {provisionPreview.accounts.length} accounts to create.
                          </Text>
                        ) : null}
                      </View>
                    ) : null}
                    {provisionPreview.categories.length > 0 ? (
                      <View style={styles.provisionGroup}>
                        <Text variant="titleSmall">Categories</Text>
                        <InlineMeta
                          numberOfLines={3}
                          items={provisionPreview.categories
                            .slice(0, 18)
                            .map(
                              (category) =>
                                `${category.name} / ${category.kindLabel} / ${category.count}`,
                            )}
                        />
                        {provisionPreview.categories.length > 18 ? (
                          <Text
                            variant="bodySmall"
                            style={{ color: theme.colors.onSurfaceVariant }}
                          >
                            Showing 18 of {provisionPreview.categories.length} categories to create.
                          </Text>
                        ) : null}
                      </View>
                    ) : null}
                  </>
                ) : lastProvision ? (
                  <>
                    <InfoRow
                      icon="check-circle-outline"
                      label="Created"
                      value={`${lastProvision.accountsCreated} accounts · ${lastProvision.categoriesCreated} categories`}
                      tone="positive"
                    />
                    <InfoRow
                      icon="database-search-outline"
                      label="Preview"
                      value="Refreshed with the new Wallet setup"
                      tone="positive"
                    />
                  </>
                ) : null}
              </SectionCard>
            ) : null}

            {!hasMissingSetup ? (
              <SectionCard
                title="Planned payments"
                subtitle="Confirm current recurring income, expenses, transfers, and adjustments before records are queued."
              >
                <InlineMeta
                  numberOfLines={2}
                  items={[
                    'Setup ready',
                    `Plans ${reviewedRegularPlanCount(reviewablePlannedPayments, pendingPlannedPayments)}/${regularPlanCount(reviewablePlannedPayments)}`,
                    `Loans ${loanPlanCount(reviewablePlannedPayments) - pendingLoanCandidates.length}/${loanPlanCount(reviewablePlannedPayments)}`,
                  ]}
                />
                {currentPlannedPayment ? (
                  <PlannedPaymentCandidateCard
                    candidate={currentPlannedPayment}
                    locale={state.preferences.locale}
                    planBusy={planBusy}
                    onApprove={() => void approvePlannedPayment(currentPlannedPayment)}
                    onEdit={() => startEditingPlannedPayment(currentPlannedPayment)}
                    onSkip={() => skipPlannedPayment(currentPlannedPayment)}
                  />
                ) : (
                  <InfoRow
                    icon="check-circle-outline"
                    label="Planned payments"
                    value="All current non-loan candidates reviewed"
                    tone="positive"
                  />
                )}
                {validAnalysis.summary.plannedPaymentsHistorical > 0 ? (
                  <InfoRow
                    icon="history"
                    label="Old patterns"
                    value={`${validAnalysis.summary.plannedPaymentsHistorical} hidden as historical`}
                    tone="warning"
                  />
                ) : null}
              </SectionCard>
            ) : null}

            {editingPlanDraft && editingPlanKey ? (
              <PlannedPaymentEditor
                draft={editingPlanDraft}
                state={state}
                onChange={setEditingPlanDraft}
                onCancel={() => {
                  setEditingPlanKey(null);
                  setEditingPlanDraft(null);
                }}
                onSave={() => {
                  const candidate = reviewablePlannedPayments.find(
                    (item) => item.key === editingPlanKey,
                  );
                  if (candidate && editingPlanDraft) {
                    void approvePlannedPayment(candidate, editingPlanDraft);
                  }
                }}
                saveLabel="Approve plan"
              />
            ) : null}

            {!hasMissingSetup && currentLoanCandidate ? (
              <SectionCard
                title="Loan account from import"
                subtitle="Confirm the imported EMI pattern, then create the loan account and linked principal EMI plan."
              >
                <LoanImportCandidateCard
                  candidate={currentLoanCandidate}
                  locale={state.preferences.locale}
                  draft={loanDraft}
                  planBusy={planBusy}
                  onChange={updateLoanDraftField}
                  onApprove={() => void approveLoanCandidate(currentLoanCandidate)}
                  onSkip={() => skipPlannedPayment(currentLoanCandidate)}
                />
              </SectionCard>
            ) : null}

            <SectionCard
              title="Import actions"
              subtitle={
                hasMissingSetup
                  ? 'Create missing accounts and categories before queueing rows.'
                  : canQueueRecords
                    ? 'The selected file is loaded and ready to queue.'
                    : 'Review planned-payment and loan candidates before queueing rows.'
              }
            >
              <InfoRow
                icon="file-check-outline"
                label="Loaded file"
                value={validAnalysis.files.join(', ')}
                tone="positive"
              />
              <InfoRow
                icon="database-sync-outline"
                label="Setup"
                value={hasMissingSetup ? 'Create setup first' : 'Ready'}
                tone={hasMissingSetup ? 'warning' : 'positive'}
              />
              <InfoRow
                icon="calendar-clock-outline"
                label="Plan review"
                value={canQueueRecords ? 'Ready' : 'Needs review'}
                tone={canQueueRecords ? 'positive' : 'warning'}
              />
              <InfoRow
                icon="check-circle-outline"
                label="Safe rows"
                value={String(validAnalysis.summary.queueable)}
                tone={queueable.length ? 'positive' : 'warning'}
              />
              <InfoRow
                icon="alert-outline"
                label="Needs review or repair"
                value={String(validAnalysis.summary.blocked + validAnalysis.summary.duplicates)}
                tone={
                  validAnalysis.summary.blocked + validAnalysis.summary.duplicates
                    ? 'warning'
                    : 'positive'
                }
              />
              <Button
                mode="contained"
                icon="inbox-arrow-down-outline"
                loading={importBusy}
                disabled={
                  queueable.length === 0 ||
                  importBusy ||
                  provisionBusy ||
                  analysisBusy ||
                  !canQueueRecords
                }
                onPress={() => void queueImport()}
              >
                Import {queueable.length} safe rows to Review
              </Button>
              <Button
                mode="contained-tonal"
                icon="delete-restore"
                loading={importBusy}
                disabled={
                  validAnalysis.proposals.length === 0 ||
                  importBusy ||
                  provisionBusy ||
                  !canQueueRecords
                }
                onPress={() => setResetImportVisible(true)}
              >
                Reset app data and import this file
              </Button>
              <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                {hasMissingSetup
                  ? 'The import count will update after setup is created.'
                  : 'Import creates Review items first. Approving Review items is what posts real ledger transactions.'}
              </Text>
            </SectionCard>

            <SectionCard title="File summaries" subtitle="Rows, dates, and transfers per export.">
              {validAnalysis.summary.perFile.map((file, index) => (
                <View key={file.fileName}>
                  <InfoRow
                    icon="file-table-outline"
                    label={file.fileName}
                    value={`${file.rowCount} rows · ${file.transferRows} transfers`}
                  />
                  <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                    {formatDateRange(file.dateRange)} · {formatTopValues(file.accounts, 3)}
                  </Text>
                  {index < validAnalysis.summary.perFile.length - 1 ? <Divider /> : null}
                </View>
              ))}
            </SectionCard>

            <SectionCard
              title="Account mapping"
              subtitle="Original Wallet account labels and how the importer will map them."
            >
              {accountAuditRows.slice(0, 18).map((row, index) => (
                <View key={row.csvName}>
                  <View style={styles.accountAuditHeader}>
                    <Text variant="titleSmall" numberOfLines={1} style={styles.proposalTitle}>
                      {row.csvName}
                    </Text>
                    <Text variant="labelLarge" numberOfLines={1} style={styles.countText}>
                      {row.count} rows
                    </Text>
                  </View>
                  <InfoRow icon="wallet-outline" label="CSV account" value={row.csvName} />
                  <InfoRow
                    icon={
                      row.matchedAccountIcon ??
                      (row.matchedAccountName ? 'check-circle-outline' : 'bank-plus')
                    }
                    iconBackgroundColor={row.matchedAccountBackgroundColor}
                    iconColor={row.matchedAccountIconColor}
                    label="App account"
                    value={row.matchedAccountName ?? 'Will be created by setup'}
                    tone={row.matchedAccountName ? 'positive' : 'warning'}
                  />
                  <InfoRow
                    icon="shape-outline"
                    label="Type and currency"
                    value={`${row.typeLabel} · ${row.currencyLabel}`}
                  />
                  <InfoRow
                    icon="bank-outline"
                    label="Institution"
                    value={row.institution ?? 'Not inferred'}
                  />
                  <InlineMeta items={[row.statusLabel, row.matchReason]} />
                  {index < Math.min(accountAuditRows.length, 18) - 1 ? <Divider /> : null}
                </View>
              ))}
              {accountAuditRows.length > 18 ? (
                <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                  Showing 18 of {accountAuditRows.length} account labels.
                </Text>
              ) : null}
            </SectionCard>

            <SectionCard title="Field summary" subtitle="Top values from the loaded Wallet file.">
              <InfoRow
                icon="wallet-outline"
                label="Accounts"
                value={formatTopValues(validAnalysis.summary.accounts, 5)}
              />
              <InfoRow
                icon="shape-outline"
                label="Categories"
                value={formatTopValues(validAnalysis.summary.categories, 5)}
              />
              <InfoRow
                icon="currency-inr"
                label="Currencies"
                value={formatTopValues(validAnalysis.summary.currencies, 5)}
              />
              <InfoRow
                icon="credit-card-outline"
                label="Payment types"
                value={formatTopValues(validAnalysis.summary.paymentTypes, 5)}
              />
              <InfoRow
                icon="tag-outline"
                label="Labels"
                value={formatTopValues(validAnalysis.summary.labels, 5)}
              />
            </SectionCard>

            <SectionCard
              title="First matched rows"
              subtitle="Rows with warnings stay editable in review."
            >
              {validAnalysis.proposals.slice(0, 10).map((proposal, index) => {
                const account = state.accounts.find(
                  (item) => item.id === proposal.suggestedAccountId,
                );
                const counter = state.accounts.find(
                  (item) => item.id === proposal.suggestedCounterAccountId,
                );
                const blockedReason = walletCsvBlockedReason(proposal);
                return (
                  <View key={proposal.key}>
                    <View style={styles.proposalHeader}>
                      <Text variant="titleSmall" numberOfLines={1} style={styles.proposalTitle}>
                        {transactionTypeLabel(proposal.suggestedType)}
                      </Text>
                      <Text
                        variant="titleSmall"
                        style={{
                          color: proposal.duplicate ? theme.colors.error : theme.colors.onSurface,
                        }}
                      >
                        {formatMoney(
                          { amountMinor: proposal.amountMinor, currency: proposal.currency },
                          state.preferences.locale,
                        )}
                      </Text>
                    </View>
                    <Text
                      variant="bodySmall"
                      style={{ color: theme.colors.onSurfaceVariant }}
                      numberOfLines={2}
                    >
                      CSV: {proposal.sourceRow.accountName}
                      {proposal.pairedRow ? ` -> ${proposal.pairedRow.accountName}` : ''}
                    </Text>
                    <Text
                      variant="bodySmall"
                      style={{ color: theme.colors.onSurfaceVariant }}
                      numberOfLines={2}
                    >
                      Account: {account?.name ?? 'Needs account'}
                      {counter ? ` -> ${counter.name}` : ''}
                    </Text>
                    <Text
                      variant="bodySmall"
                      style={{ color: theme.colors.onSurfaceVariant }}
                      numberOfLines={2}
                    >
                      {proposal.fileNames.join(', ')} · rows {proposal.rowNumbers.join(', ')} ·{' '}
                      {proposal.sourceRow.categoryName || 'No category'} ·{' '}
                      {proposal.sourceRow.currency}
                    </Text>
                    <InlineMeta
                      numberOfLines={2}
                      items={[
                        `${Math.round(proposal.confidence)}% confidence`,
                        proposal.sourceRow.accountMatch
                          ? matchKindLabel(proposal.sourceRow.accountMatch.kind)
                          : null,
                        blockedReason,
                        proposal.duplicate ? 'Duplicate' : null,
                        ...proposal.warnings.slice(0, 2),
                      ]}
                    />
                    {index < Math.min(validAnalysis.proposals.length, 10) - 1 ? <Divider /> : null}
                  </View>
                );
              })}
            </SectionCard>
          </>
        ) : sourceFiles.length > 0 ? null : (
          <SectionCard title="Ready for Wallet exports">
            <EmptyState
              icon="file-table-outline"
              title="Pick a CSV export"
              body="The importer will match accounts, pair transfers, flag duplicates, and queue safe rows for Review."
            />
          </SectionCard>
        )}
      </AppScreen>
      <Portal>
        <Dialog visible={resetImportVisible} onDismiss={() => setResetImportVisible(false)}>
          <Dialog.Title>Reset app data and import Wallet CSV?</Dialog.Title>
          <Dialog.Content>
            <Text variant="bodyMedium">
              This resets local accounts, transactions, budgets, goals, capture candidates, and
              import batches on this device. It will then recreate accounts and categories from the
              loaded Wallet CSV and queue safe rows for Review.
            </Text>
            <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
              No imported row is posted directly as a transaction from this action.
            </Text>
          </Dialog.Content>
          <Dialog.Actions>
            <Button onPress={() => setResetImportVisible(false)}>Cancel</Button>
            <Button textColor={theme.colors.error} onPress={() => void resetAndQueueImport()}>
              Reset and import
            </Button>
          </Dialog.Actions>
        </Dialog>
      </Portal>
      <Snackbar visible={Boolean(snackbar)} onDismiss={() => setSnackbar(null)} duration={2600}>
        {snackbar}
      </Snackbar>
    </>
  );
}

function queueWalletCsvAnalysis(
  draft: LedgerState,
  analysis: WalletCsvImportAnalysis,
  sourceFiles: WalletCsvFile[],
  provision?: WalletCsvProvisionSummary,
  linkOptions?: Parameters<typeof walletCsvProposalsToCaptureInputs>[2],
): QueueResult {
  const queueable = analysis.proposals.filter(isWalletCsvProposalQueueable);
  let queued = 0;
  const batch = createImportBatch(draft, {
    source: 'wallet_csv',
    status: 'queued',
    name: sourceFiles.length === 1 ? sourceFiles[0]!.fileName : 'Wallet CSV import',
    fileNames: analysis.files,
    rowCount: analysis.rowCount,
    candidateCount: queueable.length,
    duplicateCount: analysis.summary.duplicates,
    transferPairCount: analysis.summary.transferPairs,
    warningCount: analysis.summary.warnings,
    notes: importBatchNotes(analysis, provision),
  });
  const inputs = walletCsvProposalsToCaptureInputs(analysis.proposals, batch.id, linkOptions);
  for (const input of inputs) {
    const before = draft.captureCandidates.length;
    createCaptureCandidate(draft, input);
    if (draft.captureCandidates.length > before) queued += 1;
  }

  return {
    queued,
    skipped: queueable.length - queued + analysis.summary.blocked,
    queueable: queueable.length,
    provision,
    analysis,
  };
}

function createStagedWalletCsvApprovals(
  draft: LedgerState,
  plannedPayments: WalletCsvPlannedPaymentCandidate[],
  stagedPlanInputs: StagedPlanInputs,
  stagedLoanDrafts: StagedLoanDrafts,
): WalletCsvApprovalLinks {
  const ruleIdsByPlannedPaymentKey: Record<string, string> = {};
  const loanAccountIdsByPlannedPaymentKey: Record<string, string> = {};

  for (const candidate of plannedPayments) {
    const planInput = stagedPlanInputs[candidate.key];
    if (!planInput) continue;
    const rule = createFutureGenerationRule(draft, planInput);
    ruleIdsByPlannedPaymentKey[candidate.key] = rule.id;
  }

  for (const candidate of plannedPayments) {
    const loanDraft = stagedLoanDrafts[candidate.key];
    if (!loanDraft) continue;
    const created = createStagedLoanImportApproval(draft, candidate, loanDraft);
    ruleIdsByPlannedPaymentKey[candidate.key] = created.ruleId;
    loanAccountIdsByPlannedPaymentKey[candidate.key] = created.loanAccountId;
  }

  return { ruleIdsByPlannedPaymentKey, loanAccountIdsByPlannedPaymentKey };
}

function createStagedLoanImportApproval(
  draft: LedgerState,
  candidate: WalletCsvPlannedPaymentCandidate,
  loanDraft: LoanImportDraft,
) {
  const buildResult = buildLoanImportAccountDraft(draft, candidate, loanDraft);
  if (!buildResult.ok) throw new Error(buildResult.message);

  const loanAccount = createAccount(draft, {
    name: buildResult.cleanName,
    type: loanDraft.accountType,
    currency: buildResult.currency,
    openingBalanceMinor: buildResult.openingBalanceMinor,
    openingDate: candidate.startsOn,
    institution: loanDraft.institution.trim() || undefined,
    icon: accountIconForType(loanDraft.accountType),
    color: loanDraft.accountType === 'lent' ? '#0F766E' : '#6B5F47',
    includeInBudgets: false,
    includeInReports: true,
    includeInNetWorth: true,
    notes: `Created from Wallet CSV import for ${candidate.name}.`,
    loanDetails: buildResult.loanDetails,
  });
  const ruleInput = buildLoanPlannedPaymentInput(loanAccount, buildResult.loanDetails, [
    'Wallet CSV',
    'Imported loan',
  ]);
  if (!ruleInput) throw new Error('Could not build the linked EMI plan');
  const rule = createFutureGenerationRule(draft, ruleInput);
  updateAccount(draft, loanAccount.id, {
    loanDetails: { ...buildResult.loanDetails, linkedPlannedPaymentRuleId: rule.id },
  });

  return { loanAccountId: loanAccount.id, ruleId: rule.id };
}

function PlannedPaymentCandidateCard({
  candidate,
  locale,
  planBusy,
  onApprove,
  onEdit,
  onSkip,
}: {
  candidate: WalletCsvPlannedPaymentCandidate;
  locale: string;
  planBusy: boolean;
  onApprove: () => void;
  onEdit: () => void;
  onSkip: () => void;
}) {
  return (
    <View style={styles.planCandidateBox}>
      <PlannedPaymentCandidateSummary candidate={candidate} locale={locale} />
      <View style={styles.actionsRowWrap}>
        <Button
          mode="contained"
          icon="check"
          loading={planBusy}
          disabled={planBusy}
          onPress={onApprove}
        >
          Approve
        </Button>
        <Button mode="contained-tonal" icon="pencil-outline" disabled={planBusy} onPress={onEdit}>
          Edit
        </Button>
        <Button mode="outlined" icon="skip-next-outline" disabled={planBusy} onPress={onSkip}>
          Skip
        </Button>
      </View>
    </View>
  );
}

function LoanImportCandidateCard({
  candidate,
  locale,
  draft,
  planBusy,
  onChange,
  onApprove,
  onSkip,
}: {
  candidate: WalletCsvPlannedPaymentCandidate;
  locale: string;
  draft: LoanImportDraft | null;
  planBusy: boolean;
  onChange: <TKey extends keyof LoanImportDraft>(key: TKey, value: LoanImportDraft[TKey]) => void;
  onApprove: () => void;
  onSkip: () => void;
}) {
  if (!draft) {
    return (
      <View style={styles.loadingRow}>
        <ActivityIndicator animating />
        <Text variant="bodyMedium">Preparing loan draft...</Text>
      </View>
    );
  }

  return (
    <View style={styles.planCandidateBox}>
      <PlannedPaymentCandidateSummary candidate={candidate} locale={locale} />
      <InfoRow
        icon="bank-transfer-out"
        label="Loan direction"
        value={draft.accountType === 'lent' ? 'Lent money coming back' : 'Borrowed loan repayment'}
      />
      <InfoRow icon="wallet-outline" label="Repayment account" value={candidate.accountName} />
      <View style={styles.chips}>
        <Chip
          compact
          selected={draft.accountType === 'loan'}
          onPress={() => onChange('accountType', 'loan')}
        >
          Borrowed
        </Chip>
        <Chip
          compact
          selected={draft.accountType === 'lent'}
          onPress={() => onChange('accountType', 'lent')}
        >
          Lent
        </Chip>
      </View>
      <InlineMeta items={[loanKindLabel(draft.loanKind), interestModelLabel(draft)]} />
      <View style={styles.formRow}>
        <PremiumTextInput
          mode="outlined"
          label="Loan account name"
          value={draft.name}
          onChangeText={(value) => onChange('name', value)}
          style={styles.formField}
        />
        <PremiumTextInput
          mode="outlined"
          label="Lender optional"
          value={draft.institution}
          onChangeText={(value) => onChange('institution', value)}
          style={styles.formField}
        />
      </View>
      <View style={styles.formRow}>
        <PremiumTextInput
          mode="outlined"
          label={`Original principal (${candidate.currency})`}
          value={draft.principalText}
          keyboardType="numeric"
          onChangeText={(value) => onChange('principalText', value)}
          style={styles.formField}
        />
        <PremiumTextInput
          mode="outlined"
          label={`Amount left (${candidate.currency})`}
          value={draft.outstandingText}
          keyboardType="numeric"
          onChangeText={(value) => onChange('outstandingText', value)}
          style={styles.formField}
        />
      </View>
      <View style={styles.formRow}>
        <PremiumTextInput
          mode="outlined"
          label={`Principal EMI (${candidate.currency})`}
          value={draft.emiText}
          keyboardType="numeric"
          onChangeText={(value) => onChange('emiText', value)}
          style={styles.formField}
        />
        <PremiumTextInput
          mode="outlined"
          label="Remaining EMIs"
          value={draft.remainingInstallmentsText}
          keyboardType="number-pad"
          onChangeText={(value) => onChange('remainingInstallmentsText', value)}
          style={styles.formField}
        />
      </View>
      <View style={styles.formRow}>
        <DateOnlyPickerField
          label="Loan start date"
          value={draft.loanStartedOn}
          onChange={(value) => onChange('loanStartedOn', value)}
          style={styles.formField}
        />
        <DateOnlyPickerField
          label="Next EMI date"
          value={draft.nextEmiOn}
          onChange={(value) => onChange('nextEmiOn', value)}
          style={styles.formField}
        />
      </View>
      <PremiumTextInput
        mode="outlined"
        label={`Interest rate % (${draft.ratePeriod})`}
        value={draft.rateText}
        keyboardType="numeric"
        onChangeText={(value) => onChange('rateText', value)}
      />
      <View style={styles.actionsRowWrap}>
        <Button
          mode="contained"
          icon="bank-plus"
          loading={planBusy}
          disabled={planBusy}
          onPress={onApprove}
        >
          Create loan account
        </Button>
        <Button mode="outlined" icon="skip-next-outline" disabled={planBusy} onPress={onSkip}>
          Skip loan
        </Button>
      </View>
    </View>
  );
}

function PlannedPaymentCandidateSummary({
  candidate,
  locale,
}: {
  candidate: WalletCsvPlannedPaymentCandidate;
  locale: string;
}) {
  return (
    <View style={styles.planCandidateDetails}>
      <View style={styles.accountAuditHeader}>
        <Text variant="titleSmall" numberOfLines={2} style={styles.proposalTitle}>
          {candidate.name}
        </Text>
        <Text variant="labelLarge" numberOfLines={1} style={styles.countText}>
          {Math.round(candidate.confidence)}%
        </Text>
      </View>
      <InfoRow
        icon="cash-clock"
        label="Amount"
        value={plannedPaymentAmountLabel(candidate, locale)}
      />
      <InfoRow
        icon="repeat"
        label="Cadence"
        value={plannedPaymentCadenceLabel(candidate, locale)}
      />
      <InfoRow
        icon="calendar-range"
        label="Evidence"
        value={`${candidate.occurrences} rows · ${candidate.startsOn} to ${candidate.lastSeenOn}`}
      />
      <InfoRow
        icon="calendar-check-outline"
        label="Activity"
        value={plannedPaymentActivityLabel(candidate)}
        tone={candidate.activity === 'active' ? 'positive' : 'warning'}
      />
      <InfoRow icon="wallet-outline" label="Account" value={candidate.accountName} />
      {candidate.categoryName ? (
        <InfoRow icon="shape-outline" label="Category" value={candidate.categoryName} />
      ) : null}
      {candidate.warnings.length > 0 ? (
        <InlineMeta numberOfLines={2} items={candidate.warnings.slice(0, 4)} />
      ) : null}
    </View>
  );
}

function isLoanPlannedPaymentCandidate(candidate: WalletCsvPlannedPaymentCandidate): boolean {
  return candidate.type === 'loan_repayment';
}

function regularPlanCount(candidates: WalletCsvPlannedPaymentCandidate[]): number {
  return candidates.filter((candidate) => !isLoanPlannedPaymentCandidate(candidate)).length;
}

function loanPlanCount(candidates: WalletCsvPlannedPaymentCandidate[]): number {
  return candidates.filter(isLoanPlannedPaymentCandidate).length;
}

function reviewedRegularPlanCount(
  candidates: WalletCsvPlannedPaymentCandidate[],
  pending: WalletCsvPlannedPaymentCandidate[],
): number {
  return regularPlanCount(candidates) - pending.length;
}

function plannedPaymentAmountLabel(candidate: WalletCsvPlannedPaymentCandidate, locale: string) {
  const latest = formatMoney(
    { amountMinor: candidate.latestAmountMinor, currency: candidate.currency },
    locale,
  );
  if (candidate.amountMinMinor === candidate.amountMaxMinor) return latest;
  return `${latest} latest · ${formatMoney(
    { amountMinor: candidate.amountMinMinor, currency: candidate.currency },
    locale,
  )} - ${formatMoney({ amountMinor: candidate.amountMaxMinor, currency: candidate.currency }, locale)}`;
}

function plannedPaymentCadenceLabel(candidate: WalletCsvPlannedPaymentCandidate, locale: string) {
  return recurrenceCadenceLabel(
    candidate.frequency,
    candidate.interval,
    candidate.startsOn,
    candidate.dayOfMonth,
    locale,
  );
}

function plannedPaymentActivityLabel(candidate: WalletCsvPlannedPaymentCandidate) {
  if (candidate.activity === 'active') return `Active · ${candidate.activityReason}`;
  if (candidate.activity === 'needs_review') return `Review · ${candidate.activityReason}`;
  if (candidate.activity === 'already_created')
    return `Already created · ${candidate.matchingRuleName}`;
  return `Old · ${candidate.activityReason}`;
}

function defaultLoanImportDraft(
  state: LedgerState,
  candidate: WalletCsvPlannedPaymentCandidate,
): LoanImportDraft {
  const planDraft = draftFromWalletCsvPlannedPayment(state, candidate);
  const importedRepaymentMinor = loanImportedRepaymentMinor(candidate);
  const outstandingMinor = Math.max(candidate.latestAmountMinor * 60, candidate.latestAmountMinor);
  const principalMinor = Math.max(
    outstandingMinor + importedRepaymentMinor,
    candidate.amountMaxMinor,
  );
  return {
    name: defaultLoanImportName(candidate),
    institution: '',
    accountType: candidate.type === 'income' ? 'lent' : 'loan',
    loanKind: inferLoanKind(candidate),
    principalText: moneyTextFromMinor(principalMinor, candidate.currency),
    outstandingText: moneyTextFromMinor(outstandingMinor, candidate.currency),
    emiText:
      planDraft.amountText || moneyTextFromMinor(candidate.latestAmountMinor, candidate.currency),
    remainingInstallmentsText: '60',
    loanStartedOn: candidate.startsOn,
    nextEmiOn: planDraft.startsOn,
    rateText: '0',
    ratePeriod: 'annual',
    interestMethod: 'reducing_balance',
  };
}

function defaultLoanImportName(candidate: WalletCsvPlannedPaymentCandidate): string {
  const cleaned = candidate.name
    .replace(/\bemi\b/gi, '')
    .replace(/\bpayment\b/gi, '')
    .replace(/\s+/g, ' ')
    .trim();
  if (!cleaned) return 'Imported loan';
  return /loan|overdraft|credit/i.test(cleaned) ? cleaned : `${cleaned} loan`;
}

function inferLoanKind(candidate: WalletCsvPlannedPaymentCandidate): LoanKind {
  const normalized = [
    candidate.name,
    candidate.categoryName,
    candidate.paymentMethod,
    ...(candidate.tags ?? []),
  ]
    .filter(Boolean)
    .join(' ')
    .toLowerCase();
  if (candidate.type === 'income') return 'lent';
  if (normalized.includes('home') || normalized.includes('mortgage')) return 'home';
  if (normalized.includes('vehicle') || normalized.includes('car') || normalized.includes('bike')) {
    return 'vehicle';
  }
  if (normalized.includes('education') || normalized.includes('student')) return 'education';
  if (normalized.includes('business')) return 'business';
  if (normalized.includes('gold')) return 'gold';
  if (normalized.includes('bnpl')) return 'bnpl';
  if (normalized.includes('overdraft')) return 'overdraft';
  return 'personal';
}

function loanKindLabel(kind: LoanKind): string {
  const labels: Record<LoanKind, string> = {
    personal: 'Personal loan',
    home: 'Home loan',
    vehicle: 'Vehicle loan',
    education: 'Education loan',
    business: 'Business loan',
    gold: 'Gold loan',
    bnpl: 'BNPL',
    overdraft: 'Overdraft',
    lent: 'Lent money',
    other: 'Other loan',
  };
  return labels[kind];
}

function interestModelLabel(draft: LoanImportDraft): string {
  const methodLabels: Record<LoanInterestMethod, string> = {
    reducing_balance: 'Reducing balance',
    flat: 'Flat interest',
    interest_only: 'Interest first',
  };
  return `${methodLabels[draft.interestMethod]} · ${draft.ratePeriod}`;
}

function loanImportNotes(
  candidate: WalletCsvPlannedPaymentCandidate,
  outstandingMinor: number,
  importedRepaymentMinor: number,
): string {
  return [
    'Created from Wallet CSV import.',
    `CSV evidence: ${candidate.occurrences} rows from ${candidate.startsOn} to ${candidate.lastSeenOn}.`,
    `Amount left entered: ${moneyTextFromMinor(outstandingMinor, candidate.currency)} ${candidate.currency}.`,
    `Imported repayments in this file: ${moneyTextFromMinor(importedRepaymentMinor, candidate.currency)} ${candidate.currency}.`,
  ].join('\n');
}

function buildLoanImportAccountDraft(
  state: LedgerState,
  candidate: WalletCsvPlannedPaymentCandidate,
  draft: LoanImportDraft,
):
  | {
      ok: true;
      cleanName: string;
      currency: string;
      openingBalanceMinor: number;
      loanDetails: AccountLoanDetails;
    }
  | { ok: false; message: string } {
  const sourceAccount = candidate.accountId
    ? state.accounts.find((account) => account.id === candidate.accountId)
    : undefined;
  const currency = sourceAccount?.currency ?? candidate.currency;
  const cleanName = draft.name.trim();
  const emiMinor = amountMinorFromText(draft.emiText, currency);
  const outstandingMinor = amountMinorFromText(draft.outstandingText, currency);
  const importedRepaymentMinor = loanImportedRepaymentMinor(candidate);
  const requestedPrincipalMinor = amountMinorFromText(draft.principalText, currency);
  const principalMinor = Math.max(requestedPrincipalMinor, outstandingMinor, emiMinor);
  const remainingInstallments = clampWholeNumber(draft.remainingInstallmentsText, 1, 1200, 60);
  const rate = Math.max(0, Number(draft.rateText.replace(/,/g, '').trim()) || 0);

  if (!cleanName) return { ok: false, message: 'Name the loan account' };
  if (!sourceAccount) return { ok: false, message: 'Create or match the repayment account first' };
  if (!emiMinor) return { ok: false, message: 'Enter the principal EMI amount' };
  if (!outstandingMinor) return { ok: false, message: 'Enter the amount left' };
  if (!isDateOnlyValue(draft.loanStartedOn) || !isDateOnlyValue(draft.nextEmiOn)) {
    return { ok: false, message: 'Enter valid loan dates' };
  }

  const openingBalanceMinor = openingBalanceMinorForImportedLoan(
    draft.accountType,
    outstandingMinor,
    importedRepaymentMinor,
  );
  return {
    ok: true,
    cleanName,
    currency,
    openingBalanceMinor,
    loanDetails: {
      loanKind: draft.loanKind,
      principal: { amountMinor: principalMinor, currency },
      disbursedOn: draft.loanStartedOn,
      interestRatePercent: rate,
      interestRatePeriod: draft.ratePeriod,
      interestMethod: draft.interestMethod,
      repaymentSourceAccountId: sourceAccount.id,
      repaymentAmount: { amountMinor: emiMinor, currency },
      repaymentStartsOn: draft.loanStartedOn,
      repaymentFrequency: candidate.frequency,
      repaymentInterval: candidate.interval,
      repaymentDayOfMonth: dateDayFromValue(draft.nextEmiOn),
      repaymentCount: candidate.occurrences + remainingInstallments,
      autoCreateScheduledRecords: true,
      trackingStartsOn: draft.nextEmiOn,
      paidInstallmentsBeforeTracking: candidate.occurrences,
      setupMode: 'track_from_next',
      notes: loanImportNotes(candidate, outstandingMinor, importedRepaymentMinor),
    },
  };
}

function loanImportedRepaymentMinor(candidate: WalletCsvPlannedPaymentCandidate): number {
  return candidate.sourceRows.reduce((sum, row) => sum + row.amountMinor, 0);
}

function openingBalanceMinorForImportedLoan(
  accountType: LoanImportAccountType,
  outstandingMinor: number,
  importedRepaymentMinor: number,
): number {
  const targetBalanceMinor = accountType === 'lent' ? outstandingMinor : -outstandingMinor;
  const importedRepaymentEffectMinor =
    accountType === 'lent' ? -importedRepaymentMinor : importedRepaymentMinor;
  return targetBalanceMinor - importedRepaymentEffectMinor;
}

function moneyTextFromMinor(amountMinor: number, currency: string): string {
  const amount = fromMinor(Math.max(0, amountMinor), currency);
  return Number.isInteger(amount)
    ? String(amount)
    : String(amount).replace(/0+$/, '').replace(/\.$/, '');
}

function amountMinorFromText(value: string, currency: string): number {
  const amount = Number(value.replace(/,/g, '').trim());
  if (!Number.isFinite(amount) || amount <= 0) return 0;
  return toMinor(amount, currency);
}

function clampWholeNumber(value: string, min: number, max: number, fallback: number): number {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function isDateOnlyValue(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(new Date(value).getTime());
}

function dateDayFromValue(value: string): number {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? new Date().getDate() : date.getUTCDate();
}

function uniqueStrings(values: string[]): string[] {
  return Array.from(new Set(values.filter(Boolean)));
}

function importBatchNotes(
  analysis: WalletCsvImportAnalysis,
  provision?: WalletCsvProvisionSummary,
) {
  const created = provision
    ? `${provision.accountsCreated} accounts and ${provision.categoriesCreated} categories created. `
    : '';
  return `${created}${analysis.summary.queueable} queueable, ${analysis.summary.blocked} blocked, ${analysis.summary.duplicates} duplicates, ${analysis.summary.transferPairs} transfer pairs.`;
}

function formatDateRange(range: WalletCsvImportAnalysis['summary']['dateRange']) {
  if (!range.start || !range.end) return 'No valid dates';
  const start = new Date(range.start).toLocaleDateString();
  const end = new Date(range.end).toLocaleDateString();
  return start === end ? start : `${start} - ${end}`;
}

function formatTopValues(values: WalletCsvValueSummary[], limit: number) {
  if (values.length === 0) return 'None';
  return values
    .slice(0, limit)
    .map((item) => `${item.value} (${item.count})`)
    .join(', ');
}

function buildAccountAuditRows(state: LedgerState, analysis: WalletCsvImportAnalysis) {
  return analysis.summary.accounts.map((summary) => {
    const rows = analysis.parsedRows.filter((row) => row.accountName === summary.value);
    const matchedRow = rows.find((row) => row.accountId);
    const matchedAccount = state.accounts.find((account) => account.id === matchedRow?.accountId);
    const matchedAccountVisual = matchedAccount
      ? resolveAccountIconVisual(matchedAccount)
      : undefined;
    const inferredType = inferWalletCsvAccountType(summary.value);
    const typeLabel = matchedAccount
      ? accountTypeLabel(matchedAccount.type)
      : accountTypeLabel(inferredType);
    const currencyLabel =
      matchedAccount?.currency ?? formatCompactCounts(rows.map((row) => row.currency));
    const matchKind = matchedRow?.accountMatch?.kind;
    return {
      csvName: summary.value,
      count: summary.count,
      matchedAccountName: matchedAccount?.name,
      matchedAccountIcon: matchedAccountVisual?.icon,
      matchedAccountBackgroundColor: matchedAccountVisual?.backgroundColor,
      matchedAccountIconColor: matchedAccountVisual?.iconColor,
      typeLabel,
      currencyLabel,
      institution: matchedAccount?.institution ?? inferWalletCsvInstitution(summary.value),
      statusLabel: matchedAccount ? matchKindLabel(matchKind ?? 'exact') : 'Create first',
      matchReason: matchedRow?.accountMatch?.reason,
    };
  });
}

function buildProvisionPreview(analysis: WalletCsvImportAnalysis): WalletCsvProvisionPreview {
  const accountRowsByName = new Map<string, typeof analysis.parsedRows>();
  const categoriesByKey = new Map<
    string,
    { key: string; name: string; count: number; kindLabel: string }
  >();

  for (const row of analysis.parsedRows) {
    if (!row.accountId && row.accountName) {
      const rows = accountRowsByName.get(row.accountName) ?? [];
      rows.push(row);
      accountRowsByName.set(row.accountName, rows);
    }

    if (!row.isTransfer && !row.categoryId && row.categoryName) {
      const kindLabel = row.type === 'Income' ? 'Income' : 'Expense';
      const key = `${kindLabel}:${row.categoryName}`;
      const existing = categoriesByKey.get(key);
      categoriesByKey.set(key, {
        key,
        name: row.categoryName,
        kindLabel,
        count: (existing?.count ?? 0) + 1,
      });
    }
  }

  const accounts = [...accountRowsByName.entries()]
    .map(([name, rows]) => ({
      name,
      count: rows.length,
      typeLabel: accountTypeLabel(inferWalletCsvAccountType(name)),
      currencyLabel: formatCompactCounts(rows.map((row) => row.currency)),
      institution: inferWalletCsvInstitution(name),
    }))
    .sort(sortProvisionRows);

  const categories = [...categoriesByKey.values()].sort(sortProvisionRows);

  return { accounts, categories };
}

function sortProvisionRows(
  left: { name: string; count: number },
  right: { name: string; count: number },
) {
  return right.count - left.count || left.name.localeCompare(right.name);
}

function formatCompactCounts(values: string[], limit = 3) {
  const counts = new Map<string, number>();
  for (const value of values) {
    const label = value.trim();
    if (!label) continue;
    counts.set(label, (counts.get(label) ?? 0) + 1);
  }
  const sorted = [...counts.entries()].sort(
    (left, right) => right[1] - left[1] || left[0].localeCompare(right[0]),
  );
  if (sorted.length === 0) return 'Unknown currency';
  return sorted
    .slice(0, limit)
    .map(([value, count]) => `${value}${count > 1 ? ` (${count})` : ''}`)
    .join(', ');
}

function matchKindLabel(kind: 'exact' | 'alias' | 'similar') {
  if (kind === 'alias') return 'Alias match';
  if (kind === 'similar') return 'Similar-name match';
  return 'Exact match';
}

const styles = StyleSheet.create({
  csvInput: { minHeight: 180 },
  loadedFiles: { flexDirection: 'row', flexWrap: 'wrap', gap: 8, alignItems: 'center' },
  loadingRow: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  provisionGroup: { gap: 8 },
  accountAuditHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  proposalHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  planCandidateBox: { gap: 12 },
  planCandidateDetails: { gap: 8 },
  formRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  formField: { flex: 1, minWidth: 168 },
  actionsRowWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  proposalTitle: { textTransform: 'capitalize', flex: 1 },
  countText: { flexShrink: 0, fontWeight: '800' },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: 8, paddingTop: 8 },
});
