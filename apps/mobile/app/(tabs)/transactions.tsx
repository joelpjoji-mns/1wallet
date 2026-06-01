import { formatMoney } from '@1wallet/domain/money';
import type {
    Account,
    Category,
    Transaction,
    TransactionStatus,
    TransactionType,
} from '@1wallet/domain/types';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { router } from 'expo-router';
import { memo, useCallback, useDeferredValue, useMemo, useState, type ComponentProps } from 'react';
import {
    FlatList,
    Platform,
    ScrollView,
    StyleSheet,
    View,
    type ListRenderItem,
} from 'react-native';
import {
    Appbar,
    Chip,
    Surface,
    Text,
    TouchableRipple,
    useTheme,
    type MD3Theme,
} from 'react-native-paper';
import { resolveAccountIconVisual } from '../../src/accountOptions';
import { openAddRecord } from '../../src/addRecordNavigation';
import { resolveCategoryIconVisual } from '../../src/categoryIcons';
import { categoryBreadcrumb, categoryDescendantIds } from '../../src/categoryTree';
import { useAppDrawer } from '../../src/components/AppDrawerHost';
import {
    AppMenuAction,
    EmptyState,
    MetricTile,
    PremiumSearchInput,
    resolveAppIconName,
} from '../../src/components/AppKit';
import { OptionListOverlay, type OptionListItem } from '../../src/components/OptionListOverlay';
import { CategoryMultiPickerOverlay } from '../../src/components/record/RecordPickers';
import { positiveAmountColor } from '../../src/financeColors';
import { numericMediumFontFamily } from '../../src/fonts';
import { iconSurfaceForThemeTone, type IconSurfaceTone } from '../../src/iconSystem';
import { formatRecordDateLabel } from '../../src/recordDateTime';
import {
    signedTransactionAmount,
    transactionAmountDisplay,
    type TransactionAmountRowSide,
} from '../../src/transactionDisplayAmounts';
import {
    EXPENSE_TRANSACTION_TYPES as EXPENSE_TYPES,
    INCOME_TRANSACTION_TYPES as INCOME_TYPES,
    TRANSACTION_TYPE_BUCKET_OPTIONS,
    TRANSFER_TRANSACTION_TYPES as TRANSFER_TYPES,
    transactionTypeBucket,
    transactionTypeIcon,
    transactionTypeIconTone,
    transactionTypeLabel,
    type TransactionTypeBucket,
} from '../../src/transactionTypes';

type TypeFilter = 'all' | TransactionTypeBucket;
type DateFilter = 'all' | 'this_month' | 'last_30_days' | 'this_year';
type StatusFilter = 'all' | Exclude<TransactionStatus, 'scheduled'>;
type FilterPicker = 'type' | 'account' | 'category' | 'date' | 'status' | null;
type SearchSuggestion = {
  id: string;
  label: string;
  description: string;
  icon: ComponentProps<typeof MaterialCommunityIcons>['name'];
  iconBackgroundColor?: string;
  iconColor?: string;
};
const ALL_ACCOUNTS_VALUE = '__all_accounts';
const DEFAULT_DATE_FILTER: DateFilter = 'this_year';

const TYPE_FILTER_OPTIONS: OptionListItem<TypeFilter>[] = [
  {
    value: 'all',
    label: 'All types',
    description: 'Income, expense, transfer, and adjustment',
    icon: 'filter-variant',
  },
  ...TRANSACTION_TYPE_BUCKET_OPTIONS,
];

const DATE_FILTER_OPTIONS: OptionListItem<DateFilter>[] = [
  { value: 'all', label: 'All dates', description: 'Full ledger history', icon: 'calendar-range' },
  {
    value: 'this_month',
    label: 'This month',
    description: 'Current calendar month',
    icon: 'calendar-month-outline',
  },
  {
    value: 'last_30_days',
    label: 'Last 30 days',
    description: 'Rolling recent window',
    icon: 'calendar-clock',
  },
  {
    value: 'this_year',
    label: 'This year',
    description: 'Current calendar year',
    icon: 'calendar',
  },
];

const STATUS_FILTER_OPTIONS: OptionListItem<StatusFilter>[] = [
  {
    value: 'all',
    label: 'All statuses',
    description: 'Cleared, pending, and void records',
    icon: 'list-status',
  },
  {
    value: 'cleared',
    label: 'Cleared',
    description: 'Posted ledger records',
    icon: 'check-circle-outline',
  },
  { value: 'pending', label: 'Pending', description: 'Waiting to clear', icon: 'clock-outline' },
  { value: 'void', label: 'Void', description: 'Ignored or cancelled records', icon: 'cancel' },
];

