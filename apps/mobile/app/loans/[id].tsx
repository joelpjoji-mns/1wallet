import { formatMoney } from '@1wallet/domain/money';
import type { Account } from '@1wallet/domain/types';
import { buildLoanForecast, findLinkedLoanRule } from '@1wallet/ledger/loans';
import type { FutureRuleOccurrence } from '@1wallet/ledger/rules/futureGeneration';
import { indexedAccountBalance } from '@1wallet/ledger/services/indexes';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { router, useLocalSearchParams } from 'expo-router';
import { useMemo, useState, type ComponentProps } from 'react';
import { StyleSheet, View } from 'react-native';
import {
  Divider,
  ProgressBar,
  Snackbar,
  Text,
  TouchableRipple,
  useTheme,
} from 'react-native-paper';
import { accountTypeLabel, resolveAccountIconVisual } from '../../src/accountOptions';
import {
  AppScreen,
  EmptyState,
  InfoRow,
  InlineMeta,
  SectionCard,
  type AppIconName,
} from '../../src/components/AppKit';
import { iconSurfaceForThemeTone } from '../../src/iconSystem';
import {
  dateLabel,
  dueLabel,
  fallbackLoanDetails,
  loanCadenceLabel,
  loanForecastOccurrences,
  loanKindLabel,
  loanPrincipalProgress,
  loanRecordItems,
  loanScheduleCloseLabel,
  type LoanRecordItem,
} from '../../src/loans/loanUtils';
import { OccurrenceConfirmDialog } from '../../src/plannedPayments/OccurrenceConfirmDialog';
import { OccurrencePostponeDialog } from '../../src/plannedPayments/OccurrencePostponeDialog';
import { plannedRuleProgressSummary } from '../../src/plannedPayments/progress';
import {
  PLAN_DETAIL_OCCURRENCE_LOOKUP_OPTIONS,
  confirmFutureRuleOccurrence,
  dismissFutureRuleOccurrence,
  nearestActionableOccurrence,
  postponeFutureRuleOccurrence,
  restartFutureRulePlan,
} from '../../src/plannedPayments/ruleActions';

type MaterialIconName = ComponentProps<typeof MaterialCommunityIcons>['name'];

