import type {
    LoanInterestMethod,
    LoanInterestRatePeriod,
    LoanKind,
    RecurrenceFrequency,
} from '@1wallet/domain/types';
import {
    buildLoanForecast,
    buildLoanPlannedPaymentInput,
    completedLoanInstallmentCount,
    deriveLoanOutstandingPrincipal,
    dueDateForInstallment,
    findLinkedLoanRule,
    legacyLoanPlanRefPrefix,
    loanOpeningBalanceMinorForOutstanding,
} from '@1wallet/ledger/loans';
import {
    createFutureGenerationRule,
    updateFutureGenerationRule,
} from '@1wallet/ledger/rules/futureGeneration';
import { updateAccount } from '@1wallet/ledger/services';
import { indexedAccountBalance } from '@1wallet/ledger/services/indexes';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo, useRef, useState } from 'react';
import { StyleSheet, Switch, View } from 'react-native';
import { Button, Snackbar, Text, useTheme } from 'react-native-paper';
import { accountTypeLabel, resolveAccountIconVisual } from '../../../src/accountOptions';
import {
    AppScreen,
    EmptyState,
    InfoRow,
    PremiumTextInput,
    SectionCard,
} from '../../../src/components/AppKit';
import { DateOnlyPickerField } from '../../../src/components/DateOnlyPickerField';
import { OptionListOverlay, OptionSelectorRow } from '../../../src/components/OptionListOverlay';
import {
    FREQUENCY_OPTIONS,
    INTEREST_METHOD_OPTIONS,
    LOAN_KIND_OPTIONS,
    RATE_PERIOD_OPTIONS,
    buildDraftLoanDetails,
    defaultLoanKind,
    formatInputAmount,
    isValidIsoDate,
    loanScheduleCloseLabel,
    optionLabel,
    repaymentSourceAccounts,
    todayIso,
} from '../../../src/loans/loanUtils';
import { removeUnpostedFutureScheduledRecordsForRule } from '../../../src/plannedPayments/ruleActions';

type LoanEditPicker = 'source' | 'kind' | 'frequency' | 'ratePeriod' | 'interestMethod' | null;

