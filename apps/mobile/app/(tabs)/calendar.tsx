import type { Money } from '@1wallet/domain/money';
import { formatMoney, fromMinor } from '@1wallet/domain/money';
import type { Account, Category, Transaction } from '@1wallet/domain/types';
import type { FutureRuleOccurrence } from '@1wallet/ledger/rules/futureGeneration';
import {
  forecastFutureRuleOccurrences,
  futureRuleInterestExternalRef,
} from '@1wallet/ledger/rules/futureGeneration';
import { rateBetween } from '@1wallet/ledger/services';
import type { FutureGenerationRule } from '@1wallet/ledger/store/types';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { router } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import {
  Appbar,
  Button,
  Divider,
  IconButton,
  Modal,
  Portal,
  Surface,
  Text,
  TouchableRipple,
  useTheme,
} from 'react-native-paper';
import { SafeAreaView } from 'react-native-safe-area-context';
import { accountTypeLabel, resolveAccountIconVisual } from '../../src/accountOptions';
import { openAddRecord } from '../../src/addRecordNavigation';
import { resolveCategoryIconVisual } from '../../src/categoryIcons';
import { useBackLayer } from '../../src/components/AppBackLayer';
import { useAppDrawer } from '../../src/components/AppDrawerHost';
import {
  AppMenuAction,
  PremiumRow,
  PremiumSearchInput,
  TAB_BAR_OVERLAY_CLEARANCE,
} from '../../src/components/AppKit';
import {
  OptionListOverlay,
  OptionSelectorRow,
  type OptionListItem,
} from '../../src/components/OptionListOverlay';
import { numericMediumFontFamily } from '../../src/fonts';
import { iconSurfaceForThemeTone } from '../../src/iconSystem';
import {
  runAfterInteractionsWithTimeout,
  type DeferredInteractionTask,
} from '../../src/interactionScheduler';
import {
  EXPENSE_TRANSACTION_TYPES as EXPENSE_TYPES,
  INCOME_TRANSACTION_TYPES as INCOME_TYPES,
  transactionTypeLabel,
} from '../../src/transactionTypes';

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTH_ARROW_HIT_SLOP = { top: 14, bottom: 14, left: 18, right: 18 };
const MAX_CALENDAR_OCCURRENCES_PER_RULE = 96;
const MAX_BALANCE_OCCURRENCES_PER_RULE = 720;
const EMPTY_SUMMARIES_BY_DAY = new Map<string, DaySummary>();
const EMPTY_MONTH_TOTALS: MonthTotals = {
  incomeMinor: 0,
  expenseMinor: 0,
  plannedIncomeMinor: 0,
  plannedExpenseMinor: 0,
  plannedCount: 0,
  count: 0,
};

type DayEntryKind = 'income' | 'expense';
type DayEntryBase = {
  amountMinor: number;
  kind: DayEntryKind;
  planned: boolean;
};
type DayTransaction = DayEntryBase &
  (
    | { source: 'transaction'; transaction: Transaction }
    | { source: 'forecast'; occurrence: FutureRuleOccurrence; rule: FutureGenerationRule }
  );
type DaySummary = {
  incomeMinor: number;
  expenseMinor: number;
  plannedIncomeMinor: number;
  plannedExpenseMinor: number;
  plannedCount: number;
  transactions: DayTransaction[];
};
type CalendarDay = {
  key: string;
  date: Date;
  inMonth: boolean;
  isToday: boolean;
};

type SplitTotalsByTransaction = Map<string, Map<string, number>>;
type CategoryFilterValue = '__all' | string;
type MonthTotals = {
  incomeMinor: number;
  expenseMinor: number;
  plannedIncomeMinor: number;
  plannedExpenseMinor: number;
  plannedCount: number;
  count: number;
};

const ALL_CATEGORIES_VALUE = '__all';

