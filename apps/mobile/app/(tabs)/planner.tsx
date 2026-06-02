import type { Money } from '@1wallet/domain/money';
import { formatMoney, fromMinor, toMinor } from '@1wallet/domain/money';
import type { Account, Transaction, TransactionType } from '@1wallet/domain/types';
import {
  buildLoanPayoffProjection,
  findLinkedLoanRule,
  type LoanPayoffProjection,
} from '@1wallet/ledger/loans';
import {
  forecastFutureRuleOccurrences,
  plannedPaymentKindForRule,
  type FutureRuleOccurrence,
} from '@1wallet/ledger/rules/futureGeneration';
import type { BudgetStatus, GoalStatus } from '@1wallet/ledger/services';
import {
  accountBalance,
  convertMoneyForDisplay,
  monthRange,
  simulatePrepayment,
} from '@1wallet/ledger/services';
import type { LedgerIndexes } from '@1wallet/ledger/services/indexes';
import { indexedAccountBalance } from '@1wallet/ledger/services/indexes';
import type { LedgerState, PlannedPaymentKind } from '@1wallet/ledger/store/types';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { router } from 'expo-router';
import { useDeferredValue, useMemo, useState } from 'react';
import { KeyboardAvoidingView, Platform, ScrollView, StyleSheet, View } from 'react-native';
import {
  Appbar,
  Button,
  Divider,
  ProgressBar,
  Text,
  TouchableRipple,
  useTheme,
} from 'react-native-paper';
import { accountTypeLabel } from '../../src/accountOptions';
import { useAppDrawer } from '../../src/components/AppDrawerHost';
import {
  AppMenuAction,
  EmptyState,
  InfoRow,
  MetricTile,
  PremiumTextInput,
  SectionCard,
  type AppIconName,
} from '../../src/components/AppKit';
import { numericMediumFontFamily } from '../../src/fonts';
import { iconSurfaceForThemeTone } from '../../src/iconSystem';
import { loanScheduleCloseLabel, monthsLabel } from '../../src/loans/loanUtils';
import { transactionTypeIcon, transactionTypeIconTone } from '../../src/transactionTypes';
import { useDebouncedValue } from '../../src/useDebouncedValue';

type RowTone = 'default' | 'positive' | 'danger' | 'warning';

type PlannerSummary = {
  periodLabel: string;
  income: Money;
  everydaySpend: Money;
  loanEmis: Money;
  cardPayments: Money;
  debtCommitments: Money;
  goalNeed: Money;
  availableAfterEssentials: Money;
  freeToAllocate: Money;
  emiShare: number;
  savingsShare: number;
  loanPlans: LoanPlan[];
  upcomingCommitments: CommitmentPlan[];
};

type LoanPlan = {
  account: Account;
  outstanding: Money;
  monthlyPayment: Money;
  paymentSource: string;
  estimatedCloseLabel: string;
  acceleratedCloseLabel: string;
  monthsToClose?: number;
  acceleratedMonthsToClose?: number;
  nextDueLabel: string;
  recordCount: number;
};

type CommitmentPlan = {
  id: string;
  label: string;
  subtitle: string;
  amount: Money;
  dueLabel: string;
  type: TransactionType;
  status: Transaction['status'] | 'forecast';
  loanId?: string;
};

const INFLOW_TYPES = new Set<TransactionType>([
  'income',
  'refund',
  'interest_in',
  'cashback',
  'borrowed',
  'investment_sell',
]);

const EVERYDAY_OUTFLOW_TYPES = new Set<TransactionType>([
  'expense',
  'fee',
  'interest_out',
  'lent',
  'investment_buy',
]);

const LOAN_ACCOUNT_TYPES = new Set<Account['type']>(['loan', 'overdraft', 'lent']);
const DEFAULT_ANNUAL_LOAN_RATE = 10.5;