export default function Transactions() {
  const theme = useTheme();
  const { openDrawer } = useAppDrawer();
  const { state, indexes, selectors } = useLedger();
  const [query, setQuery] = useState('');
  const [typeFilter, setTypeFilter] = useState<TypeFilter>('all');
  const [accountFilter, setAccountFilter] = useState(ALL_ACCOUNTS_VALUE);
  const [selectedCategoryIds, setSelectedCategoryIds] = useState<string[]>([]);
  const [includeUncategorizedCategory, setIncludeUncategorizedCategory] = useState(false);
  const [dateFilter, setDateFilter] = useState<DateFilter>(DEFAULT_DATE_FILTER);
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all');
  const [filterPicker, setFilterPicker] = useState<FilterPicker>(null);
  const [searchFocused, setSearchFocused] = useState(false);
  const deferredQuery = useDeferredValue(query);

  const accountOptions = useMemo<OptionListItem<string>[]>(
    () => [
      {
        value: ALL_ACCOUNTS_VALUE,
        label: 'All accounts',
        description: 'Transactions from every account',
        icon: 'wallet-outline',
      },
      ...state.accounts.map((account) => {
        const visual = resolveAccountIconVisual(account);
        return {
          value: account.id,
          label: account.name,
          description: account.currency,
          icon: visual.icon,
          iconBackgroundColor: visual.backgroundColor,
          iconColor: visual.iconColor,
        };
      }),
    ],
    [state.accounts],
  );

  const selectedTypeFilter = optionLabel(TYPE_FILTER_OPTIONS, typeFilter);
  const selectedAccountFilter = optionLabel(accountOptions, accountFilter);
  const selectedAccountOption = accountOptions.find((option) => option.value === accountFilter);
  const selectedCategory =
    selectedCategoryIds.length === 1
      ? state.categories.find((category) => category.id === selectedCategoryIds[0])
      : undefined;
  const selectedCategoryVisual = selectedCategory
    ? resolveCategoryIconVisual(selectedCategory, state.categories)
    : undefined;
  const selectedCategoryFilterCount =
    selectedCategoryIds.length + (includeUncategorizedCategory ? 1 : 0);
  const selectedCategoryFilter =
    selectedCategoryFilterCount === 0
      ? 'All categories'
      : selectedCategory && !includeUncategorizedCategory
        ? selectedCategory.name
        : selectedCategoryFilterCount === 1 && includeUncategorizedCategory
          ? 'Uncategorized'
          : `${selectedCategoryFilterCount} categories`;
  const selectedDateFilter = optionLabel(DATE_FILTER_OPTIONS, dateFilter);
  const selectedStatusFilter = optionLabel(STATUS_FILTER_OPTIONS, statusFilter);
  const selectedAccountId = accountFilter === ALL_ACCOUNTS_VALUE ? undefined : accountFilter;
  const categoryFilterActive = selectedCategoryFilterCount > 0;
  const selectedCategoryMatchIds = useMemo(() => {
    const ids = new Set<string>();
    selectedCategoryIds.forEach((categoryId) => {
      ids.add(categoryId);
      categoryDescendantIds(state.categories, categoryId).forEach((descendantId) =>
        ids.add(descendantId),
      );
    });
    return ids;
  }, [selectedCategoryIds, state.categories]);
  const toggleCategoryFilter = useCallback((category: Category) => {
    setSelectedCategoryIds((current) =>
      current.includes(category.id)
        ? current.filter((categoryId) => categoryId !== category.id)
        : [...current, category.id],
    );
  }, []);
  const clearCategoryFilters = useCallback(() => {
    setSelectedCategoryIds([]);
    setIncludeUncategorizedCategory(false);
  }, []);
  const hasActiveFilters =
    query.trim().length > 0 ||
    typeFilter !== 'all' ||
    accountFilter !== ALL_ACCOUNTS_VALUE ||
    categoryFilterActive ||
    dateFilter !== DEFAULT_DATE_FILTER ||
    statusFilter !== 'all';

  const clearFilters = () => {
    setQuery('');
    setTypeFilter('all');
    setAccountFilter(ALL_ACCOUNTS_VALUE);
    clearCategoryFilters();
    setDateFilter(DEFAULT_DATE_FILTER);
    setStatusFilter('all');
  };

  const dateBounds = useMemo(() => dateBoundsForFilter(dateFilter), [dateFilter]);
  const transactions = useMemo(() => {
    const normalizedQuery = deferredQuery.trim().toLowerCase();
    const sourceTransactions =
      accountFilter === ALL_ACCOUNTS_VALUE
        ? indexes.allTransactionsSorted
        : (indexes.transactionsByAccountId.get(accountFilter) ?? []);
    return sourceTransactions.filter((transaction) => {
      if (transaction.status === 'scheduled') return false;
      if (typeFilter !== 'all' && transactionTypeBucket(transaction.type) !== typeFilter) {
        return false;
      }
      if (
        accountFilter !== ALL_ACCOUNTS_VALUE &&
        transaction.accountId !== accountFilter &&
        transaction.counterAccountId !== accountFilter
      ) {
        return false;
      }
      if (categoryFilterActive) {
        if (!transaction.categoryId) {
          if (!includeUncategorizedCategory) return false;
        } else if (!selectedCategoryMatchIds.has(transaction.categoryId)) {
          return false;
        }
      }
      if (statusFilter !== 'all' && transaction.status !== statusFilter) return false;
      if (!matchesDateFilter(transaction, dateBounds)) return false;
      if (!normalizedQuery) return true;

      const account = indexes.accountsById.get(transaction.accountId);
      const counterAccount = transaction.counterAccountId
        ? indexes.accountsById.get(transaction.counterAccountId)
        : undefined;
      const category = transaction.categoryId
        ? indexes.categoriesById.get(transaction.categoryId)
        : undefined;
      const haystack = [
        transaction.type,
        transactionTypeLabel(transaction.type),
        transaction.status,
        transaction.source,
        transaction.notes,
        transaction.paymentMethod,
        transaction.tags?.join(' '),
        account?.name,
        counterAccount?.name,
        category?.name,
      ]
        .filter(Boolean)
        .join(' ')
        .toLowerCase();

      return haystack.includes(normalizedQuery);
    });
  }, [
    accountFilter,
    categoryFilterActive,
    dateBounds,
    deferredQuery,
    includeUncategorizedCategory,
    indexes,
    selectedCategoryMatchIds,
    statusFilter,
    typeFilter,
  ]);

  const viewCurrency = selectors.displayCurrency(state);
  const displayFlow = useMemo(() => {
    let income = 0;
    let expense = 0;
    for (const transaction of transactions) {
      if (transaction.status === 'scheduled' || transaction.status === 'void') continue;
      if (transaction.isExcludedFromReports) continue;
      if (INCOME_TYPES.has(transaction.type)) income += transaction.baseAmount.amountMinor;
      if (EXPENSE_TYPES.has(transaction.type)) expense += transaction.baseAmount.amountMinor;
    }
    return {
      income: selectors.convertMoneyForDisplay(
        state,
        { amountMinor: income, currency: state.preferences.baseCurrency },
        viewCurrency,
      ),
      expense: selectors.convertMoneyForDisplay(
        state,
        { amountMinor: expense, currency: state.preferences.baseCurrency },
        viewCurrency,
      ),
    };
  }, [selectors, state, transactions, viewCurrency]);
  const pending = useMemo(
    () => transactions.filter((transaction) => transaction.status === 'pending').length,
    [transactions],
  );
  const searchSuggestions = useMemo(
    () => buildSearchSuggestions(state, indexes.allTransactionsSorted, query),
    [indexes.allTransactionsSorted, query, state],
  );
  const showSuggestions =
    (searchFocused || query.trim().length > 0) && searchSuggestions.length > 0;
  const visibleResultCount = transactions.length;
  const totalResultCount = indexes.allTransactionsSorted.filter(
    (transaction) => transaction.status !== 'scheduled',
  ).length;
  const rowDisplayKey = useMemo(() => transactionRowDisplayKey(state), [state]);
  const openTransaction = useCallback((transactionId: string) => {
    router.push(`/transaction/${transactionId}` as never);
  }, []);
  const renderTransactionItem = useCallback<ListRenderItem<Transaction>>(
    ({ item }) => (
      <TransactionRow
        transaction={item}
        state={state}
        indexes={indexes}
        selectedAccountId={selectedAccountId}
        rowDisplayKey={rowDisplayKey}
        onOpenTransaction={openTransaction}
      />
    ),
    [indexes, openTransaction, rowDisplayKey, selectedAccountId, state],
  );

  return (
    <View style={[styles.screen, { backgroundColor: theme.colors.background }]}>
      <Appbar.Header elevated={false} style={{ backgroundColor: theme.colors.background }}>
        <AppMenuAction onPress={openDrawer} />
        <Appbar.Content title="Transactions" titleStyle={styles.appbarTitle} />
        <Appbar.Action icon="plus" onPress={() => openAddRecord({ entryOrigin: 'top' })} />
        <Appbar.Action
          icon="view-dashboard-outline"
          onPress={() => router.push('/widgets' as never)}
        />
      </Appbar.Header>

      <FlatList
        data={transactions}
        keyExtractor={(transaction) => transaction.id}
        contentContainerStyle={styles.listContent}
        keyboardShouldPersistTaps="handled"
        removeClippedSubviews={Platform.OS === 'android'}
        initialNumToRender={12}
        maxToRenderPerBatch={8}
        updateCellsBatchingPeriod={32}
        windowSize={9}
        ListHeaderComponent={
          <View style={styles.headerContent}>
            <Surface
              style={[
                styles.commandPanel,
                {
                  backgroundColor: theme.colors.elevation.level1,
                  borderColor: theme.colors.outlineVariant,
                },
              ]}
              elevation={1}
            >
              <View style={styles.commandHeaderRow}>
                <View style={styles.commandCopy}>
                  <Text variant="titleMedium" style={styles.commandTitle}>
                    Find records
                  </Text>
                  <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                    {visibleResultCount} of {totalResultCount} records shown
                  </Text>
                </View>
                {hasActiveFilters ? (
                  <Chip compact icon="close" onPress={clearFilters}>
                    Clear all
                  </Chip>
                ) : null}
              </View>
              <PremiumSearchInput
                placeholder="Search merchant, note, account, tag"
                value={query}
                onChangeText={setQuery}
                onFocus={() => setSearchFocused(true)}
                onBlur={() => setSearchFocused(false)}
                style={styles.searchBar}
              />
              {showSuggestions ? (
                <ScrollView
                  horizontal
                  keyboardShouldPersistTaps="handled"
                  showsHorizontalScrollIndicator={false}
                  contentContainerStyle={styles.suggestionRail}
                >
                  {searchSuggestions.map((suggestion) => (
                    <SearchSuggestionChip
                      key={suggestion.id}
                      suggestion={suggestion}
                      onPress={() => setQuery(suggestion.label)}
                    />
                  ))}
                </ScrollView>
              ) : null}
              <View style={styles.filterToolbar}>
                <FilterToolbarButton
                  label="Type"
                  value={selectedTypeFilter}
                  icon="filter-variant"
                  active={typeFilter !== 'all'}
                  onPress={() => setFilterPicker('type')}
                />
                <FilterToolbarButton
                  label="Date"
                  value={selectedDateFilter}
                  icon="calendar-range"
                  active={dateFilter !== DEFAULT_DATE_FILTER}
                  onPress={() => setFilterPicker('date')}
                />
                <FilterToolbarButton
                  label="Account"
                  value={selectedAccountFilter}
                  icon={selectedAccountOption?.icon ?? 'wallet-outline'}
                  iconBackgroundColor={selectedAccountOption?.iconBackgroundColor}
                  iconColor={selectedAccountOption?.iconColor}
                  active={accountFilter !== ALL_ACCOUNTS_VALUE}
                  onPress={() => setFilterPicker('account')}
                />
                <FilterToolbarButton
                  label="Category"
                  value={selectedCategoryFilter}
                  icon={selectedCategoryVisual?.icon ?? 'shape-outline'}
                  iconBackgroundColor={selectedCategoryVisual?.backgroundColor}
                  iconColor={selectedCategoryVisual?.iconColor}
                  active={categoryFilterActive}
                  onPress={() => setFilterPicker('category')}
                />
                <FilterToolbarButton
                  label="Status"
                  value={selectedStatusFilter}
                  icon="list-status"
                  active={statusFilter !== 'all'}
                  onPress={() => setFilterPicker('status')}
                />
              </View>
            </Surface>
            <View style={styles.metricGrid}>
              <MetricTile
                label="Income"
                value={formatMoney(displayFlow.income, state.preferences.locale)}
                icon="trending-up"
                tone="positive"
                compact
                onPress={() => setTypeFilter('income')}
              />
              <MetricTile
                label="Expense"
                value={formatMoney(displayFlow.expense, state.preferences.locale)}
                icon="trending-down"
                tone="danger"
                compact
                onPress={() => setTypeFilter('expense')}
              />
              <MetricTile
                label="Pending"
                value={String(pending)}
                icon="clock-outline"
                tone={pending ? 'warning' : 'default'}
                compact
                onPress={() => setStatusFilter('pending')}
              />
            </View>
          </View>
        }
        ListEmptyComponent={
          <EmptyState
            icon="format-list-bulleted"
            title="No matching transactions"
            body={
              hasActiveFilters
                ? 'Clear filters to see the full ledger.'
                : 'Add a new record to start building your ledger.'
            }
            actionLabel={hasActiveFilters ? 'Clear filters' : 'Add transaction'}
            onAction={hasActiveFilters ? clearFilters : () => router.push('/add')}
          />
        }
        ItemSeparatorComponent={() => <View style={{ height: 8 }} />}
        renderItem={renderTransactionItem}
      />
      <OptionListOverlay
        visible={filterPicker === 'type'}
        title="Choose type"
        options={TYPE_FILTER_OPTIONS}
        selectedValue={typeFilter}
        searchable={false}
        onDismiss={() => setFilterPicker(null)}
        onSelect={(option) => {
          setTypeFilter(option.value);
          setFilterPicker(null);
        }}
      />
      <OptionListOverlay
        visible={filterPicker === 'account'}
        title="Choose account"
        options={accountOptions}
        selectedValue={accountFilter}
        searchPlaceholder="Search accounts"
        onDismiss={() => setFilterPicker(null)}
        onSelect={(option) => {
          setAccountFilter(option.value);
          setFilterPicker(null);
        }}
      />
      <CategoryMultiPickerOverlay
        visible={filterPicker === 'category'}
        categories={state.categories}
        selectedIds={selectedCategoryIds}
        includeUncategorized={includeUncategorizedCategory}
        onDismiss={() => setFilterPicker(null)}
        onToggleCategory={toggleCategoryFilter}
        onToggleUncategorized={() => setIncludeUncategorizedCategory((value) => !value)}
        onClear={clearCategoryFilters}
      />
      <OptionListOverlay
        visible={filterPicker === 'date'}
        title="Choose date range"
        options={DATE_FILTER_OPTIONS}
        selectedValue={dateFilter}
        searchable={false}
        onDismiss={() => setFilterPicker(null)}
        onSelect={(option) => {
          setDateFilter(option.value);
          setFilterPicker(null);
        }}
      />
      <OptionListOverlay
        visible={filterPicker === 'status'}
        title="Choose status"
        options={STATUS_FILTER_OPTIONS}
        selectedValue={statusFilter}
        searchable={false}
        onDismiss={() => setFilterPicker(null)}
        onSelect={(option) => {
          setStatusFilter(option.value);
          setFilterPicker(null);
        }}
      />
    </View>
  );
}

