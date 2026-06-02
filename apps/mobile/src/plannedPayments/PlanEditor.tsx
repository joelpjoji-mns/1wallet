import { isLoanAccountType } from '@1wallet/ledger/loans';
import type { LedgerState } from '@1wallet/ledger/store/types';
import { useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { Button, Text, TouchableRipple, useTheme } from 'react-native-paper';
import { accountTypeLabel, resolveAccountIconVisual } from '../accountOptions';
import { resolveCategoryIcon, resolveCategoryIconVisual } from '../categoryIcons';
import { PremiumTextInput, SectionCard } from '../components/AppKit';
import { DateOnlyPickerField } from '../components/DateOnlyPickerField';
import {
    OptionListOverlay,
    OptionSelectorRow,
    type OptionListItem,
} from '../components/OptionListOverlay';
import { CategoryPickerOverlay } from '../components/record/RecordPickers';
import {
    categoryApplies,
    categoryDisplayName,
    plannedKindMeta,
    requiresCounterAccount,
    transactionTypeForPlannedKind,
} from './display';
import {
    accountOption,
    activeAccounts,
    compatibleCategoryId,
    dayOfMonthText,
    dayOfWeekFromDate,
    END_MODE_OPTIONS,
    endModeLabel,
    endModeOptionFor,
    endModePatch,
    FREQUENCY_OPTIONS,
    normalizeDraftDaysOfWeek,
    PLANNED_KIND_OPTIONS,
    POST_MODE_OPTIONS,
    type PlannedPaymentDraft,
    type PlanPickerMode,
} from './planDraft';

const WEEKDAY_OPTIONS = [
  { value: 1, label: 'M', accessibilityLabel: 'Monday' },
  { value: 2, label: 'T', accessibilityLabel: 'Tuesday' },
  { value: 3, label: 'W', accessibilityLabel: 'Wednesday' },
  { value: 4, label: 'T', accessibilityLabel: 'Thursday' },
  { value: 5, label: 'F', accessibilityLabel: 'Friday' },
  { value: 6, label: 'S', accessibilityLabel: 'Saturday' },
  { value: 0, label: 'S', accessibilityLabel: 'Sunday' },
] as const;

export function PlannedPaymentEditor({
  draft,
  state,
  onChange,
  onCancel,
  onSave,
  saveLabel = 'Save plan',
}: {
  draft: PlannedPaymentDraft;
  state: LedgerState;
  onChange: (draft: PlannedPaymentDraft) => void;
  onCancel: () => void;
  onSave: () => void;
  saveLabel?: string;
}) {
  const [picker, setPicker] = useState<PlanPickerMode>(null);
  const accounts = activeAccounts(state);
  const selectedAccount = accounts.find((account) => account.id === draft.accountId);
  const selectedAccountIsLoan = selectedAccount ? isLoanAccountType(selectedAccount.type) : false;
  const isLoanPlan = draft.transactionType === 'loan_repayment';
  const counterAccounts = accounts
    .filter((account) => account.id !== draft.accountId)
    .filter((account) => {
      if (!isLoanPlan) return true;
      return selectedAccountIsLoan
        ? !isLoanAccountType(account.type)
        : isLoanAccountType(account.type);
    });
  const selectedCounterAccount = counterAccounts.find(
    (account) => account.id === draft.counterAccountId,
  );
  const selectedAccountVisual = selectedAccount
    ? resolveAccountIconVisual(selectedAccount)
    : undefined;
  const selectedCounterAccountVisual = selectedCounterAccount
    ? resolveAccountIconVisual(selectedCounterAccount)
    : undefined;
  const selectedCategory = state.categories.find((category) => category.id === draft.categoryId);
  const selectedCategoryVisual = selectedCategory
    ? resolveCategoryIconVisual(selectedCategory, state.categories)
    : undefined;
  const kindMeta = plannedKindMeta(draft.kind);
  const needsCounterAccount = requiresCounterAccount(draft.kind);
  const endModeMeta = endModeOptionFor(draft.endMode);

  const update = (patch: Partial<PlannedPaymentDraft>) => onChange({ ...draft, ...patch });
  const updateStartsOn = (startsOn: string) => {
    const currentDays = normalizeDraftDaysOfWeek(draft.daysOfWeek);
    const currentStartDay = dayOfWeekFromDate(draft.startsOn);
    const shouldFollowStartDate =
      currentDays.length === 0 || (currentDays.length === 1 && currentDays[0] === currentStartDay);
    update({
      startsOn,
      dayOfMonthText: dayOfMonthText(startsOn, draft.dayOfMonthText),
      daysOfWeek:
        draft.frequency === 'weekly' && shouldFollowStartDate
          ? [dayOfWeekFromDate(startsOn)]
          : currentDays,
    });
  };
  const updateFrequency = (frequency: PlannedPaymentDraft['frequency']) =>
    update({
      frequency,
      dayOfMonthText:
        frequency === 'monthly' ? dayOfMonthText(draft.startsOn, draft.dayOfMonthText) : '',
      daysOfWeek:
        frequency === 'weekly'
          ? draft.frequency === 'weekly'
            ? normalizeDraftDaysOfWeek(draft.daysOfWeek, draft.startsOn)
            : [dayOfWeekFromDate(draft.startsOn)]
          : draft.daysOfWeek,
    });

  return (
    <SectionCard
      title={draft.id ? 'Edit plan' : 'New plan'}
      subtitle="Schedule repeat income, expenses, and transfers."
    >
      <PremiumTextInput
        mode="outlined"
        label="Plan name"
        value={draft.name}
        onChangeText={(name) => update({ name })}
      />
      <OptionSelectorRow
        label="Type"
        value={kindMeta.label}
        description={kindMeta.description}
        icon={kindMeta.icon}
        onPress={() => setPicker('kind')}
      />
      <OptionSelectorRow
        label={isLoanPlan ? (selectedAccountIsLoan ? 'Loan account' : 'Pay from') : 'Account'}
        value={selectedAccount?.name ?? 'Select account'}
        valueNumberOfLines={2}
        description={
          selectedAccount
            ? `${accountTypeLabel(selectedAccount.type)} · ${selectedAccount.currency}`
            : 'Where the record posts'
        }
        icon={selectedAccountVisual?.icon ?? 'wallet-outline'}
        iconBackgroundColor={selectedAccountVisual?.backgroundColor}
        iconColor={selectedAccountVisual?.iconColor}
        onPress={() => setPicker('account')}
      />
      {needsCounterAccount ? (
        <OptionSelectorRow
          label={
            isLoanPlan ? (selectedAccountIsLoan ? 'Receive into' : 'Loan account') : 'To account'
          }
          value={selectedCounterAccount?.name ?? 'Select destination'}
          valueNumberOfLines={2}
          description={isLoanPlan ? 'Linked to this EMI plan' : 'Required for transfer plans'}
          icon={selectedCounterAccountVisual?.icon ?? 'swap-horizontal'}
          iconBackgroundColor={selectedCounterAccountVisual?.backgroundColor}
          iconColor={selectedCounterAccountVisual?.iconColor}
          onPress={() => setPicker('counterAccount')}
        />
      ) : null}
      {categoryApplies(draft.kind) ? (
        <OptionSelectorRow
          label="Category"
          value={categoryDisplayName(state.categories, selectedCategory)}
          valueNumberOfLines={2}
          description="Same category picker used by records"
          icon={resolveCategoryIcon(selectedCategory, state.categories)}
          iconBackgroundColor={selectedCategoryVisual?.backgroundColor}
          iconColor={selectedCategoryVisual?.iconColor}
          onPress={() => setPicker('category')}
        />
      ) : null}
      <View style={styles.formRow}>
        <PremiumTextInput
          mode="outlined"
          label={`Amount${selectedAccount ? ` (${selectedAccount.currency})` : ''}`}
          value={draft.amountText}
          keyboardType="decimal-pad"
          style={styles.formField}
          onChangeText={(amountText) => update({ amountText })}
        />
        <DateOnlyPickerField
          label="Start date"
          value={draft.startsOn}
          style={styles.formField}
          onChange={updateStartsOn}
        />
      </View>
      <View style={styles.formRow}>
        <OptionSelectorRow
          compact
          label="Repeat"
          value={optionLabel(FREQUENCY_OPTIONS, draft.frequency)}
          icon="repeat"
          style={styles.formField}
          onPress={() => setPicker('frequency')}
        />
        <PremiumTextInput
          mode="outlined"
          label="Every"
          value={draft.intervalText}
          keyboardType="number-pad"
          style={styles.formField}
          onChangeText={(intervalText) => update({ intervalText })}
        />
      </View>
      {draft.frequency === 'weekly' ? (
        <WeekdaySelector
          selectedDays={draft.daysOfWeek}
          onChange={(daysOfWeek) => update({ daysOfWeek })}
        />
      ) : null}
      <View style={styles.formRow}>
        {draft.frequency === 'monthly' ? (
          <PremiumTextInput
            mode="outlined"
            label="Day of month"
            value={draft.dayOfMonthText}
            keyboardType="number-pad"
            style={styles.formField}
            onChangeText={(dayOfMonthText) => update({ dayOfMonthText })}
          />
        ) : null}
        <OptionSelectorRow
          compact
          label="Ends"
          value={endModeLabel(draft)}
          icon={endModeMeta.icon}
          style={draft.frequency === 'monthly' ? styles.formField : styles.fullWidthField}
          onPress={() => setPicker('endMode')}
        />
      </View>
      {draft.endMode === 'untilDate' ? (
        <DateOnlyPickerField
          label="Until date"
          value={draft.endsOn}
          onChange={(endsOn) => update({ endsOn })}
        />
      ) : null}
      {draft.endMode === 'events' ? (
        <PremiumTextInput
          mode="outlined"
          label="Number of events"
          value={draft.occurrencesText}
          keyboardType="number-pad"
          placeholder="12"
          onChangeText={(occurrencesText) => update({ occurrencesText })}
        />
      ) : null}
      <OptionSelectorRow
        label="Posting"
        value={optionLabel(POST_MODE_OPTIONS, draft.postMode)}
        description={
          draft.postMode === 'automatic'
            ? 'Due generated records can post automatically'
            : 'You approve forecast records manually'
        }
        icon={draft.postMode === 'automatic' ? 'calendar-check-outline' : 'account-check-outline'}
        onPress={() => setPicker('postMode')}
      />
      <PremiumTextInput
        mode="outlined"
        label="Payment method"
        value={draft.paymentMethod}
        placeholder="Autopay, UPI, standing order"
        onChangeText={(paymentMethod) => update({ paymentMethod })}
      />
      <PremiumTextInput
        mode="outlined"
        label="Notes"
        value={draft.notes}
        multiline
        numberOfLines={3}
        style={styles.notesField}
        onChangeText={(notes) => update({ notes })}
      />
      <View style={styles.actionRow}>
        <Button
          mode={draft.enabled ? 'contained-tonal' : 'outlined'}
          icon={draft.enabled ? 'pause' : 'play'}
          onPress={() => update({ enabled: !draft.enabled })}
        >
          {draft.enabled ? 'Starts active' : 'Starts paused'}
        </Button>
        <Button mode="contained" icon="content-save-outline" onPress={onSave}>
          {saveLabel}
        </Button>
        <Button mode="text" onPress={onCancel}>
          Cancel
        </Button>
      </View>

      <OptionListOverlay
        visible={picker === 'kind'}
        title="Plan type"
        options={PLANNED_KIND_OPTIONS}
        selectedValue={draft.kind}
        searchable={false}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          update({
            kind: option.value,
            transactionType: transactionTypeForPlannedKind(option.value),
            counterAccountId: requiresCounterAccount(option.value)
              ? draft.counterAccountId
              : undefined,
            categoryId: compatibleCategoryId(state, draft.categoryId, option.value),
          });
          setPicker(null);
        }}
      />
      <OptionListOverlay
        visible={picker === 'account'}
        title="Account"
        options={accounts.map(accountOption)}
        selectedValue={draft.accountId}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          const account = accounts.find((item) => item.id === option.value);
          update({
            accountId: option.value,
            counterAccountId:
              draft.counterAccountId === option.value ? undefined : draft.counterAccountId,
            amountText: draft.amountText || (account ? '0' : draft.amountText),
          });
          setPicker(null);
        }}
      />
      <OptionListOverlay
        visible={picker === 'counterAccount'}
        title={isLoanPlan ? 'Loan account' : 'Destination account'}
        options={counterAccounts.map(accountOption)}
        selectedValue={draft.counterAccountId}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          update({ counterAccountId: option.value });
          setPicker(null);
        }}
      />
      <CategoryPickerOverlay
        visible={picker === 'category'}
        categories={state.categories}
        selectedId={draft.categoryId}
        onDismiss={() => setPicker(null)}
        onClear={() => {
          update({ categoryId: undefined });
          setPicker(null);
        }}
        onSelect={(category) => {
          update({ categoryId: category.id });
          setPicker(null);
        }}
      />
      <OptionListOverlay
        visible={picker === 'frequency'}
        title="Repeat"
        options={FREQUENCY_OPTIONS}
        selectedValue={draft.frequency}
        searchable={false}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          updateFrequency(option.value);
          setPicker(null);
        }}
      />
      <OptionListOverlay
        visible={picker === 'endMode'}
        title="Ends"
        options={END_MODE_OPTIONS}
        selectedValue={draft.endMode}
        searchable={false}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          update(endModePatch(draft, option.value));
          setPicker(null);
        }}
      />
      <OptionListOverlay
        visible={picker === 'postMode'}
        title="Posting mode"
        options={POST_MODE_OPTIONS}
        selectedValue={draft.postMode}
        searchable={false}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          update({ postMode: option.value });
          setPicker(null);
        }}
      />
    </SectionCard>
  );
}