export default function Planner() {
  const theme = useTheme();
  const { openDrawer } = useAppDrawer();
  const { state, indexes, selectors } = useLedger();
  const [extraDebtText, setExtraDebtText] = useState('0');
  const debouncedExtraDebtText = useDebouncedValue(extraDebtText, 180);
  const deferredExtraDebtText = useDeferredValue(debouncedExtraDebtText);
  const budgets = useMemo(() => selectors.budgetStatuses(state), [selectors, state]);
  const goals = useMemo(() => selectors.goalStatuses(state), [selectors, state]);
  const viewCurrency = selectors.displayCurrency(state);
  const extraDebtMinor = toMinor(
    Math.max(0, parseAmount(deferredExtraDebtText)),
    state.preferences.baseCurrency,
  );
  const planner = useMemo(
    () => buildPlannerSummary(state, goals, indexes, extraDebtMinor),
    [extraDebtMinor, goals, indexes, state],
  );
  const payoffProjection = useMemo(
    () => buildLoanPayoffProjection(state, { extraMonthlyPaymentMinor: extraDebtMinor }),
    [extraDebtMinor, state],
  );
  const { displayedFreeToAllocate, displayedIncome } = useMemo(
    () => ({
      displayedFreeToAllocate: selectors.convertMoneyForDisplay(
        state,
        planner.freeToAllocate,
        viewCurrency,
      ),
      displayedIncome: selectors.convertMoneyForDisplay(state, planner.income, viewCurrency),
    }),
    [planner.freeToAllocate, planner.income, selectors, state, viewCurrency],
  );

  return (
    <View style={[styles.screen, { backgroundColor: theme.colors.background }]}>
      <Appbar.Header elevated={false} style={{ backgroundColor: theme.colors.background }}>
        <AppMenuAction onPress={openDrawer} />
        <Appbar.Content title="Planner" titleStyle={styles.appbarTitle} />
        <Appbar.Action icon="calendar-sync-outline" onPress={() => router.push('/recurring')} />
        <Appbar.Action icon="bank-outline" onPress={() => router.push('/loans')} />
        <Appbar.Action icon="cog-outline" onPress={() => router.push('/settings')} />
      </Appbar.Header>

      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={styles.keyboardArea}
      >
        <ScrollView
          contentContainerStyle={styles.content}
          keyboardDismissMode="on-drag"
          keyboardShouldPersistTaps="handled"
          showsVerticalScrollIndicator={false}
        >
          <View style={styles.metricGrid}>
            <MetricTile
              label="Income"
              value={formatMoney(displayedIncome, state.preferences.locale)}
              icon="cash-plus"
              tone="positive"
            />
            <MetricTile
              label="EMI load"
              value={formatPercent(planner.emiShare)}
              icon="bank-transfer-out"
              tone={
                planner.emiShare >= 0.4
                  ? 'danger'
                  : planner.emiShare >= 0.25
                    ? 'warning'
                    : 'default'
              }
            />
            <MetricTile
              label="Can allocate"
              value={formatMoney(displayedFreeToAllocate, state.preferences.locale)}
              icon="piggy-bank-outline"
              tone={planner.freeToAllocate.amountMinor >= 0 ? 'positive' : 'danger'}
            />
            <MetricTile
              label="Loans"
              value={String(planner.loanPlans.length)}
              icon="bank-outline"
              tone={planner.loanPlans.length ? 'warning' : 'default'}
            />
          </View>

          <OverviewPanel planner={planner} />
          <PlannerLoanForecastPanel
            projection={payoffProjection}
            extraDebtText={extraDebtText}
            onExtraDebtTextChange={setExtraDebtText}
          />
          <BudgetsPanel budgets={budgets} viewCurrency={viewCurrency} />
          <GoalsPanel goals={goals} viewCurrency={viewCurrency} />

          <SectionCard title="Plan actions">
            <View style={styles.linkRow}>
              <Button
                mode="contained-tonal"
                icon="bank-outline"
                onPress={() => router.push('/loans')}
              >
                Loans
              </Button>
              <Button
                mode="contained-tonal"
                icon="chart-timeline-variant"
                onPress={() => router.push('/loans/forecast' as never)}
              >
                Forecast
              </Button>
              <Button
                mode="contained-tonal"
                icon="calendar-sync-outline"
                onPress={() => router.push('/recurring')}
              >
                Recurring
              </Button>
              <Button
                mode="contained-tonal"
                icon="bullseye-arrow"
                onPress={() => router.push('/goals/new')}
              >
                Goal
              </Button>
            </View>
          </SectionCard>
        </ScrollView>
      </KeyboardAvoidingView>
    </View>
  );
}

function OverviewPanel({ planner }: { planner: PlannerSummary }) {
  const { state, selectors } = useLedger();
  const viewCurrency = selectors.displayCurrency(state);
  const display = (money: Money) =>
    formatMoney(
      selectors.convertMoneyForDisplay(state, money, viewCurrency),
      state.preferences.locale,
    );

  return (
    <>
      <SectionCard title="Income plan" subtitle={planner.periodLabel}>
        <AllocationRow
          label="Income available"
          value={display(planner.income)}
          share={1}
          icon="cash-plus"
          tone="positive"
        />
        <AllocationRow
          label="Everyday spend"
          value={display(planner.everydaySpend)}
          share={shareOf(planner.everydaySpend, planner.income)}
          icon="cart-outline"
          tone="default"
        />
        <AllocationRow
          label="EMIs and cards"
          value={display(planner.debtCommitments)}
          share={shareOf(planner.debtCommitments, planner.income)}
          icon="bank-transfer-out"
          tone="warning"
        />
        <AllocationRow
          label="Goal saving need"
          value={display(planner.goalNeed)}
          share={shareOf(planner.goalNeed, planner.income)}
          icon="bullseye-arrow"
          tone="positive"
        />
        <Divider />
        <InfoRow
          icon="piggy-bank-outline"
          label="Left for extra saving or prepayment"
          value={display(planner.freeToAllocate)}
          tone={planner.freeToAllocate.amountMinor >= 0 ? 'positive' : 'danger'}
        />
        <InfoRow
          icon="chart-pie"
          label="Saving capacity"
          value={formatPercent(planner.savingsShare)}
          tone={
            planner.savingsShare >= 0.2
              ? 'positive'
              : planner.savingsShare > 0
                ? 'warning'
                : 'danger'
          }
        />
      </SectionCard>

      <SectionCard
        title="Principal EMI and loan payoff"
        subtitle={`${planner.loanPlans.length} active loans · ${formatMoney(planner.loanEmis, state.preferences.locale)} monthly principal EMI`}
      >
        {planner.loanPlans.length === 0 ? (
          <EmptyState
            icon="bank-off-outline"
            title="No active loans"
            body="Loan and overdraft accounts will appear here with close-date estimates."
          />
        ) : (
          planner.loanPlans.map((loanPlan, index) => (
            <View key={loanPlan.account.id}>
              <LoanPlanRow loanPlan={loanPlan} />
              {index < planner.loanPlans.length - 1 && <Divider />}
            </View>
          ))
        )}
      </SectionCard>

      <SectionCard
        title="Upcoming planned payments"
        subtitle="Forecasted payments due within 30 days."
      >
        {planner.upcomingCommitments.length === 0 ? (
          <EmptyState
            icon="calendar-check-outline"
            title="No upcoming planned payments"
            body="Planned income, expenses, transfers, and adjustments will appear here."
          />
        ) : (
          planner.upcomingCommitments.map((commitment, index) => (
            <View key={commitment.id}>
              <CommitmentRow commitment={commitment} />
              {index < planner.upcomingCommitments.length - 1 && <Divider />}
            </View>
          ))
        )}
      </SectionCard>
    </>
  );
}