function FilterToolbarButton({
  label,
  value,
  icon,
  iconBackgroundColor,
  iconColor,
  active,
  onPress,
}: {
  label: string;
  value: string;
  icon: ComponentProps<typeof MaterialCommunityIcons>['name'];
  iconBackgroundColor?: string;
  iconColor?: string;
  active: boolean;
  onPress: () => void;
}) {
  const theme = useTheme();
  return (
    <TouchableRipple
      style={[
        styles.filterButton,
        {
          backgroundColor: active ? theme.colors.primaryContainer : theme.colors.surface,
          borderColor: active ? theme.colors.primary : theme.colors.outlineVariant,
        },
      ]}
      borderless
      onPress={onPress}
    >
      <View style={styles.filterButtonInner}>
        <View
          style={[
            styles.filterButtonIcon,
            iconBackgroundColor ? { backgroundColor: iconBackgroundColor } : null,
          ]}
        >
          <MaterialCommunityIcons
            name={icon}
            size={18}
            color={iconColor ?? (active ? theme.colors.primary : theme.colors.onSurfaceVariant)}
          />
        </View>
        <View style={styles.filterButtonCopy}>
          <Text
            variant="labelSmall"
            numberOfLines={1}
            style={{ color: active ? theme.colors.primary : theme.colors.onSurfaceVariant }}
          >
            {label}
          </Text>
          <Text variant="labelMedium" numberOfLines={2} style={styles.filterButtonValue}>
            {value}
          </Text>
        </View>
      </View>
    </TouchableRipple>
  );
}