export function optionLabel<TValue extends string>(
  options: readonly OptionListItem<TValue>[],
  value: TValue,
): string {
  return options.find((option) => option.value === value)?.label ?? value;
}

function WeekdaySelector({
  selectedDays,
  onChange,
}: {
  selectedDays: number[];
  onChange: (days: number[]) => void;
}) {
  const theme = useTheme();
  const selected = new Set(normalizeDraftDaysOfWeek(selectedDays));

  const toggleDay = (day: number) => {
    const next = new Set(selected);
    if (next.has(day)) next.delete(day);
    else next.add(day);
    const normalized = normalizeDraftDaysOfWeek(Array.from(next));
    if (normalized.length > 0) onChange(normalized);
  };

  return (
    <View
      style={[
        styles.weekdayGroup,
        {
          backgroundColor: theme.colors.elevation.level1,
          borderColor: theme.colors.outlineVariant,
        },
      ]}
    >
      <Text variant="labelLarge" style={{ color: theme.colors.onSurface }}>
        Weekdays
      </Text>
      <View style={styles.weekdayRow}>
        {WEEKDAY_OPTIONS.map((option) => {
          const isSelected = selected.has(option.value);
          return (
            <TouchableRipple
              key={option.accessibilityLabel}
              accessibilityRole="checkbox"
              accessibilityState={{ checked: isSelected }}
              accessibilityLabel={option.accessibilityLabel}
              style={[
                styles.weekdayButton,
                {
                  backgroundColor: isSelected
                    ? theme.colors.primaryContainer
                    : theme.colors.surfaceVariant,
                  borderColor: isSelected ? theme.colors.primary : theme.colors.outlineVariant,
                },
              ]}
              borderless
              onPress={() => toggleDay(option.value)}
            >
              <Text
                variant="labelLarge"
                style={{
                  color: isSelected ? theme.colors.onPrimaryContainer : theme.colors.onSurface,
                  textAlign: 'center',
                }}
              >
                {option.label}
              </Text>
            </TouchableRipple>
          );
        })}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  actionRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
  },
  formRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
  },
  formField: {
    flex: 1,
    minWidth: 140,
  },
  fullWidthField: {
    flex: 1,
    minWidth: '100%',
  },
  notesField: {
    minHeight: 96,
    textAlignVertical: 'top',
  },
  weekdayButton: {
    alignItems: 'center',
    borderRadius: 18,
    borderWidth: 1,
    height: 36,
    justifyContent: 'center',
    width: 36,
  },
  weekdayGroup: {
    borderRadius: 16,
    borderWidth: 1,
    gap: 10,
    padding: 12,
  },
  weekdayRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
  },
});