function PlannerLoanForecastPanel({
  projection,
  extraDebtText,
  onExtraDebtTextChange,
}: {
  projection: LoanPayoffProjection;
  extraDebtText: string;
  onExtraDebtTextChange: (value: string) => void;
}) {
  const theme = useTheme();
  const { state, selectors } = useLedger();
  const viewCurrency = selectors.displayCurrency(state);
  const loanIcon = transactionTypeIcon('loan_repayment');
  const loanIconSurface = iconSurfaceForThemeTone(theme, 'loan');
  const display = (money: Money) =>
    formatMoney(
      selectors.convertMoneyForDisplay(state, money, viewCurrency),
      state.preferences.locale,
    );
  const extraMinor = toMinor(
    Math.max(0, parseAmount(extraDebtText)),
    state.preferences.baseCurrency,
  );

  return (
    <SectionCard
      title="Loan payoff forecast"
      subtitle="Try a monthly prepayment and watch close dates move."
      actionLabel="Full forecast"
      actionIcon="chart-timeline-variant"
      onAction={() => router.push('/loans/forecast' as never)}
    >
      <View style={styles.metricGrid}>
        <MetricTile
          label="Normal close"
          value={
            projection.normalClosesOn
              ? loanScheduleCloseLabel(projection.normalClosesOn, state.preferences.locale)
              : 'Needs EMI'
          }
          icon="calendar-check-outline"
          compact
        />
        <MetricTile
          label="With extra"
          value={
            projection.acceleratedClosesOn
              ? loanScheduleCloseLabel(projection.acceleratedClosesOn, state.preferences.locale)
              : 'Needs EMI'
          }
          icon="calendar-star"
          tone={projection.monthsSaved ? 'positive' : 'default'}
          compact
        />
        <MetricTile
          label="Interest saved"
          value={display(projection.interestSaved)}
          icon="bank-minus"
          tone={projection.interestSaved.amountMinor ? 'positive' : 'default'}
          compact
        />
        <MetricTile
          label="Loans"
          value={String(projection.loans.length)}
          icon="bank-outline"
          compact
        />
      </View>
      <PremiumTextInput
        label={`Extra per month (${state.preferences.baseCurrency})`}
        value={extraDebtText}
        keyboardType="numeric"
        onChangeText={onExtraDebtTextChange}
      />
      <View style={styles.linkRow}>
        <Button
          compact
          mode="outlined"
          icon="plus"
          onPress={() =>
            onExtraDebtTextChange(
              String(
                fromMinor(
                  extraMinor + toMinor(1000, state.preferences.baseCurrency),
                  state.preferences.baseCurrency,
                ),
              ),
            )
          }
        >
          1K
        </Button>
        <Button
          compact
          mode="outlined"
          icon="plus"
          onPress={() =>
            onExtraDebtTextChange(
              String(
                fromMinor(
                  extraMinor + toMinor(10000, state.preferences.baseCurrency),
                  state.preferences.baseCurrency,
                ),
              ),
            )
          }
        >
          10K
        </Button>
        <Button compact mode="text" onPress={() => onExtraDebtTextChange('0')}>
          Reset
        </Button>
      </View>
      {projection.loans.length === 0 ? (
        <EmptyState
          icon="bank-plus"
          title="No active loans"
          body="Loan and overdraft accounts will appear here once configured."
        />
      ) : (
        projection.loans.slice(0, 4).map((loanPlan, index) => {
          return (
            <View key={loanPlan.account.id}>
              <InfoRow
                icon={loanIcon}
                iconBackgroundColor={loanIconSurface.backgroundColor}
                iconColor={loanIconSurface.iconColor}
                label={loanPlan.account.name}
                value={`${loanPlan.acceleratedClosesOn ? loanScheduleCloseLabel(loanPlan.acceleratedClosesOn, state.preferences.locale) : 'Needs EMI'} · save ${display(loanPlan.interestSaved)}`}
                tone={loanPlan.interestSaved.amountMinor ? 'positive' : 'default'}
              />
              {index < Math.min(projection.loans.length, 4) - 1 ? <Divider /> : null}
            </View>
          );
        })
      )}
    </SectionCard>
  );
}

