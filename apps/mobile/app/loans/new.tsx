import { fromMinor, toMinor } from '@1wallet/domain/money';
import type {
    Account,
    AccountLoanDetails,
    LoanInterestMethod,
    LoanInterestRatePeriod,
    LoanKind,
    LoanTrackingSetupMode,
} from '@1wallet/domain/types';
import {
    buildLoanForecast,
    buildLoanPlannedPaymentInput,
    completedLoanInstallmentCount,
    deriveLoanOutstandingPrincipal,
    dueDateForInstallment,
    isLoanAccountType,
    loanOpeningBalanceMinorForOutstanding,
} from '@1wallet/ledger/loans';
import { createFutureGenerationRule } from '@1wallet/ledger/rules/futureGeneration';
import { createAccount, createTransaction, updateAccount } from '@1wallet/ledger/services';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { router } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import { StyleSheet, Switch, View } from 'react-native';
import { Button, Snackbar, Text, useTheme } from 'react-native-paper';
import {
    accountIconForType,
    accountTypeLabel,
    resolveAccountIconVisual,
} from '../../src/accountOptions';
import { AppScreen, InfoRow, PremiumTextInput, SectionCard } from '../../src/components/AppKit';
import { DateOnlyPickerField } from '../../src/components/DateOnlyPickerField';
import {
    OptionListOverlay,
    OptionSelectorRow,
    type OptionListItem,
} from '../../src/components/OptionListOverlay';

type LoanPicker =
  | 'accountType'
  | 'source'
  | 'kind'
  | 'setupMode'
  | 'ratePeriod'
  | 'interestMethod'
  | null;

const ACCOUNT_TYPE_OPTIONS: OptionListItem<Account['type']>[] = [
  {
    value: 'loan',
    label: 'Loan',
    description: 'Personal, home, vehicle, or EMI liability',
    icon: 'bank-outline',
  },
  {
    value: 'overdraft',
    label: 'Overdraft',
    description: 'Credit line or overdraft account',
    icon: 'alert-circle-outline',
  },
];

const LOAN_KIND_OPTIONS: OptionListItem<LoanKind>[] = [
  {
    value: 'personal',
    label: 'Personal loan',
    description: 'General borrowed money',
    icon: 'account-cash-outline',
  },
  {
    value: 'home',
    label: 'Home loan',
    description: 'Mortgage or home finance',
    icon: 'home-outline',
  },
  {
    value: 'vehicle',
    label: 'Vehicle loan',
    description: 'Car, bike, or vehicle finance',
    icon: 'car-clock',
  },
  {
    value: 'education',
    label: 'Education loan',
    description: 'Study or course finance',
    icon: 'school-outline',
  },
  {
    value: 'business',
    label: 'Business loan',
    description: 'Business working capital',
    icon: 'briefcase-outline',
  },
  { value: 'gold', label: 'Gold loan', description: 'Loan against gold', icon: 'gold' },
  {
    value: 'bnpl',
    label: 'BNPL / EMI card',
    description: 'Buy-now-pay-later instalments',
    icon: 'credit-card-clock-outline',
  },
  {
    value: 'overdraft',
    label: 'Overdraft',
    description: 'Credit line or OD account',
    icon: 'alert-circle-outline',
  },
  {
    value: 'other',
    label: 'Other loan',
    description: 'Anything custom',
    icon: 'dots-horizontal-circle-outline',
  },
];

const SETUP_MODE_OPTIONS: OptionListItem<LoanTrackingSetupMode>[] = [
  {
    value: 'track_from_next',
    label: 'Track from next EMI',
    description: 'Use amount left and create no old transactions',
    icon: 'calendar-start',
  },
  {
    value: 'backfill_paid',
    label: 'Backfill paid EMIs',
    description: 'Create cleared repayments for months already paid',
    icon: 'history',
  },
];

