import { formatMoney, fromMinor, normalizeCurrencyCode, toMinor } from '@1wallet/domain/money';
import type {
  Account,
  AccountMessageHint,
  CaptureCandidate,
  Category,
  TransactionType,
} from '@1wallet/domain/types';
import { messageHintSuggestionsFromCapturePayload } from '@1wallet/ledger/capture/messages';
import {
  rejectCaptureCandidate as rejectCaptureCandidateInLedger,
  type ApproveCaptureCandidateInput,
} from '@1wallet/ledger/services';
import { indexedAccountBalance } from '@1wallet/ledger/services/indexes';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { router } from 'expo-router';
import { memo, useCallback, useMemo, useRef, useState } from 'react';
import {
  Alert,
  FlatList,
  KeyboardAvoidingView,
  Modal,
  Platform,
  ScrollView,
  StyleSheet,
  View,
} from 'react-native';
import { Appbar, Button, Chip, Surface, Text, TextInput, useTheme } from 'react-native-paper';
import { resolveAccountIconVisual } from '../src/accountOptions';
import { resolveCategoryIconVisual } from '../src/categoryIcons';
import { useBackLayer } from '../src/components/AppBackLayer';
import { useAppDrawer } from '../src/components/AppDrawerHost';
import { AppMenuAction, PremiumTextInput } from '../src/components/AppKit';
import { OptionListOverlay } from '../src/components/OptionListOverlay';
import { PulsingFieldGlow } from '../src/components/PulsingFieldGlow';
import { RecordDateTimeFields } from '../src/components/record/RecordDateTimeFields';
import {
  AccountPickerOverlay,
  CategoryPickerOverlay,
} from '../src/components/record/RecordPickers';
import { RecordSelectorRow } from '../src/components/record/RecordSelectorRow';
import {
  dateTimeToIso,
  isValidLocalDate,
  isValidLocalTime,
  localDateTimeParts,
} from '../src/recordDateTime';
import {
  isTransferTransactionType,
  TRANSACTION_TYPE_OPTIONS,
  transactionTypeLabel,
} from '../src/transactionTypes';

type SourceFilter = 'all' | 'import' | 'sms' | 'email' | 'notification';
type ApprovalPickerMode = 'account' | 'counter' | 'category' | 'type' | null;
type ApprovalField = 'amount' | 'account' | 'counter' | 'category' | 'type' | 'date' | 'merchant';

type ApprovalDraft = {
  candidateId: string;
  amount: string;
  currency: string;
  type: TransactionType;
  accountId?: string;
  counterAccountId?: string;
  categoryId?: string;
  date: string;
  time: string;
  merchantNote: string;
};

