import type { Money } from '@1wallet/domain/money';
import {
  currencyDefinition,
  formatMoney,
  fromMinor,
  minorUnitsFor,
  normalizeCurrencyCode,
  toMinor,
} from '@1wallet/domain/money';
import type { Account, Category, Transaction, TransactionType } from '@1wallet/domain/types';
import {
  FUTURE_RULE_REF_PREFIX,
  forecastFutureRuleOccurrences,
  futureRuleInterestExternalRef,
  type FutureRuleOccurrence,
} from '@1wallet/ledger/rules/futureGeneration';
import {
  convertMoneyForDisplay,
  displayCurrency,
  enabledCurrencies,
  rateBetween,
} from '@1wallet/ledger/services';
import type { LedgerIndexes } from '@1wallet/ledger/services/indexes';
import { indexedAccountBalance } from '@1wallet/ledger/services/indexes';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { router } from 'expo-router';
import type { ReactNode } from 'react';
import { memo, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  PanResponder,
  Pressable,
  ScrollView,
  StyleSheet,
  View,
  type GestureResponderEvent,
  type LayoutChangeEvent,
} from 'react-native';
import {
  Chip,
  Divider,
  IconButton,
  Modal,
  Portal,
  ProgressBar,
  Surface,
  Text,
  TextInput,
  TouchableRipple,
  useTheme,
  type MD3Theme,
} from 'react-native-paper';
import { resolveCategoryIconVisual } from '../categoryIcons';
import { categoryBreadcrumb } from '../categoryTree';
import { PremiumTextInput, resolveAppIconName } from '../components/AppKit';
import { OptionListOverlay, type OptionListItem } from '../components/OptionListOverlay';
import { positiveAmountColor } from '../financeColors';
import { numericMediumFontFamily } from '../fonts';
import {
  iconSurfaceForThemeTone,
  iconTextColorForBackground,
  insetIconSurfaceForBackground,
  type IconSurfaceTone,
} from '../iconSystem';
import { transactionForRuleOccurrence } from '../plannedPayments/ruleActions';
import { formatRecordDateLabel } from '../recordDateTime';
import {
  transactionAmountDisplay,
  type TransactionAmountRowSide,
} from '../transactionDisplayAmounts';
import {
  INCOME_TRANSACTION_TYPES as INFLOW_TYPES,
  EXPENSE_TRANSACTION_TYPES as OUTFLOW_TYPES,
  TRANSFER_TRANSACTION_TYPES as TRANSFER_TYPES,
  transactionTypeIcon,
  transactionTypeIconTone,
  transactionTypeLabel,
} from '../transactionTypes';
import {
  HOME_WIDGET_REORDER_LONG_PRESS_DELAY_MS,
  HomeWidgetReorderProvider,
  HomeWidgetShell,
  WidgetDateFilterButton,
  WidgetDropdownButton,
  WidgetEmpty,
  useHomeWidgetReorderLongPress,
} from './HomeWidgetShell';
import {
  dateRangeForPreset,
  dateRangeSubtitle,
  filterTransactionsByPreset,
  timestampInRange,
} from './dateFilters';
import {
  BALANCE_HERO_DATE_PRESETS,
  BALANCE_HERO_DEFAULT_DATE_PRESET,
  CURRENCY_RATE_DATE_PRESETS,
  HOME_WIDGET_DATE_LABELS,
  HOME_WIDGET_META,
  type HomeWidgetDatePreset,
  type HomeWidgetId,
  type HomeWidgetSize,
} from './homeWidgetTypes';

type WidgetProps = {
  id: HomeWidgetId;
  size: HomeWidgetSize;
  datePreset: HomeWidgetDatePreset;
  onDatePresetChange: (preset: HomeWidgetDatePreset) => void;
  selectedAccountId?: string;
  onSelectedAccountChange?: (accountId: string | undefined) => void;
  onReorderLongPress?: () => void;
};
type WidgetShellProps = Omit<WidgetProps, 'id'>;
type LedgerStateForWidget = ReturnType<typeof useLedger>['state'];
type ExchangeRateForWidget = LedgerStateForWidget['exchangeRates'][number];
type CashCurrencyBreakdownItem = {
  amountMinor: number;
  currency: string;
  label: string;
};

const ACCOUNT_COLORS = tokens.color.accountPalette;
const WALLET_RECONCILE_REF_PREFIX = 'wallet-snapshot-reconcile:';
const CURRENCY_CHART_HEIGHT = 132;
const CURRENCY_AXIS_WIDTH = 52;
const CURRENCY_LINE_THICKNESS = 3;
const CURRENCY_DOT_SIZE = 9;
const HOME_PLANNED_LOOKAHEAD_MONTHS = 24;
const HOME_PLANNED_MAX_OCCURRENCES_PER_RULE = 240;
const ACCOUNT_LIABILITY_TYPES = new Set<Account['type']>(['credit_card', 'loan', 'overdraft']);
const ALL_ACCOUNTS_CACHE_KEY = '__all_accounts__';

type PlannedTransactionCache = {
  dayKey: string;
  results: Map<string, Transaction[]>;
  state: LedgerStateForWidget;
};

const plannedTransactionsCache = new WeakMap<LedgerIndexes, PlannedTransactionCache>();

function balanceForAccount(indexes: LedgerIndexes, account: Account): Money {
  return indexedAccountBalance(indexes, account);
}

function cashCurrencyBalancesForAccount(indexes: LedgerIndexes, account: Account): Money[] {
  if (account.type !== 'cash') return [];

  const balancesByCurrency = new Map<string, Money>();
  const addMoney = (money: Money | undefined, direction: -1 | 1) => {
    if (!money || money.amountMinor === 0) return;
    const currency = normalizeCurrencyCode(money.currency);
    const current = balancesByCurrency.get(currency) ?? { amountMinor: 0, currency };
    balancesByCurrency.set(currency, {
      amountMinor: current.amountMinor + money.amountMinor * direction,
      currency,
    });
  };

  addMoney(account.openingBalance, 1);

  for (const transaction of indexes.transactionsByAccountId.get(account.id) ?? []) {
    if (transaction.status === 'scheduled' || transaction.status === 'void') continue;

    if (transaction.accountId === account.id) {
      const direction = cashTransactionDirection(transaction);
      if (direction) addMoney(cashSourceTransactionMoney(transaction), direction);
    }

    if (TRANSFER_TYPES.has(transaction.type) && transaction.counterAccountId === account.id) {
      addMoney(cashDestinationTransferMoney(transaction, account), 1);
    }
  }

  return [...balancesByCurrency.values()]
    .filter((money) => money.amountMinor !== 0)
    .sort((left, right) => sortCashCurrencyBalance(account, left, right));
}

function cashTransactionDirection(transaction: Transaction): -1 | 1 | undefined {
  if (INFLOW_TYPES.has(transaction.type) || transaction.type === 'adjustment') return 1;
  if (OUTFLOW_TYPES.has(transaction.type) || TRANSFER_TYPES.has(transaction.type)) return -1;
  return undefined;
}

function cashSourceTransactionMoney(transaction: Transaction): Money {
  if (TRANSFER_TYPES.has(transaction.type)) return transaction.amount;
  const originalCurrency = transaction.originalAmount
    ? normalizeCurrencyCode(transaction.originalAmount.currency)
    : undefined;
  return originalCurrency && originalCurrency !== normalizeCurrencyCode(transaction.amount.currency)
    ? transaction.originalAmount!
    : transaction.amount;
}

function cashDestinationTransferMoney(transaction: Transaction, cashAccount: Account): Money {
  if (!transaction.counterAmount) return transaction.amount;
  const cashCurrency = normalizeCurrencyCode(cashAccount.currency);
  const sourceCurrency = normalizeCurrencyCode(transaction.amount.currency);
  const counterCurrency = normalizeCurrencyCode(transaction.counterAmount.currency);
  return counterCurrency === cashCurrency && sourceCurrency !== cashCurrency
    ? transaction.amount
    : transaction.counterAmount;
}

function cashCurrencyBreakdownForAccount(
  indexes: LedgerIndexes,
  account: Account,
  locale: string,
): CashCurrencyBreakdownItem[] {
  return cashCurrencyBalancesForAccount(indexes, account).map((money) => ({
    amountMinor: money.amountMinor,
    currency: money.currency,
    label: formatCashCurrencyBreakdownAmount(money, locale),
  }));
}

function cashCurrencyTotalForAccount(
  state: LedgerStateForWidget,
  indexes: LedgerIndexes,
  account: Account,
  currency: string,
): Money | undefined {
  const balances = cashCurrencyBalancesForAccount(indexes, account);
  if (!balances.length) return undefined;
  const normalizedCurrency = normalizeCurrencyCode(currency);
  return {
    amountMinor: balances.reduce(
      (sum, money) => sum + convertMoneyForDisplay(state, money, normalizedCurrency).amountMinor,
      0,
    ),
    currency: normalizedCurrency,
  };
}

function sortCashCurrencyBalance(account: Account, left: Money, right: Money): number {
  const accountCurrency = normalizeCurrencyCode(account.currency);
  const leftIsAccountCurrency = normalizeCurrencyCode(left.currency) === accountCurrency;
  const rightIsAccountCurrency = normalizeCurrencyCode(right.currency) === accountCurrency;
  if (leftIsAccountCurrency !== rightIsAccountCurrency) return leftIsAccountCurrency ? -1 : 1;
  return (
    Math.abs(right.amountMinor) - Math.abs(left.amountMinor) ||
    left.currency.localeCompare(right.currency)
  );
}

function formatCashCurrencyBreakdownAmount(money: Money, locale: string): string {
  try {
    return new Intl.NumberFormat(locale, {
      maximumFractionDigits: minorUnitsFor(money.currency),
      minimumFractionDigits: 0,
    }).format(fromMinor(money.amountMinor, money.currency));
  } catch {
    return formatMoney(money, locale);
  }
}

function cashCurrencyInlineLabel(item: CashCurrencyBreakdownItem): string {
  return `${currencyDefinition(item.currency).symbol} ${item.label}`;
}

function indexedTotalBalanceForHome(
  state: LedgerStateForWidget,
  indexes: LedgerIndexes,
  currency = displayCurrency(state),
): Money {
  const amountMinor = state.accounts.reduce((sum, account) => {
    if (account.isArchived) return sum;
    if (!account.includeInTotals) return sum;
    return (
      sum + convertMoneyForDisplay(state, balanceForAccount(indexes, account), currency).amountMinor
    );
  }, 0);
  return { amountMinor, currency };
}

function indexedNetWorthForHome(
  state: LedgerStateForWidget,
  indexes: LedgerIndexes,
  currency = displayCurrency(state),
): { total: Money; assets: Money; liabilities: Money } {
  let assets = 0;
  let liabilities = 0;
  for (const account of state.accounts) {
    if (account.isArchived) continue;
    if (!account.includeInNetWorth) continue;
    const amountMinor = convertMoneyForDisplay(
      state,
      balanceForAccount(indexes, account),
      currency,
    ).amountMinor;
    if (ACCOUNT_LIABILITY_TYPES.has(account.type)) liabilities += amountMinor;
    else assets += amountMinor;
  }
  return {
    assets: { amountMinor: assets, currency },
    liabilities: { amountMinor: liabilities, currency },
    total: { amountMinor: assets + liabilities, currency },
  };
}

function transactionsForSelectedAccount(
  indexes: LedgerIndexes,
  selectedAccountId?: string,
): Transaction[] {
  return selectedAccountId
    ? (indexes.transactionsByAccountId.get(selectedAccountId) ?? [])
    : indexes.allTransactionsSorted;
}

function plannedTransactionsForSelectedAccount(
  state: LedgerStateForWidget,
  indexes: LedgerIndexes,
  selectedAccountId?: string,
): Transaction[] {
  const cacheKey = selectedAccountId ?? ALL_ACCOUNTS_CACHE_KEY;
  const dayKey = startOfToday().toISOString().slice(0, 10);
  const cached = plannedTransactionsCache.get(indexes);
  if (cached?.state === state && cached.dayKey === dayKey) {
    const cachedResult = cached.results.get(cacheKey);
    if (cachedResult) return cachedResult;
  }

  const records = new Map<string, Transaction>();
  const rawScheduled = selectedAccountId
    ? (indexes.scheduledTransactionsByAccountId.get(selectedAccountId) ?? [])
    : indexes.scheduledTransactions;

  for (const transaction of rawScheduled) {
    if (isLinkedFutureInterestTransaction(transaction)) continue;
    const normalized = homeTransactionFromScheduled(state, indexes, transaction);
    records.set(plannedTransactionKey(normalized), normalized);
  }

  const ruleById = new Map(
    (state.preferences.futureGenerationRules ?? []).map((rule) => [rule.id, rule]),
  );
  const forecastEnd = addMonths(startOfToday(), HOME_PLANNED_LOOKAHEAD_MONTHS);
  for (const occurrence of forecastFutureRuleOccurrences(state, {
    from: startOfToday(),
    to: forecastEnd,
    maxOccurrencesPerRule: HOME_PLANNED_MAX_OCCURRENCES_PER_RULE,
  })) {
    if (!occurrenceMatchesAccount(occurrence, selectedAccountId)) continue;
    const rule = ruleById.get(occurrence.ruleId);
    if (!rule) continue;
    const existing = transactionForRuleOccurrence(state, rule, occurrence.dueOn);
    if (existing && existing.status !== 'scheduled') {
      records.delete(occurrence.externalRef);
      records.delete(existing.id);
      continue;
    }
    const transaction = homeTransactionFromOccurrence(state, indexes, occurrence, existing);
    records.delete(existing?.id ?? '');
    records.set(plannedTransactionKey(transaction), transaction);
  }

  const result = Array.from(records.values())
    .filter((transaction) => transaction.status === 'scheduled')
    .filter((transaction) => transactionMatchesAccount(transaction, selectedAccountId))
    .sort((left, right) => left.occurredAt.localeCompare(right.occurredAt));
  const nextCache =
    cached?.state === state && cached.dayKey === dayKey
      ? cached
      : { dayKey, results: new Map<string, Transaction[]>(), state };
  nextCache.results.set(cacheKey, result);
  plannedTransactionsCache.set(indexes, nextCache);
  return result;
}

function plannedTransactionKey(transaction: Transaction): string {
  return transaction.externalRef ?? transaction.id;
}

function isLinkedFutureInterestTransaction(transaction: Transaction): boolean {
  return Boolean(
    transaction.externalRef?.startsWith(`${FUTURE_RULE_REF_PREFIX}:`) &&
    transaction.externalRef.endsWith(':interest'),
  );
}

function occurrenceMatchesAccount(
  occurrence: FutureRuleOccurrence,
  selectedAccountId?: string,
): boolean {
  return (
    !selectedAccountId ||
    occurrence.accountId === selectedAccountId ||
    occurrence.counterAccountId === selectedAccountId
  );
}

function linkedScheduledFutureInterestTransaction(
  indexes: LedgerIndexes,
  transaction: Transaction,
): Transaction | undefined {
  if (!transaction.externalRef) return undefined;
  const interestRef = futureRuleInterestExternalRef(transaction.externalRef);
  const interest = indexes.transactionsByExternalRef.get(interestRef);
  return interest?.status === 'scheduled' ? interest : undefined;
}

function homeTransactionFromScheduled(
  state: LedgerStateForWidget,
  indexes: LedgerIndexes,
  transaction: Transaction,
): Transaction {
  const interest = linkedScheduledFutureInterestTransaction(indexes, transaction);
  if (!interest) return transaction;
  const amount = {
    amountMinor: transaction.amount.amountMinor + interest.amount.amountMinor,
    currency: transaction.amount.currency,
  };
  return {
    ...transaction,
    amount,
    baseAmount: convertMoneyForDisplay(state, amount, state.preferences.baseCurrency),
    updatedAt:
      interest.updatedAt > transaction.updatedAt ? interest.updatedAt : transaction.updatedAt,
  };
}

function homeTransactionFromOccurrence(
  state: LedgerStateForWidget,
  indexes: LedgerIndexes,
  occurrence: FutureRuleOccurrence,
  existing?: Transaction,
): Transaction {
  const interest = existing
    ? linkedScheduledFutureInterestTransaction(indexes, existing)
    : undefined;
  const amount = {
    amountMinor: existing
      ? existing.amount.amountMinor + (interest?.amount.amountMinor ?? 0)
      : occurrence.amountMinor,
    currency: existing?.amount.currency ?? occurrence.currency,
  };
  const counterAmount =
    existing?.counterAmount ??
    (occurrence.counterAmountMinor !== undefined
      ? {
          amountMinor: occurrence.counterAmountMinor,
          currency: occurrence.counterCurrency ?? occurrence.currency,
        }
      : undefined);
  const occurredAt = existing?.occurredAt ?? occurrence.occurredAt;
  return {
    id: existing?.id ?? `home-forecast:${occurrence.externalRef}`,
    userId: existing?.userId ?? state.userId,
    type: existing?.type ?? occurrence.type,
    status: 'scheduled',
    source: existing?.source ?? 'rule',
    accountId: existing?.accountId ?? occurrence.accountId,
    counterAccountId: existing?.counterAccountId ?? occurrence.counterAccountId,
    amount,
    baseAmount: convertMoneyForDisplay(state, amount, state.preferences.baseCurrency),
    fxRate: existing?.fxRate,
    originalAmount: existing?.originalAmount,
    originalFxRate: existing?.originalFxRate,
    counterAmount,
    counterFxRate: existing?.counterFxRate,
    categoryId: existing?.categoryId ?? occurrence.categoryId,
    merchantId: existing?.merchantId,
    occurredAt,
    locationLabel: existing?.locationLabel,
    paymentMethod: existing?.paymentMethod ?? occurrence.paymentMethod,
    notes: existing?.notes ?? occurrence.notes,
    attachments: existing?.attachments,
    tags: existing?.tags ?? occurrence.tags,
    personId: existing?.personId,
    projectId: existing?.projectId,
    tripId: existing?.tripId,
    isReimbursable: existing?.isReimbursable ?? false,
    isTaxDeductible: existing?.isTaxDeductible ?? false,
    isExcludedFromReports: existing?.isExcludedFromReports ?? false,
    originalTransactionId: existing?.originalTransactionId,
    recurringTemplateId: existing?.recurringTemplateId ?? occurrence.ruleId,
    captureCandidateId: existing?.captureCandidateId,
    sourceConfidence: existing?.sourceConfidence,
    externalRef: existing?.externalRef ?? occurrence.externalRef,
    createdAt: existing?.createdAt ?? occurredAt,
    updatedAt: existing?.updatedAt ?? occurredAt,
  };
}

function plannedInflowBaseAmountMinor(
  state: LedgerStateForWidget,
  transaction: Transaction,
  selectedAccountId?: string,
): number {
  if (!selectedAccountId) {
    return INFLOW_TYPES.has(transaction.type) ? Math.abs(transaction.baseAmount.amountMinor) : 0;
  }
  if (transaction.accountId === selectedAccountId) {
    return INFLOW_TYPES.has(transaction.type) ? Math.abs(transaction.baseAmount.amountMinor) : 0;
  }
  if (transaction.counterAccountId === selectedAccountId && TRANSFER_TYPES.has(transaction.type)) {
    return Math.abs(moneyToBaseMinor(state, transaction.counterAmount ?? transaction.amount));
  }
  return 0;
}

function plannedOutflowBaseAmountMinor(
  transaction: Transaction,
  selectedAccountId?: string,
): number {
  if (!selectedAccountId) {
    return OUTFLOW_TYPES.has(transaction.type) || TRANSFER_TYPES.has(transaction.type)
      ? Math.abs(transaction.baseAmount.amountMinor)
      : 0;
  }
  if (transaction.accountId !== selectedAccountId) return 0;
  return OUTFLOW_TYPES.has(transaction.type) || TRANSFER_TYPES.has(transaction.type)
    ? Math.abs(transaction.baseAmount.amountMinor)
    : 0;
}

function moneyToBaseMinor(state: LedgerStateForWidget, money: Money): number {
  return convertMoneyForDisplay(state, money, state.preferences.baseCurrency).amountMinor;
}

function cashflowForPreset(
  state: ReturnType<typeof useLedger>['state'],
  preset: HomeWidgetDatePreset,
  selectedAccountId?: string,
  currency = displayCurrency(state),
  indexes?: LedgerIndexes,
): { income: Money; expense: Money; net: Money } {
  const base = state.preferences.baseCurrency;
  const transactions = reportableTransactions(state, preset, selectedAccountId, indexes);
  let income = 0;
  let expense = 0;
  for (const transaction of transactions) {
    if (INFLOW_TYPES.has(transaction.type)) income += transaction.baseAmount.amountMinor;
    if (OUTFLOW_TYPES.has(transaction.type)) expense += transaction.baseAmount.amountMinor;
  }
  const incomeMoney = { amountMinor: income, currency: base };
  const expenseMoney = { amountMinor: expense, currency: base };
  return {
    income: convertMoneyForDisplay(state, incomeMoney, currency),
    expense: convertMoneyForDisplay(state, expenseMoney, currency),
    net: convertMoneyForDisplay(state, { amountMinor: income - expense, currency: base }, currency),
  };
}

export function HomeWidgetRenderer({
  id,
  size,
  datePreset,
  onDatePresetChange,
  selectedAccountId,
  onSelectedAccountChange,
  onReorderLongPress,
}: WidgetProps) {
  const props = {
    size,
    datePreset,
    onDatePresetChange,
    selectedAccountId,
    onSelectedAccountChange,
  };
  let widget: ReactNode;
  switch (id) {
    case 'balanceHero':
      widget = <BalanceHeroWidget {...props} />;
      break;
    case 'accountGrid':
      widget = <AccountGridWidget {...props} />;
      break;
    case 'summaryTiles':
      widget = <SummaryTilesWidget {...props} />;
      break;
    case 'recentRecords':
      widget = <RecentRecordsWidget {...props} />;
      break;
    case 'upcomingScheduled':
      widget = <UpcomingScheduledWidget {...props} />;
      break;
    case 'dueNow':
      widget = <DueNowWidget {...props} />;
      break;
    case 'emiTracker':
      widget = <EmiTrackerWidget {...props} />;
      break;
    case 'cardDebt':
      widget = <CardDebtWidget {...props} />;
      break;
    case 'accountGroups':
      widget = <AccountGroupsWidget {...props} />;
      break;
    case 'reviewQueue':
      widget = <ReviewQueueWidget {...props} />;
      break;
    case 'automationHealth':
      widget = <AutomationHealthWidget {...props} />;
      break;
    case 'cashflowForecast':
      widget = <CashflowForecastWidget {...props} />;
      break;
    case 'billWatch':
      widget = <BillWatchWidget {...props} />;
      break;
    case 'cardPaymentPlan':
      widget = <CardPaymentPlanWidget {...props} />;
      break;
    case 'loanPayoff':
      widget = <LoanPayoffWidget {...props} />;
      break;
    case 'savingsRunway':
      widget = <SavingsRunwayWidget {...props} />;
      break;
    case 'cashflowBook':
      widget = <CashflowBookWidget {...props} />;
      break;
    case 'balanceTrend':
      widget = <BalanceTrendWidget {...props} />;
      break;
    case 'topCategories':
      widget = <TopCategoriesWidget {...props} />;
      break;
    case 'incomeMix':
      widget = <IncomeMixWidget {...props} />;
      break;
    case 'currencyValues':
      widget = <CurrencyValuesWidget {...props} />;
      break;
    case 'budgetPressure':
      widget = <BudgetPressureWidget {...props} />;
      break;
    case 'goalProgress':
      widget = <GoalProgressWidget {...props} />;
      break;
    case 'currencyExposure':
      widget = <CurrencyExposureWidget {...props} />;
      break;
    default:
      widget = null;
  }

  return (
    <HomeWidgetReorderProvider onLongPress={onReorderLongPress}>{widget}</HomeWidgetReorderProvider>
  );
}