const RATE_PERIOD_OPTIONS: OptionListItem<LoanInterestRatePeriod>[] = [
  {
    value: 'annual',
    label: 'Annual rate',
    description: 'APR style interest rate',
    icon: 'percent-outline',
  },
  {
    value: 'monthly',
    label: 'Monthly rate',
    description: 'Interest applied each month',
    icon: 'calendar-month-outline',
  },
];

const INTEREST_METHOD_OPTIONS: OptionListItem<LoanInterestMethod>[] = [
  {
    value: 'reducing_balance',
    label: 'Reducing balance',
    description: 'Interest is charged on what is still left',
    icon: 'chart-timeline-variant',
  },
  {
    value: 'flat',
    label: 'Flat interest',
    description: 'Interest is based on original principal',
    icon: 'chart-line-variant',
  },
  {
    value: 'interest_only',
    label: 'Interest first',
    description: 'Shows interest before principal payoff',
    icon: 'bank-minus',
  },
];

export default function NewLoan() {
  const theme = useTheme();
  const { state, mutate } = useLedger();
  const [picker, setPicker] = useState<LoanPicker>(null);
  const [snackbar, setSnackbar] = useState<string | null>(null);
  const [name, setName] = useState('Home loan');
  const [institution, setInstitution] = useState('');
  const [accountType, setAccountType] = useState<Account['type']>('loan');
  const [loanKind, setLoanKind] = useState<LoanKind>('home');
  const currency = state.preferences.baseCurrency;
  const [sourceAccountId, setSourceAccountId] = useState('');
  const [originalPrincipal, setOriginalPrincipal] = useState('0');
  const [currentOutstanding, setCurrentOutstanding] = useState('0');
  const [currentOutstandingEdited, setCurrentOutstandingEdited] = useState(false);
  const [emiAmount, setEmiAmount] = useState('0');
  const [remainingInstallments, setRemainingInstallments] = useState('60');
  const [paidInstallments, setPaidInstallments] = useState('12');
  const [loanStartedOn, setLoanStartedOn] = useState(() => dateOnly(addMonths(new Date(), -12)));
  const [nextEmiOn, setNextEmiOn] = useState(() => nextMonthlyDate(new Date().getDate()));
  const [rate, setRate] = useState('0');
  const [ratePeriod, setRatePeriod] = useState<LoanInterestRatePeriod>('annual');
  const [interestMethod, setInterestMethod] = useState<LoanInterestMethod>('reducing_balance');
  const [setupMode, setSetupMode] = useState<LoanTrackingSetupMode>('track_from_next');
  const [includeInNetWorth, setIncludeInNetWorth] = useState(true);

  const sourceAccounts = useMemo(
    () =>
      state.accounts
        .filter((account) => !account.isArchived && !isLoanAccountType(account.type))
        .filter((account) => account.currency === currency)
        .sort(
          (left, right) => left.sortOrder - right.sortOrder || left.name.localeCompare(right.name),
        ),
    [currency, state.accounts],
  );
  const selectedSource =
    sourceAccounts.find((account) => account.id === sourceAccountId) ?? sourceAccounts[0];
  const selectedSourceVisual = selectedSource
    ? resolveAccountIconVisual(selectedSource)
    : undefined;
  const calculatedOutstanding = useMemo(() => {
    const originalMinor = toMinor(Math.max(0, parseAmount(originalPrincipal)), currency);
    const emiMinor = toMinor(Math.max(0, parseAmount(emiAmount)), currency);
    const paid = setupMode === 'backfill_paid' ? clampInt(paidInstallments, 0, 1200, 0) : undefined;
    return deriveLoanOutstandingPrincipal(
      {
        principal: { amountMinor: originalMinor, currency },
        repaymentAmount: { amountMinor: emiMinor, currency },
        repaymentStartsOn: loanStartedOn,
        repaymentFrequency: 'monthly',
        repaymentInterval: 1,
        repaymentDayOfMonth: dateDay(nextEmiOn),
        repaymentCount: 1200,
      },
      currency,
      { asOf: nextEmiOn, paidInstallments: paid },
    );
  }, [
    currency,
    emiAmount,
    loanStartedOn,
    nextEmiOn,
    originalPrincipal,
    paidInstallments,
    setupMode,
  ]);

  useEffect(() => {
    if (selectedSource && selectedSource.id !== sourceAccountId)
      setSourceAccountId(selectedSource.id);
  }, [selectedSource, sourceAccountId]);

  useEffect(() => {
    if (currentOutstandingEdited) return;
    setCurrentOutstanding(moneyTextFromMinor(calculatedOutstanding.amountMinor, currency));
  }, [calculatedOutstanding.amountMinor, currency, currentOutstandingEdited]);

  const save = async () => {
    const cleanName = name.trim();
    const source = selectedSource;
    const originalMinor = toMinor(Math.max(0, parseAmount(originalPrincipal)), currency);
    const outstandingMinor = toMinor(Math.max(0, parseAmount(currentOutstanding)), currency);
    const emiMinor = toMinor(Math.max(0, parseAmount(emiAmount)), currency);
    const remaining = clampInt(remainingInstallments, 1, 1200, 60);
    const schedulePaid = paidInstallmentsBeforeDate(loanStartedOn, nextEmiOn);
    const paid =
      setupMode === 'backfill_paid' ? clampInt(paidInstallments, 0, 1200, 0) : schedulePaid;
    const principalMinor = originalMinor;

    if (!cleanName) {
      setSnackbar('Name the loan');
      return;
    }
    if (!principalMinor) {
      setSnackbar('Enter the original principal');
      return;
    }
    if (!source) {
      setSnackbar(`Choose a ${currency} repayment account`);
      return;
    }
    if (!outstandingMinor) {
      setSnackbar('Enter the amount left');
      return;
    }
    if (!emiMinor) {
      setSnackbar('Enter the principal EMI amount');
      return;
    }
    if (outstandingMinor > principalMinor) {
      setSnackbar('Amount left cannot exceed original principal');
      return;
    }
    if (!isValidDateOnly(nextEmiOn) || !isValidDateOnly(loanStartedOn)) {
      setSnackbar('Enter valid loan dates');
      return;
    }

    let createdLoanId: string | undefined;
    await mutate(
      (draft) => {
        const openingBalanceMinor =
          setupMode === 'backfill_paid' ? -principalMinor : -outstandingMinor;
        const loan = createAccount(draft, {
          name: cleanName,
          type: accountType,
          currency,
          openingBalanceMinor,
          openingDate: setupMode === 'backfill_paid' ? loanStartedOn : nextEmiOn,
          institution: institution.trim() || undefined,
          icon: accountIconForType(accountType),
          color: accountType === 'overdraft' ? '#A83246' : '#6B5F47',
          includeInTotals: true,
          includeInBudgets: false,
          includeInReports: true,
          includeInNetWorth,
        });
        createdLoanId = loan.id;

        if (setupMode === 'backfill_paid' && paid > 0) {
          const historicalDetails = buildLoanDetails(loan, {
            loanKind,
            principalMinor,
            sourceAccountId: source.id,
            emiMinor,
            startsOn: loanStartedOn,
            trackingStartsOn: loanStartedOn,
            remainingCount: paid + remaining,
            paid: 0,
            rate,
            ratePeriod,
            interestMethod,
            setupMode,
          });
          const forecast = buildLoanForecast(draft, loan, historicalDetails, {
            amountMinor: openingBalanceMinor,
            currency,
          });
          for (const row of forecast.rows.slice(0, paid)) {
            createTransaction(draft, {
              type: 'loan_repayment',
              status: 'cleared',
              source: 'manual',
              accountId: source.id,
              counterAccountId: loan.id,
              amountMinor: row.payment.amountMinor,
              currency,
              counterAmountMinor: row.principal.amountMinor || undefined,
              counterCurrency: row.principal.amountMinor ? currency : undefined,
              occurredAt: withHour(row.dueAt, 8),
              paymentMethod: 'Auto debit',
              notes: `${loan.name} backfilled EMI #${row.installment}`,
              externalRef: `loan-backfill-v1:${loan.id}:${row.dueAt}`,
            });
          }
        }

        const loanDetails = buildLoanDetails(loan, {
          loanKind,
          principalMinor,
          sourceAccountId: source.id,
          emiMinor,
          startsOn: loanStartedOn,
          trackingStartsOn: nextEmiOn,
          remainingCount: paid + remaining,
          paid,
          rate,
          ratePeriod,
          interestMethod,
          setupMode,
        });
        const input = buildLoanPlannedPaymentInput(loan, loanDetails);
        const rule = input ? createFutureGenerationRule(draft, input) : undefined;
        const openingBalanceMinorForOutstanding = loanOpeningBalanceMinorForOutstanding(
          draft,
          loan,
          {
            amountMinor: outstandingMinor,
            currency,
          },
        );
        updateAccount(draft, loan.id, {
          openingBalanceMinor: openingBalanceMinorForOutstanding,
          loanDetails: { ...loanDetails, linkedPlannedPaymentRuleId: rule?.id },
        });
      },
      { slices: ['preferences', 'accounts', 'transactions'] },
    );

    setSnackbar('Loan created with EMI forecast');
    if (createdLoanId) {
      router.replace(`/loans/${createdLoanId}` as never);
    } else {
      router.replace('/loans' as never);
    }
  };

  return (
    <>
      <AppScreen title="New loan" subtitle="Create a loan account and linked EMI plan.">
        <SectionCard title="Loan account">
          <PremiumTextInput label="Loan name" value={name} onChangeText={setName} />
          <PremiumTextInput
            mode="outlined"
            label="Lender optional"
            value={institution}
            onChangeText={setInstitution}
          />
          <View style={styles.row}>
            <OptionSelectorRow
              label="Account type"
              value={optionLabel(ACCOUNT_TYPE_OPTIONS, accountType)}
              icon={accountIconForType(accountType)}
              onPress={() => setPicker('accountType')}
              style={styles.selectorField}
            />
            <OptionSelectorRow
              label="Loan type"
              value={optionLabel(LOAN_KIND_OPTIONS, loanKind)}
              icon="shape-outline"
              onPress={() => setPicker('kind')}
              style={styles.selectorField}
            />
          </View>
          <OptionSelectorRow
            label="Pay from"
            value={selectedSource?.name ?? `No ${currency} account`}
            description={
              selectedSource
                ? `${accountTypeLabel(selectedSource.type)} · ${currency}`
                : 'Add a bank, wallet, cash, or card account first'
            }
            icon={selectedSourceVisual?.icon ?? 'wallet-outline'}
            iconBackgroundColor={selectedSourceVisual?.backgroundColor}
            iconColor={selectedSourceVisual?.iconColor}
            valueNumberOfLines={2}
            onPress={() => setPicker('source')}
          />
        </SectionCard>

        <SectionCard title="Amount and schedule">
          <OptionSelectorRow
            label="Existing loan setup"
            value={optionLabel(SETUP_MODE_OPTIONS, setupMode)}
            description={
              setupMode === 'backfill_paid'
                ? 'Create old paid EMIs'
                : 'Start clean from the next EMI'
            }
            icon="calendar-start"
            onPress={() => setPicker('setupMode')}
          />
          <View style={styles.row}>
            <MoneyInput
              label="Original principal"
              value={originalPrincipal}
              currency={currency}
              onChangeText={setOriginalPrincipal}
            />
            <MoneyInput
              label="Amount left"
              value={currentOutstanding}
              currency={currency}
              onChangeText={(value) => {
                setCurrentOutstanding(value);
                setCurrentOutstandingEdited(true);
              }}
            />
          </View>
          {currentOutstandingEdited ? (
            <Button
              mode="text"
              compact
              icon="calculator-variant-outline"
              onPress={() => {
                setCurrentOutstanding(
                  moneyTextFromMinor(calculatedOutstanding.amountMinor, currency),
                );
                setCurrentOutstandingEdited(false);
              }}
            >
              Use calculated amount left
            </Button>
          ) : null}
          <View style={styles.row}>
            <MoneyInput
              label="Principal EMI"
              value={emiAmount}
              currency={currency}
              onChangeText={setEmiAmount}
            />
            <PremiumTextInput
              mode="outlined"
              label="Remaining EMIs"
              value={remainingInstallments}
              keyboardType="number-pad"
              onChangeText={setRemainingInstallments}
              style={styles.field}
            />
          </View>
          {setupMode === 'backfill_paid' ? (
            <PremiumTextInput
              mode="outlined"
              label="Paid EMIs before tracking"
              value={paidInstallments}
              keyboardType="number-pad"
              onChangeText={setPaidInstallments}
            />
          ) : null}
          <View style={styles.row}>
            <DateOnlyPickerField
              label="Loan start date"
              value={loanStartedOn}
              onChange={setLoanStartedOn}
              style={styles.field}
            />
            <DateOnlyPickerField
              label="Next EMI date"
              value={nextEmiOn}
              onChange={setNextEmiOn}
              style={styles.field}
            />
          </View>
        </SectionCard>

        <SectionCard title="Interest">
          <View style={styles.row}>
            <PremiumTextInput
              mode="outlined"
              label="Interest rate %"
              value={rate}
              keyboardType="numeric"
              onChangeText={setRate}
              style={styles.field}
            />
            <OptionSelectorRow
              label="Rate period"
              value={optionLabel(RATE_PERIOD_OPTIONS, ratePeriod)}
              icon="percent-outline"
              onPress={() => setPicker('ratePeriod')}
              style={styles.field}
            />
          </View>
          <OptionSelectorRow
            label="Interest model"
            value={optionLabel(INTEREST_METHOD_OPTIONS, interestMethod)}
            description="Reducing balance is the default EMI model"
            icon="chart-timeline-variant"
            onPress={() => setPicker('interestMethod')}
          />
        </SectionCard>

        <SectionCard title="Settings">
          <View style={styles.switchRow}>
            <View style={styles.fill}>
              <Text variant="titleSmall">Include in net worth</Text>
              <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                Loan balance appears as a liability in totals.
              </Text>
            </View>
            <Switch value={includeInNetWorth} onValueChange={setIncludeInNetWorth} />
          </View>
          <InfoRow
            icon="calendar-sync-outline"
            label="Planned payment"
            value="Loan EMI will be created"
          />
          <Button mode="contained" icon="content-save-check-outline" onPress={() => void save()}>
            Create loan
          </Button>
        </SectionCard>
      </AppScreen>

      <OptionListOverlay
        visible={picker === 'accountType'}
        title="Loan account type"
        options={ACCOUNT_TYPE_OPTIONS}
        selectedValue={accountType}
        searchable={false}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          setAccountType(option.value);
          if (option.value === 'overdraft') setLoanKind('overdraft');
          setPicker(null);
        }}
      />
      <OptionListOverlay
        visible={picker === 'source'}
        title="Pay from"
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
        emptyText={`No active ${currency} repayment accounts`}
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
        visible={picker === 'setupMode'}
        title="Existing loan setup"
        options={SETUP_MODE_OPTIONS}
        selectedValue={setupMode}
        searchable={false}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          setSetupMode(option.value);
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
      <Snackbar visible={Boolean(snackbar)} onDismiss={() => setSnackbar(null)} duration={2400}>
        {snackbar}
      </Snackbar>
    </>
  );
}