const SOURCE_FILTERS: SourceFilter[] = ['all', 'import', 'sms', 'notification', 'email'];
export default function ReviewQueue() {
  const theme = useTheme();
  const [sourceFilter, setSourceFilter] = useState<SourceFilter>('all');
  const [bulkApprovalRunning, setBulkApprovalRunning] = useState(false);
  const [bulkRejectRunning, setBulkRejectRunning] = useState(false);
  const [approvalDraft, setApprovalDraft] = useState<ApprovalDraft | undefined>();
  const [approvalPicker, setApprovalPicker] = useState<ApprovalPickerMode>(null);
  const [highlightedApprovalFields, setHighlightedApprovalFields] = useState<Set<ApprovalField>>(
    () => new Set(),
  );
  const [approvalGlowPulseKey, setApprovalGlowPulseKey] = useState(0);
  const approvalScrollRef = useRef<ScrollView>(null);
  const { openDrawer } = useAppDrawer();
  const {
    state,
    approveCaptureCandidate,
    approveCaptureCandidates,
    rejectCaptureCandidate,
    mutate,
    indexes,
  } = useLedger();
  const allPending = useMemo(
    () => indexes.captureCandidatesByStatus.get('pending') ?? [],
    [indexes.captureCandidatesByStatus],
  );
  const pending = useMemo(
    () =>
      allPending.filter((candidate) => sourceFilter === 'all' || candidate.source === sourceFilter),
    [allPending, sourceFilter],
  );
  const pendingSourceCounts = useMemo(() => captureSourceCounts(allPending), [allPending]);
  const activeAccounts = useMemo(
    () => state.accounts.filter((account) => !account.isArchived),
    [state.accounts],
  );
  const accountById = indexes.accountsById;
  const categoryById = indexes.categoriesById;
  const rulesById = useMemo(
    () => new Map((state.preferences.futureGenerationRules ?? []).map((rule) => [rule.id, rule])),
    [state.preferences.futureGenerationRules],
  );
  const captureCandidateById = useMemo(
    () => new Map(state.captureCandidates.map((candidate) => [candidate.id, candidate])),
    [state.captureCandidates],
  );
  const approvalCandidate = approvalDraft
    ? captureCandidateById.get(approvalDraft.candidateId)
    : undefined;
  const approvalAccount = approvalDraft?.accountId
    ? accountById.get(approvalDraft.accountId)
    : undefined;
  const approvalCounterAccount = approvalDraft?.counterAccountId
    ? accountById.get(approvalDraft.counterAccountId)
    : undefined;
  const approvalAccountVisual = approvalAccount
    ? resolveAccountIconVisual(approvalAccount)
    : undefined;
  const approvalCounterAccountVisual = approvalCounterAccount
    ? resolveAccountIconVisual(approvalCounterAccount)
    : undefined;
  const approvalNeedsCounter = approvalDraft
    ? isTransferTransactionType(approvalDraft.type)
    : false;
  const approvalCategory = approvalDraft?.categoryId
    ? categoryById.get(approvalDraft.categoryId)
    : undefined;
  const approvalCategoryVisual = approvalCategory
    ? resolveCategoryIconVisual(approvalCategory, state.categories)
    : undefined;
  const approvalCurrency =
    approvalAccount?.currency ?? approvalDraft?.currency ?? state.preferences.baseCurrency;

  const flashApprovalFields = useCallback((fields: ApprovalField[]) => {
    const uniqueFields = Array.from(new Set(fields));
    setHighlightedApprovalFields(new Set(uniqueFields));
    setApprovalGlowPulseKey((key) => key + 1);
  }, []);

  const openApproval = useCallback(
    (candidate: CaptureCandidate) => {
      const draft = approvalDraftFromCandidate(candidate, state.preferences.baseCurrency);
      setApprovalDraft(draft);
      setApprovalPicker(null);
    },
    [state.preferences.baseCurrency],
  );

  const updateApprovalDraft = useCallback((patch: Partial<ApprovalDraft>) => {
    setApprovalDraft((current) => (current ? { ...current, ...patch } : current));
  }, []);

  const closeApproval = useCallback(() => {
    setApprovalDraft(undefined);
    setApprovalPicker(null);
    setHighlightedApprovalFields(new Set());
  }, []);

  useBackLayer(Boolean(approvalDraft), closeApproval);

  const messageHintsForApproval = useCallback(
    (candidate: CaptureCandidate, accountId: string): AccountMessageHint[] => {
      const account = accountById.get(accountId);
      if (!account) return [];
      return messageHintSuggestionsFromCapturePayload(account, candidate.rawPayload).filter(
        (hint) => !hint.existing,
      );
    },
    [accountById],
  );

  const buildApprovalInput = useCallback(
    (
      candidate: CaptureCandidate,
      draft: ApprovalDraft,
    ): { input?: ApproveCaptureCandidateInput; missing: ApprovalField[] } => {
      const missing = approvalMissingFields(draft);
      const account = draft.accountId ? accountById.get(draft.accountId) : undefined;
      if (!account) {
        if (!missing.includes('account')) missing.push('account');
        return { missing };
      }
      if (missing.length) {
        return { missing };
      }
      const numericAmount = Number(draft.amount.replace(/,/g, '').trim());
      const amountMinor = toMinor(
        draft.type === 'adjustment' ? numericAmount : Math.abs(numericAmount),
        account.currency,
      );
      const parsedCounterAmount =
        isTransferTransactionType(draft.type) &&
        candidate.parsedCounterAmount &&
        candidate.suggestedAccountId === account.id &&
        candidate.suggestedCounterAccountId === draft.counterAccountId &&
        candidate.parsedAmount?.amountMinor === amountMinor
          ? candidate.parsedCounterAmount
          : undefined;
      const acceptedMessageHints = messageHintsForApproval(candidate, account.id);
      return {
        missing: [],
        input: {
          type: draft.type,
          accountId: account.id,
          counterAccountId: isTransferTransactionType(draft.type)
            ? draft.counterAccountId
            : undefined,
          amountMinor,
          currency: account.currency,
          counterAmountMinor: parsedCounterAmount?.amountMinor,
          counterCurrency: parsedCounterAmount?.currency,
          counterFxRate: parsedCounterAmount ? candidate.parsedCounterFxRate : undefined,
          categoryId: approvalUsesCategory(draft.type) ? draft.categoryId : undefined,
          occurredAt: dateTimeToIso(draft.date, draft.time),
          notes: draft.merchantNote.trim() || undefined,
          acceptedMessageHints: acceptedMessageHints.length ? acceptedMessageHints : undefined,
        },
      };
    },
    [accountById, messageHintsForApproval],
  );

  const submitApproval = async () => {
    if (!approvalDraft || !approvalCandidate) return;
    const { input, missing } = buildApprovalInput(approvalCandidate, approvalDraft);
    if (missing.length || !input) {
      flashApprovalFields(missing);
      return;
    }
    try {
      await approveCaptureCandidate(approvalCandidate.id, input);
      closeApproval();
    } catch (error) {
      Alert.alert('Cannot approve capture', (error as Error).message);
    }
  };

  const submitBulkApproval = async () => {
    if (bulkApprovalRunning || pending.length === 0) return;
    const approvals = pending.flatMap((candidate) => {
      const draft = approvalDraftFromCandidate(candidate, state.preferences.baseCurrency);
      const { input } = buildApprovalInput(candidate, draft);
      return input ? [{ id: candidate.id, input }] : [];
    });
    const skipped = pending.length - approvals.length;
    if (approvals.length === 0) {
      Alert.alert('Nothing ready to approve', 'These captures need manual review first.');
      return;
    }

    setBulkApprovalRunning(true);
    try {
      await approveCaptureCandidates(approvals);
      Alert.alert(
        'Approved',
        skipped > 0
          ? `Approved ${approvals.length}. ${skipped} still need manual review.`
          : `Approved ${approvals.length}.`,
      );
    } catch (error) {
      Alert.alert('Cannot approve all', (error as Error).message);
    } finally {
      setBulkApprovalRunning(false);
    }
  };

  const confirmBulkApproval = () => {
    if (bulkApprovalRunning || bulkRejectRunning || pending.length === 0) return;
    Alert.alert('Approve all?', `Approve ${pending.length} visible captures?`, [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Approve all', onPress: () => void submitBulkApproval() },
    ]);
  };

  const submitBulkReject = async () => {
    if (bulkRejectRunning || pending.length === 0) return;
    const ids = pending.map((candidate) => candidate.id);
    setBulkRejectRunning(true);
    try {
      await mutate(
        (draft) => {
          ids.forEach((id) => {
            rejectCaptureCandidateInLedger(draft, id);
          });
        },
        { slices: ['captureCandidates'] },
      );
      Alert.alert('Rejected', `Rejected ${ids.length} visible captures.`);
    } catch (error) {
      Alert.alert('Cannot reject all', (error as Error).message);
    } finally {
      setBulkRejectRunning(false);
    }
  };

  const confirmBulkReject = () => {
    if (bulkApprovalRunning || bulkRejectRunning || pending.length === 0) return;
    Alert.alert('Reject all?', `Reject ${pending.length} visible captures?`, [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Reject all',
        style: 'destructive',
        onPress: () => void submitBulkReject(),
      },
    ]);
  };

  const approvalGlowProps = (field: ApprovalField) => ({
    active: highlightedApprovalFields.has(field),
    color: theme.colors.error,
    dark: theme.dark,
    pulseKey: approvalGlowPulseKey,
  });

  const scrollApprovalToEnd = () => {
    setTimeout(
      () => approvalScrollRef.current?.scrollToEnd({ animated: true }),
      Platform.OS === 'android' ? 360 : 220,
    );
  };

  const renderCaptureCandidate = useCallback(
    ({ item }: { item: CaptureCandidate }) => (
      <CaptureCandidateCard
        candidate={item}
        account={item.suggestedAccountId ? accountById.get(item.suggestedAccountId) : undefined}
        counterAccount={
          item.suggestedCounterAccountId
            ? accountById.get(item.suggestedCounterAccountId)
            : undefined
        }
        category={item.suggestedCategoryId ? categoryById.get(item.suggestedCategoryId) : undefined}
        linkedPlanName={
          item.suggestedRecurringTemplateId
            ? rulesById.get(item.suggestedRecurringTemplateId)?.name
            : undefined
        }
        locale={state.preferences.locale}
        onApprove={openApproval}
        onReject={rejectCaptureCandidate}
      />
    ),
    [
      accountById,
      categoryById,
      openApproval,
      rejectCaptureCandidate,
      rulesById,
      state.preferences.locale,
    ],
  );

  return (
    <View style={{ flex: 1, backgroundColor: theme.colors.background }}>
      <Appbar.Header elevated={false} style={{ backgroundColor: theme.colors.background }}>
        <AppMenuAction onPress={openDrawer} />
        <Appbar.Content title="Review queue" titleStyle={s.appbarTitle} />
      </Appbar.Header>
      <FlatList
        data={pending}
        keyExtractor={(candidate) => candidate.id}
        contentContainerStyle={{ padding: tokens.space.lg, gap: tokens.space.md }}
        removeClippedSubviews={Platform.OS === 'android'}
        initialNumToRender={8}
        maxToRenderPerBatch={6}
        updateCellsBatchingPeriod={32}
        windowSize={7}
        ListHeaderComponent={
          <View style={s.listHeader}>
            <View style={s.filterBar}>
              {SOURCE_FILTERS.map((filter) => (
                <Chip
                  key={filter}
                  compact
                  selected={sourceFilter === filter}
                  onPress={() => setSourceFilter(filter)}
                >
                  {filterLabel(filter, pendingSourceCounts)}
                </Chip>
              ))}
            </View>
            {pending.length > 0 ? (
              <View style={s.bulkActions}>
                <Button
                  mode="contained"
                  icon="check-all"
                  loading={bulkApprovalRunning}
                  disabled={bulkApprovalRunning || bulkRejectRunning}
                  onPress={confirmBulkApproval}
                  accessibilityLabel={`Approve all ${pending.length} visible captures`}
                  style={s.bulkActionButton}
                >
                  Approve all
                </Button>
                <Button
                  mode="outlined"
                  icon="close-circle-outline"
                  textColor={theme.colors.error}
                  loading={bulkRejectRunning}
                  disabled={bulkApprovalRunning || bulkRejectRunning}
                  onPress={confirmBulkReject}
                  accessibilityLabel={`Reject all ${pending.length} visible captures`}
                  style={s.bulkActionButton}
                >
                  Reject all
                </Button>
              </View>
            ) : null}
          </View>
        }
        ListEmptyComponent={
          <View style={s.empty}>
            <Text variant="titleMedium" style={s.emptyTitle}>
              No captures waiting
            </Text>
            <Text variant="bodyMedium" style={{ color: theme.colors.onSurfaceVariant }}>
              Review queue clear.
            </Text>
          </View>
        }
        renderItem={renderCaptureCandidate}
      />
      <Modal
        visible={Boolean(approvalDraft)}
        transparent
        animationType="none"
        statusBarTranslucent
        onRequestClose={closeApproval}
      >
        <KeyboardAvoidingView
          behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
          keyboardVerticalOffset={tokens.space.lg}
          style={[s.approvalOverlay, { backgroundColor: theme.colors.backdrop }]}
        >
          <Surface
            elevation={4}
            style={[s.approvalSheet, { backgroundColor: theme.colors.elevation.level3 }]}
          >
            <Text variant="titleLarge" style={s.approvalTitle}>
              Approve capture
            </Text>
            <ScrollView
              ref={approvalScrollRef}
              style={s.approvalScroll}
              contentContainerStyle={s.approvalContent}
              keyboardDismissMode="on-drag"
              keyboardShouldPersistTaps="handled"
            >
              {approvalDraft ? (
                <>
                  <PulsingFieldGlow {...approvalGlowProps('amount')}>
                    <PremiumTextInput
                      label="Amount"
                      value={approvalDraft.amount}
                      onChangeText={(value) => updateApprovalDraft({ amount: value })}
                      keyboardType="decimal-pad"
                      left={<TextInput.Affix text={approvalCurrency} />}
                    />
                  </PulsingFieldGlow>
                  <PulsingFieldGlow {...approvalGlowProps('type')}>
                    <RecordSelectorRow
                      icon="shape-outline"
                      label="Type"
                      value={transactionTypeLabel(approvalDraft.type)}
                      onPress={() => setApprovalPicker('type')}
                    />
                  </PulsingFieldGlow>
                  <PulsingFieldGlow {...approvalGlowProps('account')}>
                    <RecordSelectorRow
                      icon={approvalAccountVisual?.icon ?? 'wallet-outline'}
                      iconBackgroundColor={approvalAccountVisual?.backgroundColor}
                      iconColor={approvalAccountVisual?.iconColor}
                      label={approvalNeedsCounter ? 'From account' : 'Account'}
                      value={approvalAccount?.name ?? 'Choose account'}
                      valueNumberOfLines={2}
                      onPress={() => setApprovalPicker('account')}
                    />
                  </PulsingFieldGlow>
                  {approvalNeedsCounter ? (
                    <PulsingFieldGlow {...approvalGlowProps('counter')}>
                      <RecordSelectorRow
                        icon={approvalCounterAccountVisual?.icon ?? 'swap-horizontal'}
                        iconBackgroundColor={approvalCounterAccountVisual?.backgroundColor}
                        iconColor={approvalCounterAccountVisual?.iconColor}
                        label="To account"
                        value={approvalCounterAccount?.name ?? 'Choose destination'}
                        valueNumberOfLines={2}
                        onPress={() => setApprovalPicker('counter')}
                      />
                    </PulsingFieldGlow>
                  ) : null}
                  {approvalUsesCategory(approvalDraft.type) ? (
                    <PulsingFieldGlow {...approvalGlowProps('category')}>
                      <RecordSelectorRow
                        icon={approvalCategoryVisual?.icon ?? 'shape-outline'}
                        iconBackgroundColor={approvalCategoryVisual?.backgroundColor}
                        iconColor={approvalCategoryVisual?.iconColor}
                        label="Category"
                        value={approvalCategory?.name ?? 'Choose category'}
                        valueNumberOfLines={2}
                        onPress={() => setApprovalPicker('category')}
                      />
                    </PulsingFieldGlow>
                  ) : null}
                  <PulsingFieldGlow {...approvalGlowProps('date')}>
                    <RecordDateTimeFields
                      date={approvalDraft.date}
                      time={approvalDraft.time}
                      layout="stacked"
                      onChangeDate={(date) => updateApprovalDraft({ date })}
                      onChangeTime={(time) => updateApprovalDraft({ time })}
                    />
                  </PulsingFieldGlow>
                  <PulsingFieldGlow {...approvalGlowProps('merchant')}>
                    <PremiumTextInput
                      label="Merchant / notes"
                      value={approvalDraft.merchantNote}
                      onChangeText={(merchantNote) => updateApprovalDraft({ merchantNote })}
                      onFocus={scrollApprovalToEnd}
                      left={<TextInput.Icon icon="storefront-outline" />}
                    />
                  </PulsingFieldGlow>
                </>
              ) : null}
            </ScrollView>
            <View style={s.approvalActions}>
              <Button onPress={closeApproval}>Cancel</Button>
              <Button mode="contained" onPress={() => void submitApproval()}>
                Approve
              </Button>
            </View>
          </Surface>
        </KeyboardAvoidingView>
      </Modal>
      <AccountPickerOverlay
        visible={approvalPicker === 'account' || approvalPicker === 'counter'}
        title={approvalPicker === 'counter' ? 'Choose destination' : 'Choose account'}
        accounts={
          approvalPicker === 'counter'
            ? activeAccounts.filter((account) => account.id !== approvalDraft?.accountId)
            : activeAccounts
        }
        selectedId={
          approvalPicker === 'counter' ? approvalDraft?.counterAccountId : approvalDraft?.accountId
        }
        balances={(account) =>
          formatMoney(indexedAccountBalance(indexes, account), state.preferences.locale)
        }
        onDismiss={() => setApprovalPicker(null)}
        onCreate={() => {
          setApprovalPicker(null);
          router.push('/account/new' as never);
        }}
        onSelect={(account) => {
          if (approvalPicker === 'counter') updateApprovalDraft({ counterAccountId: account.id });
          else {
            updateApprovalDraft({
              accountId: account.id,
              currency: account.currency,
              counterAccountId:
                approvalDraft?.counterAccountId === account.id
                  ? undefined
                  : approvalDraft?.counterAccountId,
            });
          }
          setApprovalPicker(null);
        }}
      />
      <CategoryPickerOverlay
        visible={approvalPicker === 'category' && Boolean(approvalDraft)}
        categories={state.categories}
        selectedId={approvalDraft?.categoryId}
        allowClear={false}
        leafOnly
        onDismiss={() => setApprovalPicker(null)}
        onSelect={(category) => {
          updateApprovalDraft({ categoryId: category.id });
          setApprovalPicker(null);
        }}
      />
      <OptionListOverlay
        visible={approvalPicker === 'type' && Boolean(approvalDraft)}
        title="Transaction type"
        options={TRANSACTION_TYPE_OPTIONS}
        selectedValue={approvalDraft?.type}
        searchable={false}
        onDismiss={() => setApprovalPicker(null)}
        onSelect={(option) => {
          const nextType = option.value;
          updateApprovalDraft({
            type: nextType,
            counterAccountId: isTransferTransactionType(nextType)
              ? approvalDraft?.counterAccountId
              : undefined,
            categoryId: approvalUsesCategory(nextType) ? approvalDraft?.categoryId : undefined,
          });
          setApprovalPicker(null);
        }}
      />
    </View>
  );
}

