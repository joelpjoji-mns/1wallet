import { formatMoney, normalizeCurrencyCode, toMinor } from '@1wallet/domain/money';
import type { Account, TransactionStatus, TransactionType } from '@1wallet/domain/types';
import {
    createCaptureCandidate,
    createTransaction,
    createTransactionSplit,
    enabledCurrencies,
    hasExplicitRate,
    rateBetween,
} from '@1wallet/ledger/services';
import { indexedAccountBalance } from '@1wallet/ledger/services/indexes';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
    Alert,
    Animated,
    Easing,
    PanResponder,
    ScrollView,
    StyleSheet,
    useWindowDimensions,
    View,
} from 'react-native';
import PagerView from 'react-native-pager-view';
import {
    Appbar,
    Button,
    Divider,
    HelperText,
    IconButton,
    Menu,
    Text,
    TextInput,
    TouchableRipple,
    useTheme,
} from 'react-native-paper';
import { resolveAccountIconVisual } from '../src/accountOptions';
import { isAddRecordEntryOrigin, type AddRecordEntryOrigin } from '../src/addRecordNavigation';
import { resolveCategoryIcon, resolveCategoryIconVisual } from '../src/categoryIcons';
import { categoryBreadcrumb } from '../src/categoryTree';
import { withColorAlpha } from '../src/colorAlpha';
import { useBackLayer } from '../src/components/AppBackLayer';
import {
    goBackOrHome,
    InfoRow,
    PremiumTextInput,
    SectionCard,
    TAB_BAR_OVERLAY_CLEARANCE,
    TAB_FAB_BOTTOM_OFFSET,
} from '../src/components/AppKit';
import { OptionListOverlay, type OptionListItem } from '../src/components/OptionListOverlay';
import { PulsingFieldGlow } from '../src/components/PulsingFieldGlow';
import { NoteAutocompleteInput } from '../src/components/record/NoteAutocompleteInput';
import { PaymentMethodSelector } from '../src/components/record/PaymentMethodSelector';
import { RecordCurrencyFields } from '../src/components/record/RecordCurrencyFields';
import {
    numberFromCurrencyText,
    resolveRecordCurrencyDraft,
    trimFxRateValue,
} from '../src/components/record/recordCurrencyMath';
import { RecordDateTimeFields } from '../src/components/record/RecordDateTimeFields';
import {
    AccountPickerOverlay as RecordAccountPickerOverlay,
    CategoryPickerOverlay as RecordCategoryPickerOverlay,
} from '../src/components/record/RecordPickers';
import { RecordSelectorRow as SelectorRow } from '../src/components/record/RecordSelectorRow';
import { buildEnabledCurrencyOptions, optionTitle } from '../src/currencyOptions';
import { freshRateBetween, refreshRatesForPairIfStale } from '../src/exchangeRateFreshness';
import { positiveAmountColor } from '../src/financeColors';
import { PANEL_SWIPE_GESTURE } from '../src/gestureDefaults';
import { iconSurfaceForThemeTone } from '../src/iconSystem';
import { pickReceiptAsset, type ReceiptCaptureSource } from '../src/receiptCapture';
import { extractReceiptFieldsFromPhoto } from '../src/receiptOcr';
import { resolveRecordCurrencyDraftForState } from '../src/recordCurrencyFreshness';
import {
    dateTimeToIso,
    isValidLocalDate,
    isValidLocalTime,
    localDateTimeParts,
} from '../src/recordDateTime';
import {
    categoryKindForTransactionType,
    TRANSACTION_TYPE_BUCKET_OPTIONS,
    transactionTypeLabel,
    TRANSFER_PURPOSE_OPTIONS,
    type TransactionTypeBucket,
} from '../src/transactionTypes';

type AddType = TransactionTypeBucket;
type PickerMode = 'account' | 'counter' | 'category' | 'status' | 'transferType' | null;
type AddPanelPage = 0 | 1;
type ChargeDraft = { id: string; label: string; amount: string };
type AddMissingField = 'amount' | 'account' | 'counter' | 'category' | 'date' | 'charges';
type MaterialCommunityIconName = keyof typeof MaterialCommunityIcons.glyphMap;
type CalcKey =
  | '0'
  | '1'
  | '2'
  | '3'
  | '4'
  | '5'
  | '6'
  | '7'
  | '8'
  | '9'
  | '.'
  | '+'
  | '-'
  | '*'
  | '/'
  | '='
  | 'clear'
  | 'back'
  | 'percent'
  | 'sign';

const TYPE_BUTTONS = TRANSACTION_TYPE_BUCKET_OPTIONS.map((option) => ({
  value: option.value,
  label: option.value === 'adjustment' ? 'Adjust' : option.label,
  icon: option.icon,
  iconTone: option.iconTone,
}));

const CALCULATOR_ROWS: CalcKey[][] = [
  ['clear', 'sign', 'percent', '/'],
  ['7', '8', '9', '*'],
  ['4', '5', '6', '-'],
  ['1', '2', '3', '+'],
  ['0', '.', 'back', '='],
];

const KEYPAD_PAGE: AddPanelPage = 0;
const DETAILS_PAGE: AddPanelPage = 1;
const KEYPAD_SCREEN_HEIGHT_RATIO = 0.5;
const ADD_ENTRY_INITIAL_SCALE = 0.18;
const ADD_ENTRY_FAB_SIZE = 56;
const ADD_ENTRY_TOP_ACTION_X_OFFSET = 28;
const ADD_ENTRY_TOP_ACTION_Y = 56;
const ADD_EXIT_DURATION_MS = 320;
const ADD_EXIT_EASING = Easing.bezier(0.16, 1, 0.3, 1);

const SMALL_NUMBER_WORDS = [
  'zero',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'eleven',
  'twelve',
  'thirteen',
  'fourteen',
  'fifteen',
  'sixteen',
  'seventeen',
  'eighteen',
  'nineteen',
] as const;

const TENS_NUMBER_WORDS = [
  '',
  '',
  'twenty',
  'thirty',
  'forty',
  'fifty',
  'sixty',
  'seventy',
  'eighty',
  'ninety',
] as const;

const NUMBER_WORD_SCALES = [
  { value: 1_000_000_000_000, label: 'trillion' },
  { value: 1_000_000_000, label: 'billion' },
  { value: 1_000_000, label: 'million' },
  { value: 1_000, label: 'thousand' },
] as const;

const MAX_SPELLABLE_AMOUNT = 999_999_999_999_999;

const STATUS_OPTIONS: OptionListItem<TransactionStatus>[] = [
  {
    value: 'cleared',
    label: 'Cleared',
    description: 'Posted now and included in balances',
    icon: 'check-circle-outline',
  },
  {
    value: 'pending',
    label: 'Pending',
    description: 'Waiting to settle, visible in records and filters',
    icon: 'clock-outline',
  },
  {
    value: 'scheduled',
    label: 'Scheduled',
    description: 'Planned for a future bill, EMI, transfer, or income',
    icon: 'calendar-clock-outline',
  },
];

const TRANSFER_TYPE_OPTIONS: OptionListItem<TransactionType>[] = TRANSFER_PURPOSE_OPTIONS;

