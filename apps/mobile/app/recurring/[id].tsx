import { formatMoney } from '@1wallet/domain/money';
import type { Transaction } from '@1wallet/domain/types';
import { syncLoanDetailsFromRule } from '@1wallet/ledger/loans';
import type { FutureRuleOccurrence } from '@1wallet/ledger/rules/futureGeneration';
import {
    deleteFutureGenerationRule,
    plannedPaymentKindForRule,
    plannedPaymentPostModeForRule,
    plannedPaymentRuleStats,
    updateFutureGenerationRule,
} from '@1wallet/ledger/rules/futureGeneration';
import type { FutureGenerationRule, LedgerState } from '@1wallet/ledger/store/types';
import { useLedger } from '@1wallet/state';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { router, useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { StyleSheet, View } from 'react-native';
import {
    Button,
    Divider,
    ProgressBar,
    Snackbar,
    Surface,
    Text,
    TouchableRipple,
    useTheme,
} from 'react-native-paper';
import { resolveAccountIconVisual } from '../../src/accountOptions';
import {
    AppScreen,
    EmptyState,
    InfoRow,
    InlineMeta,
    SectionCard,
    resolveAppIconName,
    type AppIconName,
} from '../../src/components/AppKit';
import { positiveAmountColor } from '../../src/financeColors';
import { iconSurfaceForThemeTone } from '../../src/iconSystem';
import { linkedLoanInterestTransaction } from '../../src/loans/loanUtils';
import {
    PLANNED_PAYMENT_ICON_FOREGROUND_COLOR,
    accountName,
    categoryApplies,
    categoryDisplayName,
    categoryForRule,
    dueLabel,
    plannedKindMeta,
    plannedPaymentAmountColor,
    plannedPaymentCategorySummary,
    plannedPaymentEndSummary,
    plannedPaymentRecurrenceSummary,
    plannedPaymentTileIcon,
    plannedPaymentTileIconBackgroundColor,
} from '../../src/plannedPayments/display';
import { OccurrenceConfirmDialog } from '../../src/plannedPayments/OccurrenceConfirmDialog';
import { OccurrencePostponeDialog } from '../../src/plannedPayments/OccurrencePostponeDialog';
import { plannedRuleProgressSummary } from '../../src/plannedPayments/progress';
import {
    PLAN_DETAIL_OCCURRENCE_LOOKUP_OPTIONS,
    confirmFutureRuleOccurrence,
    confirmedTransactionsForRule,
    dismissFutureRuleOccurrence,
    nearestActionableOccurrence,
    postponeFutureRuleOccurrence,
    removeUnpostedFutureScheduledRecordsForRule,
    restartFutureRulePlan,
} from '../../src/plannedPayments/ruleActions';
import { transactionTypeBucket } from '../../src/transactionTypes';

export default function PlannedPaymentDetail() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { state, mutate } = useLedger();
  const [snackbar, setSnackbar] = useState<string | null>(null);
  const [confirmingOccurrence, setConfirmingOccurrence] = useState<FutureRuleOccurrence | null>(
    null,
  );
  const [postponingOccurrence, setPostponingOccurrence] = useState<FutureRuleOccurrence | null>(
    null,
  );
  const rule = state.preferences.futureGenerationRules?.find((item) => item.id === id);

  if (!rule) {
    return (
      <AppScreen title="Planned payment" subtitle="This plan is no longer available.">
        <EmptyState
          icon="calendar-remove-outline"
          title="Plan not found"
          body="It may have been deleted."
          actionLabel="Back to plans"
          onAction={() => router.replace('/recurring' as never)}
        />
      </AppScreen>
    );
  }

  const occurrence = nearestActionableOccurrence(
    state,
    rule,
    PLAN_DETAIL_OCCURRENCE_LOOKUP_OPTIONS,
  );
  const history = confirmedTransactionsForRule(state, rule);
  const progressSummary = plannedRuleProgressSummary(state, rule);

  const confirm = async (
    targetOccurrence: FutureRuleOccurrence,
    overrides: Parameters<typeof confirmFutureRuleOccurrence>[3],
  ) => {
    let confirmed = false;
    await mutate((draftState) => {
      const currentRule = draftState.preferences.futureGenerationRules?.find(
        (item) => item.id === rule.id,
      );
      if (!currentRule) return;
      confirmFutureRuleOccurrence(draftState, currentRule, targetOccurrence, overrides);
      confirmed = true;
    });
    setConfirmingOccurrence(null);
    setSnackbar(confirmed ? 'Occurrence confirmed' : 'Nothing to confirm');
  };

  const postpone = async (
    targetOccurrence: FutureRuleOccurrence,
    overrides: Parameters<typeof postponeFutureRuleOccurrence>[3],
  ) => {
    let postponed = false;
    await mutate((draftState) => {
      const currentRule = draftState.preferences.futureGenerationRules?.find(
        (item) => item.id === rule.id,
      );
      if (!currentRule) return;
      postponeFutureRuleOccurrence(draftState, currentRule, targetOccurrence, overrides);
      postponed = true;
    });
    setPostponingOccurrence(null);
    setSnackbar(postponed ? 'Occurrence postponed' : 'Nothing to postpone');
  };

  const dismiss = async () => {
    let dismissed = false;
    await mutate((draftState) => {
      const currentRule = draftState.preferences.futureGenerationRules?.find(
        (item) => item.id === rule.id,
      );
      if (!currentRule) return;
      const nextOccurrence = nearestActionableOccurrence(
        draftState,
        currentRule,
        PLAN_DETAIL_OCCURRENCE_LOOKUP_OPTIONS,
      );
      if (!nextOccurrence) return;
      dismissFutureRuleOccurrence(draftState, currentRule, nextOccurrence.dueOn);
      dismissed = true;
    });
    setSnackbar(dismissed ? 'Occurrence dismissed' : 'Nothing to dismiss');
  };

  const toggle = async () => {
    await mutate((draftState) => {
      const updatedRule = updateFutureGenerationRule(draftState, rule.id, {
        enabled: !rule.enabled,
      });
      if (updatedRule) syncLoanDetailsFromRule(draftState, updatedRule);
    });
    setSnackbar(rule.enabled ? 'Plan paused' : 'Plan resumed');
  };

  const remove = async () => {
    await mutate((draftState) => {
      deleteFutureGenerationRule(draftState, rule.id);
      removeUnpostedFutureScheduledRecordsForRule(draftState, rule.id);
    });
    router.replace('/recurring' as never);
  };

  const restart = async () => {
    let restartedId: string | undefined;
    await mutate((draftState) => {
      const currentRule = draftState.preferences.futureGenerationRules?.find(
        (item) => item.id === rule.id,
      );
      if (!currentRule) return;
      restartedId = restartFutureRulePlan(draftState, currentRule).id;
    });
    if (restartedId) router.replace(`/recurring/${restartedId}` as never);
  };

  return (
    <>
      <AppScreen
        title="Plan detail"
        subtitle={rule.name}
        contentStyle={styles.screenContent}
        actions={[
          ...(progressSummary.complete
            ? [
                {
                  icon: 'restart' as AppIconName,
                  label: 'Restart plan',
                  onPress: () => void restart(),
                },
              ]
            : []),
          {
            icon: (rule.enabled ? 'pause' : 'play') as AppIconName,
            label: rule.enabled ? 'Pause plan' : 'Resume plan',
            onPress: () => void toggle(),
          },
          {
            icon: 'pencil-outline' as AppIconName,
            label: 'Edit plan',
            onPress: () => router.push(`/recurring/${rule.id}/edit` as never),
          },
          {
            icon: 'delete-outline' as AppIconName,
            label: 'Delete plan',
            onPress: () => void remove(),
          },
        ]}
      >
        <PlanHero rule={rule} state={state} occurrence={occurrence} />
        <OccurrenceCard
          rule={rule}
          state={state}
          occurrence={occurrence}
          onConfirm={() => setConfirmingOccurrence(occurrence ?? null)}
          onPostpone={() => setPostponingOccurrence(occurrence ?? null)}
          onDismiss={() => void dismiss()}
        />
        <HistorySection state={state} rule={rule} transactions={history} />
      </AppScreen>
      <OccurrenceConfirmDialog
        visible={Boolean(confirmingOccurrence)}
        rule={rule}
        occurrence={confirmingOccurrence ?? undefined}
        state={state}
        title="Confirm occurrence"
        confirmLabel="Confirm"
        onDismiss={() => setConfirmingOccurrence(null)}
        onConfirm={(overrides) =>
          confirmingOccurrence ? confirm(confirmingOccurrence, overrides) : undefined
        }
      />
      <OccurrencePostponeDialog
        visible={Boolean(postponingOccurrence)}
        rule={rule}
        occurrence={postponingOccurrence ?? undefined}
        state={state}
        title="Postpone occurrence"
        confirmLabel="Postpone"
        onDismiss={() => setPostponingOccurrence(null)}
        onPostpone={(overrides) =>
          postponingOccurrence ? postpone(postponingOccurrence, overrides) : undefined
        }
      />
      <Snackbar visible={Boolean(snackbar)} onDismiss={() => setSnackbar(null)} duration={2400}>
        {snackbar}
      </Snackbar>
    </>
  );
}