function LoanPlanRow({ loanPlan }: { loanPlan: LoanPlan }) {
  const theme = useTheme();
  const { state, selectors } = useLedger();
  const viewCurrency = selectors.displayCurrency(state);
  const loanIcon = transactionTypeIcon('loan_repayment');
  const loanIconSurface = iconSurfaceForThemeTone(theme, 'loan');
  const closeProgress = loanPlan.monthsToClose ? clamp01(1 - loanPlan.monthsToClose / 120) : 0;

  return (
    <TouchableRipple
      borderless
      style={styles.loanPlan}
      onPress={() =>
        router.push({ pathname: '/loans', params: { loanId: loanPlan.account.id } } as never)
      }
    >
      <View style={styles.loanPlanContent}>
        <View style={styles.loanHeader}>
          <View style={[styles.loanIcon, { backgroundColor: loanIconSurface.backgroundColor }]}>
            <MaterialCommunityIcons name={loanIcon} size={22} color={loanIconSurface.iconColor} />
          </View>
          <View style={styles.fill}>
            <Text variant="titleSmall">{loanPlan.account.name}</Text>
            <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
              {accountTypeLabel(loanPlan.account.type)} · {loanPlan.account.currency}
            </Text>
          </View>
          <Text
            variant="labelMedium"
            numberOfLines={1}
            style={[styles.loanSource, { color: theme.colors.onSurfaceVariant }]}
          >
            {loanPlan.paymentSource}
          </Text>
        </View>
        <ProgressBar progress={closeProgress} style={styles.progress} />
        <View style={styles.loanStats}>
          <MiniStat
            label="Outstanding"
            value={formatMoney(
              selectors.convertMoneyForDisplay(state, loanPlan.outstanding, viewCurrency),
              state.preferences.locale,
            )}
          />
          <MiniStat
            label="Principal EMI"
            value={formatMoney(
              selectors.convertMoneyForDisplay(state, loanPlan.monthlyPayment, viewCurrency),
              state.preferences.locale,
            )}
          />
          <MiniStat label="Closes" value={loanPlan.estimatedCloseLabel} />
          <MiniStat label="With surplus" value={loanPlan.acceleratedCloseLabel} />
        </View>
        <InfoRow icon="calendar-clock" label="Next due" value={loanPlan.nextDueLabel} />
        <InfoRow
          icon="format-list-numbered"
          label="Repayment records"
          value={String(loanPlan.recordCount)}
        />
      </View>
    </TouchableRipple>
  );
}

function CommitmentRow({ commitment }: { commitment: CommitmentPlan }) {
  const theme = useTheme();
  const { state, selectors } = useLedger();
  const viewCurrency = selectors.displayCurrency(state);
  const icon = transactionTypeIcon(commitment.type);
  const iconSurface = iconSurfaceForThemeTone(theme, transactionTypeIconTone(commitment.type));
  const content = (
    <View style={styles.commitmentRowContent}>
      <View style={[styles.commitmentIcon, { backgroundColor: iconSurface.backgroundColor }]}>
        <MaterialCommunityIcons name={icon} size={20} color={iconSurface.iconColor} />
      </View>
      <View style={styles.fill}>
        <Text variant="titleSmall">{commitment.label}</Text>
        <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
          {commitment.subtitle}
        </Text>
      </View>
      <View style={styles.commitmentMeta}>
        <Text variant="titleSmall" style={styles.moneyText}>
          {formatMoney(
            selectors.convertMoneyForDisplay(state, commitment.amount, viewCurrency),
            state.preferences.locale,
          )}
        </Text>
        <Text variant="labelSmall" style={{ color: theme.colors.onSurfaceVariant }}>
          {commitment.dueLabel}
        </Text>
      </View>
    </View>
  );

  if (commitment.loanId) {
    return (
      <TouchableRipple
        borderless
        style={styles.commitmentRow}
        onPress={() =>
          router.push({ pathname: '/loans', params: { loanId: commitment.loanId } } as never)
        }
      >
        {content}
      </TouchableRipple>
    );
  }

  return <View style={styles.commitmentRow}>{content}</View>;
}

function MiniStat({ label, value }: { label: string; value: string }) {
  const theme = useTheme();
  return (
    <View style={styles.miniStat}>
      <Text variant="labelSmall" style={{ color: theme.colors.onSurfaceVariant }}>
        {label}
      </Text>
      <Text variant="titleSmall" style={styles.miniStatValue} numberOfLines={1}>
        {value}
      </Text>
    </View>
  );
}

function AllocationRow({
  label,
  value,
  share,
  icon,
  tone,
}: {
  label: string;
  value: string;
  share: number;
  icon: AppIconName;
  tone: RowTone;
}) {
  const theme = useTheme();
  const color =
    tone === 'positive'
      ? theme.colors.tertiary
      : tone === 'danger'
        ? theme.colors.error
        : tone === 'warning'
          ? theme.colors.secondary
          : theme.colors.primary;

  return (
    <View style={styles.allocationRow}>
      <View style={styles.rowHeader}>
        <View style={styles.rowLabel}>
          <MaterialCommunityIcons name={icon} size={18} color={color} />
          <Text variant="titleSmall">{label}</Text>
        </View>
        <View style={styles.allocationValue}>
          <Text variant="titleSmall" style={styles.moneyText}>
            {value}
          </Text>
          <Text variant="labelSmall" style={{ color: theme.colors.onSurfaceVariant }}>
            {formatPercent(share)}
          </Text>
        </View>
      </View>
      <ProgressBar progress={clamp01(share)} color={color} style={styles.progress} />
    </View>
  );
}