export default function AddTransaction() {
  const theme = useTheme();
  const { width: windowWidth, height: windowHeight } = useWindowDimensions();
  const { state, indexes, mutate, refreshExchangeRates } = useLedger();
  const routeParams = useLocalSearchParams<{
    accountId?: string | string[];
    entryOrigin?: string | string[];
  }>();
  const pagerRef = useRef<PagerView>(null);
  const entryProgress = useRef(new Animated.Value(0)).current;
  const closingRef = useRef(false);
  const [transitionActive, setTransitionActive] = useState(true);
  const initialDateTime = useMemo(() => localDateTimeParts(new Date()), []);
  const routeAccountId = Array.isArray(routeParams.accountId)
    ? routeParams.accountId[0]
    : routeParams.accountId;
  const routeEntryOrigin = Array.isArray(routeParams.entryOrigin)
    ? routeParams.entryOrigin[0]
    : routeParams.entryOrigin;
  const entryOrigin = isAddRecordEntryOrigin(routeEntryOrigin) ? routeEntryOrigin : 'center';
  const activeAccounts = state.accounts.filter((account) => !account.isArchived);
  const initialAccount =
    activeAccounts.find((account) => account.id === routeAccountId) ?? activeAccounts[0];
  const [type, setType] = useState<AddType>('expense');
  const [status, setStatus] = useState<TransactionStatus>('cleared');
  const [transferType, setTransferType] = useState<TransactionType>('transfer');
  const [amount, setAmount] = useState('');
  const [expression, setExpression] = useState('');
  const [accountId, setAccountId] = useState<string | undefined>(initialAccount?.id);
  const [counterAccountId, setCounterAccountId] = useState<string | undefined>();
  const [categoryId, setCategoryId] = useState<string | undefined>();
  const [paymentMethod, setPaymentMethod] = useState('');
  const [originalCurrency, setOriginalCurrency] = useState(
    initialAccount?.currency ?? state.preferences.baseCurrency,
  );
  const [originalAmount, setOriginalAmount] = useState('');
  const [originalFxRate, setOriginalFxRate] = useState('');
  const [notes, setNotes] = useState('');
  const [date, setDate] = useState(initialDateTime.date);
  const [time, setTime] = useState(initialDateTime.time);
  const [locationLabel, setLocationLabel] = useState('');
  const [charges, setCharges] = useState<ChargeDraft[]>([]);
  const [pickerMode, setPickerMode] = useState<PickerMode>(null);
  const [currencyPickerVisible, setCurrencyPickerVisible] = useState(false);
  const [activePanelPage, setActivePanelPage] = useState<AddPanelPage>(KEYPAD_PAGE);
  const [detailsPageMounted, setDetailsPageMounted] = useState(false);
  const [saving, setSaving] = useState(false);
  const [receiptBusy, setReceiptBusy] = useState(false);
  const [submitAttempted, setSubmitAttempted] = useState(false);
  const [highlightedFields, setHighlightedFields] = useState<Set<AddMissingField>>(() => new Set());
  const [glowPulseKey, setGlowPulseKey] = useState(0);
  const compactKeypad = windowHeight < 760;
  const amountBlockMinHeight = compactKeypad ? 118 : 136;
  const keypadHeight = Math.round(windowHeight * KEYPAD_SCREEN_HEIGHT_RATIO);
  const entryMotion = useMemo(
    () => resolveAddEntryMotion(entryOrigin, windowWidth, windowHeight),
    [entryOrigin, windowHeight, windowWidth],
  );
  const addScreenAnimatedStyle = useMemo(
    () => ({
      opacity: entryProgress.interpolate({
        inputRange: [0, 0.08, 0.22, 1],
        outputRange: [0, 0.86, 1, 1],
      }),
      transform: [
        {
          translateX: entryProgress.interpolate({
            inputRange: [0, 1],
            outputRange: [entryMotion.translateX, 0],
          }),
        },
        {
          translateY: entryProgress.interpolate({
            inputRange: [0, 1],
            outputRange: [entryMotion.translateY, 0],
          }),
        },
        {
          scale: entryProgress.interpolate({
            inputRange: [0, 1],
            outputRange: [entryMotion.scale, 1],
          }),
        },
      ],
    }),
    [entryMotion.scale, entryMotion.translateX, entryMotion.translateY, entryProgress],
  );
  const backdropOpacity = entryProgress.interpolate({
    inputRange: [0, 0.32, 1],
    outputRange: [0, 0.72, 1],
  });

  useEffect(() => {
    closingRef.current = false;
    setTransitionActive(true);
    entryProgress.setValue(0);
    Animated.spring(entryProgress, {
      toValue: 1,
      speed: 19,
      bounciness: 5,
      useNativeDriver: true,
      isInteraction: false,
    }).start(({ finished }) => {
      if (finished && !closingRef.current) setTransitionActive(false);
    });
  }, [entryOrigin, entryProgress]);
  const panelSwipeResponder = useMemo(
    () =>
      PanResponder.create({
        onMoveShouldSetPanResponderCapture: (_, gestureState) => {
          const horizontal = Math.abs(gestureState.dx);
          const vertical = Math.abs(gestureState.dy);
          return (
            horizontal > PANEL_SWIPE_GESTURE.captureDistance &&
            horizontal > vertical * PANEL_SWIPE_GESTURE.verticalRatio
          );
        },
        onMoveShouldSetPanResponder: (_, gestureState) => {
          const horizontal = Math.abs(gestureState.dx);
          const vertical = Math.abs(gestureState.dy);
          return (
            horizontal > PANEL_SWIPE_GESTURE.captureDistance &&
            horizontal > vertical * PANEL_SWIPE_GESTURE.verticalRatio
          );
        },
        onPanResponderRelease: (_, gestureState) => {
          if (gestureState.dx <= -PANEL_SWIPE_GESTURE.triggerDistance) {
            setActivePanelPage(DETAILS_PAGE);
            pagerRef.current?.setPage(DETAILS_PAGE);
            return;
          }
          if (gestureState.dx >= PANEL_SWIPE_GESTURE.triggerDistance) {
            setActivePanelPage(KEYPAD_PAGE);
            pagerRef.current?.setPage(KEYPAD_PAGE);
          }
        },
      }),
    [],
  );

  const enabledCurrencyCodes = useMemo(() => enabledCurrencies(state), [state]);
  const sourceAccount = activeAccounts.find((account) => account.id === accountId);
  const counterAccount = activeAccounts.find((account) => account.id === counterAccountId);
  const sourceAccountVisual = sourceAccount ? resolveAccountIconVisual(sourceAccount) : undefined;
  const counterAccountVisual = counterAccount
    ? resolveAccountIconVisual(counterAccount)
    : undefined;
  const isAdjustment = type === 'adjustment';
  const categoryKind = categoryKindForTransactionType(type);
  const recordType: TransactionType = type === 'transfer' ? transferType : type;
  const categories = useMemo(
    () =>
      state.categories.filter((category) => !category.isArchived && category.kind === categoryKind),
    [categoryKind, state.categories],
  );
  const selectedCategory = categories.find((category) => category.id === categoryId);
  const selectedCategoryParentPath = categoryBreadcrumb(
    state.categories,
    selectedCategory?.parentId,
  );
  const selectedCategoryIcon = selectedCategory
    ? resolveCategoryIcon(selectedCategory, state.categories)
    : 'shape-outline';
  const selectedCategoryVisual = selectedCategory
    ? resolveCategoryIconVisual(selectedCategory, state.categories)
    : undefined;
  const feeCategory = state.categories.find(
    (category) => category.name.toLowerCase() === 'charges, fees',
  );
  const currency = normalizeCurrencyCode(sourceAccount?.currency ?? state.preferences.baseCurrency);
  const purchaseCurrency = normalizeCurrencyCode(originalCurrency || currency);
  const suggestedPurchaseRate =
    sourceAccount &&
    purchaseCurrency !== sourceAccount.currency &&
    hasExplicitRate(state, purchaseCurrency, sourceAccount.currency)
      ? rateBetween(state, purchaseCurrency, sourceAccount.currency)
      : undefined;
  const foreignCurrencyDraft = resolveRecordCurrencyDraft({
    originalAmountText: originalAmount,
    purchaseCurrency,
    postedCurrency: currency,
    fxRateText: originalFxRate,
    suggestedRate: suggestedPurchaseRate,
  });
  const amountValue = numberFromCurrencyText(amount);
  const effectiveAmountValue = Number.isFinite(amountValue)
    ? isAdjustment
      ? amountValue
      : Math.abs(amountValue)
    : 0;
  const amountMinor = sourceAccount
    ? (foreignCurrencyDraft.postedAmountMinor ??
      toMinor(effectiveAmountValue, sourceAccount.currency))
    : 0;
  const chargeTotalMinor =
    sourceAccount && !isAdjustment
      ? charges.reduce(
          (sum, charge) =>
            sum +
            toMinor(Number(charge.amount.replace(/,/g, '').trim()) || 0, sourceAccount.currency),
          0,
        )
      : 0;
  const errors = validate({
    type,
    amountMinor,
    sourceAccount,
    counterAccount,
    chargeTotalMinor,
    date,
    time,
    categoryId,
    fxNeedsRate: foreignCurrencyDraft.needsRate,
    purchaseCurrency,
    accountCurrency: currency,
  });
  const showErrors = submitAttempted;
  const tone = toneForType(type, theme.dark);
  const isForeignPurchase = purchaseCurrency !== currency;
  const calculatorAmount = isForeignPurchase ? originalAmount : amount;
  const calculatorAmountValue = numberFromCurrencyText(calculatorAmount);
  const displayAmount = normalizeDisplayAmount(calculatorAmount || '0');
  const amountWords = useMemo(() => amountToWords(calculatorAmount), [calculatorAmount]);
  const convertedAmountText =
    isForeignPurchase && foreignCurrencyDraft.postedMoney
      ? `${currency} ${formatMoney(foreignCurrencyDraft.postedMoney, state.preferences.locale)}`
      : isForeignPurchase && foreignCurrencyDraft.needsRate && calculatorAmountValue > 0
        ? `${currency} conversion needs rate`
        : undefined;
  const amountSign =
    (type === 'expense' && displayAmount !== '0') ||
    (type === 'adjustment' && calculatorAmountValue < 0 && displayAmount !== '0')
      ? '-'
      : '';
  const currencyPickerOptions = useMemo(
    () =>
      buildEnabledCurrencyOptions(enabledCurrencyCodes, [currency, state.preferences.baseCurrency]),
    [currency, enabledCurrencyCodes, state.preferences.baseCurrency],
  );
  const fieldGlowProps = (field: AddMissingField) => ({
    active: highlightedFields.has(field),
    color: theme.colors.error,
    dark: theme.dark,
    pulseKey: glowPulseKey,
  });
  const glowMissingFields = (fields: AddMissingField[]) => {
    const uniqueFields = Array.from(new Set(fields));
    setHighlightedFields(new Set(uniqueFields));
    setGlowPulseKey((key) => key + 1);
  };

  const closeAddRecord = useCallback(() => {
    if (closingRef.current) return;
    closingRef.current = true;
    setTransitionActive(true);
    Animated.timing(entryProgress, {
      toValue: 0,
      duration: ADD_EXIT_DURATION_MS,
      easing: ADD_EXIT_EASING,
      useNativeDriver: true,
      isInteraction: false,
    }).start(() => goBackOrHome());
  }, [entryProgress]);

  const handleAddBack = useCallback(() => {
    if (currencyPickerVisible) {
      setCurrencyPickerVisible(false);
      return true;
    }
    if (pickerMode) return false;
    closeAddRecord();
    return true;
  }, [closeAddRecord, currencyPickerVisible, pickerMode]);

  useBackLayer(true, handleAddBack);

  const save = async () => {
    setSubmitAttempted(true);
    const canRefreshMissingRate =
      sourceAccount &&
      foreignCurrencyDraft.needsRate &&
      purchaseCurrency !== currency &&
      numberFromCurrencyText(originalAmount) > 0;
    const blockingErrors = { ...errors };
    if (canRefreshMissingRate) delete blockingErrors.amount;
    if (Object.keys(blockingErrors).length > 0 || !sourceAccount) {
      const fields = addMissingFieldsFromErrors(blockingErrors);
      glowMissingFields(fields);
      if (fields.some((field) => field === 'date' || field === 'charges')) showPanel(DETAILS_PAGE);
      return;
    }
    setSaving(true);
    try {
      await refreshRatesForPairIfStale(state, refreshExchangeRates, purchaseCurrency, currency);
      const occurredAt = dateTimeToIso(date, time);
      await mutate((draft) => {
        const draftSourceAccount = draft.accounts.find(
          (account) => account.id === sourceAccount.id,
        );
        if (!draftSourceAccount) throw new Error('Choose an account.');
        const draftPostedCurrency = normalizeCurrencyCode(draftSourceAccount.currency);
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
            `Enter a ${draftPurchaseCurrency} to ${draftPostedCurrency} rate before saving.`,
          );
        }
        const originalMinor = draftForeignCurrency.originalAmountMinor;
        const draftAmountMinor =
          draftForeignCurrency.postedAmountMinor ??
          toMinor(effectiveAmountValue, draftSourceAccount.currency);
        const parent = createTransaction(draft, {
          type: recordType,
          status,
          accountId: draftSourceAccount.id,
          counterAccountId:
            recordType === 'transfer' ||
            recordType === 'card_payment' ||
            recordType === 'loan_repayment'
              ? counterAccount?.id
              : undefined,
          amountMinor: draftAmountMinor,
          currency: draftSourceAccount.currency,
          originalAmountMinor: originalMinor,
          originalCurrency: originalMinor !== undefined ? draftPurchaseCurrency : undefined,
          originalFxRate: originalMinor !== undefined ? draftForeignCurrency.fxRate : undefined,
          categoryId: type === 'transfer' || type === 'adjustment' ? undefined : categoryId,
          paymentMethod: paymentMethod.trim() || undefined,
          notes: notes.trim() || undefined,
          occurredAt,
          locationLabel: locationLabel.trim() || undefined,
        });

        if (type === 'adjustment') return;

        for (const charge of charges) {
          const numeric = Number(charge.amount.replace(/,/g, '').trim()) || 0;
          const chargeMinor = toMinor(numeric, sourceAccount.currency);
          if (chargeMinor <= 0) continue;
          const label = charge.label.trim() || 'Charges';
          if (type === 'transfer') {
            createTransaction(draft, {
              type: 'fee',
              status,
              accountId: sourceAccount.id,
              amountMinor: chargeMinor,
              currency: sourceAccount.currency,
              categoryId: feeCategory?.id,
              notes: `${label} for transfer`,
              occurredAt,
              locationLabel: locationLabel.trim() || undefined,
              originalTransactionId: parent.id,
            });
          } else {
            createTransactionSplit(draft, {
              transactionId: parent.id,
              amountMinor: chargeMinor,
              currency: sourceAccount.currency,
              categoryId: feeCategory?.id ?? categoryId,
              notes: label,
            });
          }
        }
      });
      closeAddRecord();
    } catch (error) {
      Alert.alert('Could not save record', (error as Error).message);
    } finally {
      setSaving(false);
    }
  };

  const addCharge = () => {
    setCharges((current) => [
      ...current,
      { id: `${Date.now()}-${current.length}`, label: 'Charges', amount: '' },
    ]);
  };

  const updateCharge = (id: string, patch: Partial<ChargeDraft>) => {
    setCharges((current) =>
      current.map((charge) => (charge.id === id ? { ...charge, ...patch } : charge)),
    );
  };

  const removeCharge = (id: string) => {
    setCharges((current) => current.filter((charge) => charge.id !== id));
  };

  const setCalculatorAmount = (nextValue: string) => {
    if (!isForeignPurchase) {
      setAmount(nextValue);
      return;
    }
    setOriginalAmount(nextValue);
    const nextDraft = resolveRecordCurrencyDraft({
      originalAmountText: nextValue,
      purchaseCurrency,
      postedCurrency: currency,
      fxRateText: originalFxRate,
      suggestedRate: suggestedPurchaseRate,
    });
    setAmount(nextDraft.postedAmountText ?? '');
  };

  const updateCalculatorAmount = (updater: (current: string) => string) => {
    setCalculatorAmount(updater(calculatorAmount));
  };

  const applyCalculatorKey = (key: CalcKey) => {
    if (/^\d$/.test(key)) {
      updateCalculatorAmount((current) => (current === '0' ? key : `${current}${key}`));
      return;
    }
    if (key === '.') {
      updateCalculatorAmount((current) =>
        current.includes('.') ? current : current ? `${current}.` : '0.',
      );
      return;
    }
    if (key === 'clear') {
      setCalculatorAmount('');
      setExpression('');
      return;
    }
    if (key === 'back') {
      updateCalculatorAmount((current) => current.slice(0, -1));
      return;
    }
    if (key === 'sign') {
      updateCalculatorAmount((current) => {
        if (!current || current === '0') return current;
        return current.startsWith('-') ? current.slice(1) : `-${current}`;
      });
      return;
    }
    if (key === 'percent') {
      updateCalculatorAmount((current) => trimNumber((Number(current || '0') || 0) / 100));
      return;
    }
    if (isOperator(key)) {
      const current = calculatorAmount.trim() || '0';
      if (expression && calculatorAmount) {
        setExpression(`${calculateExpression(`${expression} ${current}`)} ${key}`);
      } else if (expression) {
        setExpression(expression.replace(/[+\-*/]$/, key));
      } else {
        setExpression(`${current} ${key}`);
      }
      setCalculatorAmount('');
      return;
    }
    if (key === '=' && expression) {
      const current = calculatorAmount.trim() || '0';
      setCalculatorAmount(calculateExpression(`${expression} ${current}`));
      setExpression('');
    }
  };

  const changeType = (value: string) => {
    const nextType = value as AddType;
    setType(nextType);
    setCategoryId(undefined);
    if (nextType !== 'transfer') setCounterAccountId(undefined);
    if (nextType === 'transfer') setTransferType('transfer');
    if (nextType === 'adjustment') setCharges([]);
  };

  const changePurchaseCurrency = async (value: string) => {
    const nextCurrency = normalizeCurrencyCode(value);
    setOriginalCurrency(nextCurrency);
    if (nextCurrency === currency) {
      if (isForeignPurchase && originalAmount.trim()) {
        setAmount(originalAmount);
      }
      setOriginalAmount('');
      setOriginalFxRate('');
      return;
    }
    const nextOriginalAmount =
      !originalAmount.trim() && amount.trim() ? normalizeDisplayAmount(amount) : originalAmount;
    if (nextOriginalAmount !== originalAmount) {
      setOriginalAmount(nextOriginalAmount);
    }
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
    const nextSuggestedRate =
      sourceAccount && hasExplicitRate(rateState, nextCurrency, currency)
        ? freshRateBetween(rateState, nextCurrency, currency)
        : undefined;
    const nextFxRateText =
      !originalFxRate.trim() && nextSuggestedRate
        ? trimFxRateValue(nextSuggestedRate)
        : originalFxRate;
    if (nextFxRateText !== originalFxRate) {
      setOriginalFxRate(nextFxRateText);
    }
    const nextDraft = resolveRecordCurrencyDraft({
      originalAmountText: nextOriginalAmount,
      purchaseCurrency: nextCurrency,
      postedCurrency: currency,
      fxRateText: nextFxRateText,
      suggestedRate: nextSuggestedRate,
    });
    setAmount(nextDraft.postedAmountText ?? '');
  };

  const showPanel = (page: AddPanelPage) => {
    if (page === DETAILS_PAGE) setDetailsPageMounted(true);
    setActivePanelPage(page);
    pagerRef.current?.setPage(page);
  };

  const captureReceipt = async (source: ReceiptCaptureSource) => {
    setReceiptBusy(true);
    try {
      const receipt = await pickReceiptAsset(source);
      if (!receipt) return;
      const draftOccurredAt = dateTimeToIso(date, time);
      const trimmedLocation = locationLabel.trim();
      const trimmedNotes = notes.trim();
      const trimmedPaymentMethod = paymentMethod.trim();
      const parsedAmountMinor =
        type === 'adjustment'
          ? amountMinor !== 0
            ? amountMinor
            : undefined
          : amountMinor > 0
            ? amountMinor
            : undefined;
      const receiptFields = await extractReceiptFieldsFromPhoto(receipt, {
        fallbackCurrency: currency,
        fallbackOccurredAt: draftOccurredAt,
        fileName: receipt.name,
      });
      const receiptAmountMinor = receiptFields.amountMinor ?? parsedAmountMinor;
      const receiptCurrency = receiptFields.currency ?? currency;
      const receiptMerchant = receiptFields.merchant ?? (trimmedLocation || undefined);
      const receiptLocation = trimmedLocation || receiptMerchant;
      const receiptPaymentMethod = trimmedPaymentMethod || receiptFields.paymentMethod;
      const receiptNotes = trimmedNotes || receiptFields.notes || `Receipt: ${receipt.name}`;
      const receiptOccurredAt = receiptFields.occurredAt ?? draftOccurredAt;
      const receiptWarnings = uniqueReceiptWarnings([
        receiptAmountMinor ? 'review receipt draft fields' : 'amount missing from receipt draft',
        ...receiptFields.warnings,
      ]);
      await mutate((draft) => {
        createCaptureCandidate(draft, {
          source: 'import',
          rawHash: `receipt:${receipt.source}:${receipt.uri}`,
          rawPayload: {
            kind: 'receipt_attachment',
            source: receipt.source,
            fileName: receipt.name,
            mimeType: receipt.mimeType,
            size: receipt.size,
            width: receipt.width,
            height: receipt.height,
            uri: receipt.uri,
            capturedAt: new Date().toISOString(),
            ocrProvider: receiptFields.provider,
            ocrStatus: receiptFields.status,
            ocrText: receiptFields.text,
            ocrLines: receiptFields.lines,
            ocrParsed: {
              amountMinor: receiptFields.amountMinor,
              currency: receiptFields.currency,
              merchant: receiptFields.merchant,
              occurredAt: receiptFields.occurredAt,
              paymentMethod: receiptFields.paymentMethod,
            },
            ocrError: receiptFields.errorMessage,
            ocrWarnings: receiptFields.warnings,
            sourceScreen: 'add_record',
            draft: {
              type: recordType,
              status,
              amountMinor: receiptAmountMinor,
              currency,
              originalCurrency: purchaseCurrency,
              originalAmount,
              originalFxRate,
              occurredAt: receiptOccurredAt,
              accountId: sourceAccount?.id,
              counterAccountId: type === 'transfer' ? counterAccount?.id : undefined,
              categoryId: type === 'transfer' || type === 'adjustment' ? undefined : categoryId,
              paymentMethod: receiptPaymentMethod || undefined,
              locationLabel: receiptLocation || undefined,
              notes: trimmedNotes || undefined,
            },
          },
          parsedAmountMinor: receiptAmountMinor,
          parsedCurrency: receiptCurrency,
          parsedMerchant: receiptMerchant,
          parsedLocationLabel: receiptLocation,
          parsedNotes: receiptNotes,
          parsedPaymentMethod: receiptPaymentMethod || undefined,
          parsedOccurredAt: receiptOccurredAt,
          suggestedAccountId: sourceAccount?.id,
          suggestedCounterAccountId: type === 'transfer' ? counterAccount?.id : undefined,
          suggestedCategoryId:
            type === 'transfer' || type === 'adjustment' ? undefined : categoryId,
          suggestedType: recordType,
          confidence: Math.max(receiptFields.confidence, receiptAmountMinor ? 68 : 28),
          externalRef: receipt.uri,
          warnings: receiptWarnings,
        });
      });
      router.push('/review' as never);
    } catch (error) {
      Alert.alert('Could not import receipt', (error as Error).message);
    } finally {
      setReceiptBusy(false);
    }
  };

  return (
    <View style={styles.transitionHost}>
      {transitionActive ? (
        <Animated.View
          pointerEvents="none"
          style={[
            styles.transitionBackdrop,
            { backgroundColor: theme.colors.background, opacity: backdropOpacity },
          ]}
        />
      ) : null}
      <Animated.View
        renderToHardwareTextureAndroid={transitionActive}
        shouldRasterizeIOS={transitionActive}
        style={[
          styles.screen,
          { backgroundColor: theme.colors.background },
          addScreenAnimatedStyle,
        ]}
      >
        <Appbar.Header elevated={false} style={{ backgroundColor: theme.colors.background }}>
          <Appbar.BackAction onPress={closeAddRecord} />
          <Appbar.Content title="Add record" titleStyle={styles.appbarTitle} />
          <Appbar.Action
            icon="camera-outline"
            disabled={receiptBusy}
            onPress={() => void captureReceipt('camera')}
          />
          <Appbar.Action icon="check" disabled={saving} onPress={() => void save()} />
        </Appbar.Header>

        <View style={styles.content}>
          <RecordTypeTabs value={type} tone={tone} onChange={changeType} />
          <AddPanelTabs activePage={activePanelPage} tone={tone} onChange={showPanel} />

          <View style={styles.recordSwipeSurface} {...panelSwipeResponder.panHandlers}>
            <PagerView
              ref={pagerRef}
              style={styles.recordPager}
              initialPage={KEYPAD_PAGE}
              onPageScroll={(event) => {
                if (
                  !detailsPageMounted &&
                  event.nativeEvent.position === KEYPAD_PAGE &&
                  event.nativeEvent.offset > 0.04
                ) {
                  setDetailsPageMounted(true);
                }
              }}
              onPageSelected={(event) => {
                const nextPage = event.nativeEvent.position as AddPanelPage;
                if (nextPage === DETAILS_PAGE) setDetailsPageMounted(true);
                setActivePanelPage(nextPage);
              }}
            >
              <View key="keypad" collapsable={false} style={styles.pagerPage}>
                <View style={styles.keypadPageContent}>
                  <PulsingFieldGlow
                    {...fieldGlowProps('amount')}
                    style={[styles.amountGlow, { minHeight: amountBlockMinHeight }]}
                  >
                    <View
                      style={[
                        styles.amountBlock,
                        {
                          backgroundColor: theme.colors.elevation.level1,
                          borderColor: theme.colors.outlineVariant,
                          minHeight: amountBlockMinHeight,
                        },
                      ]}
                    >
                      <View
                        style={[
                          styles.amountValueRow,
                          convertedAmountText ? styles.amountValueRowWithConversion : null,
                        ]}
                      >
                        <Text
                          variant="displayMedium"
                          numberOfLines={1}
                          adjustsFontSizeToFit
                          minimumFontScale={0.34}
                          style={[styles.amountText, { color: tone.amount }]}
                        >
                          {amountSign}
                          {displayAmount}
                        </Text>
                        <View style={styles.amountCurrencyAnchor}>
                          <Menu
                            visible={currencyPickerVisible}
                            onDismiss={() => setCurrencyPickerVisible(false)}
                            anchorPosition="bottom"
                            contentStyle={[
                              styles.currencyMenu,
                              { backgroundColor: theme.colors.elevation.level2 },
                            ]}
                            anchor={
                              <TouchableRipple
                                accessibilityLabel="Choose purchase currency"
                                accessibilityRole="button"
                                borderless
                                onPress={() => setCurrencyPickerVisible(true)}
                                style={[
                                  styles.currencyChip,
                                  {
                                    backgroundColor: theme.colors.secondaryContainer,
                                    borderColor: theme.colors.outlineVariant,
                                  },
                                ]}
                              >
                                <View style={styles.currencyChipInner}>
                                  <Text
                                    variant="labelLarge"
                                    numberOfLines={1}
                                    style={[
                                      styles.currencyChipText,
                                      { color: theme.colors.onSecondaryContainer },
                                    ]}
                                  >
                                    {purchaseCurrency}
                                  </Text>
                                  <MaterialCommunityIcons
                                    name="chevron-down"
                                    size={18}
                                    color={theme.colors.onSecondaryContainer}
                                  />
                                </View>
                              </TouchableRipple>
                            }
                          >
                            <ScrollView
                              style={styles.currencyMenuScroll}
                              keyboardShouldPersistTaps="handled"
                              showsVerticalScrollIndicator={false}
                            >
                              {currencyPickerOptions.map((option) => (
                                <Menu.Item
                                  key={option.value}
                                  leadingIcon={option.icon}
                                  trailingIcon={
                                    option.value === purchaseCurrency ? 'check' : undefined
                                  }
                                  title={optionTitle(option)}
                                  onPress={() => {
                                    changePurchaseCurrency(option.value);
                                    setCurrencyPickerVisible(false);
                                  }}
                                />
                              ))}
                            </ScrollView>
                          </Menu>
                        </View>
                      </View>
                      <View
                        style={[
                          styles.amountMetaStack,
                          convertedAmountText ? styles.amountMetaStackWithConversion : null,
                        ]}
                      >
                        <Text
                          variant="labelSmall"
                          numberOfLines={1}
                          style={[styles.expressionText, { color: theme.colors.onSurfaceVariant }]}
                        >
                          {expression || ' '}
                        </Text>
                        {convertedAmountText ? (
                          <Text
                            variant="titleMedium"
                            numberOfLines={1}
                            adjustsFontSizeToFit
                            minimumFontScale={0.72}
                            style={[styles.convertedAmountText, { color: theme.colors.onSurface }]}
                          >
                            {convertedAmountText}
                          </Text>
                        ) : null}
                        <AmountWordsLine text={amountWords} toneColor={tone.amount} />
                      </View>
                    </View>
                  </PulsingFieldGlow>

                  <View style={styles.selectorGrid}>
                    <PulsingFieldGlow {...fieldGlowProps('account')} style={styles.selectorGlow}>
                      <SelectorRow
                        icon={sourceAccountVisual?.icon ?? 'wallet-outline'}
                        iconBackgroundColor={sourceAccountVisual?.backgroundColor}
                        iconColor={sourceAccountVisual?.iconColor}
                        label={type === 'transfer' ? 'From' : 'Account'}
                        value={sourceAccount?.name ?? 'Choose'}
                        valueNumberOfLines={2}
                        supporting={
                          sourceAccount
                            ? formatMoney(
                                indexedAccountBalance(indexes, sourceAccount),
                                state.preferences.locale,
                              )
                            : undefined
                        }
                        compact
                        style={styles.keypadSelectorRow}
                        onPress={() => setPickerMode('account')}
                      />
                    </PulsingFieldGlow>
                    {type === 'transfer' ? (
                      <PulsingFieldGlow {...fieldGlowProps('counter')} style={styles.selectorGlow}>
                        <SelectorRow
                          icon={counterAccountVisual?.icon ?? 'swap-horizontal'}
                          iconBackgroundColor={counterAccountVisual?.backgroundColor}
                          iconColor={counterAccountVisual?.iconColor}
                          label="To account"
                          value={counterAccount?.name ?? 'Choose'}
                          valueNumberOfLines={2}
                          supporting="Required"
                          compact
                          style={styles.keypadSelectorRow}
                          onPress={() => setPickerMode('counter')}
                        />
                      </PulsingFieldGlow>
                    ) : type === 'adjustment' ? (
                      <View
                        style={[
                          styles.adjustmentSummary,
                          {
                            backgroundColor: theme.colors.elevation.level1,
                            borderColor: theme.colors.outlineVariant,
                          },
                        ]}
                      >
                        <View
                          style={[
                            styles.selectorIcon,
                            { backgroundColor: theme.colors.primaryContainer },
                          ]}
                        >
                          <MaterialCommunityIcons
                            name="tune-variant"
                            size={20}
                            color={theme.colors.primary}
                          />
                        </View>
                        <View style={styles.adjustmentCopy}>
                          <Text
                            variant="labelMedium"
                            style={{ color: theme.colors.onSurfaceVariant }}
                          >
                            Adjustment
                          </Text>
                          <Text
                            variant="titleSmall"
                            numberOfLines={1}
                            style={styles.adjustmentValue}
                          >
                            Balance correction
                          </Text>
                          <Text
                            variant="bodySmall"
                            numberOfLines={1}
                            style={{ color: theme.colors.onSurfaceVariant }}
                          >
                            Direct correction
                          </Text>
                        </View>
                      </View>
                    ) : (
                      <PulsingFieldGlow {...fieldGlowProps('category')} style={styles.selectorGlow}>
                        <SelectorRow
                          icon={selectedCategoryIcon}
                          iconBackgroundColor={selectedCategoryVisual?.backgroundColor}
                          iconColor={selectedCategoryVisual?.iconColor}
                          label="Category"
                          value={selectedCategory?.name ?? 'Choose'}
                          valueNumberOfLines={2}
                          supporting={selectedCategoryParentPath}
                          compact
                          style={styles.keypadSelectorRow}
                          onPress={() => setPickerMode('category')}
                        />
                      </PulsingFieldGlow>
                    )}
                  </View>

                  <View style={[styles.keypadFrame, { height: keypadHeight }]}>
                    <View style={styles.keypadPanel}>
                      <CalculatorKeypad
                        compact={compactKeypad}
                        tone={tone}
                        onPress={applyCalculatorKey}
                      />
                    </View>
                  </View>
                </View>
              </View>

              <View key="details" collapsable={false} style={styles.pagerPage}>
                {detailsPageMounted ? (
                  <ScrollView
                    style={styles.detailsPanel}
                    contentContainerStyle={styles.detailsContent}
                    keyboardShouldPersistTaps="handled"
                    showsVerticalScrollIndicator={false}
                  >
                    <SectionCard title="Details">
                      <NoteAutocompleteInput
                        value={notes}
                        onChangeText={setNotes}
                        sources={state.transactions}
                        numberOfLines={3}
                      />
                      <PulsingFieldGlow {...fieldGlowProps('date')}>
                        <RecordDateTimeFields
                          date={date}
                          time={time}
                          onChangeDate={setDate}
                          onChangeTime={setTime}
                        />
                      </PulsingFieldGlow>
                      <SelectorRow
                        icon="list-status"
                        label="Status"
                        value={optionLabel(STATUS_OPTIONS, status)}
                        supporting={
                          status === 'scheduled'
                            ? 'Upcoming payment or income'
                            : status === 'pending'
                              ? 'Waiting to settle'
                              : 'Posted now'
                        }
                        onPress={() => setPickerMode('status')}
                      />
                      {type === 'transfer' ? (
                        <SelectorRow
                          icon="swap-horizontal"
                          label="Transfer purpose"
                          value={transactionTypeLabel(transferType)}
                          supporting={
                            transferType === 'card_payment'
                              ? 'Credit card bill payment'
                              : transferType === 'loan_repayment'
                                ? 'Loan EMI or repayment'
                                : 'Move money between accounts'
                          }
                          onPress={() => setPickerMode('transferType')}
                        />
                      ) : null}
                      <RecordCurrencyFields
                        accountCurrency={sourceAccount?.currency}
                        baseCurrency={state.preferences.baseCurrency}
                        enabledCurrencies={enabledCurrencyCodes}
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
                      <PaymentMethodSelector
                        account={sourceAccount}
                        transactionType={type}
                        value={paymentMethod}
                        onChange={setPaymentMethod}
                        autoFill="suggested"
                      />
                      <PremiumTextInput
                        label="Place"
                        value={locationLabel}
                        onChangeText={setLocationLabel}
                        left={<TextInput.Icon icon="map-marker-outline" />}
                      />
                    </SectionCard>

                    <SectionCard title="Receipt">
                      <View style={styles.receiptActions}>
                        <Button
                          mode="contained-tonal"
                          icon="camera-outline"
                          loading={receiptBusy}
                          disabled={receiptBusy}
                          onPress={() => void captureReceipt('camera')}
                        >
                          Scan
                        </Button>
                        <Button mode="outlined" icon="image-outline" disabled={receiptBusy}>
                          Photo
                        </Button>
                        <Button
                          mode="outlined"
                          icon="paperclip"
                          disabled={receiptBusy}
                          onPress={() => void captureReceipt('file')}
                        >
                          File
                        </Button>
                      </View>
                    </SectionCard>

                    {type !== 'adjustment' ? (
                      <SectionCard
                        title={type === 'transfer' ? 'Transfer fees' : 'Charges and line items'}
                      >
                        {charges.length === 0 ? (
                          <Text
                            variant="bodyMedium"
                            style={{ color: theme.colors.onSurfaceVariant }}
                          >
                            No extra charges added.
                          </Text>
                        ) : (
                          charges.map((charge, index) => (
                            <PulsingFieldGlow key={charge.id} {...fieldGlowProps('charges')}>
                              <View>
                                <View style={styles.chargeRow}>
                                  <PremiumTextInput
                                    label="Name"
                                    value={charge.label}
                                    onChangeText={(value) =>
                                      updateCharge(charge.id, { label: value })
                                    }
                                    style={styles.chargeLabel}
                                  />
                                  <PremiumTextInput
                                    label="Amount"
                                    value={charge.amount}
                                    onChangeText={(value) =>
                                      updateCharge(charge.id, { amount: value })
                                    }
                                    keyboardType="decimal-pad"
                                    style={styles.chargeAmount}
                                  />
                                  <IconButton
                                    icon="close"
                                    onPress={() => removeCharge(charge.id)}
                                  />
                                </View>
                                {index < charges.length - 1 ? <Divider /> : null}
                              </View>
                            </PulsingFieldGlow>
                          ))
                        )}
                        <HelperText type="error" visible={showErrors && Boolean(errors.charges)}>
                          {errors.charges}
                        </HelperText>
                        {chargeTotalMinor > 0 && sourceAccount ? (
                          <InfoRow
                            icon="script-text-outline"
                            label={type === 'transfer' ? 'Extra fees' : 'Line items'}
                            value={formatMoney(
                              { amountMinor: chargeTotalMinor, currency: sourceAccount.currency },
                              state.preferences.locale,
                            )}
                            tone="warning"
                          />
                        ) : null}
                        <Button mode="contained-tonal" icon="plus" onPress={addCharge}>
                          Add charge
                        </Button>
                      </SectionCard>
                    ) : null}

                    <Button
                      mode="contained"
                      icon="content-save-outline"
                      loading={saving}
                      disabled={saving}
                      onPress={() => void save()}
                    >
                      Save record
                    </Button>
                  </ScrollView>
                ) : (
                  <View style={styles.detailsPanelPlaceholder} />
                )}
              </View>
            </PagerView>
          </View>
        </View>

        <RecordAccountPickerOverlay
          visible={pickerMode === 'account' || pickerMode === 'counter'}
          title={pickerMode === 'counter' ? 'Choose destination' : 'Choose account'}
          accounts={
            pickerMode === 'counter'
              ? activeAccounts.filter((account) => account.id !== accountId)
              : activeAccounts
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
          kind={categoryKind}
          categories={state.categories}
          selectedId={categoryId}
          allowClear={false}
          leafOnly
          onDismiss={() => setPickerMode(null)}
          onSelect={(category) => {
            setCategoryId(category.id);
            setPickerMode(null);
          }}
        />
        <OptionListOverlay
          visible={pickerMode === 'status'}
          title="Record status"
          options={STATUS_OPTIONS}
          selectedValue={status}
          searchable={false}
          onDismiss={() => setPickerMode(null)}
          onSelect={(option) => {
            setStatus(option.value);
            setPickerMode(null);
          }}
        />
        <OptionListOverlay
          visible={pickerMode === 'transferType'}
          title="Transfer purpose"
          options={TRANSFER_TYPE_OPTIONS}
          selectedValue={transferType}
          searchable={false}
          onDismiss={() => setPickerMode(null)}
          onSelect={(option) => {
            setTransferType(option.value);
            setPickerMode(null);
          }}
        />
      </Animated.View>
    </View>
  );
}