const CaptureCandidateCard = memo(function CaptureCandidateCard({
  candidate,
  account,
  counterAccount,
  category,
  linkedPlanName,
  locale,
  onApprove,
  onReject,
}: {
  candidate: CaptureCandidate;
  account?: Account;
  counterAccount?: Account;
  category?: Category;
  linkedPlanName?: string;
  locale: string;
  onApprove: (candidate: CaptureCandidate) => void;
  onReject: (id: string) => Promise<void>;
}) {
  const theme = useTheme();
  const walletCsvRows = useMemo(
    () => walletCsvCaptureRows(candidate.rawPayload),
    [candidate.rawPayload],
  );
  const receiptFileName =
    typeof candidate.rawPayload.fileName === 'string' ? candidate.rawPayload.fileName : undefined;
  const needsCounter = candidate.suggestedType
    ? isTransferTransactionType(candidate.suggestedType)
    : false;
  const approve = useCallback(() => onApprove(candidate), [candidate, onApprove]);
  const reject = useCallback(() => {
    void onReject(candidate.id).catch((error) => {
      Alert.alert('Cannot reject capture', (error as Error).message);
    });
  }, [candidate.id, onReject]);

  return (
    <Surface
      style={[
        s.card,
        {
          backgroundColor: theme.colors.elevation.level1,
          borderColor: theme.colors.outlineVariant,
        },
      ]}
      elevation={1}
    >
      <View style={s.cardHeader}>
        <Text variant="labelMedium" style={[s.source, { color: theme.colors.primary }]}>
          {candidate.source.toUpperCase()}
        </Text>
        <Text variant="labelMedium" style={{ color: theme.colors.onSurfaceVariant }}>
          {Math.round(candidate.confidence)}%
        </Text>
      </View>
      <Text variant="headlineSmall" style={s.amount}>
        {candidate.parsedAmount ? formatMoney(candidate.parsedAmount, locale) : 'Amount missing'}
      </Text>
      <Text variant="bodyMedium" style={{ color: theme.colors.onSurfaceVariant }}>
        {candidate.parsedMerchant ?? 'Unknown merchant'}
      </Text>
      <View style={s.metaGrid}>
        <Meta
          label="Type"
          value={
            candidate.suggestedType ? transactionTypeLabel(candidate.suggestedType) : 'Needs review'
          }
          labelColor={theme.colors.onSurfaceVariant}
          valueColor={theme.colors.onSurface}
        />
        <Meta
          label="Account"
          value={account?.name ?? 'Needs review'}
          labelColor={theme.colors.onSurfaceVariant}
          valueColor={theme.colors.onSurface}
        />
        {needsCounter ? (
          <Meta
            label="To account"
            value={counterAccount?.name ?? 'Needs review'}
            labelColor={theme.colors.onSurfaceVariant}
            valueColor={theme.colors.onSurface}
          />
        ) : null}
        {candidate.suggestedType === 'adjustment' ? null : (
          <Meta
            label="Category"
            value={category?.name ?? 'Uncategorized'}
            labelColor={theme.colors.onSurfaceVariant}
            valueColor={theme.colors.onSurface}
          />
        )}
        {linkedPlanName ? (
          <Meta
            label="Plan"
            value={linkedPlanName}
            labelColor={theme.colors.onSurfaceVariant}
            valueColor={theme.colors.primary}
          />
        ) : null}
        <Meta
          label="Date"
          value={
            candidate.parsedOccurredAt
              ? new Date(candidate.parsedOccurredAt).toLocaleString()
              : 'Needs review'
          }
          labelColor={theme.colors.onSurfaceVariant}
          valueColor={theme.colors.onSurface}
        />
        {candidate.parsedLocationLabel ? (
          <Meta
            label="Place"
            value={candidate.parsedLocationLabel}
            labelColor={theme.colors.onSurfaceVariant}
            valueColor={theme.colors.onSurface}
          />
        ) : null}
        {receiptFileName ? (
          <Meta
            label="Receipt"
            value={receiptFileName}
            labelColor={theme.colors.onSurfaceVariant}
            valueColor={theme.colors.onSurface}
          />
        ) : null}
      </View>
      {walletCsvRows.length > 0 ? (
        <View style={s.csvBox}>
          <Text variant="titleSmall" style={s.hintTitle}>
            Wallet CSV source
          </Text>
          {walletCsvRows.map((row, index) => (
            <Text
              key={`${row.fileName}:${row.rowNumber}:${index}`}
              variant="bodySmall"
              style={{ color: theme.colors.onSurfaceVariant }}
            >
              {row.fileName ? `${row.fileName} · ` : ''}
              {row.rowNumber ? `row ${row.rowNumber} · ` : ''}
              {row.accountName}
              {row.matchedAccountName && row.matchedAccountName !== row.accountName
                ? ` -> ${row.matchedAccountName}`
                : ''}
              {' · '}
              {row.categoryName || 'No category'} · {row.amount} {row.currency}
              {row.payee ? ` · ${row.payee}` : row.note ? ` · ${row.note}` : ''}
            </Text>
          ))}
        </View>
      ) : null}
      <View style={s.actions}>
        <Button mode="contained" icon="check" style={s.actionButton} onPress={approve}>
          Approve
        </Button>
        <Button
          mode="outlined"
          textColor={theme.colors.error}
          icon="close"
          style={s.actionButton}
          onPress={reject}
        >
          Reject
        </Button>
      </View>
    </Surface>
  );
});