function BudgetsPanel({
  budgets,
  viewCurrency,
}: {
  budgets: BudgetStatus[];
  viewCurrency: string;
}) {
  const theme = useTheme();
  const { state, selectors } = useLedger();

  return (
    <SectionCard
      title="Budgets"
      subtitle="Monthly category limits with overrun detection."
      actionLabel="New"
      actionIcon="plus"
      onAction={() => router.push('/budgets/new')}
    >
      {budgets.length === 0 ? (
        <EmptyState
          icon="chart-donut"
          title="No budgets yet"
          body="Create budgets for groceries, food, bills, travel, or any category."
          actionLabel="New budget"
          onAction={() => router.push('/budgets/new')}
        />
      ) : (
        budgets.map((budget, index) => (
          <View key={budget.budgetId}>
            <View style={styles.rowHeader}>
              <Text variant="titleSmall" numberOfLines={1} style={styles.rowHeaderTitle}>
                {budget.name}
              </Text>
              <Text
                variant="labelLarge"
                numberOfLines={1}
                style={[
                  styles.percentText,
                  { color: budget.isOver ? theme.colors.error : theme.colors.primary },
                ]}
              >
                {Math.round(budget.share * 100)}%
              </Text>
            </View>
            <ProgressBar
              progress={Math.min(budget.share, 1)}
              color={budget.isOver ? theme.colors.error : theme.colors.primary}
              style={styles.progress}
            />
            <InfoRow
              label="Spent"
              value={formatMoney(
                selectors.convertMoneyForDisplay(state, budget.spent, viewCurrency),
                state.preferences.locale,
              )}
            />
            <InfoRow
              label="Remaining"
              value={formatMoney(
                selectors.convertMoneyForDisplay(state, budget.remaining, viewCurrency),
                state.preferences.locale,
              )}
              tone={budget.isOver ? 'danger' : 'positive'}
            />
            {index < budgets.length - 1 && <Divider />}
          </View>
        ))
      )}
    </SectionCard>
  );
}

function GoalsPanel({ goals, viewCurrency }: { goals: GoalStatus[]; viewCurrency: string }) {
  const theme = useTheme();
  const { state, selectors } = useLedger();

  return (
    <SectionCard
      title="Goals"
      subtitle="Savings targets and monthly required progress."
      actionLabel="New"
      actionIcon="plus"
      onAction={() => router.push('/goals/new')}
    >
      {goals.length === 0 ? (
        <EmptyState
          icon="bullseye-arrow"
          title="No goals yet"
          body="Create an emergency fund, trip, debt payoff, or purchase goal."
          actionLabel="New goal"
          onAction={() => router.push('/goals/new')}
        />
      ) : (
        goals.map((goal, index) => (
          <View key={goal.goalId}>
            <View style={styles.rowHeader}>
              <Text variant="titleSmall" numberOfLines={1} style={styles.rowHeaderTitle}>
                {goal.name}
              </Text>
              <Text
                variant="labelLarge"
                numberOfLines={1}
                style={[styles.percentText, { color: theme.colors.primary }]}
              >
                {Math.round(goal.share * 100)}%
              </Text>
            </View>
            <ProgressBar progress={Math.min(goal.share, 1)} style={styles.progress} />
            <InfoRow
              label="Saved"
              value={formatMoney(
                selectors.convertMoneyForDisplay(state, goal.saved, viewCurrency),
                state.preferences.locale,
              )}
            />
            <InfoRow
              label="Target"
              value={formatMoney(
                selectors.convertMoneyForDisplay(state, goal.target, viewCurrency),
                state.preferences.locale,
              )}
            />
            {goal.monthlyRequired ? (
              <InfoRow
                label="Monthly required"
                value={formatMoney(
                  selectors.convertMoneyForDisplay(state, goal.monthlyRequired, viewCurrency),
                  state.preferences.locale,
                )}
                tone="warning"
              />
            ) : null}
            {index < goals.length - 1 && <Divider />}
          </View>
        ))
      )}
    </SectionCard>
  );
}