function RecordTypeTabs({
  value,
  tone,
  onChange,
}: {
  value: AddType;
  tone: ReturnType<typeof toneForType>;
  onChange: (value: string) => void;
}) {
  const theme = useTheme();

  return (
    <View
      style={[
        styles.typeTabs,
        {
          backgroundColor: theme.colors.elevation.level1,
          borderColor: theme.colors.outlineVariant,
        },
      ]}
    >
      {TYPE_BUTTONS.map((option) => {
        const active = option.value === value;
        const color = active ? tone.amount : theme.colors.onSurfaceVariant;
        const iconSurface = iconSurfaceForThemeTone(theme, option.iconTone);
        return (
          <TouchableRipple
            key={option.value}
            accessibilityRole="button"
            accessibilityState={{ selected: active }}
            borderless
            onPress={() => onChange(option.value)}
            style={[
              styles.typeTab,
              active
                ? {
                    backgroundColor: withColorAlpha(tone.amount, theme.dark ? 0.18 : 0.1),
                    borderColor: withColorAlpha(tone.amount, theme.dark ? 0.56 : 0.4),
                  }
                : { borderColor: 'transparent' },
            ]}
          >
            <View style={styles.typeTabInner}>
              <View style={[styles.typeTabIcon, { backgroundColor: iconSurface.backgroundColor }]}>
                <MaterialCommunityIcons
                  name={option.icon}
                  size={16}
                  color={iconSurface.iconColor}
                />
              </View>
              <Text
                variant="labelMedium"
                numberOfLines={1}
                style={[styles.typeTabLabel, { color }]}
              >
                {option.label}
              </Text>
            </View>
          </TouchableRipple>
        );
      })}
    </View>
  );
}