function Meta({
  label,
  value,
  labelColor,
  valueColor,
}: {
  label: string;
  value: string;
  labelColor: string;
  valueColor: string;
}) {
  return (
    <View style={s.metaItem}>
      <Text variant="bodySmall" style={[s.metaLabel, { color: labelColor }]}>
        {label}
      </Text>
      <Text variant="bodySmall" style={[s.metaValue, { color: valueColor }]}>
        {value}
      </Text>
    </View>
  );
}

function captureSourceCounts(candidates: CaptureCandidate[]): Map<SourceFilter, number> {
  const counts = new Map<SourceFilter, number>(SOURCE_FILTERS.map((filter) => [filter, 0]));
  counts.set('all', candidates.length);
  for (const candidate of candidates) {
    if (SOURCE_FILTERS.includes(candidate.source as SourceFilter)) {
      counts.set(
        candidate.source as SourceFilter,
        (counts.get(candidate.source as SourceFilter) ?? 0) + 1,
      );
    }
  }
  return counts;
}

function filterLabel(filter: SourceFilter, counts: Map<SourceFilter, number>): string {
  if (filter === 'all') return `${counts.get('all') ?? 0} total`;
  const count = counts.get(filter) ?? 0;
  return `${filter === 'notification' ? 'Notif' : filter.toUpperCase()} ${count}`;
}

