import { formatMoney, fromMinor, normalizeCurrencyCode, toMinor } from '@1wallet/domain/money';
import type { Account, Transaction, TransactionType } from '@1wallet/domain/types';
import {
    enabledCurrencies,
    hasExplicitRate,
    rateBetween,
    updateTransaction,
} from '@1wallet/ledger/services';
import { indexedAccountBalance } from '@1wallet/ledger/services/indexes';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import { Alert, ScrollView, StyleSheet, Switch, Text, View } from 'react-native';
import {
    Appbar,
    Button,
    Divider,
    TextInput as PaperTextInput,
    Snackbar,
    useTheme,
} from 'react-native-paper';
import { resolveAccountIconVisual } from '../../src/accountOptions';
import { resolveCategoryIcon, resolveCategoryIconVisual } from '../../src/categoryIcons';
import { categoryBreadcrumb } from '../../src/categoryTree';
import { goBackOrHome, InfoRow, PremiumTextInput, SectionCard } from '../../src/components/AppKit';
import { OptionListOverlay, type OptionListItem } from '../../src/components/OptionListOverlay';
import { NoteAutocompleteInput } from '../../src/components/record/NoteAutocompleteInput';
import { PaymentMethodSelector } from '../../src/components/record/PaymentMethodSelector';
import { RecordCurrencyFields } from '../../src/components/record/RecordCurrencyFields';
import {
    numberFromCurrencyText,
    resolveRecordCurrencyDraft,
    trimFxRateValue,
} from '../../src/components/record/recordCurrencyMath';
import { RecordDateTimeFields } from '../../src/components/record/RecordDateTimeFields';
import {
    AccountPickerOverlay as RecordAccountPickerOverlay,
    CategoryPickerOverlay as RecordCategoryPickerOverlay,
} from '../../src/components/record/RecordPickers';
import { RecordSelectorRow } from '../../src/components/record/RecordSelectorRow';
import { freshRateBetween, refreshRatesForPairIfStale } from '../../src/exchangeRateFreshness';
import { positiveAmountColor } from '../../src/financeColors';
import { linkedLoanInterestTransaction } from '../../src/loans/loanUtils';
import {
    pickReceiptAsset,
    receiptAssetToAttachment,
    type ReceiptCaptureSource,
} from '../../src/receiptCapture';
import { resolveRecordCurrencyDraftForState } from '../../src/recordCurrencyFreshness';
import {
    dateTimeToIso,
    isValidLocalDate,
    isValidLocalTime,
    localDateTimePartsFromIso,
} from '../../src/recordDateTime';
import {
    signedTransactionAmount,
    transactionAmountDisplay,
} from '../../src/transactionDisplayAmounts';
import {
    isTransferTransactionType,
    TRANSACTION_TYPE_BUCKET_OPTIONS,
    transactionTypeBucket,
    transactionTypeForBucket,
    transactionTypeOptionFor,
    type TransactionTypeBucket,
} from '../../src/transactionTypes';

type PickerMode = 'type' | 'account' | 'counter' | 'category' | null;
const TRANSACTION_TYPE_OPTIONS: OptionListItem<TransactionTypeBucket>[] =
  TRANSACTION_TYPE_BUCKET_OPTIONS;

