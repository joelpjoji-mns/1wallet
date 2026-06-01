import { createFutureGenerationRule } from '@1wallet/ledger/rules/futureGeneration';
import { useLedger } from '@1wallet/state';
import { router } from 'expo-router';
import { useState } from 'react';
import { Snackbar } from 'react-native-paper';
import { AppScreen } from '../../src/components/AppKit';
import { PlannedPaymentEditor } from '../../src/plannedPayments/PlanEditor';
import {
  createDefaultPlanDraft,
  futureRuleInputFromDraft,
  type PlannedPaymentDraft,
} from '../../src/plannedPayments/planDraft';

export default function NewPlannedPayment() {
  const { state, mutate } = useLedger();
  const [draft, setDraft] = useState<PlannedPaymentDraft>(() => createDefaultPlanDraft(state));
  const [snackbar, setSnackbar] = useState<string | null>(null);

  const save = async () => {
    const result = futureRuleInputFromDraft(state, draft);
    if (!result.ok) {
      setSnackbar(result.message);
      return;
    }

    let savedId: string | undefined;
    await mutate((draftState) => {
      const rule = createFutureGenerationRule(draftState, result.input);
      savedId = rule.id;
    });

    if (savedId) router.replace(`/recurring/${savedId}` as never);
  };

  return (
    <>
      <AppScreen
        title="New plan"
        subtitle="Create a recurring forecast."
        contentStyle={{ paddingTop: 8 }}
      >
        <PlannedPaymentEditor
          draft={draft}
          state={state}
          onChange={setDraft}
          onCancel={() => router.back()}
          onSave={() => void save()}
          saveLabel="Create plan"
        />
      </AppScreen>
      <Snackbar visible={Boolean(snackbar)} onDismiss={() => setSnackbar(null)} duration={2400}>
        {snackbar}
      </Snackbar>
    </>
  );
}