export default function LoanDetail() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { state, indexes, selectors, mutate } = useLedger();
  const [snackbar, setSnackbar] = useState<string | null>(null);
  const [confirmingOccurrence, setConfirmingOccurrence] = useState<FutureRuleOccurrence | null>(
    null,
  );
  const [postponingOccurrence, setPostponingOccurrence] = useState<FutureRuleOccurrence | null>(
    null,
  );
  const loan = useMemo(
    () => state.accounts.find((account) => account.id === id),
    [id, state.accounts],
  );
  const details = useMemo(
    () => (loan ? (loan.loanDetails ?? fallbackLoanDetails(loan, indexes)) : undefined),
    [indexes, loan],
  );
  const repaymentSourceAccount = useMemo(
    () =>
      details?.repaymentSourceAccountId
        ? state.accounts.find((account) => account.id === details.repaymentSourceAccountId)
        : undefined,
    [details?.repaymentSourceAccountId, state.accounts],
  );
  const repaymentSourceVisual = repaymentSourceAccount
    ? resolveAccountIconVisual(repaymentSourceAccount)
    : undefined;
  const balance = useMemo(
    () => (loan ? indexedAccountBalance(indexes, loan) : undefined),
    [indexes, loan],
  );
  const forecast = useMemo(
    () =>
      loan && details && balance ? buildLoanForecast(state, loan, details, balance) : undefined,
    [balance, details, loan, state],
  );
  const viewCurrency = selectors.displayCurrency(state);
  const displayOutstanding = useMemo(
    () =>
      forecast
        ? selectors.convertMoneyForDisplay(state, forecast.outstanding, viewCurrency)
        : undefined,
    [forecast, selectors, state, viewCurrency],
  );
  const linkedRule = useMemo(
    () => (loan ? findLinkedLoanRule(state, loan.id) : undefined),
    [loan, state],
  );
  const linkedRuleProgress = useMemo(
    () => (linkedRule ? plannedRuleProgressSummary(state, linkedRule) : undefined),
    [linkedRule, state],
  );
  const forecastUpcoming = useMemo(
    () => (loan ? loanForecastOccurrences(state, loan, 24) : []),
    [loan, state],
  );
  const nextUpcoming = useMemo(
    () =>
      linkedRule
        ? (nearestActionableOccurrence(state, linkedRule, PLAN_DETAIL_OCCURRENCE_LOOKUP_OPTIONS) ??
          forecastUpcoming[0])
        : forecastUpcoming[0],
    [forecastUpcoming, linkedRule, state],
  );
  const records = useMemo(
    () =>
      loan
        ? uniqueLoanRecords(
            loanRecordItems(state, loan, 24).filter((record) => record.kind === 'transaction'),
          )
        : [],
    [loan, state],
  );

  if (!loan) {
    return (
      <AppScreen title="Loan detail" subtitle="This loan is no longer available.">
        <EmptyState
          icon="bank-off-outline"
          title="Loan not found"
          body="It may have been deleted or archived."
          actionLabel="Back to loans"
          onAction={() => router.replace('/loans' as never)}
        />
      </AppScreen>
    );
  }
  if (!details || !balance || !forecast || !displayOutstanding) return null;

  const nextPrincipalMinor = nextUpcoming
    ? Math.max(
        0,
        nextUpcoming.principalAmountMinor ??
          nextUpcoming.counterAmountMinor ??
          nextUpcoming.amountMinor,
      )
    : 0;
  const nextInterestMinor = nextUpcoming
    ? Math.max(0, nextUpcoming.amountMinor - nextPrincipalMinor)
    : 0;
  const confirmOccurrence = async (
    occurrence: FutureRuleOccurrence,
    overrides: Parameters<typeof confirmFutureRuleOccurrence>[3],
  ) => {
    let confirmed = false;
    await mutate(
      (draftState) => {
        const currentRule = linkedRule
          ? draftState.preferences.futureGenerationRules?.find((rule) => rule.id === linkedRule.id)
          : undefined;
        if (!currentRule) return;
        confirmFutureRuleOccurrence(draftState, currentRule, occurrence, overrides);
        confirmed = true;
      },
      { slices: ['preferences', 'transactions', 'transactionSplits'] },
    );
    setConfirmingOccurrence(null);
    setSnackbar(confirmed ? 'Repayment confirmed' : 'Nothing to confirm');
  };

  const postponeOccurrence = async (
    occurrence: FutureRuleOccurrence,
    overrides: Parameters<typeof postponeFutureRuleOccurrence>[3],
  ) => {
    let postponed = false;
    await mutate(
      (draftState) => {
        const currentRule = linkedRule
          ? draftState.preferences.futureGenerationRules?.find((rule) => rule.id === linkedRule.id)
          : undefined;
        if (!currentRule) return;
        postponeFutureRuleOccurrence(draftState, currentRule, occurrence, overrides);
        postponed = true;
      },
      { slices: ['preferences'] },
    );
    setPostponingOccurrence(null);
    setSnackbar(postponed ? 'Repayment postponed' : 'Nothing to postpone');
  };

  const dismissOccurrence = async (occurrence: FutureRuleOccurrence) => {
    let dismissed = false;
    await mutate(
      (draftState) => {
        const currentRule = linkedRule
          ? draftState.preferences.futureGenerationRules?.find((rule) => rule.id === linkedRule.id)
          : undefined;
        if (!currentRule) return;
        dismissFutureRuleOccurrence(draftState, currentRule, occurrence.dueOn);
        dismissed = true;
      },
      { slices: ['preferences'] },
    );
    setSnackbar(dismissed ? 'Repayment dismissed' : 'Nothing to dismiss');
  };

  const restartLinkedPlan = async () => {
    let restartedId: string | undefined;
    await mutate(
      (draftState) => {
        const currentRule = linkedRule
          ? draftState.preferences.futureGenerationRules?.find((rule) => rule.id === linkedRule.id)
          : undefined;
        if (!currentRule) return;
        restartedId = restartFutureRulePlan(draftState, currentRule).id;
      },
      { slices: ['preferences'] },
    );
    if (restartedId) router.push(`/recurring/${restartedId}` as never);
  };

  return (
    <>
      <AppScreen
        title={loan.name}
        subtitle={`${accountTypeLabel(loan.type)} · ${loan.currency}`}
        contentStyle={styles.content}
        actions={[
          ...(linkedRuleProgress?.complete
            ? [
                {
                  icon: 'restart' as AppIconName,
                  label: 'Restart EMI',
                  onPress: () => void restartLinkedPlan(),
                },
              ]
            : []),
          {
            icon: 'chart-timeline-variant' as AppIconName,
            label: 'Forecast',
            onPress: () =>
              router.push({ pathname: '/loans/forecast', params: { loanIds: loan.id } } as never),
          },
          {
            icon: 'pencil-outline' as AppIconName,
            label: 'Edit loan',
            onPress: () => router.push(`/loans/${loan.id}/edit` as never),
          },
        ]}
      >
        <LoanHero
          loan={loan}
          details={details}
          accountBalance={balance}
          outstanding={displayOutstanding}
          forecast={forecast}
          repaymentSourceName={accountName(state.accounts, details.repaymentSourceAccountId)}
          repaymentSourceIcon={
            (repaymentSourceVisual?.icon ?? 'wallet-outline') as MaterialIconName
          }
          linkedRuleName={linkedRule?.name}
        />

        <SectionCard title="Next repayment" compact>
          {nextUpcoming ? (
            <>
              <InfoRow
                icon="calendar-clock-outline"
                label="Due"
                value={dueLabel(nextUpcoming.occurredAt)}
              />
              <InfoRow
                icon="cash-multiple"
                label="EMI"
                value={formatMoney(
                  {
                    amountMinor: nextPrincipalMinor || nextUpcoming.amountMinor,
                    currency: nextUpcoming.counterCurrency ?? loan.currency,
                  },
                  state.preferences.locale,
                )}
              />
              <InfoRow
                icon="percent-outline"
                label="Interest debit"
                value={formatMoney(
                  { amountMinor: nextInterestMinor, currency: nextUpcoming.currency },
                  state.preferences.locale,
                )}
              />
              <InfoRow
                icon="cash-plus"
                label="Total"
                value={formatMoney(
                  { amountMinor: nextUpcoming.amountMinor, currency: nextUpcoming.currency },
                  state.preferences.locale,
                )}
              />
            </>
          ) : (
            <EmptyState
              icon="calendar-clock-outline"
              title="No upcoming EMI"
              body="No linked EMI planned payment yet."
            />
          )}
          {nextUpcoming && linkedRule ? (
            <View style={styles.actionRow}>
              <RepaymentActionButton
                tone="primary"
                icon="check-circle-outline"
                onPress={() => setConfirmingOccurrence(nextUpcoming)}
                label="Record"
              />
              <RepaymentActionButton
                tone="tonal"
                icon="calendar-arrow-right"
                onPress={() => setPostponingOccurrence(nextUpcoming)}
                label="Postpone"
              />
              <RepaymentActionButton
                tone="outline"
                icon="close-circle-outline"
                onPress={() => void dismissOccurrence(nextUpcoming)}
                label="Dismiss"
              />
            </View>
          ) : null}
        </SectionCard>

        <SectionCard
          title="Records"
          compact
          subtitle={`${records.length} paid ${records.length === 1 ? 'repayment' : 'repayments'}, latest first.`}
        >
          {records.length === 0 ? (
            <EmptyState
              icon="bank-transfer-out"
              title="No repayments yet"
              body="Paid repayments will appear here."
            />
          ) : (
            records.map((record, index) => (
              <View key={record.key}>
                <LoanRecordRow record={record} />
                {index < records.length - 1 ? <Divider /> : null}
              </View>
            ))
          )}
        </SectionCard>
      </AppScreen>
      <OccurrenceConfirmDialog
        visible={Boolean(confirmingOccurrence && linkedRule)}
        rule={linkedRule}
        occurrence={confirmingOccurrence ?? undefined}
        state={state}
        indexes={indexes}
        title="Confirm repayment"
        confirmLabel="Record repayment"
        onDismiss={() => setConfirmingOccurrence(null)}
        onConfirm={(overrides) =>
          confirmingOccurrence ? confirmOccurrence(confirmingOccurrence, overrides) : undefined
        }
      />
      <OccurrencePostponeDialog
        visible={Boolean(postponingOccurrence && linkedRule)}
        rule={linkedRule}
        occurrence={postponingOccurrence ?? undefined}
        state={state}
        title="Postpone repayment"
        confirmLabel="Postpone"
        onDismiss={() => setPostponingOccurrence(null)}
        onPostpone={(overrides) =>
          postponingOccurrence ? postponeOccurrence(postponingOccurrence, overrides) : undefined
        }
      />
      <Snackbar visible={Boolean(snackbar)} onDismiss={() => setSnackbar(null)} duration={2400}>
        {snackbar}
      </Snackbar>
    </>
  );
}

