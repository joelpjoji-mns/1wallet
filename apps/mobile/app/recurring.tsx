import { formatMoney } from '@1wallet/domain/money';
import { plannedPaymentRuleStats } from '@1wallet/ledger/rules/futureGeneration';
import type { FutureGenerationRule, LedgerState } from '@1wallet/ledger/store/types';
import { useLedger } from '@1wallet/state';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { router } from 'expo-router';
import { useMemo } from 'react';
import { StyleSheet, View } from 'react-native';
import { ProgressBar, Surface, Text, TouchableRipple, useTheme } from 'react-native-paper';
import { AppScreen, EmptyState, SectionCard, type AppIconName } from '../src/components/AppKit';
import { iconSurfaceForThemeTone } from '../src/iconSystem';
import {
    dueLabel,
    PLANNED_PAYMENT_ICON_FOREGROUND_COLOR,
    plannedPaymentAmountColor,
    plannedPaymentCategorySummary,
    plannedPaymentRecurrenceSummary,
    plannedPaymentTileIcon,
    plannedPaymentTileIconBackgroundColor,
    plannedPaymentTileIconForegroundColor,
} from '../src/plannedPayments/display';
import { plannedRuleProgressSummary } from '../src/plannedPayments/progress';
import {
    nearestActionableOccurrence,
    PLAN_DETAIL_OCCURRENCE_LOOKUP_OPTIONS,
} from '../src/plannedPayments/ruleActions';

const DAY_MS = 24 * 60 * 60 * 1000;
const EMPTY_FUTURE_RULES: FutureGenerationRule[] = [];

export default function Recurring() {
  const { state } = useLedger();
  const planRules = state.preferences.futureGenerationRules ?? EMPTY_FUTURE_RULES;
  const { activePlanCount, completedPlanRules, visiblePlanRules } = useMemo(() => {
    const nextVisible: FutureGenerationRule[] = [];
    const nextCompleted: FutureGenerationRule[] = [];
    let nextActiveCount = 0;
    for (const rule of planRules) {
      if (plannedRuleProgressSummary(state, rule).complete) {
        nextCompleted.push(rule);
        continue;
      }
      nextVisible.push(rule);
      if (rule.enabled) nextActiveCount += 1;
    }
    return {
      activePlanCount: nextActiveCount,
      completedPlanRules: nextCompleted,
      visiblePlanRules: nextVisible,
    };
  }, [planRules, state]);
  const dueThisWeekCount = useMemo(
    () => countDueThisWeekPlanOccurrences(state, visiblePlanRules),
    [state, visiblePlanRules],
  );

  const openNewPlan = () => router.push('/recurring/new' as never);

  return (
    <AppScreen
      title="Planned payments"
      back={false}
      drawer
      subtitle="Scheduled income, expenses, transfers, and adjustments."
      contentStyle={styles.screenContent}
      actions={[{ icon: 'plus', label: 'Add plan', onPress: openNewPlan }]}
    >
      <SectionCard title="Overview" compact variant="elevated">
        <PlanSummaryPanel
          activeCount={activePlanCount}
          dueCount={dueThisWeekCount}
          onAdd={openNewPlan}
        />
      </SectionCard>

      <SectionCard title="Plans" compact>
        {visiblePlanRules.length === 0 ? (
          <EmptyState
            icon="calendar-plus"
            title="No active plans"
            body="Add an income, expense, transfer, or adjustment plan."
            actionLabel="Add plan"
            onAction={openNewPlan}
          />
        ) : (
          visiblePlanRules.map((rule) => (
            <PlannedPaymentTile
              key={rule.id}
              rule={rule}
              state={state}
              onPress={() => router.push(`/recurring/${rule.id}` as never)}
            />
          ))
        )}
      </SectionCard>

      {completedPlanRules.length > 0 ? (
        <SectionCard title="Past planned payments" compact>
          <PastPlansLink count={completedPlanRules.length} />
        </SectionCard>
      ) : null}
    </AppScreen>
  );
}

function PlanSummaryPanel({
  activeCount,
  dueCount,
  onAdd,
}: {
  activeCount: number;
  dueCount: number;
  onAdd: () => void;
}) {
  const theme = useTheme();

  return (
    <View style={styles.summaryGrid}>
      <CompactMetricPill icon="calendar-sync-outline" label="Active" value={String(activeCount)} />
      <CompactMetricPill
        icon="calendar-alert"
        label="Due this week"
        value={String(dueCount)}
        tone={dueCount > 0 ? 'warning' : 'default'}
      />
      <TouchableRipple
        accessibilityRole="button"
        accessibilityLabel="Add plan"
        borderless
        style={[styles.summaryAdd, { backgroundColor: theme.colors.primary }]}
        onPress={onAdd}
      >
        <View style={styles.summaryAddInner}>
          <MaterialCommunityIcons name="plus" size={18} color={theme.colors.onPrimary} />
          <Text variant="labelLarge" style={{ color: theme.colors.onPrimary }}>
            Add plan
          </Text>
        </View>
      </TouchableRipple>
    </View>
  );
}