function BalanceHeroWidget({
  size,
  datePreset,
  onDatePresetChange,
  selectedAccountId,
}: WidgetShellProps) {
  const theme = useTheme();
  const onReorderLongPress = useHomeWidgetReorderLongPress();
  const { state, indexes, selectors, setDisplayCurrency } = useLedger();
  const viewCurrency = selectors.displayCurrency(state);
  const heroDatePreset = BALANCE_HERO_DATE_PRESETS.includes(datePreset)
    ? datePreset
    : BALANCE_HERO_DEFAULT_DATE_PRESET;
  const selectedAccount = useMemo(
    () => (selectedAccountId ? indexes.accountsById.get(selectedAccountId) : undefined),
    [indexes.accountsById, selectedAccountId],
  );
  const enabledCurrencyCodes = useMemo(() => enabledCurrencies(state), [state]);
  const total = useMemo(() => {
    if (!selectedAccount) return indexedTotalBalanceForHome(state, indexes, viewCurrency);
    if (selectedAccount.type === 'cash') {
      return (
        cashCurrencyTotalForAccount(state, indexes, selectedAccount, viewCurrency) ??
        selectors.convertMoneyForDisplay(
          state,
          balanceForAccount(indexes, selectedAccount),
          viewCurrency,
        )
      );
    }
    return selectors.convertMoneyForDisplay(
      state,
      balanceForAccount(indexes, selectedAccount),
      viewCurrency,
    );
  }, [indexes, selectedAccount, selectors, state, viewCurrency]);
  const cashCurrencyBreakdown = useMemo(
    () =>
      selectedAccount?.type === 'cash'
        ? cashCurrencyBreakdownForAccount(indexes, selectedAccount, state.preferences.locale)
        : [],
    [indexes, selectedAccount, state],
  );
  const cashCurrencyBreakdownLabel = useMemo(
    () => cashCurrencyBreakdown.map(cashCurrencyInlineLabel).join(' | '),
    [cashCurrencyBreakdown],
  );
  const flow = useMemo(
    () => cashflowForPreset(state, heroDatePreset, selectedAccountId, viewCurrency, indexes),
    [heroDatePreset, indexes, selectedAccountId, state, viewCurrency],
  );

  return (
    <Surface
      style={[
        styles.hero,
        {
          backgroundColor: theme.colors.elevation.level1,
          borderColor: theme.colors.outlineVariant,
        },
      ]}
      elevation={1}
    >
      <View style={styles.heroHeader}>
        <View style={styles.heroCopy}>
          <BalanceHeroTitle onLongPress={onReorderLongPress}>
            <Text
              variant="labelLarge"
              style={[styles.mutedText, { color: theme.colors.onSurfaceVariant }]}
            >
              {selectedAccount ? selectedAccount.name : 'Balance'}
            </Text>
          </BalanceHeroTitle>
          <Text
            variant={size === 'compact' ? 'headlineMedium' : 'displaySmall'}
            style={styles.heroAmount}
            numberOfLines={1}
            adjustsFontSizeToFit
          >
            {formatMoney(total, state.preferences.locale)}
          </Text>
          {cashCurrencyBreakdownLabel ? (
            <Text
              variant="labelLarge"
              numberOfLines={1}
              adjustsFontSizeToFit
              minimumFontScale={0.72}
              style={[styles.heroCashBreakdownText, { color: theme.colors.onSurfaceVariant }]}
            >
              {cashCurrencyBreakdownLabel}
            </Text>
          ) : null}
        </View>
        <View style={styles.heroActions}>
          <WidgetDateFilterButton
            value={heroDatePreset}
            onChange={onDatePresetChange}
            presets={BALANCE_HERO_DATE_PRESETS}
            buttonLabel={compactBalanceDateLabel(heroDatePreset)}
            menuWidth={132}
          />
          <BalanceCurrencyButton
            value={viewCurrency}
            currencies={enabledCurrencyCodes}
            onChange={(currency) => void setDisplayCurrency(currency)}
          />
        </View>
      </View>
      <View style={styles.metricRow}>
        <MoneyMetric
          label="Income"
          value={flow.income}
          locale={state.preferences.locale}
          tone="positive"
        />
        <MoneyMetric
          label="Expense"
          value={flow.expense}
          locale={state.preferences.locale}
          tone="danger"
        />
      </View>
    </Surface>
  );
}

function BalanceHeroTitle({
  children,
  onLongPress,
}: {
  children: ReactNode;
  onLongPress?: () => void;
}) {
  if (!onLongPress) return <>{children}</>;
  return (
    <Pressable
      onLongPress={onLongPress}
      delayLongPress={HOME_WIDGET_REORDER_LONG_PRESS_DELAY_MS}
      hitSlop={6}
      style={styles.heroTitlePressArea}
    >
      {children}
    </Pressable>
  );
}

function compactBalanceDateLabel(preset: HomeWidgetDatePreset): string {
  switch (preset) {
    case 'today':
      return '1 Day';
    case 'thisWeek':
      return '1 Week';
    case 'thisMonth':
      return '1 Month';
    case 'thisYear':
      return '1 Year';
    default:
      return HOME_WIDGET_DATE_LABELS[preset];
  }
}

function BalanceCurrencyButton({
  value,
  currencies,
  onChange,
}: {
  value: string;
  currencies: string[];
  onChange: (currency: string) => void;
}) {
  const options = useMemo(
    () => uniqueCurrencyCodes(currencies).map(currencyOptionForCode),
    [currencies],
  );

  return (
    <WidgetDropdownButton
      value={value}
      label={value}
      icon={resolveAppIconName(currencyDefinition(value).icon, 'currency-usd')}
      items={options.map((option) => ({
        value: option.value,
        label: option.value,
        icon: option.icon,
        disabled: option.disabled,
      }))}
      menuWidth={104}
      onSelect={onChange}
    />
  );
}

function AccountGridWidget({ size, selectedAccountId, onSelectedAccountChange }: WidgetShellProps) {
  const theme = useTheme();
  const { state, indexes } = useLedger();
  const [instantSelectedAccountId, setInstantSelectedAccountId] = useState(selectedAccountId);
  const instantSelectedAccountIdRef = useRef(selectedAccountId);
  const accounts = useMemo(
    () =>
      state.accounts
        .filter((account) => !account.isArchived && account.showOnHome)
        .sort(
          (left, right) => left.sortOrder - right.sortOrder || left.name.localeCompare(right.name),
        ),
    [state.accounts],
  );
  const locale = state.preferences.locale;
  const viewCurrency = displayCurrency(state);
  const dimmedTileColor = theme.colors.surfaceVariant;
  const dimmedTileContentColor = theme.colors.onSurfaceVariant;
  const dimmedIconBackgroundColor = theme.colors.surfaceDisabled;
  const dimmedIconColor = theme.colors.onSurfaceDisabled;

  useEffect(() => {
    instantSelectedAccountIdRef.current = selectedAccountId;
    setInstantSelectedAccountId(selectedAccountId);
  }, [selectedAccountId]);

  const handleAccountPress = useCallback(
    (accountId: string) => {
      const nextSelectedAccountId =
        accountId === instantSelectedAccountIdRef.current ? undefined : accountId;
      instantSelectedAccountIdRef.current = nextSelectedAccountId;
      setInstantSelectedAccountId(nextSelectedAccountId);
      requestAnimationFrame(() => onSelectedAccountChange?.(nextSelectedAccountId));
    },
    [onSelectedAccountChange],
  );

  const accountTileModels = useMemo(
    () =>
      accounts.map((account, index) => {
        const color =
          account.color ?? ACCOUNT_COLORS[index % ACCOUNT_COLORS.length] ?? tokens.color.md3Primary;
        const balance = balanceForAccount(indexes, account);
        const cashDisplayBalance =
          account.type === 'cash'
            ? cashCurrencyTotalForAccount(state, indexes, account, viewCurrency)
            : undefined;
        const convertedBalance = cashDisplayBalance
          ? undefined
          : normalizeCurrencyCode(balance.currency) !== normalizeCurrencyCode(viewCurrency) &&
              realRateBetween(state, balance.currency, viewCurrency)
            ? convertMoneyForDisplay(state, balance, viewCurrency)
            : undefined;
        const cashCurrencyBreakdown = cashCurrencyBreakdownForAccount(indexes, account, locale);
        const selected = account.id === instantSelectedAccountId;
        const dimmed = Boolean(instantSelectedAccountId && !selected);
        const tileColor = dimmed ? dimmedTileColor : color;
        const contentColor = dimmed
          ? dimmedTileContentColor
          : iconTextColorForBackground(tileColor);
        const iconSurface = dimmed
          ? { backgroundColor: dimmedIconBackgroundColor, iconColor: dimmedIconColor }
          : insetIconSurfaceForBackground(tileColor);

        return {
          accountId: account.id,
          accountName: account.name,
          accountIcon: resolveAppIconName(account.icon, iconForAccount(account.type)),
          balanceLabel: formatMoney(cashDisplayBalance ?? balance, locale),
          cashCurrencyBreakdown: cashCurrencyBreakdown.length ? cashCurrencyBreakdown : undefined,
          color: tileColor,
          compact: size === 'compact',
          contentColor,
          iconBackgroundColor: iconSurface.backgroundColor,
          iconColor: iconSurface.iconColor,
          convertedBalanceLabel: convertedBalance
            ? formatMoney(convertedBalance, locale)
            : undefined,
          dimmed,
          selected,
        };
      }),
    [
      accounts,
      dimmedIconBackgroundColor,
      dimmedIconColor,
      dimmedTileColor,
      dimmedTileContentColor,
      indexes,
      instantSelectedAccountId,
      locale,
      size,
      state,
      viewCurrency,
    ],
  );
  const selectedHomeAccount = useMemo(
    () => accounts.find((account) => account.id === instantSelectedAccountId),
    [accounts, instantSelectedAccountId],
  );
  const openAccountManagement = useCallback(() => {
    if (selectedHomeAccount) {
      router.push({ pathname: '/account/[id]', params: { id: selectedHomeAccount.id } });
      return;
    }
    router.push('/(tabs)/accounts' as never);
  }, [selectedHomeAccount]);

  return (
    <HomeWidgetShell
      {...HOME_WIDGET_META.accountGrid}
      size={size}
      subtitle={instantSelectedAccountId ? 'Tap selected account again to show all' : undefined}
      actionLabel="Manage"
      onAction={openAccountManagement}
    >
      {accounts.length === 0 ? (
        <WidgetEmpty text="No accounts yet. Add cash, bank, wallet, card, or loan accounts." />
      ) : (
        <View style={styles.accountGrid}>
          {accountTileModels.map((account) => (
            <MemoizedAccountTile
              key={account.accountId}
              {...account}
              onPressAccount={handleAccountPress}
            />
          ))}
        </View>
      )}
      <TouchableRipple
        style={[styles.addAccount, { borderColor: theme.colors.outlineVariant }]}
        onPress={() => router.push('/account/new' as never)}
        borderless
      >
        <View style={styles.addAccountInner}>
          <MaterialCommunityIcons name="plus" size={16} color={theme.colors.primary} />
          <Text
            variant="labelMedium"
            style={[styles.mutedText, { color: theme.colors.onSurfaceVariant }]}
          >
            Add account
          </Text>
        </View>
      </TouchableRipple>
    </HomeWidgetShell>
  );
}

function SummaryTilesWidget({
  size,
  datePreset,
  onDatePresetChange,
  selectedAccountId,
}: WidgetShellProps) {
  const { state, indexes, selectors } = useLedger();
  const viewCurrency = selectors.displayCurrency(state);
  const selectedAccount = useMemo(
    () => (selectedAccountId ? indexes.accountsById.get(selectedAccountId) : undefined),
    [indexes.accountsById, selectedAccountId],
  );
  const netWorth = useMemo(
    () => indexedNetWorthForHome(state, indexes, viewCurrency),
    [indexes, state, viewCurrency],
  );
  const scheduledExpense = useMemo(
    () =>
      filterTransactionsByPreset(
        plannedTransactionsForSelectedAccount(state, indexes, selectedAccountId),
        datePreset,
      )
        .filter((transaction) => transactionMatchesAccount(transaction, selectedAccountId))
        .reduce(
          (sum, transaction) => sum + plannedOutflowBaseAmountMinor(transaction, selectedAccountId),
          0,
        ),
    [datePreset, indexes, selectedAccountId, state],
  );
  const debtMetric = useMemo(
    () => ({
      amountMinor: Math.abs(Math.min(0, netWorth.liabilities.amountMinor)),
      currency: netWorth.liabilities.currency,
    }),
    [netWorth.liabilities.amountMinor, netWorth.liabilities.currency],
  );
  const balanceMetric = useMemo(
    () =>
      selectedAccount
        ? selectors.convertMoneyForDisplay(
            state,
            balanceForAccount(indexes, selectedAccount),
            viewCurrency,
          )
        : netWorth.total,
    [indexes, netWorth.total, selectedAccount, selectors, state, viewCurrency],
  );

  return (
    <HomeWidgetShell
      {...HOME_WIDGET_META.summaryTiles}
      size={size}
      datePreset={datePreset}
      onDatePresetChange={onDatePresetChange}
    >
      <View style={styles.summaryGrid}>
        <SummaryTile
          label="Planned"
          value={formatMoney(
            selectors.convertMoneyForDisplay(
              state,
              { amountMinor: scheduledExpense, currency: state.preferences.baseCurrency },
              viewCurrency,
            ),
            state.preferences.locale,
          )}
          icon="calendar-clock-outline"
        />
        <SummaryTile
          label="Debts"
          value={formatMoney(debtMetric, state.preferences.locale)}
          icon="credit-card-clock-outline"
          tone="danger"
        />
        <SummaryTile
          label={selectedAccount ? 'Account' : 'Net worth'}
          value={formatMoney(balanceMetric, state.preferences.locale)}
          icon={selectedAccount ? 'wallet-outline' : 'scale-balance'}
        />
      </View>
    </HomeWidgetShell>
  );
}

function RecentRecordsWidget({
  size,
  datePreset,
  onDatePresetChange,
  selectedAccountId,
}: WidgetShellProps) {
  const { indexes } = useLedger();
  const records = useMemo(
    () =>
      filterTransactionsByPreset(indexes.allTransactionsSorted, datePreset)
        .filter((item) => transactionMatchesAccount(item, selectedAccountId))
        .filter((item) => item.status !== 'scheduled')
        .filter((item) => item.status !== 'void')
        .filter((item) => !item.externalRef?.startsWith(WALLET_RECONCILE_REF_PREFIX))
        .slice(0, 5),
    [datePreset, indexes.allTransactionsSorted, selectedAccountId],
  );

  return (
    <HomeWidgetShell
      {...HOME_WIDGET_META.recentRecords}
      size={size}
      datePreset={datePreset}
      onDatePresetChange={onDatePresetChange}
      actionLabel="View"
      onAction={() => router.push('/(tabs)/transactions' as never)}
    >
      {records.length === 0 ? (
        <WidgetEmpty text="No records yet. Add one to start the ledger." />
      ) : (
        <TransactionList records={records} selectedAccountId={selectedAccountId} />
      )}
    </HomeWidgetShell>
  );
}

function UpcomingScheduledWidget({
  size,
  datePreset,
  onDatePresetChange,
  selectedAccountId,
}: WidgetShellProps) {
  const { state, indexes } = useLedger();
  const records = useMemo(
    () =>
      filterTransactionsByPreset(
        plannedTransactionsForSelectedAccount(state, indexes, selectedAccountId),
        datePreset,
      )
        .filter((item) => transactionMatchesAccount(item, selectedAccountId))
        .slice(0, 5),
    [datePreset, indexes, selectedAccountId, state],
  );

  return (
    <HomeWidgetShell
      {...HOME_WIDGET_META.upcomingScheduled}
      size={size}
      datePreset={datePreset}
      onDatePresetChange={onDatePresetChange}
      actionLabel="Open"
      onAction={() => router.push('/recurring' as never)}
    >
      {records.length === 0 ? (
        <WidgetEmpty text="No planned payments yet." />
      ) : (
        <TransactionList records={records} scheduled selectedAccountId={selectedAccountId} />
      )}
    </HomeWidgetShell>
  );
}

function DueNowWidget({
  size,
  datePreset,
  onDatePresetChange,
  selectedAccountId,
}: WidgetShellProps) {
  const { state, indexes, selectors } = useLedger();
  const viewCurrency = selectors.displayCurrency(state);
  const dueSummary = useMemo(() => {
    const now = new Date();
    const endOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
    const records = plannedTransactionsForSelectedAccount(state, indexes, selectedAccountId)
      .filter((item) => transactionMatchesAccount(item, selectedAccountId))
      .filter((item) => new Date(item.occurredAt) < endOfToday)
      .slice();
    const overdue = records.filter((item) => dayOffsetFromToday(item.occurredAt) < 0).length;
    const amountMinor = records.reduce(
      (sum, item) =>
        sum +
        selectors.convertMoneyForDisplay(
          state,
          {
            amountMinor: Math.abs(item.baseAmount.amountMinor),
            currency: item.baseAmount.currency,
          },
          viewCurrency,
        ).amountMinor,
      0,
    );
    return { amountMinor, overdue, records };
  }, [indexes, selectedAccountId, selectors, state, viewCurrency]);

  return (
    <HomeWidgetShell
      {...HOME_WIDGET_META.dueNow}
      size={size}
      datePreset={datePreset}
      onDatePresetChange={onDatePresetChange}
      actionLabel="Open"
      onAction={() => router.push('/recurring' as never)}
    >
      <View style={styles.summaryGrid}>
        <SummaryTile
          label="Due"
          value={String(dueSummary.records.length)}
          icon="calendar-alert"
          tone={dueSummary.records.length ? 'warning' : 'default'}
        />
        <SummaryTile
          label="Amount"
          value={formatMoney(
            { amountMinor: dueSummary.amountMinor, currency: viewCurrency },
            state.preferences.locale,
          )}
          icon="calendar-clock-outline"
          tone={dueSummary.amountMinor ? 'warning' : 'default'}
        />
        <SummaryTile
          label="Overdue"
          value={String(dueSummary.overdue)}
          icon="alert-circle-outline"
          tone={dueSummary.overdue ? 'danger' : 'default'}
        />
      </View>
      {dueSummary.records.length === 0 ? (
        <WidgetEmpty text="No bills, cards, or EMIs due today." />
      ) : (
        <TransactionList
          records={dueSummary.records.slice(0, 3)}
          scheduled
          selectedAccountId={selectedAccountId}
        />
      )}
    </HomeWidgetShell>
  );
}

function EmiTrackerWidget({
  size,
  datePreset,
  onDatePresetChange,
  selectedAccountId,
}: WidgetShellProps) {
  const { state, indexes, selectors } = useLedger();
  const viewCurrency = selectors.displayCurrency(state);
  const now = new Date();
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
  const monthEnd = new Date(now.getFullYear(), now.getMonth() + 1, 1);
  const scheduledEmis = plannedTransactionsForSelectedAccount(state, indexes, selectedAccountId)
    .filter((item) => item.type === 'loan_repayment')
    .filter((item) => transactionMatchesAccount(item, selectedAccountId))
    .slice();
  const nextEmi = scheduledEmis.find((item) => new Date(item.occurredAt) >= startOfToday());
  const monthlyAmountMinor = scheduledEmis
    .filter((item) => {
      const due = new Date(item.occurredAt);
      return due >= monthStart && due < monthEnd;
    })
    .reduce(
      (sum, item) =>
        sum +
        selectors.convertMoneyForDisplay(
          state,
          {
            amountMinor: Math.abs(item.baseAmount.amountMinor),
            currency: item.baseAmount.currency,
          },
          viewCurrency,
        ).amountMinor,
      0,
    );

  return (
    <HomeWidgetShell
      {...HOME_WIDGET_META.emiTracker}
      size={size}
      datePreset={datePreset}
      onDatePresetChange={onDatePresetChange}
      actionLabel="Loans"
      onAction={() => router.push('/loans' as never)}
    >
      <View style={styles.twoColumnMetrics}>
        <SummaryTile
          label="Planned EMIs"
          value={String(scheduledEmis.length)}
          icon="calendar-sync-outline"
        />
        <SummaryTile
          label="This month"
          value={formatMoney(
            { amountMinor: monthlyAmountMinor, currency: viewCurrency },
            state.preferences.locale,
          )}
          icon="bank-transfer-out"
          tone={monthlyAmountMinor ? 'warning' : 'default'}
        />
      </View>
      {nextEmi ? (
        <InfoLine
          icon="calendar-clock-outline"
          label="Next EMI"
          value={formatMoney(nextEmi.amount, state.preferences.locale)}
          subvalue={`${formatRelativeTransactionDate(nextEmi.occurredAt)} · ${transactionTypeLabel(nextEmi.type)}`}
          danger={dayOffsetFromToday(nextEmi.occurredAt) < 0}
          positive={dayOffsetFromToday(nextEmi.occurredAt) > 7}
        />
      ) : (
        <WidgetEmpty text="No loan EMI reminders scheduled." />
      )}
    </HomeWidgetShell>
  );
}

function CardDebtWidget({
  size,
  datePreset,
  onDatePresetChange,
  selectedAccountId,
}: WidgetShellProps) {
  const { state, indexes, selectors } = useLedger();
  const viewCurrency = selectors.displayCurrency(state);
  const cards = state.accounts.filter(
    (account) =>
      !account.isArchived &&
      account.includeInTotals &&
      account.type === 'credit_card' &&
      (!selectedAccountId || account.id === selectedAccountId),
  );
  const rows = cards
    .map((account) => {
      const balance = balanceForAccount(indexes, account);
      return {
        account,
        balance,
        displayBalance: selectors.convertMoneyForDisplay(state, balance, viewCurrency),
      };
    })
    .sort((left, right) => left.displayBalance.amountMinor - right.displayBalance.amountMinor);
  const totalDebt = rows.reduce(
    (sum, row) => sum + Math.abs(Math.min(0, row.displayBalance.amountMinor)),
    0,
  );
  const highest = rows.find((row) => row.displayBalance.amountMinor < 0);
  const highestAmount = highest
    ? {
        amountMinor: Math.abs(Math.min(0, highest.displayBalance.amountMinor)),
        currency: highest.displayBalance.currency,
      }
    : undefined;

  return (
    <HomeWidgetShell
      {...HOME_WIDGET_META.cardDebt}
      size={size}
      datePreset={datePreset}
      onDatePresetChange={onDatePresetChange}
      actionLabel="Cards"
      onAction={() => router.push('/cards' as never)}
    >
      <View style={styles.twoColumnMetrics}>
        <SummaryTile
          label="Total cards"
          value={formatMoney(
            { amountMinor: totalDebt, currency: viewCurrency },
            state.preferences.locale,
          )}
          icon="credit-card-outline"
          tone="danger"
        />
        <SummaryTile label="Cards" value={String(cards.length)} icon="card-multiple-outline" />
      </View>
      {highest ? (
        <InfoLine
          icon="alert-circle-outline"
          label="Highest card"
          value={`${highest.account.name} · ${formatMoney(
            highestAmount ?? highest.displayBalance,
            state.preferences.locale,
          )}`}
          danger
        />
      ) : (
        <WidgetEmpty
          text={cards.length === 0 ? 'No credit cards yet.' : 'No card debt right now.'}
        />
      )}
    </HomeWidgetShell>
  );
}

function AccountGroupsWidget({
  size,
  datePreset,
  onDatePresetChange,
  selectedAccountId,
}: WidgetShellProps) {
  const { state, indexes, selectors } = useLedger();
  const viewCurrency = selectors.displayCurrency(state);
  const groups = new Map<string, { count: number; amountMinor: number }>();
  for (const account of state.accounts) {
    if (selectedAccountId && account.id !== selectedAccountId) continue;
    if (account.isArchived || !account.includeInTotals) continue;
    const label = account.groupName ?? account.type.replace('_', ' ');
    const balance = balanceForAccount(indexes, account);
    const baseAmount = selectors.convertMoneyForDisplay(state, balance, viewCurrency).amountMinor;
    const current = groups.get(label) ?? { count: 0, amountMinor: 0 };
    groups.set(label, { count: current.count + 1, amountMinor: current.amountMinor + baseAmount });
  }
  const rows = Array.from(groups.entries()).sort(
    (left, right) => Math.abs(right[1].amountMinor) - Math.abs(left[1].amountMinor),
  );

  return (
    <HomeWidgetShell
      {...HOME_WIDGET_META.accountGroups}
      size={size}
      datePreset={datePreset}
      onDatePresetChange={onDatePresetChange}
    >
      {rows.length === 0 ? (
        <WidgetEmpty text="Account groups appear after you add accounts." />
      ) : (
        rows.slice(0, 6).map(([label, item], index) => (
          <View key={label}>
            <InfoLine
              icon="folder-outline"
              label={`${label} · ${item.count}`}
              value={formatMoney(
                { amountMinor: item.amountMinor, currency: viewCurrency },
                state.preferences.locale,
              )}
              danger={item.amountMinor < 0}
            />
            {index < rows.length - 1 && index < 5 ? <Divider /> : null}
          </View>
        ))
      )}
    </HomeWidgetShell>
  );
}