export default function TransactionDetail() {
  const theme = useTheme();
  const { id } = useLocalSearchParams<{ id: string }>();
  const {
    state,
    indexes,
    ready,
    mutate,
    editTransaction,
    removeTransaction,
    refreshExchangeRates,
  } = useLedger();
  const tx = state.transactions.find((item) => item.id === id);

  const [formId, setFormId] = useState<string | undefined>();
  const [type, setType] = useState<TransactionType>('expense');
  const [amount, setAmount] = useState('');
  const [originalCurrency, setOriginalCurrency] = useState('');
  const [originalAmount, setOriginalAmount] = useState('');
  const [originalFxRate, setOriginalFxRate] = useState('');
  const [accountId, setAccountId] = useState<string | undefined>();
  const [counterAccountId, setCounterAccountId] = useState<string | undefined>();
  const [categoryId, setCategoryId] = useState<string | undefined>();
  const [date, setDate] = useState('');
  const [time, setTime] = useState('');
  const [locationLabel, setLocationLabel] = useState('');
  const [paymentMethod, setPaymentMethod] = useState('');
  const [notes, setNotes] = useState('');
  const [tagsText, setTagsText] = useState('');
  const [isReimbursable, setIsReimbursable] = useState(false);
  const [isTaxDeductible, setIsTaxDeductible] = useState(false);
  const [isExcludedFromReports, setIsExcludedFromReports] = useState(false);
  const [pickerMode, setPickerMode] = useState<PickerMode>(null);
  const [receiptBusy, setReceiptBusy] = useState(false);
  const [snackbar, setSnackbar] = useState<string | null>(null);

  useEffect(() => {
    if (!tx || tx.id === formId) return;
    setFormId(tx.id);
    setType(tx.type);
    setAmount(String(fromMinor(tx.amount.amountMinor, tx.amount.currency)));
    setOriginalCurrency(tx.originalAmount?.currency ?? tx.amount.currency);
    setOriginalAmount(
      tx.originalAmount
        ? String(fromMinor(tx.originalAmount.amountMinor, tx.originalAmount.currency))
        : '',
    );
    setOriginalFxRate(tx.originalFxRate ? String(tx.originalFxRate) : '');
    setAccountId(tx.accountId);
    setCounterAccountId(tx.counterAccountId);
    setCategoryId(tx.categoryId);
    const nextDateTime = localDateTimePartsFromIso(tx.occurredAt);
    setDate(nextDateTime.date);
    setTime(nextDateTime.time);
    setLocationLabel(tx.locationLabel ?? '');
    setPaymentMethod(tx.paymentMethod ?? '');
    setNotes(tx.notes ?? '');
    setTagsText((tx.tags ?? []).join(', '));
    setIsReimbursable(tx.isReimbursable);
    setIsTaxDeductible(tx.isTaxDeductible);
    setIsExcludedFromReports(tx.isExcludedFromReports);
  }, [formId, tx]);

  const accounts = useMemo(
    () =>
      state.accounts.filter(
        (account) =>
          !account.isArchived || account.id === accountId || account.id === counterAccountId,
      ),
    [accountId, counterAccountId, state.accounts],
  );
  const selectedAccount = accounts.find((account) => account.id === accountId);
  const counterAccount = accounts.find((account) => account.id === counterAccountId);
  const selectedAccountVisual = selectedAccount
    ? resolveAccountIconVisual(selectedAccount)
    : undefined;
  const counterAccountVisual = counterAccount
    ? resolveAccountIconVisual(counterAccount)
    : undefined;
  const selectedType = transactionTypeOptionFor(type);
  const isTransfer = isTransferTransactionType(type);
  const selectedCategory = state.categories.find((category) => category.id === categoryId);
  const selectedCategoryPath = categoryBreadcrumb(state.categories, categoryId);
  const selectedCategoryVisual = selectedCategory
    ? resolveCategoryIconVisual(selectedCategory, state.categories)
    : undefined;
  const postedCurrency = normalizeCurrencyCode(
    selectedAccount?.currency ?? tx?.amount.currency ?? state.preferences.baseCurrency,
  );
  const purchaseCurrency = normalizeCurrencyCode(
    originalCurrency ||
      selectedAccount?.currency ||
      tx?.amount.currency ||
      state.preferences.baseCurrency,
  );
  const suggestedPurchaseRate =
    purchaseCurrency !== postedCurrency && hasExplicitRate(state, purchaseCurrency, postedCurrency)
      ? rateBetween(state, purchaseCurrency, postedCurrency)
      : undefined;
  const foreignCurrencyDraft = resolveRecordCurrencyDraft({
    originalAmountText: originalAmount,
    purchaseCurrency,
    postedCurrency,
    fxRateText: originalFxRate,
    suggestedRate: suggestedPurchaseRate,
  });

  if (!ready) {
    return (
      <View style={[s.empty, { backgroundColor: theme.colors.background }]}>
        <Text style={[s.emptyText, { color: theme.colors.onSurfaceVariant }]}>Loading…</Text>
      </View>
    );
  }

  if (!tx) {
    return (
      <View style={[s.empty, { backgroundColor: theme.colors.background }]}>
        <Text style={[s.emptyText, { color: theme.colors.onSurfaceVariant }]}>
          Transaction not found.
        </Text>
      </View>
    );
  }

  const heroAmountDisplay = transactionAmountDisplay(tx, 'single', state, state.preferences.locale);
  const heroAmountColor = transactionDetailAmountColor(
    tx,
    theme.dark,
    theme.colors.primary,
    theme.colors.error,
  );

  const changeTypeBucket = (nextBucket: TransactionTypeBucket) => {
    const nextType = transactionTypeForBucket(nextBucket);
    setType(nextType);
    const nextIsTransfer = isTransferTransactionType(nextType);
    if (nextIsTransfer || nextType === 'adjustment') {
      setCategoryId(undefined);
    }
    if (!nextIsTransfer) setCounterAccountId(undefined);
  };

  const changePurchaseCurrency = async (value: string) => {
    const nextCurrency = normalizeCurrencyCode(value);
    setOriginalCurrency(nextCurrency);
    if (nextCurrency === postedCurrency) {
      setOriginalAmount('');
      setOriginalFxRate('');
      return;
    }
    const nextOriginalAmount =
      !originalAmount.trim() && amount.trim() ? normalizeDisplayAmount(amount) : originalAmount;
    if (nextOriginalAmount !== originalAmount) setOriginalAmount(nextOriginalAmount);
    let rateState = state;
    try {
      rateState = await refreshRatesForPairIfStale(
        state,
        refreshExchangeRates,
        nextCurrency,
        postedCurrency,
      );
    } catch (error) {
      console.warn('Could not refresh exchange rates for selected currency', error);
    }
    const nextSuggestedRate = hasExplicitRate(rateState, nextCurrency, postedCurrency)
      ? freshRateBetween(rateState, nextCurrency, postedCurrency)
      : undefined;
    const nextFxRateText =
      !originalFxRate.trim() && nextSuggestedRate
        ? trimFxRateValue(nextSuggestedRate)
        : originalFxRate;
    if (nextFxRateText !== originalFxRate) setOriginalFxRate(nextFxRateText);
    const nextDraft = resolveRecordCurrencyDraft({
      originalAmountText: nextOriginalAmount,
      purchaseCurrency: nextCurrency,
      postedCurrency,
      fxRateText: nextFxRateText,
      suggestedRate: nextSuggestedRate,
    });
    if (nextDraft.postedAmountText) setAmount(nextDraft.postedAmountText);
  };

  const save = async () => {
    const numericAmount = numberFromCurrencyText(amount);
    const saveAmount = type === 'adjustment' ? numericAmount : Math.abs(numericAmount);
    const tags = parseTags(tagsText);
    if (!selectedAccount || !accountId) return Alert.alert('Pick an account');
    const canRefreshMissingRate =
      foreignCurrencyDraft.needsRate &&
      purchaseCurrency !== postedCurrency &&
      numberFromCurrencyText(originalAmount) > 0;
    if (foreignCurrencyDraft.needsRate && !canRefreshMissingRate) {
      return Alert.alert(
        'Enter an exchange rate',
        `Add a ${purchaseCurrency} to ${postedCurrency} rate before saving.`,
      );
    }
    if (type === 'adjustment') {
      if ((!Number.isFinite(saveAmount) || saveAmount === 0) && !canRefreshMissingRate) {
        return Alert.alert('Enter a positive or negative adjustment');
      }
    } else if ((!Number.isFinite(saveAmount) || saveAmount <= 0) && !canRefreshMissingRate)
      return Alert.alert('Enter an amount');
    if (!isValidLocalDate(date)) return Alert.alert('Enter a valid date');
    if (!isValidLocalTime(time)) return Alert.alert('Enter a valid time');
    if (isTransfer && !counterAccountId) return Alert.alert('Pick a destination account');

    try {
      await refreshRatesForPairIfStale(
        state,
        refreshExchangeRates,
        purchaseCurrency,
        postedCurrency,
      );
      await mutate(
        (draft) => {
          const draftAccount = draft.accounts.find((account) => account.id === accountId);
          if (!draftAccount) throw new Error('Pick an account');
          const draftPostedCurrency = normalizeCurrencyCode(draftAccount.currency);
          const draftPurchaseCurrency = normalizeCurrencyCode(
            originalCurrency || draftPostedCurrency,
          );
          const draftForeignCurrency = resolveRecordCurrencyDraftForState({
            state: draft,
            originalAmountText: originalAmount,
            purchaseCurrency: draftPurchaseCurrency,
            postedCurrency: draftPostedCurrency,
            fxRateText: originalFxRate,
          });
          if (draftForeignCurrency.needsRate) {
            throw new Error(
              `Add a ${draftPurchaseCurrency} to ${draftPostedCurrency} rate before saving.`,
            );
          }
          const originalMinor = draftForeignCurrency.originalAmountMinor;
          updateTransaction(draft, tx.id, {
            type,
            accountId,
            counterAccountId: isTransfer ? counterAccountId : null,
            amountMinor:
              draftForeignCurrency.postedAmountMinor ?? toMinor(saveAmount, draftAccount.currency),
            currency: draftAccount.currency,
            originalAmountMinor: originalMinor ?? null,
            originalCurrency: originalMinor !== undefined ? draftPurchaseCurrency : null,
            originalFxRate:
              originalMinor !== undefined ? (draftForeignCurrency.fxRate ?? null) : null,
            categoryId: isTransfer || type === 'adjustment' ? null : (categoryId ?? null),
            occurredAt: dateTimeToIso(date, time, new Date(tx.occurredAt)),
            locationLabel: locationLabel.trim() || null,
            paymentMethod: paymentMethod.trim() || null,
            notes: notes.trim() || null,
            tags: tags.length > 0 ? tags : null,
            isReimbursable,
            isTaxDeductible,
            isExcludedFromReports,
          });
        },
        { slices: ['transactions'] },
      );
      goBackOrHome();
    } catch (error) {
      Alert.alert('Could not save transaction', (error as Error).message);
    }
  };

  const attachReceipt = async (source: ReceiptCaptureSource) => {
    setReceiptBusy(true);
    try {
      const receipt = await pickReceiptAsset(source);
      if (!receipt) return;
      const attachment = receiptAssetToAttachment(receipt);
      await editTransaction(tx.id, {
        attachments: [...(tx.attachments ?? []), attachment],
      });
      setSnackbar('Receipt attached');
    } catch (error) {
      Alert.alert('Could not attach receipt', (error as Error).message);
    } finally {
      setReceiptBusy(false);
    }
  };

  const confirmDelete = () => {
    Alert.alert('Delete transaction?', 'This removes the record from your ledger.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: async () => {
          await removeTransaction(tx.id);
          goBackOrHome();
        },
      },
    ]);
  };

  return (
    <View style={[s.screen, { backgroundColor: theme.colors.background }]}>
      <Appbar.Header elevated={false} style={{ backgroundColor: theme.colors.background }}>
        <Appbar.BackAction onPress={goBackOrHome} />
        <Appbar.Content title="Edit transaction" titleStyle={s.appbarTitle} />
        <Appbar.Action icon="delete-outline" onPress={confirmDelete} />
        <Appbar.Action icon="check" onPress={() => void save()} />
      </Appbar.Header>

      <ScrollView contentContainerStyle={s.container} keyboardShouldPersistTaps="handled">
        <View
          style={[
            s.heroCard,
            {
              backgroundColor: theme.colors.elevation.level1,
              borderColor: theme.colors.outlineVariant,
            },
          ]}
        >
          <Text style={[s.muted, { color: theme.colors.onSurfaceVariant }]}>
            {selectedType.label}
          </Text>
          <Text style={[s.hero, { color: heroAmountColor }]}>{heroAmountDisplay.primary}</Text>
          {heroAmountDisplay.secondary.map((secondaryAmount) => (
            <Text
              key={secondaryAmount}
              style={[s.heroSecondary, { color: theme.colors.onSurfaceVariant }]}
            >
              {secondaryAmount}
            </Text>
          ))}
          <Text style={[s.muted, { color: theme.colors.onSurfaceVariant }]}>
            {new Date(tx.occurredAt).toLocaleString()}
          </Text>
        </View>

        <View style={s.selectorGrid}>
          <RecordSelectorRow
            icon={selectedType.icon}
            label="Type"
            value={selectedType.label}
            supporting={selectedType.description}
            onPress={() => setPickerMode('type')}
          />
          <RecordSelectorRow
            icon={selectedAccountVisual?.icon ?? 'wallet-outline'}
            iconBackgroundColor={selectedAccountVisual?.backgroundColor}
            iconColor={selectedAccountVisual?.iconColor}
            label={isTransfer ? 'From account' : 'Account'}
            value={selectedAccount?.name ?? 'Choose account'}
            valueNumberOfLines={2}
            supporting={accountSupporting(selectedAccount, state.preferences.locale, indexes)}
            onPress={() => setPickerMode('account')}
          />
        </View>

        {isTransfer || type !== 'adjustment' ? (
          <View style={s.selectorGrid}>
            {isTransfer ? (
              <RecordSelectorRow
                icon={counterAccountVisual?.icon ?? 'swap-horizontal'}
                iconBackgroundColor={counterAccountVisual?.backgroundColor}
                iconColor={counterAccountVisual?.iconColor}
                label="To account"
                value={counterAccount?.name ?? 'Choose destination'}
                valueNumberOfLines={2}
                supporting="Required for transfer types"
                onPress={() => setPickerMode('counter')}
              />
            ) : (
              <RecordSelectorRow
                icon={resolveCategoryIcon(selectedCategory, state.categories)}
                iconBackgroundColor={selectedCategoryVisual?.backgroundColor}
                iconColor={selectedCategoryVisual?.iconColor}
                label="Category"
                value={selectedCategoryPath ?? selectedCategory?.name ?? 'Uncategorized'}
                valueNumberOfLines={2}
                supporting={selectedCategoryPath ?? 'Optional'}
                onPress={() => setPickerMode('category')}
              />
            )}
          </View>
        ) : null}

        <SectionCard title="Amount" subtitle={selectedAccount?.currency ?? tx.amount.currency}>
          <PremiumTextInput
            label="Amount"
            value={amount}
            onChangeText={setAmount}
            keyboardType={type === 'adjustment' ? 'numbers-and-punctuation' : 'numeric'}
            style={s.amountInput}
            placeholder="0"
          />
          <RecordCurrencyFields
            accountCurrency={selectedAccount?.currency}
            baseCurrency={state.preferences.baseCurrency}
            enabledCurrencies={enabledCurrencies(state)}
            locale={state.preferences.locale}
            postedAmount={amount}
            onPostedAmountChange={setAmount}
            originalCurrency={purchaseCurrency}
            onOriginalCurrencyChange={changePurchaseCurrency}
            originalAmount={originalAmount}
            onOriginalAmountChange={setOriginalAmount}
            fxRate={originalFxRate}
            onFxRateChange={setOriginalFxRate}
            suggestedRate={suggestedPurchaseRate}
          />
        </SectionCard>

        <SectionCard title="Details">
          <RecordDateTimeFields
            date={date}
            time={time}
            onChangeDate={setDate}
            onChangeTime={setTime}
          />
          <PremiumTextInput
            label="Place"
            value={locationLabel}
            onChangeText={setLocationLabel}
            left={<PaperTextInput.Icon icon="map-marker-outline" />}
          />
          <PaymentMethodSelector
            account={selectedAccount}
            transactionType={type}
            value={paymentMethod}
            onChange={setPaymentMethod}
            autoFill="empty"
          />
          <NoteAutocompleteInput
            value={notes}
            onChangeText={setNotes}
            sources={state.transactions}
            excludeTransactionId={tx.id}
            numberOfLines={3}
          />
        </SectionCard>

        <SectionCard title="Tags" subtitle="Optional labels for search and filtering">
          <PremiumTextInput
            label="Tags"
            value={tagsText}
            onChangeText={setTagsText}
            placeholder="food, reimbursed, work"
            autoCapitalize="none"
            left={<PaperTextInput.Icon icon="tag-outline" />}
          />
        </SectionCard>

        <SectionCard title="Receipts">
          <View style={s.receiptActions}>
            <Button
              mode="contained-tonal"
              icon="camera-outline"
              loading={receiptBusy}
              disabled={receiptBusy}
              onPress={() => void attachReceipt('camera')}
            >
              Scan
            </Button>
            <Button
              mode="outlined"
              icon="image-outline"
              disabled={receiptBusy}
              onPress={() => void attachReceipt('library')}
            >
              Photo
            </Button>
            <Button
              mode="outlined"
              icon="paperclip"
              disabled={receiptBusy}
              onPress={() => void attachReceipt('file')}
            >
              File
            </Button>
          </View>
          {tx.attachments?.length ? (
            <View style={s.attachmentList}>
              {tx.attachments.map((attachment) => (
                <InfoRow
                  key={attachment.id}
                  icon="paperclip"
                  label={attachment.source}
                  value={attachment.name}
                />
              ))}
            </View>
          ) : null}
        </SectionCard>

        <SectionCard title="Flags">
          <ToggleRow label="Reimbursable" value={isReimbursable} onChange={setIsReimbursable} />
          <Divider />
          <ToggleRow label="Tax deductible" value={isTaxDeductible} onChange={setIsTaxDeductible} />
          <Divider />
          <ToggleRow
            label="Exclude from reports"
            value={isExcludedFromReports}
            onChange={setIsExcludedFromReports}
          />
        </SectionCard>

        <SectionCard title="Record metadata">
          <InfoRow label="Source" value={tx.source} />
          {tx.sourceConfidence !== undefined ? (
            <InfoRow label="Confidence" value={`${Math.round(tx.sourceConfidence)}%`} />
          ) : null}
          {tx.externalRef ? <InfoRow label="Reference" value={tx.externalRef} /> : null}
        </SectionCard>

        <LinkedLoanRecordSection state={state} transaction={tx} />

        <Button mode="contained" icon="content-save-outline" onPress={() => void save()}>
          Save changes
        </Button>
        <Button
          mode="outlined"
          icon="delete-outline"
          textColor={theme.colors.error}
          onPress={confirmDelete}
        >
          Delete transaction
        </Button>
      </ScrollView>

      <OptionListOverlay
        visible={pickerMode === 'type'}
        title="Choose type"
        options={TRANSACTION_TYPE_OPTIONS}
        selectedValue={transactionTypeBucket(type)}
        onDismiss={() => setPickerMode(null)}
        onSelect={(option) => {
          changeTypeBucket(option.value);
          setPickerMode(null);
        }}
      />
      <RecordAccountPickerOverlay
        visible={pickerMode === 'account' || pickerMode === 'counter'}
        title={pickerMode === 'counter' ? 'Choose destination' : 'Choose account'}
        accounts={
          pickerMode === 'counter'
            ? accounts.filter((account) => account.id !== accountId)
            : accounts
        }
        selectedId={pickerMode === 'counter' ? counterAccountId : accountId}
        balances={(account) =>
          formatMoney(indexedAccountBalance(indexes, account), state.preferences.locale)
        }
        onDismiss={() => setPickerMode(null)}
        onCreate={() => {
          setPickerMode(null);
          router.push('/account/new');
        }}
        onSelect={(account) => {
          if (pickerMode === 'counter') setCounterAccountId(account.id);
          else {
            setAccountId(account.id);
            setOriginalCurrency(account.currency);
            if (counterAccountId === account.id) setCounterAccountId(undefined);
          }
          setPickerMode(null);
        }}
      />
      <RecordCategoryPickerOverlay
        visible={pickerMode === 'category' && type !== 'adjustment'}
        categories={state.categories}
        selectedId={categoryId}
        onDismiss={() => setPickerMode(null)}
        onClear={() => {
          setCategoryId(undefined);
          setPickerMode(null);
        }}
        onSelect={(category) => {
          setCategoryId(category.id);
          setPickerMode(null);
        }}
      />
      <Snackbar visible={Boolean(snackbar)} onDismiss={() => setSnackbar(null)} duration={2200}>
        {snackbar}
      </Snackbar>
    </View>
  );
}