function approvalDraftFromCandidate(
  candidate: CaptureCandidate,
  fallbackCurrency: string,
): ApprovalDraft {
  const currency = normalizeCurrencyCode(candidate.parsedAmount?.currency ?? fallbackCurrency);
  const dateTime = localDateTimeParts(
    candidate.parsedOccurredAt && !Number.isNaN(new Date(candidate.parsedOccurredAt).getTime())
      ? new Date(candidate.parsedOccurredAt)
      : new Date(),
  );
  const amount = candidate.parsedAmount
    ? trimNumber(fromMinor(candidate.parsedAmount.amountMinor, currency))
    : '';
  return {
    candidateId: candidate.id,
    amount,
    currency,
    type: candidate.suggestedType ?? 'expense',
    accountId: candidate.suggestedAccountId,
    counterAccountId: candidate.suggestedCounterAccountId,
    categoryId: candidate.suggestedCategoryId,
    date: dateTime.date,
    time: dateTime.time,
    merchantNote: candidate.parsedNotes ?? candidate.parsedMerchant ?? '',
  };
}

function approvalMissingFields(
  draft: ApprovalDraft,
  { includeSoftFields = false }: { includeSoftFields?: boolean } = {},
): ApprovalField[] {
  const missing: ApprovalField[] = [];
  const amount = Number(draft.amount.replace(/,/g, '').trim());
  if (
    !Number.isFinite(amount) ||
    (draft.type === 'adjustment' ? amount === 0 : Math.abs(amount) <= 0)
  ) {
    missing.push('amount');
  }
  if (!draft.type) missing.push('type');
  if (!draft.accountId) missing.push('account');
  if (isTransferTransactionType(draft.type) && !draft.counterAccountId) missing.push('counter');
  if (approvalUsesCategory(draft.type) && !draft.categoryId) missing.push('category');
  if (!isValidLocalDate(draft.date) || !isValidLocalTime(draft.time)) missing.push('date');
  if (includeSoftFields && !draft.merchantNote.trim()) missing.push('merchant');
  return missing;
}