function MoneyInput({
  label,
  value,
  currency,
  onChangeText,
}: {
  label: string;
  value: string;
  currency: string;
  onChangeText: (value: string) => void;
}) {
  return (
    <PremiumTextInput
      mode="outlined"
      label={`${label} (${currency})`}
      value={value}
      keyboardType="numeric"
      onChangeText={onChangeText}
      style={styles.field}
    />
  );
}

function buildLoanDetails(
  loan: Account,
  input: {
    loanKind: LoanKind;
    principalMinor: number;
    sourceAccountId: string;
    emiMinor: number;
    startsOn: string;
    trackingStartsOn: string;
    remainingCount: number;
    paid: number;
    rate: string;
    ratePeriod: LoanInterestRatePeriod;
    interestMethod: LoanInterestMethod;
    setupMode: LoanTrackingSetupMode;
  },
): AccountLoanDetails {
  return {
    loanKind: input.loanKind,
    principal: { amountMinor: input.principalMinor, currency: loan.currency },
    disbursedOn: input.startsOn,
    interestRatePercent: Math.max(0, Number(input.rate) || 0),
    interestRatePeriod: input.ratePeriod,
    interestMethod: input.interestMethod,
    repaymentSourceAccountId: input.sourceAccountId,
    repaymentAmount: { amountMinor: input.emiMinor, currency: loan.currency },
    repaymentStartsOn: input.startsOn,
    repaymentFrequency: 'monthly',
    repaymentInterval: 1,
    repaymentDayOfMonth: dateDay(input.trackingStartsOn),
    repaymentCount: input.remainingCount,
    autoCreateScheduledRecords: true,
    trackingStartsOn: input.trackingStartsOn,
    paidInstallmentsBeforeTracking: input.paid,
    setupMode: input.setupMode,
  };
}