export default function Calendar() {
  const theme = useTheme();
  const { openDrawer } = useAppDrawer();
  const { state, indexes } = useLedger();
  const [visibleMonth, setVisibleMonth] = useState(() => startOfMonth(new Date()));
  const [calculationMonth, setCalculationMonth] = useState(() => startOfMonth(new Date()));
  const [selectedCategoryId, setSelectedCategoryId] = useState<string | undefined>();
  const [categoryPickerVisible, setCategoryPickerVisible] = useState(false);
  const [accountPickerVisible, setAccountPickerVisible] = useState(false);
  const [selectedAccountIdsOverride, setSelectedAccountIdsOverride] = useState<
    string[] | undefined
  >();
  const [selectedDayKey, setSelectedDayKey] = useState<string | undefined>();
  const visibleMonthRef = useRef(visibleMonth);
  const calculationTaskRef = useRef<DeferredInteractionTask | null>(null);

  const baseCurrency = state.preferences.baseCurrency;
  const locale = state.preferences.locale;

  const monthStart = useMemo(() => startOfMonth(visibleMonth), [visibleMonth]);
  const calculationMonthStart = useMemo(() => startOfMonth(calculationMonth), [calculationMonth]);
  const calculationMonthEnd = useMemo(
    () => addMonths(calculationMonthStart, 1),
    [calculationMonthStart],
  );
  const calendarDataPending = monthStart.getTime() !== calculationMonthStart.getTime();
  const calendarDays = useMemo(() => buildCalendarDays(monthStart), [monthStart]);
  const calendarWeeks = useMemo(() => chunkCalendarDays(calendarDays), [calendarDays]);
  const calculationCalendarDays = useMemo(
    () => buildCalendarDays(calculationMonthStart),
    [calculationMonthStart],
  );
  const calculationGridStart = calculationCalendarDays[0]?.date ?? calculationMonthStart;
  const calculationGridEnd = addDays(
    calculationCalendarDays[calculationCalendarDays.length - 1]?.date ?? calculationMonthEnd,
    1,
  );

  useEffect(() => {
    visibleMonthRef.current = visibleMonth;
  }, [visibleMonth]);

  useEffect(
    () => () => {
      calculationTaskRef.current?.cancel();
      calculationTaskRef.current = null;
    },
    [],
  );

  const scheduleCalendarCalculation = useCallback((nextMonth: Date) => {
    calculationTaskRef.current?.cancel();
    calculationTaskRef.current = runAfterInteractionsWithTimeout(() => {
      calculationTaskRef.current = null;
      setCalculationMonth(startOfMonth(nextMonth));
    }, 220);
  }, []);
  const activeAccounts = useMemo(
    () =>
      state.accounts
        .filter((account) => !account.isArchived)
        .sort(
          (left, right) => left.sortOrder - right.sortOrder || left.name.localeCompare(right.name),
        ),
    [state.accounts],
  );
  const defaultForecastAccountIds = useMemo(
    () => activeAccounts.filter(isDefaultForecastAccount).map((account) => account.id),
    [activeAccounts],
  );
  const selectedAccountIds = useMemo(
    () =>
      normalizeSelectedAccountIds(
        selectedAccountIdsOverride ?? defaultForecastAccountIds,
        activeAccounts,
      ),
    [activeAccounts, defaultForecastAccountIds, selectedAccountIdsOverride],
  );
  const selectedAccountIdSet = useMemo(() => new Set(selectedAccountIds), [selectedAccountIds]);
  const selectedAccountLabel = useMemo(
    () => formatAccountFilterLabel(activeAccounts, selectedAccountIds, defaultForecastAccountIds),
    [activeAccounts, defaultForecastAccountIds, selectedAccountIds],
  );

  const categories = useMemo(
    () =>
      state.categories
        .filter((category) => !category.isArchived)
        .sort(
          (left, right) => left.sortOrder - right.sortOrder || left.name.localeCompare(right.name),
        ),
    [state.categories],
  );
  const selectedCategory = categories.find((category) => category.id === selectedCategoryId);
  const categoryOptions = useMemo<OptionListItem<CategoryFilterValue>[]>(
    () => [
      {
        value: ALL_CATEGORIES_VALUE,
        label: 'All categories',
        description: 'Income and expense forecast for the full month',
        icon: 'calendar-month-outline',
      },
      ...categories.map((category) => {
        const visual = resolveCategoryIconVisual(category, categories);
        return {
          value: category.id,
          label: category.name,
          description: 'Category',
          icon: visual.icon,
          iconBackgroundColor: visual.backgroundColor,
          iconColor: visual.iconColor,
        };
      }),
    ],
    [categories],
  );

  const categoryById = indexes.categoriesById;
  const selectedCategoryVisual = selectedCategory
    ? resolveCategoryIconVisual(selectedCategory, categories)
    : undefined;
  const accountById = indexes.accountsById;
  const splitTotalsByTransaction = useMemo(
    () => buildSplitTotalsByTransaction(state.transactionSplits),
    [state.transactionSplits],
  );
  const rulesById = useMemo(
    () => new Map((state.preferences.futureGenerationRules ?? []).map((rule) => [rule.id, rule])),
    [state.preferences.futureGenerationRules],
  );
  const balanceForecastWindowStart = useMemo(
    () => minDate(startOfDay(new Date()), calculationGridStart),
    [calculationGridStart],
  );
  const balanceForecastWindowEnd = useMemo(
    () => maxDate(calculationGridEnd, calculationMonthEnd),
    [calculationGridEnd, calculationMonthEnd],
  );
  const calendarForecastOccurrences = useMemo(
    () =>
      forecastFutureRuleOccurrences(state, {
        from: calculationGridStart,
        to: calculationGridEnd,
        now: calculationGridStart,
        maxOccurrencesPerRule: MAX_CALENDAR_OCCURRENCES_PER_RULE,
      }),
    [calculationGridEnd, calculationGridStart, state],
  );
  const balanceForecastOccurrences = useMemo(
    () =>
      forecastFutureRuleOccurrences(state, {
        from: balanceForecastWindowStart,
        to: balanceForecastWindowEnd,
        now: balanceForecastWindowStart,
        maxOccurrencesPerRule: MAX_BALANCE_OCCURRENCES_PER_RULE,
      }),
    [balanceForecastWindowEnd, balanceForecastWindowStart, state],
  );

  const summariesByDay = useMemo(() => {
    const summaries = new Map<string, DaySummary>();
    const from = calculationGridStart.toISOString();
    const to = calculationGridEnd.toISOString();
    const transactions: Transaction[] = [];

    for (const transaction of indexes.allTransactionsSorted) {
      if (transaction.occurredAt >= to) continue;
      if (transaction.occurredAt < from) break;
      transactions.push(transaction);
    }

    for (const transaction of transactions) {
      if (isLinkedLoanInterestTransaction(transaction, state)) continue;
      if (!isReportableTransaction(transaction, state, selectedAccountIdSet)) continue;

      const amountMinor = amountForCategoryFilter(
        transaction,
        selectedCategoryId,
        splitTotalsByTransaction,
        state,
        baseCurrency,
      );
      if (amountMinor <= 0) continue;

      const kind = entryKindForTransaction(transaction);
      if (!kind) continue;
      const planned = isPlannedTransaction(transaction);

      const key = dateKeyFromIso(transaction.occurredAt);
      const summary = summaries.get(key) ?? emptyDaySummary();

      if (kind === 'income') summary.incomeMinor += amountMinor;
      if (kind === 'expense') summary.expenseMinor += amountMinor;
      if (planned && kind === 'income') summary.plannedIncomeMinor += amountMinor;
      if (planned && kind === 'expense') summary.plannedExpenseMinor += amountMinor;
      if (planned) summary.plannedCount += 1;
      summary.transactions.push({ source: 'transaction', transaction, amountMinor, kind, planned });
      summaries.set(key, summary);
    }

    for (const occurrence of calendarForecastOccurrences) {
      if (occurrence.occurredAt >= to || occurrence.occurredAt < from) continue;
      if (indexes.transactionsByExternalRef.has(occurrence.externalRef)) continue;
      const rule = rulesById.get(occurrence.ruleId);
      if (!rule) continue;
      if (!isReportableForecastOccurrence(occurrence, state, selectedAccountIdSet)) continue;

      const amountMinor = amountForForecastCategoryFilter(
        occurrence,
        selectedCategoryId,
        state,
        baseCurrency,
      );
      if (amountMinor <= 0) continue;

      const kind = entryKindForTransactionType(occurrence.type);
      if (!kind) continue;

      const key = dateKeyFromIso(occurrence.occurredAt);
      const summary = summaries.get(key) ?? emptyDaySummary();
      if (kind === 'income') summary.incomeMinor += amountMinor;
      if (kind === 'expense') summary.expenseMinor += amountMinor;
      if (kind === 'income') summary.plannedIncomeMinor += amountMinor;
      if (kind === 'expense') summary.plannedExpenseMinor += amountMinor;
      summary.plannedCount += 1;
      summary.transactions.push({
        source: 'forecast',
        occurrence,
        rule,
        amountMinor,
        kind,
        planned: true,
      });
      summaries.set(key, summary);
    }

    return summaries;
  }, [
    calculationGridEnd,
    calculationGridStart,
    baseCurrency,
    calendarForecastOccurrences,
    rulesById,
    indexes.transactionsByExternalRef,
    selectedAccountIdSet,
    selectedCategoryId,
    indexes.allTransactionsSorted,
    splitTotalsByTransaction,
    state,
  ]);

  const monthTotals = useMemo<MonthTotals>(() => {
    if (calendarDataPending) return EMPTY_MONTH_TOTALS;
    return calendarDays.reduce(
      (totals, day) => {
        if (!day.inMonth) return totals;
        const summary = summariesByDay.get(day.key);
        if (!summary) return totals;
        return {
          incomeMinor: totals.incomeMinor + summary.incomeMinor,
          expenseMinor: totals.expenseMinor + summary.expenseMinor,
          plannedIncomeMinor: totals.plannedIncomeMinor + summary.plannedIncomeMinor,
          plannedExpenseMinor: totals.plannedExpenseMinor + summary.plannedExpenseMinor,
          plannedCount: totals.plannedCount + summary.plannedCount,
          count: totals.count + summary.transactions.length,
        };
      },
      {
        incomeMinor: 0,
        expenseMinor: 0,
        plannedIncomeMinor: 0,
        plannedExpenseMinor: 0,
        plannedCount: 0,
        count: 0,
      },
    );
  }, [calendarDataPending, calendarDays, summariesByDay]);
  const forecastNetMinor = useMemo(() => {
    return (
      projectedBalanceForAccountsThroughDateFromIndexes(
        state,
        indexes,
        selectedAccountIds,
        calculationMonthEnd,
        baseCurrency,
      ).amountMinor +
      virtualForecastDeltaForAccountsThroughDate(
        state,
        selectedAccountIds,
        calculationMonthEnd,
        baseCurrency,
        balanceForecastOccurrences,
        indexes.transactionsByExternalRef,
      )
    );
  }, [
    baseCurrency,
    calculationMonthEnd,
    balanceForecastOccurrences,
    indexes,
    selectedAccountIds,
    state,
  ]);
  const displaySummariesByDay = calendarDataPending ? EMPTY_SUMMARIES_BY_DAY : summariesByDay;

  const selectedSummary = selectedDayKey ? displaySummariesByDay.get(selectedDayKey) : undefined;
  const selectedDayLabel = selectedDayKey ? formatDayTitle(selectedDayKey, locale) : '';

  const moveMonth = useCallback(
    (offset: number) => {
      const nextMonth = addMonths(visibleMonthRef.current, offset);
      visibleMonthRef.current = nextMonth;
      setSelectedDayKey(undefined);
      setVisibleMonth(nextMonth);
      scheduleCalendarCalculation(nextMonth);
    },
    [scheduleCalendarCalculation],
  );

  const toggleAccountFilter = (accountId: string) => {
    setSelectedDayKey(undefined);
    setSelectedAccountIdsOverride((current) => {
      const source = current ?? selectedAccountIds;
      return source.includes(accountId)
        ? source.filter((selectedId) => selectedId !== accountId)
        : [...source, accountId];
    });
  };

  const resetAccountFilter = () => {
    setSelectedDayKey(undefined);
    setSelectedAccountIdsOverride(undefined);
  };

  const selectAllAccounts = () => {
    setSelectedDayKey(undefined);
    setSelectedAccountIdsOverride(activeAccounts.map((account) => account.id));
  };

  const clearAccountFilter = () => {
    setSelectedDayKey(undefined);
    setSelectedAccountIdsOverride([]);
  };

  return (
    <View style={[styles.screen, { backgroundColor: theme.colors.background }]}>
      <Appbar.Header elevated={false} style={{ backgroundColor: theme.colors.background }}>
        <AppMenuAction onPress={openDrawer} />
        <Appbar.Content title="Calendar" titleStyle={styles.appbarTitle} />
        <Appbar.Action icon="plus" onPress={() => openAddRecord({ entryOrigin: 'top' })} />
      </Appbar.Header>

      <ScrollView
        style={styles.contentScroll}
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}
      >
        <Surface
          style={[
            styles.monthCard,
            {
              backgroundColor: theme.colors.elevation.level1,
              borderColor: theme.colors.outlineVariant,
            },
          ]}
          elevation={1}
        >
          <View style={styles.monthHeader}>
            <IconButton
              icon="chevron-left"
              accessibilityLabel="Previous month"
              hitSlop={MONTH_ARROW_HIT_SLOP}
              style={styles.monthArrowButton}
              onPress={() => moveMonth(-1)}
            />
            <View style={styles.monthCopy}>
              <Text variant="titleLarge" style={styles.monthTitle}>
                {formatMonthTitle(monthStart, locale)}
              </Text>
              <Text
                variant="bodySmall"
                numberOfLines={1}
                style={{ color: theme.colors.onSurfaceVariant }}
              >
                {selectedCategory ? selectedCategory.name : 'All categories'} ·{' '}
                {selectedAccountLabel}
              </Text>
            </View>
            <IconButton
              icon="chevron-right"
              accessibilityLabel="Next month"
              hitSlop={MONTH_ARROW_HIT_SLOP}
              style={styles.monthArrowButton}
              onPress={() => moveMonth(1)}
            />
          </View>

          <View style={styles.summaryRow}>
            <SummaryPill
              label="Net"
              amount={{ amountMinor: forecastNetMinor, currency: baseCurrency }}
              color={balanceColor(forecastNetMinor, theme.dark, theme.colors.onSurfaceVariant)}
              locale={locale}
            />
            <SummaryPill
              label="Income"
              amount={{ amountMinor: monthTotals.incomeMinor, currency: baseCurrency }}
              color={incomeColor(theme.dark)}
              locale={locale}
            />
            <SummaryPill
              label="Expense"
              amount={{ amountMinor: monthTotals.expenseMinor, currency: baseCurrency }}
              color={expenseColor(theme.dark, theme.colors.error)}
              locale={locale}
            />
          </View>
          <Text variant="labelSmall" style={{ color: theme.colors.onSurfaceVariant }}>
            {calendarDataPending
              ? 'Updating month...'
              : monthTotals.plannedCount > 0
                ? `${monthTotals.plannedCount} planned records included`
                : 'Actual records only'}
          </Text>
          <View style={styles.filterRow}>
            <OptionSelectorRow
              label="Category"
              value={selectedCategory?.name ?? 'All categories'}
              description="Month forecast"
              icon={selectedCategoryVisual?.icon ?? 'shape-outline'}
              iconBackgroundColor={selectedCategoryVisual?.backgroundColor}
              iconColor={selectedCategoryVisual?.iconColor}
              compact
              style={styles.filterSelector}
              onPress={() => setCategoryPickerVisible(true)}
            />
            <OptionSelectorRow
              label="Accounts"
              value={selectedAccountLabel}
              description="Running Net"
              icon="bank-outline"
              compact
              style={styles.filterSelector}
              onPress={() => setAccountPickerVisible(true)}
            />
          </View>
        </Surface>

        <Surface
          style={[
            styles.calendarCard,
            {
              backgroundColor: theme.colors.elevation.level1,
              borderColor: theme.colors.outlineVariant,
            },
          ]}
          elevation={1}
        >
          <View style={styles.weekRow}>
            {WEEKDAYS.map((day) => (
              <Text
                key={day}
                variant="labelSmall"
                style={[styles.weekday, { color: theme.colors.onSurfaceVariant }]}
              >
                {day}
              </Text>
            ))}
          </View>
          <View style={styles.grid}>
            {calendarWeeks.map((week) => (
              <View key={week[0]?.key ?? 'week'} style={styles.gridWeek}>
                {week.map((day) => {
                  const summary = displaySummariesByDay.get(day.key) ?? emptyDaySummary();
                  const hasTransactions = summary.transactions.length > 0;
                  return (
                    <TouchableRipple
                      key={day.key}
                      style={styles.daySlot}
                      borderless
                      hitSlop={2}
                      disabled={!hasTransactions}
                      onPress={() => setSelectedDayKey(day.key)}
                    >
                      <Surface
                        style={[
                          styles.dayCell,
                          {
                            backgroundColor: day.isToday
                              ? theme.colors.primaryContainer
                              : theme.colors.elevation.level2,
                            borderColor: day.isToday
                              ? theme.colors.primary
                              : theme.colors.outlineVariant,
                            opacity: day.inMonth ? 1 : 0.45,
                          },
                        ]}
                        elevation={day.isToday ? 2 : 0}
                      >
                        <View style={styles.dayHeader}>
                          <Text
                            variant="labelMedium"
                            numberOfLines={1}
                            adjustsFontSizeToFit
                            minimumFontScale={0.8}
                            style={{
                              color: day.isToday
                                ? theme.colors.onPrimaryContainer
                                : theme.colors.onSurface,
                              fontWeight: '800',
                            }}
                          >
                            {day.date.getDate()}
                          </Text>
                          {hasTransactions ? (
                            <View style={[styles.dot, { backgroundColor: theme.colors.primary }]} />
                          ) : null}
                        </View>
                        <View style={styles.dayAmounts}>
                          {summary.incomeMinor > 0 ? (
                            <Text
                              variant="labelSmall"
                              numberOfLines={1}
                              adjustsFontSizeToFit
                              minimumFontScale={0.75}
                              style={[styles.dayAmount, { color: incomeColor(theme.dark) }]}
                            >
                              +{formatCompactMoney(summary.incomeMinor, baseCurrency, locale)}
                            </Text>
                          ) : null}
                          {summary.expenseMinor > 0 ? (
                            <Text
                              variant="labelSmall"
                              numberOfLines={1}
                              adjustsFontSizeToFit
                              minimumFontScale={0.75}
                              style={[
                                styles.dayAmount,
                                { color: expenseColor(theme.dark, theme.colors.error) },
                              ]}
                            >
                              -{formatCompactMoney(summary.expenseMinor, baseCurrency, locale)}
                            </Text>
                          ) : null}
                        </View>
                      </Surface>
                    </TouchableRipple>
                  );
                })}
              </View>
            ))}
          </View>
        </Surface>
      </ScrollView>

      <OptionListOverlay
        visible={categoryPickerVisible}
        title="Calendar category"
        options={categoryOptions}
        selectedValue={selectedCategoryId ?? ALL_CATEGORIES_VALUE}
        searchPlaceholder="Search categories"
        onDismiss={() => setCategoryPickerVisible(false)}
        onSelect={(option) => {
          setSelectedCategoryId(option.value === ALL_CATEGORIES_VALUE ? undefined : option.value);
          setSelectedDayKey(undefined);
          setCategoryPickerVisible(false);
        }}
      />

      <AccountFilterOverlay
        visible={accountPickerVisible}
        accounts={activeAccounts}
        selectedIds={selectedAccountIds}
        defaultIds={defaultForecastAccountIds}
        onDismiss={() => setAccountPickerVisible(false)}
        onToggle={toggleAccountFilter}
        onSelectDefault={resetAccountFilter}
        onSelectAll={selectAllAccounts}
        onClear={clearAccountFilter}
      />

      <Portal>
        <Modal
          visible={Boolean(selectedDayKey)}
          onDismiss={() => setSelectedDayKey(undefined)}
          contentContainerStyle={[
            styles.modal,
            {
              backgroundColor: theme.colors.elevation.level2,
              borderColor: theme.colors.outlineVariant,
            },
          ]}
        >
          <View style={styles.modalHeader}>
            <View style={styles.fill}>
              <Text variant="titleLarge" style={styles.modalTitle}>
                {selectedDayLabel}
              </Text>
              <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                {selectedCategory ? selectedCategory.name : 'All categories'}
              </Text>
            </View>
            <IconButton icon="close" onPress={() => setSelectedDayKey(undefined)} />
          </View>

          {selectedSummary ? (
            <>
              <View style={styles.summaryRow}>
                <SummaryPill
                  label="Income"
                  amount={{ amountMinor: selectedSummary.incomeMinor, currency: baseCurrency }}
                  color={incomeColor(theme.dark)}
                  locale={locale}
                />
                <SummaryPill
                  label="Spent"
                  amount={{ amountMinor: selectedSummary.expenseMinor, currency: baseCurrency }}
                  color={expenseColor(theme.dark, theme.colors.error)}
                  locale={locale}
                />
              </View>
              <Divider />
              <ScrollView style={styles.dayList} showsVerticalScrollIndicator={false}>
                {selectedSummary.transactions.map((entry) => (
                  <CalendarTransactionRow
                    key={dayEntryKey(entry)}
                    entry={entry}
                    category={categoryById.get(dayEntryCategoryId(entry) ?? '')}
                    accountName={accountById.get(dayEntryAccountId(entry))?.name}
                    locale={locale}
                    currency={baseCurrency}
                    onPress={() => {
                      setSelectedDayKey(undefined);
                      if (entry.source === 'forecast') {
                        router.push(`/recurring/${entry.rule.id}` as never);
                      } else {
                        router.push(`/transaction/${entry.transaction.id}` as never);
                      }
                    }}
                  />
                ))}
              </ScrollView>
            </>
          ) : null}
        </Modal>
      </Portal>
    </View>
  );
}