function approvalUsesCategory(type: TransactionType): boolean {
  return !isTransferTransactionType(type) && type !== 'adjustment';
}

function trimNumber(value: number): string {
  if (!Number.isFinite(value)) return '';
  return String(Math.round(value * 100) / 100);
}

type WalletCsvCaptureRow = {
  fileName: string;
  rowNumber: string;
  accountName: string;
  matchedAccountName?: string;
  categoryName: string;
  currency: string;
  amount: string;
  payee?: string;
  note?: string;
};

function walletCsvCaptureRows(rawPayload: Record<string, unknown>): WalletCsvCaptureRow[] {
  if (rawPayload.source !== 'wallet_csv') return [];
  const refs = Array.isArray(rawPayload.rowRefs) ? rawPayload.rowRefs : [];
  if (refs.length > 0) return refs.map(normalizeWalletCsvRowRef).filter(isWalletCsvCaptureRow);

  const rows = Array.isArray(rawPayload.rows) ? rawPayload.rows : [];
  return rows.map(normalizeWalletCsvRawRow).filter(isWalletCsvCaptureRow);
}

function isWalletCsvCaptureRow(
  value: WalletCsvCaptureRow | undefined,
): value is WalletCsvCaptureRow {
  return Boolean(value);
}

function normalizeWalletCsvRowRef(value: unknown): WalletCsvCaptureRow | undefined {
  if (!value || typeof value !== 'object') return undefined;
  const row = value as Record<string, unknown>;
  const accountName = stringValue(row.accountName);
  if (!accountName) return undefined;
  return {
    fileName: stringValue(row.fileName),
    rowNumber: stringValue(row.rowNumber),
    accountName,
    matchedAccountName: optionalStringValue(row.matchedAccountName),
    categoryName: stringValue(row.categoryName),
    currency: stringValue(row.currency),
    amount: stringValue(row.amount),
    payee: optionalStringValue(row.payee),
    note: optionalStringValue(row.note),
  };
}