function LoanHero({
  loan,
  details,
  accountBalance,
  outstanding,
  forecast,
  repaymentSourceName,
  repaymentSourceIcon,
  linkedRuleName,
}: {
  loan: Account;
  details: NonNullable<Account['loanDetails']>;
  accountBalance: { amountMinor: number; currency: string };
  outstanding: { amountMinor: number; currency: string };
  forecast: ReturnType<typeof buildLoanForecast>;
  repaymentSourceName?: string;
  repaymentSourceIcon: MaterialIconName;
  linkedRuleName?: string;
}) {
  const theme = useTheme();
  const { state } = useLedger();
  const visual = resolveAccountIconVisual(loan);
  const rateLabel = `${details.interestRatePercent ?? 0}% ${details.interestRatePeriod ?? 'annual'}`;
  const principalProgress = loanPrincipalProgress(loan, accountBalance);
  const progressPercent = `${Math.round(principalProgress.progress * 100)}%`;
  const amountLeftWithInterest = {
    amountMinor: forecast.outstanding.amountMinor + forecast.totalInterest.amountMinor,
    currency: forecast.outstanding.currency,
  };
  const startDate = details.disbursedOn ?? details.repaymentStartsOn ?? details.trackingStartsOn;
  const startDateLabel = startDate ? dateLabel(startDate, state.preferences.locale) : 'Not set';
  const endDateLabel = forecast.scheduleClosesOn
    ? dateLabel(forecast.scheduleClosesOn, state.preferences.locale)
    : 'Still open';
  const paidInstallmentsLabel = String(Math.max(0, forecast.completedInstallments));
  const remainingInstallmentsLabel =
    forecast.remainingInstallments !== undefined
      ? String(Math.max(0, forecast.remainingInstallments))
      : 'Open';
  const totalInstallmentsLabel =
    forecast.totalInstallments !== undefined
      ? String(Math.max(0, forecast.totalInstallments))
      : 'Open';

  return (
    <View
      style={[
        styles.hero,
        {
          backgroundColor: theme.colors.elevation.level1,
          borderColor: theme.colors.outlineVariant,
        },
      ]}
    >
      <View style={styles.heroTop}>
        <View style={[styles.heroIcon, { backgroundColor: visual.backgroundColor }]}>
          <MaterialCommunityIcons name={visual.icon} size={24} color={visual.iconColor} />
        </View>
        <View style={styles.fill}>
          <Text variant="titleMedium" numberOfLines={1} style={styles.heroTitle}>
            {loan.name}
          </Text>
          <Text
            variant="bodySmall"
            numberOfLines={1}
            style={{ color: theme.colors.onSurfaceVariant }}
          >
            {accountTypeLabel(loan.type)} · {loan.currency}
          </Text>
        </View>
        <Text variant="titleMedium" numberOfLines={1} style={styles.heroAmount}>
          {formatMoney(outstanding, state.preferences.locale)}
        </Text>
      </View>
      <View style={styles.progressCopyRow}>
        <Text
          variant="labelSmall"
          numberOfLines={1}
          style={{ color: theme.colors.onSurfaceVariant }}
        >
          Repaid {formatMoney(principalProgress.paid, state.preferences.locale)} of{' '}
          {formatMoney(principalProgress.total, state.preferences.locale)}
        </Text>
        <Text variant="labelSmall" numberOfLines={1} style={{ color: theme.colors.primary }}>
          {progressPercent}
        </Text>
      </View>
      <ProgressBar progress={principalProgress.progress} style={styles.progress} />
      <View style={styles.heroStats}>
        <StatPill
          label="Closes in"
          value={
            forecast.scheduleClosesOn
              ? loanScheduleCloseLabel(forecast.scheduleClosesOn, state.preferences.locale)
              : 'Needs EMI setup'
          }
        />
        <StatPill
          label="Interest"
          value={formatMoney(forecast.totalInterest, state.preferences.locale)}
        />
      </View>
      <View style={styles.heroDetailGrid}>
        <HeroDetail icon="shape-outline" label="Type" value={loanKindLabel(details.loanKind)} />
        <HeroDetail
          icon="scale-balance"
          label="Principal"
          value={
            details.principal ? formatMoney(details.principal, state.preferences.locale) : 'Not set'
          }
        />
        <HeroDetail
          icon="wallet-outline"
          label="Amount left (principal)"
          value={formatMoney(outstanding, state.preferences.locale)}
        />
        <HeroDetail
          icon="percent-outline"
          label="Remaining interest"
          value={formatMoney(forecast.totalInterest, state.preferences.locale)}
        />
        <HeroDetail
          icon="cash-multiple"
          label="Amount left + interest"
          value={formatMoney(amountLeftWithInterest, state.preferences.locale)}
        />
        <HeroDetail
          icon="bank-transfer-out"
          label="EMI"
          value={
            details.repaymentAmount
              ? formatMoney(details.repaymentAmount, state.preferences.locale)
              : 'Not set'
          }
        />
        <HeroDetail icon="percent-outline" label="Rate" value={rateLabel} />
        <HeroDetail icon="calendar-start" label="Loan start" value={startDateLabel} />
        <HeroDetail
          icon="repeat"
          label="Cadence"
          value={loanCadenceLabel(details, state.preferences.locale)}
        />
        <HeroDetail icon="check-circle-outline" label="Paid EMIs" value={paidInstallmentsLabel} />
        <HeroDetail
          icon="clock-outline"
          label="Remaining EMIs"
          value={remainingInstallmentsLabel}
        />
        <HeroDetail icon="counter" label="Total EMIs" value={totalInstallmentsLabel} />
        <HeroDetail icon="calendar-check-outline" label="End date" value={endDateLabel} />
        <HeroDetail
          icon={repaymentSourceIcon}
          label={loan.type === 'lent' ? 'Receive into' : 'Pay from'}
          value={repaymentSourceName ?? 'Not set'}
        />
        <HeroDetail
          icon={linkedRuleName ? 'link-variant' : 'link-variant-off'}
          label="Plan"
          value={linkedRuleName ?? 'Not linked'}
        />
      </View>
    </View>
  );
}

