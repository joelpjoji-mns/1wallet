import { syncLoanDetailsFromRule } from '@1wallet/ledger/loans';
import { updateFutureGenerationRule } from '@1wallet/ledger/rules/futureGeneration';
import { useLedger } from '@1wallet/state';
import { router, useLocalSearchParams } from 'expo-router';
import { useMemo, useState } from 'react';
import { Snackbar } from 'react-native-paper';
import { AppScreen, EmptyState } from '../../../src/components/AppKit';
import { PlannedPaymentEditor } from '../../../src/plannedPayments/PlanEditor';
import {
    draftFromRule,
    futureRuleInputFromDraft,
    type PlannedPaymentDraft,
} from '../../../src/plannedPayments/planDraft';
import { removeUnpostedFutureScheduledRecordsForRule } from '../../../src/plannedPayments/ruleActions';

export default function EditPlannedPayment() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { state, mutate } = useLedger();
  const rule = state.preferences.futureGenerationRules?.find((item) => item.id === id);
  const initialDraft = useMemo(() => (rule ? draftFromRule(rule) : null), [rule]);
  const [draft, setDraft] = useState<PlannedPaymentDraft | null>(initialDraft);
  const [snackbar, setSnackbar] = useState<string | null>(null);

  const activeDraft = draft ?? initialDraft;

  const save = async () => {
    if (!activeDraft || !rule) return;
    const result = futureRuleInputFromDraft(state, activeDraft);
    if (!result.ok) {
      setSnackbar(result.message);
      return;
    }

    await mutate((draftState) => {
      const updatedRule = updateFutureGenerationRule(draftState, rule.id, result.input);
      if (updatedRule) syncLoanDetailsFromRule(draftState, updatedRule);
      removeUnpostedFutureScheduledRecordsForRule(draftState, rule.id);
    });
    router.replace(`/recurring/${rule.id}` as never);
  };

  if (!rule || !activeDraft) {
    return (
      <AppScreen title="Edit plan" subtitle="This plan is no longer available.">
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

  return (
    <>
      <AppScreen title="Edit plan" subtitle={rule.name} contentStyle={{ paddingTop: 8 }}>
        <PlannedPaymentEditor
          draft={activeDraft}
          state={state}
          onChange={setDraft}
          onCancel={() => router.back()}
          onSave={() => void save()}
          saveLabel="Save changes"
        />
      </AppScreen>
      <Snackbar visible={Boolean(snackbar)} onDismiss={() => setSnackbar(null)} duration={2400}>
        {snackbar}
      </Snackbar>
    </>
  );
}