function ReviewQueueWidget({
  size,
  datePreset,
  onDatePresetChange,
  selectedAccountId,
}: WidgetShellProps) {
  const { indexes } = useLedger();
  const range = useMemo(() => dateRangeForPreset(datePreset), [datePreset]);
  const { bySource, pending } = useMemo(() => {
    const pending = (indexes.captureCandidatesByStatus.get('pending') ?? [])
      .filter(
        (candidate) =>
          !selectedAccountId ||
          candidate.suggestedAccountId === selectedAccountId ||
          candidate.suggestedCounterAccountId === selectedAccountId,
      )
      .filter((candidate) => timestampInRange(candidate.createdAt, range));
    const bySource = pending.reduce<Record<string, number>>((acc, item) => {
      acc[item.source] = (acc[item.source] ?? 0) + 1;
      return acc;
    }, {});
    return { bySource, pending };
  }, [indexes.captureCandidatesByStatus, range, selectedAccountId]);

  return (
    <HomeWidgetShell
      {...HOME_WIDGET_META.reviewQueue}
      size={size}
      datePreset={datePreset}
      onDatePresetChange={onDatePresetChange}
      actionLabel="Review"
      onAction={() => router.push('/review' as never)}
    >
      <View style={styles.twoColumnMetrics}>
        <SummaryTile
          label="Pending"
          value={String(pending.length)}
          icon="inbox-arrow-down-outline"
          tone={pending.length ? 'warning' : 'default'}
        />
        <SummaryTile
          label="Sources"
          value={String(Object.keys(bySource).length)}
          icon="source-branch"
        />
      </View>
      {pending.length === 0 ? (
        <WidgetEmpty text="Review queue clear." />
      ) : (
        <ChipRow values={Object.entries(bySource).map(([source, count]) => `${source} ${count}`)} />
      )}
    </HomeWidgetShell>
  );
}

function AutomationHealthWidget({
  size,
  datePreset,
  onDatePresetChange,
  selectedAccountId,
}: WidgetShellProps) {
  const { state, indexes } = useLedger();
  const pendingCaptures = useMemo(
    () =>
      (indexes.captureCandidatesByStatus.get('pending') ?? []).filter(
        (candidate) =>
          !selectedAccountId ||
          candidate.suggestedAccountId === selectedAccountId ||
          candidate.suggestedCounterAccountId === selectedAccountId,
      ),
    [indexes.captureCandidatesByStatus, selectedAccountId],
  );
  const importWarnings = useMemo(
    () =>
      state.importBatches.reduce(
        (sum, batch) => sum + batch.warningCount + batch.duplicateCount,
        0,
      ),
    [state.importBatches],
  );
  const scheduledWeek = useMemo(
    () =>
      plannedTransactionsForSelectedAccount(state, indexes, selectedAccountId).filter(
        (transaction) => {
          const days = dayOffsetFromToday(transaction.occurredAt);
          return days >= 0 && days <= 7;
        },
      ),
    [indexes, selectedAccountId, state],
  );
  const matchedAccounts = useMemo(
    () =>
      state.accounts.filter(
        (account) =>
          (account.matchIdentifiers?.length ?? 0) > 0 ||
          (account.messageSourceHints?.smsSenderIds?.length ?? 0) > 0 ||
          (account.messageSourceHints?.emailDomains?.length ?? 0) > 0,
      ).length,
    [state.accounts],
  );

  return (
    <HomeWidgetShell
      {...HOME_WIDGET_META.automationHealth}
      size={size}
      datePreset={datePreset}
      onDatePresetChange={onDatePresetChange}
      actionLabel="Imports"
      onAction={() => router.push('/imports' as never)}
    >
      <View style={styles.summaryGrid}>
        <SummaryTile
          label="Review"
          value={String(pendingCaptures.length)}
          icon="robot-outline"
          tone={pendingCaptures.length ? 'warning' : 'default'}
        />
        <SummaryTile
          label="Warnings"
          value={String(importWarnings)}
          icon="file-alert-outline"
          tone={importWarnings ? 'warning' : 'default'}
        />
        <SummaryTile
          label="7-day plan"
          value={String(scheduledWeek.length)}
          icon="calendar-clock-outline"
        />
      </View>
      <InfoLine
        icon="target-account"
        label="Message matching"
        value={`${matchedAccounts}/${state.accounts.length}`}
        subvalue="Accounts with last-4, sender, or email hints"
        positive={matchedAccounts > 0}
      />
    </HomeWidgetShell>
  );
}

function CashflowForecastWidget({
  size,
  datePreset,
  onDatePresetChange,
  selectedAccountId,
}: WidgetShellProps) {
  const { state, indexes, selectors } = useLedger();
  const viewCurrency = selectors.displayCurrency(state);
  const upcoming = scheduledTransactionsWithinDays(
    plannedTransactionsForSelectedAccount(state, indexes, selectedAccountId),
    30,
    selectedAccountId,
  );
  const incomeMinor = upcoming.reduce(
    (sum, transaction) => sum + plannedInflowBaseAmountMinor(state, transaction, selectedAccountId),
    0,
  );
  const outflowMinor = upcoming.reduce(
    (sum, transaction) => sum + plannedOutflowBaseAmountMinor(transaction, selectedAccountId),
    0,
  );
  const netMinor = incomeMinor - outflowMinor;
  const next = upcoming[0];

  return (
    <HomeWidgetShell
      {...HOME_WIDGET_META.cashflowForecast}
      size={size}
      datePreset={datePreset}
      onDatePresetChange={onDatePresetChange}
      subtitle="Next 30 days"
      actionLabel="Plan"
      onAction={() => router.push('/recurring' as never)}
    >
      <View style={styles.summaryGrid}>
        <SummaryTile
          label="Income"
          value={formatMoney(
            selectors.convertMoneyForDisplay(
              state,
              { amountMinor: incomeMinor, currency: state.preferences.baseCurrency },
              viewCurrency,
            ),
            state.preferences.locale,
          )}
          icon="arrow-down-bold-outline"
        />
        <SummaryTile
          label="Outflow"
          value={formatMoney(
            selectors.convertMoneyForDisplay(
              state,
              { amountMinor: outflowMinor, currency: state.preferences.baseCurrency },
              viewCurrency,
            ),
            state.preferences.locale,
          )}
          icon="arrow-up-bold-outline"
          tone={outflowMinor ? 'warning' : 'default'}
        />
        <SummaryTile
          label="Net"
          value={formatMoney(
            selectors.convertMoneyForDisplay(
              state,
              { amountMinor: netMinor, currency: state.preferences.baseCurrency },
              viewCurrency,
            ),
            state.preferences.locale,
          )}
          icon="swap-vertical"
          tone={netMinor < 0 ? 'danger' : 'default'}
        />
      </View>
      {next ? (
        <InfoLine
          icon={transactionTypeIcon(next.type)}
          label="Next scheduled"
          value={formatMoney(next.amount, state.preferences.locale)}
          subvalue={`${formatRelativeTransactionDate(next.occurredAt)} · ${transactionTypeLabel(next.type)}`}
          danger={dayOffsetFromToday(next.occurredAt) < 0}
        />
      ) : (
        <WidgetEmpty text="No scheduled cashflow in the next 30 days." />
      )}
    </HomeWidgetShell>
  );
}

function BillWatchWidget({
  size,
  datePreset,
  onDatePresetChange,
  selectedAccountId,
}: WidgetShellProps) {
  const { state, indexes } = useLedger();
  const bills = scheduledTransactionsWithinDays(
    plannedTransactionsForSelectedAccount(state, indexes, selectedAccountId),
    30,
    selectedAccountId,
  ).filter(
    (transaction) =>
      transaction.type === 'expense' ||
      transaction.type === 'card_payment' ||
      transaction.type === 'loan_repayment',
  );
  const autoDebits = bills.filter((transaction) =>
    transaction.paymentMethod?.toLowerCase().includes('auto'),
  );
  const overdue = bills.filter((transaction) => dayOffsetFromToday(transaction.occurredAt) < 0);
  const next = bills[0];

  return (
    <HomeWidgetShell
      {...HOME_WIDGET_META.billWatch}
      size={size}
      datePreset={datePreset}
      onDatePresetChange={onDatePresetChange}
      subtitle="Next 30 days"
      actionLabel="Bills"
      onAction={() => router.push('/recurring' as never)}
    >
      <View style={styles.summaryGrid}>
        <SummaryTile label="Bills" value={String(bills.length)} icon="clipboard-text-outline" />
        <SummaryTile
          label="Auto debit"
          value={String(autoDebits.length)}
          icon="calendar-sync-outline"
          tone={autoDebits.length ? 'warning' : 'default'}
        />
        <SummaryTile
          label="Overdue"
          value={String(overdue.length)}
          icon="alert-circle-outline"
          tone={overdue.length ? 'danger' : 'default'}
        />
      </View>
      {next ? (
        <InfoLine
          icon={transactionTypeIcon(next.type)}
          label="Next bill"
          value={formatMoney(next.amount, state.preferences.locale)}
          subvalue={`${formatRelativeTransactionDate(next.occurredAt)} · ${next.paymentMethod ?? transactionTypeLabel(next.type)}`}
          danger={dayOffsetFromToday(next.occurredAt) < 0}
        />
      ) : (
        <WidgetEmpty text="No bills, subscriptions, cards, or EMIs in the next 30 days." />
      )}
    </HomeWidgetShell>
  );
}

function CardPaymentPlanWidget({
  size,
  datePreset,
  onDatePresetChange,
  selectedAccountId,
}: WidgetShellProps) {
  const { state, indexes, selectors } = useLedger();
  const viewCurrency = selectors.displayCurrency(state);
  const cards = state.accounts.filter(
    (account) =>
      !account.isArchived &&
      account.type === 'credit_card' &&
      (!selectedAccountId || account.id === selectedAccountId),
  );
  const payments = scheduledTransactionsWithinDays(
    plannedTransactionsForSelectedAccount(state, indexes, selectedAccountId),
    30,
    selectedAccountId,
  ).filter((transaction) => transaction.type === 'card_payment');
  const totalDebtMinor = cards.reduce((sum, card) => {
    const balance = balanceForAccount(indexes, card);
    const display = selectors.convertMoneyForDisplay(state, balance, viewCurrency);
    return sum + Math.abs(Math.min(display.amountMinor, 0));
  }, 0);
  const plannedMinor = payments.reduce(
    (sum, payment) =>
      sum +
      Math.abs(selectors.convertMoneyForDisplay(state, payment.amount, viewCurrency).amountMinor),
    0,
  );
  const next = payments[0];

  return (
    <HomeWidgetShell
      {...HOME_WIDGET_META.cardPaymentPlan}
      size={size}
      datePreset={datePreset}
      onDatePresetChange={onDatePresetChange}
      actionLabel="Cards"
      onAction={() => router.push('/cards' as never)}
    >
      <View style={styles.twoColumnMetrics}>
        <SummaryTile
          label="Card debt"
          value={formatMoney(
            { amountMinor: totalDebtMinor, currency: viewCurrency },
            state.preferences.locale,
          )}
          icon="credit-card-outline"
          tone={totalDebtMinor ? 'danger' : 'default'}
        />
        <SummaryTile
          label="Planned"
          value={formatMoney(
            { amountMinor: plannedMinor, currency: viewCurrency },
            state.preferences.locale,
          )}
          icon="credit-card-check-outline"
          tone={plannedMinor ? 'warning' : 'default'}
        />
      </View>
      {next ? (
        <InfoLine
          icon="calendar-clock-outline"
          label="Next card payment"
          value={formatMoney(next.amount, state.preferences.locale)}
          subvalue={formatRelativeTransactionDate(next.occurredAt)}
          danger={dayOffsetFromToday(next.occurredAt) < 0}
        />
      ) : (
        <WidgetEmpty text="No scheduled card payments." />
      )}
    </HomeWidgetShell>
  );
}

function LoanPayoffWidget({
  size,
  datePreset,
  onDatePresetChange,
  selectedAccountId,
}: WidgetShellProps) {
  const { state, indexes, selectors } = useLedger();
  const viewCurrency = selectors.displayCurrency(state);
  const loans = state.accounts.filter(
    (account) =>
      !account.isArchived &&
      ['loan', 'overdraft', 'lent'].includes(account.type) &&
      (!selectedAccountId || account.id === selectedAccountId),
  );
  const emis = scheduledTransactionsWithinDays(
    plannedTransactionsForSelectedAccount(state, indexes, selectedAccountId),
    30,
    selectedAccountId,
  ).filter((transaction) => transaction.type === 'loan_repayment');
  const remainingMinor = loans.reduce((sum, loan) => {
    const balance = balanceForAccount(indexes, loan);
    const display = selectors.convertMoneyForDisplay(state, balance, viewCurrency);
    return sum + Math.abs(Math.min(display.amountMinor, 0));
  }, 0);
  const emiMinor = emis.reduce(
    (sum, emi) =>
      sum + Math.abs(selectors.convertMoneyForDisplay(state, emi.amount, viewCurrency).amountMinor),
    0,
  );
  const next = emis[0];

  return (
    <HomeWidgetShell
      {...HOME_WIDGET_META.loanPayoff}
      size={size}
      datePreset={datePreset}
      onDatePresetChange={onDatePresetChange}
      actionLabel="Loans"
      onAction={() => router.push('/loans' as never)}
    >
      <View style={styles.twoColumnMetrics}>
        <SummaryTile
          label="Remaining"
          value={formatMoney(
            { amountMinor: remainingMinor, currency: viewCurrency },
            state.preferences.locale,
          )}
          icon="bank-outline"
          tone={remainingMinor ? 'danger' : 'default'}
        />
        <SummaryTile
          label="30-day EMI"
          value={formatMoney(
            { amountMinor: emiMinor, currency: viewCurrency },
            state.preferences.locale,
          )}
          icon="bank-transfer-out"
          tone={emiMinor ? 'warning' : 'default'}
        />
      </View>
      {next ? (
        <InfoLine
          icon="calendar-clock-outline"
          label="Next EMI"
          value={formatMoney(next.amount, state.preferences.locale)}
          subvalue={formatRelativeTransactionDate(next.occurredAt)}
          danger={dayOffsetFromToday(next.occurredAt) < 0}
        />
      ) : (
        <WidgetEmpty text="No scheduled loan repayments." />
      )}
    </HomeWidgetShell>
  );
}

function SavingsRunwayWidget({
  size,
  datePreset,
  onDatePresetChange,
  selectedAccountId,
}: WidgetShellProps) {
  const { state, indexes, selectors } = useLedger();
  const viewCurrency = selectors.displayCurrency(state);
  const liquidTypes = new Set(['bank', 'cash', 'wallet', 'prepaid', 'debit_card']);
  const liquidBaseMinor = state.accounts
    .filter(
      (account) =>
        !account.isArchived &&
        liquidTypes.has(account.type) &&
        (!selectedAccountId || account.id === selectedAccountId),
    )
    .reduce((sum, account) => {
      const baseBalance = selectors.convertMoneyForDisplay(
        state,
        balanceForAccount(indexes, account),
        state.preferences.baseCurrency,
      );
      return sum + Math.max(0, baseBalance.amountMinor);
    }, 0);
  const since = new Date();
  since.setDate(since.getDate() - 30);
  const thirtyDaySpendMinor = transactionsForSelectedAccount(indexes, selectedAccountId)
    .filter((transaction) => transaction.status !== 'scheduled' && transaction.status !== 'void')
    .filter((transaction) => !transaction.isExcludedFromReports)
    .filter((transaction) => OUTFLOW_TYPES.has(transaction.type))
    .filter((transaction) => new Date(transaction.occurredAt) >= since)
    .reduce((sum, transaction) => sum + Math.abs(transaction.baseAmount.amountMinor), 0);
  const dailySpendMinor = Math.round(thirtyDaySpendMinor / 30);
  const runwayDays =
    dailySpendMinor > 0 ? Math.floor(liquidBaseMinor / dailySpendMinor) : undefined;
  const liquidDisplay = selectors.convertMoneyForDisplay(
    state,
    { amountMinor: liquidBaseMinor, currency: state.preferences.baseCurrency },
    viewCurrency,
  );
  const dailyDisplay = selectors.convertMoneyForDisplay(
    state,
    { amountMinor: dailySpendMinor, currency: state.preferences.baseCurrency },
    viewCurrency,
  );

  return (
    <HomeWidgetShell
      {...HOME_WIDGET_META.savingsRunway}
      size={size}
      datePreset={datePreset}
      onDatePresetChange={onDatePresetChange}
      subtitle="Liquid cash vs last 30 days"
    >
      <View style={styles.twoColumnMetrics}>
        <SummaryTile
          label="Liquid"
          value={formatMoney(liquidDisplay, state.preferences.locale)}
          icon="wallet-outline"
        />
        <SummaryTile
          label="Runway"
          value={runwayDays === undefined ? 'No spend' : `${runwayDays}d`}
          icon="timer-sand"
          tone={runwayDays !== undefined && runwayDays < 14 ? 'warning' : 'default'}
        />
      </View>
      <InfoLine
        icon="chart-timeline-variant"
        label="Daily burn"
        value={formatMoney(dailyDisplay, state.preferences.locale)}
        subvalue="Based on cleared expenses in the last 30 days"
        danger={dailySpendMinor > 0}
      />
    </HomeWidgetShell>
  );
}

function CashflowBookWidget({
  size,
  datePreset,
  onDatePresetChange,
  selectedAccountId,
}: WidgetShellProps) {
  const { state, indexes } = useLedger();
  const flow = cashflowForPreset(
    state,
    datePreset,
    selectedAccountId,
    displayCurrency(state),
    indexes,
  );

  return (
    <HomeWidgetShell
      {...HOME_WIDGET_META.cashflowBook}
      size={size}
      datePreset={datePreset}
      onDatePresetChange={onDatePresetChange}
      subtitle={dateRangeSubtitle(datePreset) ?? 'All time'}
    >
      <InfoLine
        icon="arrow-down-bold-outline"
        label="Income"
        value={formatMoney(flow.income, state.preferences.locale)}
        positive
      />
      <Divider />
      <InfoLine
        icon="arrow-up-bold-outline"
        label="Expenses"
        value={formatMoney(flow.expense, state.preferences.locale)}
        danger
      />
      <Divider />
      <InfoLine
        icon="swap-vertical"
        label="Net"
        value={formatMoney(flow.net, state.preferences.locale)}
        danger={flow.net.amountMinor < 0}
        positive={flow.net.amountMinor >= 0}
      />
    </HomeWidgetShell>
  );
}

function BalanceTrendWidget({
  size,
  datePreset,
  onDatePresetChange,
  selectedAccountId,
}: WidgetShellProps) {
  const { state } = useLedger();
  const viewCurrency = displayCurrency(state);
  const [selectedPointKey, setSelectedPointKey] = useState<string>();
  const series = useMemo(
    () => balanceTrendSeriesForPreset(state, datePreset, selectedAccountId, viewCurrency),
    [datePreset, selectedAccountId, state, viewCurrency],
  );
  const summaryPoint = series.latest;
  const change = summaryPoint.changeFromStartMinor;
  const changeMoney = { amountMinor: Math.abs(change), currency: viewCurrency };
  const hideTrendTooltip = () => setSelectedPointKey(undefined);

  return (
    <HomeWidgetShell
      {...HOME_WIDGET_META.balanceTrend}
      size={size}
      datePreset={datePreset}
      onDatePresetChange={onDatePresetChange}
      onTouchStart={hideTrendTooltip}
      subtitle={dateRangeSubtitle(datePreset) ?? 'Recent balance'}
    >
      <InteractiveBalanceTrendChart
        series={series}
        selectedPointKey={selectedPointKey}
        onSelectedPointChange={(point) => setSelectedPointKey(point.key)}
        onSelectedPointClear={hideTrendTooltip}
        locale={state.preferences.locale}
        currency={viewCurrency}
      />
      <View style={styles.trendSummaryRow} onTouchStart={hideTrendTooltip}>
        <Text variant="bodySmall" numberOfLines={1} style={styles.mutedText}>
          Current {summaryPoint.label}{' '}
          {formatMoney(
            { amountMinor: summaryPoint.amountMinor, currency: viewCurrency },
            state.preferences.locale,
          )}
        </Text>
        <Text variant="bodySmall" style={change >= 0 ? styles.positiveText : styles.dangerText}>
          {change >= 0 ? '+' : '-'}
          {formatMoney(changeMoney, state.preferences.locale)}
        </Text>
      </View>
    </HomeWidgetShell>
  );
}

function TopCategoriesWidget({
  size,
  datePreset,
  onDatePresetChange,
  selectedAccountId,
}: WidgetShellProps) {
  return (
    <CategoryBreakdownWidget
      widgetId="topCategories"
      kind="expense"
      size={size}
      datePreset={datePreset}
      onDatePresetChange={onDatePresetChange}
      selectedAccountId={selectedAccountId}
      emptyText="No spending categories this month."
    />
  );
}

function IncomeMixWidget({
  size,
  datePreset,
  onDatePresetChange,
  selectedAccountId,
}: WidgetShellProps) {
  return (
    <CategoryBreakdownWidget
      widgetId="incomeMix"
      kind="income"
      size={size}
      datePreset={datePreset}
      onDatePresetChange={onDatePresetChange}
      selectedAccountId={selectedAccountId}
      emptyText="No income records in this period."
    />
  );
}

function CategoryBreakdownWidget({
  widgetId,
  kind,
  size,
  datePreset,
  onDatePresetChange,
  selectedAccountId,
  emptyText,
}: WidgetShellProps & {
  widgetId: 'topCategories' | 'incomeMix';
  kind: 'expense' | 'income';
  emptyText: string;
}) {
  const theme = useTheme();
  const { state, indexes } = useLedger();
  const viewCurrency = displayCurrency(state);
  const [expandedCategoryKey, setExpandedCategoryKey] = useState<string>();
  const [selectedSubcategory, setSelectedSubcategory] = useState<TopCategorySubcategory>();
  const categories = useMemo(
    () =>
      topCategoryDrilldownForPreset(
        state,
        datePreset,
        kind,
        selectedAccountId,
        viewCurrency,
        indexes,
      ).slice(0, 5),
    [datePreset, indexes, kind, selectedAccountId, state, viewCurrency],
  );
  const closeSubcategoryRecords = () => setSelectedSubcategory(undefined);

  return (
    <>
      <HomeWidgetShell
        {...HOME_WIDGET_META[widgetId]}
        size={size}
        datePreset={datePreset}
        onDatePresetChange={onDatePresetChange}
        actionLabel="Records"
        onAction={() => router.push('/(tabs)/transactions' as never)}
      >
        {categories.length === 0 ? (
          <WidgetEmpty text={emptyText} />
        ) : (
          categories.map((category, index) => {
            const categoryKey = category.categoryId ?? category.categoryName;
            const expanded = expandedCategoryKey === categoryKey;
            const color = ACCOUNT_COLORS[index % ACCOUNT_COLORS.length] ?? tokens.color.md3Primary;
            return (
              <View key={categoryKey} style={styles.categoryDrillGroup}>
                <TouchableRipple
                  borderless
                  style={styles.categoryDrillRipple}
                  onPress={() => setExpandedCategoryKey(expanded ? undefined : categoryKey)}
                >
                  <View style={styles.categoryDrillHeader}>
                    <View style={styles.fill}>
                      <BarRow
                        label={category.categoryName}
                        value={formatMoney(category.amount, state.preferences.locale)}
                        subvalue={`${category.subcategories.length} ${category.subcategories.length === 1 ? 'subcategory' : 'subcategories'}`}
                        progress={category.share}
                        color={color}
                      />
                    </View>
                    <MaterialCommunityIcons
                      name={expanded ? 'chevron-up' : 'chevron-down'}
                      size={20}
                      color={color}
                    />
                  </View>
                </TouchableRipple>
                {expanded ? (
                  <View style={styles.subcategoryStack}>
                    {category.subcategories.map((subcategory) => (
                      <TouchableRipple
                        key={subcategory.key}
                        borderless
                        style={styles.subcategoryRipple}
                        onPress={() => setSelectedSubcategory(subcategory)}
                      >
                        <View style={styles.subcategoryRow}>
                          <BarRow
                            label={subcategory.categoryName}
                            value={formatMoney(subcategory.amount, state.preferences.locale)}
                            subvalue={`${subcategory.recordCount} ${subcategory.recordCount === 1 ? 'record' : 'records'}`}
                            progress={subcategory.share}
                            color={color}
                          />
                        </View>
                      </TouchableRipple>
                    ))}
                  </View>
                ) : null}
              </View>
            );
          })
        )}
      </HomeWidgetShell>
      <Portal>
        <Modal
          visible={Boolean(selectedSubcategory)}
          onDismiss={closeSubcategoryRecords}
          contentContainerStyle={[
            styles.categoryRecordsModal,
            {
              backgroundColor: theme.colors.elevation.level2,
              borderColor: theme.colors.outlineVariant,
            },
          ]}
        >
          {selectedSubcategory ? (
            <TopCategoryRecordsModalContent
              subcategory={selectedSubcategory}
              selectedAccountId={selectedAccountId}
              locale={state.preferences.locale}
              onDismiss={closeSubcategoryRecords}
            />
          ) : null}
        </Modal>
      </Portal>
    </>
  );
}