function HeroDetail({
  icon,
  label,
  value,
}: {
  icon: MaterialIconName;
  label: string;
  value: string;
}) {
  const theme = useTheme();
  const iconSurface = iconSurfaceForThemeTone(theme, 'loan');
  return (
    <View style={[styles.heroDetailItem, { borderColor: theme.colors.outlineVariant }]}>
      <View style={[styles.heroDetailIcon, { backgroundColor: iconSurface.backgroundColor }]}>
        <MaterialCommunityIcons name={icon} size={16} color={iconSurface.iconColor} />
      </View>
      <View style={styles.fill}>
        <Text
          variant="labelSmall"
          numberOfLines={1}
          style={{ color: theme.colors.onSurfaceVariant }}
        >
          {label}
        </Text>
        <Text variant="labelLarge" numberOfLines={2} style={styles.heroDetailValue}>
          {value}
        </Text>
      </View>
    </View>
  );
}

function LoanRecordRow({ record }: { record: LoanRecordItem }) {
  const theme = useTheme();
  const { state } = useLedger();
  const iconSurface = iconSurfaceForThemeTone(theme, 'loan');
  const meta = record.transaction?.paymentMethod ?? record.transaction?.source ?? 'Record';
  const emi = record.principal ?? record.total;
  const interest = record.interest ?? { amountMinor: 0, currency: record.total.currency };
  const statusLabel =
    record.kind === 'forecast' ? 'Forecast' : record.status === 'pending' ? 'Pending' : 'Paid';
  const content = (
    <View style={styles.recordInner}>
      <View style={[styles.recordIcon, { backgroundColor: iconSurface.backgroundColor }]}>
        <MaterialCommunityIcons name="bank-transfer-out" size={18} color={iconSurface.iconColor} />
      </View>
      <View style={styles.fill}>
        <Text variant="titleSmall" numberOfLines={1} style={styles.strongText}>
          {dateLabel(record.occurredAt, state.preferences.locale)}
        </Text>
        <Text
          variant="bodySmall"
          numberOfLines={1}
          style={{ color: theme.colors.onSurfaceVariant }}
        >
          {meta}
        </Text>
        <InlineMeta
          numberOfLines={1}
          items={[statusLabel, record.interestTransaction ? 'Linked interest' : null]}
        />
      </View>
      <View style={styles.recordAmountBlock}>
        <Text variant="labelLarge" numberOfLines={1} style={styles.moneyText}>
          {formatMoney(emi, state.preferences.locale)}
        </Text>
        <Text
          variant="labelSmall"
          numberOfLines={1}
          style={[styles.recordAmountLabel, { color: theme.colors.primary }]}
        >
          EMI
        </Text>
        <Text
          variant="labelSmall"
          numberOfLines={1}
          style={[styles.recordAmountMeta, { color: theme.colors.onSurfaceVariant }]}
        >
          Interest debit {formatMoney(interest, state.preferences.locale)}
        </Text>
        <Text
          variant="labelSmall"
          numberOfLines={1}
          style={[styles.recordAmountMeta, { color: theme.colors.onSurfaceVariant }]}
        >
          Total {formatMoney(record.total, state.preferences.locale)}
        </Text>
      </View>
    </View>
  );

  const transaction = record.transaction;
  if (!transaction) return content;

  return (
    <TouchableRipple
      borderless
      style={styles.recordRow}
      onPress={() => router.push(`/transaction/${transaction.id}` as never)}
    >
      {content}
    </TouchableRipple>
  );
}