function CompactMetricPill({
  icon,
  label,
  value,
  tone = 'default',
}: {
  icon: AppIconName;
  label: string;
  value: string;
  tone?: 'default' | 'warning';
}) {
  const theme = useTheme();
  const isWarning = tone === 'warning';
  const iconBackgroundColor = isWarning ? theme.colors.secondary : theme.colors.primary;
  const backgroundColor = isWarning ? theme.colors.secondaryContainer : theme.colors.surface;
  const textColor = isWarning ? theme.colors.onSecondaryContainer : theme.colors.onSurface;

  return (
    <Surface
      style={[
        styles.summaryMetric,
        {
          backgroundColor,
          borderColor: theme.colors.outlineVariant,
        },
      ]}
      elevation={0}
    >
      <View style={[styles.summaryMetricIcon, { backgroundColor: iconBackgroundColor }]}>
        <MaterialCommunityIcons
          name={icon}
          size={16}
          color={PLANNED_PAYMENT_ICON_FOREGROUND_COLOR}
        />
      </View>
      <View style={styles.summaryMetricCopy}>
        <Text
          variant="labelSmall"
          numberOfLines={1}
          style={{ color: theme.colors.onSurfaceVariant }}
        >
          {label}
        </Text>
        <Text
          variant="titleMedium"
          numberOfLines={1}
          style={[styles.summaryMetricValue, { color: textColor }]}
        >
          {value}
        </Text>
      </View>
    </Surface>
  );
}

function PlannedPaymentTile({
  rule,
  state,
  onPress,
}: {
  rule: FutureGenerationRule;
  state: LedgerState;
  onPress: () => void;
}) {
  const theme = useTheme();
  const stats = plannedPaymentRuleStats(state, rule);
  const icon = plannedPaymentTileIcon(state, rule);
  const iconBackgroundColor = plannedPaymentTileIconBackgroundColor(
    state,
    rule,
    theme.colors.primaryContainer,
  );
  const iconColor = plannedPaymentTileIconForegroundColor(state, rule, theme.colors.primary);
  const amountColor = plannedPaymentAmountColor(theme.colors, rule, theme.dark);
  const amount = formatMoney(
    { amountMinor: rule.amountMinor, currency: rule.currency },
    state.preferences.locale,
  );
  const recurrence = plannedPaymentRecurrenceSummary(rule);
  const progressSummary = plannedRuleProgressSummary(state, rule, stats);
  const progress = planProgressLabel(progressSummary);
  const nextOccurrence = nearestActionableOccurrence(
    state,
    rule,
    PLAN_DETAIL_OCCURRENCE_LOOKUP_OPTIONS,
  );
  const nextPlannedAt = nextOccurrence?.occurredAt ?? stats.nextDueAt;
  const nextPlanned = nextPlannedAt
    ? dueLabel(nextPlannedAt, state.preferences.locale)
    : 'No upcoming';
  const note = rule.notes?.trim();
  const pausedStatus = rule.enabled ? undefined : 'Paused';

  return (
    <TouchableRipple
      borderless
      style={[
        styles.planTile,
        {
          backgroundColor: theme.colors.surface,
          borderColor: rule.enabled ? theme.colors.outlineVariant : theme.colors.secondary,
        },
      ]}
      onPress={onPress}
    >
      <View style={styles.planTileInner}>
        <View style={[styles.planTileIcon, { backgroundColor: iconBackgroundColor }]}>
          <MaterialCommunityIcons name={icon} size={18} color={iconColor} />
        </View>
        <View style={styles.planTileBody}>
          <View style={styles.planTileHeader}>
            <View style={styles.planTileTitleColumn}>
              <Text variant="titleSmall" numberOfLines={1} style={styles.planTileTitle}>
                {rule.name} {progress}
              </Text>
              <Text
                variant="bodySmall"
                numberOfLines={1}
                style={{ color: theme.colors.onSurfaceVariant }}
              >
                {plannedPaymentCategorySummary(state, rule)}
              </Text>
              {note || pausedStatus ? (
                <Text
                  variant="bodySmall"
                  numberOfLines={1}
                  style={[
                    styles.planTileStatusSummary,
                    note ? styles.planTileNoteGap : undefined,
                    { color: theme.colors.onSurfaceVariant },
                  ]}
                >
                  {note ? <Text style={styles.planTileNoteText}>{note}</Text> : null}
                  {note && pausedStatus ? ' - ' : null}
                  {pausedStatus}
                </Text>
              ) : null}
            </View>
            <View style={styles.planTileMetaColumn}>
              <Text
                variant="labelLarge"
                numberOfLines={1}
                style={[styles.planTileAmount, { color: amountColor }]}
              >
                {amount}
              </Text>
              <Text
                variant="bodySmall"
                numberOfLines={1}
                style={[styles.planTileMetaText, { color: theme.colors.onSurfaceVariant }]}
              >
                {recurrence}
              </Text>
              <Text
                variant="bodySmall"
                numberOfLines={1}
                style={[styles.planTileMetaText, { color: theme.colors.primary }]}
              >
                {nextPlanned}
              </Text>
            </View>
          </View>
          {progressSummary.progress === undefined ? null : (
            <View style={styles.planTileDetailStack}>
              <ProgressBar progress={progressSummary.progress} style={styles.planProgress} />
            </View>
          )}
        </View>
        <MaterialCommunityIcons
          name="chevron-right"
          size={18}
          color={theme.colors.onSurfaceVariant}
        />
      </View>
    </TouchableRipple>
  );
}

