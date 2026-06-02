import { formatMoney } from '@1wallet/domain/money';
import type { FutureGenerationRule, LedgerState } from '@1wallet/ledger/store/types';
import { useLedger } from '@1wallet/state';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { router } from 'expo-router';
import { useMemo } from 'react';
import { StyleSheet, View } from 'react-native';
import { Button, Surface, Text, useTheme } from 'react-native-paper';
import { AppScreen, EmptyState, SectionCard } from '../../src/components/AppKit';
import {
    plannedPaymentAmountColor,
    plannedPaymentCategorySummary,
    plannedPaymentRecurrenceSummary,
    plannedPaymentTileIcon,
    plannedPaymentTileIconBackgroundColor,
    plannedPaymentTileIconForegroundColor,
} from '../../src/plannedPayments/display';
import { plannedRuleProgressSummary } from '../../src/plannedPayments/progress';
import { restartFutureRulePlan } from '../../src/plannedPayments/ruleActions';

const EMPTY_FUTURE_RULES: FutureGenerationRule[] = [];

export default function PastPlannedPayments() {
  const { state, mutate } = useLedger();
  const planRules = state.preferences.futureGenerationRules ?? EMPTY_FUTURE_RULES;
  const completedPlanRules = useMemo(
    () =>
      planRules
        .filter((rule) => plannedRuleProgressSummary(state, rule).complete)
        .sort((left, right) => right.updatedAt.localeCompare(left.updatedAt)),
    [planRules, state],
  );

  const restartPlan = async (rule: FutureGenerationRule) => {
    let restartedId: string | undefined;
    await mutate(
      (draftState) => {
        const currentRule = draftState.preferences.futureGenerationRules?.find(
          (item) => item.id === rule.id,
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
      title="Past planned payments"
      subtitle="Completed plans you can review, edit, or restart."
      contentStyle={styles.screenContent}
    >
      <SectionCard title="Completed plans" compact>
        {completedPlanRules.length === 0 ? (
          <EmptyState
            icon="history"
            title="No past planned payments"
            body="Completed plans will appear here."
            actionLabel="Back to plans"
            onAction={() => router.replace('/recurring' as never)}
          />
        ) : (
          completedPlanRules.map((rule) => (
            <PastPlanRow
              key={rule.id}
              rule={rule}
              state={state}
              onOpen={() => router.push(`/recurring/${rule.id}` as never)}
              onEdit={() => router.push(`/recurring/${rule.id}/edit` as never)}
              onRestart={() => void restartPlan(rule)}
            />
          ))
        )}
      </SectionCard>
    </AppScreen>
  );
}

function PastPlanRow({
  rule,
  state,
  onOpen,
  onEdit,
  onRestart,
}: {
  rule: FutureGenerationRule;
  state: LedgerState;
  onOpen: () => void;
  onEdit: () => void;
  onRestart: () => void;
}) {
  const theme = useTheme();
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
  const progress = plannedRuleProgressSummary(state, rule);
  const completedLabel = `Completed ${progress.completedOccurrences}/${progress.totalOccurrences ?? 'all'}`;

  return (
    <Surface
      style={[
        styles.pastRow,
        { backgroundColor: theme.colors.surface, borderColor: theme.colors.outlineVariant },
      ]}
      elevation={0}
    >
      <View style={styles.pastMainRow}>
        <View style={[styles.planIcon, { backgroundColor: iconBackgroundColor }]}>
          <MaterialCommunityIcons name={icon} size={18} color={iconColor} />
        </View>
        <View style={styles.pastCopy}>
          <Text variant="titleSmall" numberOfLines={1} style={styles.strongText}>
            {rule.name}
          </Text>
          <Text
            variant="bodySmall"
            numberOfLines={1}
            style={{ color: theme.colors.onSurfaceVariant }}
          >
            {plannedPaymentCategorySummary(state, rule)}
          </Text>
          <Text
            variant="bodySmall"
            numberOfLines={1}
            style={{ color: theme.colors.onSurfaceVariant }}
          >
            {completedLabel} - {plannedPaymentRecurrenceSummary(rule)}
          </Text>
        </View>
        <Text
          variant="labelLarge"
          numberOfLines={1}
          adjustsFontSizeToFit
          minimumFontScale={0.75}
          style={[styles.amountText, { color: amountColor }]}
        >
          {amount}
        </Text>
      </View>
      <View style={styles.actions}>
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
  screenContent: {
    gap: 10,
    paddingHorizontal: 14,
    paddingTop: 6,
    paddingBottom: 88,
  },
  pastRow: {
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    gap: 8,
    padding: 10,
  },
  pastMainRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  planIcon: {
    width: 34,
    height: 34,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  pastCopy: {
    flex: 1,
    minWidth: 0,
    gap: 1,
  },
  strongText: {
    fontWeight: '800',
  },
  amountText: {
    flexShrink: 0,
    maxWidth: '34%',
    fontWeight: '800',
    textAlign: 'right',
  },
  actions: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'flex-end',
    gap: 6,
  },
});