function LinkedLoanRecordSection({
  state,
  transaction,
}: {
  state: ReturnType<typeof useLedger>['state'];
  transaction: Transaction;
}) {
  const linkedInterest =
    transaction.type === 'loan_repayment'
      ? linkedLoanInterestTransaction(state, transaction)
      : undefined;
  const linkedRepayment =
    transaction.type === 'interest_in' || transaction.type === 'interest_out'
      ? state.transactions.find((item) => item.id === transaction.originalTransactionId)
      : undefined;
  const linked = linkedInterest ?? linkedRepayment;
  if (!linked) return null;

  const title = linkedInterest ? 'Linked interest' : 'Linked repayment';
  const account = state.accounts.find((item) => item.id === linked.accountId);

  return (
    <SectionCard title="Linked loan record">
      <InfoRow label={title} value={formatMoney(linked.amount, state.preferences.locale)} />
      <InfoRow label="Account" value={account?.name ?? 'Unknown account'} />
      <Button
        mode="contained-tonal"
        icon="open-in-new"
        onPress={() => router.push(`/transaction/${linked.id}` as never)}
      >
        Open linked record
      </Button>
    </SectionCard>
  );
}

function ToggleRow({
  label,
  value,
  onChange,
}: {
  label: string;
  value: boolean;
  onChange: (value: boolean) => void;
}) {
  const theme = useTheme();
  return (
    <View style={s.toggleRow}>
      <Text style={[s.toggleLabel, { color: theme.colors.onSurface }]}>{label}</Text>
      <Switch value={value} onValueChange={onChange} />
    </View>
  );
}