function SearchSuggestionChip({
  suggestion,
  onPress,
}: {
  suggestion: SearchSuggestion;
  onPress: () => void;
}) {
  const theme = useTheme();
  return (
    <TouchableRipple
      borderless
      style={[
        styles.suggestionChip,
        { backgroundColor: theme.colors.surface, borderColor: theme.colors.outlineVariant },
      ]}
      onPress={onPress}
    >
      <View style={styles.suggestionInner}>
        <View
          style={[
            styles.suggestionIcon,
            suggestion.iconBackgroundColor
              ? { backgroundColor: suggestion.iconBackgroundColor }
              : null,
          ]}
        >
          <MaterialCommunityIcons
            name={suggestion.icon}
            size={16}
            color={suggestion.iconColor ?? theme.colors.onSurfaceVariant}
          />
        </View>
        <View style={styles.suggestionCopy}>
          <Text variant="labelMedium" numberOfLines={1} style={styles.suggestionLabel}>
            {suggestion.label}
          </Text>
          <Text
            variant="labelSmall"
            numberOfLines={1}
            style={{ color: theme.colors.onSurfaceVariant }}
          >
            {suggestion.description}
          </Text>
        </View>
      </View>
    </TouchableRipple>
  );
}

function buildSearchSuggestions(
  state: ReturnType<typeof useLedger>['state'],
  transactions: Transaction[],
  query: string,
): SearchSuggestion[] {
  const normalizedQuery = query.trim().toLowerCase();
  const suggestions: SearchSuggestion[] = [];
  const seen = new Set<string>();
  const push = (suggestion: SearchSuggestion) => {
    const normalized = suggestion.label.trim().toLowerCase();
    if (!normalized || seen.has(normalized)) return;
    if (
      normalizedQuery &&
      !`${normalized} ${suggestion.description.toLowerCase()}`.includes(normalizedQuery)
    ) {
      return;
    }
    seen.add(normalized);
    suggestions.push(suggestion);
  };

  for (const merchant of state.merchants.slice(0, 16)) {
    push({
      id: `merchant:${merchant.id}`,
      label: merchant.name,
      description: 'Merchant',
      icon: 'store-outline',
    });
  }
  for (const account of state.accounts.filter((item) => !item.isArchived).slice(0, 16)) {
    const visual = resolveAccountIconVisual(account);
    push({
      id: `account:${account.id}`,
      label: account.name,
      description: `${account.currency} account`,
      icon: visual.icon,
      iconBackgroundColor: visual.backgroundColor,
      iconColor: visual.iconColor,
    });
  }
  for (const category of state.categories.filter((item) => !item.isArchived).slice(0, 24)) {
    const visual = resolveCategoryIconVisual(category, state.categories);
    push({
      id: `category:${category.id}`,
      label: categoryBreadcrumb(state.categories, category.id) ?? category.name,
      description: `${category.kind} category`,
      icon: visual.icon,
      iconBackgroundColor: visual.backgroundColor,
      iconColor: visual.iconColor,
    });
  }
  for (const transaction of transactions.slice(0, 80)) {
    if (transaction.paymentMethod) {
      push({
        id: `payment:${transaction.id}:${transaction.paymentMethod}`,
        label: transaction.paymentMethod,
        description: 'Payment method',
        icon: 'credit-card-outline',
      });
    }
    for (const tag of transaction.tags ?? []) {
      push({
        id: `tag:${transaction.id}:${tag}`,
        label: tag,
        description: 'Tag',
        icon: 'tag-outline',
      });
    }
  }
  return suggestions.slice(0, 10);
}