function TopCategoryRecordsModalContent({
  subcategory,
  selectedAccountId,
  locale,
  onDismiss,
}: {
  subcategory: TopCategorySubcategory;
  selectedAccountId?: string;
  locale: string;
  onDismiss: () => void;
}) {
  const theme = useTheme();

  return (
    <View style={styles.categoryRecordsModalContent}>
      <View style={styles.categoryRecordsHeader}>
        <View style={styles.fill}>
          <Text variant="titleLarge" numberOfLines={1} style={styles.recordTitle}>
            {subcategory.categoryName}
          </Text>
          <Text
            variant="bodySmall"
            numberOfLines={1}
            style={{ color: theme.colors.onSurfaceVariant }}
          >
            {subcategory.recordCount} {subcategory.recordCount === 1 ? 'record' : 'records'} ·{' '}
            {formatMoney(subcategory.amount, locale)}
          </Text>
        </View>
        <IconButton icon="close" onPress={onDismiss} />
      </View>
      <Divider />
      <ScrollView style={styles.categoryRecordsScroll} showsVerticalScrollIndicator={false}>
        {subcategory.records.length === 0 ? (
          <WidgetEmpty text="No records in this subcategory." />
        ) : (
          <TransactionList records={subcategory.records} selectedAccountId={selectedAccountId} />
        )}
      </ScrollView>
    </View>
  );
}

function CurrencyValuesWidget({ size, datePreset, onDatePresetChange }: WidgetShellProps) {
  const theme = useTheme();
  const { state } = useLedger();
  const [pickerVisible, setPickerVisible] = useState(false);
  const [selectedRatePointKey, setSelectedRatePointKey] = useState<string>();
  const enabledCurrencyCodes = useMemo(() => enabledCurrencyCodesForWidget(state), [state]);
  const enabledCurrencyKey = enabledCurrencyCodes.join('|');
  const [converterCurrencies, setConverterCurrencies] = useState<string[]>(() =>
    initialCurrencyConverterCodes(state),
  );
  const [sourceCurrency, setSourceCurrency] = useState(
    () => initialCurrencyConverterCodes(state)[0] ?? state.preferences.baseCurrency,
  );
  const previousEnabledCurrencyKeyRef = useRef(enabledCurrencyKey);
  const [sourceValue, setSourceValue] = useState('1');
  const locale = state.preferences.locale;
  const defaultCurrency = state.preferences.baseCurrency;
  const chartAmount = positiveCurrencyInputValue(sourceValue) || 1;
  const rateDatePreset = CURRENCY_RATE_DATE_PRESETS.includes(datePreset) ? datePreset : 'thisMonth';
  const chartSourceCurrencies = useMemo(
    () => currencyRateChartSourceCurrencies(state, converterCurrencies, defaultCurrency),
    [converterCurrencies, defaultCurrency, state],
  );
  const rateHistory = useCurrencyRateHistory(
    defaultCurrency,
    chartSourceCurrencies,
    rateDatePreset,
  );
  const primaryTarget = useMemo(
    () =>
      converterCurrencies.find(
        (currency) =>
          currency !== sourceCurrency && realRateBetween(state, sourceCurrency, currency),
      ) ?? converterCurrencies.find((currency) => currency !== sourceCurrency),
    [converterCurrencies, sourceCurrency, state],
  );
  const primaryRate = useMemo(
    () => (primaryTarget ? realRateBetween(state, sourceCurrency, primaryTarget) : undefined),
    [primaryTarget, sourceCurrency, state],
  );
  const primaryTargetMoney =
    primaryTarget && primaryRate
      ? decimalToMoney(chartAmount * primaryRate.rate, primaryTarget)
      : undefined;
  const rateSeries = useMemo(
    () =>
      chartSourceCurrencies.length > 0
        ? currencyRateTrendSeriesForPreset(
            state,
            chartSourceCurrencies,
            defaultCurrency,
            rateDatePreset,
            rateHistory.data,
          )
        : undefined,
    [chartSourceCurrencies, defaultCurrency, rateDatePreset, rateHistory.data, state],
  );
  const primaryRateLine =
    rateSeries?.lines.find((line) => line.sourceCurrency === sourceCurrency) ??
    rateSeries?.lines[0];
  const rateChange = primaryRateLine ? primaryRateLine.latest.rate - primaryRateLine.start.rate : 0;
  const pickerOptions = useMemo(
    () => currencyValuePickerOptions(state, converterCurrencies),
    [converterCurrencies, state],
  );
  const hasAddableCurrency = pickerOptions.some((option) => !option.disabled);
  const hideRateTooltip = () => setSelectedRatePointKey(undefined);

  useEffect(() => {
    const previousEnabled = previousEnabledCurrencyKeyRef.current
      ? previousEnabledCurrencyKeyRef.current.split('|')
      : [];
    const newlyEnabled = enabledCurrencyCodes.filter(
      (currency) => !previousEnabled.includes(currency),
    );

    setConverterCurrencies((current) => {
      const retained = current.filter((currency) => enabledCurrencyCodes.includes(currency));
      const seeded = retained.length > 0 ? retained : enabledCurrencyCodes;
      const next = uniqueCurrencyCodes([...seeded, ...newlyEnabled]).slice(0, 4);
      const resolved = next.length > 0 ? next : [normalizeCurrencyCode(defaultCurrency)];
      return sameCurrencyCodes(current, resolved) ? current : resolved;
    });
    previousEnabledCurrencyKeyRef.current = enabledCurrencyKey;
  }, [defaultCurrency, enabledCurrencyCodes, enabledCurrencyKey]);

  useEffect(() => {
    setSourceCurrency((current) => {
      if (enabledCurrencyCodes.includes(current) && converterCurrencies.includes(current)) {
        return current;
      }
      return (
        converterCurrencies[0] ?? enabledCurrencyCodes[0] ?? normalizeCurrencyCode(defaultCurrency)
      );
    });
  }, [converterCurrencies, defaultCurrency, enabledCurrencyCodes]);

  const updateCurrencyValue = (currency: string, value: string) => {
    hideRateTooltip();
    setSourceCurrency(currency);
    setSourceValue(sanitizeCurrencyInput(value));
  };

  const focusCurrencyValue = (currency: string) => {
    if (currency === sourceCurrency) return;
    hideRateTooltip();
    setSourceValue(convertedCurrencyInputValue(state, sourceValue, sourceCurrency, currency));
    setSourceCurrency(currency);
  };

  const addConverterCurrency = (currency: string) => {
    hideRateTooltip();
    const normalized = normalizeCurrencyCode(currency);
    if (!enabledCurrencyCodes.includes(normalized)) return;
    setConverterCurrencies((current) => uniqueCurrencyCodes([...current, normalized]));
    setPickerVisible(false);
  };

  const removeConverterCurrency = (currency: string) => {
    hideRateTooltip();
    setConverterCurrencies((current) => {
      if (current.length <= 1) return current;
      return current.filter((item) => item !== currency);
    });
  };

  return (
    <>
      <HomeWidgetShell
        {...HOME_WIDGET_META.currencyValues}
        size={size}
        subtitle={
          rateSeries?.lines.length
            ? `${rateSeries.lines.length} rates to ${defaultCurrency}`
            : primaryTarget
              ? `1 ${sourceCurrency} to ${primaryTarget}`
              : 'Exchange values'
        }
        datePreset={rateDatePreset}
        onDatePresetChange={onDatePresetChange}
        datePresets={CURRENCY_RATE_DATE_PRESETS}
        actionLabel="Rates"
        onAction={() => router.push('/currencies' as never)}
        onTouchStart={hideRateTooltip}
      >
        <View style={styles.currencyValuesHeader}>
          <View style={styles.fill}>
            <Text variant="labelLarge" style={{ color: theme.colors.onSurfaceVariant }}>
              {formatPlainCurrencyNumber(chartAmount, sourceCurrency)} {sourceCurrency}
            </Text>
            {primaryTarget && primaryTargetMoney ? (
              <Text variant="titleMedium" numberOfLines={1} style={styles.currencyValueHeadline}>
                {formatMoney(primaryTargetMoney, locale)}
              </Text>
            ) : primaryTarget ? (
              <Text
                variant="bodyMedium"
                numberOfLines={1}
                style={[styles.currencyValueMissing, { color: theme.colors.secondary }]}
              >
                No saved rate for {sourceCurrency} to {primaryTarget}
              </Text>
            ) : null}
          </View>
          <IconButton
            icon="plus"
            mode="contained-tonal"
            disabled={!hasAddableCurrency}
            onPress={() => setPickerVisible(true)}
          />
        </View>

        {rateSeries ? (
          <>
            <InteractiveCurrencyRateTrendChart
              series={rateSeries}
              selectedPointKey={selectedRatePointKey}
              onSelectedPointChange={(point) => setSelectedRatePointKey(point.key)}
              onSelectedPointClear={hideRateTooltip}
              locale={locale}
            />
            <View style={styles.trendSummaryRow} onTouchStart={hideRateTooltip}>
              <Text
                variant="bodySmall"
                numberOfLines={1}
                style={[styles.mutedText, { color: theme.colors.onSurfaceVariant }]}
              >
                {primaryRateLine
                  ? `Latest ${primaryRateLine.latest.label} 1 ${primaryRateLine.sourceCurrency} = ${formatRateDisplay(
                      primaryRateLine.latest.rate,
                      defaultCurrency,
                      locale,
                    )}`
                  : 'Latest rate unavailable'}
              </Text>
              <Text
                variant="bodySmall"
                style={rateChange >= 0 ? styles.positiveText : styles.dangerText}
              >
                {formatRateDelta(rateChange, defaultCurrency, locale)}
              </Text>
            </View>
          </>
        ) : (
          <WidgetEmpty text="Add another enabled currency to draw the exchange trend." />
        )}

        <View style={styles.currencyConverterStack}>
          {converterCurrencies.map((currency) => {
            const isSource = currency === sourceCurrency;
            const explicitRate = hasRealExplicitRate(state, sourceCurrency, currency);
            return (
              <View key={currency} style={styles.currencyConverterItem}>
                <View style={styles.currencyConverterRow}>
                  <PremiumTextInput
                    dense
                    label={currency}
                    value={
                      isSource
                        ? sourceValue
                        : convertedCurrencyInputValue(state, sourceValue, sourceCurrency, currency)
                    }
                    onFocus={() => focusCurrencyValue(currency)}
                    onChangeText={(value) => updateCurrencyValue(currency, value)}
                    keyboardType="decimal-pad"
                    returnKeyType="done"
                    selectTextOnFocus
                    left={<TextInput.Icon icon={currencyIcon(currency)} />}
                    style={styles.currencyConverterInput}
                  />
                  {converterCurrencies.length > 2 ? (
                    <IconButton icon="close" onPress={() => removeConverterCurrency(currency)} />
                  ) : null}
                </View>
                <Text
                  variant="labelSmall"
                  numberOfLines={1}
                  style={{
                    color: explicitRate ? theme.colors.onSurfaceVariant : theme.colors.secondary,
                  }}
                >
                  {currencyRateLabel(state, sourceCurrency, currency, locale)}
                </Text>
              </View>
            );
          })}
        </View>
      </HomeWidgetShell>
      <OptionListOverlay
        visible={pickerVisible}
        title="Add enabled currency"
        options={pickerOptions}
        searchPlaceholder="Search currencies"
        emptyText="Enable more currencies from Currencies first"
        onDismiss={() => setPickerVisible(false)}
        onSelect={(option) => {
          if (option.disabled) return;
          addConverterCurrency(option.value);
        }}
      />
    </>
  );
}

function InteractiveCurrencyRateTrendChart({
  series,
  selectedPointKey,
  onSelectedPointChange,
  onSelectedPointClear,
  locale,
}: {
  series: CurrencyRateTrendSeries;
  selectedPointKey?: string;
  onSelectedPointChange: (point: CurrencyRateTrendPoint) => void;
  onSelectedPointClear: () => void;
  locale: string;
}) {
  const theme = useTheme();
  const [plotWidth, setPlotWidth] = useState(0);
  const selectedPoint = selectedPointKey
    ? series.points.find((point) => point.key === selectedPointKey)
    : undefined;
  const axisTicks = useMemo(
    () => currencyRateAxisTicks(series.points, series.targetCurrency, locale),
    [locale, series.points, series.targetCurrency],
  );
  const chartMin = axisTicks[0]?.rate ?? 0;
  const chartMax = axisTicks[axisTicks.length - 1]?.rate ?? 1;
  const chartRange = Math.max(Number.EPSILON, chartMax - chartMin);
  const rangeDuration = Math.max(1, series.rangeEnd - series.rangeStart);
  const usableWidth = Math.max(1, plotWidth - TREND_CHART_PADDING_X * 2);
  const usableHeight = TREND_CHART_HEIGHT - TREND_CHART_PADDING_Y * 2;

  const coordinateForPoint = (point: CurrencyRateTrendPoint) => {
    const x =
      TREND_CHART_PADDING_X + ((point.timestamp - series.rangeStart) / rangeDuration) * usableWidth;
    const y = TREND_CHART_PADDING_Y + (1 - (point.rate - chartMin) / chartRange) * usableHeight;
    return {
      point,
      x: clampNumber(x, TREND_CHART_PADDING_X, TREND_CHART_PADDING_X + usableWidth),
      y: clampNumber(y, TREND_CHART_PADDING_Y, TREND_CHART_PADDING_Y + usableHeight),
    };
  };

  const selectedLineIndex = selectedPoint
    ? series.lines.findIndex((line) => line.sourceCurrency === selectedPoint.sourceCurrency)
    : -1;
  const selectedLineColor = currencyRateLineColor(theme, Math.max(0, selectedLineIndex));
  const selectedCoordinate = selectedPoint ? coordinateForPoint(selectedPoint) : undefined;
  const tooltipHeight = 66;
  const tooltipLeft = selectedCoordinate
    ? selectedCoordinate.x > plotWidth * 0.56
      ? selectedCoordinate.x - TREND_TOOLTIP_WIDTH - tokens.space.sm
      : selectedCoordinate.x + tokens.space.sm
    : 0;
  const tooltipTop = selectedCoordinate
    ? selectedCoordinate.y > TREND_CHART_HEIGHT * 0.52
      ? selectedCoordinate.y - tooltipHeight - tokens.space.sm
      : selectedCoordinate.y + tokens.space.sm
    : 0;
  const clampedTooltipLeft = clampNumber(
    tooltipLeft,
    0,
    Math.max(0, plotWidth - TREND_TOOLTIP_WIDTH),
  );
  const clampedTooltipTop = clampNumber(tooltipTop, 0, TREND_CHART_HEIGHT - tooltipHeight);

  const panResponder = useMemo(
    () =>
      PanResponder.create({
        onStartShouldSetPanResponder: () => true,
        onMoveShouldSetPanResponder: () => true,
        onPanResponderGrant: (event: GestureResponderEvent) => {
          if (plotWidth <= 0) return;
          const x = clampNumber(
            event.nativeEvent.locationX - TREND_CHART_PADDING_X,
            0,
            usableWidth,
          );
          const timestamp = series.rangeStart + (x / Math.max(1, usableWidth)) * rangeDuration;
          onSelectedPointChange(nearestCurrencyRatePoint(series.points, timestamp));
        },
        onPanResponderMove: (event: GestureResponderEvent) => {
          if (plotWidth <= 0) return;
          const x = clampNumber(
            event.nativeEvent.locationX - TREND_CHART_PADDING_X,
            0,
            usableWidth,
          );
          const timestamp = series.rangeStart + (x / Math.max(1, usableWidth)) * rangeDuration;
          onSelectedPointChange(nearestCurrencyRatePoint(series.points, timestamp));
        },
      }),
    [
      onSelectedPointChange,
      plotWidth,
      rangeDuration,
      series.points,
      series.rangeStart,
      usableWidth,
    ],
  );

  return (
    <View
      style={[styles.trendCard, { backgroundColor: theme.colors.surfaceVariant }]}
      onTouchStart={onSelectedPointClear}
    >
      <View style={styles.trendChartBody}>
        <View style={styles.trendAxis}>
          {axisTicks.map((tick) => {
            const y =
              TREND_CHART_PADDING_Y + (1 - (tick.rate - chartMin) / chartRange) * usableHeight;
            return (
              <Text
                key={tick.key}
                variant="labelSmall"
                numberOfLines={1}
                style={[
                  styles.trendAxisLabel,
                  {
                    top: clampNumber(y - 7, 0, TREND_CHART_HEIGHT - 14),
                    color: theme.colors.onSurfaceVariant,
                  },
                ]}
              >
                {tick.label}
              </Text>
            );
          })}
        </View>
        <View
          collapsable={false}
          style={styles.trendPlotArea}
          onLayout={(event) => setPlotWidth(event.nativeEvent.layout.width)}
          onTouchStart={(event) => event.stopPropagation()}
          {...panResponder.panHandlers}
        >
          {axisTicks.map((tick) => {
            const y =
              TREND_CHART_PADDING_Y + (1 - (tick.rate - chartMin) / chartRange) * usableHeight;
            return (
              <View
                key={tick.key}
                style={[
                  styles.trendGridLine,
                  {
                    top: y,
                    backgroundColor: theme.colors.outlineVariant,
                    opacity: 0.58,
                  },
                ]}
              />
            );
          })}
          {plotWidth > 0
            ? series.lines.flatMap((line, lineIndex) => {
                const lineColor = currencyRateLineColor(theme, lineIndex);
                const coordinates = smoothCurrencyRateCoordinates(
                  line.plotPoints.map(coordinateForPoint),
                  TREND_CHART_PADDING_Y,
                  TREND_CHART_PADDING_Y + usableHeight,
                );
                return coordinates.slice(1).map((coordinate, index) => {
                  const previous = coordinates[index];
                  if (!previous) return null;
                  const dx = coordinate.x - previous.x;
                  const dy = coordinate.y - previous.y;
                  const length = Math.sqrt(dx * dx + dy * dy);
                  if (length < 0.5) return null;
                  const segmentWidth = length + TREND_LINE_THICKNESS;
                  return (
                    <View
                      key={`${line.sourceCurrency}-smooth-${index}`}
                      style={[
                        styles.trendSegment,
                        {
                          width: segmentWidth,
                          left: previous.x + dx / 2 - segmentWidth / 2,
                          top: previous.y + dy / 2 - TREND_LINE_THICKNESS / 2,
                          backgroundColor: lineColor,
                          transform: [{ rotate: `${Math.atan2(dy, dx)}rad` }],
                        },
                      ]}
                    />
                  );
                });
              })
            : null}
          {plotWidth > 0 && selectedPoint && selectedCoordinate ? (
            <>
              <View
                pointerEvents="none"
                style={[
                  styles.trendCursor,
                  { left: selectedCoordinate.x, backgroundColor: selectedLineColor },
                ]}
              />
              <View
                pointerEvents="none"
                style={[
                  styles.trendDot,
                  styles.trendDotLatest,
                  {
                    left: selectedCoordinate.x - TREND_LATEST_DOT_SIZE / 2,
                    top: selectedCoordinate.y - TREND_LATEST_DOT_SIZE / 2,
                    backgroundColor: selectedLineColor,
                    borderColor: theme.colors.surfaceVariant,
                  },
                ]}
              />
              <View
                pointerEvents="none"
                style={[
                  styles.trendTooltip,
                  {
                    left: clampedTooltipLeft,
                    top: clampedTooltipTop,
                    backgroundColor: theme.colors.elevation.level3,
                    borderColor: theme.colors.outlineVariant,
                  },
                ]}
              >
                <Text
                  variant="labelSmall"
                  numberOfLines={1}
                  style={[styles.mutedText, { color: theme.colors.onSurfaceVariant }]}
                >
                  {selectedPoint.fullLabel}
                </Text>
                <Text variant="labelLarge" numberOfLines={1} style={styles.trendTooltipAmount}>
                  1 {selectedPoint.sourceCurrency} ={' '}
                  {formatRateDisplay(selectedPoint.rate, selectedPoint.targetCurrency, locale)}
                </Text>
              </View>
            </>
          ) : null}
        </View>
      </View>
      <View style={styles.currencyRateLegend}>
        {series.lines.map((line, index) => (
          <View key={line.sourceCurrency} style={styles.currencyRateLegendItem}>
            <View
              style={[
                styles.currencyRateLegendSwatch,
                { backgroundColor: currencyRateLineColor(theme, index) },
              ]}
            />
            <Text
              variant="labelSmall"
              numberOfLines={1}
              style={{ color: theme.colors.onSurfaceVariant }}
            >
              {line.sourceCurrency}
            </Text>
          </View>
        ))}
      </View>
      <View style={styles.trendXAxisRow}>
        <View style={styles.trendXAxisSpacer} />
        <View style={styles.trendXAxisLabels}>
          <Text
            variant="labelSmall"
            numberOfLines={1}
            style={{ color: theme.colors.onSurfaceVariant }}
          >
            {series.startLabel}
          </Text>
          <Text
            variant="labelSmall"
            numberOfLines={1}
            style={{ color: theme.colors.onSurfaceVariant }}
          >
            {series.hasMovement ? `${series.movementCount} changes` : 'No change'}
          </Text>
          <Text
            variant="labelSmall"
            numberOfLines={1}
            style={{ color: theme.colors.onSurfaceVariant }}
          >
            {series.latestLabel}
          </Text>
        </View>
      </View>
    </View>
  );
}

type CurrencyRateTrendPoint = {
  key: string;
  sourceCurrency: string;
  targetCurrency: string;
  timestamp: number;
  label: string;
  fullLabel: string;
  rate: number;
  changeFromPrevious: number;
  changeFromStart: number;
  rateRecordCount: number;
  anchor: boolean;
};

type CurrencyRateTrendLine = {
  sourceCurrency: string;
  targetCurrency: string;
  points: CurrencyRateTrendPoint[];
  plotPoints: CurrencyRateTrendPoint[];
  start: CurrencyRateTrendPoint;
  latest: CurrencyRateTrendPoint;
  hasMovement: boolean;
  movementCount: number;
};

type CurrencyRateTrendSeries = {
  targetCurrency: string;
  lines: CurrencyRateTrendLine[];
  points: CurrencyRateTrendPoint[];
  startLabel: string;
  latestLabel: string;
  rangeStart: number;
  rangeEnd: number;
  hasMovement: boolean;
  movementCount: number;
};

type CurrencyRateAxisTick = { key: string; rate: number; label: string };

type CurrencyRateTrendCoordinate = {
  point: CurrencyRateTrendPoint;
  x: number;
  y: number;
};

type CurrencyRateHistoryPoint = {
  timestamp: number;
  asOfDate: string;
  rates: Record<string, number>;
};

type CurrencyRateHistorySnapshot = {
  baseCurrency: string;
  quoteCurrencies: string[];
  points: CurrencyRateHistoryPoint[];
};

function currencyRateTrendSeriesForPreset(
  state: LedgerStateForWidget,
  sourceCurrencies: string[],
  targetCurrency: string,
  preset: HomeWidgetDatePreset,
  history?: CurrencyRateHistorySnapshot,
): CurrencyRateTrendSeries {
  const target = normalizeCurrencyCode(targetCurrency);
  const sources = uniqueCurrencyCodes(sourceCurrencies).filter((currency) => currency !== target);
  const range = currencyRateRangeForPreset(state, preset, sources[0] ?? target, target);
  const lines = sources
    .map((source) => currencyRateTrendLineForPreset(state, source, target, preset, range, history))
    .filter(isCurrencyRateTrendLine);
  const points = lines.flatMap((line) => line.points);
  const firstLine = lines[0];
  const movementCount = lines.reduce((total, line) => total + line.movementCount, 0);

  return {
    targetCurrency: target,
    lines,
    points,
    startLabel: firstLine?.start.label ?? formatTrendShortLabel(range.start.getTime(), preset),
    latestLabel: firstLine?.latest.label ?? formatTrendShortLabel(range.end.getTime(), preset),
    rangeStart: range.start.getTime(),
    rangeEnd: range.end.getTime(),
    hasMovement: movementCount > 0,
    movementCount,
  };
}