function PlanHero({
  rule,
  state,
  occurrence,
}: {
  rule: FutureGenerationRule;
  state: LedgerState;
  occurrence?: FutureRuleOccurrence;
}) {
  const theme = useTheme();
  const plannedKind = plannedPaymentKindForRule(rule);
  const kindMeta = plannedKindMeta(plannedKind);
  const category = categoryForRule(state, rule);
  const icon = plannedPaymentTileIcon(state, rule);
  const iconBackgroundColor = plannedPaymentTileIconBackgroundColor(
    state,
    rule,
    theme.colors.primaryContainer,
  );
  const iconColor = PLANNED_PAYMENT_ICON_FOREGROUND_COLOR;
  const amountColor = plannedPaymentAmountColor(theme.colors, rule, theme.dark);
  const configIconSurface = iconSurfaceForThemeTone(theme, 'plan');
  const configIconBackgroundColor = configIconSurface.backgroundColor;
  const configIconColor = PLANNED_PAYMENT_ICON_FOREGROUND_COLOR;
  const endSummary = plannedPaymentEndSummary(rule);
  const stats = plannedPaymentRuleStats(state, rule);
  const progressSummary = plannedRuleProgressSummary(state, rule, stats);
  const remainingLabel = remainingOccurrenceLabel(rule, progressSummary.remainingOccurrences);
  const remainingAmountLabel = progressSummary.remainingAmount
    ? formatMoney(progressSummary.remainingAmount, state.preferences.locale)
    : 'Open ended';
  const statusLabel = progressSummary.complete ? 'Complete' : rule.enabled ? 'Active' : 'Paused';

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
      <View style={styles.heroTop}>
        <View style={[styles.heroIcon, { backgroundColor: iconBackgroundColor }]}>
          <MaterialCommunityIcons name={icon} size={25} color={iconColor} />
        </View>
        <View style={styles.heroCopy}>
          <Text variant="titleMedium" numberOfLines={1} style={styles.heroTitle}>
            {rule.name}
          </Text>
          <Text
            variant="bodySmall"
            numberOfLines={1}
            style={{ color: theme.colors.onSurfaceVariant }}
          >
            {kindMeta.label} · {plannedPaymentCategorySummary(state, rule)}
          </Text>
          <Text
            variant="bodySmall"
            numberOfLines={1}
            style={{ color: theme.colors.onSurfaceVariant }}
          >
            {plannedPaymentRecurrenceSummary(rule)}
          </Text>
        </View>
        <Text
          variant="titleMedium"
          numberOfLines={1}
          style={[styles.heroAmount, { color: amountColor }]}
        >
          {formatMoney(
            { amountMinor: rule.amountMinor, currency: rule.currency },
            state.preferences.locale,
          )}
        </Text>
      </View>
      <View style={styles.heroStats}>
        <StatPill
          label="Next"
          value={occurrence ? dueLabel(occurrence.occurredAt, state.preferences.locale) : 'None'}
        />
        <StatPill
          label="Posting"
          value={plannedPaymentPostModeForRule(rule) === 'automatic' ? 'Auto' : 'Manual'}
        />
        <StatPill label="Status" value={statusLabel} />
      </View>
      <View style={styles.progressPanel}>
        <View style={styles.progressCopyRow}>
          <Text variant="labelLarge" style={styles.configTitle}>
            Progress
          </Text>
          <Text variant="labelSmall" style={{ color: theme.colors.primary }}>
            {progressSummary.completedOccurrences}/{progressSummary.totalOccurrences ?? '∞'} done
          </Text>
        </View>
        {progressSummary.progress === undefined ? null : (
          <ProgressBar progress={progressSummary.progress} style={styles.planProgress} />
        )}
        <View style={styles.heroStats}>
          <StatPill
            label="Done"
            value={`${progressSummary.completedOccurrences}/${progressSummary.totalOccurrences ?? '∞'}`}
          />
          <StatPill label="Remaining" value={remainingLabel} />
          <StatPill label="Amount left" value={remainingAmountLabel} />
        </View>
      </View>
      <Divider style={styles.heroDivider} />
      <Text
        variant="labelLarge"
        style={[styles.configTitle, { color: theme.colors.onSurfaceVariant }]}
      >
        Config
      </Text>
      <View style={styles.configRows}>
        {categoryApplies(plannedKind) ? (
          <InfoRow
            icon={resolveAppIconName(category?.icon, kindMeta.icon)}
            iconBackgroundColor={category?.color ?? configIconBackgroundColor}
            iconColor={configIconColor}
            label="Category"
            value={categoryDisplayName(state.categories, category)}
          />
        ) : null}
        <InfoRow
          icon="repeat-variant"
          iconBackgroundColor={configIconBackgroundColor}
          iconColor={configIconColor}
          label="Recurrence"
          value={plannedPaymentRecurrenceSummary(rule)}
        />
        <InfoRow
          icon="calendar-start"
          iconBackgroundColor={configIconBackgroundColor}
          iconColor={configIconColor}
          label="Starts"
          value={rule.startsOn}
        />
        {endSummary === 'Forever' ? null : (
          <InfoRow
            icon="calendar-outline"
            iconBackgroundColor={configIconBackgroundColor}
            iconColor={configIconColor}
            label="Ends"
            value={endSummary}
          />
        )}
        {rule.paymentMethod ? (
          <InfoRow
            icon="bank-transfer"
            iconBackgroundColor={configIconBackgroundColor}
            iconColor={configIconColor}
            label="Payment method"
            value={rule.paymentMethod}
          />
        ) : null}
        {rule.notes ? (
          <InfoRow
            icon="note-text-outline"
            iconBackgroundColor={configIconBackgroundColor}
            iconColor={configIconColor}
            label="Notes"
            value={rule.notes}
          />
        ) : null}
      </View>
    </Surface>
  );
}