function optionLabel<TValue extends string>(
  options: readonly OptionListItem<TValue>[],
  selectedValue: TValue,
) {
  return options.find((option) => option.value === selectedValue)?.label ?? 'All';
}

type DateFilterBounds = {
  filter: DateFilter;
  nowTime: number;
  startTime?: number;
  endTime?: number;
};

function dateBoundsForFilter(filter: DateFilter): DateFilterBounds {
  const now = new Date();
  const nowTime = now.getTime();
  if (filter === 'all') return { filter, nowTime };
  if (filter === 'this_month') {
    return {
      filter,
      nowTime,
      startTime: new Date(now.getFullYear(), now.getMonth(), 1).getTime(),
      endTime: new Date(now.getFullYear(), now.getMonth() + 1, 1).getTime(),
    };
  }
  if (filter === 'this_year') {
    return {
      filter,
      nowTime,
      startTime: new Date(now.getFullYear(), 0, 1).getTime(),
      endTime: new Date(now.getFullYear() + 1, 0, 1).getTime(),
    };
  }

  const start = new Date(now);
  start.setDate(now.getDate() - 30);
  return { filter, nowTime, startTime: start.getTime(), endTime: nowTime + 1 };
}

function matchesDateFilter(transaction: Transaction, bounds: DateFilterBounds) {
  if (bounds.filter === 'all') return true;

  const occurredTime = Date.parse(transaction.occurredAt);
  if (!Number.isFinite(occurredTime)) return false;

  return occurredTime >= (bounds.startTime ?? 0) && occurredTime < (bounds.endTime ?? Infinity);
}

