import { formatMoney, fromMinor, toMinor } from '@1wallet/domain/money';
import type { Account } from '@1wallet/domain/types';
import {
    buildLoanPayoffProjection,
    type LoanPayoffLoanPlan,
    type LoanPayoffStrategy,
} from '@1wallet/ledger/loans';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import {
    Appbar,
    Button,
    Divider,
    Portal,
    Surface,
    Text,
    TouchableRipple,
    useTheme,
} from 'react-native-paper';
import { SafeAreaView } from 'react-native-safe-area-context';
import { accountTypeLabel, resolveAccountIconVisual } from '../../src/accountOptions';
import { useBackLayer } from '../../src/components/AppBackLayer';
import {
    AppScreen,
    EmptyState,
    InfoRow,
    InlineMeta,
    MetricTile,
    PremiumRow,
    PremiumTextInput,
    SectionCard,
} from '../../src/components/AppKit';
import { OptionListOverlay, type OptionListItem } from '../../src/components/OptionListOverlay';
import { activeLoanAccounts, loanScheduleCloseLabel, monthsLabel } from '../../src/loans/loanUtils';

const STRATEGY_OPTIONS: OptionListItem<LoanPayoffStrategy>[] = [
  {
    value: 'equal',
    label: 'Equal split',
    description: 'Divide extra money across selected loans',
    icon: 'call-split',
  },
  {
    value: 'avalanche',
    label: 'Avalanche',
    description: 'Send extra money to the highest interest loan',
    icon: 'chart-line-variant',
  },
  {
    value: 'snowball',
    label: 'Snowball',
    description: 'Send extra money to the smallest outstanding loan',
    icon: 'arrow-collapse-down',
  },
];

type ForecastPicker = 'loans' | 'strategy' | null;