function remainingOccurrenceLabel(
  rule: FutureGenerationRule,
  remainingOccurrences: number | undefined,
): string {
  if (remainingOccurrences === undefined) return 'Ongoing';
  if (rule.type !== 'loan_repayment') return `${remainingOccurrences} left`;
  return `${remainingOccurrences} ${remainingOccurrences === 1 ? 'EMI' : 'EMIs'}`;
}

function OccurrenceCard({
  rule,
  state,
  occurrence,
  onConfirm,
  onPostpone,
  onDismiss,
}: {
  rule: FutureGenerationRule;
  state: LedgerState;
  occurrence?: FutureRuleOccurrence;
  onConfirm: () => void;
  onPostpone: () => void;
  onDismiss: () => void;
}) {
  const theme = useTheme();
  const occurrenceIconSurface = iconSurfaceForThemeTone(theme, 'plan');
  const occurrenceIconBackgroundColor = occurrenceIconSurface.backgroundColor;

  if (!occurrence) {
    return (
      <SectionCard title="Next occurrence" compact>
        <EmptyState
          icon="calendar-check-outline"
          title="Nothing upcoming"
          body="This plan has no remaining forecast dates."
        />
      </SectionCard>
    );
  }

  const account = state.accounts.find((item) => item.id === rule.accountId);
  const counterAccount = rule.counterAccountId
    ? state.accounts.find((item) => item.id === rule.counterAccountId)
    : undefined;
  const accountVisual = account ? resolveAccountIconVisual(account) : undefined;
  const counterAccountVisual = counterAccount
    ? resolveAccountIconVisual(counterAccount)
    : undefined;

  return (
    <SectionCard title="Next occurrence" compact>
      <InfoRow
        icon="calendar-clock-outline"
        iconBackgroundColor={occurrenceIconBackgroundColor}
        iconColor={PLANNED_PAYMENT_ICON_FOREGROUND_COLOR}
        label="Due"
        value={dueLabel(occurrence.occurredAt, state.preferences.locale)}
      />
      <InfoRow
        icon="cash-multiple"
        iconBackgroundColor={occurrenceIconBackgroundColor}
        iconColor={PLANNED_PAYMENT_ICON_FOREGROUND_COLOR}
        label="Amount"
        value={formatMoney(
          { amountMinor: rule.amountMinor, currency: rule.currency },
          state.preferences.locale,
        )}
      />
      <InfoRow
        icon={accountVisual?.icon ?? 'wallet-outline'}
        iconBackgroundColor={accountVisual?.backgroundColor ?? occurrenceIconBackgroundColor}
        iconColor={PLANNED_PAYMENT_ICON_FOREGROUND_COLOR}
        label="Account"
        value={accountName(state, rule.accountId) ?? 'Unknown account'}
      />
      {rule.counterAccountId ? (
        <InfoRow
          icon={counterAccountVisual?.icon ?? 'swap-horizontal'}
          iconBackgroundColor={
            counterAccountVisual?.backgroundColor ?? occurrenceIconBackgroundColor
          }
          iconColor={PLANNED_PAYMENT_ICON_FOREGROUND_COLOR}
          label="To account"
          value={accountName(state, rule.counterAccountId) ?? 'Unknown account'}
        />
      ) : null}
      <View style={styles.occurrenceActionRow}>
        <Button
          compact
          mode="contained"
          icon="check-circle-outline"
          onPress={onConfirm}
          style={styles.occurrenceActionButton}
          labelStyle={styles.occurrenceActionLabel}
        >
          Record
        </Button>
        <Button
          compact
          mode="contained-tonal"
          icon="calendar-arrow-right"
          onPress={onPostpone}
          style={styles.occurrenceActionButton}
          labelStyle={styles.occurrenceActionLabel}
        >
          Postpone
        </Button>
        <Button
          compact
          mode="outlined"
          icon="close-circle-outline"
          onPress={onDismiss}
          style={styles.occurrenceActionButton}
          labelStyle={styles.occurrenceActionLabel}
        >
          Dismiss
        </Button>
      </View>
    </SectionCard>
  );
}