type TransactionRowSide = TransactionAmountRowSide;
type TransactionDisplayRow = { transaction: Transaction; side: TransactionRowSide };
type LedgerStateSnapshot = ReturnType<typeof useLedger>['state'];
type LedgerIndexSnapshot = ReturnType<typeof useLedger>['indexes'];

const TransactionRow = memo(function TransactionRow({
  transaction,
  state,
  indexes,
  selectedAccountId,
  rowDisplayKey,
  onOpenTransaction,
}: {
  transaction: Transaction;
  state: LedgerStateSnapshot;
  indexes: LedgerIndexSnapshot;
  selectedAccountId?: string;
  rowDisplayKey: string;
  onOpenTransaction: (transactionId: string) => void;
}) {
  const theme = useTheme();
  const rows = useMemo(
    () => displayRowsForTransaction(transaction, selectedAccountId),
    [selectedAccountId, transaction],
  );
  const openRow = useCallback(
    () => onOpenTransaction(transaction.id),
    [onOpenTransaction, transaction.id],
  );

  return (
    <Surface
      style={[
        styles.rowCard,
        {
          backgroundColor: theme.colors.elevation.level1,
          borderColor: theme.colors.outlineVariant,
        },
      ]}
      elevation={1}
    >
      <View style={TRANSFER_TYPES.has(transaction.type) ? styles.transferPair : undefined}>
        {rows.map((row) => (
          <TransactionRecordRow
            key={`${transaction.id}-${row.side}`}
            row={row}
            state={state}
            indexes={indexes}
            onPress={openRow}
          />
        ))}
      </View>
    </Surface>
  );
}, areTransactionRowsEqual);