function AddPanelTabs({
  activePage,
  tone,
  onChange,
}: {
  activePage: AddPanelPage;
  tone: ReturnType<typeof toneForType>;
  onChange: (page: AddPanelPage) => void;
}) {
  const theme = useTheme();
  const tabs: { page: AddPanelPage; label: string; icon: MaterialCommunityIconName }[] = [
    { page: KEYPAD_PAGE, label: 'Keypad', icon: 'calculator-variant-outline' },
    { page: DETAILS_PAGE, label: 'Details', icon: 'playlist-edit' },
  ];

  return (
    <View
      style={[
        styles.panelTabs,
        {
          backgroundColor: theme.colors.elevation.level1,
          borderColor: theme.colors.outlineVariant,
        },
      ]}
    >
      {tabs.map((tab) => {
        const active = activePage === tab.page;
        const color = active ? tone.amount : theme.colors.onSurfaceVariant;
        return (
          <TouchableRipple
            key={tab.page}
            accessibilityRole="tab"
            accessibilityState={{ selected: active }}
            borderless
            onPress={() => onChange(tab.page)}
            style={[
              styles.panelTab,
              active
                ? {
                    backgroundColor: withColorAlpha(tone.amount, theme.dark ? 0.16 : 0.08),
                    borderColor: withColorAlpha(tone.amount, theme.dark ? 0.5 : 0.36),
                  }
                : { borderColor: 'transparent' },
            ]}
          >
            <View style={styles.panelTabInner}>
              <MaterialCommunityIcons name={tab.icon} size={18} color={color} />
              <Text variant="labelLarge" numberOfLines={1} style={{ color, fontWeight: '800' }}>
                {tab.label}
              </Text>
            </View>
          </TouchableRipple>
        );
      })}
    </View>
  );
}