function SummaryPill({
  label,
  amount,
  color,
  locale,
}: {
  label: string;
  amount: Money;
  color: string;
  locale: string;
}) {
  const theme = useTheme();
  return (
    <Surface
      style={[
        styles.summaryPill,
        {
          backgroundColor: theme.colors.elevation.level2,
          borderColor: theme.colors.outlineVariant,
        },
      ]}
      elevation={0}
    >
      <Text variant="labelSmall" style={{ color: theme.colors.onSurfaceVariant }}>
        {label}
      </Text>
      <Text
        variant="labelLarge"
        numberOfLines={1}
        adjustsFontSizeToFit
        minimumFontScale={0.72}
        style={{ color, fontFamily: numericMediumFontFamily, fontWeight: '800' }}
      >
        {formatMoney(amount, locale)}
      </Text>
    </Surface>
  );
}

function CalendarTransactionRow({
  entry,
  category,
  accountName,
  locale,
  currency,
  onPress,
}: {
  entry: DayTransaction;
  category?: Category;
  accountName?: string;
  locale: string;
  currency: string;
  onPress: () => void;
}) {
  const theme = useTheme();
  const amountColor =
    entry.kind === 'income'
      ? incomeColor(theme.dark)
      : expenseColor(theme.dark, theme.colors.error);
  const iconSurface = iconSurfaceForThemeTone(
    theme,
    entry.planned ? 'plan' : entry.kind === 'income' ? 'income' : 'expense',
  );
  const sign = entry.kind === 'income' ? '+' : '-';
  const title =
    entry.source === 'forecast'
      ? (category?.name ?? entry.rule.name)
      : (category?.name ?? transactionTypeLabel(entry.transaction.type));
  const notes = entry.source === 'forecast' ? entry.occurrence.notes : entry.transaction.notes;
  const subtitleSuffix =
    entry.source === 'forecast' ? ' - Forecast' : entry.planned ? ' - Planned' : '';

  return (
    <TouchableRipple borderless style={styles.transactionRipple} onPress={onPress}>
      <View style={styles.transactionRow}>
        <View style={[styles.transactionIcon, { backgroundColor: iconSurface.backgroundColor }]}>
          <MaterialCommunityIcons
            name={
              entry.planned
                ? 'calendar-clock-outline'
                : entry.kind === 'income'
                  ? 'arrow-down-left'
                  : 'arrow-up-right'
            }
            size={20}
            color={iconSurface.iconColor}
          />
        </View>
        <View style={styles.transactionCopy}>
          <Text variant="titleSmall" numberOfLines={1} style={{ color: theme.colors.onSurface }}>
            {title}
          </Text>
          <Text
            variant="bodySmall"
            numberOfLines={1}
            style={{ color: theme.colors.onSurfaceVariant }}
          >
            {accountName ?? 'Missing account'}
            {subtitleSuffix}
            {notes ? ` · ${notes}` : ''}
          </Text>
        </View>
        <Text
          variant="titleSmall"
          numberOfLines={1}
          style={{ color: amountColor, fontFamily: numericMediumFontFamily, fontWeight: '800' }}
        >
          {sign} {formatMoney({ amountMinor: entry.amountMinor, currency }, locale)}
        </Text>
      </View>
    </TouchableRipple>
  );
}

