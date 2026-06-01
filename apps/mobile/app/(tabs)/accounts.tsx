import { formatMoney } from '@1wallet/domain/money';
import type { Account } from '@1wallet/domain/types';
import { indexedAccountBalance } from '@1wallet/ledger/services/indexes';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { router } from 'expo-router';
import { useCallback, useMemo, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import DraggableFlatList, {
    ScaleDecorator,
    ShadowDecorator,
} from 'react-native-draggable-flatlist';
import {
    ActivityIndicator,
    Appbar,
    FAB,
    Text,
    TouchableRipple,
    useTheme,
} from 'react-native-paper';
import { accountTypeLabel, resolveAccountIconVisual } from '../../src/accountOptions';
import { useAppDrawer } from '../../src/components/AppDrawerHost';
import {
    AppMenuAction,
    EmptyState,
    MetricTile,
    PremiumSearchInput,
    TAB_BAR_OVERLAY_CLEARANCE,
    TAB_FAB_BOTTOM_OFFSET,
} from '../../src/components/AppKit';
import {
    OptionListOverlay,
    OptionSelectorRow,
    type OptionListItem,
} from '../../src/components/OptionListOverlay';
import { numericMediumFontFamily } from '../../src/fonts';

type AccountFilterPicker = 'included' | 'archived' | null;
const LIABILITY_ACCOUNT_TYPES = new Set<Account['type']>(['credit_card', 'loan', 'overdraft']);
const ACCOUNT_ROW_HEIGHT = 76;
const REORDER_ANIMATION_CONFIG = {
  damping: 36,
  mass: 0.25,
  overshootClamping: true,
  restDisplacementThreshold: 1,
  restSpeedThreshold: 1,
  stiffness: 420,
};

const INCLUDED_ACCOUNT_OPTIONS: OptionListItem<'all' | 'totals'>[] = [
  {
    value: 'all',
    label: 'Include excluded',
    description: 'Show accounts that are excluded from totals',
    icon: 'eye-outline',
  },
  {
    value: 'totals',
    label: 'Totals only',
    description: 'Show only accounts included in total balance',
    icon: 'scale-balance',
  },
];

const ARCHIVED_ACCOUNT_OPTIONS: OptionListItem<'active' | 'all'>[] = [
  {
    value: 'active',
    label: 'Active only',
    description: 'Hide archived accounts from the list',
    icon: 'eye-outline',
  },
  {
    value: 'all',
    label: 'Include archived',
    description: 'Show archived accounts beside active accounts',
    icon: 'archive-outline',
  },
];

export default function Accounts() {
  const theme = useTheme();
  const { openDrawer } = useAppDrawer();
  const { state, indexes, selectors, mutate, saveStatus, saveError } = useLedger();
  const [query, setQuery] = useState('');
  const [showExcluded, setShowExcluded] = useState(true);
  const [showArchived, setShowArchived] = useState(false);
  const [filterPicker, setFilterPicker] = useState<AccountFilterPicker>(null);

  const orderedAccounts = useMemo(
    () =>
      [...state.accounts].sort(
        (left, right) => left.sortOrder - right.sortOrder || left.name.localeCompare(right.name),
      ),
    [state.accounts],
  );

  const rows = useMemo(() => {
    const normalizedQuery = query.trim().toLowerCase();
    return orderedAccounts
      .filter((account) => showArchived || !account.isArchived)
      .filter((account) => showExcluded || account.includeInTotals)
      .filter((account) => {
        if (!normalizedQuery) return true;
        const haystack = [account.name, account.type, account.institution, account.groupName]
          .filter(Boolean)
          .join(' ')
          .toLowerCase();
        return haystack.includes(normalizedQuery);
      });
  }, [orderedAccounts, query, showArchived, showExcluded]);

  const persistReorder = useCallback(
    (visibleRows: Account[]) => {
      if (visibleRows.length === 0) return;

      const visibleOrderIds = visibleRows.map((account) => account.id);
      const visibleIds = new Set(visibleOrderIds);
      if (visibleIds.size !== visibleOrderIds.length) return;

      let visibleIndex = 0;
      const orderedIds = orderedAccounts.map((account) => {
        if (!visibleIds.has(account.id)) return account.id;
        const visibleAccountId = visibleOrderIds[visibleIndex];
        visibleIndex += 1;
        return visibleAccountId ?? account.id;
      });

      const changed = orderedIds.some((id, index) => id !== orderedAccounts[index]?.id);
      if (!changed) return;

      void mutate((draft) => {
        const sortOrderById = new Map(orderedIds.map((id, index) => [id, index + 1] as const));
        for (const account of draft.accounts) {
          const sortOrder = sortOrderById.get(account.id);
          if (sortOrder) account.sortOrder = sortOrder;
        }
      }).catch(() => undefined);
    },
    [mutate, orderedAccounts],
  );

  const viewCurrency = selectors.displayCurrency(state);
  const total = useMemo(
    () =>
      state.accounts.reduce(
        (sum, account) => {
          if (!account.includeInTotals) return sum;
          return {
            amountMinor:
              sum.amountMinor +
              selectors.convertMoneyForDisplay(
                state,
                indexedAccountBalance(indexes, account),
                viewCurrency,
              ).amountMinor,
            currency: viewCurrency,
          };
        },
        { amountMinor: 0, currency: viewCurrency },
      ),
    [indexes, selectors, state, viewCurrency],
  );
  const netWorth = useMemo(() => {
    let assets = 0;
    let liabilities = 0;
    for (const account of state.accounts) {
      if (!account.includeInNetWorth) continue;
      const amountMinor = selectors.convertMoneyForDisplay(
        state,
        indexedAccountBalance(indexes, account),
        viewCurrency,
      ).amountMinor;
      if (LIABILITY_ACCOUNT_TYPES.has(account.type)) liabilities += amountMinor;
      else assets += amountMinor;
    }
    return { total: { amountMinor: assets + liabilities, currency: viewCurrency } };
  }, [indexes, selectors, state, viewCurrency]);
  const excluded = state.accounts.filter(
    (account) => !account.includeInTotals && !account.isArchived,
  ).length;
  const archived = state.accounts.filter((account) => account.isArchived).length;
  const lastActivityByAccountId = useMemo(() => {
    const map = new Map<string, string>();
    for (const [accountId, transactions] of indexes.transactionsByAccountId) {
      const lastActivity =
        transactions.find(
          (transaction) => transaction.status !== 'scheduled' && transaction.status !== 'void',
        ) ?? transactions[0];
      if (lastActivity) map.set(accountId, lastActivity.occurredAt);
    }
    return map;
  }, [indexes.transactionsByAccountId]);

  return (
    <View style={[styles.screen, { backgroundColor: theme.colors.background }]}>
      <Appbar.Header elevated={false} style={{ backgroundColor: theme.colors.background }}>
        <AppMenuAction onPress={openDrawer} />
        <Appbar.Content title="Accounts" titleStyle={styles.appbarTitle} />
        <Appbar.Action icon="credit-card-outline" onPress={() => router.push('/cards')} />
        <Appbar.Action icon="bank-outline" onPress={() => router.push('/loans')} />
      </Appbar.Header>

      <DraggableFlatList
        data={rows}
        keyExtractor={(account) => account.id}
        activationDistance={4}
        animationConfig={REORDER_ANIMATION_CONFIG}
        autoscrollThreshold={120}
        autoscrollSpeed={520}
        containerStyle={styles.accountList}
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}
        ListHeaderComponent={
          <View style={styles.listHeader}>
            <PremiumSearchInput
              placeholder="Search accounts"
              value={query}
              onChangeText={setQuery}
            />

            <View style={styles.metricGrid}>
              <MetricTile
                label="Total"
                value={formatMoney(total, state.preferences.locale)}
                icon="wallet-outline"
                compact
              />
              <MetricTile
                label="Net worth"
                value={formatMoney(netWorth.total, state.preferences.locale)}
                icon="scale-balance"
                compact
              />
            </View>

            <View style={styles.visibilityRow}>
              <OptionSelectorRow
                label="Included accounts"
                value={showExcluded ? `Include excluded (${excluded})` : 'Totals only'}
                description={showExcluded ? 'All active accounts' : `${excluded} hidden`}
                icon="scale-balance"
                compact
                style={styles.visibilitySelector}
                onPress={() => setFilterPicker('included')}
              />
              <OptionSelectorRow
                label="Archive visibility"
                value={showArchived ? `Include archived (${archived})` : 'Active only'}
                description={showArchived ? 'Archived visible' : `${archived} archived`}
                icon="archive-outline"
                compact
                style={styles.visibilitySelector}
                onPress={() => setFilterPicker('archived')}
              />
            </View>

            {rows.length > 0 ? (
              <View style={styles.accountsHeader}>
                <View style={styles.accountsHeaderCopy}>
                  <Text variant="titleMedium" style={styles.accountsHeaderTitle}>
                    Accounts
                  </Text>
                  <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                    {rows.length} in current order
                  </Text>
                </View>
                {saveStatus === 'saving' ? <ActivityIndicator size="small" /> : null}
                {saveError ? (
                  <MaterialCommunityIcons
                    name="alert-circle-outline"
                    size={20}
                    color={theme.colors.error}
                  />
                ) : null}
              </View>
            ) : null}
          </View>
        }
        ListEmptyComponent={
          <EmptyState
            icon="wallet-plus-outline"
            title="No accounts found"
            body="Add a cash, bank, wallet, card, or loan account to start tracking."
            actionLabel="Add account"
            onAction={() => router.push('/account/new')}
          />
        }
        onDragEnd={({ data }) => {
          persistReorder(data);
        }}
        renderPlaceholder={() => (
          <View collapsable={false} pointerEvents="none" style={styles.accountCell}>
            <View
              style={[
                styles.accountPlaceholder,
                {
                  backgroundColor: theme.colors.surfaceVariant,
                  borderColor: theme.colors.outlineVariant,
                },
              ]}
            />
          </View>
        )}
        renderItem={({ item, drag, isActive }) => (
          <View collapsable={false} style={styles.accountCell}>
            <ScaleDecorator activeScale={1.01}>
              <ShadowDecorator>
                <AccountRow
                  account={item}
                  balance={indexedAccountBalance(indexes, item)}
                  drag={drag}
                  isDragging={isActive}
                  locale={state.preferences.locale}
                  lastActivityAt={lastActivityByAccountId.get(item.id)}
                />
              </ShadowDecorator>
            </ScaleDecorator>
          </View>
        )}
      />
      <OptionListOverlay
        visible={filterPicker === 'included'}
        title="Included accounts"
        options={INCLUDED_ACCOUNT_OPTIONS}
        selectedValue={showExcluded ? 'all' : 'totals'}
        searchable={false}
        onDismiss={() => setFilterPicker(null)}
        onSelect={(option) => {
          setShowExcluded(option.value === 'all');
          setFilterPicker(null);
        }}
      />
      <OptionListOverlay
        visible={filterPicker === 'archived'}
        title="Archive visibility"
        options={ARCHIVED_ACCOUNT_OPTIONS}
        selectedValue={showArchived ? 'all' : 'active'}
        searchable={false}
        onDismiss={() => setFilterPicker(null)}
        onSelect={(option) => {
          setShowArchived(option.value === 'all');
          setFilterPicker(null);
        }}
      />
      <FAB
        icon="plus"
        style={[styles.fab, { backgroundColor: theme.colors.primaryContainer }]}
        color={theme.colors.onPrimaryContainer}
        onPress={() => router.push('/account/new')}
      />
    </View>
  );
}