export default function LoanForecast() {
  const { loanIds } = useLocalSearchParams<{ loanIds?: string | string[] }>();
  const theme = useTheme();
  const { state, selectors } = useLedger();
  const loans = useMemo(() => activeLoanAccounts(state), [state]);
  const queryLoanIds = firstParamValue(loanIds)?.split(',').filter(Boolean) ?? [];
  const [selectedLoanIds, setSelectedLoanIds] = useState<string[]>(queryLoanIds);
  const [picker, setPicker] = useState<ForecastPicker>(null);
  const [extraText, setExtraText] = useState('0');
  const [strategy, setStrategy] = useState<LoanPayoffStrategy>('equal');
  const viewCurrency = selectors.displayCurrency(state);
  const baseCurrency = state.preferences.baseCurrency;
  const selectedIds = selectedLoanIds.length ? selectedLoanIds : loans.map((loan) => loan.id);
  const extraMinor = toMinor(Math.max(0, parseAmount(extraText)), baseCurrency);
  const projection = useMemo(
    () =>
      buildLoanPayoffProjection(state, {
        loanIds: selectedIds,
        extraMonthlyPaymentMinor: extraMinor,
        strategy,
      }),
    [extraMinor, selectedIds, state, strategy],
  );
  const selectedLabel =
    selectedIds.length === loans.length ? 'All loans' : `${selectedIds.length} selected`;
  const displayedOutstanding = selectors.convertMoneyForDisplay(
    state,
    projection.outstanding,
    viewCurrency,
  );
  const displayedMonthly = selectors.convertMoneyForDisplay(
    state,
    projection.monthlyPayment,
    viewCurrency,
  );
  const displayedExtra = selectors.convertMoneyForDisplay(
    state,
    projection.extraMonthlyPayment,
    viewCurrency,
  );
  const displayedSaved = selectors.convertMoneyForDisplay(
    state,
    projection.interestSaved,
    viewCurrency,
  );

  useEffect(() => {
    if (queryLoanIds.length) return;
    if (selectedLoanIds.length) return;
    setSelectedLoanIds(loans.map((loan) => loan.id));
  }, [loans, queryLoanIds.length, selectedLoanIds.length]);

  return (
    <>
      <AppScreen
        title="Loan forecast"
        subtitle="Try extra payments and see when selected loans close."
        contentStyle={styles.content}
      >
        <View style={styles.metricGrid}>
          <MetricTile
            label="Outstanding"
            value={formatMoney(displayedOutstanding, state.preferences.locale)}
            icon="scale-balance"
            tone={displayedOutstanding.amountMinor ? 'warning' : 'default'}
            compact
          />
          <MetricTile
            label="Principal EMI"
            value={formatMoney(displayedMonthly, state.preferences.locale)}
            icon="bank-transfer-out"
            tone={displayedMonthly.amountMinor ? 'warning' : 'default'}
            compact
          />
          <MetricTile
            label="Extra"
            value={formatMoney(displayedExtra, state.preferences.locale)}
            icon="plus-circle-outline"
            tone={displayedExtra.amountMinor ? 'positive' : 'default'}
            compact
          />
          <MetricTile
            label="Interest saved"
            value={formatMoney(displayedSaved, state.preferences.locale)}
            icon="bank-minus"
            tone={displayedSaved.amountMinor ? 'positive' : 'default'}
            compact
          />
        </View>

        <SectionCard title="Forecast setup" compact variant="elevated">
          <TouchableRipple
            borderless
            style={[styles.selector, { borderColor: theme.colors.outlineVariant }]}
            onPress={() => setPicker('loans')}
          >
            <View style={styles.selectorInner}>
              <MaterialCommunityIcons name="bank-outline" size={22} color={theme.colors.primary} />
              <View style={styles.fill}>
                <Text variant="labelLarge" style={{ color: theme.colors.onSurfaceVariant }}>
                  Loans
                </Text>
                <Text variant="titleMedium" numberOfLines={1}>
                  {selectedLabel}
                </Text>
              </View>
              <MaterialCommunityIcons
                name="chevron-right"
                size={22}
                color={theme.colors.onSurfaceVariant}
              />
            </View>
          </TouchableRipple>
          <TouchableRipple
            borderless
            style={[styles.selector, { borderColor: theme.colors.outlineVariant }]}
            onPress={() => setPicker('strategy')}
          >
            <View style={styles.selectorInner}>
              <MaterialCommunityIcons
                name="chart-line-variant"
                size={22}
                color={theme.colors.primary}
              />
              <View style={styles.fill}>
                <Text variant="labelLarge" style={{ color: theme.colors.onSurfaceVariant }}>
                  Payoff strategy
                </Text>
                <Text variant="titleMedium" numberOfLines={1}>
                  {strategyLabel(strategy)}
                </Text>
              </View>
              <MaterialCommunityIcons
                name="chevron-right"
                size={22}
                color={theme.colors.onSurfaceVariant}
              />
            </View>
          </TouchableRipple>
          <ExtraPaymentControl
            currency={baseCurrency}
            valueText={extraText}
            monthlyMinor={projection.monthlyPayment.amountMinor}
            onChangeText={setExtraText}
          />
        </SectionCard>

        <SectionCard title="Close dates" compact>
          <InfoRow
            icon="calendar-check-outline"
            label="Without extra"
            value={closeSummary(
              projection.normalMonthsToClose,
              projection.normalClosesOn,
              state.preferences.locale,
            )}
          />
          <InfoRow
            icon="calendar-star"
            label="With extra"
            value={closeSummary(
              projection.acceleratedMonthsToClose,
              projection.acceleratedClosesOn,
              state.preferences.locale,
            )}
            tone={projection.monthsSaved ? 'positive' : 'default'}
          />
          <InfoRow
            icon="timer-sand"
            label="Time saved"
            value={projection.monthsSaved ? monthsLabel(projection.monthsSaved) : 'No change'}
            tone={projection.monthsSaved ? 'positive' : 'default'}
          />
          <InfoRow
            icon="bank-minus"
            label="Interest saved"
            value={formatMoney(displayedSaved, state.preferences.locale)}
            tone={displayedSaved.amountMinor ? 'positive' : 'default'}
          />
        </SectionCard>

        <SectionCard title="Selected loans" compact>
          {projection.loans.length === 0 ? (
            <EmptyState
              icon="bank-plus"
              title="No loans selected"
              body="Select one or more active loans to forecast payoff."
              actionLabel="Select loans"
              onAction={() => setPicker('loans')}
            />
          ) : (
            projection.loans.map((plan, index) => (
              <View key={plan.account.id}>
                <ForecastLoanRow plan={plan} />
                {index < projection.loans.length - 1 ? <Divider /> : null}
              </View>
            ))
          )}
        </SectionCard>
      </AppScreen>

      <LoanMultiSelectOverlay
        visible={picker === 'loans'}
        loans={loans}
        selectedLoanIds={selectedIds}
        onApply={(nextIds) => {
          setSelectedLoanIds(nextIds);
          setPicker(null);
        }}
        onDismiss={() => setPicker(null)}
      />
      <OptionListOverlay
        visible={picker === 'strategy'}
        title="Payoff strategy"
        options={STRATEGY_OPTIONS}
        selectedValue={strategy}
        searchable={false}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          setStrategy(option.value);
          setPicker(null);
        }}
      />
    </>
  );
}

