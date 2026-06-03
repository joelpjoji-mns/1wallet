import { toMinor } from '@1wallet/domain/money';
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
    parseAmount,
    repaymentSourceAccounts,
    todayIso,
} from '../../../src/loans/loanUtils';
import { removeUnpostedFutureScheduledRecordsForRule } from '../../../src/plannedPayments/ruleActions';

type AutoSolveAnchor = 'paidInstallments' | 'amountLeft';

type LoanEditPicker = 'source' | 'kind' | 'frequency' | 'ratePeriod' | 'interestMethod' | null;

type LoanMathOverrides = Partial<{
  principal: string;
  amountLeft: string;
  payment: string;
  rate: string;
  ratePeriod: LoanInterestRatePeriod;
  frequency: RecurrenceFrequency;
  interval: string;
  installments: string;
  paidInstallments: string;
}>;
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
  const [loanStartOn, setLoanStartOn] = useState(todayIso());
  const [startsOn, setStartsOn] = useState(todayIso());
  const [frequency, setFrequency] = useState<RecurrenceFrequency>('monthly');
  const [interval, setInterval] = useState('1');
  const [dayOfMonth, setDayOfMonth] = useState(String(new Date().getDate()));
  const [installments, setInstallments] = useState('12');
  const [paidInstallments, setPaidInstallments] = useState('0');
  const [remainingInstallments, setRemainingInstallments] = useState('12');
  const [autoSolveAnchor, setAutoSolveAnchor] = useState<AutoSolveAnchor>('paidInstallments');
  const [remainingInterest, setRemainingInterest] = useState('0');
  const [amountLeftWithInterest, setAmountLeftWithInterest] = useState('0');
  const [endsOn, setEndsOn] = useState('');
  const [autoCreate, setAutoCreate] = useState(true);
  const [manualEndDate, setManualEndDate] = useState(false);
  const [manualInterestTiles, setManualInterestTiles] = useState(false);

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
    const scheduleStart =
      details?.repaymentStartsOn ?? details?.trackingStartsOn ?? details?.disbursedOn ?? todayIso();
    const disbursedOn = details?.disbursedOn ?? scheduleStart;
    const cadenceFrequency = details?.repaymentFrequency ?? 'monthly';
    const cadenceInterval = String(details?.repaymentInterval ?? 1);
    const cadenceDayOfMonth = String(details?.repaymentDayOfMonth ?? new Date().getDate());
    const totalCount = details?.repaymentCount ?? 12;
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
    const seededRemainingInterest = details
      ? buildLoanForecast(state, loan, details, {
          amountMinor: calculatedOutstanding.amountMinor,
          currency: loan.currency,
        }).totalInterest
      : { amountMinor: 0, currency: loan.currency };
    setRemainingInterest(formatInputAmount(seededRemainingInterest));
    setAmountLeftWithInterest(
      formatInputAmount({
        amountMinor: calculatedOutstanding.amountMinor + seededRemainingInterest.amountMinor,
        currency: loan.currency,
      }),
    );
    setPaidInstallments(String(paidCount));
    setPayment(
      formatInputAmount(details?.repaymentAmount ?? { amountMinor: 0, currency: loan.currency }),
    );
    setRate(String(details?.interestRatePercent ?? 0));
    setRatePeriod(details?.interestRatePeriod ?? 'annual');
    setInterestMethod(details?.interestMethod ?? 'reducing_balance');
    setLoanStartOn(disbursedOn);
    setStartsOn(scheduleStart);
    setFrequency(cadenceFrequency);
    setInterval(cadenceInterval);
    setDayOfMonth(cadenceDayOfMonth);
    setInstallments(String(totalCount));
    setRemainingInstallments(String(Math.max(0, totalCount - paidCount)));
    const seededEndDate =
      details?.repaymentEndsOn ??
      installmentDueOnIndex({
        startsOn: scheduleStart,
        frequency: cadenceFrequency,
        interval: cadenceInterval,
        dayOfMonth: cadenceDayOfMonth,
        installmentIndex: Math.max(0, totalCount - 1),
      });
    setEndsOn(seededEndDate);
    setManualEndDate(Boolean(details?.repaymentEndsOn));
    setManualInterestTiles(false);
    setAutoSolveAnchor('paidInstallments');
    setAutoCreate(details?.autoCreateScheduledRecords ?? true);
  }, [indexes, loan, sourceAccounts, state]);

  const computedScheduleCloseOn = useMemo(
    () =>
      installmentDueOnIndex({
        startsOn,
        frequency,
        interval,
        dayOfMonth,
        installmentIndex: Math.max(0, parseWholeNumber(installments, 1) - 1),
      }),
    [dayOfMonth, frequency, installments, interval, startsOn],
  );

  useEffect(() => {
    if (manualEndDate) return;
    setEndsOn((current) =>
      current === computedScheduleCloseOn ? current : computedScheduleCloseOn,
    );
  }, [computedScheduleCloseOn, manualEndDate]);

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
            disbursedOn: loanStartOn,
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
      loanStartOn,
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

  const outstandingMinor = useMemo(
    () => (loan ? toMinor(Math.max(0, parseAmount(amountLeft)), loan.currency) : 0),
    [amountLeft, loan],
  );

  const forecast = useMemo(
    () =>
      loan && draftDetails
        ? buildLoanForecast(state, loan, draftDetails, {
            amountMinor: outstandingMinor,
            currency: loan.currency,
          })
        : undefined,
    [draftDetails, loan, outstandingMinor, state],
  );

  useEffect(() => {
    if (!loan || !forecast || manualInterestTiles) return;
    const nextInterest = forecast.totalInterest;
    setRemainingInterest(formatInputAmount(nextInterest));
    setAmountLeftWithInterest(
      formatInputAmount({
        amountMinor: outstandingMinor + nextInterest.amountMinor,
        currency: loan.currency,
      }),
    );
  }, [forecast, loan, manualInterestTiles, outstandingMinor]);

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

  const parseMathInputs = (overrides: LoanMathOverrides = {}) => {
    const principalMinor = toMinor(
      Math.max(0, parseAmount(overrides.principal ?? principal)),
      loan.currency,
    );
    const paymentMinor = toMinor(
      Math.max(0, parseAmount(overrides.payment ?? payment)),
      loan.currency,
    );
    const amountLeftMinor = toMinor(
      Math.max(0, parseAmount(overrides.amountLeft ?? amountLeft)),
      loan.currency,
    );
    const totalInstallments = Math.max(
      0,
      parseWholeNumber(overrides.installments ?? installments, 0),
    );
    const paidCount = Math.max(
      0,
      parseWholeNumber(overrides.paidInstallments ?? paidInstallments, 0),
    );
    return {
      principalMinor,
      paymentMinor,
      amountLeftMinor,
      totalInstallments,
      paidCount,
    };
  };

  const syncRemainingFromCounts = (overrides: LoanMathOverrides = {}) => {
    const { totalInstallments, paidCount } = parseMathInputs(overrides);
    setRemainingInstallments(String(Math.max(0, totalInstallments - paidCount)));
  };

  const syncAmountLeftFromPaid = (overrides: LoanMathOverrides = {}) => {
    const { principalMinor, paymentMinor, paidCount } = parseMathInputs(overrides);
    const solvedOutstanding = solveOutstandingFromInputs(principalMinor, paymentMinor, paidCount);
    setAmountLeft(formatInputAmount({ amountMinor: solvedOutstanding, currency: loan.currency }));
    syncRemainingFromCounts(overrides);
  };

  const syncPaidFromAmountLeft = (overrides: LoanMathOverrides = {}) => {
    const { principalMinor, paymentMinor, amountLeftMinor, totalInstallments } =
      parseMathInputs(overrides);
    const solvedPaid = solvePaidFromOutstanding(principalMinor, paymentMinor, amountLeftMinor);
    if (solvedPaid === undefined) {
      syncRemainingFromCounts(overrides);
      return;
    }
    const roundedPaid = Math.max(0, Math.round(solvedPaid));
    const boundedPaid =
      totalInstallments > 0 ? Math.min(totalInstallments, roundedPaid) : roundedPaid;
    setPaidInstallments(String(boundedPaid));
    setRemainingInstallments(String(Math.max(0, totalInstallments - boundedPaid)));
  };

  const applyAutoSolve = (anchor: AutoSolveAnchor, overrides: LoanMathOverrides = {}) => {
    if (anchor === 'amountLeft') {
      syncPaidFromAmountLeft(overrides);
      return;
    }
    syncAmountLeftFromPaid(overrides);
  };

  const handlePrincipalChange = (nextValue: string) => {
    setPrincipal(nextValue);
    setManualInterestTiles(false);
    applyAutoSolve(autoSolveAnchor, { principal: nextValue });
  };

  const handleAmountLeftChange = (nextValue: string) => {
    setAutoSolveAnchor('amountLeft');
    setAmountLeft(nextValue);
    setManualInterestTiles(false);
    applyAutoSolve('amountLeft', { amountLeft: nextValue });
  };

  const handlePaymentChange = (nextValue: string) => {
    setPayment(nextValue);
    setManualInterestTiles(false);
    applyAutoSolve(autoSolveAnchor, { payment: nextValue });
  };

  const handleRateChange = (nextValue: string) => {
    setRate(nextValue);
    setManualInterestTiles(false);
    applyAutoSolve(autoSolveAnchor, { rate: nextValue });
  };

  const handleRemainingInterestChange = (nextValue: string) => {
    const interestMinor = toMinor(Math.max(0, parseAmount(nextValue)), loan.currency);
    setManualInterestTiles(true);
    setRemainingInterest(nextValue);
    setAmountLeftWithInterest(
      formatInputAmount({ amountMinor: outstandingMinor + interestMinor, currency: loan.currency }),
    );
  };

  const handleAmountLeftWithInterestChange = (nextValue: string) => {
    const totalMinor = toMinor(Math.max(0, parseAmount(nextValue)), loan.currency);
    const interestMinor = Math.max(0, totalMinor - outstandingMinor);
    setManualInterestTiles(true);
    setAmountLeftWithInterest(nextValue);
    setRemainingInterest(
      formatInputAmount({ amountMinor: interestMinor, currency: loan.currency }),
    );
  };

  const handleInstallmentsChange = (nextValue: string) => {
    setInstallments(nextValue);
    setManualEndDate(false);
    setManualInterestTiles(false);
    applyAutoSolve(autoSolveAnchor, { installments: nextValue });
  };

  const handlePaidInstallmentsChange = (nextValue: string) => {
    setAutoSolveAnchor('paidInstallments');
    setPaidInstallments(nextValue);
    setManualInterestTiles(false);
    applyAutoSolve('paidInstallments', { paidInstallments: nextValue });
  };

  const handleRemainingInstallmentsChange = (nextValue: string) => {
    const remaining = parseWholeNumber(nextValue, 0);
    const paid = parseWholeNumber(paidInstallments, 0);
    const total = paid + remaining;
    setRemainingInstallments(nextValue);
    setInstallments(String(total));
    setManualEndDate(false);
    setManualInterestTiles(false);
    applyAutoSolve(autoSolveAnchor, { installments: String(total) });
  };

  const handleEndDateChange = (nextValue: string) => {
    setEndsOn(nextValue);
    setManualEndDate(Boolean(nextValue));
    if (!nextValue || !isValidIsoDate(startsOn) || !isValidIsoDate(nextValue)) return;
    const total = countInstallmentsThroughDate({
      startsOn,
      frequency,
      interval,
      dayOfMonth,
      endsOn: nextValue,
    });
    if (!total) return;
    setInstallments(String(total));
    setManualInterestTiles(false);
    applyAutoSolve(autoSolveAnchor, { installments: String(total) });
  };

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
    const amountLeftMinor = toMinor(Math.max(0, parseAmount(amountLeft)), loan.currency);
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
    if (!isValidIsoDate(draftDetails.disbursedOn)) {
      setSnackbar('Enter a valid loan start date');
      return;
    }
    if (!isValidIsoDate(draftDetails.repaymentStartsOn)) {
      setSnackbar('Enter a valid first EMI date');
      return;
    }

    let linkedRuleId: string | undefined;
    await mutate(
      (draft) => {
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
      },
      { slices: ['preferences', 'accounts', 'transactions'] },
    );
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
            onPress={() => router.push(`/account/${loan.id}` as never)}
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
              onChangeText={handlePrincipalChange}
              currency={loan.currency}
            />
            <MoneyField
              label="Amount left (principal)"
              value={amountLeft}
              onChangeText={handleAmountLeftChange}
              currency={loan.currency}
            />
          </View>
          <View style={styles.twoColumn}>
            <MoneyField
              label="EMI"
              value={payment}
              onChangeText={handlePaymentChange}
              currency={loan.currency}
            />
            <MoneyField
              label="Remaining interest"
              value={remainingInterest}
              onChangeText={handleRemainingInterestChange}
              currency={loan.currency}
            />
          </View>
          <View style={styles.twoColumn}>
            <MoneyField
              label="Amount left incl interest"
              value={amountLeftWithInterest}
              onChangeText={handleAmountLeftWithInterestChange}
              currency={loan.currency}
            />
          </View>
          <View style={styles.twoColumn}>
            <PremiumTextInput
              mode="outlined"
              label="Interest rate %"
              value={rate}
              onChangeText={handleRateChange}
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
              label="Loan start date"
              value={loanStartOn}
              onChange={(nextValue) => {
                setLoanStartOn(nextValue);
                setManualInterestTiles(false);
              }}
              style={styles.flexField}
            />
            <DateOnlyPickerField
              label="First EMI date"
              value={startsOn}
              onChange={(nextValue) => {
                setStartsOn(nextValue);
                setManualInterestTiles(false);
              }}
              style={styles.flexField}
            />
          </View>
          <View style={styles.twoColumn}>
            <PremiumTextInput
              mode="outlined"
              label="Day"
              value={dayOfMonth}
              onChangeText={(nextValue) => {
                setDayOfMonth(nextValue);
                setManualInterestTiles(false);
              }}
              keyboardType="number-pad"
              style={styles.flexField}
            />
          </View>
          <View style={styles.twoColumn}>
            <PremiumTextInput
              mode="outlined"
              label="Every"
              value={interval}
              onChangeText={(nextValue) => {
                setInterval(nextValue);
                setManualInterestTiles(false);
                applyAutoSolve(autoSolveAnchor, { interval: nextValue });
              }}
              keyboardType="number-pad"
              style={styles.flexField}
            />
            <PremiumTextInput
              mode="outlined"
              label="Installments"
              value={installments}
              onChangeText={handleInstallmentsChange}
              keyboardType="number-pad"
              style={styles.flexField}
            />
          </View>
          <View style={styles.twoColumn}>
            <PremiumTextInput
              mode="outlined"
              label="Paid EMIs"
              value={paidInstallments}
              onChangeText={handlePaidInstallmentsChange}
              keyboardType="number-pad"
              style={styles.flexField}
            />
            <PremiumTextInput
              mode="outlined"
              label="Remaining EMIs"
              value={remainingInstallments}
              onChangeText={handleRemainingInstallmentsChange}
              keyboardType="number-pad"
              style={styles.flexField}
            />
          </View>
          <DateOnlyPickerField
            label="End date"
            value={endsOn}
            onChange={handleEndDateChange}
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
          setManualInterestTiles(false);
          applyAutoSolve(autoSolveAnchor, { frequency: option.value });
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
          setManualInterestTiles(false);
          applyAutoSolve(autoSolveAnchor, { ratePeriod: option.value });
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
  return installmentDueOnIndex({
    startsOn,
    frequency,
    interval,
    dayOfMonth,
    installmentIndex: parseWholeNumber(paidInstallments, 0),
  });
}