const TransactionRecordRow = memo(function TransactionRecordRow({
  row,
  state,
  indexes,
  onPress,
}: {
  row: TransactionDisplayRow;
  state: LedgerStateSnapshot;
  indexes: LedgerIndexSnapshot;
  onPress: () => void;
}) {
  const theme = useTheme();
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
  const icon =
    categoryVisual?.icon ??
    resolveAppIconName(category?.icon, transactionRowIcon(transaction, side));
  const fallbackIconSurface = iconSurfaceForThemeTone(
    theme,
    transactionRowIconTone(transaction, side),
  );
  const iconBackgroundColor =
    categoryVisual?.backgroundColor ?? fallbackIconSurface.backgroundColor;
  const iconColor = categoryVisual?.iconColor ?? fallbackIconSurface.iconColor;
  const title = useMemo(
    () => transactionRowTitle(transaction, side, state.categories, account, counterAccount),
    [account, counterAccount, side, state.categories, transaction],
  );
  const accountLine = useMemo(
    () => transactionRowMeta(transaction, side, account, counterAccount),
    [account, counterAccount, side, transaction],
  );
  const secondaryLine = useMemo(() => transactionRowSecondaryMeta(transaction), [transaction]);
  const dateLabel = useMemo(
    () => formatRelativeTransactionDate(transaction.occurredAt),
    [transaction.occurredAt],
  );
  const amountDisplay = useMemo(
    () => transactionAmountDisplay(transaction, side, state, state.preferences.locale),
    [side, state, transaction],
  );

  return (
    <TouchableRipple onPress={onPress} borderless style={styles.rowRipple}>
      <View style={[styles.row, side === 'transferIn' && styles.linkedTransferRow]}>
        <View style={[styles.rowIcon, { backgroundColor: iconBackgroundColor }]}>
          <MaterialCommunityIcons name={icon} size={22} color={iconColor} />
        </View>
        <View style={styles.rowCopy}>
          <Text variant="titleSmall" numberOfLines={1} style={styles.rowTitle}>
            {title}
          </Text>
          <Text
            variant="bodySmall"
            style={{ color: theme.colors.onSurfaceVariant }}
            numberOfLines={1}
          >
            {accountLine}
          </Text>
          {secondaryLine ? (
            <Text
              variant="labelSmall"
              style={{ color: theme.colors.onSurfaceVariant }}
              numberOfLines={1}
            >
              {secondaryLine}
            </Text>
          ) : null}
        </View>
        <View style={styles.rowAmountWrap}>
          <Text
            variant="titleSmall"
            numberOfLines={1}
            adjustsFontSizeToFit
            minimumFontScale={0.65}
            style={[styles.rowAmount, { color }]}
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
              style={[styles.rowSecondaryAmount, { color: theme.colors.onSurfaceVariant }]}
            >
              {secondaryAmount}
            </Text>
          ))}
          <Text
            variant="labelSmall"
            numberOfLines={1}
            style={[styles.rowDate, { color: theme.colors.onSurfaceVariant }]}
          >
            {dateLabel}
          </Text>
        </View>
      </View>
    </TouchableRipple>
  );
});

function areTransactionRowsEqual(
  previous: {
    transaction: Transaction;
    selectedAccountId?: string;
    rowDisplayKey: string;
    onOpenTransaction: (transactionId: string) => void;
  },
  next: {
    transaction: Transaction;
    selectedAccountId?: string;
    rowDisplayKey: string;
    onOpenTransaction: (transactionId: string) => void;
  },
) {
  return (
    previous.transaction.id === next.transaction.id &&
    previous.transaction.updatedAt === next.transaction.updatedAt &&
    previous.selectedAccountId === next.selectedAccountId &&
    previous.rowDisplayKey === next.rowDisplayKey &&
    previous.onOpenTransaction === next.onOpenTransaction
  );
}

function transactionRowDisplayKey(state: LedgerStateSnapshot) {
  const displayCurrency = state.preferences.displayCurrency ?? state.preferences.baseCurrency;
  const accountsKey = state.accounts
    .map((account) =>
      [account.id, account.name, account.currency, account.icon, account.color].join(':'),
    )
    .join('|');
  const categoriesKey = state.categories
    .map((category) =>
      [category.id, category.name, category.icon, category.color, category.parentId].join(':'),
    )
    .join('|');
  const ratesKey = state.exchangeRates
    .map((rate) => [rate.base, rate.quote, rate.rate, rate.asOfDate, rate.updatedAt].join(':'))
    .join('|');

  return [
    state.preferences.locale,
    state.preferences.baseCurrency,
    displayCurrency,
    accountsKey,
    categoriesKey,
    ratesKey,
  ].join('::');
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
  if (INCOME_TYPES.has(transaction.type)) return positiveAmountColor(theme.dark);
  if (EXPENSE_TYPES.has(transaction.type)) return theme.colors.error;
  return signedTransactionAmount(transaction) < 0
    ? theme.colors.error
    : positiveAmountColor(theme.dark);
}