function buildPlannerSummary(
  state: LedgerState,
  goals: GoalStatus[],
  indexes?: LedgerIndexes,
  extraForDebtOverrideMinor?: number,
): PlannerSummary {
  const now = new Date();
  const baseCurrency = state.preferences.baseCurrency;
  const { start, end } = monthRange(now, state.preferences.startDayOfMonth);
  const income = { amountMinor: 0, currency: baseCurrency };
  const everydaySpend = { amountMinor: 0, currency: baseCurrency };
  const loanEmis = { amountMinor: 0, currency: baseCurrency };
  const cardPayments = { amountMinor: 0, currency: baseCurrency };

  for (const transaction of state.transactions) {
    if (transaction.status === 'void') continue;
    if (!isWithin(transaction.occurredAt, start, end)) continue;
    if (transaction.isExcludedFromReports) continue;

    if (INFLOW_TYPES.has(transaction.type)) {
      income.amountMinor += transaction.baseAmount.amountMinor;
    } else if (EVERYDAY_OUTFLOW_TYPES.has(transaction.type)) {
      everydaySpend.amountMinor += transaction.baseAmount.amountMinor;
    } else if (transaction.type === 'loan_repayment') {
      loanEmis.amountMinor += transaction.baseAmount.amountMinor;
    } else if (transaction.type === 'card_payment') {
      cardPayments.amountMinor += transaction.baseAmount.amountMinor;
    }
  }

  const debtCommitments = {
    amountMinor: loanEmis.amountMinor + cardPayments.amountMinor,
    currency: baseCurrency,
  };
  const goalNeed = {
    amountMinor: goals.reduce((total, goal) => total + toBaseMinor(state, goal.monthlyRequired), 0),
    currency: baseCurrency,
  };
  const availableAfterEssentials = {
    amountMinor: income.amountMinor - everydaySpend.amountMinor - debtCommitments.amountMinor,
    currency: baseCurrency,
  };
  const freeToAllocate = {
    amountMinor: availableAfterEssentials.amountMinor - goalNeed.amountMinor,
    currency: baseCurrency,
  };
  const extraForDebt = Math.max(0, extraForDebtOverrideMinor ?? freeToAllocate.amountMinor);
  const loanPlans = buildLoanPlans(state, now, extraForDebt, indexes);

  return {
    periodLabel: formatPeriod(start, end, state.preferences.locale),
    income,
    everydaySpend,
    loanEmis,
    cardPayments,
    debtCommitments,
    goalNeed,
    availableAfterEssentials,
    freeToAllocate,
    emiShare: shareOf(debtCommitments, income),
    savingsShare: shareOf(
      { amountMinor: Math.max(0, availableAfterEssentials.amountMinor), currency: baseCurrency },
      income,
    ),
    loanPlans,
    upcomingCommitments: buildUpcomingCommitments(state, now),
  };
}

function buildLoanPlans(
  state: LedgerState,
  now: Date,
  extraForDebtMinor: number,
  indexes?: LedgerIndexes,
): LoanPlan[] {
  const baseCurrency = state.preferences.baseCurrency;
  const loanAccounts = state.accounts
    .filter((account) => LOAN_ACCOUNT_TYPES.has(account.type) && !account.isArchived)
    .sort((left, right) => left.sortOrder - right.sortOrder || left.name.localeCompare(right.name));

  return loanAccounts.map((account) => {
    const balance = indexes
      ? indexedAccountBalance(indexes, account)
      : accountBalance(state, account.id);
    const outstandingBaseMinor = Math.abs(toBaseMinor(state, balance));
    const repayments = (indexes?.transactionsByAccountId.get(account.id) ?? state.transactions)
      .filter(
        (transaction) =>
          transaction.type === 'loan_repayment' &&
          transaction.status !== 'void' &&
          transaction.status !== 'scheduled' &&
          (indexes ||
            transaction.accountId === account.id ||
            transaction.counterAccountId === account.id),
      )
      .sort((left, right) => left.occurredAt.localeCompare(right.occurredAt));
    const loanForecasts = loanForecastOccurrences(state, account, now, 6);
    const monthlyPayment = estimateMonthlyPayment(
      state,
      repayments,
      now,
      account.currency,
      loanForecasts[0],
    );
    const baseMonthlyPaymentMinor = toBaseMinor(state, monthlyPayment.money);
    const monthsToClose = payoffMonths(
      outstandingBaseMinor,
      baseMonthlyPaymentMinor,
      0,
      baseCurrency,
    );
    const acceleratedMonthsToClose = payoffMonths(
      outstandingBaseMinor,
      baseMonthlyPaymentMinor,
      extraForDebtMinor,
      baseCurrency,
    );
    const nextDue =
      loanForecasts[0] ??
      repayments.find(
        (transaction) =>
          transaction.status === 'pending' &&
          startOfDay(new Date(transaction.occurredAt)) >= startOfDay(now),
      );

    return {
      account,
      outstanding: convertMoneyForDisplay(
        state,
        { amountMinor: outstandingBaseMinor, currency: baseCurrency },
        account.currency,
      ),
      monthlyPayment: monthlyPayment.money,
      paymentSource: monthlyPayment.source,
      estimatedCloseLabel: closeLabel(monthsToClose, now, state.preferences.locale),
      acceleratedCloseLabel:
        extraForDebtMinor > 0
          ? closeLabel(acceleratedMonthsToClose, now, state.preferences.locale)
          : 'No surplus',
      monthsToClose,
      acceleratedMonthsToClose,
      nextDueLabel: nextDue ? relativeDueLabel(nextDue.occurredAt, now) : 'No due date',
      recordCount: repayments.length,
    };
  });
}