function installmentDueOnIndex({
  startsOn,
  frequency,
  interval,
  dayOfMonth,
  installmentIndex,
}: {
  startsOn: string;
  frequency: RecurrenceFrequency;
  interval: string;
  dayOfMonth: string;
  installmentIndex: number;
}): string {
  if (!isValidIsoDate(startsOn)) return startsOn;
  return dateOnly(
    dueDateForInstallment(
      startsOn,
      frequency,
      parseWholeNumber(interval, 1),
      Math.max(0, installmentIndex),
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

function countInstallmentsThroughDate({
  startsOn,
  frequency,
  interval,
  dayOfMonth,
  endsOn,
}: {
  startsOn: string;
  frequency: RecurrenceFrequency;
  interval: string;
  dayOfMonth: string;
  endsOn: string;
}): number {
  if (!isValidIsoDate(startsOn) || !isValidIsoDate(endsOn)) return 0;
  const endDate = new Date(endsOn);
  const maxInstallments = 1200;
  for (let index = 0; index < maxInstallments; index += 1) {
    const due = dueDateForInstallment(
      startsOn,
      frequency,
      parseWholeNumber(interval, 1),
      index,
      parseWholeNumber(dayOfMonth, new Date().getDate()),
    );
    if (due > endDate) return Math.max(1, index);
  }
  return maxInstallments;
}

function solveOutstandingFromInputs(
  principalMinor: number,
  paymentMinor: number,
  paidInstallments: number,
): number {
  const principal = Math.max(0, principalMinor);
  const payment = Math.max(0, paymentMinor);
  const paid = Math.max(0, paidInstallments);
  if (!principal || !payment || paid <= 0) return principal;
  return Math.max(0, principal - payment * paid);
}

function solvePaidFromOutstanding(
  principalMinor: number,
  paymentMinor: number,
  outstandingMinor: number,
): number | undefined {
  const principal = Math.max(0, principalMinor);
  const payment = Math.max(0, paymentMinor);
  const outstanding = Math.max(0, outstandingMinor);
  if (!principal || !payment) return undefined;
  if (outstanding >= principal) return 0;
  return (principal - outstanding) / payment;
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