function AccountFilterOverlay({
  visible,
  accounts,
  selectedIds,
  defaultIds,
  onDismiss,
  onToggle,
  onSelectDefault,
  onSelectAll,
  onClear,
}: {
  visible: boolean;
  accounts: Account[];
  selectedIds: string[];
  defaultIds: string[];
  onDismiss: () => void;
  onToggle: (accountId: string) => void;
  onSelectDefault: () => void;
  onSelectAll: () => void;
  onClear: () => void;
}) {
  const theme = useTheme();
  const [query, setQuery] = useState('');

  useBackLayer(visible, onDismiss);

  useEffect(() => {
    if (!visible) setQuery('');
  }, [visible]);

  const selectedIdSet = useMemo(() => new Set(selectedIds), [selectedIds]);
  const filteredAccounts = useMemo(() => {
    const normalized = query.trim().toLowerCase();
    if (!normalized) return accounts;
    return accounts.filter((account) =>
      [account.name, account.institution ?? '', accountTypeLabel(account.type), account.currency]
        .join(' ')
        .toLowerCase()
        .includes(normalized),
    );
  }, [accounts, query]);
  const usingDefault = sameSelection(selectedIds, defaultIds);

  if (!visible) return null;

  return (
    <Portal>
      <Surface
        style={[styles.fullScreenOverlay, { backgroundColor: theme.colors.background }]}
        elevation={0}
      >
        <SafeAreaView style={styles.overlaySafeArea} edges={['top', 'left', 'right']}>
          <Appbar.Header elevated={false} style={{ backgroundColor: theme.colors.background }}>
            <Appbar.BackAction onPress={onDismiss} />
            <Appbar.Content title="Calendar accounts" titleStyle={styles.appbarTitle} />
            <Appbar.Action icon="check" accessibilityLabel="Done" onPress={onDismiss} />
          </Appbar.Header>
          <View style={styles.overlayContent}>
            {accounts.length > 8 ? (
              <PremiumSearchInput
                placeholder="Search accounts"
                value={query}
                onChangeText={setQuery}
              />
            ) : null}
            <View style={styles.filterActionRow}>
              <Button
                compact
                mode={usingDefault ? 'contained-tonal' : 'outlined'}
                onPress={onSelectDefault}
              >
                Default
              </Button>
              <Button compact mode="outlined" onPress={onSelectAll}>
                All
              </Button>
              <Button compact mode="outlined" onPress={onClear}>
                None
              </Button>
            </View>
            <ScrollView
              contentContainerStyle={styles.accountListContent}
              keyboardShouldPersistTaps="handled"
              showsVerticalScrollIndicator={false}
            >
              {filteredAccounts.length === 0 ? (
                <View style={styles.emptyAccountState}>
                  <MaterialCommunityIcons
                    name="text-search"
                    size={28}
                    color={theme.colors.onSurfaceVariant}
                  />
                  <Text variant="bodyMedium" style={{ color: theme.colors.onSurfaceVariant }}>
                    No accounts found
                  </Text>
                </View>
              ) : (
                filteredAccounts.map((account) => {
                  const visual = resolveAccountIconVisual(account);
                  return (
                    <PremiumRow
                      key={account.id}
                      icon={visual.icon}
                      iconBackgroundColor={visual.backgroundColor}
                      iconColor={visual.iconColor}
                      title={account.name}
                      titleNumberOfLines={2}
                      subtitle={accountFilterSubtitle(account)}
                      meta={account.currency}
                      selected={selectedIdSet.has(account.id)}
                      onPress={() => onToggle(account.id)}
                    />
                  );
                })
              )}
            </ScrollView>
          </View>
        </SafeAreaView>
      </Surface>
    </Portal>
  );
}