function PastPlansLink({ count }: { count: number }) {
  const theme = useTheme();
  const iconSurface = iconSurfaceForThemeTone(theme, 'plan');

  return (
    <TouchableRipple
      borderless
      style={[styles.archiveLink, { borderColor: theme.colors.outlineVariant }]}
      onPress={() => router.push('/recurring/past' as never)}
    >
      <View style={styles.archiveLinkInner}>
        <View style={[styles.archiveIcon, { backgroundColor: iconSurface.backgroundColor }]}>
          <MaterialCommunityIcons
            name="history"
            size={19}
            color={PLANNED_PAYMENT_ICON_FOREGROUND_COLOR}
          />
        </View>
        <View style={styles.archiveCopy}>
          <Text variant="titleSmall" numberOfLines={1} style={styles.planTileTitle}>
            Past planned payments
          </Text>
          <Text
            variant="bodySmall"
            numberOfLines={1}
            style={{ color: theme.colors.onSurfaceVariant }}
          >
            {count} {count === 1 ? 'completed plan' : 'completed plans'} available
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

function daysUntil(value: string): number | undefined {
  const due = new Date(value);
  if (Number.isNaN(due.getTime())) return undefined;
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  due.setHours(0, 0, 0, 0);
  return Math.ceil((due.getTime() - today.getTime()) / DAY_MS);
}

function isDueThisWeek(value: string) {
  const daysAway = daysUntil(value);
  return daysAway !== undefined && daysAway <= 7;
}

function countDueThisWeekPlanOccurrences(
  state: LedgerState,
  rules: FutureGenerationRule[],
): number {
  return rules.reduce((count, rule) => {
    const occurrence = nearestActionableOccurrence(
      state,
      rule,
      PLAN_DETAIL_OCCURRENCE_LOOKUP_OPTIONS,
    );
    return occurrence && isDueThisWeek(occurrence.occurredAt) ? count + 1 : count;
  }, 0);
}

function planProgressLabel(progress: ReturnType<typeof plannedRuleProgressSummary>): string {
  return progress.totalOccurrences === undefined
    ? ''
    : `(${progress.completedOccurrences}/${progress.totalOccurrences})`;
}

const styles = StyleSheet.create({
  screenContent: {
    gap: 10,
    paddingHorizontal: 14,
    paddingTop: 6,
    paddingBottom: 88,
  },
  summaryGrid: {
    flexDirection: 'row',
    gap: 6,
  },
  summaryMetric: {
    flex: 1,
    minWidth: 0,
    minHeight: 50,
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    gap: 8,
    paddingHorizontal: 10,
    paddingVertical: 8,
  },
  summaryMetricCopy: {
    flex: 1,
    minWidth: 0,
  },
  summaryMetricIcon: {
    width: 28,
    height: 28,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  summaryMetricValue: {
    fontWeight: '800',
  },
  summaryAdd: {
    flex: 1,
    minWidth: 0,
    minHeight: 50,
    borderRadius: 8,
    overflow: 'hidden',
  },
  summaryAddInner: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 4,
  },
  planTile: {
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  planTileInner: {
    minHeight: 66,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingHorizontal: 10,
    paddingVertical: 9,
  },
  planTileIcon: {
    width: 34,
    height: 34,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  planTileBody: {
    flex: 1,
    minWidth: 0,
    gap: 2,
  },
  planTileHeader: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    gap: 8,
  },
  planTileTitleColumn: {
    flex: 1,
    minWidth: 0,
    gap: 1,
  },
  planTileTitle: {
    fontWeight: '800',
  },
  planTileMetaColumn: {
    flexShrink: 0,
    width: '42%',
    alignItems: 'flex-end',
    gap: 1,
  },
  planTileAmount: {
    fontWeight: '800',
    textAlign: 'right',
  },
  planTileMetaText: {
    maxWidth: '100%',
    textAlign: 'right',
  },
  planTileStatusSummary: {
    flexShrink: 1,
  },
  planTileNoteGap: {
    marginTop: 2,
  },
  planTileNoteText: {
    fontStyle: 'italic',
  },
  planTileDetailStack: { gap: 1 },
  planProgress: { height: 6, borderRadius: 3, marginBottom: 3 },
  archiveLink: {
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  archiveLinkInner: {
    minHeight: 58,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingHorizontal: 10,
    paddingVertical: 9,
  },
  archiveIcon: {
    width: 34,
    height: 34,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  archiveCopy: { flex: 1, minWidth: 0, gap: 1 },
});