function parseAmount(value: string): number {
  return Number(value.replace(/,/g, '').trim()) || 0;
}

function moneyTextFromMinor(amountMinor: number, currency: string): string {
  const amount = fromMinor(Math.max(0, amountMinor), currency);
  return Number.isInteger(amount)
    ? String(amount)
    : String(amount).replace(/0+$/, '').replace(/\.$/, '');
}

function clampInt(value: string, min: number, max: number, fallback: number): number {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function isValidDateOnly(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(new Date(value).getTime());
}

function dateDay(value: string): number {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? new Date().getDate() : date.getDate();
}

function paidInstallmentsBeforeDate(startsOn: string, nextEmiOn: string): number {
  return completedLoanInstallmentCount(
    {
      repaymentStartsOn: startsOn,
      repaymentFrequency: 'monthly',
      repaymentInterval: 1,
      repaymentDayOfMonth: dateDay(nextEmiOn),
      repaymentCount: 1200,
    },
    nextEmiOn,
  );
}

function withHour(dateIso: string, hour: number): string {
  const date = new Date(dateIso);
  date.setHours(hour, 0, 0, 0);
  return date.toISOString();
}

function nextMonthlyDate(dayOfMonth: number): string {
  const today = new Date();
  const candidate = dueDateForInstallment(dateOnly(today), 'monthly', 1, 0, dayOfMonth);
  if (candidate < startOfDay(today))
    return dateOnly(dueDateForInstallment(dateOnly(today), 'monthly', 1, 1, dayOfMonth));
  return dateOnly(candidate);
}

function addMonths(date: Date, months: number): Date {
  return new Date(date.getFullYear(), date.getMonth() + months, date.getDate());
}

function startOfDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function dateOnly(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function optionLabel<TValue extends string>(
  options: readonly OptionListItem<TValue>[],
  value: TValue,
): string {
  return options.find((option) => option.value === value)?.label ?? value;
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', flexWrap: 'wrap', gap: tokens.space.md },
  field: { flex: 1, minWidth: 150 },
  selectorField: { flexGrow: 1, flexBasis: '100%' },
  fill: { flex: 1, minWidth: 0 },
  switchRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: tokens.space.md,
  },
});