function buildCalendarDays(monthStart: Date): CalendarDay[] {
  const startOffset = monthStart.getDay();
  const gridStart = addDays(monthStart, -startOffset);
  const nextMonthStart = addMonths(monthStart, 1);
  const monthEnd = addDays(nextMonthStart, -1);
  const endOffset = 6 - monthEnd.getDay();
  const gridEnd = addDays(monthEnd, endOffset);
  const dayCount = daysBetween(gridStart, gridEnd) + 1;
  const todayKey = dateKey(new Date());

  return Array.from({ length: dayCount }, (_, index) => {
    const date = addDays(gridStart, index);
    const key = dateKey(date);
    return {
      key,
      date,
      inMonth: date.getMonth() === monthStart.getMonth(),
      isToday: key === todayKey,
    };
  });
}

function chunkCalendarDays(days: CalendarDay[]): CalendarDay[][] {
  const weeks: CalendarDay[][] = [];
  for (let index = 0; index < days.length; index += 7) {
    weeks.push(days.slice(index, index + 7));
  }
  return weeks;
}

function buildSplitTotalsByTransaction(
  splits: { transactionId: string; categoryId?: string; amount: Money }[],
): SplitTotalsByTransaction {
  const map: SplitTotalsByTransaction = new Map();
  for (const split of splits) {
    if (!split.categoryId) continue;
    const totals = map.get(split.transactionId) ?? new Map<string, number>();
    totals.set(
      split.categoryId,
      (totals.get(split.categoryId) ?? 0) + Math.abs(split.amount.amountMinor),
    );
    map.set(split.transactionId, totals);
  }
  return map;
}

