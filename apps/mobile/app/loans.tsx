import { formatMoney } from '@1wallet/domain/money';
import { buildLoanPayoffProjection, type LoanPayoffLoanPlan } from '@1wallet/ledger/loans';
import type { LedgerState } from '@1wallet/ledger/store/types';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo } from 'react';
import { StyleSheet, View } from 'react-native';
import { Button, Divider, ProgressBar, Text, TouchableRipple, useTheme } from 'react-native-paper';
import { accountTypeLabel, resolveAccountIconVisual } from '../src/accountOptions';
import {
    AppScreen,
    EmptyState,
    InfoRow,
    InlineMeta,
    MetricTile,
    SectionCard,
} from '../src/components/AppKit';
import { iconSurfaceForThemeTone } from '../src/iconSystem';
import {
    dueLabel,
    loanKindLabel,
    loanListItems,
    loanPrincipalProgress,
    loanScheduleCloseLabel,
    recurrenceCadenceLabel,
    type LoanListItem,
} from '../src/loans/loanUtils';
import { plannedRuleProgressSummary } from '../src/plannedPayments/progress';

export default function Loans() {
  const { loanId, selectedLoanId } = useLocalSearchParams<{
    loanId?: string | string[];
    selectedLoanId?: string | string[];
  }>();
  const { state, indexes, selectors } = useLedger();
  const requestedLoanId = firstParamValue(loanId) ?? firstParamValue(selectedLoanId);
  const { allItems, items, pastItems } = useMemo(() => {
    const nextAllItems = loanListItems(state, indexes, 12, { includePaidOff: true });
    const nextItems: LoanListItem[] = [];
    const nextPastItems: LoanListItem[] = [];
    for (const item of nextAllItems) {
      if (isPastLoanItem(state, item)) nextPastItems.push(item);
      else nextItems.push(item);
    }
    return { allItems: nextAllItems, items: nextItems, pastItems: nextPastItems };
  }, [indexes, state]);
  const projection = useMemo(() => buildLoanPayoffProjection(state), [state]);
  const projectionPlanByLoanId = useMemo(
    () => new Map(projection.loans.map((plan) => [plan.account.id, plan])),
    [projection.loans],
  );
  const viewCurrency = selectors.displayCurrency(state);
  const { forecastInterest, monthlyPrincipalEmi, nextDue, totalOutstanding } = useMemo(() => {
    let outstandingMinor = 0;
    let closestDue: NonNullable<LoanListItem['nextDue']> | undefined;
    for (const item of items) {
      outstandingMinor += Math.abs(
        selectors.convertMoneyForDisplay(
          state,
          { amountMinor: Math.abs(item.balance.amountMinor), currency: item.balance.currency },
          viewCurrency,
        ).amountMinor,
      );
      if (item.nextDue && (!closestDue || item.nextDue.occurredAt < closestDue.occurredAt)) {
        closestDue = item.nextDue;
      }
    }
    return {
      forecastInterest: selectors.convertMoneyForDisplay(
        state,
        projection.totalInterest,
        viewCurrency,
      ),
      monthlyPrincipalEmi: selectors.convertMoneyForDisplay(
        state,
        projection.monthlyPayment,
        viewCurrency,
      ),
      nextDue: closestDue,
      totalOutstanding: outstandingMinor,
    };
  }, [items, projection.monthlyPayment, projection.totalInterest, selectors, state, viewCurrency]);

  useEffect(() => {
    if (!requestedLoanId) return;
    if (!allItems.some((item) => item.loan.id === requestedLoanId)) return;
    router.replace(`/loans/${requestedLoanId}` as never);
  }, [allItems, requestedLoanId]);

  return (
    <AppScreen
      title="Loans & EMI"
      back={false}
      drawer
      subtitle="Track balances, repayments, linked interest, and closure dates."
      contentStyle={styles.content}
      actions={[
        {
          icon: 'chart-timeline-variant',
          label: 'Forecast',
          onPress: () => router.push('/loans/forecast' as never),
        },
        { icon: 'plus', label: 'Add loan', onPress: () => router.push('/loans/new' as never) },
      ]}
    >
      <View style={styles.metricGrid}>
        <MetricTile label="Loans" value={String(items.length)} icon="bank-outline" compact />
        <MetricTile
          label="Outstanding"
          value={formatMoney(
            { amountMinor: totalOutstanding, currency: viewCurrency },
            state.preferences.locale,
          )}
          icon="scale-balance"
          tone={totalOutstanding ? 'warning' : 'default'}
          compact
        />
        <MetricTile
          label="Principal EMI"
          value={formatMoney(monthlyPrincipalEmi, state.preferences.locale)}
          icon="bank-transfer-out"
          tone={monthlyPrincipalEmi.amountMinor ? 'warning' : 'default'}
          compact
        />
        <MetricTile
          label="Next due"
          value={nextDue ? dueLabel(nextDue.occurredAt) : 'None'}
          icon="calendar-alert"
          tone={nextDue ? 'warning' : 'default'}
          compact
        />
      </View>

      <SectionCard
        title="Payoff snapshot"
        compact
        variant="elevated"
        actionLabel="Forecast"
        actionIcon="chart-timeline-variant"
        onAction={() => router.push('/loans/forecast' as never)}
      >
        <InfoRow
          icon="calendar-check-outline"
          label="All loans close"
          value={
            projection.normalClosesOn
              ? loanScheduleCloseLabel(projection.normalClosesOn, state.preferences.locale)
              : 'Needs EMI setup'
          }
          tone={projection.normalClosesOn ? 'positive' : 'warning'}
        />
        <InfoRow
          icon="bank-minus"
          label="Forecast interest"
          value={formatMoney(forecastInterest, state.preferences.locale)}
        />
        <View style={styles.actionRow}>
          <Button mode="contained" icon="plus" onPress={() => router.push('/loans/new' as never)}>
            Add loan
          </Button>
          <Button
            mode="contained-tonal"
            icon="calendar-sync-outline"
            onPress={() => router.push('/recurring' as never)}
          >
            Plans
          </Button>
        </View>
      </SectionCard>

      <SectionCard
        title="Loan accounts"
        compact
        subtitle="Tap a loan to see records, config, and forecast details."
      >
        {items.length === 0 ? (
          <EmptyState
            icon="bank-plus"
            title="No loans yet"
            body="Create a loan, overdraft, or EMI account to track repayment progress."
            actionLabel="Add loan"
            onAction={() => router.push('/loans/new' as never)}
          />
        ) : (
          items.map((item, index) => {
            const plan = projectionPlanByLoanId.get(item.loan.id);
            return (
              <View key={item.loan.id}>
                <LoanAccountRow item={item} payoffPlan={plan} />
                {index < items.length - 1 ? <Divider /> : null}
              </View>
            );
          })
        )}
      </SectionCard>

      {pastItems.length > 0 ? (
        <SectionCard title="Past planned loans" compact>
          <PastLoansLink count={pastItems.length} />
        </SectionCard>
      ) : null}
    </AppScreen>
  );
}