function currencyRateTrendLineForPreset(
  state: LedgerStateForWidget,
  source: string,
  target: string,
  preset: HomeWidgetDatePreset,
  range: { start: Date; end: Date },
  history?: CurrencyRateHistorySnapshot,
): CurrencyRateTrendLine | undefined {
  const currentRate = realRateBetween(state, source, target)?.rate ?? 0;
  const rateRecordTimes = currencyRateRecordTimestamps(
    state,
    source,
    target,
    range.start,
    range.end,
  );
  const historyTimes = currencyRateHistoryTimestamps(history, source, range.start, range.end);
  const timestamps = uniqueSortedNumbers([
    ...trendAnchorTimestamps(range.start, range.end, preset),
    ...historyTimes,
    ...rateRecordTimes,
  ]);
  const points: CurrencyRateTrendPoint[] = [];

  for (const timestamp of timestamps) {
    const savedRate = realRateBetweenAt(state, source, target, timestamp);
    const historicalRate = currencyRateHistoryRateAtOrBefore(history, source, timestamp);
    const rate = savedRate?.rate ?? historicalRate ?? currentRate;
    if (!Number.isFinite(rate) || rate <= 0) continue;
    const previous = points[points.length - 1];
    const first = points[0];
    points.push({
      key: `rate-${source}-${target}-${timestamp}`,
      sourceCurrency: source,
      targetCurrency: target,
      timestamp,
      label: formatTrendShortLabel(timestamp, preset),
      fullLabel: formatTrendFullLabel(timestamp),
      rate,
      changeFromPrevious: previous ? rate - previous.rate : 0,
      changeFromStart: first ? rate - first.rate : 0,
      rateRecordCount: rateRecordTimes.includes(timestamp) ? 1 : 0,
      anchor: !rateRecordTimes.includes(timestamp) && !historyTimes.includes(timestamp),
    });
  }

  if (points.length === 0 && currentRate <= 0) return undefined;
  const fallback = emptyCurrencyRatePoint(source, target, currentRate || 1, preset);
  const safePoints = points.length > 0 ? points : [fallback];
  const latest = safePoints[safePoints.length - 1] ?? fallback;
  const start = safePoints[0] ?? fallback;
  const movementCount = safePoints.filter((point) => Math.abs(point.changeFromPrevious) > 0).length;

  return {
    sourceCurrency: source,
    targetCurrency: target,
    points: safePoints,
    plotPoints: downsampleCurrencyRatePoints(safePoints),
    start,
    latest,
    hasMovement: movementCount > 0,
    movementCount,
  };
}

function isCurrencyRateTrendLine(
  line: CurrencyRateTrendLine | undefined,
): line is CurrencyRateTrendLine {
  return Boolean(line);
}

function smoothCurrencyRateCoordinates(
  coordinates: CurrencyRateTrendCoordinate[],
  minY: number,
  maxY: number,
): CurrencyRateTrendCoordinate[] {
  if (coordinates.length <= 2) return coordinates;
  const smooth: CurrencyRateTrendCoordinate[] = [];
  for (let index = 0; index < coordinates.length - 1; index += 1) {
    const previous = coordinates[Math.max(0, index - 1)] ?? coordinates[index];
    const current = coordinates[index];
    const next = coordinates[index + 1];
    const after = coordinates[Math.min(coordinates.length - 1, index + 2)] ?? next;
    if (!previous || !current || !next || !after) continue;
    if (index === 0) smooth.push(current);
    const distance = Math.max(1, next.x - current.x);
    const steps = clampNumber(Math.ceil(distance / 8), 4, 12);
    for (let step = 1; step <= steps; step += 1) {
      const progress = step / steps;
      smooth.push({
        point: next.point,
        x: current.x + (next.x - current.x) * progress,
        y: clampNumber(catmullRom(previous.y, current.y, next.y, after.y, progress), minY, maxY),
      });
    }
  }
  return smooth;
}

function catmullRom(
  previousValue: number,
  currentValue: number,
  nextValue: number,
  afterValue: number,
  progress: number,
): number {
  const progressSquared = progress * progress;
  const progressCubed = progressSquared * progress;
  return (
    0.5 *
    (2 * currentValue +
      (-previousValue + nextValue) * progress +
      (2 * previousValue - 5 * currentValue + 4 * nextValue - afterValue) * progressSquared +
      (-previousValue + 3 * currentValue - 3 * nextValue + afterValue) * progressCubed)
  );
}

function currencyRateRangeForPreset(
  state: LedgerStateForWidget,
  preset: HomeWidgetDatePreset,
  sourceCurrency: string,
  targetCurrency: string,
): { start: Date; end: Date } {
  const range = dateRangeForPreset(preset);
  const today = new Date();
  let end = range.end ? new Date(range.end) : today;
  if (end.getTime() > today.getTime()) end = today;
  let start = range.start
    ? new Date(range.start)
    : (earliestCurrencyRateDate(state, sourceCurrency, targetCurrency) ??
      new Date(today.getTime() - 30 * 24 * 60 * 60 * 1000));
  if (start.getTime() > end.getTime()) start = new Date(end.getTime() - 24 * 60 * 60 * 1000);
  if (start.getTime() === end.getTime()) end = new Date(start.getTime() + 60 * 60 * 1000);
  return { start, end };
}

function currencyRateHistoryTimestamps(
  history: CurrencyRateHistorySnapshot | undefined,
  sourceCurrency: string,
  start: Date,
  end: Date,
): number[] {
  if (!history) return [];
  const source = normalizeCurrencyCode(sourceCurrency);
  const startTime = start.getTime();
  const endTime = end.getTime();
  return history.points
    .filter(
      (point) =>
        point.timestamp >= startTime &&
        point.timestamp <= endTime &&
        Number.isFinite(point.rates[source]),
    )
    .map((point) => point.timestamp);
}

function currencyRateHistoryRateAtOrBefore(
  history: CurrencyRateHistorySnapshot | undefined,
  sourceCurrency: string,
  timestamp: number,
): number | undefined {
  if (!history) return undefined;
  const source = normalizeCurrencyCode(sourceCurrency);
  let latest: number | undefined;
  for (const point of history.points) {
    if (point.timestamp > timestamp) break;
    const rate = point.rates[source];
    if (typeof rate === 'number' && Number.isFinite(rate) && rate > 0) latest = rate;
  }
  return latest;
}

function useCurrencyRateHistory(
  targetCurrency: string,
  sourceCurrencies: string[],
  preset: HomeWidgetDatePreset,
): { data?: CurrencyRateHistorySnapshot; loading: boolean; error?: string } {
  const request = useMemo(() => {
    const target = normalizeCurrencyCode(targetCurrency);
    const sources = uniqueCurrencyCodes(sourceCurrencies).filter((currency) => currency !== target);
    if (sources.length === 0) return undefined;
    const range = currencyRateHistoryRangeForPreset(preset);
    return {
      key: `${target}:${sources.join(',')}:${isoDateOnly(range.start)}:${isoDateOnly(range.end)}`,
      target,
      sources,
      startDate: isoDateOnly(range.start),
      endDate: isoDateOnly(range.end),
    };
  }, [preset, sourceCurrencies, targetCurrency]);
  const [state, setState] = useState<{
    key?: string;
    data?: CurrencyRateHistorySnapshot;
    loading: boolean;
    error?: string;
  }>({ loading: false });

  useEffect(() => {
    if (!request) {
      setState({ loading: false });
      return;
    }
    let cancelled = false;
    setState((current) => ({ ...current, key: request.key, loading: true, error: undefined }));

    const load = async () => {
      try {
        const response = await fetch(
          `https://api.frankfurter.app/${encodeURIComponent(request.startDate)}..${encodeURIComponent(
            request.endDate,
          )}?from=${encodeURIComponent(request.target)}&to=${encodeURIComponent(
            request.sources.join(','),
          )}`,
        );
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const payload = (await response.json()) as {
          rates?: Record<string, Record<string, number>>;
        };
        const points = Object.entries(payload.rates ?? {})
          .map(([asOfDate, rates]) => {
            const invertedRates: Record<string, number> = {};
            for (const source of request.sources) {
              const targetToSource = rates?.[source];
              if (
                typeof targetToSource === 'number' &&
                Number.isFinite(targetToSource) &&
                targetToSource > 0
              ) {
                invertedRates[source] = 1 / targetToSource;
              }
            }
            return {
              timestamp: Date.parse(`${asOfDate}T00:00:00.000Z`),
              asOfDate,
              rates: invertedRates,
            };
          })
          .filter(
            (point) => Number.isFinite(point.timestamp) && Object.keys(point.rates).length > 0,
          )
          .sort((left, right) => left.timestamp - right.timestamp);

        if (!cancelled) {
          setState({
            key: request.key,
            loading: false,
            data: {
              baseCurrency: request.target,
              quoteCurrencies: request.sources,
              points,
            },
          });
        }
      } catch (error) {
        if (!cancelled) {
          setState({
            key: request.key,
            data: undefined,
            loading: false,
            error: error instanceof Error ? error.message : 'Could not load rate history',
          });
        }
      }
    };

    void load();
    return () => {
      cancelled = true;
    };
  }, [request]);

  if (!request || state.key === request.key) return state;
  return { loading: true, data: state.data };
}

function currencyRateHistoryRangeForPreset(preset: HomeWidgetDatePreset): {
  start: Date;
  end: Date;
} {
  const range = dateRangeForPreset(preset);
  const today = new Date();
  let end = range.end ? new Date(range.end) : today;
  if (end.getTime() > today.getTime()) end = today;
  let start = range.start
    ? new Date(range.start)
    : new Date(end.getTime() - 30 * 24 * 60 * 60 * 1000);
  if (start.getTime() > end.getTime()) start = new Date(end.getTime() - 24 * 60 * 60 * 1000);
  return { start, end };
}

function isoDateOnly(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function currencyRateRecordTimestamps(
  state: LedgerStateForWidget,
  sourceCurrency: string,
  targetCurrency: string,
  start: Date,
  end: Date,
): number[] {
  const startTime = start.getTime();
  const endTime = end.getTime();
  const pivots = new Set([sourceCurrency, targetCurrency, ...realRatePivotCurrencies(state)]);
  return uniqueSortedNumbers(
    state.exchangeRates
      .filter((rate) => {
        if (!isRealExchangeRateRecord(rate)) return false;
        const base = normalizeCurrencyCode(rate.base);
        const quote = normalizeCurrencyCode(rate.quote);
        if (!pivots.has(base) || !pivots.has(quote)) return false;
        const timestamp = exchangeRateTimestamp(rate);
        return timestamp >= startTime && timestamp <= endTime;
      })
      .map(exchangeRateTimestamp),
  );
}

function earliestCurrencyRateDate(
  state: LedgerStateForWidget,
  sourceCurrency: string,
  targetCurrency: string,
): Date | undefined {
  const timestamps = currencyRateRecordTimestamps(
    state,
    sourceCurrency,
    targetCurrency,
    new Date(0),
    new Date(),
  );
  const first = timestamps[0];
  return first !== undefined ? new Date(first) : undefined;
}

function realRateBetweenAt(
  state: LedgerStateForWidget,
  sourceCurrency: string,
  targetCurrency: string,
  timestamp: number,
): { rate: number; asOfDate?: string } | undefined {
  if (sourceCurrency === targetCurrency) return { rate: 1 };
  const directRate = directRealRateBetweenAt(state, sourceCurrency, targetCurrency, timestamp);
  if (directRate) return directRate;

  for (const pivot of realRatePivotCurrencies(state)) {
    if (pivot === sourceCurrency || pivot === targetCurrency) continue;
    const sourceToPivot = directRealRateBetweenAt(state, sourceCurrency, pivot, timestamp);
    if (!sourceToPivot) continue;
    const pivotToTarget = directRealRateBetweenAt(state, pivot, targetCurrency, timestamp);
    if (!pivotToTarget) continue;
    return {
      rate: sourceToPivot.rate * pivotToTarget.rate,
      asOfDate:
        sourceToPivot.asOfDate === pivotToTarget.asOfDate ? sourceToPivot.asOfDate : undefined,
    };
  }
  return undefined;
}

function directRealRateBetweenAt(
  state: LedgerStateForWidget,
  sourceCurrency: string,
  targetCurrency: string,
  timestamp: number,
): { rate: number; asOfDate?: string } | undefined {
  const direct = latestRealExchangeRateAt(state, sourceCurrency, targetCurrency, timestamp);
  const inverse = latestRealExchangeRateAt(state, targetCurrency, sourceCurrency, timestamp);
  if (!direct && !inverse) return undefined;
  if (direct && (!inverse || exchangeRateTimestamp(direct) >= exchangeRateTimestamp(inverse))) {
    return { rate: direct.rate, asOfDate: direct.asOfDate };
  }
  if (inverse && inverse.rate !== 0) return { rate: 1 / inverse.rate, asOfDate: inverse.asOfDate };
  return undefined;
}

function latestRealExchangeRateAt(
  state: LedgerStateForWidget,
  baseCurrency: string,
  quoteCurrency: string,
  timestamp: number,
): ExchangeRateForWidget | undefined {
  return state.exchangeRates
    .filter(
      (rate) =>
        isRealExchangeRateRecord(rate) &&
        exchangeRateTimestamp(rate) <= timestamp &&
        normalizeCurrencyCode(rate.base) === normalizeCurrencyCode(baseCurrency) &&
        normalizeCurrencyCode(rate.quote) === normalizeCurrencyCode(quoteCurrency),
    )
    .sort((left, right) => exchangeRateTimestamp(right) - exchangeRateTimestamp(left))[0];
}

function currencyRateAxisTicks(
  points: CurrencyRateTrendPoint[],
  targetCurrency: string,
  locale: string,
): CurrencyRateAxisTick[] {
  const values = points.length > 0 ? points.map((point) => point.rate) : [0];
  const rawMin = Math.min(...values);
  const rawMax = Math.max(...values);
  const rawRange = Math.max(Number.EPSILON, rawMax - rawMin);
  const pad = rawMin === rawMax ? Math.max(Math.abs(rawMin) * 0.08, 0.0001) : rawRange * 0.12;
  const chartMin = Math.max(0, rawMin - pad);
  const chartMax = rawMax + pad;
  const step = niceRateStep((chartMax - chartMin) / 4);
  const axisMin = Math.max(0, Math.floor(chartMin / step) * step);
  const axisMax = Math.ceil(chartMax / step) * step;
  const ticks: CurrencyRateAxisTick[] = [];
  for (let value = axisMin; value <= axisMax + step / 2 && ticks.length < 7; value += step) {
    const rate = Number(value.toPrecision(12));
    ticks.push({
      key: `rate-axis-${rate}`,
      rate,
      label: formatRateAxisLabel(rate, targetCurrency, locale),
    });
  }
  return ticks.length >= 2
    ? ticks
    : [
        { key: 'rate-axis-0', rate: 0, label: formatRateAxisLabel(0, targetCurrency, locale) },
        {
          key: 'rate-axis-1',
          rate: step,
          label: formatRateAxisLabel(step, targetCurrency, locale),
        },
      ];
}

function niceRateStep(value: number): number {
  const safeValue = Math.max(Number.EPSILON, Math.abs(value));
  const exponent = Math.floor(Math.log10(safeValue));
  const base = Math.pow(10, exponent);
  const fraction = safeValue / base;
  const niceFraction = fraction <= 1 ? 1 : fraction <= 2 ? 2 : fraction <= 5 ? 5 : 10;
  return niceFraction * base;
}

function downsampleCurrencyRatePoints(points: CurrencyRateTrendPoint[]): CurrencyRateTrendPoint[] {
  if (points.length <= TREND_MAX_PLOT_POINTS) return points;
  const first = points[0];
  const last = points[points.length - 1];
  if (!first || !last) return points;
  const keep = new Set<string>([first.key, last.key]);
  const movers = [...points]
    .sort((left, right) => Math.abs(right.changeFromPrevious) - Math.abs(left.changeFromPrevious))
    .slice(0, Math.floor(TREND_MAX_PLOT_POINTS * 0.3));
  movers.forEach((point) => keep.add(point.key));
  const remainingSlots = Math.max(1, TREND_MAX_PLOT_POINTS - keep.size);
  const stride = Math.max(1, (points.length - 1) / remainingSlots);
  for (let index = 0; index < points.length; index += stride) {
    const point = points[Math.round(index)];
    if (point) keep.add(point.key);
  }
  return points.filter((point) => keep.has(point.key)).slice(0, TREND_MAX_PLOT_POINTS);
}

function nearestCurrencyRatePoint(
  points: CurrencyRateTrendPoint[],
  timestamp: number,
): CurrencyRateTrendPoint {
  if (points.length === 0) return emptyCurrencyRatePoint('INR', 'USD', 1, 'thisMonth');
  let low = 0;
  let high = points.length - 1;
  while (low < high) {
    const mid = Math.floor((low + high) / 2);
    const midpoint = points[mid];
    if (!midpoint) break;
    if (midpoint.timestamp < timestamp) low = mid + 1;
    else high = mid;
  }
  const next =
    points[low] ??
    points[points.length - 1] ??
    emptyCurrencyRatePoint('INR', 'USD', 1, 'thisMonth');
  const previous = points[Math.max(0, low - 1)] ?? next;
  return Math.abs((previous?.timestamp ?? 0) - timestamp) <= Math.abs(next.timestamp - timestamp)
    ? previous
    : next;
}

function emptyCurrencyRatePoint(
  sourceCurrency: string,
  targetCurrency: string,
  rate: number,
  preset: HomeWidgetDatePreset,
): CurrencyRateTrendPoint {
  const now = Date.now();
  return {
    key: `empty-rate-${sourceCurrency}-${targetCurrency}`,
    sourceCurrency,
    targetCurrency,
    timestamp: now,
    label: formatTrendShortLabel(now, preset),
    fullLabel: formatTrendFullLabel(now),
    rate: Math.max(Number.EPSILON, rate),
    changeFromPrevious: 0,
    changeFromStart: 0,
    rateRecordCount: 0,
    anchor: true,
  };
}

function initialCurrencyConverterCodes(state: LedgerStateForWidget): string[] {
  return enabledCurrencyCodesForWidget(state).slice(0, 4);
}

function currencyRateChartSourceCurrencies(
  state: LedgerStateForWidget,
  converterCurrencies: string[],
  defaultCurrency: string,
): string[] {
  const enabled = new Set(enabledCurrencyCodesForWidget(state));
  return uniqueCurrencyCodes(converterCurrencies)
    .filter((currency) => enabled.has(currency))
    .filter((currency) => currency !== normalizeCurrencyCode(defaultCurrency))
    .slice(0, 4);
}

function currencyValuePickerOptions(
  state: LedgerStateForWidget,
  selectedCurrencies: string[],
): OptionListItem[] {
  const selected = new Set(selectedCurrencies.map(normalizeCurrencyCode));
  const enabled = new Set(enabledCurrencyCodesForWidget(state));
  const currencies = enabledCurrencyCodesForWidget(state);
  return currencies.map((currency) => {
    const definition = currencyDefinition(currency);
    return {
      value: currency,
      label: currency,
      description: definition.label,
      icon: currencyIcon(currency),
      disabled: selected.has(currency) || !enabled.has(currency),
    };
  });
}

function enabledCurrencyCodesForWidget(state: LedgerStateForWidget): string[] {
  return uniqueCurrencyCodes(enabledCurrencies(state));
}

function sameCurrencyCodes(left: string[], right: string[]): boolean {
  return left.length === right.length && left.every((currency, index) => currency === right[index]);
}

function convertedCurrencyInputValue(
  state: LedgerStateForWidget,
  sourceValue: string,
  sourceCurrency: string,
  targetCurrency: string,
): string {
  if (sourceValue.trim() === '' || sourceValue === '.') return '';
  const amount = parseCurrencyInput(sourceValue);
  if (!Number.isFinite(amount)) return '';
  const rate = realRateBetween(state, sourceCurrency, targetCurrency);
  if (!rate) return '';
  const converted = amount * rate.rate;
  return formatPlainCurrencyNumber(converted, targetCurrency);
}

function currencyRateLabel(
  state: LedgerStateForWidget,
  sourceCurrency: string,
  targetCurrency: string,
  locale: string,
): string {
  if (sourceCurrency === targetCurrency) return 'Active input';
  const rate = realRateBetween(state, sourceCurrency, targetCurrency);
  if (!rate) return `No saved rate for ${sourceCurrency} to ${targetCurrency}`;
  const money = decimalToMoney(rate.rate, targetCurrency);
  const dateSuffix = rate.asOfDate ? ` · ${rate.asOfDate}` : '';
  return `1 ${sourceCurrency} = ${formatMoney(money, locale)}${dateSuffix}`;
}

function hasRealExplicitRate(
  state: LedgerStateForWidget,
  sourceCurrency: string,
  targetCurrency: string,
): boolean {
  return Boolean(realRateBetween(state, sourceCurrency, targetCurrency));
}

function realRateBetween(
  state: LedgerStateForWidget,
  sourceCurrency: string,
  targetCurrency: string,
): { rate: number; asOfDate?: string } | undefined {
  const normalizedSource = normalizeCurrencyCode(sourceCurrency);
  const normalizedTarget = normalizeCurrencyCode(targetCurrency);
  if (normalizedSource === normalizedTarget) return { rate: 1 };

  const directRate = directRealRateBetween(state, normalizedSource, normalizedTarget);
  if (directRate) return directRate;

  for (const pivot of realRatePivotCurrencies(state)) {
    if (pivot === normalizedSource || pivot === normalizedTarget) continue;
    const sourceToPivot = directRealRateBetween(state, normalizedSource, pivot);
    if (!sourceToPivot) continue;
    const pivotToTarget = directRealRateBetween(state, pivot, normalizedTarget);
    if (!pivotToTarget) continue;
    return {
      rate: sourceToPivot.rate * pivotToTarget.rate,
      asOfDate:
        sourceToPivot.asOfDate === pivotToTarget.asOfDate ? sourceToPivot.asOfDate : undefined,
    };
  }

  return undefined;
}

function directRealRateBetween(
  state: LedgerStateForWidget,
  normalizedSource: string,
  normalizedTarget: string,
): { rate: number; asOfDate?: string } | undefined {
  const direct = latestRealExchangeRate(state, normalizedSource, normalizedTarget);
  const inverse = latestRealExchangeRate(state, normalizedTarget, normalizedSource);
  if (!direct && !inverse) return undefined;
  if (direct && (!inverse || exchangeRateTimestamp(direct) >= exchangeRateTimestamp(inverse))) {
    return { rate: direct.rate, asOfDate: direct.asOfDate };
  }
  if (inverse && inverse.rate !== 0) return { rate: 1 / inverse.rate, asOfDate: inverse.asOfDate };
  return undefined;
}

function realRatePivotCurrencies(state: LedgerStateForWidget): string[] {
  const currencies = new Set<string>();
  currencies.add(normalizeCurrencyCode(state.preferences.baseCurrency));
  for (const rate of state.exchangeRates) {
    currencies.add(normalizeCurrencyCode(rate.base));
    currencies.add(normalizeCurrencyCode(rate.quote));
  }
  return Array.from(currencies).filter(Boolean);
}

function latestRealExchangeRate(
  state: LedgerStateForWidget,
  baseCurrency: string,
  quoteCurrency: string,
): ExchangeRateForWidget | undefined {
  return state.exchangeRates
    .filter(
      (rate) =>
        isRealExchangeRateRecord(rate) &&
        normalizeCurrencyCode(rate.base) === normalizeCurrencyCode(baseCurrency) &&
        normalizeCurrencyCode(rate.quote) === normalizeCurrencyCode(quoteCurrency),
    )
    .sort((left, right) => exchangeRateTimestamp(right) - exchangeRateTimestamp(left))[0];
}

function isRealExchangeRateRecord(rate: ExchangeRateForWidget): boolean {
  return Number.isFinite(rate.rate) && rate.rate > 0;
}

function exchangeRateTimestamp(rate: ExchangeRateForWidget): number {
  const parsed = Date.parse(rate.updatedAt ?? rate.asOfDate);
  return Number.isFinite(parsed) ? parsed : 0;
}

function currencyIcon(currency: string) {
  return resolveAppIconName(currencyDefinition(currency).icon, 'currency-usd');
}

function decimalToMoney(value: number, currency: string): Money {
  return { amountMinor: toMinor(Number.isFinite(value) ? value : 0, currency), currency };
}

function sanitizeCurrencyInput(value: string): string {
  const normalized = value.replace(/,/g, '.').replace(/[^\d.]/g, '');
  const [whole = '', ...rest] = normalized.split('.');
  const fraction = rest.join('');
  return rest.length > 0 ? `${whole}.${fraction}` : whole;
}

function parseCurrencyInput(value: string): number {
  if (value.trim() === '' || value === '.') return 0;
  const parsed = Number(value.replace(/,/g, '.'));
  return Number.isFinite(parsed) ? parsed : Number.NaN;
}

function positiveCurrencyInputValue(value: string): number {
  const parsed = parseCurrencyInput(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
}

function formatPlainCurrencyNumber(value: number, currency: string): string {
  if (!Number.isFinite(value)) return '';
  const absolute = Math.abs(value);
  const decimals = absolute >= 100 ? 2 : absolute >= 1 ? minorUnitsFor(currency) : 6;
  return trimTrailingZeros(value.toFixed(decimals));
}

function formatRateDisplay(value: number, currency: string, locale: string): string {
  const definition = currencyDefinition(currency);
  return `${definition.symbol}${formatRateNumber(value, locale)} ${definition.code}`;
}

function formatRateDelta(value: number, currency: string, locale: string): string {
  const sign = value >= 0 ? '+' : '-';
  return `${sign}${formatRateDisplay(Math.abs(value), currency, locale)}`;
}

function formatRateAxisLabel(value: number, currency: string, locale: string): string {
  return `${currencyDefinition(currency).symbol}${formatRateNumber(value, locale)}`;
}

function currencyRateLineColor(theme: MD3Theme, index: number): string {
  const palette = [
    theme.colors.primary,
    tokens.color.md3Positive,
    theme.colors.tertiary,
    '#C47F00',
    theme.colors.secondary,
  ];
  return palette[index % palette.length] ?? theme.colors.primary;
}

function formatRateNumber(value: number, locale: string): string {
  if (!Number.isFinite(value)) return '0';
  const absolute = Math.abs(value);
  return new Intl.NumberFormat(locale, {
    notation: absolute >= 10000 ? 'compact' : 'standard',
    maximumFractionDigits: absolute >= 100 ? 2 : absolute >= 1 ? 4 : 6,
  }).format(value);
}

function trimTrailingZeros(value: string): string {
  return value.replace(/\.0+$/, '').replace(/(\.\d*?)0+$/, '$1');
}

function uniqueCurrencyCodes(values: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const value of values) {
    const normalized = normalizeCurrencyCode(value);
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    result.push(normalized);
  }
  return result;
}

function uniqueSortedNumbers(values: number[]): number[] {
  return Array.from(new Set(values.filter(Number.isFinite))).sort((left, right) => left - right);
}

function currencyOptionForCode(currency: string): OptionListItem {
  const definition = currencyDefinition(currency);
  return {
    value: definition.code,
    label: definition.code,
    description: definition.label,
    icon: resolveAppIconName(definition.icon, 'currency-usd'),
  };
}

function BudgetPressureWidget({ size, datePreset, onDatePresetChange }: WidgetShellProps) {
  const { state, selectors } = useLedger();
  const budgets = useMemo(
    () =>
      selectors
        .budgetStatuses(state)
        .sort((left, right) => right.share - left.share)
        .slice(0, 4),
    [selectors, state],
  );

  return (
    <HomeWidgetShell
      {...HOME_WIDGET_META.budgetPressure}
      size={size}
      datePreset={datePreset}
      onDatePresetChange={onDatePresetChange}
      actionLabel="Planner"
      onAction={() => router.push('/(tabs)/planner' as never)}
    >
      {budgets.length === 0 ? (
        <WidgetEmpty text="No budgets yet." />
      ) : (
        budgets.map((budget) => (
          <BarRow
            key={budget.budgetId}
            label={budget.name}
            value={`${Math.round(budget.share * 100)}%`}
            progress={budget.share}
            color={budget.isOver ? tokens.color.md3Danger : tokens.color.md3Primary}
          />
        ))
      )}
    </HomeWidgetShell>
  );
}

function GoalProgressWidget({ size, datePreset, onDatePresetChange }: WidgetShellProps) {
  const { state, selectors } = useLedger();
  const viewCurrency = selectors.displayCurrency(state);
  const goals = useMemo(() => selectors.goalStatuses(state).slice(0, 4), [selectors, state]);

  return (
    <HomeWidgetShell
      {...HOME_WIDGET_META.goalProgress}
      size={size}
      datePreset={datePreset}
      onDatePresetChange={onDatePresetChange}
      actionLabel="Planner"
      onAction={() => router.push('/(tabs)/planner' as never)}
    >
      {goals.length === 0 ? (
        <WidgetEmpty text="No goals yet." />
      ) : (
        goals.map((goal) => (
          <BarRow
            key={goal.goalId}
            label={goal.name}
            value={`${Math.round(goal.share * 100)}%`}
            progress={goal.share}
            color={tokens.color.md3Positive}
            subvalue={
              goal.monthlyRequired
                ? `${formatMoney(
                    selectors.convertMoneyForDisplay(state, goal.monthlyRequired, viewCurrency),
                    state.preferences.locale,
                  )} / mo`
                : undefined
            }
          />
        ))
      )}
    </HomeWidgetShell>
  );
}

function CurrencyExposureWidget({
  size,
  datePreset,
  onDatePresetChange,
  selectedAccountId,
}: WidgetShellProps) {
  const { state, indexes, selectors } = useLedger();
  const viewCurrency = selectors.displayCurrency(state);
  const rows = state.accounts
    .filter(
      (account) =>
        !account.isArchived &&
        account.includeInTotals &&
        account.currency !== state.preferences.baseCurrency &&
        (!selectedAccountId || account.id === selectedAccountId),
    )
    .map((account) => ({ account, balance: balanceForAccount(indexes, account) }));

  return (
    <HomeWidgetShell
      {...HOME_WIDGET_META.currencyExposure}
      size={size}
      datePreset={datePreset}
      onDatePresetChange={onDatePresetChange}
    >
      {rows.length === 0 ? (
        <WidgetEmpty text="No non-base currency accounts." />
      ) : (
        rows.map(({ account, balance }, index) => (
          <View key={account.id}>
            <InfoLine
              icon="currency-gbp"
              label={account.name}
              value={formatMoney(balance, state.preferences.locale)}
              subvalue={
                balance.currency !== viewCurrency
                  ? formatMoney(
                      selectors.convertMoneyForDisplay(state, balance, viewCurrency),
                      state.preferences.locale,
                    )
                  : undefined
              }
            />
            {index < rows.length - 1 ? <Divider /> : null}
          </View>
        ))
      )}
    </HomeWidgetShell>
  );
}

type AccountTileProps = {
  accountId: string;
  accountName: string;
  accountIcon: ReturnType<typeof resolveAppIconName>;
  balanceLabel: string;
  cashCurrencyBreakdown?: CashCurrencyBreakdownItem[];
  compact: boolean;
  color: string;
  contentColor: string;
  convertedBalanceLabel?: string;
  iconBackgroundColor: string;
  iconColor: string;
  selected: boolean;
  dimmed: boolean;
  onPressAccount: (accountId: string) => void;
};

function AccountTile({
  accountId,
  accountName,
  accountIcon,
  balanceLabel,
  cashCurrencyBreakdown,
  compact,
  color,
  contentColor,
  convertedBalanceLabel,
  iconBackgroundColor,
  iconColor,
  selected,
  onPressAccount,
}: AccountTileProps) {
  const handlePress = useCallback(() => onPressAccount(accountId), [accountId, onPressAccount]);
  const cashBreakdownLabel = cashCurrencyBreakdown
    ?.map(cashCurrencyInlineLabel)
    .join(' | ');
  const secondaryBalanceLabel = [convertedBalanceLabel, cashBreakdownLabel]
    .filter(Boolean)
    .join(' | ');
  const accessibilityLabel = [accountName, balanceLabel, secondaryBalanceLabel]
    .filter(Boolean)
    .join(', ');

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      style={({ pressed }) => [
        styles.accountTile,
        compact && styles.accountTileCompact,
        { backgroundColor: color },
        selected && [styles.selectedAccountTile, { borderColor: contentColor }],
        pressed && styles.pressedAccountTile,
      ]}
      onPress={handlePress}
    >
      <View style={styles.accountTileContent}>
        <View style={styles.accountTopLine}>
          <View style={[styles.accountIcon, { backgroundColor: iconBackgroundColor }]}>
            <MaterialCommunityIcons name={accountIcon} size={16} color={iconColor} />
          </View>
          <View style={styles.fill}>
            <Text
              variant="labelSmall"
              numberOfLines={1}
              ellipsizeMode="tail"
              style={[styles.tileName, { color: contentColor }]}
            >
              {accountName}
            </Text>
          </View>
        </View>
        <Text
          variant="labelMedium"
          numberOfLines={1}
          adjustsFontSizeToFit
          minimumFontScale={0.72}
          style={[styles.accountBalance, { color: contentColor }]}
        >
          {balanceLabel}
        </Text>
        {secondaryBalanceLabel ? (
          <Text
            variant="labelSmall"
            numberOfLines={1}
            adjustsFontSizeToFit
            minimumFontScale={0.72}
            style={[styles.accountSecondaryBalance, { color: contentColor }]}
          >
            {secondaryBalanceLabel}
          </Text>
        ) : null}
      </View>
    </Pressable>
  );
}

