import { formatMoney } from '@1wallet/domain/money';
import type { LedgerState } from '@1wallet/ledger/store/types';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { router } from 'expo-router';
import { useMemo } from 'react';
import { StyleSheet, View } from 'react-native';
import { Button, Surface, Text, useTheme } from 'react-native-paper';
import { resolveAccountIconVisual } from '../../src/accountOptions';
import { AppScreen, EmptyState, InlineMeta, SectionCard } from '../../src/components/AppKit';
import {
    loanKindLabel,
    loanListItems,
    loanPrincipalProgress,
    type LoanListItem,
} from '../../src/loans/loanUtils';
import { plannedRuleProgressSummary } from '../../src/plannedPayments/progress';
import { restartFutureRulePlan } from '../../src/plannedPayments/ruleActions';

export default function PastPlannedLoans() {
  const { state, indexes, mutate } = useLedger();
  const pastItems = useMemo(
    () =>
      loanListItems(state, indexes, 12, { includePaidOff: true })
        .filter((item) => isPastLoanItem(state, item))
        .sort((left, right) => left.loan.name.localeCompare(right.loan.name)),
    [indexes, state],
  );

  const restartLoanPlan = async (item: LoanListItem) => {
    if (!item.linkedRule) {
      router.push(`/loans/${item.loan.id}/edit` as never);
      return;
    }
    let restartedId: string | undefined;
    await mutate(
      (draftState) => {
        const currentRule = draftState.preferences.futureGenerationRules?.find(
          (rule) => rule.id === item.linkedRule?.id,
        );
        if (!currentRule) return;
        restartedId = restartFutureRulePlan(draftState, currentRule).id;
      },
      { slices: ['preferences'] },
    );
    if (restartedId) router.push(`/recurring/${restartedId}` as never);
  };

  return (
    <AppScreen
      title="Past planned loans"
      subtitle="Completed or paid-off loan plans."
      contentStyle={styles.content}
    >
      <SectionCard title="Past loan plans" compact>
        {pastItems.length === 0 ? (
          <EmptyState
            icon="history"
            title="No past planned loans"
            body="Completed or paid-off loan plans will appear here."
            actionLabel="Back to loans"
            onAction={() => router.replace('/loans' as never)}
          />
        ) : (
          pastItems.map((item) => (
            <PastLoanPlanRow
              key={item.loan.id}
              item={item}
              onOpen={() => router.push(`/loans/${item.loan.id}` as never)}
              onEdit={() => router.push(`/loans/${item.loan.id}/edit` as never)}
              onRestart={() => void restartLoanPlan(item)}
            />
          ))
        )}
      </SectionCard>
    </AppScreen>
  );
}

function isPastLoanItem(state: LedgerState, item: LoanListItem): boolean {
  if (item.paidOff) return true;
  return item.linkedRule ? plannedRuleProgressSummary(state, item.linkedRule).complete : false;
}

function PastLoanPlanRow({
  item,
  onOpen,
  onEdit,
  onRestart,
}: {
  item: LoanListItem;
  onOpen: () => void;
  onEdit: () => void;
  onRestart: () => void;
}) {
  const theme = useTheme();
  const { state, selectors } = useLedger();
  const visual = resolveAccountIconVisual(item.loan);
  const viewCurrency = selectors.displayCurrency(state);
  const displayBalance = selectors.convertMoneyForDisplay(
    state,
    item.forecast.outstanding,
    viewCurrency,
  );
  const balanceLabel = item.paidOff
    ? 'Paid off'
    : `Outstanding ${formatMoney(displayBalance, state.preferences.locale)}`;
  const progress = loanPrincipalProgress(item.loan, item.balance);

  return (
    <Surface
      style={[
        styles.pastLoanRow,
        { backgroundColor: theme.colors.surface, borderColor: theme.colors.outlineVariant },
      ]}
      elevation={0}
    >
      <View style={styles.pastLoanMainRow}>
        <View style={[styles.loanIcon, { backgroundColor: visual.backgroundColor }]}>
          <MaterialCommunityIcons name={visual.icon} size={22} color={visual.iconColor} />
        </View>
        <View style={styles.pastLoanCopy}>
          <Text variant="titleSmall" numberOfLines={1} style={styles.strongText}>
            {item.loan.name}
          </Text>
          <InlineMeta
            numberOfLines={2}
            items={[
              loanKindLabel(item.loan.loanDetails?.loanKind),
              balanceLabel,
              item.linkedRuleName ?? 'No linked plan',
              `${Math.round(progress.progress * 100)}% repaid`,
            ]}
          />
        </View>
      </View>
      <View style={styles.pastLoanActions}>
        <Button compact mode="contained-tonal" icon="open-in-new" onPress={onOpen}>
          Open
        </Button>
        <Button compact mode="outlined" icon="pencil-outline" onPress={onEdit}>
          Edit
        </Button>
        <Button compact mode="outlined" icon="restart" onPress={onRestart}>
          Restart
        </Button>
      </View>
    </Surface>
  );
}

const styles = StyleSheet.create({
  content: { paddingTop: tokens.space.md, paddingBottom: 88 },
  pastLoanRow: {
    borderRadius: tokens.radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    gap: tokens.space.sm,
    padding: tokens.space.md,
  },
  pastLoanMainRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.md,
  },
  loanIcon: {
    width: 44,
    height: 44,
    borderRadius: tokens.radius.md,
    alignItems: 'center',
    justifyContent: 'center',
  },
  pastLoanCopy: { flex: 1, minWidth: 0, gap: 2 },
  strongText: { fontWeight: '800' },
  pastLoanActions: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'flex-end',
    gap: tokens.space.sm,
  },
});