function isPastLoanItem(state: LedgerState, item: LoanListItem): boolean {
  if (item.paidOff) return true;
  return item.linkedRule ? plannedRuleProgressSummary(state, item.linkedRule).complete : false;
}

function LoanAccountRow({
  item,
  payoffPlan,
}: {
  item: LoanListItem;
  payoffPlan?: LoanPayoffLoanPlan;
}) {
  const theme = useTheme();
  const { state, selectors } = useLedger();
  const loan = item.loan;
  const viewCurrency = selectors.displayCurrency(state);
  const visual = resolveAccountIconVisual(loan);
  const displayBalance = selectors.convertMoneyForDisplay(
    state,
    { amountMinor: Math.abs(item.balance.amountMinor), currency: item.balance.currency },
    viewCurrency,
  );
  const payment = loan.loanDetails?.repaymentAmount;
  const closeLabel = payoffPlan?.normalClosesOn
    ? loanScheduleCloseLabel(payoffPlan.normalClosesOn, state.preferences.locale)
    : 'Needs EMI';
  const interestLabel = item.forecast.totalInterest.amountMinor
    ? `Interest ${formatMoney(item.forecast.totalInterest, state.preferences.locale)}`
    : 'No interest';
  const principalProgress = loanPrincipalProgress(loan, item.balance);
  const progressPercent = `${Math.round(principalProgress.progress * 100)}%`;
  const emiLabel = payment?.amountMinor ? formatMoney(payment, state.preferences.locale) : 'No EMI';
  const cadenceLabel = loan.loanDetails
    ? recurrenceCadenceLabel(
        loan.loanDetails.repaymentFrequency,
        loan.loanDetails.repaymentInterval,
        loan.loanDetails.repaymentStartsOn,
        loan.loanDetails.repaymentDayOfMonth,
        state.preferences.locale,
      )
    : 'Needs setup';
  const nextDueLabel = item.nextDue ? dueLabel(item.nextDue.occurredAt) : 'No due';
  const loanTypeLabel = `${accountTypeLabel(loan.type)} ${loan.currency}`;
  const outstandingLabel = `Outstanding ${formatMoney(displayBalance, state.preferences.locale)}`;
  const repaidLabel = `Repaid ${formatMoney(principalProgress.paid, state.preferences.locale)} of ${formatMoney(
    principalProgress.total,
    state.preferences.locale,
  )}`;

  return (
    <TouchableRipple
      borderless
      style={styles.loanRow}
      onPress={() => router.push(`/loans/${loan.id}` as never)}
    >
      <View style={styles.loanRowContent}>
        <View style={styles.loanHeader}>
          <View style={[styles.loanIcon, { backgroundColor: visual.backgroundColor }]}>
            <MaterialCommunityIcons name={visual.icon} size={22} color={visual.iconColor} />
          </View>
          <View style={styles.loanCopy}>
            <Text variant="titleSmall" numberOfLines={1} style={styles.strongText}>
              {loan.name}
            </Text>
            <Text
              variant="bodySmall"
              numberOfLines={1}
              style={{ color: theme.colors.onSurfaceVariant }}
            >
              {loanTypeLabel}
            </Text>
            <ProgressBar progress={principalProgress.progress} style={styles.progress} />
            <View style={styles.progressCopyRow}>
              <Text
                variant="labelSmall"
                numberOfLines={1}
                style={[styles.progressCopy, { color: theme.colors.onSurfaceVariant }]}
              >
                {repaidLabel}
              </Text>
              <Text variant="labelSmall" numberOfLines={1} style={{ color: theme.colors.primary }}>
                {progressPercent}
              </Text>
            </View>
            <InlineMeta
              numberOfLines={2}
              items={[
                loanKindLabel(loan.loanDetails?.loanKind),
                outstandingLabel,
                closeLabel,
                interestLabel,
              ]}
            />
          </View>
          <View style={styles.amountBlock}>
            <Text
              variant="titleSmall"
              numberOfLines={1}
              adjustsFontSizeToFit
              minimumFontScale={0.72}
              style={styles.moneyText}
            >
              {emiLabel}
            </Text>
            <Text
              variant="labelSmall"
              numberOfLines={1}
              style={{ color: theme.colors.onSurfaceVariant }}
            >
              {cadenceLabel}
            </Text>
            <Text variant="labelSmall" numberOfLines={1} style={{ color: theme.colors.primary }}>
              {nextDueLabel}
            </Text>
          </View>
        </View>
      </View>
    </TouchableRipple>
  );
}