function AccountRow({
  account,
  balance,
  drag,
  isDragging,
  locale,
  lastActivityAt,
}: {
  account: Account;
  balance: ReturnType<typeof indexedAccountBalance>;
  drag: () => void;
  isDragging: boolean;
  locale: string;
  lastActivityAt?: string;
}) {
  const theme = useTheme();
  const visual = resolveAccountIconVisual(account);
  const onPress = () => router.push({ pathname: '/account/[id]', params: { id: account.id } });
  const meta = accountMetaLabel(account, lastActivityAt, locale);
  const flags = accountFlagLabel(account);

  return (
    <TouchableRipple
      onPress={onPress}
      style={[
        styles.accountRipple,
        {
          backgroundColor: isDragging
            ? theme.colors.primaryContainer
            : theme.colors.elevation.level1,
          borderColor: isDragging ? theme.colors.primary : theme.colors.outlineVariant,
        },
      ]}
      borderless
    >
      <View
        style={[
          styles.accountRow,
          !account.includeInTotals && styles.excludedAccountRow,
          account.isArchived && styles.archivedAccountRow,
        ]}
      >
        <View style={[styles.accountIcon, { backgroundColor: visual.backgroundColor }]}>
          <MaterialCommunityIcons name={visual.icon} size={20} color={visual.iconColor} />
        </View>
        <View style={styles.accountCopy}>
          <View style={styles.accountTitleLine}>
            <Text variant="titleSmall" numberOfLines={1} style={styles.accountName}>
              {account.name}
            </Text>
            <Text variant="titleSmall" style={styles.balanceText}>
              {formatMoney(balance, locale)}
            </Text>
          </View>
          <Text
            variant="bodySmall"
            style={[styles.accountMeta, { color: theme.colors.onSurfaceVariant }]}
            numberOfLines={1}
          >
            {meta}
          </Text>
          {flags ? (
            <Text
              variant="labelSmall"
              style={[styles.accountFlags, { color: theme.colors.secondary }]}
              numberOfLines={1}
            >
              {flags}
            </Text>
          ) : null}
        </View>
        <TouchableRipple
          accessibilityLabel={`Reorder ${account.name}`}
          accessibilityRole="button"
          onPressIn={drag}
          hitSlop={8}
          style={styles.dragHandle}
          borderless
        >
          <MaterialCommunityIcons
            name="drag-vertical"
            size={24}
            color={theme.colors.onSurfaceVariant}
          />
        </TouchableRipple>
      </View>
    </TouchableRipple>
  );
}