function accountSupporting(
  account: Account | undefined,
  locale: string,
  indexes: ReturnType<typeof useLedger>['indexes'],
): string {
  if (!account) return 'Required';
  return formatMoney(indexedAccountBalance(indexes, account), locale);
}

function parseTags(value: string): string[] {
  const tags = value
    .split(',')
    .map((tag) => tag.trim())
    .filter(Boolean);
  return Array.from(new Set(tags));
}

function transactionDetailAmountColor(
  transaction: Transaction,
  dark: boolean | undefined,
  transferColor: string,
  expenseColor: string,
): string {
  const bucket = transactionTypeBucket(transaction.type);
  if (bucket === 'income') return positiveAmountColor(dark);
  if (bucket === 'transfer') return transferColor;
  if (bucket === 'expense') return expenseColor;
  return signedTransactionAmount(transaction) < 0 ? expenseColor : positiveAmountColor(dark);
}

function normalizeDisplayAmount(value: string): string {
  return value.startsWith('-') ? value.slice(1) || '0' : value;
}

const s = StyleSheet.create({
  screen: { flex: 1 },
  appbarTitle: { fontWeight: '700' },
  container: { padding: tokens.space.lg, gap: tokens.space.md, paddingBottom: 36 },
  empty: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: tokens.space.xl },
  emptyText: { fontFamily: tokens.font.nativeFamily.regular, fontSize: tokens.font.size.md },
  heroCard: {
    borderRadius: tokens.radius.lg,
    padding: tokens.space.lg,
    borderWidth: 1,
    gap: tokens.space.xs,
  },
  hero: {
    fontFamily: tokens.font.nativeFamily.numericMedium,
    fontSize: tokens.font.size.hero,
    fontWeight: '800',
  },
  heroSecondary: {
    fontFamily: tokens.font.nativeFamily.numericMedium,
    fontSize: tokens.font.size.sm,
    fontWeight: '700',
  },
  muted: { fontFamily: tokens.font.nativeFamily.regular, fontSize: tokens.font.size.sm },
  selectorGrid: { flexDirection: 'row', gap: tokens.space.sm },
  amountInput: {
    fontFamily: tokens.font.nativeFamily.numericMedium,
    borderWidth: 1,
    borderRadius: tokens.radius.md,
    padding: tokens.space.lg,
    fontSize: tokens.font.size.hero,
    textAlign: 'right',
    fontWeight: '800',
  },
  receiptActions: { flexDirection: 'row', flexWrap: 'wrap', gap: tokens.space.sm },
  attachmentList: { gap: tokens.space.xs },
  toggleRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: tokens.space.sm,
    gap: tokens.space.md,
  },
  toggleLabel: { fontFamily: tokens.font.nativeFamily.regular, fontSize: tokens.font.size.md },
});