function RepaymentActionButton({
  tone,
  icon,
  label,
  onPress,
}: {
  tone: 'primary' | 'tonal' | 'outline';
  icon: MaterialIconName;
  label: string;
  onPress: () => void;
}) {
  const theme = useTheme();
  const backgroundColor =
    tone === 'primary'
      ? theme.colors.primary
      : tone === 'tonal'
        ? theme.colors.primaryContainer
        : 'transparent';
  const foregroundColor =
    tone === 'primary'
      ? theme.colors.onPrimary
      : tone === 'tonal'
        ? theme.colors.onPrimaryContainer
        : theme.colors.primary;
  const borderColor = tone === 'outline' ? theme.colors.outline : 'transparent';

  return (
    <TouchableRipple
      accessibilityRole="button"
      accessibilityLabel={label}
      borderless
      style={[styles.repaymentAction, { backgroundColor, borderColor }]}
      onPress={onPress}
    >
      <View style={styles.repaymentActionInner}>
        <MaterialCommunityIcons name={icon} size={17} color={foregroundColor} />
        <Text
          variant="labelMedium"
          numberOfLines={1}
          adjustsFontSizeToFit
          minimumFontScale={0.58}
          style={[styles.repaymentActionLabel, { color: foregroundColor }]}
        >
          {label}
        </Text>
      </View>
    </TouchableRipple>
  );
}