function CalculatorKeypad({
  compact,
  tone,
  onPress,
}: {
  compact: boolean;
  tone: ReturnType<typeof toneForType>;
  onPress: (key: CalcKey) => void;
}) {
  const theme = useTheme();
  return (
    <View style={[styles.keypad, compact && styles.keypadCompact]}>
      {CALCULATOR_ROWS.map((row) => (
        <View key={row.join('-')} style={[styles.keypadRow, compact && styles.keypadRowCompact]}>
          {row.map((key) => {
            const emphasized = key === '=';
            const operator = isOperator(key) || key === 'percent' || key === 'sign';
            const backgroundColor = emphasized
              ? tone.equals
              : operator
                ? tone.operator
                : theme.colors.elevation.level2;
            const color = emphasized
              ? tone.onEquals
              : operator
                ? tone.onOperator
                : theme.colors.onSurface;
            return (
              <TouchableRipple
                key={key}
                style={[styles.key, compact && styles.keyCompact, { backgroundColor }]}
                borderless
                onPress={() => onPress(key)}
              >
                <View style={styles.keyInner}>
                  {key === 'back' ? (
                    <MaterialCommunityIcons
                      name="backspace-outline"
                      size={compact ? 26 : 30}
                      color={color}
                    />
                  ) : (
                    <Text
                      variant="headlineSmall"
                      style={[styles.keyText, compact && styles.keyTextCompact, { color }]}
                    >
                      {keyLabel(key)}
                    </Text>
                  )}
                </View>
              </TouchableRipple>
            );
          })}
        </View>
      ))}
    </View>
  );
}