const MemoizedAccountTile = memo(
  AccountTile,
  (previous, next) =>
    previous.accountId === next.accountId &&
    previous.accountName === next.accountName &&
    previous.accountIcon === next.accountIcon &&
    previous.balanceLabel === next.balanceLabel &&
    previous.cashCurrencyBreakdown === next.cashCurrencyBreakdown &&
    previous.compact === next.compact &&
    previous.color === next.color &&
    previous.contentColor === next.contentColor &&
    previous.convertedBalanceLabel === next.convertedBalanceLabel &&
    previous.iconBackgroundColor === next.iconBackgroundColor &&
    previous.iconColor === next.iconColor &&
    previous.selected === next.selected &&
    previous.dimmed === next.dimmed &&
    previous.onPressAccount === next.onPressAccount,
);

type TransactionRowSide = TransactionAmountRowSide;
type TransactionDisplayRow = { transaction: Transaction; side: TransactionRowSide };

function TransactionList({
  records,
  scheduled,
  selectedAccountId,
}: {
  records: Transaction[];
  scheduled?: boolean;
  selectedAccountId?: string;
}) {
  const openTransaction = useCallback((transaction: Transaction) => {
    if (transaction.id.startsWith('home-forecast:') && transaction.recurringTemplateId) {
      router.push(`/recurring/${transaction.recurringTemplateId}` as never);
      return;
    }
    router.push(`/transaction/${transaction.id}` as never);
  }, []);

  return (
    <View style={styles.listStack}>
      {records.map((record, index) => {
        const rows = displayRowsForTransaction(record, selectedAccountId);
        return (
          <View key={record.id}>
            <View style={TRANSFER_TYPES.has(record.type) ? styles.transferPair : undefined}>
              {rows.map((row) => (
                <TransactionRecordRow
                  key={`${record.id}-${row.side}`}
                  row={row}
                  scheduled={scheduled}
                  onOpenTransaction={openTransaction}
                />
              ))}
            </View>
            {index < records.length - 1 ? <Divider /> : null}
          </View>
        );
      })}
    </View>
  );
}

const TransactionRecordRow = memo(function TransactionRecordRow({
  row,
  scheduled,
  onOpenTransaction,
}: {
  row: TransactionDisplayRow;
  scheduled?: boolean;
  onOpenTransaction: (transaction: Transaction) => void;
}) {
  const theme = useTheme();
  const { state, indexes } = useLedger();
  const { transaction, side } = row;
  const account = indexes.accountsById.get(transaction.accountId);
  const counterAccount = transaction.counterAccountId
    ? indexes.accountsById.get(transaction.counterAccountId)
    : undefined;
  const category = transaction.categoryId
    ? indexes.categoriesById.get(transaction.categoryId)
    : undefined;
  const color = transactionRowColor(transaction, side, theme);
  const categoryVisual = category
    ? resolveCategoryIconVisual(category, state.categories)
    : undefined;
  const icon = scheduled
    ? 'calendar-clock-outline'
    : (categoryVisual?.icon ??
      resolveAppIconName(category?.icon, transactionRowIcon(transaction, side)));
  const fallbackIconSurface = iconSurfaceForThemeTone(
    theme,
    scheduled ? 'plan' : transactionRowIconTone(transaction, side),
  );
  const iconBackgroundColor =
    categoryVisual?.backgroundColor ?? fallbackIconSurface.backgroundColor;
  const iconColor = categoryVisual?.iconColor ?? fallbackIconSurface.iconColor;
  const title = useMemo(
    () => transactionRowTitle(transaction, side, state.categories, account, counterAccount),
    [account, counterAccount, side, state.categories, transaction],
  );
  const note = transaction.notes?.trim();
  const accountLine = useMemo(
    () => transactionRowMeta(transaction, side, account, counterAccount),
    [account, counterAccount, side, transaction],
  );
  const dateLabel = useMemo(
    () => formatRelativeTransactionDate(transaction.occurredAt),
    [transaction.occurredAt],
  );
  const amountDisplay = useMemo(
    () => transactionAmountDisplay(transaction, side, state, state.preferences.locale),
    [side, state, transaction],
  );
  const openRow = useCallback(
    () => onOpenTransaction(transaction),
    [onOpenTransaction, transaction],
  );

  return (
    <TouchableRipple onPress={openRow} borderless style={styles.recordRowRipple}>
      <View style={[styles.recordRow, side === 'transferIn' && styles.linkedTransferRow]}>
        <View style={[styles.recordIcon, { backgroundColor: iconBackgroundColor }]}>
          <MaterialCommunityIcons name={icon} size={19} color={iconColor} />
        </View>
        <View style={styles.recordCopy}>
          <Text variant="bodyMedium" numberOfLines={1} style={styles.recordTitle}>
            {title}
          </Text>
          <Text
            variant="labelSmall"
            numberOfLines={1}
            style={[styles.mutedText, { color: theme.colors.onSurfaceVariant }]}
          >
            {accountLine}
          </Text>
          {note ? (
            <Text
              variant="labelSmall"
              numberOfLines={1}
              style={[styles.mutedText, { color: theme.colors.onSurfaceVariant }]}
            >
              {note}
            </Text>
          ) : null}
        </View>
        <View style={styles.recordAmountWrap}>
          <Text
            variant="bodyMedium"
            numberOfLines={1}
            adjustsFontSizeToFit
            minimumFontScale={0.65}
            style={[styles.recordAmount, { color }]}
          >
            {amountDisplay.primary}
          </Text>
          {amountDisplay.secondary.map((secondaryAmount) => (
            <Text
              key={secondaryAmount}
              variant="labelSmall"
              numberOfLines={1}
              adjustsFontSizeToFit
              minimumFontScale={0.65}
              style={[styles.recordSecondaryAmount, { color: theme.colors.onSurfaceVariant }]}
            >
              {secondaryAmount}
            </Text>
          ))}
          <Text
            variant="labelSmall"
            numberOfLines={1}
            style={[styles.recordDate, { color: theme.colors.onSurfaceVariant }]}
          >
            {dateLabel}
          </Text>
        </View>
      </View>
    </TouchableRipple>
  );
});

function transactionMatchesAccount(transaction: Transaction, selectedAccountId?: string): boolean {
  return (
    !selectedAccountId ||
    transaction.accountId === selectedAccountId ||
    transaction.counterAccountId === selectedAccountId
  );
}

function displayRowsForTransaction(
  transaction: Transaction,
  selectedAccountId?: string,
): TransactionDisplayRow[] {
  if (!TRANSFER_TYPES.has(transaction.type)) return [{ transaction, side: 'single' }];
  if (selectedAccountId) {
    if (transaction.accountId === selectedAccountId) return [{ transaction, side: 'transferOut' }];
    if (transaction.counterAccountId === selectedAccountId)
      return [{ transaction, side: 'transferIn' }];
  }
  return [
    { transaction, side: 'transferOut' },
    { transaction, side: 'transferIn' },
  ];
}

function transactionRowColor(
  transaction: Transaction,
  side: TransactionRowSide,
  theme: MD3Theme,
): string {
  if (side === 'transferOut') return theme.colors.error;
  if (side === 'transferIn') return positiveAmountColor(theme.dark);
  if (TRANSFER_TYPES.has(transaction.type)) return theme.colors.primary;
  if (INFLOW_TYPES.has(transaction.type)) return positiveAmountColor(theme.dark);
  if (OUTFLOW_TYPES.has(transaction.type)) return theme.colors.error;
  return signedTransactionAmount(transaction) < 0
    ? theme.colors.error
    : positiveAmountColor(theme.dark);
}

function transactionRowIcon(transaction: Transaction, side: TransactionRowSide) {
  if (side === 'transferOut') return 'arrow-up-right';
  if (side === 'transferIn') return 'arrow-down-left';
  return transactionIcon(transaction.type);
}

function transactionRowIconTone(
  transaction: Transaction,
  side: TransactionRowSide,
): IconSurfaceTone {
  if (side === 'transferOut' || side === 'transferIn') return 'transfer';
  return transactionTypeIconTone(transaction.type);
}

function transactionRowTitle(
  transaction: Transaction,
  side: TransactionRowSide,
  categories: ReturnType<typeof useLedger>['state']['categories'],
  account?: Account,
  counterAccount?: Account,
): string {
  if (side === 'transferOut') return `Transfer to ${counterAccount?.name ?? 'account'}`;
  if (side === 'transferIn') return `Transfer from ${account?.name ?? 'account'}`;
  return categoryBreadcrumb(categories, transaction.categoryId) ?? typeLabel(transaction.type);
}

function transactionRowMeta(
  transaction: Transaction,
  side: TransactionRowSide,
  account?: Account,
  counterAccount?: Account,
): string {
  if (side === 'transferOut') return `from ${account?.name ?? 'account'}`;
  if (side === 'transferIn') return `to ${counterAccount?.name ?? 'account'}`;
  if (TRANSFER_TYPES.has(transaction.type)) {
    return `${account?.name ?? 'account'} to ${counterAccount?.name ?? 'account'}`;
  }
  return account?.name ?? 'Missing account';
}

function formatRelativeTransactionDate(value: string): string {
  return formatRecordDateLabel(value);
}

function startOfToday(): Date {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), now.getDate());
}

function addMonths(date: Date, months: number): Date {
  return new Date(date.getFullYear(), date.getMonth() + months, date.getDate());
}

function dayOffsetFromToday(value: string): number {
  const due = new Date(value);
  if (Number.isNaN(due.getTime())) return 0;
  const today = startOfToday();
  const dueDay = new Date(due.getFullYear(), due.getMonth(), due.getDate());
  return Math.round((dueDay.getTime() - today.getTime()) / 86400000);
}

function scheduledTransactionsWithinDays(
  transactions: Transaction[],
  days: number,
  selectedAccountId?: string,
): Transaction[] {
  const start = startOfToday();
  const end = new Date(start);
  end.setDate(end.getDate() + days + 1);
  return transactions
    .filter((transaction) => transaction.status === 'scheduled')
    .filter((transaction) => transactionMatchesAccount(transaction, selectedAccountId))
    .filter((transaction) => {
      const due = new Date(transaction.occurredAt);
      return !Number.isNaN(due.getTime()) && due >= start && due < end;
    })
    .sort((left, right) => left.occurredAt.localeCompare(right.occurredAt));
}

function MoneyMetric({
  label,
  value,
  locale,
  tone,
}: {
  label: string;
  value: Money;
  locale: string;
  tone: 'positive' | 'danger';
}) {
  const theme = useTheme();
  const color = tone === 'positive' ? positiveAmountColor(theme.dark) : theme.colors.error;

  return (
    <Surface
      style={[styles.moneyMetric, { backgroundColor: theme.colors.elevation.level2 }]}
      elevation={0}
    >
      <Text
        variant="labelSmall"
        style={[styles.mutedText, { color: theme.colors.onSurfaceVariant }]}
      >
        {label}
      </Text>
      <Text
        variant="labelLarge"
        numberOfLines={1}
        adjustsFontSizeToFit
        minimumFontScale={0.7}
        style={{ color }}
      >
        {formatMoney(value, locale)}
      </Text>
    </Surface>
  );
}

function SummaryTile({
  label,
  value,
  icon,
  tone,
}: {
  label: string;
  value: string;
  icon: string;
  tone?: 'default' | 'danger' | 'warning';
}) {
  const theme = useTheme();
  const iconSurface = iconSurfaceForThemeTone(theme, summaryToneToIconTone(tone));

  return (
    <Surface
      style={[styles.summaryTile, { backgroundColor: theme.colors.elevation.level2 }]}
      elevation={0}
    >
      <View style={[styles.summaryTileIcon, { backgroundColor: iconSurface.backgroundColor }]}>
        <MaterialCommunityIcons name={icon as never} size={17} color={iconSurface.iconColor} />
      </View>
      <Text
        variant="labelSmall"
        numberOfLines={1}
        style={[styles.mutedText, { color: theme.colors.onSurfaceVariant }]}
      >
        {label}
      </Text>
      <Text
        variant="labelMedium"
        numberOfLines={1}
        adjustsFontSizeToFit
        minimumFontScale={0.65}
        style={[styles.summaryValue, { color: theme.colors.onSurface }]}
      >
        {value}
      </Text>
    </Surface>
  );
}

function InfoLine({
  icon,
  label,
  value,
  subvalue,
  danger,
  positive,
}: {
  icon: string;
  label: string;
  value: string;
  subvalue?: string;
  danger?: boolean;
  positive?: boolean;
}) {
  const theme = useTheme();
  const color = positive
    ? theme.colors.tertiary
    : danger
      ? theme.colors.error
      : theme.colors.onSurface;
  const iconSurface = iconSurfaceForThemeTone(
    theme,
    positive ? 'income' : danger ? 'danger' : 'record',
  );

  return (
    <View style={styles.infoLine}>
      <View style={[styles.infoLineIcon, { backgroundColor: iconSurface.backgroundColor }]}>
        <MaterialCommunityIcons name={icon as never} size={16} color={iconSurface.iconColor} />
      </View>
      <View style={styles.fill}>
        <Text
          variant="bodyMedium"
          numberOfLines={1}
          style={[styles.infoLabel, { color: theme.colors.onSurface }]}
        >
          {label}
        </Text>
        {subvalue ? (
          <Text
            variant="labelSmall"
            numberOfLines={1}
            style={[styles.mutedText, { color: theme.colors.onSurfaceVariant }]}
          >
            {subvalue}
          </Text>
        ) : null}
      </View>
      <Text
        variant="bodyMedium"
        numberOfLines={1}
        adjustsFontSizeToFit
        minimumFontScale={0.65}
        style={[styles.infoValue, { color }]}
      >
        {value}
      </Text>
    </View>
  );
}

function summaryToneToIconTone(tone?: 'default' | 'danger' | 'warning'): IconSurfaceTone {
  if (tone === 'danger') return 'danger';
  if (tone === 'warning') return 'warning';
  return 'widget';
}

function BarRow({
  label,
  value,
  subvalue,
  progress,
  color,
}: {
  label: string;
  value: string;
  subvalue?: string;
  progress: number;
  color: string;
}) {
  const theme = useTheme();

  return (
    <View style={styles.barRow}>
      <View style={styles.barHeader}>
        <View style={styles.fill}>
          <Text variant="labelMedium" numberOfLines={1} style={styles.fill}>
            {label}
          </Text>
          {subvalue ? (
            <Text
              variant="labelSmall"
              numberOfLines={1}
              style={[styles.mutedText, { color: theme.colors.onSurfaceVariant }]}
            >
              {subvalue}
            </Text>
          ) : null}
        </View>
        <Text variant="labelLarge" numberOfLines={1} style={styles.infoValue}>
          {value}
        </Text>
      </View>
      <ProgressBar
        progress={Math.min(Math.max(progress, 0), 1)}
        color={color}
        style={[styles.progress, { backgroundColor: theme.colors.outlineVariant }]}
      />
    </View>
  );
}

type BalanceTrendPoint = {
  key: string;
  timestamp: number;
  label: string;
  fullLabel: string;
  amountMinor: number;
  changeFromPreviousMinor: number;
  changeFromStartMinor: number;
  eventCount: number;
  eventLabel?: string;
  anchor: boolean;
};

type BalanceTrendSeries = {
  points: BalanceTrendPoint[];
  plotPoints: BalanceTrendPoint[];
  start: BalanceTrendPoint;
  latest: BalanceTrendPoint;
  rangeStart: number;
  rangeEnd: number;
  hasMovement: boolean;
  movementCount: number;
};

type BalanceTrendAxisTick = { key: string; amountMinor: number; label: string };

const TREND_CHART_HEIGHT = 164;
const TREND_AXIS_WIDTH = 58;
const TREND_CHART_PADDING_X = tokens.space.md;
const TREND_CHART_PADDING_Y = tokens.space.lg;
const TREND_LINE_THICKNESS = 3;
const TREND_DOT_SIZE = 7;
const TREND_LATEST_DOT_SIZE = 11;
const TREND_TOOLTIP_WIDTH = 164;
const TREND_MAX_PLOT_POINTS = 92;