function ExtraPaymentControl({
  currency,
  valueText,
  monthlyMinor,
  onChangeText,
}: {
  currency: string;
  valueText: string;
  monthlyMinor: number;
  onChangeText: (value: string) => void;
}) {
  const theme = useTheme();
  const [trackWidth, setTrackWidth] = useState(1);
  const valueMinor = toMinor(Math.max(0, parseAmount(valueText)), currency);
  const maxMinor = Math.max(monthlyMinor, valueMinor, toMinor(50000, currency));
  const progress = maxMinor > 0 ? Math.min(1, valueMinor / maxMinor) : 0;
  const setFromPercent = (percent: number) => {
    const nextMinor = Math.round(maxMinor * Math.max(0, Math.min(1, percent)));
    onChangeText(String(fromMinor(nextMinor, currency)));
  };

  return (
    <View style={styles.extraControl}>
      <PremiumTextInput
        label={`Extra per month (${currency})`}
        value={valueText}
        keyboardType="numeric"
        onChangeText={onChangeText}
      />
      <Pressable
        accessibilityRole="adjustable"
        accessibilityLabel="Extra monthly payment slider"
        style={[styles.sliderTrack, { backgroundColor: theme.colors.surfaceVariant }]}
        onLayout={(event) => setTrackWidth(Math.max(1, event.nativeEvent.layout.width))}
        onPress={(event) => {
          const locationX = event.nativeEvent.locationX;
          setFromPercent(locationX / trackWidth);
        }}
      >
        <View
          style={[
            styles.sliderFill,
            { width: `${Math.round(progress * 100)}%`, backgroundColor: theme.colors.primary },
          ]}
        />
      </Pressable>
      <View style={styles.actionRow}>
        <Button
          compact
          mode="outlined"
          icon="minus"
          onPress={() =>
            onChangeText(
              String(fromMinor(Math.max(0, valueMinor - toMinor(1000, currency)), currency)),
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
            onChangeText(String(fromMinor(valueMinor + toMinor(1000, currency), currency)))
          }
        >
          1K
        </Button>
        <Button
          compact
          mode="outlined"
          icon="plus"
          onPress={() =>
            onChangeText(String(fromMinor(valueMinor + toMinor(10000, currency), currency)))
          }
        >
          10K
        </Button>
        <Button compact mode="text" onPress={() => onChangeText('0')}>
          Reset
        </Button>
      </View>
    </View>
  );
}

function ForecastLoanRow({ plan }: { plan: LoanPayoffLoanPlan }) {
  const { state, selectors } = useLedger();
  const viewCurrency = selectors.displayCurrency(state);
  const visual = resolveAccountIconVisual(plan.account);
  const outstanding = selectors.convertMoneyForDisplay(state, plan.outstanding, viewCurrency);
  const extra = selectors.convertMoneyForDisplay(state, plan.extraMonthlyPayment, viewCurrency);
  const saved = selectors.convertMoneyForDisplay(state, plan.interestSaved, viewCurrency);

  return (
    <TouchableRipple
      borderless
      style={styles.loanRow}
      onPress={() => router.push(`/loans/${plan.account.id}` as never)}
    >
      <View style={styles.loanRowInner}>
        <View style={styles.rowHeader}>
          <View style={styles.rowTitle}>
            <View style={[styles.rowIcon, { backgroundColor: visual.backgroundColor }]}>
              <MaterialCommunityIcons name={visual.icon} size={18} color={visual.iconColor} />
            </View>
            <View style={styles.fill}>
              <Text variant="titleSmall" numberOfLines={1} style={styles.strongText}>
                {plan.account.name}
              </Text>
              <Text variant="bodySmall" numberOfLines={1}>
                {accountTypeLabel(plan.account.type)} · {plan.account.currency}
              </Text>
            </View>
          </View>
          <Text variant="titleSmall" numberOfLines={1} style={styles.moneyText}>
            {formatMoney(outstanding, state.preferences.locale)}
          </Text>
        </View>
        <InlineMeta
          numberOfLines={2}
          items={[
            `Normal ${monthsLabel(plan.normalMonthsToClose)}`,
            `Extra ${monthsLabel(plan.acceleratedMonthsToClose)}`,
            `${formatMoney(extra, state.preferences.locale)} extra`,
            `Save ${formatMoney(saved, state.preferences.locale)}`,
          ]}
        />
      </View>
    </TouchableRipple>
  );
}

function LoanMultiSelectOverlay({
  visible,
  loans,
  selectedLoanIds,
  onApply,
  onDismiss,
}: {
  visible: boolean;
  loans: Account[];
  selectedLoanIds: string[];
  onApply: (loanIds: string[]) => void;
  onDismiss: () => void;
}) {
  const theme = useTheme();
  const [draftIds, setDraftIds] = useState<string[]>(selectedLoanIds);

  useBackLayer(visible, onDismiss);

  useEffect(() => {
    if (visible) setDraftIds(selectedLoanIds);
  }, [selectedLoanIds, visible]);

  if (!visible) return null;

  const toggleLoan = (loanId: string) => {
    setDraftIds((current) =>
      current.includes(loanId) ? current.filter((id) => id !== loanId) : [...current, loanId],
    );
  };

  return (
    <Portal>
      <Surface style={[styles.overlay, { backgroundColor: theme.colors.background }]} elevation={0}>
        <SafeAreaView style={styles.safeArea} edges={['top', 'left', 'right']}>
          <Appbar.Header elevated={false} style={{ backgroundColor: theme.colors.background }}>
            <Appbar.BackAction onPress={onDismiss} />
            <Appbar.Content title="Select loans" titleStyle={styles.appbarTitle} />
            <Appbar.Action icon="check" onPress={() => onApply(draftIds)} />
          </Appbar.Header>
          <View style={styles.overlayContent}>
            <View style={styles.actionRow}>
              <Button
                mode="contained-tonal"
                icon="check-all"
                onPress={() => setDraftIds(loans.map((loan) => loan.id))}
              >
                All
              </Button>
              <Button mode="outlined" icon="close" onPress={() => setDraftIds([])}>
                None
              </Button>
            </View>
            <ScrollView
              contentContainerStyle={styles.optionList}
              showsVerticalScrollIndicator={false}
            >
              {loans.length === 0 ? (
                <EmptyState icon="bank-plus" title="No loans" body="Add a loan account first." />
              ) : (
                loans.map((loan) => {
                  const visual = resolveAccountIconVisual(loan);
                  return (
                    <PremiumRow
                      key={loan.id}
                      icon={visual.icon}
                      iconBackgroundColor={visual.backgroundColor}
                      iconColor={visual.iconColor}
                      title={loan.name}
                      titleNumberOfLines={2}
                      subtitle={`${accountTypeLabel(loan.type)} · ${loan.currency}`}
                      selected={draftIds.includes(loan.id)}
                      onPress={() => toggleLoan(loan.id)}
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

function strategyLabel(strategy: LoanPayoffStrategy): string {
  return STRATEGY_OPTIONS.find((option) => option.value === strategy)?.label ?? strategy;
}

function closeSummary(
  _months: number | undefined,
  closesOn: string | undefined,
  locale: string,
): string {
  if (!closesOn) return 'Needs EMI setup';
  return loanScheduleCloseLabel(closesOn, locale);
}

function parseAmount(value: string): number {
  return Number(value.replace(/,/g, '').trim()) || 0;
}

function firstParamValue(value: string | string[] | undefined): string | undefined {
  return Array.isArray(value) ? value[0] : value;
}

const styles = StyleSheet.create({
  content: { gap: tokens.space.md, paddingTop: tokens.space.sm },
  fill: { flex: 1, minWidth: 0 },
  metricGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: tokens.space.sm },
  selector: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: tokens.radius.md,
    overflow: 'hidden',
  },
  selectorInner: {
    minHeight: 64,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.md,
    paddingHorizontal: tokens.space.md,
  },
  extraControl: { gap: tokens.space.sm },
  sliderTrack: { height: 12, borderRadius: 6, overflow: 'hidden' },
  sliderFill: { height: '100%', borderRadius: 6 },
  actionRow: { flexDirection: 'row', flexWrap: 'wrap', gap: tokens.space.sm },
  loanRow: { borderRadius: tokens.radius.md, overflow: 'hidden' },
  loanRowInner: { gap: tokens.space.sm, paddingVertical: tokens.space.md },
  rowHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: tokens.space.md,
  },
  rowTitle: {
    flex: 1,
    minWidth: 0,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.sm,
  },
  rowIcon: {
    width: 34,
    height: 34,
    borderRadius: tokens.radius.pill,
    alignItems: 'center',
    justifyContent: 'center',
  },
  strongText: { fontWeight: '800' },
  moneyText: { fontWeight: '800', textAlign: 'right', maxWidth: '42%' },
  overlay: { ...StyleSheet.absoluteFill, zIndex: 30 },
  safeArea: { flex: 1 },
  appbarTitle: { fontWeight: '700' },
  overlayContent: { flex: 1, gap: tokens.space.md, padding: tokens.space.lg, paddingTop: 0 },
  optionList: { gap: tokens.space.sm, paddingBottom: tokens.space.lg },
});