export default function LoanEdit() {
  const theme = useTheme();
  const { id } = useLocalSearchParams<{ id: string }>();
  const { state, indexes, mutate } = useLedger();
  const loan = state.accounts.find((account) => account.id === id);
  const hydratedLoanIdRef = useRef<string | null>(null);
  const [picker, setPicker] = useState<LoanEditPicker>(null);
  const [snackbar, setSnackbar] = useState<string | null>(null);
  const [loanKind, setLoanKind] = useState<LoanKind>('personal');
  const [sourceAccountId, setSourceAccountId] = useState('');
  const [principal, setPrincipal] = useState('0');
  const [amountLeft, setAmountLeft] = useState('0');
  const [payment, setPayment] = useState('0');
  const [rate, setRate] = useState('0');
  const [ratePeriod, setRatePeriod] = useState<LoanInterestRatePeriod>('annual');
  const [interestMethod, setInterestMethod] = useState<LoanInterestMethod>('reducing_balance');
  const [startsOn, setStartsOn] = useState(todayIso());
  const [frequency, setFrequency] = useState<RecurrenceFrequency>('monthly');
  const [interval, setInterval] = useState('1');
  const [dayOfMonth, setDayOfMonth] = useState(String(new Date().getDate()));
  const [installments, setInstallments] = useState('12');
  const [paidInstallments, setPaidInstallments] = useState('0');
  const [endsOn, setEndsOn] = useState('');
  const [autoCreate, setAutoCreate] = useState(true);

  const sourceAccounts = useMemo(
    () => repaymentSourceAccounts(state.accounts, loan),
    [loan, state.accounts],
  );
  const selectedSource = sourceAccounts.find((account) => account.id === sourceAccountId);
  const linkedRule = loan ? findLinkedLoanRule(state, loan.id) : undefined;

  useEffect(() => {
    if (!loan) {
      hydratedLoanIdRef.current = null;
      return;
    }
    if (hydratedLoanIdRef.current === loan.id) return;
    hydratedLoanIdRef.current = loan.id;
    const details = loan.loanDetails;
    const balance = indexedAccountBalance(indexes, loan);
    const outstandingMinor = Math.abs(balance.amountMinor || details?.principal?.amountMinor || 0);
    setLoanKind(details?.loanKind ?? defaultLoanKind(loan));
    setSourceAccountId(
      details?.repaymentSourceAccountId &&
        sourceAccounts.some((account) => account.id === details.repaymentSourceAccountId)
        ? details.repaymentSourceAccountId
        : (sourceAccounts[0]?.id ?? ''),
    );
    setPrincipal(
      formatInputAmount(
        details?.principal ?? { amountMinor: outstandingMinor, currency: loan.currency },
      ),
    );
    const paidCount = details ? completedLoanInstallmentCount(details, new Date()) : 0;
    const calculatedOutstanding = details
      ? deriveLoanOutstandingPrincipal(details, loan.currency, { paidInstallments: paidCount })
      : { amountMinor: outstandingMinor, currency: loan.currency };
    setAmountLeft(formatInputAmount(calculatedOutstanding));
    setPaidInstallments(String(paidCount));
    setPayment(
      formatInputAmount(details?.repaymentAmount ?? { amountMinor: 0, currency: loan.currency }),
    );
    setRate(String(details?.interestRatePercent ?? 0));
    setRatePeriod(details?.interestRatePeriod ?? 'annual');
    setInterestMethod(details?.interestMethod ?? 'reducing_balance');
    setStartsOn(details?.repaymentStartsOn ?? details?.trackingStartsOn ?? todayIso());
    setFrequency(details?.repaymentFrequency ?? 'monthly');
    setInterval(String(details?.repaymentInterval ?? 1));
    setDayOfMonth(String(details?.repaymentDayOfMonth ?? new Date().getDate()));
    setInstallments(String(details?.repaymentCount ?? 12));
    setEndsOn(details?.repaymentEndsOn ?? '');
    setAutoCreate(details?.autoCreateScheduledRecords ?? true);
  }, [indexes, loan, sourceAccounts]);

  const draftTrackingStartsOn = useMemo(
    () =>
      installmentDueOn({
        startsOn,
        frequency,
        interval,
        dayOfMonth,
        paidInstallments,
      }),
    [dayOfMonth, frequency, interval, paidInstallments, startsOn],
  );

  const draftDetails = useMemo(
    () =>
      loan
        ? buildDraftLoanDetails(loan, {
            loanKind,
            sourceAccountId,
            principal,
            payment,
            rate,
            ratePeriod,
            interestMethod,
            startsOn,
            frequency,
            interval,
            dayOfMonth,
            installments,
            paidInstallments,
            trackingStartsOn: draftTrackingStartsOn,
            endsOn,
            autoCreate,
          })
        : undefined,
    [
      autoCreate,
      dayOfMonth,
      endsOn,
      frequency,
      installments,
      interestMethod,
      interval,
      loan,
      loanKind,
      payment,
      paidInstallments,
      principal,
      rate,
      ratePeriod,
      sourceAccountId,
      startsOn,
      draftTrackingStartsOn,
    ],
  );
  const calculatedOutstanding = useMemo(
    () =>
      draftDetails && loan
        ? deriveLoanOutstandingPrincipal(draftDetails, loan.currency, {
            paidInstallments: parseWholeNumber(paidInstallments, 0),
          })
        : undefined,
    [draftDetails, loan, paidInstallments],
  );
  const totalInstallments = draftDetails?.repaymentCount;
  const paidInstallmentCount = parseWholeNumber(paidInstallments, 0);
  const remainingInstallments =
    totalInstallments !== undefined ? Math.max(0, totalInstallments - paidInstallmentCount) : 0;

  useEffect(() => {
    if (!calculatedOutstanding) return;
    setAmountLeft(formatInputAmount(calculatedOutstanding));
  }, [calculatedOutstanding]);

  const forecast = useMemo(
    () =>
      loan && draftDetails
        ? buildLoanForecast(state, loan, draftDetails, {
            amountMinor: calculatedOutstanding?.amountMinor ?? 0,
            currency: loan.currency,
          })
        : undefined,
    [calculatedOutstanding?.amountMinor, draftDetails, loan, state],
  );

  if (!loan) {
    return (
      <AppScreen title="Edit loan" subtitle="This loan is no longer available.">
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

  const loanVisual = resolveAccountIconVisual(loan);
  const selectedSourceVisual = selectedSource
    ? resolveAccountIconVisual(selectedSource)
    : undefined;

  const savePlan = async () => {
    if (!draftDetails || !forecast) {
      setSnackbar('Add a loan account first');
      return;
    }
    if (!selectedSource) {
      setSnackbar(`Choose a ${loan.currency} repayment account`);
      return;
    }
    if (!draftDetails.repaymentAmount?.amountMinor) {
      setSnackbar('Enter a repayment amount');
      return;
    }
    const amountLeftMinor = calculatedOutstanding?.amountMinor ?? 0;
    const principalMinor = Math.abs(draftDetails.principal?.amountMinor ?? 0);
    const paidCount = parseWholeNumber(paidInstallments, 0);
    const totalInstallments = draftDetails.repaymentCount ?? 0;
    if (!principalMinor) {
      setSnackbar('Enter the original principal');
      return;
    }
    if (amountLeftMinor > principalMinor) {
      setSnackbar('Amount left cannot exceed original principal');
      return;
    }
    if (paidCount > totalInstallments) {
      setSnackbar('Paid EMIs cannot exceed total installments');
      return;
    }
    if (!isValidIsoDate(draftDetails.repaymentStartsOn)) {
      setSnackbar('Enter a valid start date');
      return;
    }

    let linkedRuleId: string | undefined;
    await mutate((draft) => {
      const existingRule = findLinkedLoanRule(draft, loan.id);
      const input = buildLoanPlannedPaymentInput(
        loan,
        draftDetails,
        existingRule?.tags ?? linkedRule?.tags,
      );
      const prefix = legacyLoanPlanRefPrefix(loan.id);
      draft.transactions = draft.transactions.filter(
        (transaction) =>
          !(transaction.status === 'scheduled' && transaction.externalRef?.startsWith(prefix)),
      );

      if (input) {
        const rule = existingRule
          ? updateFutureGenerationRule(draft, existingRule.id, input)
          : createFutureGenerationRule(draft, input);
        linkedRuleId = rule?.id;
        if (linkedRuleId) removeUnpostedFutureScheduledRecordsForRule(draft, linkedRuleId);
      }

      const draftLoan = draft.accounts.find((account) => account.id === loan.id);
      const openingBalanceMinor = draftLoan
        ? loanOpeningBalanceMinorForOutstanding(draft, draftLoan, {
            amountMinor: amountLeftMinor,
            currency: loan.currency,
          })
        : undefined;

      updateAccount(draft, loan.id, {
        ...(openingBalanceMinor !== undefined ? { openingBalanceMinor } : {}),
        loanDetails: { ...draftDetails, linkedPlannedPaymentRuleId: linkedRuleId },
      });
    });
    setSnackbar(linkedRuleId ? 'Loan plan saved with linked EMI forecast' : 'Loan plan saved');
    router.replace(`/loans/${loan.id}` as never);
  };

  return (
    <>
      <AppScreen title="Edit loan" subtitle={loan.name} contentStyle={styles.content}>
        <SectionCard title="Loan config" subtitle="Repayment source, interest, and recurrence.">
          <OptionSelectorRow
            label="Loan account"
            value={loan.name}
            description={`${accountTypeLabel(loan.type)} · ${loan.currency}`}
            icon={loanVisual.icon}
            iconBackgroundColor={loanVisual.backgroundColor}
            iconColor={loanVisual.iconColor}
            valueNumberOfLines={2}
            disabled
            onPress={() => undefined}
          />
          <OptionSelectorRow
            label={loan.type === 'lent' ? 'Receive into' : 'Pay from'}
            value={selectedSource?.name ?? 'Choose account'}
            description={
              sourceAccounts.length
                ? `Any active ${loan.currency} account`
                : `Add an active ${loan.currency} repayment account`
            }
            icon={selectedSourceVisual?.icon ?? 'wallet-outline'}
            iconBackgroundColor={selectedSourceVisual?.backgroundColor}
            iconColor={selectedSourceVisual?.iconColor}
            valueNumberOfLines={2}
            onPress={() => setPicker('source')}
          />
          <View style={styles.twoColumn}>
            <OptionSelectorRow
              label="Loan type"
              value={optionLabel(LOAN_KIND_OPTIONS, loanKind)}
              icon="shape-outline"
              onPress={() => setPicker('kind')}
              style={styles.flexField}
            />
            <OptionSelectorRow
              label="Repeat"
              value={optionLabel(FREQUENCY_OPTIONS, frequency)}
              icon="repeat"
              onPress={() => setPicker('frequency')}
              style={styles.flexField}
            />
          </View>
          <View style={styles.twoColumn}>
            <MoneyField
              label="Original principal"
              value={principal}
              onChangeText={setPrincipal}
              currency={loan.currency}
            />
            <MoneyField
              label="Calculated amount left"
              value={amountLeft}
              currency={loan.currency}
              editable={false}
            />
          </View>
          <View style={styles.twoColumn}>
            <MoneyField
              label="Principal EMI"
              value={payment}
              onChangeText={setPayment}
              currency={loan.currency}
            />
          </View>
          <View style={styles.twoColumn}>
            <PremiumTextInput
              mode="outlined"
              label="Interest rate %"
              value={rate}
              onChangeText={setRate}
              keyboardType="numeric"
              style={styles.flexField}
            />
            <OptionSelectorRow
              label="Rate period"
              value={optionLabel(RATE_PERIOD_OPTIONS, ratePeriod)}
              icon="percent-outline"
              onPress={() => setPicker('ratePeriod')}
              style={styles.flexField}
            />
          </View>
          <OptionSelectorRow
            label="Interest model"
            value={optionLabel(INTEREST_METHOD_OPTIONS, interestMethod)}
            description="Forecast interest before each repayment"
            icon="chart-timeline-variant"
            onPress={() => setPicker('interestMethod')}
          />
          <View style={styles.twoColumn}>
            <DateOnlyPickerField
              label="Start date"
              value={startsOn}
              onChange={setStartsOn}
              style={styles.flexField}
            />
            <PremiumTextInput
              mode="outlined"
              label="Day"
              value={dayOfMonth}
              onChangeText={setDayOfMonth}
              keyboardType="number-pad"
              style={styles.flexField}
            />
          </View>
          <View style={styles.twoColumn}>
            <PremiumTextInput
              mode="outlined"
              label="Every"
              value={interval}
              onChangeText={setInterval}
              keyboardType="number-pad"
              style={styles.flexField}
            />
            <PremiumTextInput
              mode="outlined"
              label="Installments"
              value={installments}
              onChangeText={setInstallments}
              keyboardType="number-pad"
              style={styles.flexField}
            />
          </View>
          <View style={styles.twoColumn}>
            <PremiumTextInput
              mode="outlined"
              label="Paid EMIs"
              value={paidInstallments}
              onChangeText={setPaidInstallments}
              keyboardType="number-pad"
              style={styles.flexField}
            />
            <PremiumTextInput
              mode="outlined"
              label="Remaining EMIs"
              value={String(remainingInstallments)}
              editable={false}
              style={styles.flexField}
            />
          </View>
          <DateOnlyPickerField
            label="End date optional"
            value={endsOn}
            onChange={setEndsOn}
            allowClear
          />
          <View style={styles.switchRow}>
            <View style={styles.fill}>
              <Text variant="titleSmall">Linked planned payment</Text>
              <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                Keep this EMI visible with the rest of Planned payments.
              </Text>
            </View>
            <Switch value={autoCreate} onValueChange={setAutoCreate} />
          </View>
          {linkedRule ? (
            <InfoRow icon="calendar-sync-outline" label="Planned payment" value={linkedRule.name} />
          ) : null}
          {forecast ? (
            <InfoRow
              icon="calendar-check-outline"
              label="Forecast close"
              value={
                forecast.scheduleClosesOn
                  ? loanScheduleCloseLabel(forecast.scheduleClosesOn, state.preferences.locale)
                  : 'Still open'
              }
              tone={forecast.scheduleClosesOn ? 'positive' : 'warning'}
            />
          ) : null}
          <Button
            mode="contained"
            icon="content-save-check-outline"
            onPress={() => void savePlan()}
          >
            Save EMI plan
          </Button>
          {linkedRule ? (
            <Button
              mode="contained-tonal"
              icon="calendar-arrow-right"
              onPress={() => router.push(`/recurring/${linkedRule.id}` as never)}
            >
              Open planned payment
            </Button>
          ) : null}
        </SectionCard>
      </AppScreen>

      <OptionListOverlay
        visible={picker === 'source'}
        title={loan.type === 'lent' ? 'Receive into' : 'Pay from'}
        options={sourceAccounts.map((account) => {
          const visual = resolveAccountIconVisual(account);
          return {
            value: account.id,
            label: account.name,
            description: `${accountTypeLabel(account.type)} · ${account.currency}`,
            icon: visual.icon,
            iconBackgroundColor: visual.backgroundColor,
            iconColor: visual.iconColor,
          };
        })}
        selectedValue={sourceAccountId}
        emptyText={`No active ${loan.currency} repayment accounts`}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          setSourceAccountId(option.value);
          setPicker(null);
        }}
      />
      <OptionListOverlay
        visible={picker === 'kind'}
        title="Loan type"
        options={LOAN_KIND_OPTIONS}
        selectedValue={loanKind}
        searchable={false}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          setLoanKind(option.value);
          setPicker(null);
        }}
      />
      <OptionListOverlay
        visible={picker === 'frequency'}
        title="Repeat"
        options={FREQUENCY_OPTIONS}
        selectedValue={frequency}
        searchable={false}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          setFrequency(option.value);
          setPicker(null);
        }}
      />
      <OptionListOverlay
        visible={picker === 'ratePeriod'}
        title="Rate period"
        options={RATE_PERIOD_OPTIONS}
        selectedValue={ratePeriod}
        searchable={false}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          setRatePeriod(option.value);
          setPicker(null);
        }}
      />
      <OptionListOverlay
        visible={picker === 'interestMethod'}
        title="Interest model"
        options={INTEREST_METHOD_OPTIONS}
        selectedValue={interestMethod}
        searchable={false}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          setInterestMethod(option.value);
          setPicker(null);
        }}
      />
      <Snackbar visible={Boolean(snackbar)} onDismiss={() => setSnackbar(null)} duration={2600}>
        {snackbar}
      </Snackbar>
    </>
  );
}