function PastLoansLink({ count }: { count: number }) {
  const theme = useTheme();
  const iconSurface = iconSurfaceForThemeTone(theme, 'loan');

  return (
    <TouchableRipple
      borderless
      style={[styles.archiveLink, { borderColor: theme.colors.outlineVariant }]}
      onPress={() => router.push('/loans/past' as never)}
    >
      <View style={styles.archiveLinkInner}>
        <View style={[styles.archiveIcon, { backgroundColor: iconSurface.backgroundColor }]}>
          <MaterialCommunityIcons name="history" size={19} color={iconSurface.iconColor} />
        </View>
        <View style={styles.archiveCopy}>
          <Text variant="titleSmall" numberOfLines={1} style={styles.strongText}>
            Past planned loans
          </Text>
          <Text
            variant="bodySmall"
            numberOfLines={1}
            style={{ color: theme.colors.onSurfaceVariant }}
          >
            {count} {count === 1 ? 'past loan plan' : 'past loan plans'} available
          </Text>
        </View>
        <MaterialCommunityIcons
          name="chevron-right"
          size={20}
          color={theme.colors.onSurfaceVariant}
        />
      </View>
    </TouchableRipple>
  );
}

function firstParamValue(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

const styles = StyleSheet.create({
  content: { paddingTop: tokens.space.md },
  metricGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: tokens.space.sm },
  actionRow: { flexDirection: 'row', flexWrap: 'wrap', gap: tokens.space.sm },
  loanRow: { borderRadius: tokens.radius.md, overflow: 'hidden' },
  loanRowContent: { gap: tokens.space.sm, paddingVertical: tokens.space.md },
  loanHeader: { flexDirection: 'row', alignItems: 'center', gap: tokens.space.md },
  loanIcon: {
    width: 44,
    height: 44,
    borderRadius: tokens.radius.md,
    alignItems: 'center',
    justifyContent: 'center',
  },
  loanCopy: { flex: 1, minWidth: 0, gap: 2 },
  amountBlock: { alignItems: 'flex-end', flexShrink: 0, width: 116, gap: 2 },
  strongText: { fontWeight: '800' },
  moneyText: { fontWeight: '800', maxWidth: '100%', textAlign: 'right' },
  progressCopyRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: tokens.space.sm,
  },
  progressCopy: { flex: 1, minWidth: 0 },
  progress: { height: 7, borderRadius: 4, marginTop: 3 },
  archiveLink: {
    borderRadius: tokens.radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  archiveLinkInner: {
    minHeight: 60,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.md,
    padding: tokens.space.md,
  },
  archiveIcon: {
    width: 42,
    height: 42,
    borderRadius: tokens.radius.md,
    alignItems: 'center',
    justifyContent: 'center',
  },
  archiveCopy: { flex: 1, minWidth: 0, gap: 2 },
});