function normalizeSelectedAccountIds(accountIds: string[], accounts: Account[]): string[] {
  const activeAccountIds = new Set(accounts.map((account) => account.id));
  const seen = new Set<string>();
  const normalized: string[] = [];
  for (const accountId of accountIds) {
    if (!activeAccountIds.has(accountId) || seen.has(accountId)) continue;
    seen.add(accountId);
    normalized.push(accountId);
  }
  return normalized;
}

function isDefaultForecastAccount(account: Account): boolean {
  return !account.isArchived && account.includeInReports !== false;
}

function formatAccountFilterLabel(
  accounts: Account[],
  selectedIds: string[],
  defaultIds: string[],
): string {
  if (accounts.length === 0) return 'No accounts';
  if (selectedIds.length === 0) return 'No accounts';
  if (selectedIds.length === accounts.length) return 'All accounts';
  if (sameSelection(selectedIds, defaultIds)) return 'Default accounts';
  if (selectedIds.length === 1) {
    return accounts.find((account) => account.id === selectedIds[0])?.name ?? '1 account';
  }
  return `${selectedIds.length} accounts`;
}

function sameSelection(left: string[], right: string[]): boolean {
  if (left.length !== right.length) return false;
  const selected = new Set(left);
  return right.every((id) => selected.has(id));
}

function accountFilterSubtitle(account: Account): string {
  const parts = [accountTypeLabel(account.type), account.currency];
  if (account.includeInReports === false) parts.push('reports off');
  if (account.includeInTotals === false) parts.push('totals off');
  return parts.join(' · ');
}

function amountForCategoryFilter(
  transaction: Transaction,
  selectedCategoryId: string | undefined,
  splitTotalsByTransaction: SplitTotalsByTransaction,
  state: ReturnType<typeof useLedger>['state'],
  baseCurrency: string,
): number {
  const transactionBaseMinor = calendarTransactionBaseMinor(transaction, state, baseCurrency);
  if (!selectedCategoryId) return transactionBaseMinor;
  if (transaction.categoryId === selectedCategoryId) return transactionBaseMinor;

  const splitMinor = splitTotalsByTransaction.get(transaction.id)?.get(selectedCategoryId) ?? 0;
  if (splitMinor <= 0 || transaction.amount.amountMinor === 0) return 0;

  const ratio = splitMinor / Math.abs(transaction.amount.amountMinor);
  return Math.round(transactionBaseMinor * ratio);
}

function amountForForecastCategoryFilter(
  occurrence: FutureRuleOccurrence,
  selectedCategoryId: string | undefined,
  state: ReturnType<typeof useLedger>['state'],
  baseCurrency: string,
): number {
  if (selectedCategoryId && occurrence.categoryId !== selectedCategoryId) return 0;
  return calendarForecastOccurrenceBaseMinor(occurrence, state, baseCurrency);
}

function calendarTransactionBaseMinor(
  transaction: Transaction,
  state: ReturnType<typeof useLedger>['state'],
  baseCurrency: string,
): number {
  if (transaction.type !== 'loan_repayment') return Math.abs(transaction.baseAmount.amountMinor);
  const loan = loanAccountForCalendarRepayment(transaction, state.accounts);
  const interest = loan ? linkedLoanInterestForCalendar(transaction, state) : undefined;
  const usesLoanInterestAccount = Boolean(interest && loan && interest.accountId === loan.id);
  const principal = usesLoanInterestAccount
    ? {
        amountMinor: Math.max(
          0,
          transaction.amount.amountMinor - (interest?.amount.amountMinor ?? 0),
        ),
        currency: transaction.amount.currency,
      }
    : (transaction.counterAmount ?? transaction.amount);
  return Math.abs(
    Math.round(principal.amountMinor * rateBetween(state, principal.currency, baseCurrency)),
  );
}

function loanAccountForCalendarRepayment(
  transaction: Transaction,
  accounts: Account[],
): Account | undefined {
  const account = accounts.find((item) => item.id === transaction.accountId);
  if (account && isLoanAccountType(account.type)) return account;
  const counterAccount = transaction.counterAccountId
    ? accounts.find((item) => item.id === transaction.counterAccountId)
    : undefined;
  return counterAccount && isLoanAccountType(counterAccount.type) ? counterAccount : undefined;
}

function linkedLoanInterestForCalendar(
  repayment: Transaction,
  state: ReturnType<typeof useLedger>['state'],
): Transaction | undefined {
  const expectedRef = repayment.externalRef
    ? futureRuleInterestExternalRef(repayment.externalRef)
    : undefined;
  return state.transactions.find((transaction) => {
    if (transaction.status === 'void') return false;
    if (expectedRef && transaction.externalRef === expectedRef) return true;
    return (
      transaction.originalTransactionId === repayment.id &&
      (transaction.type === 'interest_in' || transaction.type === 'interest_out')
    );
  });
}

function isLoanAccountType(type: Account['type']): boolean {
  return type === 'loan' || type === 'overdraft' || type === 'lent';
}

