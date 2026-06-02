import { formatMoney, fromMinor, normalizeCurrencyCode, toMinor } from '@1wallet/domain/money';
import type { Account, TransactionType } from '@1wallet/domain/types';
import { enabledCurrencies, hasExplicitRate, rateBetween } from '@1wallet/ledger/services';
import { indexedAccountBalance } from '@1wallet/ledger/services/indexes';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import { Alert, ScrollView, StyleSheet, View } from 'react-native';
import { Appbar, Button, HelperText, Text, TextInput, useTheme } from 'react-native-paper';
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
import {
    dateTimeToIso,
    isValidLocalDate,
    isValidLocalTime,
    localDateTimePartsFromIso,
} from '../../src/recordDateTime';
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
const FIXABLE_WARNINGS = new Set([
  'invalid amount',
  'amount missing',
  'invalid date',
  'date needs review',
  'unknown type',
  'transaction direction needs review',
  'ambiguous transfer match',
  'ambiguous account match',
  'account needs matching detail',
  'merchant needs review',
  'receipt amount needs review',
  'receipt merchant needs review',
  'receipt date needs review',
  'receipt OCR returned no text',
  'receipt OCR supports image photos only',
  'receipt OCR unavailable; review fields manually',
]);

export default function CaptureCandidateDetail() {
  const theme = useTheme();
  const { id } = useLocalSearchParams<{ id: string }>();
  const { state, indexes, ready, editCaptureCandidate, refreshExchangeRates } = useLedger();
  const candidate = state.captureCandidates.find((item) => item.id === id);

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
  const [merchant, setMerchant] = useState('');
  const [locationLabel, setLocationLabel] = useState('');
  const [paymentMethod, setPaymentMethod] = useState('');
  const [notes, setNotes] = useState('');
  const [reference, setReference] = useState('');
  const [pickerMode, setPickerMode] = useState<PickerMode>(null);
  const [submitAttempted, setSubmitAttempted] = useState(false);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!candidate || candidate.id === formId) return;
    setFormId(candidate.id);
    setType(candidate.suggestedType ?? 'expense');
    const parsedCurrency = candidate.parsedAmount?.currency ?? state.preferences.baseCurrency;
    const suggestedAccount = state.accounts.find(
      (account) => account.id === candidate.suggestedAccountId,
    );
    const postedCurrency = suggestedAccount?.currency ?? parsedCurrency;
    const parsedValue = candidate.parsedAmount
      ? fromMinor(candidate.parsedAmount.amountMinor, parsedCurrency)
      : 0;
    const shouldTreatParsedAsOriginal =
      candidate.parsedAmount &&
      parsedCurrency !== postedCurrency &&
      !candidate.parsedOriginalAmount;
    const suggestedParsedRate =
      shouldTreatParsedAsOriginal && hasExplicitRate(state, parsedCurrency, postedCurrency)
        ? rateBetween(state, parsedCurrency, postedCurrency)
        : undefined;
    setAmount(
      candidate.parsedAmount
        ? shouldTreatParsedAsOriginal
          ? suggestedParsedRate
            ? String(parsedValue * suggestedParsedRate)
            : ''
          : String(fromMinor(candidate.parsedAmount.amountMinor, postedCurrency))
        : '',
    );
    setOriginalCurrency(
      candidate.parsedOriginalAmount?.currency ??
        (shouldTreatParsedAsOriginal ? parsedCurrency : postedCurrency),
    );
    setOriginalAmount(
      candidate.parsedOriginalAmount
        ? String(
            fromMinor(
              candidate.parsedOriginalAmount.amountMinor,
              candidate.parsedOriginalAmount.currency,
            ),
          )
        : shouldTreatParsedAsOriginal
          ? String(parsedValue)
          : '',
    );
    setOriginalFxRate(
      candidate.parsedOriginalFxRate
        ? String(candidate.parsedOriginalFxRate)
        : shouldTreatParsedAsOriginal && suggestedParsedRate
          ? String(suggestedParsedRate)
          : '',
    );
    setAccountId(candidate.suggestedAccountId);
    setCounterAccountId(candidate.suggestedCounterAccountId);
    setCategoryId(candidate.suggestedCategoryId);
    const dateTime = localDateTimePartsFromIso(candidate.parsedOccurredAt ?? candidate.createdAt);
    setDate(dateTime.date);
    setTime(dateTime.time);
    setMerchant(candidate.parsedMerchant ?? '');
    setLocationLabel(candidate.parsedLocationLabel ?? '');
    setPaymentMethod(candidate.parsedPaymentMethod ?? '');
    setNotes(candidate.parsedNotes ?? '');
    setReference(candidate.externalRef ?? '');
  }, [candidate, formId, state]);

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
  const amountValue = numberFromCurrencyText(amount);
  const currency = normalizeCurrencyCode(
    selectedAccount?.currency ??
      candidate?.parsedAmount?.currency ??
      state.preferences.baseCurrency,
  );
  const purchaseCurrency = normalizeCurrencyCode(originalCurrency || currency);
  const suggestedPurchaseRate =
    purchaseCurrency !== currency && hasExplicitRate(state, purchaseCurrency, currency)
      ? rateBetween(state, purchaseCurrency, currency)
      : undefined;
  const foreignCurrencyDraft = resolveRecordCurrencyDraft({
    originalAmountText: originalAmount,
    purchaseCurrency,
    postedCurrency: currency,
    fxRateText: originalFxRate,
    suggestedRate: suggestedPurchaseRate,
  });
  const saveAmount = type === 'adjustment' ? amountValue : Math.abs(amountValue);
  const amountMinor = Number.isFinite(saveAmount)
    ? (foreignCurrencyDraft.postedAmountMinor ?? toMinor(saveAmount, currency))
    : 0;
  const errors = validateCaptureDraft({
    amountMinor,
    account: selectedAccount,
    counterAccount,
    isTransfer,
    isAdjustment: type === 'adjustment',
    date,
    time,
    fxNeedsRate: foreignCurrencyDraft.needsRate,
    purchaseCurrency,
    accountCurrency: currency,
  });
  const showErrors = submitAttempted;

  if (!ready) {
    return (
      <View style={[s.empty, { backgroundColor: theme.colors.background }]}>
        <Text style={[s.emptyText, { color: theme.colors.onSurfaceVariant }]}>Loading...</Text>
      </View>
    );
  }

  if (!candidate) {
    return (
      <View style={[s.empty, { backgroundColor: theme.colors.background }]}>
        <Text style={[s.emptyText, { color: theme.colors.onSurfaceVariant }]}>
          Capture not found.
        </Text>
      </View>
    );
  }

  const save = async () => {
    setSubmitAttempted(true);
    const canRefreshMissingRate =
      foreignCurrencyDraft.needsRate &&
      purchaseCurrency !== currency &&
      numberFromCurrencyText(originalAmount) > 0;
    const blockingErrors = { ...errors };
    if (canRefreshMissingRate) delete blockingErrors.amount;
    if (Object.keys(blockingErrors).length > 0 || !selectedAccount) return;
    setSaving(true);
    try {
      const rateState = await refreshRatesForPairIfStale(
        state,
        refreshExchangeRates,
        purchaseCurrency,
        currency,
      );
      const refreshedForeignCurrency = resolveRecordCurrencyDraft({
        originalAmountText: originalAmount,
        purchaseCurrency,
        postedCurrency: currency,
        fxRateText: originalFxRate,
        suggestedRate: freshRateBetween(rateState, purchaseCurrency, currency),
      });
      if (refreshedForeignCurrency.needsRate) {
        throw new Error(`Add a ${purchaseCurrency} to ${currency} rate before saving.`);
      }
      const trimmedMerchant = merchant.trim();
      const trimmedLocation = locationLabel.trim();
      const originalMinor = refreshedForeignCurrency.originalAmountMinor;
      await editCaptureCandidate(candidate.id, {
        parsedAmountMinor: refreshedForeignCurrency.postedAmountMinor ?? amountMinor,
        parsedCurrency: selectedAccount.currency,
        parsedOriginalAmountMinor: originalMinor ?? null,
        parsedOriginalCurrency: originalMinor !== undefined ? purchaseCurrency : null,
        parsedOriginalFxRate:
          originalMinor !== undefined ? (refreshedForeignCurrency.fxRate ?? null) : null,
        parsedMerchant: trimmedMerchant || null,
        parsedLocationLabel: trimmedLocation || trimmedMerchant || null,
        parsedNotes: notes.trim() || null,
        parsedPaymentMethod: paymentMethod.trim() || null,
        parsedOccurredAt: dateTimeToIso(date, time, new Date(candidate.createdAt)),
        suggestedAccountId: selectedAccount.id,
        suggestedCounterAccountId: isTransfer ? counterAccount?.id : null,
        suggestedCategoryId: isTransfer || type === 'adjustment' ? null : (categoryId ?? null),
        suggestedType: type,
        confidence: Math.max(candidate.confidence, 90),
        externalRef: reference.trim() || null,
        warnings: cleanWarnings(candidate.warnings),
      });
      goBackOrHome();
    } catch (error) {
      Alert.alert('Could not save capture', (error as Error).message);
    } finally {
      setSaving(false);
    }
  };

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
    if (nextCurrency === currency) {
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
        currency,
      );
    } catch (error) {
      console.warn('Could not refresh exchange rates for selected currency', error);
    }
    const nextSuggestedRate = hasExplicitRate(rateState, nextCurrency, currency)
      ? freshRateBetween(rateState, nextCurrency, currency)
      : undefined;
    const nextFxRateText =
      !originalFxRate.trim() && nextSuggestedRate
        ? trimFxRateValue(nextSuggestedRate)
        : originalFxRate;
    if (nextFxRateText !== originalFxRate) setOriginalFxRate(nextFxRateText);
    const nextDraft = resolveRecordCurrencyDraft({
      originalAmountText: nextOriginalAmount,
      purchaseCurrency: nextCurrency,
      postedCurrency: currency,
      fxRateText: nextFxRateText,
      suggestedRate: nextSuggestedRate,
    });
    if (nextDraft.postedAmountText) setAmount(nextDraft.postedAmountText);
  };

  const rawBody = rawPayloadText(candidate.rawPayload);

  return (
    <View style={[s.screen, { backgroundColor: theme.colors.background }]}>
      <Appbar.Header elevated={false} style={{ backgroundColor: theme.colors.background }}>
        <Appbar.BackAction onPress={goBackOrHome} />
        <Appbar.Content title="Edit capture" titleStyle={s.appbarTitle} />
        <Appbar.Action icon="check" disabled={saving} onPress={() => void save()} />
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
          <Text variant="labelMedium" style={{ color: theme.colors.primary }}>
            {candidate.source.toUpperCase()} CAPTURE
          </Text>
          <Text variant="displaySmall" numberOfLines={1} adjustsFontSizeToFit style={s.heroAmount}>
            {amountMinor !== 0
              ? formatMoney({ amountMinor, currency }, state.preferences.locale)
              : 'Amount missing'}
          </Text>
          <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
            Save corrections here, then approve from the Review queue.
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

        <SectionCard title="Amount" subtitle={selectedAccount?.currency ?? currency}>
          <PremiumTextInput
            label="Amount"
            value={amount}
            onChangeText={setAmount}
            keyboardType={type === 'adjustment' ? 'numbers-and-punctuation' : 'decimal-pad'}
            left={<TextInput.Icon icon="cash" />}
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
          <HelperText type="error" visible={showErrors && Boolean(errors.amount)}>
            {errors.amount}
          </HelperText>
        </SectionCard>

        <SectionCard title="Details">
          <RecordDateTimeFields
            date={date}
            time={time}
            onChangeDate={setDate}
            onChangeTime={setTime}
          />
          <HelperText type="error" visible={showErrors && Boolean(errors.date)}>
            {errors.date}
          </HelperText>
          <HelperText type="error" visible={showErrors && Boolean(errors.time)}>
            {errors.time}
          </HelperText>
          <PremiumTextInput
            label="Merchant"
            value={merchant}
            onChangeText={setMerchant}
            left={<TextInput.Icon icon="store-outline" />}
          />
          <PremiumTextInput
            label="Place"
            value={locationLabel}
            onChangeText={setLocationLabel}
            left={<TextInput.Icon icon="map-marker-outline" />}
          />
          <PaymentMethodSelector
            account={selectedAccount}
            transactionType={type}
            value={paymentMethod}
            onChange={setPaymentMethod}
            autoFill="empty"
          />
          <PremiumTextInput
            label="Reference"
            value={reference}
            onChangeText={setReference}
            autoCapitalize="characters"
            left={<TextInput.Icon icon="identifier" />}
          />
          <NoteAutocompleteInput
            value={notes}
            onChangeText={setNotes}
            sources={state.transactions}
            numberOfLines={4}
          />
        </SectionCard>

        {showErrors && (errors.account || errors.counter) ? (
          <SectionCard title="Required fixes">
            <HelperText type="error" visible={Boolean(errors.account)}>
              {errors.account}
            </HelperText>
            <HelperText type="error" visible={Boolean(errors.counter)}>
              {errors.counter}
            </HelperText>
          </SectionCard>
        ) : null}

        <SectionCard title="Original capture">
          <InfoRow label="Source" value={candidate.source} />
          <InfoRow label="Confidence" value={`${Math.round(candidate.confidence)}%`} />
          {candidate.warnings?.length ? (
            <InfoRow label="Warnings" value={candidate.warnings.join(', ')} />
          ) : null}
          {rawBody ? (
            <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
              {rawBody}
            </Text>
          ) : null}
        </SectionCard>

        <Button
          mode="contained"
          icon="content-save-outline"
          loading={saving}
          disabled={saving}
          onPress={() => void save()}
        >
          Save for review
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
    </View>
  );
}