function estimateMonthlyPayment(
  state: LedgerState,
  repayments: Transaction[],
  now: Date,
  currency: string,
  nextForecast?: FutureRuleOccurrence,
): { money: Money; source: string } {
  const { start, end } = monthRange(now, state.preferences.startDayOfMonth);
  const currentMonth = sumTransactions(
    state,
    repayments.filter((item) => isWithin(item.occurredAt, start, end)),
    currency,
  );
  if (currentMonth.amountMinor > 0) return { money: currentMonth, source: 'This month' };

  const nextScheduled = repayments.find(
    (transaction) =>
      ['scheduled', 'pending'].includes(transaction.status) &&
      startOfDay(new Date(transaction.occurredAt)) >= startOfDay(now),
  );
  if (nextScheduled) {
    return { money: moneyForTransaction(state, nextScheduled, currency), source: 'Next due' };
  }

  if (nextForecast) {
    return {
      money: { amountMinor: nextForecast.amountMinor, currency: nextForecast.currency },
      source: 'Next forecast',
    };
  }

  const sixMonthsAgo = new Date(now);
  sixMonthsAgo.setMonth(sixMonthsAgo.getMonth() - 6);
  const recent = repayments.filter(
    (transaction) =>
      transaction.status !== 'scheduled' &&
      new Date(transaction.occurredAt) >= sixMonthsAgo &&
      new Date(transaction.occurredAt) <= now,
  );
  const recentTotal = sumTransactions(state, recent, currency);
  if (recentTotal.amountMinor > 0) {
    return {
      money: { amountMinor: Math.round(recentTotal.amountMinor / 6), currency },
      source: '6 mo avg',
    };
  }

  return { money: { amountMinor: 0, currency }, source: 'No EMI' };
}

function buildUpcomingCommitments(state: LedgerState, now: Date): CommitmentPlan[] {
  const from = startOfDay(now);
  const to = upcomingCommitmentWindowEnd(from);
  const postedRefs = new Set(
    state.transactions
      .filter((transaction) => transaction.status !== 'scheduled')
      .map((transaction) => transaction.externalRef)
      .filter((value): value is string => Boolean(value)),
  );
  const rulesById = new Map(
    (state.preferences.futureGenerationRules ?? []).map((rule) => [rule.id, rule]),
  );

  return forecastFutureRuleOccurrences(state, {
    from,
    to,
    now: from,
    maxOccurrencesPerRule: 40,
  })
    .filter((occurrence) => !postedRefs.has(occurrence.externalRef))
    .slice(0, 30)
    .map((occurrence) => {
      const rule = rulesById.get(occurrence.ruleId);
      const destination = occurrence.counterAccountId
        ? state.accounts.find((account) => account.id === occurrence.counterAccountId)
        : undefined;
      const source = state.accounts.find((account) => account.id === occurrence.accountId);
      const kind = rule ? plannedPaymentKindForRule(rule) : undefined;
      const label =
        occurrence.type === 'loan_repayment'
          ? (destination?.name ?? 'Loan EMI')
          : (rule?.name ??
            destination?.name ??
            source?.name ??
            transactionTypeFallback(occurrence.type));
      return {
        id: occurrence.externalRef,
        label,
        subtitle: [source?.name, kind ? plannedKindLabel(kind) : 'planned', 'forecast']
          .filter(Boolean)
          .join(' · '),
        amount: { amountMinor: occurrence.amountMinor, currency: occurrence.currency },
        dueLabel: relativeDueLabel(occurrence.occurredAt, now),
        type: occurrence.type,
        status: 'forecast' as const,
        loanId: loanIdForOccurrence(state, occurrence),
      };
    });
}

function loanForecastOccurrences(
  state: LedgerState,
  account: Account,
  now: Date,
  horizonMonths: number,
): FutureRuleOccurrence[] {
  const rule = findLinkedLoanRule(state, account.id);
  if (!rule) return [];
  const from = startOfDay(now);
  const to = new Date(from);
  to.setMonth(to.getMonth() + horizonMonths);
  return forecastFutureRuleOccurrences(state, {
    from,
    to,
    now: from,
    maxOccurrencesPerRule: 24,
    ruleIds: [rule.id],
  });
}

function upcomingCommitmentWindowEnd(from: Date): Date {
  const thirtyDays = addDays(from, 31);
  const nextMonth = new Date(from);
  nextMonth.setMonth(nextMonth.getMonth() + 1);
  return thirtyDays.getTime() <= nextMonth.getTime() ? thirtyDays : nextMonth;
}

function loanIdForOccurrence(
  state: LedgerState,
  occurrence: FutureRuleOccurrence,
): string | undefined {
  const account = state.accounts.find((item) => item.id === occurrence.accountId);
  if (account && LOAN_ACCOUNT_TYPES.has(account.type)) return account.id;
  const counterAccount = occurrence.counterAccountId
    ? state.accounts.find((item) => item.id === occurrence.counterAccountId)
    : undefined;
  if (counterAccount && LOAN_ACCOUNT_TYPES.has(counterAccount.type)) return counterAccount.id;
  return undefined;
}

function plannedKindLabel(kind: PlannedPaymentKind): string {
  return kind.replace(/_/g, ' ');
}

function transactionTypeFallback(type: TransactionType): string {
  return type.replace(/_/g, ' ');
}