function MoneyField({
  label,
  value,
  currency,
  onChangeText,
  editable = true,
}: {
  label: string;
  value: string;
  currency: string;
  onChangeText?: (value: string) => void;
  editable?: boolean;
}) {
  return (
    <PremiumTextInput
      mode="outlined"
      label={`${label} (${currency})`}
      value={value}
      onChangeText={onChangeText}
      editable={editable}
      keyboardType="numeric"
      style={styles.flexField}
    />
  );
}

function installmentDueOn({
  startsOn,
  frequency,
  interval,
  dayOfMonth,
  paidInstallments,
}: {
  startsOn: string;
  frequency: RecurrenceFrequency;
  interval: string;
  dayOfMonth: string;
  paidInstallments: string;
}): string {
  if (!isValidIsoDate(startsOn)) return startsOn;
  return dateOnly(
    dueDateForInstallment(
      startsOn,
      frequency,
      parseWholeNumber(interval, 1),
      parseWholeNumber(paidInstallments, 0),
      parseWholeNumber(dayOfMonth, new Date().getDate()),
    ),
  );
}

function parseWholeNumber(value: string, fallback: number): number {
  const parsed = Number.parseInt(value.trim(), 10);
  return Number.isFinite(parsed) ? Math.max(0, parsed) : fallback;
}

function dateOnly(value: Date): string {
  const year = value.getFullYear();
  const month = String(value.getMonth() + 1).padStart(2, '0');
  const day = String(value.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

const styles = StyleSheet.create({
  content: { paddingTop: tokens.space.sm },
  twoColumn: { flexDirection: 'row', flexWrap: 'wrap', gap: tokens.space.md },
  flexField: { flex: 1, minWidth: 150 },
  fill: { flex: 1, minWidth: 0 },
  switchRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: tokens.space.md,
    paddingVertical: tokens.space.xs,
  },
});