function InteractiveBalanceTrendChart({
  series,
  selectedPointKey,
  onSelectedPointChange,
  onSelectedPointClear,
  locale,
  currency,
}: {
  series: BalanceTrendSeries;
  selectedPointKey?: string;
  onSelectedPointChange: (point: BalanceTrendPoint) => void;
  onSelectedPointClear: () => void;
  locale: string;
  currency: string;
}) {
  const theme = useTheme();
  const [plotWidth, setPlotWidth] = useState(0);
  const selectedPoint = selectedPointKey
    ? series.points.find((point) => point.key === selectedPointKey)
    : undefined;
  const axisTicks = useMemo(
    () => trendAxisTicks(series.points, currency, locale),
    [currency, locale, series.points],
  );
  const chartMin = axisTicks[0]?.amountMinor ?? 0;
  const chartMax = axisTicks[axisTicks.length - 1]?.amountMinor ?? 1;
  const chartRange = Math.max(1, chartMax - chartMin);
  const rangeDuration = Math.max(1, series.rangeEnd - series.rangeStart);
  const usableWidth = Math.max(1, plotWidth - TREND_CHART_PADDING_X * 2);
  const usableHeight = TREND_CHART_HEIGHT - TREND_CHART_PADDING_Y * 2;

  const coordinateForPoint = (point: BalanceTrendPoint) => {
    const x =
      TREND_CHART_PADDING_X + ((point.timestamp - series.rangeStart) / rangeDuration) * usableWidth;
    const y =
      TREND_CHART_PADDING_Y + (1 - (point.amountMinor - chartMin) / chartRange) * usableHeight;
    return {
      point,
      x: clampNumber(x, TREND_CHART_PADDING_X, TREND_CHART_PADDING_X + usableWidth),
      y: clampNumber(y, TREND_CHART_PADDING_Y, TREND_CHART_PADDING_Y + usableHeight),
    };
  };

  const plotCoordinates = series.plotPoints.map(coordinateForPoint);
  const selectedCoordinate = selectedPoint ? coordinateForPoint(selectedPoint) : undefined;
  const tooltipHeight = 62;
  const tooltipLeft = selectedCoordinate
    ? selectedCoordinate.x > plotWidth * 0.56
      ? selectedCoordinate.x - TREND_TOOLTIP_WIDTH - tokens.space.sm
      : selectedCoordinate.x + tokens.space.sm
    : 0;
  const tooltipTop = selectedCoordinate
    ? selectedCoordinate.y > TREND_CHART_HEIGHT * 0.52
      ? selectedCoordinate.y - tooltipHeight - tokens.space.sm
      : selectedCoordinate.y + tokens.space.sm
    : 0;
  const clampedTooltipLeft = clampNumber(
    tooltipLeft,
    0,
    Math.max(0, plotWidth - TREND_TOOLTIP_WIDTH),
  );
  const clampedTooltipTop = clampNumber(tooltipTop, 0, TREND_CHART_HEIGHT - tooltipHeight);

  const handleLayout = (event: LayoutChangeEvent) => {
    setPlotWidth(event.nativeEvent.layout.width);
  };

  const panResponder = useMemo(
    () =>
      PanResponder.create({
        onStartShouldSetPanResponder: () => true,
        onMoveShouldSetPanResponder: () => true,
        onPanResponderGrant: (event: GestureResponderEvent) => {
          if (plotWidth <= 0) return;
          const x = clampNumber(event.nativeEvent.locationX, 0, plotWidth);
          const timestamp = series.rangeStart + (x / Math.max(1, plotWidth)) * rangeDuration;
          onSelectedPointChange(nearestTrendPoint(series.points, timestamp));
        },
        onPanResponderMove: (event: GestureResponderEvent) => {
          if (plotWidth <= 0) return;
          const x = clampNumber(event.nativeEvent.locationX, 0, plotWidth);
          const timestamp = series.rangeStart + (x / Math.max(1, plotWidth)) * rangeDuration;
          onSelectedPointChange(nearestTrendPoint(series.points, timestamp));
        },
      }),
    [onSelectedPointChange, plotWidth, rangeDuration, series.points, series.rangeStart],
  );

  return (
    <View
      style={[styles.trendCard, { backgroundColor: theme.colors.surfaceVariant }]}
      onTouchStart={onSelectedPointClear}
    >
      <View style={styles.trendChartBody}>
        <View style={styles.trendAxis}>
          {axisTicks.map((tick) => {
            const y =
              TREND_CHART_PADDING_Y +
              (1 - (tick.amountMinor - chartMin) / chartRange) * usableHeight;
            return (
              <Text
                key={tick.key}
                variant="labelSmall"
                numberOfLines={1}
                style={[
                  styles.trendAxisLabel,
                  {
                    top: clampNumber(y - 7, 0, TREND_CHART_HEIGHT - 14),
                    color: theme.colors.onSurfaceVariant,
                  },
                ]}
              >
                {tick.label}
              </Text>
            );
          })}
        </View>
        <View
          collapsable={false}
          style={styles.trendPlotArea}
          onLayout={handleLayout}
          onTouchStart={(event) => event.stopPropagation()}
          {...panResponder.panHandlers}
        >
          {axisTicks.map((tick) => {
            const y =
              TREND_CHART_PADDING_Y +
              (1 - (tick.amountMinor - chartMin) / chartRange) * usableHeight;
            return (
              <View
                key={tick.key}
                style={[
                  styles.trendGridLine,
                  {
                    top: y,
                    backgroundColor:
                      tick.amountMinor === 0 ? theme.colors.primary : theme.colors.outlineVariant,
                    opacity: tick.amountMinor === 0 ? 0.42 : 0.58,
                  },
                ]}
              />
            );
          })}
          {plotWidth > 0
            ? plotCoordinates.slice(1).map((coordinate, index) => {
                const previous = plotCoordinates[index];
                if (!previous) return null;
                const dx = coordinate.x - previous.x;
                const dy = coordinate.y - previous.y;
                const length = Math.sqrt(dx * dx + dy * dy);
                if (length < 0.5) return null;
                const angle = `${Math.atan2(dy, dx)}rad`;
                return (
                  <View
                    key={`${previous.point.key}-${coordinate.point.key}`}
                    style={[
                      styles.trendSegment,
                      {
                        width: length,
                        left: previous.x + dx / 2 - length / 2,
                        top: previous.y + dy / 2 - TREND_LINE_THICKNESS / 2,
                        backgroundColor: theme.colors.primary,
                        transform: [{ rotate: angle }],
                      },
                    ]}
                  />
                );
              })
            : null}
          {plotWidth > 0 && series.plotPoints.length <= 48
            ? plotCoordinates
                .filter((coordinate) => coordinate.point.eventCount > 0)
                .map((coordinate) => (
                  <View
                    key={`event-${coordinate.point.key}`}
                    style={[
                      styles.trendEventDot,
                      {
                        left: coordinate.x - TREND_DOT_SIZE / 2,
                        top: coordinate.y - TREND_DOT_SIZE / 2,
                        backgroundColor: theme.colors.primaryContainer,
                        borderColor: theme.colors.primary,
                      },
                    ]}
                  />
                ))
            : null}
          {plotWidth > 0 && selectedPoint && selectedCoordinate ? (
            <>
              <View
                pointerEvents="none"
                style={[
                  styles.trendCursor,
                  { left: selectedCoordinate.x, backgroundColor: theme.colors.primary },
                ]}
              />
              <View
                pointerEvents="none"
                style={[
                  styles.trendDot,
                  styles.trendDotLatest,
                  {
                    left: selectedCoordinate.x - TREND_LATEST_DOT_SIZE / 2,
                    top: selectedCoordinate.y - TREND_LATEST_DOT_SIZE / 2,
                    backgroundColor: theme.colors.primary,
                    borderColor: theme.colors.surfaceVariant,
                  },
                ]}
              />
              <View
                pointerEvents="none"
                style={[
                  styles.trendTooltip,
                  {
                    left: clampedTooltipLeft,
                    top: clampedTooltipTop,
                    backgroundColor: theme.colors.elevation.level3,
                    borderColor: theme.colors.outlineVariant,
                  },
                ]}
              >
                <Text
                  variant="labelSmall"
                  numberOfLines={1}
                  style={[styles.mutedText, { color: theme.colors.onSurfaceVariant }]}
                >
                  {selectedPoint.fullLabel}
                </Text>
                <Text variant="labelLarge" numberOfLines={1} style={styles.trendTooltipAmount}>
                  Net {formatMoney({ amountMinor: selectedPoint.amountMinor, currency }, locale)}
                </Text>
              </View>
            </>
          ) : null}
        </View>
      </View>
      <View style={styles.trendXAxisRow}>
        <View style={styles.trendXAxisSpacer} />
        <View style={styles.trendXAxisLabels}>
          <Text
            variant="labelSmall"
            numberOfLines={1}
            style={{ color: theme.colors.onSurfaceVariant }}
          >
            {series.start.label}
          </Text>
          <Text
            variant="labelSmall"
            numberOfLines={1}
            style={{ color: theme.colors.onSurfaceVariant }}
          >
            {series.hasMovement ? `${series.movementCount} moves` : 'No movement'}
          </Text>
          <Text
            variant="labelSmall"
            numberOfLines={1}
            style={{ color: theme.colors.onSurfaceVariant }}
          >
            {series.latest.label}
          </Text>
        </View>
      </View>
    </View>
  );
}

function ChipRow({ values }: { values: string[] }) {
  return (
    <View style={styles.chipRow}>
      {values.map((value) => (
        <Chip key={value} compact>
          {value}
        </Chip>
      ))}
    </View>
  );
}

type TopCategorySubcategory = {
  key: string;
  categoryId?: string;
  categoryName: string;
  amount: Money;
  share: number;
  recordCount: number;
  records: Transaction[];
};

type TopCategoryDrilldown = {
  categoryId?: string;
  categoryName: string;
  amount: Money;
  share: number;
  subcategories: TopCategorySubcategory[];
};

type CategoryDrilldownBucket = {
  key: string;
  categoryId?: string;
  categoryName: string;
  amountBaseMinor: number;
  recordIds: Set<string>;
  subcategories: Map<string, CategoryDrilldownSubBucket>;
};

type CategoryDrilldownSubBucket = {
  key: string;
  categoryId?: string;
  categoryName: string;
  amountBaseMinor: number;
  recordIds: Set<string>;
};

function topCategoryDrilldownForPreset(
  state: ReturnType<typeof useLedger>['state'],
  preset: HomeWidgetDatePreset,
  kind: 'expense' | 'income',
  selectedAccountId?: string,
  currency = displayCurrency(state),
  indexes?: LedgerIndexes,
): TopCategoryDrilldown[] {
  const base = state.preferences.baseCurrency;
  const types = kind === 'expense' ? OUTFLOW_TYPES : INFLOW_TYPES;
  const categoryById =
    indexes?.categoriesById ?? new Map(state.categories.map((category) => [category.id, category]));
  const transactionById = new Map(
    (indexes?.allTransactionsSorted ?? state.transactions).map((transaction) => [
      transaction.id,
      transaction,
    ]),
  );
  const buckets = new Map<string, CategoryDrilldownBucket>();
  let totalBaseMinor = 0;

  for (const transaction of reportableTransactions(state, preset, selectedAccountId, indexes)) {
    if (!types.has(transaction.type)) continue;
    for (const allocation of reportingAllocationsForWidget(state, transaction, indexes)) {
      const category = allocation.categoryId ? categoryById.get(allocation.categoryId) : undefined;
      const rootCategory = category ? rootCategoryFor(category, categoryById) : undefined;
      const rootKey = rootCategory?.id ?? '__none';
      const rootBucket = ensureTopCategoryBucket(buckets, rootKey, rootCategory);
      const subBucket = ensureSubcategoryBucket(
        rootBucket,
        subcategoryBucketForAllocation(category, rootCategory, categoryById),
      );

      rootBucket.amountBaseMinor += allocation.amountBaseMinor;
      rootBucket.recordIds.add(transaction.id);
      subBucket.amountBaseMinor += allocation.amountBaseMinor;
      subBucket.recordIds.add(transaction.id);
      totalBaseMinor += allocation.amountBaseMinor;
    }
  }

  return Array.from(buckets.values())
    .map((bucket) => ({
      categoryId: bucket.categoryId,
      categoryName: bucket.categoryName,
      amount: convertMoneyForDisplay(
        state,
        { amountMinor: bucket.amountBaseMinor, currency: base },
        currency,
      ),
      share: totalBaseMinor > 0 ? bucket.amountBaseMinor / totalBaseMinor : 0,
      subcategories: Array.from(bucket.subcategories.values())
        .map((subcategory) => ({
          key: subcategory.key,
          categoryId: subcategory.categoryId,
          categoryName: subcategory.categoryName,
          amount: convertMoneyForDisplay(
            state,
            { amountMinor: subcategory.amountBaseMinor, currency: base },
            currency,
          ),
          share:
            bucket.amountBaseMinor > 0 ? subcategory.amountBaseMinor / bucket.amountBaseMinor : 0,
          recordCount: subcategory.recordIds.size,
          records: recordsForIds(transactionById, subcategory.recordIds),
        }))
        .sort((left, right) => right.amount.amountMinor - left.amount.amountMinor),
    }))
    .sort((left, right) => right.amount.amountMinor - left.amount.amountMinor);
}

function ensureTopCategoryBucket(
  buckets: Map<string, CategoryDrilldownBucket>,
  key: string,
  category?: Category,
): CategoryDrilldownBucket {
  const existing = buckets.get(key);
  if (existing) return existing;
  const bucket: CategoryDrilldownBucket = {
    key,
    categoryId: category?.id,
    categoryName: category?.name ?? 'Uncategorized',
    amountBaseMinor: 0,
    recordIds: new Set(),
    subcategories: new Map(),
  };
  buckets.set(key, bucket);
  return bucket;
}

function ensureSubcategoryBucket(
  topBucket: CategoryDrilldownBucket,
  input: { key: string; categoryId?: string; categoryName: string },
): CategoryDrilldownSubBucket {
  const existing = topBucket.subcategories.get(input.key);
  if (existing) return existing;
  const bucket: CategoryDrilldownSubBucket = {
    key: input.key,
    categoryId: input.categoryId,
    categoryName: input.categoryName,
    amountBaseMinor: 0,
    recordIds: new Set(),
  };
  topBucket.subcategories.set(input.key, bucket);
  return bucket;
}

function subcategoryBucketForAllocation(
  category: Category | undefined,
  rootCategory: Category | undefined,
  categoryById: Map<string, Category>,
): { key: string; categoryId?: string; categoryName: string } {
  if (!category || !rootCategory) {
    return { key: '__none', categoryName: 'Uncategorized records' };
  }
  if (category.id === rootCategory.id) {
    return {
      key: `${rootCategory.id}:self`,
      categoryId: rootCategory.id,
      categoryName: `This ${rootCategory.name}`,
    };
  }
  const subcategory = immediateChildBelowRoot(category, rootCategory, categoryById) ?? category;
  return { key: subcategory.id, categoryId: subcategory.id, categoryName: subcategory.name };
}

function rootCategoryFor(category: Category, categoryById: Map<string, Category>): Category {
  let current = category;
  const seen = new Set<string>();
  while (current.parentId && !seen.has(current.id)) {
    seen.add(current.id);
    const parent = categoryById.get(current.parentId);
    if (!parent) break;
    current = parent;
  }
  return current;
}

function immediateChildBelowRoot(
  category: Category,
  rootCategory: Category,
  categoryById: Map<string, Category>,
): Category | undefined {
  let current = category;
  const seen = new Set<string>();
  while (current.parentId && current.parentId !== rootCategory.id && !seen.has(current.id)) {
    seen.add(current.id);
    const parent = categoryById.get(current.parentId);
    if (!parent) break;
    current = parent;
  }
  return current.parentId === rootCategory.id ? current : undefined;
}

function recordsForIds(
  transactionById: Map<string, Transaction>,
  recordIds: Set<string>,
): Transaction[] {
  return Array.from(recordIds)
    .map((id) => transactionById.get(id))
    .filter((transaction): transaction is Transaction => Boolean(transaction))
    .sort(
      (left, right) => new Date(right.occurredAt).getTime() - new Date(left.occurredAt).getTime(),
    );
}

function reportingAllocationsForWidget(
  state: ReturnType<typeof useLedger>['state'],
  transaction: Transaction,
  indexes?: LedgerIndexes,
): { categoryId?: string; amountBaseMinor: number }[] {
  const splits =
    indexes?.splitsByTransactionId.get(transaction.id) ??
    state.transactionSplits.filter((split) => split.transactionId === transaction.id);
  if (splits.length === 0) {
    return [
      { categoryId: transaction.categoryId, amountBaseMinor: transaction.baseAmount.amountMinor },
    ];
  }

  const allocations = splits.map((split) => ({
    categoryId: split.categoryId ?? transaction.categoryId,
    amountBaseMinor: Math.round(
      split.amount.amountMinor *
        rateBetween(state, split.amount.currency, state.preferences.baseCurrency),
    ),
  }));
  const allocated = allocations.reduce((sum, split) => sum + split.amountBaseMinor, 0);
  const remainder = transaction.baseAmount.amountMinor - allocated;
  if (remainder > 0)
    allocations.push({ categoryId: transaction.categoryId, amountBaseMinor: remainder });
  return allocations;
}

function reportableTransactions(
  state: ReturnType<typeof useLedger>['state'],
  preset: HomeWidgetDatePreset,
  selectedAccountId?: string,
  indexes?: LedgerIndexes,
): Transaction[] {
  const sourceTransactions = indexes
    ? transactionsForSelectedAccount(indexes, selectedAccountId)
    : state.transactions;
  return filterTransactionsByPreset(sourceTransactions, preset).filter((transaction) => {
    if (!transactionMatchesAccount(transaction, selectedAccountId)) return false;
    if (transaction.status === 'scheduled' || transaction.status === 'void') return false;
    if (transaction.isExcludedFromReports) return false;
    const account =
      indexes?.accountsById.get(transaction.accountId) ??
      state.accounts.find((item) => item.id === transaction.accountId);
    return Boolean(account && !account.isArchived && account.includeInReports);
  });
}

type BalanceTrendReplayEvent =
  | { timestamp: number; kind: 'opening'; account: Account; label: string }
  | { timestamp: number; kind: 'transaction'; transaction: Transaction; label: string };

function balanceTrendSeriesForPreset(
  state: ReturnType<typeof useLedger>['state'],
  preset: HomeWidgetDatePreset,
  selectedAccountId?: string,
  currency = displayCurrency(state),
): BalanceTrendSeries {
  const accounts = state.accounts.filter(
    (account) =>
      !account.isArchived &&
      account.includeInTotals &&
      (!selectedAccountId || account.id === selectedAccountId),
  );
  const range = trendRangeForPreset(state, preset, accounts);
  const accountById = new Map(accounts.map((account) => [account.id, account]));
  const balances = new Map<string, number>();

  for (const account of accounts) {
    balances.set(account.id, accountBalanceAt(state, account, range.start).amountMinor);
  }

  const startAmountMinor = trendTotalBalance(state, accounts, balances, currency);
  const points: BalanceTrendPoint[] = [];
  const pushPoint = (timestamp: number, anchor: boolean, eventCount = 0, eventLabel?: string) => {
    const amountMinor = trendTotalBalance(state, accounts, balances, currency);
    const previous = points[points.length - 1];
    const point: BalanceTrendPoint = {
      key: `${anchor ? 'anchor' : 'event'}-${timestamp}-${points.length}`,
      timestamp,
      label: formatTrendShortLabel(timestamp, preset),
      fullLabel: formatTrendFullLabel(timestamp),
      amountMinor,
      changeFromPreviousMinor: amountMinor - (previous?.amountMinor ?? amountMinor),
      changeFromStartMinor: amountMinor - startAmountMinor,
      eventCount,
      eventLabel,
      anchor,
    };
    if (previous?.timestamp === timestamp) {
      points[points.length - 1] = { ...point, key: previous.key };
    } else {
      points.push(point);
    }
  };

  pushPoint(range.start.getTime(), true);

  const events = trendReplayEvents(state, accounts, range.start, range.end);
  const anchors = trendAnchorTimestamps(range.start, range.end, preset);
  let eventIndex = 0;
  let anchorIndex = 1;

  while (eventIndex < events.length || anchorIndex < anchors.length) {
    const nextEventTime = events[eventIndex]?.timestamp ?? Number.POSITIVE_INFINITY;
    const nextAnchorTime = anchors[anchorIndex] ?? Number.POSITIVE_INFINITY;
    if (nextEventTime <= nextAnchorTime) {
      const timestamp = nextEventTime;
      const labels: string[] = [];
      let changedEvents = 0;
      while (eventIndex < events.length && events[eventIndex]?.timestamp === timestamp) {
        const event = events[eventIndex];
        if (event && applyTrendReplayEvent(state, accountById, balances, event)) {
          changedEvents += 1;
          labels.push(event.label);
        }
        eventIndex += 1;
      }
      if (changedEvents > 0) {
        pushPoint(timestamp, false, changedEvents, summarizeTrendEventLabels(labels));
      }
      while (anchors[anchorIndex] === timestamp) anchorIndex += 1;
    } else {
      pushPoint(nextAnchorTime, true);
      anchorIndex += 1;
    }
  }

  if ((points[points.length - 1]?.timestamp ?? 0) < range.end.getTime()) {
    pushPoint(range.end.getTime(), true);
  }

  const latest = points[points.length - 1] ?? points[0] ?? emptyTrendPoint(currency);
  const start = points[0] ?? latest;
  const hasMovement = points.some((point) => point.changeFromPreviousMinor !== 0);
  const movementCount = points.reduce((sum, point) => sum + point.eventCount, 0);

  return {
    points,
    plotPoints: downsampleTrendPoints(points),
    start,
    latest,
    rangeStart: range.start.getTime(),
    rangeEnd: range.end.getTime(),
    hasMovement,
    movementCount,
  };
}

function trendRangeForPreset(
  state: ReturnType<typeof useLedger>['state'],
  preset: HomeWidgetDatePreset,
  accounts: Account[],
): { start: Date; end: Date } {
  const range = dateRangeForPreset(preset);
  const today = new Date();
  let end = range.end ? new Date(range.end) : today;
  if (end.getTime() > today.getTime()) end = today;
  let start = range.start ? new Date(range.start) : earliestTrendDate(state, accounts);
  start ??= new Date(today.getFullYear(), today.getMonth(), 1);
  if (start.getTime() > end.getTime()) start = new Date(end.getTime() - 24 * 60 * 60 * 1000);
  if (start.getTime() === end.getTime()) end = new Date(start.getTime() + 60 * 60 * 1000);
  return { start, end };
}

function earliestTrendDate(
  state: ReturnType<typeof useLedger>['state'],
  accounts: Account[],
): Date | undefined {
  const accountIds = new Set(accounts.map((account) => account.id));
  let earliest = Number.POSITIVE_INFINITY;
  for (const account of accounts) {
    const time = new Date(account.openingDate).getTime();
    if (!Number.isNaN(time)) earliest = Math.min(earliest, time);
  }
  for (const transaction of state.transactions) {
    if (!transactionAffectsTrendAccounts(transaction, accountIds)) continue;
    const time = new Date(transaction.occurredAt).getTime();
    if (!Number.isNaN(time)) earliest = Math.min(earliest, time);
  }
  return Number.isFinite(earliest) ? new Date(earliest) : undefined;
}

function trendReplayEvents(
  state: ReturnType<typeof useLedger>['state'],
  accounts: Account[],
  start: Date,
  end: Date,
): BalanceTrendReplayEvent[] {
  const accountIds = new Set(accounts.map((account) => account.id));
  const startTime = start.getTime();
  const endTime = end.getTime();
  const events: BalanceTrendReplayEvent[] = [];

  for (const account of accounts) {
    const openingTime = new Date(account.openingDate).getTime();
    if (
      Number.isNaN(openingTime) ||
      openingTime < startTime ||
      openingTime > endTime ||
      account.openingBalance.amountMinor === 0
    ) {
      continue;
    }
    events.push({
      timestamp: openingTime,
      kind: 'opening',
      account,
      label: `${account.name} opened`,
    });
  }

  for (const transaction of state.transactions) {
    if (transaction.status === 'scheduled' || transaction.status === 'void') continue;
    if (!transactionAffectsTrendAccounts(transaction, accountIds)) continue;
    const timestamp = new Date(transaction.occurredAt).getTime();
    if (Number.isNaN(timestamp) || timestamp < startTime || timestamp > endTime) continue;
    events.push({
      timestamp,
      kind: 'transaction',
      transaction,
      label: trendEventLabel(state, transaction),
    });
  }

  return events.sort((left, right) => left.timestamp - right.timestamp);
}