function payoffMonths(
  outstandingMinor: number,
  monthlyPaymentMinor: number,
  extraMonthlyMinor: number,
  currency: string,
): number | undefined {
  if (outstandingMinor <= 0) return 0;
  if (monthlyPaymentMinor <= 0) return undefined;
  const result = simulatePrepayment(
    outstandingMinor,
    DEFAULT_ANNUAL_LOAN_RATE,
    monthlyPaymentMinor,
    extraMonthlyMinor,
    0,
    currency,
  );
  return Number.isFinite(result.monthsToClose) ? result.monthsToClose : undefined;
}

function closeLabel(months: number | undefined, now: Date, locale: string): string {
  if (months === 0) return 'Closed';
  if (!months) return 'Needs EMI';
  const date = new Date(now);
  date.setMonth(date.getMonth() + months);
  return `${monthsLabel(months)} · ${monthLabel(date, locale)}`;
}

function moneyForTransaction(
  state: LedgerState,
  transaction: Transaction,
  currency: string,
): Money {
  return convertMoneyForDisplay(state, transaction.amount, currency);
}

function sumTransactions(state: LedgerState, transactions: Transaction[], currency: string): Money {
  return transactions.reduce(
    (total, transaction) => ({
      amountMinor:
        total.amountMinor + moneyForTransaction(state, transaction, currency).amountMinor,
      currency,
    }),
    { amountMinor: 0, currency },
  );
}

function toBaseMinor(state: LedgerState, money?: Money): number {
  if (!money) return 0;
  return convertMoneyForDisplay(state, money, state.preferences.baseCurrency).amountMinor;
}

function shareOf(part: Money, whole: Money): number {
  if (whole.amountMinor <= 0) return 0;
  return part.amountMinor / whole.amountMinor;
}

function formatPercent(value: number): string {
  return `${Math.round(value * 100)}%`;
}

function parseAmount(value: string): number {
  return Number(value.replace(/,/g, '').trim()) || 0;
}

function clamp01(value: number): number {
  return Math.max(0, Math.min(1, value));
}

function isWithin(iso: string, start: Date, end: Date): boolean {
  const date = new Date(iso);
  return date >= start && date < end;
}

function startOfDay(date: Date): Date {
  const next = new Date(date);
  next.setHours(0, 0, 0, 0);
  return next;
}

function addDays(date: Date, days: number): Date {
  const next = new Date(date);
  next.setDate(next.getDate() + days);
  return next;
}

function relativeDueLabel(iso: string, now: Date): string {
  const due = startOfDay(new Date(iso));
  const today = startOfDay(now);
  const days = Math.round((due.getTime() - today.getTime()) / 86_400_000);
  if (days === 0) return 'Today';
  if (days === 1) return 'Tomorrow';
  if (days < 0) return `${Math.abs(days)}d late`;
  return `${days}d`;
}

function monthLabel(date: Date, locale: string): string {
  return new Intl.DateTimeFormat(locale, { month: 'short', year: 'numeric' }).format(date);
}

function formatPeriod(start: Date, end: Date, locale: string): string {
  const endDate = new Date(end);
  endDate.setDate(endDate.getDate() - 1);
  return `${monthLabel(start, locale)} · ${start.getDate()}-${endDate.getDate()}`;
}

const styles = StyleSheet.create({
  screen: { flex: 1 },
  fill: { flex: 1, minWidth: 0 },
  keyboardArea: { flex: 1 },
  appbarTitle: { fontWeight: '700' },
  content: { padding: tokens.space.lg, gap: tokens.space.lg, paddingBottom: 112 },
  metricGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: tokens.space.md },
  rowHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: tokens.space.md,
    paddingVertical: 4,
  },
  rowLabel: { flexDirection: 'row', alignItems: 'center', gap: tokens.space.sm, flexShrink: 1 },
  rowHeaderTitle: { flex: 1, minWidth: 0 },
  percentText: { flexShrink: 0, fontWeight: '800' },
  allocationRow: { gap: tokens.space.xs },
  allocationValue: { alignItems: 'flex-end', flexShrink: 0 },
  progress: { height: 8, borderRadius: 4, marginVertical: 6 },
  loanPlan: { paddingVertical: tokens.space.xs },
  loanPlanContent: { gap: tokens.space.sm },
  loanHeader: { flexDirection: 'row', alignItems: 'center', gap: tokens.space.md },
  loanSource: { flexShrink: 0, maxWidth: 116 },
  loanIcon: {
    width: 44,
    height: 44,
    borderRadius: tokens.radius.md,
    alignItems: 'center',
    justifyContent: 'center',
  },
  loanStats: { flexDirection: 'row', flexWrap: 'wrap', gap: tokens.space.sm },
  miniStat: {
    flex: 1,
    minWidth: 118,
    gap: 2,
    paddingVertical: tokens.space.xs,
  },
  miniStatValue: {
    fontFamily: numericMediumFontFamily,
    fontWeight: '800',
  },
  commitmentRow: {
    paddingVertical: 6,
  },
  commitmentRowContent: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.md,
  },
  commitmentIcon: {
    width: 40,
    height: 40,
    borderRadius: tokens.radius.md,
    alignItems: 'center',
    justifyContent: 'center',
  },
  commitmentMeta: { alignItems: 'flex-end', gap: 2, maxWidth: 132 },
  moneyText: { fontFamily: numericMediumFontFamily, fontWeight: '800' },
  linkRow: { flexDirection: 'row', flexWrap: 'wrap', gap: tokens.space.sm },
});