function normalizeWalletCsvRawRow(value: unknown): WalletCsvCaptureRow | undefined {
  if (!value || typeof value !== 'object') return undefined;
  const row = value as Record<string, unknown>;
  const accountName = stringValue(row.account);
  if (!accountName) return undefined;
  return {
    fileName: '',
    rowNumber: '',
    accountName,
    categoryName: stringValue(row.category),
    currency: stringValue(row.currency),
    amount: stringValue(row.amount),
    payee: optionalStringValue(row.payee),
    note: optionalStringValue(row.note),
  };
}

function stringValue(value: unknown): string {
  if (typeof value === 'string') return value;
  if (typeof value === 'number') return String(value);
  return '';
}

function optionalStringValue(value: unknown): string | undefined {
  const text = stringValue(value).trim();
  return text || undefined;
}

const s = StyleSheet.create({
  appbarTitle: { fontWeight: '700' },
  listHeader: { gap: tokens.space.sm },
  filterBar: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  bulkActions: { flexDirection: 'row', flexWrap: 'wrap', gap: tokens.space.sm },
  bulkActionButton: { flexGrow: 1, borderRadius: tokens.radius.md },
  header: {
    borderRadius: tokens.radius.md,
    padding: tokens.space.lg,
    borderWidth: 1,
    gap: tokens.space.xs,
  },
  title: { fontWeight: '800' },
  empty: { padding: tokens.space.xxl, alignItems: 'center', gap: tokens.space.xs },
  emptyTitle: { fontWeight: '700' },
  card: {
    borderRadius: tokens.radius.md,
    padding: tokens.space.md,
    borderWidth: 1,
    gap: tokens.space.xs,
  },
  cardHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  source: { fontWeight: '800' },
  amount: { fontWeight: '800' },
  metaGrid: { gap: tokens.space.xs, marginTop: tokens.space.xs },
  metaItem: { flexDirection: 'row', justifyContent: 'space-between', gap: tokens.space.md },
  metaLabel: {},
  metaValue: {
    fontWeight: '600',
    flexShrink: 1,
    textAlign: 'right',
  },
  actions: {
    flexDirection: 'row',
    gap: tokens.space.sm,
    marginTop: tokens.space.sm,
  },
  hintBox: { gap: tokens.space.sm, marginTop: tokens.space.xs },
  csvBox: { gap: 4, marginTop: tokens.space.xs },
  hintTitle: { fontWeight: '700' },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  warningBox: {
    borderRadius: tokens.radius.md,
    padding: tokens.space.sm,
    gap: 2,
  },
  actionButton: { flexGrow: 1, borderRadius: tokens.radius.md },
  approvalOverlay: {
    flex: 1,
    justifyContent: 'center',
    padding: tokens.space.lg,
  },
  approvalSheet: {
    borderRadius: tokens.radius.lg,
    maxHeight: '88%',
    overflow: 'hidden',
  },
  approvalTitle: {
    fontWeight: '700',
    paddingHorizontal: tokens.space.lg,
    paddingTop: tokens.space.lg,
    paddingBottom: tokens.space.sm,
  },
  approvalScroll: { maxHeight: 520 },
  approvalActions: {
    flexDirection: 'row',
    justifyContent: 'flex-end',
    gap: tokens.space.sm,
    padding: tokens.space.md,
    paddingTop: tokens.space.sm,
  },
  approvalContent: {
    gap: tokens.space.sm,
    paddingHorizontal: tokens.space.lg,
    paddingBottom: tokens.space.xxl,
    paddingTop: tokens.space.md,
  },
});