function applyTrendReplayEvent(
  state: ReturnType<typeof useLedger>['state'],
  accountById: Map<string, Account>,
  balances: Map<string, number>,
  event: BalanceTrendReplayEvent,
): boolean {
  if (event.kind === 'opening') {
    const current = balances.get(event.account.id) ?? 0;
    balances.set(event.account.id, current + event.account.openingBalance.amountMinor);
    return event.account.openingBalance.amountMinor !== 0;
  }

  const { transaction } = event;
  let changed = false;
  const sourceAccount = accountById.get(transaction.accountId);
  if (sourceAccount) {
    const amountMinor = convertMoneyForDisplay(
      state,
      transaction.amount,
      sourceAccount.currency,
    ).amountMinor;
    const delta = trendSourceAccountDelta(transaction, amountMinor);
    if (delta !== 0) {
      balances.set(sourceAccount.id, (balances.get(sourceAccount.id) ?? 0) + delta);
      changed = true;
    }
  }

  const counterAccount = transaction.counterAccountId
    ? accountById.get(transaction.counterAccountId)
    : undefined;
  if (counterAccount && TRANSFER_TYPES.has(transaction.type)) {
    const counterMoney = transaction.counterAmount ?? transaction.amount;
    const delta = convertMoneyForDisplay(state, counterMoney, counterAccount.currency).amountMinor;
    if (delta !== 0) {
      balances.set(counterAccount.id, (balances.get(counterAccount.id) ?? 0) + delta);
      changed = true;
    }
  }

  return changed;
}

function trendSourceAccountDelta(transaction: Transaction, amountMinor: number): number {
  if (INFLOW_TYPES.has(transaction.type)) return amountMinor;
  if (OUTFLOW_TYPES.has(transaction.type)) return -amountMinor;
  if (TRANSFER_TYPES.has(transaction.type)) return -amountMinor;
  if (transaction.type === 'adjustment') return amountMinor;
  return 0;
}

function trendTotalBalance(
  state: ReturnType<typeof useLedger>['state'],
  accounts: Account[],
  balances: Map<string, number>,
  currency: string,
): number {
  return accounts.reduce((sum, account) => {
    const balance = { amountMinor: balances.get(account.id) ?? 0, currency: account.currency };
    return sum + convertMoneyForDisplay(state, balance, currency).amountMinor;
  }, 0);
}

function trendAnchorTimestamps(start: Date, end: Date, preset: HomeWidgetDatePreset): number[] {
  const timestamps = [start.getTime()];
  let cursor = nextTrendAnchor(start, preset);
  while (cursor.getTime() < end.getTime() && timestamps.length < 240) {
    timestamps.push(cursor.getTime());
    cursor = advanceTrendAnchor(cursor, preset);
  }
  if (timestamps[timestamps.length - 1] !== end.getTime()) timestamps.push(end.getTime());
  return Array.from(new Set(timestamps)).sort((left, right) => left - right);
}

function nextTrendAnchor(value: Date, preset: HomeWidgetDatePreset): Date {
  const next = new Date(value);
  if (preset === 'today') {
    next.setMinutes(0, 0, 0);
    next.setHours(next.getHours() + 1);
    return next;
  }
  if (preset === 'thisYear') {
    next.setHours(0, 0, 0, 0);
    next.setDate(next.getDate() + 7);
    return next;
  }
  if (preset === 'allTime') {
    return new Date(next.getFullYear(), next.getMonth() + 1, 1);
  }
  next.setHours(0, 0, 0, 0);
  next.setDate(next.getDate() + 1);
  return next;
}

function advanceTrendAnchor(value: Date, preset: HomeWidgetDatePreset): Date {
  const next = new Date(value);
  if (preset === 'today') next.setHours(next.getHours() + 1);
  else if (preset === 'thisYear') next.setDate(next.getDate() + 7);
  else if (preset === 'allTime') next.setMonth(next.getMonth() + 1);
  else next.setDate(next.getDate() + 1);
  return next;
}

function transactionAffectsTrendAccounts(
  transaction: Transaction,
  accountIds: Set<string>,
): boolean {
  return (
    accountIds.has(transaction.accountId) ||
    Boolean(transaction.counterAccountId && accountIds.has(transaction.counterAccountId))
  );
}

function trendEventLabel(
  state: ReturnType<typeof useLedger>['state'],
  transaction: Transaction,
): string {
  const account = state.accounts.find((item) => item.id === transaction.accountId);
  const category = transaction.categoryId
    ? state.categories.find((item) => item.id === transaction.categoryId)
    : undefined;
  const label = category?.name ?? typeLabel(transaction.type);
  return account ? `${label} · ${account.name}` : label;
}

function summarizeTrendEventLabels(labels: string[]): string | undefined {
  const [first, ...rest] = labels.filter(Boolean);
  if (!first) return undefined;
  return rest.length > 0 ? `${first} +${rest.length} more` : first;
}

function downsampleTrendPoints(points: BalanceTrendPoint[]): BalanceTrendPoint[] {
  if (points.length <= TREND_MAX_PLOT_POINTS) return points;
  const first = points[0];
  const last = points[points.length - 1];
  if (!first || !last) return points;
  const keep = new Set<string>();
  const add = (point?: BalanceTrendPoint) => {
    if (point) keep.add(point.key);
  };
  add(first);
  add(last);
  add(points.reduce((min, point) => (point.amountMinor < min.amountMinor ? point : min), first));
  add(points.reduce((max, point) => (point.amountMinor > max.amountMinor ? point : max), first));

  const movers = [...points]
    .sort(
      (left, right) =>
        Math.abs(right.changeFromPreviousMinor) - Math.abs(left.changeFromPreviousMinor),
    )
    .slice(0, Math.floor(TREND_MAX_PLOT_POINTS * 0.28));
  movers.forEach(add);

  const remainingSlots = Math.max(1, TREND_MAX_PLOT_POINTS - keep.size);
  const stride = Math.max(1, (points.length - 1) / remainingSlots);
  for (let index = 0; index < points.length; index += stride) {
    add(points[Math.round(index)]);
  }

  return points.filter((point) => keep.has(point.key)).slice(0, TREND_MAX_PLOT_POINTS);
}

function trendAxisTicks(
  points: BalanceTrendPoint[],
  currency: string,
  locale: string,
): BalanceTrendAxisTick[] {
  const values = points.length > 0 ? points.map((point) => point.amountMinor) : [0];
  const rawMin = Math.min(...values);
  const rawMax = Math.max(...values);
  const rawRange = Math.max(1, rawMax - rawMin);
  const pad = rawMin === rawMax ? Math.max(100, Math.abs(rawMin) * 0.12) : rawRange * 0.12;
  let chartMin = rawMin - pad;
  let chartMax = rawMax + pad;
  if (rawMin < 0 && rawMax > 0) {
    chartMin = Math.min(chartMin, 0);
    chartMax = Math.max(chartMax, 0);
  }
  const step = niceTrendStep((chartMax - chartMin) / 4);
  const axisMin = Math.floor(chartMin / step) * step;
  const axisMax = Math.ceil(chartMax / step) * step;
  const ticks: BalanceTrendAxisTick[] = [];
  for (let value = axisMin; value <= axisMax + step / 2 && ticks.length < 7; value += step) {
    const amountMinor = Math.round(value);
    ticks.push({
      key: `axis-${amountMinor}`,
      amountMinor,
      label: formatCompactTrendMoney(amountMinor, currency, locale),
    });
  }
  return ticks.length >= 2
    ? ticks
    : [
        { key: 'axis-0', amountMinor: 0, label: formatCompactTrendMoney(0, currency, locale) },
        {
          key: 'axis-1',
          amountMinor: step,
          label: formatCompactTrendMoney(step, currency, locale),
        },
      ];
}

function niceTrendStep(value: number): number {
  const safeValue = Math.max(1, Math.abs(value));
  const exponent = Math.floor(Math.log10(safeValue));
  const base = Math.pow(10, exponent);
  const fraction = safeValue / base;
  const niceFraction = fraction <= 1 ? 1 : fraction <= 2 ? 2 : fraction <= 5 ? 5 : 10;
  return Math.max(1, niceFraction * base);
}

function nearestTrendPoint(points: BalanceTrendPoint[], timestamp: number): BalanceTrendPoint {
  if (points.length === 0) return emptyTrendPoint('INR');
  let low = 0;
  let high = points.length - 1;
  while (low < high) {
    const mid = Math.floor((low + high) / 2);
    const midpoint = points[mid];
    if (!midpoint) break;
    if (midpoint.timestamp < timestamp) low = mid + 1;
    else high = mid;
  }
  const next = points[low] ?? points[points.length - 1] ?? emptyTrendPoint('INR');
  const previous = points[Math.max(0, low - 1)] ?? next;
  return Math.abs((previous?.timestamp ?? 0) - timestamp) <= Math.abs(next.timestamp - timestamp)
    ? previous
    : next;
}

function emptyTrendPoint(currency: string): BalanceTrendPoint {
  const now = Date.now();
  return {
    key: `empty-${currency}`,
    timestamp: now,
    label: 'Now',
    fullLabel: formatTrendFullLabel(now),
    amountMinor: 0,
    changeFromPreviousMinor: 0,
    changeFromStartMinor: 0,
    eventCount: 0,
    anchor: true,
  };
}

function formatTrendShortLabel(timestamp: number, preset: HomeWidgetDatePreset): string {
  const date = new Date(timestamp);
  if (preset === 'today') {
    return date.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
  }
  if (preset === 'allTime') {
    return date.toLocaleDateString(undefined, { month: 'short', year: '2-digit' });
  }
  return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

function formatTrendFullLabel(timestamp: number): string {
  return new Date(timestamp).toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

function formatCompactTrendMoney(amountMinor: number, currency: string, locale: string): string {
  try {
    const value = fromMinor(amountMinor === 0 ? 0 : amountMinor, currency);
    const abs = Math.abs(value);
    return new Intl.NumberFormat(locale, {
      style: 'currency',
      currency,
      notation: abs >= 10000 ? 'compact' : 'standard',
      maximumFractionDigits: abs >= 1000 ? 1 : 0,
    }).format(value);
  } catch {
    return formatMoney({ amountMinor, currency }, locale);
  }
}

function clampNumber(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

function accountBalanceAt(
  state: ReturnType<typeof useLedger>['state'],
  account: Account,
  endExclusive: Date,
): Money {
  let balance = account.openingBalance.amountMinor;
  const openingDate = new Date(account.openingDate);
  if (!Number.isNaN(openingDate.getTime()) && openingDate >= endExclusive) balance = 0;

  for (const transaction of state.transactions) {
    if (transaction.status === 'scheduled' || transaction.status === 'void') continue;
    const occurredAt = new Date(transaction.occurredAt);
    if (Number.isNaN(occurredAt.getTime()) || occurredAt >= endExclusive) continue;
    if (transaction.accountId === account.id) {
      const amountMinor = convertMoneyForDisplay(
        state,
        transaction.amount,
        account.currency,
      ).amountMinor;
      if (INFLOW_TYPES.has(transaction.type)) balance += amountMinor;
      else if (OUTFLOW_TYPES.has(transaction.type)) balance -= amountMinor;
      else if (TRANSFER_TYPES.has(transaction.type)) balance -= amountMinor;
      else if (transaction.type === 'adjustment') balance += amountMinor;
    }
    if (TRANSFER_TYPES.has(transaction.type) && transaction.counterAccountId === account.id) {
      const counterMoney = transaction.counterAmount ?? transaction.amount;
      balance += convertMoneyForDisplay(state, counterMoney, account.currency).amountMinor;
    }
  }

  return { amountMinor: balance, currency: account.currency };
}

function signedTransactionAmount(transaction: Transaction) {
  if (INFLOW_TYPES.has(transaction.type)) return transaction.amount.amountMinor;
  if (OUTFLOW_TYPES.has(transaction.type)) return -transaction.amount.amountMinor;
  return transaction.amount.amountMinor;
}

function typeLabel(type: TransactionType) {
  return transactionTypeLabel(type);
}

function transactionIcon(type: TransactionType) {
  return transactionTypeIcon(type);
}

function iconForAccount(type: Account['type']) {
  switch (type) {
    case 'cash':
      return 'cash-multiple';
    case 'bank':
    case 'debit_card':
      return 'bank-outline';
    case 'credit_card':
      return 'credit-card-outline';
    case 'wallet':
      return 'wallet-outline';
    case 'prepaid':
      return 'card-account-details-outline';
    case 'loan':
    case 'overdraft':
      return 'hand-coin-outline';
    case 'investment':
    case 'crypto':
      return 'chart-line';
    case 'savings_goal':
      return 'bullseye-arrow';
    default:
      return 'wallet-outline';
  }
}

const styles = StyleSheet.create({
  hero: {
    borderRadius: tokens.radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: tokens.space.md,
    paddingVertical: tokens.space.sm,
    gap: tokens.space.sm,
  },
  heroHeader: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    flexWrap: 'wrap',
    gap: tokens.space.sm,
  },
  heroCopy: { flexGrow: 1, flexShrink: 1, minWidth: 150, gap: tokens.space.xs },
  heroTitlePressArea: { alignSelf: 'flex-start' },
  heroAmount: { fontFamily: numericMediumFontFamily, fontWeight: '800' },
  heroCashBreakdownText: {
    fontFamily: numericMediumFontFamily,
    fontWeight: '800',
    letterSpacing: 0,
    marginTop: -2,
    opacity: 0.9,
  },
  heroActions: {
    flexDirection: 'column',
    alignItems: 'flex-end',
    justifyContent: 'flex-end',
    gap: tokens.space.xs,
    marginLeft: 'auto',
  },
  metricRow: { flexDirection: 'row', flexWrap: 'wrap', gap: tokens.space.sm },
  moneyMetric: {
    flex: 1,
    minWidth: 128,
    minHeight: 48,
    paddingHorizontal: tokens.space.sm,
    paddingVertical: tokens.space.xs,
    borderRadius: tokens.radius.md,
    justifyContent: 'center',
  },
  accountGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    alignItems: 'stretch',
    gap: tokens.space.xs,
  },
  accountTile: {
    flexGrow: 0,
    flexShrink: 0,
    flexBasis: '31.7%',
    maxWidth: '31.7%',
    height: 66,
    borderRadius: tokens.radius.md,
    borderWidth: 2,
    borderColor: 'transparent',
    overflow: 'hidden',
  },
  accountTileCompact: { height: 58 },
  selectedAccountTile: {},
  pressedAccountTile: { transform: [{ scale: 0.985 }] },
  accountTileContent: {
    flex: 1,
    paddingHorizontal: 7,
    paddingVertical: 6,
    gap: 2,
    justifyContent: 'center',
  },
  accountTopLine: { flexDirection: 'row', alignItems: 'center', gap: tokens.space.xs },
  accountIcon: {
    width: 22,
    height: 22,
    borderRadius: tokens.radius.sm,
    alignItems: 'center',
    justifyContent: 'center',
  },
  accountBalance: {
    fontFamily: numericMediumFontFamily,
    fontSize: 13,
    lineHeight: 15,
    fontWeight: '700',
  },
  accountSecondaryBalance: {
    fontFamily: numericMediumFontFamily,
    fontSize: 10,
    lineHeight: 12,
    fontWeight: '700',
    opacity: 0.86,
  },
  tileName: { fontSize: 11, lineHeight: 13, fontWeight: '700' },
  addAccount: {
    borderRadius: tokens.radius.md,
    borderWidth: 1,
    borderStyle: 'dashed',
    overflow: 'hidden',
  },
  addAccountInner: {
    minHeight: 34,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: tokens.space.xs,
  },
  summaryGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: tokens.space.sm },
  twoColumnMetrics: { flexDirection: 'row', gap: tokens.space.sm },
  summaryTile: {
    flex: 1,
    minWidth: 96,
    minHeight: 74,
    gap: tokens.space.xs,
    padding: tokens.space.sm,
    borderRadius: tokens.radius.md,
  },
  summaryTileIcon: {
    width: 30,
    height: 30,
    borderRadius: tokens.radius.sm,
    alignItems: 'center',
    justifyContent: 'center',
  },
  summaryValue: { fontFamily: numericMediumFontFamily, fontWeight: '800' },
  infoLine: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 7 },
  infoLineIcon: {
    width: 30,
    height: 30,
    borderRadius: tokens.radius.sm,
    alignItems: 'center',
    justifyContent: 'center',
  },
  recordRowRipple: { borderRadius: tokens.radius.md, overflow: 'hidden' },
  transferPair: { gap: 2, paddingVertical: 2 },
  recordRow: {
    minHeight: 58,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingVertical: 8,
    paddingHorizontal: 4,
    borderRadius: tokens.radius.md,
  },
  linkedTransferRow: {
    marginLeft: 18,
    borderLeftWidth: 2,
    borderLeftColor: 'rgba(128,128,128,0.28)',
    paddingLeft: 10,
  },
  expandedRecordRow: { backgroundColor: 'rgba(128,128,128,0.08)' },
  recordIcon: {
    width: 36,
    height: 36,
    borderRadius: tokens.radius.md,
    alignItems: 'center',
    justifyContent: 'center',
  },
  recordCopy: { flex: 1, minWidth: 0, gap: 2 },
  recordTitle: { fontWeight: '800' },
  recordAmountWrap: { width: 104, alignItems: 'flex-end', gap: 2 },
  recordAmount: { fontFamily: numericMediumFontFamily, fontWeight: '800', textAlign: 'right' },
  recordSecondaryAmount: { textAlign: 'right' },
  recordDate: { textAlign: 'right' },
  recordDetails: {
    marginLeft: 46,
    marginBottom: 8,
    padding: 8,
    borderRadius: tokens.radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    gap: 2,
  },
  infoLabel: {},
  infoValue: {
    fontFamily: numericMediumFontFamily,
    fontWeight: '800',
    maxWidth: '48%',
    textAlign: 'right',
  },
  miniLine: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 8,
    paddingVertical: 4,
  },
  listStack: { gap: 0 },
  currencyValuesHeader: { flexDirection: 'row', alignItems: 'center', gap: tokens.space.sm },
  currencyValueHeadline: { fontFamily: numericMediumFontFamily, fontWeight: '800' },
  currencyValueMissing: { fontWeight: '700' },
  currencyChartWrap: { gap: tokens.space.xs },
  currencyChartBody: { flexDirection: 'row', alignItems: 'stretch', gap: tokens.space.sm },
  currencyChartAxis: {
    width: CURRENCY_AXIS_WIDTH,
    height: CURRENCY_CHART_HEIGHT,
    position: 'relative',
  },
  currencyChartAxisLabel: {
    position: 'absolute',
    right: 0,
    width: CURRENCY_AXIS_WIDTH,
    textAlign: 'right',
    fontSize: 9,
    lineHeight: 12,
  },
  currencyChartPlot: {
    flex: 1,
    minWidth: 0,
    height: CURRENCY_CHART_HEIGHT,
    overflow: 'hidden',
    position: 'relative',
  },
  currencyChartGridLine: {
    position: 'absolute',
    left: 0,
    right: 0,
    height: StyleSheet.hairlineWidth,
    opacity: 0.7,
  },
  currencyLineSegment: {
    position: 'absolute',
    height: CURRENCY_LINE_THICKNESS,
    borderRadius: CURRENCY_LINE_THICKNESS,
  },
  currencyChartPoint: {
    position: 'absolute',
    width: CURRENCY_DOT_SIZE,
    height: CURRENCY_DOT_SIZE,
    borderRadius: CURRENCY_DOT_SIZE / 2,
    borderWidth: 2,
  },
  currencyMissingPoint: {
    position: 'absolute',
    width: CURRENCY_DOT_SIZE,
    height: CURRENCY_DOT_SIZE,
    borderRadius: CURRENCY_DOT_SIZE / 2,
    borderWidth: 1,
    borderStyle: 'dashed',
  },
  currencyPointValue: {
    position: 'absolute',
    width: 48,
    textAlign: 'center',
    fontSize: 9,
    lineHeight: 12,
  },
  currencyBarsRow: {
    flex: 1,
    height: CURRENCY_CHART_HEIGHT,
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-around',
    gap: tokens.space.xs,
    paddingHorizontal: tokens.space.xs,
    paddingTop: tokens.space.md,
  },
  currencyBarSlot: { flex: 1, minWidth: 34, alignItems: 'center', justifyContent: 'flex-end' },
  currencyBarValue: { marginBottom: 4, fontSize: 9, lineHeight: 12, textAlign: 'center' },
  currencyBar: { width: 22, minHeight: 3, borderRadius: 6 },
  currencyChartXAxisRow: { flexDirection: 'row', alignItems: 'center', gap: tokens.space.sm },
  currencyChartXAxisSpacer: { width: CURRENCY_AXIS_WIDTH },
  currencyChartXAxisLabels: {
    flex: 1,
    minWidth: 0,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-around',
    gap: tokens.space.xs,
  },
  currencyConverterStack: { gap: tokens.space.sm },
  currencyConverterItem: { gap: 2 },
  currencyConverterRow: { flexDirection: 'row', alignItems: 'center', gap: tokens.space.xs },
  currencyConverterInput: { flex: 1 },
  categoryDrillGroup: { gap: 4 },
  categoryDrillRipple: { borderRadius: tokens.radius.md, overflow: 'hidden' },
  categoryDrillHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.xs,
    paddingRight: tokens.space.xs,
  },
  subcategoryStack: {
    marginLeft: tokens.space.md,
    paddingLeft: tokens.space.sm,
    borderLeftWidth: 2,
    borderLeftColor: 'rgba(128,128,128,0.24)',
    gap: 2,
  },
  subcategoryRipple: { borderRadius: tokens.radius.md, overflow: 'hidden' },
  subcategoryRow: { paddingLeft: tokens.space.xs },
  categoryRecordsModal: {
    margin: tokens.space.lg,
    borderRadius: tokens.radius.lg,
    borderWidth: StyleSheet.hairlineWidth,
    maxHeight: '78%',
  },
  categoryRecordsModalContent: { padding: tokens.space.md, gap: tokens.space.sm },
  categoryRecordsHeader: { flexDirection: 'row', alignItems: 'center', gap: tokens.space.sm },
  categoryRecordsScroll: { maxHeight: 420 },
  barRow: { gap: 6, paddingVertical: 6 },
  barHeader: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  progress: { height: 6, borderRadius: 3 },
  trendCard: {
    borderRadius: tokens.radius.md,
    padding: tokens.space.md,
    gap: tokens.space.xs,
  },
  trendChartBody: { flexDirection: 'row', alignItems: 'stretch', gap: tokens.space.sm },
  trendAxis: { width: TREND_AXIS_WIDTH, height: TREND_CHART_HEIGHT, position: 'relative' },
  trendAxisLabel: {
    position: 'absolute',
    right: 0,
    width: TREND_AXIS_WIDTH,
    textAlign: 'right',
    fontSize: 9,
    lineHeight: 12,
  },
  trendPlotArea: {
    flex: 1,
    minWidth: 0,
    height: TREND_CHART_HEIGHT,
    overflow: 'hidden',
    position: 'relative',
  },
  trendGridLine: {
    position: 'absolute',
    left: 0,
    right: 0,
    height: StyleSheet.hairlineWidth,
    opacity: 0.7,
  },
  trendSegment: {
    position: 'absolute',
    height: TREND_LINE_THICKNESS,
    borderRadius: 2,
  },
  trendEventDot: {
    position: 'absolute',
    width: TREND_DOT_SIZE,
    height: TREND_DOT_SIZE,
    borderRadius: TREND_DOT_SIZE / 2,
    borderWidth: 1,
  },
  trendDot: {
    position: 'absolute',
    width: TREND_DOT_SIZE,
    height: TREND_DOT_SIZE,
    borderRadius: TREND_DOT_SIZE / 2,
    borderWidth: 2,
  },
  trendDotLatest: {
    width: TREND_LATEST_DOT_SIZE,
    height: TREND_LATEST_DOT_SIZE,
    borderRadius: TREND_LATEST_DOT_SIZE / 2,
  },
  trendCursor: {
    position: 'absolute',
    top: 0,
    bottom: 0,
    width: StyleSheet.hairlineWidth,
    opacity: 0.82,
  },
  trendTooltip: {
    position: 'absolute',
    width: TREND_TOOLTIP_WIDTH,
    minHeight: 56,
    borderRadius: tokens.radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    padding: tokens.space.sm,
    gap: 2,
  },
  trendTooltipAmount: { fontFamily: numericMediumFontFamily, fontWeight: '800' },
  currencyRateLegend: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: tokens.space.sm,
    paddingLeft: TREND_AXIS_WIDTH + tokens.space.sm,
  },
  currencyRateLegendItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
  },
  currencyRateLegendSwatch: {
    width: 18,
    height: 4,
    borderRadius: 2,
  },
  trendLabelRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: tokens.space.sm,
  },
  trendSummaryRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: tokens.space.md,
  },
  trendXAxisRow: { flexDirection: 'row', alignItems: 'center', gap: tokens.space.sm },
  trendXAxisSpacer: { width: TREND_AXIS_WIDTH },
  trendXAxisLabels: {
    flex: 1,
    minWidth: 0,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: tokens.space.sm,
  },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 6 },
  fill: { flex: 1, minWidth: 0 },
  mutedText: { color: tokens.color.md3.dark.onSurfaceVariant },
  dangerText: { color: tokens.color.md3Danger, fontWeight: '800' },
  positiveText: { color: tokens.color.md3Positive, fontWeight: '800' },
});