function AmountWordsLine({ text, toneColor }: { text: string; toneColor: string }) {
  const theme = useTheme();
  const animation = useRef(new Animated.Value(1)).current;
  const [visibleText, setVisibleText] = useState(text);
  const [visibleCharacters, setVisibleCharacters] = useState(text.length);

  useEffect(() => {
    const nextText = text || 'zero';
    const charactersPerTick = Math.max(1, Math.ceil(nextText.length / 18));
    let nextVisibleCharacters = 0;

    setVisibleText(nextText);
    setVisibleCharacters(nextText.length <= 1 ? nextText.length : 1);
    animation.setValue(0);
    Animated.timing(animation, {
      toValue: 1,
      duration: 180,
      easing: Easing.out(Easing.cubic),
      useNativeDriver: true,
    }).start();

    const interval = setInterval(() => {
      nextVisibleCharacters = Math.min(nextText.length, nextVisibleCharacters + charactersPerTick);
      setVisibleCharacters(nextVisibleCharacters);
      if (nextVisibleCharacters >= nextText.length) clearInterval(interval);
    }, 22);

    return () => clearInterval(interval);
  }, [animation, text]);

  const opacity = animation.interpolate({ inputRange: [0, 1], outputRange: [0.28, 1] });
  const translateY = animation.interpolate({ inputRange: [0, 1], outputRange: [3, 0] });
  const color = withColorAlpha(toneColor, theme.dark ? 0.64 : 0.58);

  return (
    <Animated.Text
      accessibilityLabel={`Amount in words: ${text}`}
      numberOfLines={1}
      style={[styles.amountWordsText, { color, opacity, transform: [{ translateY }] }]}
    >
      {visibleText.slice(0, visibleCharacters)}
    </Animated.Text>
  );
}