function HistorySection({
  state,
  rule,
  transactions,
}: {
  state: LedgerState;
  rule: FutureGenerationRule;
  transactions: Transaction[];
}) {
  return (
    <SectionCard title="Confirmed history" compact>
      {transactions.length === 0 ? (
        <HistoryEmptyState state={state} rule={rule} />
      ) : (
        transactions.map((transaction, index) => (
          <View key={transaction.id}>
            <HistoryRow state={state} rule={rule} transaction={transaction} />
            {index < transactions.length - 1 ? <Divider /> : null}
          </View>
        ))
      )}
    </SectionCard>
  );
}

function HistoryEmptyState({ state, rule }: { state: LedgerState; rule: FutureGenerationRule }) {
  const theme = useTheme();
  const icon = plannedPaymentTileIcon(state, rule);
  const iconBackgroundColor = plannedPaymentTileIconBackgroundColor(
    state,
    rule,
    theme.colors.primaryContainer,
  );
  return (
    <View style={styles.historyEmptyState}>
      <View style={[styles.historyEmptyIcon, { backgroundColor: iconBackgroundColor }]}>
        <MaterialCommunityIcons
          name={icon}
          size={26}
          color={PLANNED_PAYMENT_ICON_FOREGROUND_COLOR}
        />
      </View>
      <Text variant="titleMedium" style={styles.historyEmptyTitle}>
        No confirmed records
      </Text>
      <Text
        variant="bodyMedium"
        style={[styles.historyEmptyBody, { color: theme.colors.onSurfaceVariant }]}
      >
        Confirmed occurrences will appear here.
      </Text>
    </View>
  );
}