function transactionRowIcon(transaction: Transaction, side: TransactionRowSide) {
  if (side === 'transferOut') return 'arrow-up-right';
  if (side === 'transferIn') return 'arrow-down-left';
  if (INCOME_TYPES.has(transaction.type)) return 'arrow-down-left';
  if (EXPENSE_TYPES.has(transaction.type)) return 'arrow-up-right';
  return transactionTypeIcon(transaction.type);
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

function transactionRowSecondaryMeta(transaction: Transaction): string {
  const parts: string[] = [];
  if (transaction.status !== 'cleared') parts.push(transaction.status);
  if (transaction.paymentMethod) parts.push(transaction.paymentMethod);
  if (transaction.tags?.length) parts.push(transaction.tags.slice(0, 2).join(', '));
  if (transaction.notes?.trim()) parts.push(transaction.notes.trim());
  return parts.join(' · ');
}

function formatRelativeTransactionDate(value: string): string {
  return formatRecordDateLabel(value);
}

function typeLabel(type: TransactionType): string {
  return transactionTypeLabel(type);
}

const styles = StyleSheet.create({
  screen: { flex: 1 },
  appbarTitle: { fontWeight: '700' },
  listContent: {
    padding: tokens.space.md,
    paddingBottom: 132,
  },
  headerContent: { gap: tokens.space.md, marginBottom: tokens.space.sm },
  commandPanel: {
    borderRadius: tokens.radius.lg,
    borderWidth: StyleSheet.hairlineWidth,
    padding: tokens.space.md,
    gap: tokens.space.sm,
  },
  commandHeaderRow: { flexDirection: 'row', alignItems: 'center', gap: tokens.space.sm },
  commandCopy: { flex: 1, minWidth: 0 },
  commandTitle: { fontWeight: '800' },
  searchBar: { borderRadius: tokens.radius.lg, elevation: 0 },
  suggestionRail: { gap: tokens.space.sm, paddingRight: tokens.space.sm },
  suggestionChip: {
    width: 172,
    borderRadius: tokens.radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  suggestionInner: {
    minHeight: 48,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.sm,
    paddingHorizontal: tokens.space.sm,
  },
  suggestionIcon: {
    width: 28,
    height: 28,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
  },
  suggestionCopy: { flex: 1, minWidth: 0 },
  suggestionLabel: { fontWeight: '800' },
  filterToolbar: { flexDirection: 'row', flexWrap: 'wrap', gap: tokens.space.sm },
  filterButton: {
    minWidth: '30%',
    flexGrow: 1,
    flexBasis: '30%',
    borderRadius: tokens.radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  filterButtonInner: {
    minHeight: 56,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.sm,
    paddingHorizontal: tokens.space.sm,
    paddingVertical: tokens.space.xs,
  },
  filterButtonIcon: {
    width: 30,
    height: 30,
    borderRadius: 15,
    alignItems: 'center',
    justifyContent: 'center',
  },
  filterButtonCopy: { flex: 1, minWidth: 0 },
  filterButtonValue: { fontWeight: '800' },
  filterGrid: { gap: tokens.space.sm },
  filterSelectorRow: { flexDirection: 'row', gap: tokens.space.sm },
  filterSelector: { flex: 1 },
  metricGrid: { flexDirection: 'row', gap: tokens.space.sm },
  rowRipple: { borderRadius: tokens.radius.md, overflow: 'hidden' },
  rowCard: {
    borderRadius: tokens.radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  transferPair: { gap: 2, paddingVertical: 2 },
  row: {
    flexDirection: 'row',
    gap: tokens.space.sm,
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderRadius: tokens.radius.md,
  },
  linkedTransferRow: {
    marginLeft: 22,
    borderLeftWidth: 2,
    borderLeftColor: 'rgba(128,128,128,0.28)',
    paddingLeft: 12,
  },
  expandedRow: { backgroundColor: 'rgba(128,128,128,0.08)' },
  rowIcon: {
    width: 38,
    height: 38,
    borderRadius: tokens.radius.md,
    alignItems: 'center',
    justifyContent: 'center',
  },
  rowCopy: { flex: 1, minWidth: 0, gap: 2 },
  rowTitle: { textTransform: 'capitalize' },
  rowAmountWrap: { width: 112, alignItems: 'flex-end', gap: 2 },
  rowAmount: {
    color: tokens.color.md3Positive,
    fontFamily: numericMediumFontFamily,
    fontWeight: '800',
    textAlign: 'right',
  },
  rowDate: { textAlign: 'right' },
  rowSecondaryAmount: { textAlign: 'right' },
  rowDetails: {
    marginHorizontal: 14,
    marginBottom: 12,
    padding: 10,
    borderRadius: tokens.radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    gap: 4,
  },
  detailLine: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 12,
  },
  detailValue: { flex: 1, textAlign: 'right', fontWeight: '700' },
});