function resolveAddEntryMotion(
  origin: AddRecordEntryOrigin,
  windowWidth: number,
  windowHeight: number,
) {
  if (origin === 'center') return { scale: 0.92, translateX: 0, translateY: 0 };

  const sourceX =
    origin === 'fab'
      ? windowWidth - tokens.space.lg - ADD_ENTRY_FAB_SIZE / 2
      : windowWidth - ADD_ENTRY_TOP_ACTION_X_OFFSET;
  const sourceY =
    origin === 'fab'
      ? windowHeight - TAB_BAR_OVERLAY_CLEARANCE - TAB_FAB_BOTTOM_OFFSET - ADD_ENTRY_FAB_SIZE / 2
      : ADD_ENTRY_TOP_ACTION_Y;

  return {
    scale: ADD_ENTRY_INITIAL_SCALE,
    translateX: clamp(sourceX, 0, windowWidth) - windowWidth / 2,
    translateY: clamp(sourceY, 0, windowHeight) - windowHeight / 2,
  };
}

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(Math.max(value, minimum), maximum);
}

function validate({
  type,
  amountMinor,
  sourceAccount,
  counterAccount,
  chargeTotalMinor,
  date,
  time,
  categoryId,
  fxNeedsRate,
  purchaseCurrency,
  accountCurrency,
}: {
  type: AddType;
  amountMinor: number;
  sourceAccount?: Account;
  counterAccount?: Account;
  chargeTotalMinor: number;
  date: string;
  time: string;
  categoryId?: string;
  fxNeedsRate?: boolean;
  purchaseCurrency?: string;
  accountCurrency?: string;
}): Record<string, string> {
  const errors: Record<string, string> = {};
  if (type === 'adjustment') {
    if (amountMinor === 0) errors.amount = 'Enter a positive or negative adjustment.';
  } else if (amountMinor <= 0) errors.amount = 'Enter an amount greater than zero.';
  if (fxNeedsRate) {
    errors.amount = `Enter a ${purchaseCurrency} to ${accountCurrency} rate before saving.`;
  }
  if (!sourceAccount) errors.account = 'Choose an account.';
  if (type === 'transfer' && !counterAccount) errors.counter = 'Choose a destination account.';
  if (type !== 'transfer' && type !== 'adjustment' && !categoryId) {
    errors.category = 'Choose a category.';
  }
  if (!isValidLocalDate(date)) errors.date = 'Use a valid date like 2026-01-31.';
  if (!isValidLocalTime(time)) errors.time = 'Use a valid 24-hour time like 18:45.';
  if (type !== 'transfer' && type !== 'adjustment' && chargeTotalMinor > amountMinor) {
    errors.charges = 'Line-item charges cannot exceed the record amount.';
  }
  return errors;
}

function addMissingFieldsFromErrors(errors: Record<string, string>): AddMissingField[] {
  const fields: AddMissingField[] = [];
  if (errors.amount) fields.push('amount');
  if (errors.account) fields.push('account');
  if (errors.counter) fields.push('counter');
  if (errors.category) fields.push('category');
  if (errors.date || errors.time) fields.push('date');
  if (errors.charges) fields.push('charges');
  return fields;
}

function isOperator(key: CalcKey): key is '+' | '-' | '*' | '/' {
  return key === '+' || key === '-' || key === '*' || key === '/';
}

function calculateExpression(value: string): string {
  const tokens = value.trim().split(/\s+/);
  let result = Number(tokens[0] ?? 0);
  for (let index = 1; index < tokens.length; index += 2) {
    const operator = tokens[index];
    const next = Number(tokens[index + 1] ?? 0);
    if (!Number.isFinite(next)) continue;
    if (operator === '+') result += next;
    if (operator === '-') result -= next;
    if (operator === '*') result *= next;
    if (operator === '/' && next !== 0) result /= next;
  }
  return trimNumber(result);
}

function trimNumber(value: number): string {
  if (!Number.isFinite(value)) return '';
  return String(Math.round(value * 100) / 100);
}

function normalizeDisplayAmount(value: string): string {
  return value.startsWith('-') ? value.slice(1) || '0' : value;
}

function amountToWords(value: string): string {
  const cleaned = value.replace(/,/g, '').trim();
  if (!cleaned || cleaned === '-' || cleaned === '.' || cleaned === '-.') return 'zero';

  const negative = cleaned.startsWith('-');
  const unsigned = negative ? cleaned.slice(1) : cleaned;
  const [integerPart = '', fractionPart] = unsigned.split('.');
  const integerDigits = integerPart.replace(/\D/g, '').replace(/^0+(?=\d)/, '') || '0';
  const integerAmount = Number(integerDigits);
  const fractionDigits = (fractionPart ?? '').replace(/\D/g, '').slice(0, 4);

  if (!Number.isFinite(integerAmount) || integerAmount > MAX_SPELLABLE_AMOUNT) {
    return negative ? 'minus amount too large to spell' : 'amount too large to spell';
  }

  const hasNonZeroFraction = [...fractionDigits].some((digit) => digit !== '0');
  const shouldSayNegative = negative && (integerAmount > 0 || hasNonZeroFraction);
  const words = [spellIntegerAmount(integerAmount)];

  if (fractionPart !== undefined) {
    words.push('point');
    if (fractionDigits.length > 0) {
      words.push(...[...fractionDigits].map((digit) => smallNumberWord(Number(digit))));
    }
  }

  return `${shouldSayNegative ? 'minus ' : ''}${words.join(' ')}`.replace(/\s+/g, ' ').trim();
}

function spellIntegerAmount(value: number): string {
  if (value === 0) return 'zero';

  let remainingAmount = Math.floor(value);
  const words: string[] = [];
  for (const scale of NUMBER_WORD_SCALES) {
    if (remainingAmount < scale.value) continue;
    const scaleCount = Math.floor(remainingAmount / scale.value);
    words.push(`${spellIntegerAmount(scaleCount)} ${scale.label}`);
    remainingAmount %= scale.value;
  }
  if (remainingAmount > 0) words.push(spellUnderThousand(remainingAmount));
  return words.join(' ');
}

function spellUnderThousand(value: number): string {
  const hundreds = Math.floor(value / 100);
  const remainder = value % 100;
  const words: string[] = [];

  if (hundreds > 0) words.push(`${smallNumberWord(hundreds)} hundred`);
  if (remainder > 0) words.push(spellUnderHundred(remainder));
  return words.join(' ');
}

function spellUnderHundred(value: number): string {
  if (value < 20) return smallNumberWord(value);
  const tens = Math.floor(value / 10);
  const remainder = value % 10;
  return remainder > 0
    ? `${tensNumberWord(tens)} ${smallNumberWord(remainder)}`
    : tensNumberWord(tens);
}