function accountMetaLabel(account: Account, lastActivityAt: string | undefined, locale: string) {
  const parts = [accountTypeLabel(account.type), account.currency];
  if (account.institution) parts.push(account.institution);
  if (account.groupName) parts.push(account.groupName);
  if (lastActivityAt) parts.push(`Last ${formatAccountActivity(lastActivityAt, locale)}`);
  return parts.join(' · ');
}

function accountFlagLabel(account: Account): string {
  const flags: string[] = [];
  if (!account.includeInTotals) flags.push('Totals off');
  if (!account.includeInNetWorth) flags.push('Net worth off');
  if (!account.includeInReports) flags.push('Reports off');
  if (account.isArchived) flags.push('Archived');
  return flags.join(' · ');
}

function formatAccountActivity(value: string, locale: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return 'activity';
  return date.toLocaleDateString(locale, { month: 'short', day: 'numeric' });
}

const styles = StyleSheet.create({
  screen: { flex: 1 },
  appbarTitle: { fontWeight: '700' },
  content: { padding: tokens.space.md, paddingBottom: 112 },
  accountList: { flex: 1 },
  listHeader: { gap: tokens.space.md, paddingBottom: tokens.space.md },
  accountsHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: tokens.space.md,
  },
  accountsHeaderCopy: { flex: 1, minWidth: 0 },
  accountsHeaderTitle: { fontWeight: '800' },
  metricGrid: { flexDirection: 'row', gap: tokens.space.sm },
  visibilityRow: { flexDirection: 'row', gap: tokens.space.sm },
  visibilitySelector: { flex: 1, minWidth: 0 },
  accountCell: { paddingBottom: tokens.space.md },
  accountPlaceholder: {
    height: ACCOUNT_ROW_HEIGHT,
    borderRadius: tokens.radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    opacity: 0.32,
  },
  accountRipple: {
    borderRadius: tokens.radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  accountRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.sm,
    height: ACCOUNT_ROW_HEIGHT,
    paddingLeft: tokens.space.md,
    paddingRight: tokens.space.xs,
    paddingVertical: 8,
  },
  excludedAccountRow: { opacity: 0.5 },
  archivedAccountRow: { opacity: 0.64 },
  accountIcon: {
    width: 36,
    height: 36,
    borderRadius: tokens.radius.md,
    alignItems: 'center',
    justifyContent: 'center',
  },
  accountCopy: { flex: 1, minWidth: 0, gap: 1 },
  accountTitleLine: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  accountName: { flex: 1 },
  balanceText: { fontFamily: numericMediumFontFamily, fontWeight: '800', maxWidth: 132 },
  accountMeta: { lineHeight: 16 },
  accountFlags: { lineHeight: 14, fontWeight: '700' },
  dragHandle: {
    width: 44,
    height: 44,
    borderRadius: tokens.radius.pill,
    alignItems: 'center',
    justifyContent: 'center',
  },
  fab: {
    position: 'absolute',
    right: tokens.space.lg,
    bottom: TAB_BAR_OVERLAY_CLEARANCE + TAB_FAB_BOTTOM_OFFSET,
    width: 56,
    height: 56,
    borderRadius: tokens.radius.pill,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