function HistoryRow({
  state,
  rule,
  transaction,
}: {
  state: LedgerState;
  rule: FutureGenerationRule;
  transaction: Transaction;
}) {
  const theme = useTheme();
  const interestTransaction = linkedLoanInterestTransaction(state, transaction);
  const displayAmount = interestTransaction
    ? {
        amountMinor: transaction.amount.amountMinor + interestTransaction.amount.amountMinor,
        currency: transaction.amount.currency,
      }
    : transaction.amount;
  const amountColor = historyAmountColor(
    transaction,
    theme.dark,
    theme.colors.primary,
    theme.colors.error,
  );
  const icon = plannedPaymentTileIcon(state, rule);
  const iconBackgroundColor = plannedPaymentTileIconBackgroundColor(
    state,
    rule,
    theme.colors.primaryContainer,
  );
  return (
    <TouchableRipple
      borderless
      style={styles.historyRow}
      onPress={() => router.push(`/transaction/${transaction.id}` as never)}
    >
      <View style={styles.historyInner}>
        <View style={[styles.historyIcon, { backgroundColor: iconBackgroundColor }]}>
          <MaterialCommunityIcons
            name={icon}
            size={18}
            color={PLANNED_PAYMENT_ICON_FOREGROUND_COLOR}
          />
        </View>
        <View style={styles.historyCopy}>
          <Text variant="titleSmall" numberOfLines={1} style={styles.historyTitle}>
            {formatConfirmedDate(transaction.occurredAt, state.preferences.locale)}
          </Text>
          <Text
            variant="bodySmall"
            numberOfLines={1}
            style={{ color: theme.colors.onSurfaceVariant }}
          >
            {transaction.notes ?? accountName(state, transaction.accountId) ?? 'Confirmed'}
          </Text>
          {interestTransaction ? (
            <InlineMeta
              items={[
                `P ${formatMoney(transaction.amount, state.preferences.locale)}`,
                `I ${formatMoney(interestTransaction.amount, state.preferences.locale)}`,
              ]}
            />
          ) : null}
        </View>
        <Text
          variant="labelLarge"
          numberOfLines={1}
          style={[styles.historyAmount, { color: amountColor }]}
        >
          {formatMoney(displayAmount, state.preferences.locale)}
        </Text>
      </View>
    </TouchableRipple>
  );
}

