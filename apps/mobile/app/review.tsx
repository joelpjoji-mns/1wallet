import { formatMoney, fromMinor, normalizeCurrencyCode, toMinor } from '@1wallet/domain/money';
import type { AccountMessageHint, CaptureCandidate, TransactionType } from '@1wallet/domain/types';
import { messageHintSuggestionsFromCapturePayload } from '@1wallet/ledger/capture/messages';
import {
    rejectCaptureCandidate as rejectCaptureCandidateInLedger,
    type ApproveCaptureCandidateInput,
} from '@1wallet/ledger/services';
import { indexedAccountBalance } from '@1wallet/ledger/services/indexes';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { router, useFocusEffect } from 'expo-router';
import { useCallback, useRef, useState } from 'react';
import {
    Alert,
    FlatList,
    KeyboardAvoidingView,
    Platform,
    ScrollView,
    StyleSheet,
    View,
} from 'react-native';
import {
    Appbar,
    Button,
    Chip,
    Dialog,
    Portal,
    Surface,
    Text,
    TextInput,
    useTheme,
} from 'react-native-paper';
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
    categoryKindForTransactionType,
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
    reload,
    selectors,
    indexes,
  } = useLedger();
  const allPending = selectors.queryCaptureCandidates(state, { status: 'pending' });
  const pending = allPending.filter(
    (candidate) => sourceFilter === 'all' || candidate.source === sourceFilter,
  );
  const activeAccounts = state.accounts.filter((account) => !account.isArchived);
  const approvalCandidate = approvalDraft
    ? state.captureCandidates.find((candidate) => candidate.id === approvalDraft.candidateId)
    : undefined;
  const approvalAccount = approvalDraft?.accountId
    ? state.accounts.find((account) => account.id === approvalDraft.accountId)
    : undefined;
  const approvalCounterAccount = approvalDraft?.counterAccountId
    ? state.accounts.find((account) => account.id === approvalDraft.counterAccountId)
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
  const approvalCategoryKind = approvalDraft
    ? categoryKindForTransactionType(approvalDraft.type)
    : 'expense';
  const approvalCategory = approvalDraft?.categoryId
    ? state.categories.find((category) => category.id === approvalDraft.categoryId)
    : undefined;
  const approvalCategoryVisual = approvalCategory
    ? resolveCategoryIconVisual(approvalCategory, state.categories)
    : undefined;
  const approvalCurrency =
    approvalAccount?.currency ?? approvalDraft?.currency ?? state.preferences.baseCurrency;

  useFocusEffect(
    useCallback(() => {
      void reload().catch(() => undefined);
    }, [reload]),
  );

  const flashApprovalFields = (fields: ApprovalField[]) => {
    const uniqueFields = Array.from(new Set(fields));
    setHighlightedApprovalFields(new Set(uniqueFields));
    setApprovalGlowPulseKey((key) => key + 1);
  };

  const openApproval = (candidate: CaptureCandidate) => {
    const draft = approvalDraftFromCandidate(candidate, state.preferences.baseCurrency);
    setApprovalDraft(draft);
    setApprovalPicker(null);
    const missing = approvalMissingFields(draft, { includeSoftFields: true });
    if (missing.length) setTimeout(() => flashApprovalFields(missing), 80);
  };

  const updateApprovalDraft = (patch: Partial<ApprovalDraft>) => {
    setApprovalDraft((current) => (current ? { ...current, ...patch } : current));
  };

  const closeApproval = useCallback(() => {
    setApprovalDraft(undefined);
    setApprovalPicker(null);
    setHighlightedApprovalFields(new Set());
  }, []);

  useBackLayer(Boolean(approvalDraft), closeApproval);

  const buildApprovalInput = (
    candidate: CaptureCandidate,
    draft: ApprovalDraft,
  ): { input?: ApproveCaptureCandidateInput; missing: ApprovalField[] } => {
    const missing = approvalMissingFields(draft);
    const account = draft.accountId
      ? state.accounts.find((item) => item.id === draft.accountId)
      : undefined;
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
  };

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
      await mutate((draft) => {
        ids.forEach((id) => {
          rejectCaptureCandidateInLedger(draft, id);
        });
      });
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

  const messageHintsForApproval = (
    candidate: CaptureCandidate,
    accountId: string,
  ): AccountMessageHint[] => {
    const account = state.accounts.find((item) => item.id === accountId);
    if (!account) return [];
    return messageHintSuggestionsFromCapturePayload(account, candidate.rawPayload).filter(
      (hint) => !hint.existing,
    );
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
                  {filterLabel(filter, allPending)}
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
        renderItem={({ item }) => {
          const account = state.accounts.find(
            (candidateAccount) => candidateAccount.id === item.suggestedAccountId,
          );
          const counterAccount = state.accounts.find(
            (candidateAccount) => candidateAccount.id === item.suggestedCounterAccountId,
          );
          const category = state.categories.find(
            (candidateCategory) => candidateCategory.id === item.suggestedCategoryId,
          );
          const linkedPlan = item.suggestedRecurringTemplateId
            ? state.preferences.futureGenerationRules?.find(
                (rule) => rule.id === item.suggestedRecurringTemplateId,
              )
            : undefined;
          const receiptFileName =
            typeof item.rawPayload.fileName === 'string' ? item.rawPayload.fileName : undefined;
          const walletCsvRows = walletCsvCaptureRows(item.rawPayload);
          const needsCounter = item.suggestedType
            ? isTransferTransactionType(item.suggestedType)
            : false;

          const reject = async () => {
            await rejectCaptureCandidate(item.id);
          };

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
                  {item.source.toUpperCase()}
                </Text>
                <Text variant="labelMedium" style={{ color: theme.colors.onSurfaceVariant }}>
                  {Math.round(item.confidence)}%
                </Text>
              </View>
              <Text variant="headlineSmall" style={s.amount}>
                {item.parsedAmount
                  ? formatMoney(item.parsedAmount, state.preferences.locale)
                  : 'Amount missing'}
              </Text>
              <Text variant="bodyMedium" style={{ color: theme.colors.onSurfaceVariant }}>
                {item.parsedMerchant ?? 'Unknown merchant'}
              </Text>
              <View style={s.metaGrid}>
                <Meta
                  label="Type"
                  value={
                    item.suggestedType ? transactionTypeLabel(item.suggestedType) : 'Needs review'
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
                {item.suggestedType === 'adjustment' ? null : (
                  <Meta
                    label="Category"
                    value={category?.name ?? 'Uncategorized'}
                    labelColor={theme.colors.onSurfaceVariant}
                    valueColor={theme.colors.onSurface}
                  />
                )}
                {linkedPlan ? (
                  <Meta
                    label="Plan"
                    value={linkedPlan.name}
                    labelColor={theme.colors.onSurfaceVariant}
                    valueColor={theme.colors.primary}
                  />
                ) : null}
                <Meta
                  label="Date"
                  value={
                    item.parsedOccurredAt
                      ? new Date(item.parsedOccurredAt).toLocaleString()
                      : 'Needs review'
                  }
                  labelColor={theme.colors.onSurfaceVariant}
                  valueColor={theme.colors.onSurface}
                />
                {item.parsedLocationLabel ? (
                  <Meta
                    label="Place"
                    value={item.parsedLocationLabel}
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
                <Button
                  mode="contained"
                  icon="check"
                  style={s.actionButton}
                  onPress={() => openApproval(item)}
                >
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
        }}
      />
      <Portal>
        <KeyboardAvoidingView
          behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
          keyboardVerticalOffset={tokens.space.lg}
          pointerEvents="box-none"
          style={s.keyboardHost}
        >
          <Dialog visible={Boolean(approvalDraft)} onDismiss={closeApproval} style={s.dialog}>
            <Dialog.Title>Approve capture</Dialog.Title>
            <Dialog.ScrollArea style={s.dialogScrollArea}>
              <ScrollView
                ref={approvalScrollRef}
                contentContainerStyle={s.dialogContent}
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
            </Dialog.ScrollArea>
            <Dialog.Actions>
              <Button onPress={closeApproval}>Cancel</Button>
              <Button mode="contained" onPress={() => void submitApproval()}>
                Approve
              </Button>
            </Dialog.Actions>
          </Dialog>
        </KeyboardAvoidingView>
      </Portal>
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
        kind={approvalCategoryKind}
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

function filterLabel(filter: SourceFilter, candidates: CaptureCandidate[]): string {
  if (filter === 'all') return `${candidates.length} total`;
  const count = candidates.filter((candidate) => candidate.source === filter).length;
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
  keyboardHost: { flex: 1, justifyContent: 'center' },
  dialog: { borderRadius: tokens.radius.lg, maxHeight: '88%' },
  dialogScrollArea: { maxHeight: 520 },
  dialogContent: {
    gap: tokens.space.sm,
    paddingBottom: tokens.space.xxl,
    paddingTop: tokens.space.md,
  },
});