function calendarForecastOccurrenceBaseMinor(
  occurrence: FutureRuleOccurrence,
  state: ReturnType<typeof useLedger>['state'],
  baseCurrency: string,
): number {
  if (occurrence.type !== 'loan_repayment') {
    return Math.abs(
      Math.round(occurrence.amountMinor * rateBetween(state, occurrence.currency, baseCurrency)),
    );
  }
  const principalMinor =
    occurrence.principalAmountMinor ?? occurrence.counterAmountMinor ?? occurrence.amountMinor;
  const principalCurrency =
    occurrence.principalCurrency ?? occurrence.counterCurrency ?? occurrence.currency;
  return Math.abs(Math.round(principalMinor * rateBetween(state, principalCurrency, baseCurrency)));
}

function entryKindForTransaction(transaction: Transaction): DayEntryKind | undefined {
  return entryKindForTransactionType(transaction.type);
}

function entryKindForTransactionType(type: Transaction['type']): DayEntryKind | undefined {
  if (INCOME_TYPES.has(type)) return 'income';
  if (type === 'card_payment' || type === 'loan_repayment') {
    return 'expense';
  }
  if (EXPENSE_TYPES.has(type)) return 'expense';
  return undefined;
}

function isReportableForecastOccurrence(
  occurrence: FutureRuleOccurrence,
  state: ReturnType<typeof useLedger>['state'],
  selectedAccountIds?: ReadonlySet<string>,
): boolean {
  const account = state.accounts.find((item) => item.id === occurrence.accountId);
  if (!account || account.isArchived || account.includeInReports === false) return false;
  if (selectedAccountIds) {
    return entryMatchesSelectedAccounts(
      occurrence.accountId,
      occurrence.counterAccountId,
      selectedAccountIds,
    );
  }
  return true;
}

function virtualForecastDeltaForAccountsThroughDate(
  state: ReturnType<typeof useLedger>['state'],
  accountIds: string[],
  through: Date,
  currency: string,
  forecastOccurrences: FutureRuleOccurrence[],
  realOccurrenceRefs: { has(value: string): boolean },
): number {
  const selectedAccountIds = new Set(accountIds);
  const from = new Date();
  let delta = 0;
  for (const occurrence of forecastOccurrences) {
    const occurredAt = new Date(occurrence.occurredAt);
    if (Number.isNaN(occurredAt.getTime())) continue;
    if (occurredAt < from || occurredAt >= through) continue;
    if (realOccurrenceRefs.has(occurrence.externalRef)) continue;
    if (
      !entryMatchesSelectedAccounts(
        occurrence.accountId,
        occurrence.counterAccountId,
        selectedAccountIds,
      )
    ) {
      continue;
    }
    const kind = entryKindForTransactionType(occurrence.type);
    if (!kind) continue;
    const amount = calendarForecastOccurrenceBaseMinor(occurrence, state, currency);
    if (kind === 'income') delta += amount;
    if (kind === 'expense') delta -= amount;
  }
  return delta;
}

function projectedBalanceForAccountsThroughDateFromIndexes(
  state: ReturnType<typeof useLedger>['state'],
  indexes: ReturnType<typeof useLedger>['indexes'],
  accountIds: string[],
  through: Date,
  currency: string,
): Money {
  const selectedAccountIds = new Set(accountIds);
  let balance = 0;

  for (const accountId of selectedAccountIds) {
    const account = indexes.accountsById.get(accountId);
    const accountBalance = account ? indexes.balancesByAccountId.get(account.id) : undefined;
    if (!accountBalance) continue;
    balance += Math.round(
      accountBalance.amountMinor * rateBetween(state, accountBalance.currency, currency),
    );
  }

  return { amountMinor: balance, currency };
}

function minDate(left: Date, right: Date): Date {
  return left.getTime() <= right.getTime() ? left : right;
}

function maxDate(left: Date, right: Date): Date {
  return left.getTime() >= right.getTime() ? left : right;
}

function dayEntryKey(entry: DayTransaction): string {
  return entry.source === 'forecast' ? entry.occurrence.externalRef : entry.transaction.id;
}

function dayEntryCategoryId(entry: DayTransaction): string | undefined {
  return entry.source === 'forecast' ? entry.occurrence.categoryId : entry.transaction.categoryId;
}

function dayEntryAccountId(entry: DayTransaction): string {
  return entry.source === 'forecast' ? entry.occurrence.accountId : entry.transaction.accountId;
}

function isReportableTransaction(
  transaction: Transaction,
  state: ReturnType<typeof useLedger>['state'],
  selectedAccountIds?: ReadonlySet<string>,
): boolean {
  if (transaction.status === 'void') return false;
  if (transaction.isExcludedFromReports) return false;
  const account = state.accounts.find((item) => item.id === transaction.accountId);
  if (!account || account.isArchived || account.includeInReports === false) return false;
  if (selectedAccountIds) {
    return entryMatchesSelectedAccounts(
      transaction.accountId,
      transaction.counterAccountId,
      selectedAccountIds,
    );
  }
  return true;
}

function isLinkedLoanInterestTransaction(
  transaction: Transaction,
  state: ReturnType<typeof useLedger>['state'],
): boolean {
  if (transaction.type !== 'interest_in' && transaction.type !== 'interest_out') return false;
  if (transaction.originalTransactionId) {
    return state.transactions.some(
      (item) => item.id === transaction.originalTransactionId && item.type === 'loan_repayment',
    );
  }
  if (!transaction.externalRef) return false;
  return state.transactions.some(
    (item) =>
      item.type === 'loan_repayment' &&
      (item.externalRef
        ? futureRuleInterestExternalRef(item.externalRef) === transaction.externalRef
        : false),
  );
}

function entryMatchesSelectedAccounts(
  accountId: string,
  counterAccountId: string | undefined,
  selectedAccountIds: ReadonlySet<string>,
): boolean {
  return (
    selectedAccountIds.has(accountId) ||
    Boolean(counterAccountId && selectedAccountIds.has(counterAccountId))
  );
}

function emptyDaySummary(): DaySummary {
  return {
    incomeMinor: 0,
    expenseMinor: 0,
    plannedIncomeMinor: 0,
    plannedExpenseMinor: 0,
    plannedCount: 0,
    transactions: [],
  };
}

function isPlannedTransaction(transaction: Transaction): boolean {
  return transaction.status === 'scheduled' || Boolean(transaction.recurringTemplateId);
}

function startOfMonth(value: Date): Date {
  return new Date(value.getFullYear(), value.getMonth(), 1);
}

function addMonths(value: Date, months: number): Date {
  return new Date(value.getFullYear(), value.getMonth() + months, 1);
}