function historyAmountColor(
  transaction: Transaction,
  dark: boolean | undefined,
  transferColor: string,
  expenseColor: string,
): string {
  const bucket = transactionTypeBucket(transaction.type);
  if (bucket === 'income') return positiveAmountColor(dark);
  if (bucket === 'transfer') return transferColor;
  return expenseColor;
}

function formatConfirmedDate(value: string, locale: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value.slice(0, 10) || 'Confirmed';
  return new Intl.DateTimeFormat(locale, { dateStyle: 'medium' }).format(date);
}

function StatPill({ label, value }: { label: string; value: string }) {
  const theme = useTheme();
  return (
    <View style={[styles.statPill, { backgroundColor: theme.colors.surfaceVariant }]}>
      <Text variant="labelSmall" numberOfLines={1} style={{ color: theme.colors.onSurfaceVariant }}>
        {label}
      </Text>
      <Text
        variant="labelLarge"
        numberOfLines={1}
        adjustsFontSizeToFit
        minimumFontScale={0.7}
        style={styles.statValue}
      >
        {value}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  screenContent: {
    gap: 10,
    paddingHorizontal: 14,
    paddingTop: 6,
    paddingBottom: 88,
  },
  hero: {
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    gap: 10,
    padding: 12,
  },
  heroTop: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  heroIcon: {
    width: 40,
    height: 40,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  heroCopy: {
    flex: 1,
    minWidth: 0,
    gap: 1,
  },
  heroTitle: {
    fontWeight: '800',
  },
  heroAmount: {
    maxWidth: '38%',
    fontWeight: '800',
    textAlign: 'right',
  },
  heroStats: {
    flexDirection: 'row',
    gap: 6,
  },
  heroDivider: {
    marginVertical: 2,
  },
  progressPanel: {
    gap: 6,
  },
  progressCopyRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 8,
  },
  planProgress: { height: 7, borderRadius: 4 },
  configTitle: {
    fontWeight: '800',
  },
  configRows: {
    gap: 8,
  },
  statPill: {
    flex: 1,
    minWidth: 0,
    borderRadius: 8,
    paddingHorizontal: 9,
    paddingVertical: 6,
  },
  statValue: {
    fontWeight: '800',
  },
  occurrenceActionRow: {
    flexDirection: 'row',
    gap: 6,
  },
  occurrenceActionButton: {
    flex: 1,
    minWidth: 0,
  },
  occurrenceActionLabel: {
    marginHorizontal: 0,
  },
  historyEmptyState: {
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    paddingHorizontal: 12,
    paddingVertical: 16,
  },
  historyEmptyIcon: {
    width: 56,
    height: 56,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  historyEmptyTitle: {
    fontWeight: '700',
    textAlign: 'center',
  },
  historyEmptyBody: {
    textAlign: 'center',
  },
  historyRow: {
    borderRadius: 8,
    overflow: 'hidden',
  },
  historyInner: {
    minHeight: 54,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 9,
    paddingVertical: 8,
  },
  historyIcon: {
    width: 30,
    height: 30,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  historyCopy: {
    flex: 1,
    minWidth: 0,
    gap: 2,
  },
  historyTitle: {
    fontWeight: '700',
  },
  historyAmount: {
    flexShrink: 0,
    maxWidth: '45%',
    fontWeight: '800',
    textAlign: 'right',
  },
});