function StatPill({ label, value }: { label: string; value: string }) {
  const theme = useTheme();
  return (
    <View style={[styles.statPill, { backgroundColor: theme.colors.surfaceVariant }]}>
      <Text variant="labelSmall" numberOfLines={1} style={{ color: theme.colors.onSurfaceVariant }}>
        {label}
      </Text>
      <Text variant="labelLarge" numberOfLines={1} style={styles.statValue}>
        {value}
      </Text>
    </View>
  );
}

function accountName(accounts: Account[], id?: string): string | undefined {
  return id ? accounts.find((account) => account.id === id)?.name : undefined;
}

function uniqueLoanRecords(records: LoanRecordItem[]): LoanRecordItem[] {
  const seen = new Set<string>();
  return records.filter((record) => {
    const key = loanRecordPaymentKey(record);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function loanRecordPaymentKey(record: LoanRecordItem): string {
  const transaction = record.transaction;
  const accountPair = transaction
    ? [transaction.accountId, transaction.counterAccountId].filter(Boolean).sort().join('|')
    : '';
  return [
    record.occurredAt.slice(0, 10),
    record.total.currency,
    record.total.amountMinor,
    record.principal?.amountMinor ?? '',
    record.interest?.amountMinor ?? '',
    accountPair,
  ].join(':');
}

const styles = StyleSheet.create({
  content: { gap: tokens.space.md, paddingTop: tokens.space.sm },
  fill: { flex: 1, minWidth: 0 },
  hero: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: tokens.radius.md,
    gap: tokens.space.sm,
    padding: tokens.space.md,
  },
  heroTop: { flexDirection: 'row', alignItems: 'center', gap: tokens.space.md },
  heroIcon: {
    width: 48,
    height: 48,
    borderRadius: tokens.radius.md,
    alignItems: 'center',
    justifyContent: 'center',
  },
  heroTitle: { fontWeight: '800' },
  heroAmount: { maxWidth: '42%', textAlign: 'right', fontWeight: '800' },
  heroStats: { flexDirection: 'row', gap: tokens.space.sm },
  heroDetailGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: tokens.space.sm },
  heroDetailItem: {
    width: '48%',
    minWidth: 145,
    flexGrow: 1,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: tokens.radius.md,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.xs,
    paddingHorizontal: tokens.space.sm,
    paddingVertical: tokens.space.xs,
  },
  heroDetailIcon: {
    width: 28,
    height: 28,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
  },
  heroDetailValue: { fontWeight: '800' },
  statPill: {
    flex: 1,
    minWidth: 0,
    borderRadius: tokens.radius.md,
    paddingHorizontal: tokens.space.sm,
    paddingVertical: tokens.space.xs,
  },
  statValue: { fontWeight: '800' },
  progressCopyRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: tokens.space.sm,
  },
  progress: { height: 8, borderRadius: 4 },
  actionRow: { flexDirection: 'row', flexWrap: 'nowrap', gap: tokens.space.xs },
  repaymentAction: {
    flex: 1,
    minWidth: 0,
    borderRadius: tokens.radius.pill,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  repaymentActionInner: {
    minHeight: 42,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 5,
    paddingHorizontal: 6,
  },
  repaymentActionLabel: {
    flexShrink: 1,
    minWidth: 0,
    textAlign: 'center',
    fontWeight: '700',
  },
  recordRow: { borderRadius: tokens.radius.md, overflow: 'hidden' },
  recordInner: {
    minHeight: 72,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.sm,
    paddingVertical: tokens.space.sm,
  },
  recordAmountBlock: { alignItems: 'flex-end', flexShrink: 0, gap: 2, minWidth: 136 },
  recordIcon: {
    width: 34,
    height: 34,
    borderRadius: tokens.radius.md,
    alignItems: 'center',
    justifyContent: 'center',
  },
  strongText: { fontWeight: '800' },
  moneyText: { fontWeight: '800', textAlign: 'right' },
  recordAmountLabel: { fontWeight: '700' },
  recordAmountMeta: { textAlign: 'right', fontWeight: '600' },
});