function addDays(value: Date, days: number): Date {
  const next = new Date(value);
  next.setDate(next.getDate() + days);
  return next;
}

function daysBetween(start: Date, end: Date): number {
  const msPerDay = 24 * 60 * 60 * 1000;
  return Math.round((startOfDay(end).getTime() - startOfDay(start).getTime()) / msPerDay);
}

function startOfDay(value: Date): Date {
  return new Date(value.getFullYear(), value.getMonth(), value.getDate());
}

function dateKeyFromIso(value: string): string {
  return dateKey(new Date(value));
}

function dateKey(value: Date): string {
  const month = String(value.getMonth() + 1).padStart(2, '0');
  const day = String(value.getDate()).padStart(2, '0');
  return `${value.getFullYear()}-${month}-${day}`;
}

function formatMonthTitle(value: Date, locale: string): string {
  return value.toLocaleDateString(locale, { month: 'long', year: 'numeric' });
}

function formatDayTitle(key: string, locale: string): string {
  return new Date(`${key}T00:00:00`).toLocaleDateString(locale, {
    weekday: 'long',
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

function formatCompactMoney(amountMinor: number, currency: string, locale: string): string {
  const value = Math.abs(fromMinor(amountMinor, currency));
  const symbol = currencySymbol(currency, locale);
  if (value >= 10000000) return `${formatScaledAmount(value / 10000000)}Cr`;
  if (value >= 100000) return `${formatScaledAmount(value / 100000)}L`;
  if (value >= 1000) return `${formatScaledAmount(value / 1000)}k`;
  return `${symbol}${Math.round(value)}`;
}

function formatScaledAmount(value: number): string {
  if (value >= 100) return String(Math.round(value));
  return value.toFixed(1).replace(/\.0$/, '');
}

function currencySymbol(currency: string, locale: string): string {
  try {
    const parts = new Intl.NumberFormat(locale, {
      style: 'currency',
      currency,
      currencyDisplay: 'narrowSymbol',
      maximumFractionDigits: 0,
    }).formatToParts(0);
    return parts.find((part) => part.type === 'currency')?.value ?? `${currency} `;
  } catch {
    return `${currency} `;
  }
}

function incomeColor(dark?: boolean): string {
  return dark ? '#8ED99F' : '#137A3A';
}

function expenseColor(dark: boolean | undefined, fallback: string): string {
  return dark ? '#FFB4AB' : fallback;
}

function balanceColor(amountMinor: number, dark: boolean | undefined, fallback: string): string {
  if (amountMinor > 0) return incomeColor(dark);
  if (amountMinor < 0) return expenseColor(dark, '#BA1A1A');
  return fallback;
}

const styles = StyleSheet.create({
  screen: { flex: 1 },
  appbarTitle: { fontWeight: '700' },
  contentScroll: { flex: 1 },
  content: {
    flexGrow: 1,
    padding: tokens.space.md,
    paddingBottom: TAB_BAR_OVERLAY_CLEARANCE + tokens.space.lg,
    gap: tokens.space.sm,
  },
  monthCard: {
    borderRadius: tokens.radius.lg,
    borderWidth: StyleSheet.hairlineWidth,
    padding: tokens.space.sm,
    gap: tokens.space.xs,
  },
  monthHeader: { flexDirection: 'row', alignItems: 'center' },
  monthArrowButton: { marginHorizontal: 0 },
  monthCopy: { flex: 1, alignItems: 'center', minWidth: 0 },
  monthTitle: { fontWeight: '800' },
  summaryRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.sm,
  },
  summaryPill: {
    flex: 1,
    minWidth: 0,
    borderRadius: tokens.radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: tokens.space.sm,
    paddingVertical: 6,
    gap: 2,
  },
  filterRow: { flexDirection: 'row', gap: tokens.space.sm },
  filterSelector: { flex: 1, minWidth: 0, backgroundColor: 'transparent' },
  calendarCard: {
    flex: 1,
    borderRadius: tokens.radius.lg,
    borderWidth: StyleSheet.hairlineWidth,
    padding: tokens.space.sm,
    gap: tokens.space.xs,
  },
  weekRow: { flexDirection: 'row' },
  weekday: { flex: 1, textAlign: 'center', fontWeight: '800', paddingVertical: 6 },
  grid: { flex: 1 },
  gridWeek: { flex: 1, flexDirection: 'row' },
  daySlot: {
    flex: 1,
    padding: 2,
    borderRadius: tokens.radius.md,
    overflow: 'hidden',
  },
  dayCell: {
    flex: 1,
    borderRadius: tokens.radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 4,
    paddingVertical: 5,
    justifyContent: 'space-between',
    minWidth: 0,
  },
  dayHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 2,
    minWidth: 0,
  },
  dot: { width: 5, height: 5, borderRadius: tokens.radius.pill },
  dayAmounts: { gap: 2, minHeight: 26, justifyContent: 'flex-end' },
  dayAmount: {
    fontFamily: numericMediumFontFamily,
    fontSize: 9,
    lineHeight: 11,
    fontWeight: '800',
    includeFontPadding: false,
  },
  modal: {
    width: '92%',
    maxHeight: '84%',
    alignSelf: 'center',
    borderRadius: tokens.radius.lg,
    borderWidth: StyleSheet.hairlineWidth,
    padding: tokens.space.lg,
    gap: tokens.space.md,
  },
  modalHeader: { flexDirection: 'row', alignItems: 'center', gap: tokens.space.sm },
  modalTitle: { fontWeight: '800' },
  fill: { flex: 1, minWidth: 0 },
  dayList: { maxHeight: 420 },
  fullScreenOverlay: {
    ...StyleSheet.absoluteFill,
  },
  overlaySafeArea: { flex: 1 },
  overlayContent: {
    flex: 1,
    paddingHorizontal: tokens.space.md,
    paddingBottom: tokens.space.md,
    gap: tokens.space.sm,
  },
  filterActionRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.sm,
  },
  accountListContent: {
    gap: tokens.space.sm,
    paddingBottom: tokens.space.lg,
  },
  emptyAccountState: {
    minHeight: 180,
    alignItems: 'center',
    justifyContent: 'center',
    gap: tokens.space.sm,
  },
  transactionRipple: { borderRadius: tokens.radius.md, overflow: 'hidden' },
  transactionRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.md,
    paddingVertical: tokens.space.sm,
  },
  transactionIcon: {
    width: 38,
    height: 38,
    borderRadius: tokens.radius.md,
    alignItems: 'center',
    justifyContent: 'center',
  },
  transactionCopy: { flex: 1, minWidth: 0 },
});