function validateCaptureDraft({
  amountMinor,
  account,
  counterAccount,
  isTransfer,
  isAdjustment,
  date,
  time,
  fxNeedsRate,
  purchaseCurrency,
  accountCurrency,
}: {
  amountMinor: number;
  account?: Account;
  counterAccount?: Account;
  isTransfer: boolean;
  isAdjustment: boolean;
  date: string;
  time: string;
  fxNeedsRate?: boolean;
  purchaseCurrency?: string;
  accountCurrency?: string;
}): Record<string, string> {
  const errors: Record<string, string> = {};
  if (isAdjustment) {
    if (amountMinor === 0) errors.amount = 'Enter a positive or negative adjustment.';
  } else if (amountMinor <= 0) errors.amount = 'Enter an amount greater than zero.';
  if (fxNeedsRate) {
    errors.amount = `Enter a ${purchaseCurrency} to ${accountCurrency} rate before saving.`;
  }
  if (!account) errors.account = 'Choose an account.';
  if (isTransfer && !counterAccount) errors.counter = 'Choose a destination account.';
  if (!isValidLocalDate(date)) errors.date = 'Use a valid date like 2026-01-31.';
  if (!isValidLocalTime(time)) errors.time = 'Use a valid 24-hour time like 18:45.';
  return errors;
}

function cleanWarnings(warnings?: string[]): string[] | undefined {
  const remaining = (warnings ?? []).filter((warning) => !FIXABLE_WARNINGS.has(warning));
  return remaining.length > 0 ? remaining : undefined;
}

function accountSupporting(
  account: Account | undefined,
  locale: string,
  indexes: ReturnType<typeof useLedger>['indexes'],
): string {
  if (!account) return 'Required';
  return formatMoney(indexedAccountBalance(indexes, account), locale);
}

function rawPayloadText(rawPayload: Record<string, unknown>): string | undefined {
  const body = typeof rawPayload.body === 'string' ? rawPayload.body : undefined;
  const fileName = typeof rawPayload.fileName === 'string' ? rawPayload.fileName : undefined;
  const ocrText = typeof rawPayload.ocrText === 'string' ? rawPayload.ocrText : undefined;
  const subject = typeof rawPayload.subject === 'string' ? rawPayload.subject : undefined;
  return [subject, body ?? ocrText ?? fileName].filter(Boolean).join('\n') || undefined;
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
  heroAmount: {
    fontFamily: tokens.font.nativeFamily.numericMedium,
    fontWeight: '800',
  },
  selectorGrid: { flexDirection: 'row', gap: tokens.space.sm },
});