function smallNumberWord(value: number): string {
  return SMALL_NUMBER_WORDS[value] ?? 'zero';
}

function tensNumberWord(value: number): string {
  return TENS_NUMBER_WORDS[value] ?? '';
}

function uniqueReceiptWarnings(warnings: string[]): string[] {
  return [...new Set(warnings.filter(Boolean))];
}

function keyLabel(key: CalcKey): string {
  if (key === 'clear') return 'AC';
  if (key === 'percent') return '%';
  if (key === 'sign') return '+/-';
  if (key === '*') return 'x';
  return key;
}

function optionLabel<TValue extends string>(
  options: readonly OptionListItem<TValue>[],
  value: TValue,
) {
  return options.find((option) => option.value === value)?.label ?? value;
}

function toneForType(type: AddType, isDark: boolean) {
  const scheme = isDark ? tokens.color.md3.dark : tokens.color.md3.light;
  if (type === 'income') {
    return {
      amount: positiveAmountColor(isDark),
      operator: scheme.tertiaryContainer,
      onOperator: scheme.onTertiaryContainer,
      equals: '#ECFFB8',
      onEquals: '#173300',
      muted: scheme.onSurfaceVariant,
    };
  }
  if (type === 'transfer') {
    return {
      amount: scheme.primary,
      operator: scheme.primaryContainer,
      onOperator: scheme.onPrimaryContainer,
      equals: '#D7E3FF',
      onEquals: '#001B3E',
      muted: scheme.onSurfaceVariant,
    };
  }
  if (type === 'adjustment') {
    return {
      amount: scheme.secondary,
      operator: scheme.secondaryContainer,
      onOperator: scheme.onSecondaryContainer,
      equals: '#D7E3FF',
      onEquals: '#001B3E',
      muted: scheme.onSurfaceVariant,
    };
  }
  return {
    amount: scheme.error,
    operator: scheme.errorContainer,
    onOperator: scheme.onErrorContainer,
    equals: '#ECFFB8',
    onEquals: '#173300',
    muted: scheme.onSurfaceVariant,
  };
}

const styles = StyleSheet.create({
  transitionHost: { flex: 1, backgroundColor: 'transparent' },
  transitionBackdrop: { ...StyleSheet.absoluteFill },
  screen: { flex: 1, overflow: 'hidden' },
  appbarTitle: { fontWeight: '700' },
  content: { flex: 1, paddingHorizontal: tokens.space.md, gap: tokens.space.xs, paddingBottom: 8 },
  typeTabs: {
    minHeight: 48,
    borderRadius: tokens.radius.lg,
    borderWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 3,
    padding: 3,
    overflow: 'hidden',
  },
  typeTabIcon: {
    width: 28,
    height: 28,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
  },
  typeTab: {
    flex: 1,
    minWidth: 0,
    borderRadius: tokens.radius.md,
    borderWidth: 1,
    overflow: 'hidden',
  },
  typeTabInner: {
    minHeight: 40,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 5,
    paddingHorizontal: 5,
  },
  typeTabLabel: { flexShrink: 1, minWidth: 0, fontWeight: '800' },
  panelTabs: {
    alignSelf: 'center',
    minHeight: 42,
    minWidth: 232,
    borderRadius: tokens.radius.pill,
    borderWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 3,
    padding: 3,
    overflow: 'hidden',
  },
  panelTab: {
    flex: 1,
    minWidth: 0,
    borderRadius: tokens.radius.pill,
    borderWidth: 1,
    overflow: 'hidden',
  },
  panelTabInner: {
    minHeight: 34,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
    paddingHorizontal: tokens.space.sm,
  },
  recordSwipeSurface: { flex: 1, minHeight: 0 },
  keypadPageContent: { flex: 1, gap: tokens.space.xs, minHeight: 0 },
  amountGlow: { flex: 1, minHeight: 136 },
  amountBlock: {
    flex: 1,
    minHeight: 136,
    justifyContent: 'center',
    alignItems: 'center',
    position: 'relative',
    borderWidth: 1,
    borderRadius: tokens.radius.lg,
    paddingHorizontal: tokens.space.md,
    paddingVertical: tokens.space.md,
  },
  amountValueRow: {
    width: '100%',
    minHeight: 58,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: tokens.space.sm,
    position: 'relative',
  },
  amountValueRowWithConversion: {
    transform: [{ translateY: -13 }],
  },
  amountText: {
    flexGrow: 1,
    flexShrink: 1,
    minWidth: 0,
    textAlign: 'right',
    fontFamily: tokens.font.nativeFamily.numeric,
    fontSize: 50,
    lineHeight: 58,
    fontWeight: '400',
    letterSpacing: 0,
    includeFontPadding: false,
  },
  amountCurrencyAnchor: {
    flexShrink: 0,
    justifyContent: 'center',
  },
  amountMetaStack: {
    position: 'absolute',
    left: tokens.space.md,
    right: tokens.space.md,
    bottom: 6,
    minHeight: 27,
    alignItems: 'center',
    justifyContent: 'flex-end',
    gap: 0,
  },
  amountMetaStackWithConversion: {
    bottom: 8,
    minHeight: 50,
  },
  expressionText: {
    width: '100%',
    minHeight: 12,
    textAlign: 'center',
    fontSize: 10.5,
    lineHeight: 12,
    fontWeight: '500',
    letterSpacing: 0,
  },
  amountWordsText: {
    width: '100%',
    minHeight: 14,
    textAlign: 'center',
    fontSize: 11,
    lineHeight: 14,
    fontStyle: 'italic',
    fontWeight: '400',
    letterSpacing: 0,
    includeFontPadding: false,
  },
  convertedAmountText: {
    width: '100%',
    minHeight: 22,
    textAlign: 'center',
    fontFamily: tokens.font.nativeFamily.numericMedium,
    fontSize: 17,
    lineHeight: 22,
    fontWeight: '800',
    letterSpacing: 0,
    includeFontPadding: false,
  },
  currencyChip: {
    borderRadius: tokens.radius.pill,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  currencyChipInner: {
    minWidth: 76,
    minHeight: 40,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 2,
    paddingHorizontal: tokens.space.sm,
  },
  currencyChipText: { fontWeight: '800' },
  currencyMenu: { maxHeight: 360, minWidth: 220, borderRadius: tokens.radius.lg },
  currencyMenuScroll: { maxHeight: 360 },
  selectorGrid: { flexDirection: 'row', gap: tokens.space.xs },
  selectorGlow: { flex: 1, minWidth: 0, minHeight: 68 },
  keypadSelectorRow: { minHeight: 68, borderRadius: tokens.radius.md },
  adjustmentSummary: {
    flex: 1,
    minHeight: 68,
    borderRadius: tokens.radius.lg,
    borderWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.sm,
    paddingHorizontal: tokens.space.md,
    paddingVertical: tokens.space.sm,
  },
  selectorIcon: {
    width: 36,
    height: 36,
    borderRadius: tokens.radius.pill,
    alignItems: 'center',
    justifyContent: 'center',
  },
  adjustmentCopy: { flex: 1, minWidth: 0, gap: 1 },
  adjustmentValue: { fontWeight: '800' },
  keypadFrame: { flexShrink: 0, position: 'relative' },
  recordPager: { flex: 1 },
  pagerPage: { flex: 1 },
  keypadPanel: { flex: 1, justifyContent: 'flex-start', paddingHorizontal: 2, paddingBottom: 2 },
  keypad: { flex: 1, gap: 5 },
  keypadCompact: { gap: 4 },
  keypadRow: { flex: 1, minHeight: 44, flexDirection: 'row', gap: 6 },
  keypadRowCompact: { minHeight: 40, gap: 5 },
  key: { flex: 1, minWidth: 0, borderRadius: tokens.radius.md, overflow: 'hidden' },
  keyCompact: { borderRadius: tokens.radius.md },
  keyInner: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  keyText: {
    fontFamily: tokens.font.nativeFamily.numericMedium,
    fontSize: 28,
    lineHeight: 32,
    fontWeight: '700',
    letterSpacing: 0,
    includeFontPadding: false,
  },
  keyTextCompact: { fontSize: 25, lineHeight: 29 },
  detailsPanel: { flex: 1 },
  detailsPanelPlaceholder: { flex: 1 },
  detailsContent: { gap: tokens.space.md, paddingBottom: 10 },
  receiptActions: { flexDirection: 'row', flexWrap: 'wrap', gap: tokens.space.sm },
  chargeRow: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingVertical: 8 },
  chargeLabel: { flex: 1.2 },
  chargeAmount: { flex: 0.9 },
});
