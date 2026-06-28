import 'dart:math' as math;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../common/route_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/currency_picker.dart';
import '../common/full_screen_picker.dart';
import '../transactions/transaction_row.dart';
import '../../utils/number_formatter.dart';
import 'loan_forecast_simulator.dart';

class LoansScreen extends ConsumerWidget {
  const LoansScreen({super.key, this.mode = 'overview', this.accountId});

  final String mode;
  final String? accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ledgerProvider);
    final allLoans = state.accounts
        .where(
          (account) => account.type == 'loan' || account.type == 'overdraft',
        )
        .toList();
    final activeLoans = allLoans
        .where((account) => !_isPastLoan(state, account))
        .toList();
    final pastLoans = allLoans
        .where((account) => _isPastLoan(state, account))
        .toList();
    final listedLoans = mode == 'past' ? pastLoans : activeLoans;
    final selectedLoan = accountById(state, accountId);
    final emi = scheduledTransactions(state)
        .where((record) => record.type == 'loan_repayment')
        .fold<int>(0, (sum, record) => sum + record.amount.amountMinor);
    return RouteScaffold(
      title: switch (mode) {
        'forecast' => 'Loan forecast',
        'new' => 'New loan',
        'edit' => 'Edit loan',
        'detail' => selectedLoan?.name ?? 'Loan detail',
        'past' => 'Past loans',
        _ => 'Loans',
      },
      actions: [
        IconButton(
          onPressed: () => context.push('/loans/new'),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
      child: Column(
        children: [
          if (mode != 'detail' && mode != 'edit' && mode != 'new' && mode != 'forecast') ...[
            SectionCard(
              title: 'Loan control center',
              subtitle: 'Outstanding, next EMI, forecast and payoff pressure.',
              child: Row(
                children: [
                  Expanded(
                    child: MetricTile(
                      label: mode == 'past' ? 'Past loans' : 'Loans',
                      value: '${listedLoans.length}',
                      icon: Icons.account_balance_outlined,
                      compact: true,
                      tone: mode == 'past'
                          ? MetricTone.standard
                          : MetricTone.warning,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: MetricTile(
                      label: mode == 'past' ? 'Archived' : 'Next EMI',
                      value: mode == 'past'
                          ? '${pastLoans.length}'
                          : formatMoney(
                              convertMoneyForDisplay(
                                state,
                                Money(
                                  amountMinor: emi,
                                  currency: state.preferences.baseCurrency,
                                ),
                              ),
                              state.preferences.locale,
                            ),
                      icon: mode == 'past'
                          ? Icons.archive_outlined
                          : Icons.event_repeat_outlined,
                      compact: true,
                      tone: mode == 'past'
                          ? MetricTone.warning
                          : MetricTone.danger,
                    ),
                  ),
                ],
              ),
            ),
            const Gap(AppSpacing.lg),
          ],
          if (mode == 'new' || mode == 'edit')
            LoanForm(accountId: accountId)
          else if (mode == 'detail')
            selectedLoan == null
                ? EmptyState(
                    icon: Icons.account_balance_outlined,
                    title: 'Loan not found',
                    body:
                        'This loan account is not available in the local ledger.',
                    actionLabel: 'Back to loans',
                    onAction: () => context.push('/loans'),
                  )
                : LoanDetailView(loan: selectedLoan)
          else if (mode == 'forecast')
            LoanForecastView(state: state, loans: activeLoans)
          else if (listedLoans.isEmpty)
            EmptyState(
              icon: mode == 'past'
                  ? Icons.history_rounded
                  : Icons.account_balance_outlined,
              title: mode == 'past' ? 'No past loans yet' : 'No loans yet',
              body: mode == 'past'
                  ? 'Archived or closed loans will appear here once you finish one and archive it.'
                  : 'Create a loan account to track EMIs, balances, and payoff progress.',
              actionLabel: mode == 'past' ? 'Back to loans' : 'Create loan',
              onAction: () =>
                  context.push(mode == 'past' ? '/loans' : '/loans/new'),
            )
          else
            for (final loan in listedLoans) ...[
              _LoanCompactCard(
                state: state,
                loan: loan,
                mode: mode,
                onTap: () => context.push('/loans/${loan.id}'),
              ),
              const SizedBox(height: 6),
            ],
        ],
      ),
    );
  }
}

class LoanForm extends ConsumerStatefulWidget {
  const LoanForm({super.key, this.accountId});

  final String? accountId;

  @override
  ConsumerState<LoanForm> createState() => _LoanFormState();
}

class _LoanFormState extends ConsumerState<LoanForm> {
  final _nameController = TextEditingController();
  final _lenderController = TextEditingController();
  final _principalController = TextEditingController();
  final _currentBalanceController = TextEditingController();
  final _emiController = TextEditingController();
  final _rateController = TextEditingController();
  final _tenureController = TextEditingController();
  String? _loadedAccountId;
  String? _sourceAccountId;
  var _loanKind = 'loan';
  var _currency =
      kDefaultCurrency; // will be synced from state in _syncLoanDraft
  var _frequency = 'monthly';
  int _interval = 1;
  final Set<int> _daysOfWeek = {};
  final Set<int> _daysOfMonth = {};
  var _hideInterestInLedger = true;
  DateTime _nextEmiDate = DateTime.now().add(const Duration(days: 30));

  @override
  void initState() {
    super.initState();
    _principalController.addListener(_autoCalculateEmi);
    _rateController.addListener(_autoCalculateEmi);
    _tenureController.addListener(_autoCalculateEmi);
  }

  void _autoCalculateEmi() {
    final principalMinor = _amountMinorFromInput(_principalController.text);
    final rate = _optionalDouble(_rateController.text);
    final tenure = _optionalInt(_tenureController.text);

    if (principalMinor > 0 &&
        rate != null &&
        rate > 0 &&
        tenure != null &&
        tenure > 0 &&
        _frequency == 'monthly' &&
        _interval == 1) {
      final monthlyRate = rate / 100 / 12;
      final numerator =
          principalMinor * monthlyRate * math.pow(1 + monthlyRate, tenure);
      final denominator = math.pow(1 + monthlyRate, tenure) - 1;
      final emiMinor = (numerator / denominator).round();

      final newText = _formatAmountInput(emiMinor);
      if (_emiController.text != newText && _emiController.text.isEmpty) {
        _emiController.text = newText;
      } else if (_emiController.text != newText &&
          _emiController.text.isNotEmpty) {
        // Only aggressively overwrite if it seems the user hasn't explicitly set a custom EMI recently.
        // A simple check is to overwrite if it's currently showing an old auto-calculated EMI.
        _emiController.text = newText;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _lenderController.dispose();
    _principalController.dispose();
    _currentBalanceController.dispose();
    _emiController.dispose();
    _rateController.dispose();
    _tenureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerProvider);
    final loan = accountById(state, widget.accountId);
    _syncLoanDraft(state, loan);
    final sourceAccount = accountById(state, _sourceAccountId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: loan == null ? 'Loan details' : 'Edit loan details',
          subtitle: 'Create a loan account and optional scheduled EMI.',
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Loan name',
                  prefixIcon: Icon(Icons.account_balance_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _lenderController,
                decoration: const InputDecoration(
                  labelText: 'Lender / institution',
                  prefixIcon: Icon(Icons.business_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _principalController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        ThousandsSeparatorInputFormatter(state.preferences.locale)
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Original Principal',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      controller: _currentBalanceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        ThousandsSeparatorInputFormatter(state.preferences.locale)
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Current Balance',
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _emiController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        ThousandsSeparatorInputFormatter(state.preferences.locale)
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Repayment amount',
                        prefixIcon: Icon(Icons.event_repeat_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      controller: _rateController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        ThousandsSeparatorInputFormatter(state.preferences.locale)
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Rate %',
                        prefixIcon: Icon(Icons.percent_rounded),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _tenureController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tenure count',
                  prefixIcon: Icon(Icons.timelapse_outlined),
                ),
              ),
            ],
          ),
        ),
        const Gap(AppSpacing.lg),
        SectionCard(
          title: 'Repayment schedule',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PremiumRow(
                icon: Icons.category_outlined,
                title: 'Loan type',
                subtitle: accountTypeLabel(_loanKind),
                onTap: _showLoanKindPicker,
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: _frequency,
                decoration: const InputDecoration(
                  labelText: 'EMI Frequency',
                  prefixIcon: Icon(Icons.repeat_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'daily', child: Text('Daily')),
                  DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                  DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                  DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                ],
                onChanged: (value) =>
                    setState(() => _frequency = value ?? 'monthly'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                initialValue: _interval.toString(),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText:
                      'Every X ${_frequency == 'daily' ? 'day' : _frequency.replaceAll('ly', '')}s',
                  prefixIcon: const Icon(Icons.timer_outlined),
                ),
                onChanged: (value) => _interval = int.tryParse(value) ?? 1,
              ),
              if (_frequency == 'weekly') ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'On these days:',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 1; i <= 7; i++)
                      FilterChip(
                        label: Text(['', 'M', 'T', 'W', 'T', 'F', 'S', 'S'][i]),
                        selected: _daysOfWeek.contains(i),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              if (_daysOfWeek.length < _interval) {
                                _daysOfWeek.add(i);
                              }
                            } else {
                              _daysOfWeek.remove(i);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ],
              if (_frequency == 'monthly') ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'On these days of the month:',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (var i = 1; i <= 31; i++)
                      FilterChip(
                        label: Text('$i'),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        selected: _daysOfMonth.contains(i),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              if (_daysOfMonth.length < _interval) {
                                _daysOfMonth.add(i);
                              }
                            } else {
                              _daysOfMonth.remove(i);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              PremiumRow(
                icon: sourceAccount == null
                    ? Icons.account_balance_wallet_outlined
                    : accountIcon(sourceAccount),
                title: 'Pay from',
                subtitle: sourceAccount?.name ?? 'Choose source account',
                iconColor: sourceAccount == null
                    ? null
                    : accountDisplayColor(sourceAccount),
                onTap: () => _showSourceAccountPicker(state),
              ),
              const SizedBox(height: AppSpacing.sm),
              LiquidGlassSwitchListTile(
                title: const Text('Hide interest in main ledger'),
                value: _hideInterestInLedger,
                onChanged: (value) =>
                    setState(() => _hideInterestInLedger = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              PremiumRow(
                icon: Icons.calendar_month_outlined,
                title: 'Next EMI date',
                subtitle: formatLedgerDate(
                  _nextEmiDate,
                  state.preferences.locale,
                ),
                onTap: _pickNextEmiDate,
              ),
              const SizedBox(height: AppSpacing.sm),
              PremiumRow(
                icon: Icons.currency_exchange_outlined,
                title: 'Currency',
                subtitle: _currency,
                onTap: () => _showCurrencyPicker(state),
              ),
            ],
          ),
        ),
        const Gap(AppSpacing.lg),
        FilledButton.icon(
          onPressed: () => _saveLoan(state, loan),
          icon: const Icon(Icons.save_outlined),
          label: Text(loan == null ? 'Create loan' : 'Save loan'),
        ),
      ],
    );
  }

  void _syncLoanDraft(LedgerState state, Account? loan) {
    final key = loan?.id ?? '__new__';
    if (_loadedAccountId == key) return;
    _loadedAccountId = key;
    final details = loan == null ? null : _effectiveLoanDetails(state, loan);
    _currency = loan?.currency ?? state.preferences.baseCurrency;
    _loanKind = loan?.type ?? 'loan';
    _nameController.text = loan?.name ?? '';
    _lenderController.text = loan?.institution ?? '';
    _principalController.text = details?.principal == null
        ? loan == null
              ? ''
              : _formatAmountInput(loan.openingBalance.amountMinor.abs())
        : _formatAmountInput(details!.principal!.amountMinor.abs());
    final balance = loan == null ? null : accountBalance(state, loan);
    _currentBalanceController.text = balance == null
        ? ''
        : _formatAmountInput(balance.amountMinor.abs());
    final existingEmi = _existingLoanEmi(state, loan?.id);
    final repaymentAmount = details?.repaymentAmount;
    _emiController.text = repaymentAmount == null && existingEmi == null
        ? ''
        : _formatAmountInput(
            (existingEmi?.amount ?? repaymentAmount!).amountMinor.abs(),
          );
    _rateController.text = _formatOptionalDecimal(
      details?.interestRatePercent ?? _doubleTagValue(loan?.groupName, 'rate'),
    );
    _tenureController.text =
        (details?.repaymentCount ??
                _intTagValue(loan?.groupName, 'tenure') ??
                '')
            .toString();
    _sourceAccountId =
        details?.repaymentSourceAccountId ??
        existingEmi?.accountId ??
        state.accounts
            .firstWhereOrNull(
              (account) => !account.isArchived && !isLiabilityAccount(account),
            )
            ?.id;
    _nextEmiDate =
        details?.repaymentStartsOn ??
        existingEmi?.occurredAt ??
        DateTime.now().add(const Duration(days: 30));
    _hideInterestInLedger = details?.hideInterestInLedger ?? true;
    _frequency =
        existingEmi?.recurrenceFrequency ??
        details?.recurrenceFrequency ??
        'monthly';
    _interval =
        existingEmi?.recurrenceInterval ?? details?.recurrenceInterval ?? 1;
    _daysOfWeek.clear();
    if (existingEmi?.recurrenceDaysOfWeek != null) {
      _daysOfWeek.addAll(existingEmi!.recurrenceDaysOfWeek!);
    } else if (details?.recurrenceDaysOfWeek != null) {
      _daysOfWeek.addAll(details!.recurrenceDaysOfWeek!);
    }
    _daysOfMonth.clear();
    if (existingEmi?.recurrenceDaysOfMonth != null) {
      _daysOfMonth.addAll(existingEmi!.recurrenceDaysOfMonth!);
    } else if (details?.recurrenceDaysOfMonth != null) {
      _daysOfMonth.addAll(details!.recurrenceDaysOfMonth!);
    }
  }

  Future<void> _showLoanKindPicker() async {
    final next = await showFullScreenPicker<String>(
      context: context,
      title: 'Loan type',
      searchable: false,
      selectedValue: _loanKind,
      options: const [
        PickerOption(
          value: 'loan',
          title: 'Loan',
          subtitle: 'Personal, home, education, vehicle, or business loan',
          icon: Icons.account_balance_outlined,
        ),
        PickerOption(
          value: 'overdraft',
          title: 'Overdraft',
          subtitle: 'Credit line or overdraft balance',
          icon: Icons.account_balance_wallet_outlined,
        ),
      ],
    );
    if (next == null) return;
    setState(() => _loanKind = next);
  }

  Future<void> _showSourceAccountPicker(LedgerState state) async {
    final next = await showFullScreenPicker<String>(
      context: context,
      title: 'EMI source account',
      searchHint: 'Search accounts',
      selectedValue: _sourceAccountId,
      options: [
        for (final account in state.accounts.where(
          (account) => !account.isArchived && !isLiabilityAccount(account),
        ))
          PickerOption(
            value: account.id,
            title: account.name,
            subtitle:
                '${accountTypeLabel(account.type)} · ${formatMoney(accountBalance(state, account), state.preferences.locale)}',
            icon: accountIcon(account),
            iconColor: accountDisplayColor(account),
          ),
      ],
    );
    if (next == null) return;
    setState(() => _sourceAccountId = next);
  }

  Future<void> _showCurrencyPicker(LedgerState state) async {
    final next = await showCurrencyPicker(
      context: context,
      state: state,
      selectedValue: _currency,
    );
    if (next == null) return;
    setState(() => _currency = next);
  }

  Future<void> _pickNextEmiDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextEmiDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _nextEmiDate = picked);
  }

  Future<void> _saveLoan(LedgerState state, Account? existingLoan) async {
    final name = _nameController.text.trim();
    final principalMinor = _amountMinorFromInput(
      _principalController.text,
    ).abs();
    final currentBalanceInput = _amountMinorFromInput(
      _currentBalanceController.text,
    ).abs();
    final effectiveCurrentBalanceMinor = _currentBalanceController.text.isEmpty
        ? principalMinor
        : currentBalanceInput;
    final emiMinor = _amountMinorFromInput(_emiController.text).abs();
    final rate = _optionalDouble(_rateController.text);
    final tenure = _optionalInt(_tenureController.text);
    if (name.isEmpty) {
      _showRouteMessage(context, 'Enter a loan name.');
      return;
    }
    if (principalMinor <= 0) {
      _showRouteMessage(context, 'Enter the loan principal.');
      return;
    }
    final sourceAccount = accountById(state, _sourceAccountId);
    if (emiMinor > 0 && sourceAccount == null) {
      _showRouteMessage(context, 'Choose the account that pays the EMI.');
      return;
    }
    try {
      final loanDetails = AccountLoanDetails(
        loanKind: _loanKind,
        principal: Money(amountMinor: principalMinor, currency: _currency),
        repaymentAmount: emiMinor <= 0
            ? null
            : Money(amountMinor: emiMinor, currency: _currency),
        interestRatePercent: rate,
        repaymentCount: tenure,
        repaymentStartsOn: _nextEmiDate,
        repaymentSourceAccountId: _sourceAccountId,
        recurrenceFrequency: _frequency,
        recurrenceInterval: _interval,
        recurrenceDaysOfWeek: _daysOfWeek.isEmpty
            ? null
            : (List<int>.from(_daysOfWeek)..sort()),
        recurrenceDaysOfMonth: _daysOfMonth.isEmpty
            ? null
            : (List<int>.from(_daysOfMonth)..sort()),
        recurrenceEndDate: existingLoan?.loanDetails?.recurrenceEndDate,
        recurrenceLimit: existingLoan?.loanDetails?.recurrenceLimit,
        hideInterestInLedger: _hideInterestInLedger,
      );
      int transactionsSum = 0;
      if (existingLoan != null) {
        final balance = accountBalance(state, existingLoan).amountMinor;
        transactionsSum = balance - existingLoan.openingBalance.amountMinor;
      }
      final newOpeningBalanceMinor =
          -effectiveCurrentBalanceMinor - transactionsSum;

      final loan = await ref
          .read(ledgerProvider.notifier)
          .upsertAccount(
            id: existingLoan?.id,
            name: name,
            type: _loanKind,
            currency: _currency,
            openingBalanceMinor: newOpeningBalanceMinor,
            institution: _lenderController.text,
            groupName: _nonLoanGroupName(existingLoan?.groupName),
            loanDetails: loanDetails,
            includeInTotals: existingLoan?.includeInTotals ?? false,
            includeInReports: existingLoan?.includeInReports ?? true,
            includeInNetWorth: existingLoan?.includeInNetWorth ?? true,
            showOnHome: existingLoan?.showOnHome ?? false,
            isArchived: existingLoan?.isArchived ?? false,
          );
      if (emiMinor > 0 && sourceAccount != null) {
        final latestState = ref.read(ledgerProvider);
        final existingEmi = _existingLoanEmi(latestState, loan.id);
        await ref
            .read(ledgerProvider.notifier)
            .upsertTransaction(
              id: existingEmi?.id,
              type: 'loan_repayment',
              accountId: sourceAccount.id,
              counterAccountId: loan.id,
              amountMinor: emiMinor,
              status: 'scheduled',
              source: 'recurring',
              categoryId: _firstCategoryId(latestState, preferred: 'emi'),
              paymentMethod: 'Auto debit',
              notes: 'Scheduled EMI for ${loan.name}',
              occurredAt: _nextEmiDate,
              recurrenceFrequency: _frequency,
              recurrenceInterval: _interval,
              recurrenceDaysOfWeek: _daysOfWeek.isEmpty
                  ? null
                  : (List<int>.from(_daysOfWeek)..sort()),
              recurrenceDaysOfMonth: _daysOfMonth.isEmpty
                  ? null
                  : (List<int>.from(_daysOfMonth)..sort()),
            );
      } else {
        final latestState = ref.read(ledgerProvider);
        final existingEmi = _existingLoanEmi(latestState, loan.id);
        if (existingEmi != null) {
          await ref
              .read(ledgerProvider.notifier)
              .deleteTransaction(existingEmi.id);
        }
      }
      if (!mounted) return;
      _showRouteMessage(
        context,
        existingLoan == null ? 'Loan created.' : 'Loan saved.',
      );
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/loans');
      }
    } catch (error) {
      if (!mounted) return;
      _showRouteMessage(context, error.toString());
    }
  }
}

class LoanDetailView extends ConsumerWidget {
  const LoanDetailView({required this.loan, super.key});

  final Account loan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ledgerProvider);
    final balance = accountBalance(state, loan);
    final nextEmi = _existingLoanEmi(state, loan.id);
    final details = _effectiveLoanDetails(state, loan);
    final projection = _loanProjection(state, loan);
    final repaymentHistory = _loanHistoryRepayments(state, loan.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconBubble(
                      icon: Icons.account_balance_rounded,
                      color: Theme.of(context).colorScheme.primary,
                      compact: true,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            loan.name,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'LOAN ACCOUNT',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      formatMoney(
                        balance.copyWith(
                          amountMinor: balance.amountMinor.abs(),
                        ),
                        state.preferences.locale,
                      ),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                if (details.principal != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Builder(
                    builder: (context) {
                      final principal = details.principal!.amountMinor.abs();
                      final paid = repaymentHistory
                          .where((r) => r.status != 'void')
                          .fold<int>(
                            0,
                            (sum, r) => sum + r.amount.amountMinor.abs(),
                          );
                      final progress = principal > 0
                          ? (paid / principal).clamp(0.0, 1.0)
                          : 0.0;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Paid: ${formatMoney(Money(amountMinor: paid, currency: loan.currency), state.preferences.locale)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (projection.monthsRemaining != null)
                                Text(
                                  '${projection.monthsRemaining} mos left',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        const Gap(AppSpacing.lg),

        // Metadata Grid
        Row(
          children: [
            Expanded(
              child: MetricTile(
                label: 'Next EMI',
                value: _nextEmiLabel(state, details, nextEmi),
                icon: Icons.event_repeat_rounded,
                tone: projection.monthlyEmi <= 0
                    ? MetricTone.warning
                    : MetricTone.danger,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: MetricTile(
                label: 'Est. Payoff',
                value: projection.payoffLabel,
                icon: Icons.timeline_rounded,
                tone: MetricTone.standard,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: MetricTile(
                label: 'Interest Rate',
                value: details.interestRatePercent != null
                    ? '${_formatOptionalDecimal(details.interestRatePercent)}% p.a.'
                    : 'N/A',
                icon: Icons.percent_rounded,
                tone: MetricTone.standard,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: MetricTile(
                label: 'Tenure',
                value: details.repaymentCount != null
                    ? '${details.repaymentCount} mo'
                    : 'N/A',
                icon: Icons.timelapse_rounded,
                tone: MetricTone.standard,
              ),
            ),
          ],
        ),
        const Gap(AppSpacing.xl),

        // Action Buttons
        FilledButton.icon(
          onPressed: () => context.push('/loans/${loan.id}/edit'),
          icon: const Icon(Icons.edit_rounded),
          label: const Text('Edit loan details'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
          ),
        ),
        const Gap(AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => context.push('/loans/forecast'),
                icon: const Icon(Icons.show_chart_rounded),
                label: const Text('Forecast'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _confirmArchiveLoan(context, ref, loan),
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Archive'),
              ),
            ),
          ],
        ),
        const Gap(AppSpacing.xxl),

        // Repayment History
        SectionCard(
          title: 'Repayment history',
          subtitle: repaymentHistory.isEmpty
              ? 'Posted EMI and repayment entries will appear here.'
              : '${repaymentHistory.length} posted repayments',
          child: repaymentHistory.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No repayment history yet',
                  body:
                      'Once repayments are posted, this loan will show the real timeline here.',
                )
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < repaymentHistory.length;
                      index++
                    ) ...[
                      TransactionRow(
                        state: state,
                        transaction: repaymentHistory[index],
                        onTap: () => context.push(
                          '/transaction/${repaymentHistory[index].id}',
                        ),
                      ),
                      if (index != repaymentHistory.length - 1)
                        const SizedBox(height: AppSpacing.xxs),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _confirmArchiveLoan(
    BuildContext context,
    WidgetRef ref,
    Account loan,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive loan?'),
        content: const Text(
          'This hides the loan if linked transactions exist, or removes it if unused.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(ledgerProvider.notifier).deleteAccount(loan.id);
    if (!context.mounted) return;
    _showRouteMessage(context, 'Loan archived.');
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/loans');
    }
  }
}

class _LoanCompactCard extends StatelessWidget {
  const _LoanCompactCard({
    required this.state,
    required this.loan,
    required this.mode,
    required this.onTap,
  });

  final LedgerState state;
  final Account loan;
  final String mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final balance = accountBalance(state, loan);
    final details = _effectiveLoanDetails(state, loan);
    final projection = _loanProjection(state, loan);
    final repayments = _postedLoanRepayments(state, loan.id);
    final nextEmi = _existingLoanEmi(state, loan.id);
    final scheduleDate = nextEmi?.occurredAt ?? details.repaymentStartsOn;
    final status = _scheduleStatus(
      context,
      scheduleDate,
      locale: state.preferences.locale,
      historyMode: mode == 'past',
    );
    final scheme = Theme.of(context).colorScheme;
    final cadence = _loanCadenceLabel(details);
    final cadenceSummary = [
      cadence,
      if (details.repaymentCount != null) 'for ${details.repaymentCount} times',
      if (mode == 'past' && repayments.isNotEmpty)
        '${repayments.length} repayments',
    ].join(' · ');
    final primaryTitle = loan.institution ?? accountTypeLabel(loan.type);
    final tertiaryLine = loan.institution != null
        ? '"${loan.institution}"'
        : null;
    final rightAmount = details.repaymentAmount != null
        ? details.repaymentAmount!
        : balance.copyWith(amountMinor: balance.amountMinor.abs());
    final rightAmountText = _formatSignedMoney(
      rightAmount,
      negative: mode != 'past',
      locale: state.preferences.locale,
    );

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      loan.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(status.icon, color: status.color, size: 26),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RoundTileIcon(
                    icon: accountIcon(loan),
                    color: loan.color ?? scheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          primaryTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          cadenceSummary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                        if (tertiaryLine != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            tertiaryLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                              fontSize: 13,
                            ),
                          ),
                        ],
                        if (mode == 'past') ...[
                          const SizedBox(height: 6),
                          Text(
                            projection.payoffLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        rightAmountText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: mode == 'past'
                                  ? scheme.onSurface
                                  : scheme.error,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        status.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: status.color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (details.principal != null) ...[
                const SizedBox(height: AppSpacing.md),
                Builder(
                  builder: (context) {
                    final principal = details.principal!.amountMinor.abs();
                    final paid = repayments
                        .where((r) => r.status != 'void')
                        .fold<int>(
                          0,
                          (sum, r) => sum + r.amount.amountMinor.abs(),
                        );
                    final progress = principal > 0
                        ? (paid / principal).clamp(0.0, 1.0)
                        : 0.0;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Paid: ${formatMoney(Money(amountMinor: paid, currency: loan.currency), state.preferences.locale)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (projection.monthsRemaining != null)
                              Text(
                                '${projection.monthsRemaining} mos left',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: progress,
                          backgroundColor: scheme.surfaceContainerHighest,
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundTileIcon extends StatelessWidget {
  const _RoundTileIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = color.computeLuminance() > 0.5
        ? scheme.onSurface
        : scheme.surface;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, color: foreground, size: 28),
    );
  }
}

class NumberedDotPainter extends FlDotPainter {
  final String label;
  final Color color;
  final Color textColor;
  final double radius;

  NumberedDotPainter(this.label, {this.color = Colors.green, this.textColor = Colors.white, this.radius = 10});

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) {
    final paint = Paint()..color = color;
    canvas.drawCircle(offsetInCanvas, radius, paint);

    final textSpan = TextSpan(
      text: label,
      style: TextStyle(color: textColor, fontSize: radius * 1.2, fontWeight: FontWeight.bold),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        offsetInCanvas.dx - textPainter.width / 2,
        offsetInCanvas.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  Size getSize(FlSpot spot) {
    return Size(radius * 2, radius * 2);
  }

  @override
  Color get mainColor => color;

  @override
  FlDotPainter lerp(FlDotPainter a, FlDotPainter b, double t) {
    return this; 
  }
  
  @override
  List<Object?> get props => [label, color, textColor, radius];
}

class DynamicForecastLineChart extends StatefulWidget {
  final List<FlSpot> spots;
  final double chartWidth;
  final Color lineColor;
  final List<dynamic> balanceCurve;
  final String locale;
  final Map<double, String> payoffDots;
  final String currencySymbol;

  const DynamicForecastLineChart({
    super.key,
    required this.spots,
    required this.chartWidth,
    required this.lineColor,
    required this.balanceCurve,
    required this.locale,
    required this.payoffDots,
    required this.currencySymbol,
  });

  @override
  State<DynamicForecastLineChart> createState() => _DynamicForecastLineChartState();
}

class _DynamicForecastLineChartState extends State<DynamicForecastLineChart> {
  double _currentMinX = 0;
  double _currentMaxX = 100;
  double _currentMinY = 0;
  double _currentMaxY = 100;
  
  double _zoomPercent = 0.5;

  @override
  void initState() {
    super.initState();
    _initBounds();
  }

  void _initBounds() {
    if (widget.spots.isNotEmpty) {
      final firstX = widget.spots.first.x;
      final lastX = widget.spots.last.x;
      final totalRange = lastX - firstX;
      
      final initialRange = (totalRange / 3.0).clamp(30.0, totalRange);
      
      _currentMinX = firstX;
      _currentMaxX = firstX + initialRange;
      if (_currentMaxX > lastX) _currentMaxX = lastX;
      
      _zoomPercent = totalRange > 0 ? 1.0 - (initialRange / totalRange) : 0.0;
      if (_zoomPercent < 0) _zoomPercent = 0;
      if (_zoomPercent > 1) _zoomPercent = 1;
      
      _updateYLimits();
    }
  }

  @override
  void didUpdateWidget(DynamicForecastLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spots != widget.spots) {
       WidgetsBinding.instance.addPostFrameCallback((_) {
         setState(() => _updateYLimits());
       });
    }
  }

  void _updateYLimits() {
    if (widget.spots.isEmpty) return;
    
    double minY = double.infinity;
    double maxY = double.negativeInfinity;
    
    for (final spot in widget.spots) {
      if (spot.x >= _currentMinX && spot.x <= _currentMaxX) {
        if (spot.y < minY) minY = spot.y;
        if (spot.y > maxY) maxY = spot.y;
      }
    }
    
    if (minY == double.infinity) {
      minY = 0;
      maxY = 100;
    }
    
    if (minY == maxY) {
      minY -= 50;
      maxY += 50;
    }
    
    final range = maxY - minY;
    minY -= range * 0.1;
    maxY += range * 0.1;
    
    _currentMinY = minY;
    _currentMaxY = maxY;
  }

  void _onSliderChange(double val) {
    if (widget.spots.isEmpty) return;
    final totalRange = widget.spots.last.x - widget.spots.first.x;
    if (totalRange <= 0) return;
    
    setState(() {
      _zoomPercent = val;
      final minRange = 30.0;
      final newRange = minRange + (1.0 - val) * (totalRange - minRange);
      
      final center = (_currentMinX + _currentMaxX) / 2;
      _currentMinX = center - newRange / 2;
      _currentMaxX = center + newRange / 2;
      
      if (_currentMinX < widget.spots.first.x) {
        _currentMinX = widget.spots.first.x;
        _currentMaxX = _currentMinX + newRange;
      }
      if (_currentMaxX > widget.spots.last.x) {
        _currentMaxX = widget.spots.last.x;
        _currentMinX = _currentMaxX - newRange;
      }
      
      _updateYLimits();
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (widget.spots.isEmpty) return;
    
    final width = context.size?.width ?? 300;
    final range = _currentMaxX - _currentMinX;
    final deltaX = -(details.delta.dx / width) * range;
    
    setState(() {
      _currentMinX += deltaX;
      _currentMaxX += deltaX;
      
      if (_currentMinX < widget.spots.first.x) {
        final diff = widget.spots.first.x - _currentMinX;
        _currentMinX += diff;
        _currentMaxX += diff;
      }
      if (_currentMaxX > widget.spots.last.x) {
        final diff = _currentMaxX - widget.spots.last.x;
        _currentMinX -= diff;
        _currentMaxX -= diff;
      }
      
      _updateYLimits();
    });
  }

  double get _xInterval {
    final range = _currentMaxX - _currentMinX;
    if (range <= 0) return 1;
    final idealCount = 4.0;
    final interval = (range / idealCount).ceilToDouble();
    return interval < 1 ? 1 : interval;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.spots.isEmpty) return const SizedBox.shrink();
    
    double yInterval = ((_currentMaxY - _currentMinY) / 5).roundToDouble();
    if (yInterval < 1) yInterval = 1;

    final numberFormat = NumberFormat.compactCurrency(locale: widget.locale, symbol: widget.currencySymbol);

    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onHorizontalDragUpdate: _onPanUpdate,
            child: Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 8.0, right: 16.0),
              child: LineChart(
                LineChartData(
                  minY: _currentMinY,
                  maxY: _currentMaxY,
                  minX: _currentMinX,
                  maxX: _currentMaxX,
                  clipData: const FlClipData.all(),
                  lineTouchData: LineTouchData(
                    enabled: true,
                    handleBuiltInTouches: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (spot) => Theme.of(context).colorScheme.surfaceContainerHigh,
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final now = DateTime.now();
                          final today = DateTime(now.year, now.month, now.day);
                          final date = today.add(Duration(days: spot.x.toInt()));
                          final dateStr = DateFormat('dd MMM yyyy').format(date);
                          
                          final amt = NumberFormat.decimalPattern(widget.locale).format(spot.y);
                          final moneyStr = '${widget.currencySymbol}$amt';
                          
                          return LineTooltipItem(
                            '$moneyStr\n',
                            TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                            children: [
                              TextSpan(
                                text: dateStr,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontSize: 10,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ],
                          );
                        }).toList();
                      },
                    ),
                  ),
                  extraLinesData: ExtraLinesData(
                    verticalLines: [
                      VerticalLine(
                        x: 0,
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                        strokeWidth: 2,
                        dashArray: [5, 5],
                        label: VerticalLineLabel(
                          show: true,
                          alignment: Alignment.bottomRight,
                          padding: const EdgeInsets.only(bottom: 24, left: 4),
                          style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
                          labelResolver: (_) => "Today",
                        ),
                      ),
                      ...widget.payoffDots.keys.map((x) {
                          final now = DateTime.now();
                          final today = DateTime(now.year, now.month, now.day);
                          final date = today.add(Duration(days: x.toInt()));
                          final dateStr = DateFormat('dd MMM yy').format(date);
                          
                          return VerticalLine(
                            x: x,
                            color: Colors.green.withValues(alpha: 0.5),
                            strokeWidth: 1,
                            dashArray: [3, 3],
                            label: VerticalLineLabel(
                              show: true,
                              alignment: Alignment.bottomRight,
                              padding: const EdgeInsets.only(bottom: 4, left: 4),
                              style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                              labelResolver: (_) => dateStr,
                            ),
                          );
                      }),
                    ],
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: widget.spots,
                      isCurved: true,
                      color: widget.lineColor,
                      barWidth: 4,
                      shadow: BoxShadow(
                        color: widget.lineColor.withValues(alpha: 0.5),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            widget.lineColor.withValues(alpha: 0.5),
                            widget.lineColor.withValues(alpha: 0.0),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      dotData: FlDotData(
                        show: true,
                        checkToShowDot: (spot, barData) => widget.payoffDots.containsKey(spot.x),
                        getDotPainter: (spot, percent, barData, index) {
                          final label = widget.payoffDots[spot.x];
                          if (label != null) {
                            return NumberedDotPainter(label);
                          }
                          return FlDotCirclePainter(radius: 0, color: Colors.transparent);
                        },
                      ),
                    ),
                  ],
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: _xInterval,
                        getTitlesWidget: (value, meta) {
                          final now = DateTime.now();
                          final today = DateTime(now.year, now.month, now.day);
                          final date = today.add(Duration(days: value.toInt()));
                          
                          final range = _currentMaxX - _currentMinX;
                          String dateStr;
                          if (range <= 60) {
                            dateStr = DateFormat('dd MMM').format(date);
                          } else if (range <= 365) {
                            dateStr = DateFormat('MMM yy').format(date);
                          } else {
                            dateStr = DateFormat('yyyy').format(date);
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(dateStr, style: const TextStyle(fontSize: 10)),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        interval: yInterval,
                        getTitlesWidget: (value, meta) {
                           return Padding(
                             padding: const EdgeInsets.only(right: 8.0),
                             child: Text(
                               numberFormat.format(value), 
                               textAlign: TextAlign.right,
                               style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                             ),
                           );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true, 
                    drawVerticalLine: true,
                    verticalInterval: _xInterval,
                    horizontalInterval: yInterval,
                  ),
                  borderData: FlBorderData(show: false),
                ),
                duration: Duration.zero,
              ),
            ),
          ),
        ),
        Row(
          children: [
            const Icon(Icons.zoom_out, size: 20, color: Colors.grey),
            Expanded(
              child: Slider(
                value: _zoomPercent,
                min: 0.0,
                max: 1.0,
                onChanged: _onSliderChange,
              ),
            ),
            const Icon(Icons.zoom_in, size: 20, color: Colors.grey),
          ],
        ),
      ],
    );
  }
}
class DynamicForecastBarChart extends StatefulWidget {
  final List<BarChartGroupData> barGroups;
  final double chartWidth;
  final List<DateTime> timeKeys;
  final String locale;
  final String currencySymbol;

  const DynamicForecastBarChart({
    super.key,
    required this.barGroups,
    required this.chartWidth,
    required this.timeKeys,
    required this.locale,
    required this.currencySymbol,
  });

  @override
  State<DynamicForecastBarChart> createState() => _DynamicForecastBarChartState();
}

class _DynamicForecastBarChartState extends State<DynamicForecastBarChart> {
  double _currentMinX = 0;
  double _currentMaxX = 100;
  double _currentMinY = 0;
  double _currentMaxY = 100;
  
  double _zoomPercent = 0.5;

  @override
  void initState() {
    super.initState();
    _initBounds();
  }

  void _initBounds() {
    if (widget.barGroups.isNotEmpty) {
      final totalRange = widget.barGroups.length - 1.0;
      
      final initialRange = (totalRange / 3.0).clamp(4.0, totalRange);
      
      _currentMinX = 0;
      _currentMaxX = initialRange;
      if (_currentMaxX > totalRange) _currentMaxX = totalRange;
      
      _zoomPercent = totalRange > 0 ? 1.0 - (initialRange / totalRange) : 0.0;
      if (_zoomPercent < 0) _zoomPercent = 0;
      if (_zoomPercent > 1) _zoomPercent = 1;
      
      _updateYLimits();
    }
  }

  @override
  void didUpdateWidget(DynamicForecastBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.barGroups != widget.barGroups) {
       WidgetsBinding.instance.addPostFrameCallback((_) {
         setState(() => _updateYLimits());
       });
    }
  }

  void _updateYLimits() {
    if (widget.barGroups.isEmpty) return;
    
    double minY = double.infinity;
    double maxY = double.negativeInfinity;
    
    for (int i = 0; i < widget.barGroups.length; i++) {
      if (i >= _currentMinX - 1 && i <= _currentMaxX + 1) {
        final group = widget.barGroups[i];
        if (group.barRods.isNotEmpty) {
          final y = group.barRods.first.toY;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    
    if (minY == double.infinity) {
      minY = 0;
      maxY = 100;
    }
    if (minY == maxY) {
      minY -= 50;
      maxY += 50;
    }
    
    final range = maxY - minY;
    minY -= range * 0.1;
    maxY += range * 0.1;
    
    _currentMinY = minY;
    _currentMaxY = maxY;
  }

  void _onSliderChange(double val) {
    if (widget.barGroups.isEmpty) return;
    final totalRange = widget.barGroups.length - 1.0;
    if (totalRange <= 0) return;
    
    setState(() {
      _zoomPercent = val;
      final minRange = 4.0;
      final newRange = minRange + (1.0 - val) * (totalRange - minRange);
      
      final center = (_currentMinX + _currentMaxX) / 2;
      _currentMinX = center - newRange / 2;
      _currentMaxX = center + newRange / 2;
      
      if (_currentMinX < 0) {
        _currentMinX = 0;
        _currentMaxX = _currentMinX + newRange;
      }
      if (_currentMaxX > totalRange) {
        _currentMaxX = totalRange;
        _currentMinX = _currentMaxX - newRange;
      }
      
      _updateYLimits();
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (widget.barGroups.isEmpty) return;
    
    final width = context.size?.width ?? 300;
    final range = _currentMaxX - _currentMinX;
    final deltaX = -(details.delta.dx / width) * range;
    
    setState(() {
      _currentMinX += deltaX;
      _currentMaxX += deltaX;
      
      final totalRange = widget.barGroups.length - 1.0;
      
      if (_currentMinX < 0) {
        final diff = 0 - _currentMinX;
        _currentMinX += diff;
        _currentMaxX += diff;
      }
      if (_currentMaxX > totalRange) {
        final diff = _currentMaxX - totalRange;
        _currentMinX -= diff;
        _currentMaxX -= diff;
      }
      
      _updateYLimits();
    });
  }

  double get _xInterval {
    final range = _currentMaxX - _currentMinX;
    if (range <= 0) return 1;
    final idealCount = 4.0;
    final interval = (range / idealCount).ceilToDouble();
    return interval < 1 ? 1 : interval;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.barGroups.isEmpty) return const SizedBox.shrink();
    
    double yInterval = ((_currentMaxY - _currentMinY) / 5).roundToDouble();
    if (yInterval < 1) yInterval = 1;

    final numberFormat = NumberFormat.compactCurrency(locale: widget.locale, symbol: widget.currencySymbol);

    final visibleGroups = widget.barGroups.where((g) => g.x >= _currentMinX.floor() && g.x <= _currentMaxX.ceil()).toList();
    
    final widthAvailable = MediaQuery.of(context).size.width - 64;
    final visibleCount = visibleGroups.length;
    double dynamicBarWidth = visibleCount > 0 ? (widthAvailable / visibleCount) * 0.5 : 12.0;
    if (dynamicBarWidth > 20) dynamicBarWidth = 20;
    if (dynamicBarWidth < 2) dynamicBarWidth = 2;
    
    final updatedVisibleGroups = visibleGroups.map((g) {
      final oldRod = g.barRods.first;
      return BarChartGroupData(
        x: g.x,
        barRods: [
          oldRod.copyWith(width: dynamicBarWidth),
        ],
      );
    }).toList();

    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onHorizontalDragUpdate: _onPanUpdate,
            child: Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 8.0, right: 16.0),
              child: BarChart(
                BarChartData(
                  minY: _currentMinY,
                  maxY: _currentMaxY,
                  barGroups: updatedVisibleGroups,
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        interval: _xInterval,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx >= 0 && idx < widget.timeKeys.length) {
                            final date = widget.timeKeys[idx];
                            final range = _currentMaxX - _currentMinX;
                            String str;
                            if (range <= 12) {
                              str = DateFormat('dd MMM').format(date);
                            } else if (range <= 52) {
                              str = DateFormat('MMM yy').format(date);
                            } else {
                              str = DateFormat('yyyy').format(date);
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(str, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        interval: yInterval,
                        getTitlesWidget: (value, meta) {
                           return Padding(
                             padding: const EdgeInsets.only(right: 8.0),
                             child: Text(
                               numberFormat.format(value), 
                               textAlign: TextAlign.right,
                               style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                             ),
                           );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true, 
                    drawVerticalLine: false,
                    horizontalInterval: yInterval,
                  ),
                  borderData: FlBorderData(show: false),
                ),
                duration: Duration.zero,
              ),
            ),
          ),
        ),
        Row(
          children: [
            const Icon(Icons.zoom_out, size: 20, color: Colors.grey),
            Expanded(
              child: Slider(
                value: _zoomPercent,
                min: 0.0,
                max: 1.0,
                onChanged: _onSliderChange,
              ),
            ),
            const Icon(Icons.zoom_in, size: 20, color: Colors.grey),
          ],
        ),
      ],
    );
  }
}

class LoanForecastView extends ConsumerStatefulWidget {
  const LoanForecastView({required this.state, required this.loans, super.key});

  final LedgerState state;
  final List<Account> loans;

  @override
  ConsumerState<LoanForecastView> createState() => _LoanForecastViewState();
}

class _LoanForecastViewState extends ConsumerState<LoanForecastView> {
  late final TextEditingController _emergencyController;
  late double _extraAllocationPercent;
  late List<Account> _priorityLoans;

  void _syncPriorityLoans() {
    final prefs = widget.state.preferences;
    _priorityLoans = List.from(widget.loans);
    
    final savedOrder = prefs.loanPriorityIds;
    _priorityLoans.sort((a, b) {
      final aIndex = savedOrder.indexOf(a.id);
      final bIndex = savedOrder.indexOf(b.id);
      if (aIndex != -1 && bIndex != -1) {
        return aIndex.compareTo(bIndex);
      }
      if (aIndex != -1) return -1;
      if (bIndex != -1) return 1;

      final aRate = a.loanDetails?.interestRatePercent ?? 0;
      final bRate = b.loanDetails?.interestRatePercent ?? 0;
      return bRate.compareTo(aRate);
    });
  }

  @override
  void initState() {
    super.initState();
    final prefs = widget.state.preferences;
    _emergencyController = TextEditingController(text: (prefs.forecastEmergencyCashMinor / 100).toInt().toString());
    _extraAllocationPercent = prefs.forecastExtraAllocationPercent;
    _syncPriorityLoans();
  }

  @override
  void didUpdateWidget(LoanForecastView oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    final currentIds = _priorityLoans.map((l) => l.id).toSet();
    final newIds = widget.loans.map((l) => l.id).toSet();
    
    bool needsSync = false;
    
    if (currentIds.length != newIds.length || !currentIds.containsAll(newIds)) {
      needsSync = true;
    }
    
    final savedOrder = widget.state.preferences.loanPriorityIds;
    if (!needsSync && savedOrder.length == _priorityLoans.length) {
      for (int i = 0; i < savedOrder.length; i++) {
        if (savedOrder[i] != _priorityLoans[i].id) {
          needsSync = true;
          break;
        }
      }
    } else if (savedOrder.length != _priorityLoans.length) {
      needsSync = true;
    }
    
    if (needsSync) {
      _syncPriorityLoans();
    } else {
      final newLoansMap = { for (var l in widget.loans) l.id : l };
      for (int i = 0; i < _priorityLoans.length; i++) {
        if (newLoansMap.containsKey(_priorityLoans[i].id)) {
          _priorityLoans[i] = newLoansMap[_priorityLoans[i].id]!;
        }
      }
    }
  }

  @override
  void dispose() {
    _emergencyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loans.isEmpty) {
      return const EmptyState(
        icon: Icons.account_balance_outlined,
        title: 'No loans yet',
        body: 'Create a loan account to see payoff projections.',
      );
    }

    final emergencyMinor = _amountMinorFromInput(_emergencyController.text).abs();

    final activeLoans = widget.loans.map((loan) {
      final details = _effectiveLoanDetails(widget.state, loan);
      final emi = details.repaymentAmount?.amountMinor.abs() ?? _existingLoanEmi(widget.state, loan.id)?.amount.amountMinor.abs() ?? 0;
      final rate = details.interestRatePercent ?? 0;
      final remaining = accountBalance(widget.state, loan).amountMinor.abs();
      return ActiveLoan(
        account: loan,
        principalMinor: remaining,
        monthlyEmiMinor: emi,
        annualRatePercent: rate,
      );
    }).toList();

    final result = simulateForecastPayoffGraph(
      state: widget.state,
      activeLoans: activeLoans,
      emergencySavingMinor: emergencyMinor,
      extraPaymentAllocationPercent: _extraAllocationPercent,
      loanPriorityIds: _priorityLoans.map((l) => l.id).toList(),
    );

    final locale = widget.state.preferences.locale;
    final scheme = Theme.of(context).colorScheme;
    final currencyFormat = NumberFormat.simpleCurrency(locale: locale, name: widget.state.preferences.displayCurrency);
    final currencySymbol = currencyFormat.currencySymbol;

    final spots = <FlSpot>[];
    final now = DateTime.now();
    final todayMillis = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch.toDouble();
    
    for (int i = 0; i < result.balanceCurve.length; i++) {
      final pt = result.balanceCurve[i];
      final x = (pt.date.millisecondsSinceEpoch - todayMillis) / 86400000.0;
      final y = pt.netBalanceMinor / 100.0;
      spots.add(FlSpot(x, y));
    }
    
    if (spots.isEmpty) {
      spots.add(const FlSpot(0, 0));
    }
    
    final lineChartWidth = math.max(MediaQuery.of(context).size.width - 64, spots.length * 1.5);

    final weeklyBalances = <DateTime, double>{};
    if (result.balanceCurve.isNotEmpty) {
      for (final pt in result.balanceCurve) {
        final daysSinceMonday = pt.date.weekday - 1; 
        final weekStart = pt.date.subtract(Duration(days: daysSinceMonday));
        final weekKey = DateTime(weekStart.year, weekStart.month, weekStart.day);
        weeklyBalances[weekKey] = pt.netBalanceMinor / 100.0;
      }
    }
    
    final barGroups = <BarChartGroupData>[];
    int weekIndex = 0;
    for (final entry in weeklyBalances.entries) {
      final y = entry.value;
      barGroups.add(
        BarChartGroupData(
          x: weekIndex,
          barRods: [
            BarChartRodData(
              toY: y,
              color: y >= 0 ? scheme.primary : scheme.error,
              width: 12,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
      weekIndex++;
    }
    
    final weekKeys = weeklyBalances.keys.toList();
    final barChartWidth = math.max(MediaQuery.of(context).size.width - 64, weekKeys.length * 24.0);

    final loanNumberMap = <String, int>{};
    for (int i = 0; i < _priorityLoans.length; i++) {
      loanNumberMap[_priorityLoans[i].id] = i + 1;
    }
    
    final payoffDots = <double, String>{};
    for (final event in result.payoffEvents) {
      final eventX = (event.payoffDate.millisecondsSinceEpoch - todayMillis) / 86400000.0;
      final number = loanNumberMap[event.loan.id]?.toString() ?? '';
      
      double closestX = 0;
      double minDiff = double.infinity;
      for (final spot in spots) {
        final diff = (spot.x - eventX).abs();
        if (diff < minDiff) {
          minDiff = diff;
          closestX = spot.x;
        }
      }
      
      if (payoffDots.containsKey(closestX)) {
        payoffDots[closestX] = '${payoffDots[closestX]},$number';
      } else {
        payoffDots[closestX] = number;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (result.impact.interestSavedMinor > 0 || result.impact.monthsSaved > 0)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.tertiary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bolt, color: Colors.white, size: 28),
                    const SizedBox(width: 8),
                    Text(
                      'Accelerated Impact',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'You could save ${formatMoney(Money(amountMinor: result.impact.interestSavedMinor, currency: widget.state.preferences.baseCurrency), locale)} in interest and finish ${result.impact.monthsSaved} months early!',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                ),
              ],
            ),
          ),
        SectionCard(
          title: 'Payoff Simulation',
          subtitle: 'Adjust your emergency fund and extra cash allocation to see the payoff graph.',
          child: Column(
            children: [
              TextFormField(
                controller: _emergencyController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  ThousandsSeparatorInputFormatter(widget.state.preferences.locale)
                ],
                decoration: InputDecoration(
                  labelText: 'Emergency Cash to keep',
                  prefixText: currencySymbol,
                  prefixIcon: const Icon(Icons.savings_outlined),
                ),
                onChanged: (val) {
                  final newMinor = _amountMinorFromInput(val).abs();
                  ref.read(ledgerProvider.notifier).updatePreferences(
                    widget.state.preferences.copyWith(forecastEmergencyCashMinor: newMinor),
                  );
                  setState(() {});
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Extra Cash Allocation',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '${(_extraAllocationPercent * 100).toInt()}% to priority loans',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _extraAllocationPercent,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    onChangeEnd: (val) {
                      ref.read(ledgerProvider.notifier).updatePreferences(
                        widget.state.preferences.copyWith(forecastExtraAllocationPercent: val),
                      );
                    },
                    onChanged: (val) {
                      setState(() => _extraAllocationPercent = val);
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '0% (Base EMI only)',
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                      Text(
                        '100% (Aggressive)',
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const Gap(AppSpacing.lg),
        
        SectionCard(
          title: 'Projected Liquid Cash',
          subtitle: 'Includes past actuals and future projections. Watch the balance plummet when a loan pays off!',
          child: SizedBox(
            height: 380,
            child: DynamicForecastLineChart(
              spots: spots,
              chartWidth: lineChartWidth,
              lineColor: scheme.primary,
              balanceCurve: result.balanceCurve,
              locale: locale,
              payoffDots: payoffDots,
              currencySymbol: currencySymbol,
            ),
          ),
        ),
        
        const Gap(AppSpacing.lg),
        
        SectionCard(
          title: 'Weekly Calendar View',
          subtitle: 'End-of-week projected liquid cash over time.',
          child: SizedBox(
            height: 380,
            child: DynamicForecastBarChart(
              barGroups: barGroups,
              chartWidth: barChartWidth,
              timeKeys: weekKeys,
              locale: locale,
              currencySymbol: currencySymbol,
            ),
          ),
        ),
        
        const Gap(AppSpacing.lg),
        
        SectionCard(
          title: 'Payoff Priority & Timeline',
          subtitle: 'Drag and drop to change priority. The timeline reflects exactly when each loan pays off.',
          child: ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (oldIndex < newIndex) {
                  newIndex -= 1;
                }
                final item = _priorityLoans.removeAt(oldIndex);
                _priorityLoans.insert(newIndex, item);
              });
              final newOrder = _priorityLoans.map((l) => l.id).toList();
              // Important: Delay updatePreferences slightly so the ReorderableListView finishes its animation
              // before the parent triggers a rebuild with the new state.
              Future.delayed(const Duration(milliseconds: 50), () {
                if (mounted) {
                  ref.read(ledgerProvider.notifier).updatePreferences(
                    widget.state.preferences.copyWith(loanPriorityIds: newOrder),
                  );
                }
              });
            },
            children: _priorityLoans.asMap().entries.map((entry) {
              final index = entry.key;
              final loan = entry.value;
              final event = result.payoffEvents.firstWhereOrNull((e) => e.loan.id == loan.id);
              final payoffStr = event != null ? ' · Pays off ${formatLedgerDate(event.payoffDate, locale)}' : '';
              final balStr = formatMoney(accountBalance(widget.state, loan), locale);

              return ListTile(
                key: ValueKey(loan.id),
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: const Icon(Icons.drag_handle),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.green,
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                title: Text(loan.name),
                subtitle: Text('$balStr$payoffStr'),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
TransactionRecord? _existingLoanEmi(LedgerState state, String? loanId) {
  if (loanId == null) return null;
  final matches =
      scheduledTransactions(state)
          .where(
            (transaction) =>
                transaction.type == 'loan_repayment' &&
                transaction.counterAccountId == loanId,
          )
          .toList()
        ..sort((left, right) => left.occurredAt.compareTo(right.occurredAt));
  return matches.isEmpty ? null : matches.first;
}

List<TransactionRecord> _postedLoanRepayments(
  LedgerState state,
  String loanId,
) {
  return state.transactions
      .where(
        (transaction) =>
            (transaction.accountId == loanId ||
                transaction.counterAccountId == loanId) &&
            transaction.status != 'scheduled' &&
            (transaction.type == 'loan_repayment' ||
                (transaction.status == 'void' &&
                    transaction.notes?.toLowerCase() == 'skipped')),
      )
      .toList();
}

List<TransactionRecord> _loanHistoryRepayments(
  LedgerState state,
  String loanId,
) {
  final items = state.transactions
      .where(
        (transaction) =>
            (transaction.accountId == loanId ||
                transaction.counterAccountId == loanId) &&
            (transaction.status != 'scheduled' ||
                transaction.notes?.toLowerCase() == 'skipped'),
      )
      .toList();
  items.sort((left, right) => right.occurredAt.compareTo(left.occurredAt));
  return items;
}





bool _isPastLoan(LedgerState state, Account loan) {
  if (loan.isArchived) return true;
  final remaining = accountBalance(state, loan).amountMinor.abs();
  if (remaining != 0) return false;
  final principalMinor =
      loan.loanDetails?.principal?.amountMinor.abs() ??
      loan.openingBalance.amountMinor.abs();
  if (principalMinor <= 0) return false;
  return true;
}

String _loanCadenceLabel(AccountLoanDetails details) {
  if (details.repaymentAmount == null) return 'No EMI schedule';
  final n = details.recurrenceInterval < 1 ? 1 : details.recurrenceInterval;
  final unit = switch (details.recurrenceFrequency) {
    'daily' => n == 1 ? 'day' : 'days',
    'weekly' => n == 1 ? 'week' : 'weeks',
    'yearly' => n == 1 ? 'year' : 'years',
    'monthly' => n == 1 ? 'month' : 'months',
    _ => n == 1 ? 'month' : 'months',
  };
  return 'Every $n $unit';
}

({String label, IconData icon, Color color}) _scheduleStatus(
  BuildContext context,
  DateTime? date, {
  required String locale,
  required bool historyMode,
}) {
  final scheme = Theme.of(context).colorScheme;
  if (date == null) {
    return (
      label: historyMode ? 'Past loan' : 'No due date',
      icon: historyMode ? Icons.history_rounded : Icons.schedule_outlined,
      color: scheme.outline,
    );
  }
  final tone = _scheduleTone(date);
  final color = switch (tone) {
    MetricTone.danger => scheme.error,
    MetricTone.warning => scheme.secondary,
    MetricTone.positive => scheme.tertiary,
    MetricTone.standard => scheme.primary,
  };
  return (
    label: _scheduleStatusLabel(date, locale: locale, historyMode: historyMode),
    icon: historyMode
        ? Icons.history_rounded
        : tone == MetricTone.danger
        ? Icons.warning_rounded
        : Icons.history_toggle_off_rounded,
    color: color,
  );
}

MetricTone _scheduleTone(DateTime date) {
  final today = DateTime.now();
  final startToday = DateTime(today.year, today.month, today.day);
  final startDate = DateTime(date.year, date.month, date.day);
  final diff = startDate.difference(startToday).inDays;
  if (diff < 0) return MetricTone.danger;
  if (diff <= 7) return MetricTone.warning;
  return MetricTone.standard;
}

String _scheduleStatusLabel(
  DateTime date, {
  required String locale,
  required bool historyMode,
}) {
  return formatLedgerDate(date, locale);
}

String _formatSignedMoney(
  Money money, {
  required bool negative,
  required String locale,
}) {
  final sign = negative ? '-' : '';
  return '$sign${formatMoney(money.copyWith(amountMinor: money.amountMinor.abs()), locale)}';
}

AccountLoanDetails _effectiveLoanDetails(LedgerState state, Account loan) {
  final fallbackPrincipal = Money(
    amountMinor: loan.openingBalance.amountMinor.abs(),
    currency: loan.currency,
  );
  final existing = loan.loanDetails;
  if (existing != null) {
    return existing.copyWith(
      principal: existing.principal ?? fallbackPrincipal,
    );
  }
  final existingEmi = _existingLoanEmi(state, loan.id);
  return AccountLoanDetails(
    loanKind: loan.type,
    principal: fallbackPrincipal,
    repaymentAmount: existingEmi?.amount.copyWith(currency: loan.currency),
    interestRatePercent: _doubleTagValue(loan.groupName, 'rate'),
    repaymentCount: _intTagValue(loan.groupName, 'tenure'),
    repaymentStartsOn: existingEmi?.occurredAt,
    repaymentSourceAccountId: existingEmi?.accountId,
  );
}

String _nextEmiLabel(
  LedgerState state,
  AccountLoanDetails details,
  TransactionRecord? scheduledEmi,
) {
  final amount = scheduledEmi?.amount ?? details.repaymentAmount;
  final date = scheduledEmi?.occurredAt ?? details.repaymentStartsOn;
  if (amount == null && date == null) return 'Not scheduled';
  final parts = [
    if (date != null) formatLedgerDate(date, state.preferences.locale),
    if (amount != null) formatMoney(amount, state.preferences.locale),
  ];
  return parts.join(' · ');
}

String? _tagValue(String? source, String key) {
  if (source == null || source.trim().isEmpty) return null;
  for (final part in source.split('|')) {
    final separator = part.indexOf(':');
    if (separator <= 0) continue;
    final itemKey = part.substring(0, separator).trim();
    if (itemKey != key) continue;
    final value = part.substring(separator + 1).trim();
    return value.isEmpty ? null : value;
  }
  return null;
}

double? _doubleTagValue(String? source, String key) {
  final value = _tagValue(source, key);
  return value == null ? null : double.tryParse(value);
}

int? _intTagValue(String? source, String key) {
  final value = _tagValue(source, key);
  return value == null ? null : int.tryParse(value);
}

double? _optionalDouble(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return double.tryParse(trimmed);
}

int? _optionalInt(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return int.tryParse(trimmed);
}

String _formatOptionalDecimal(double? value) {
  if (value == null) return '';
  if (value == value.roundToDouble()) return value.round().toString();
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String? _nonLoanGroupName(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final parts = trimmed
      .split('|')
      .where((part) {
        final key = part.split(':').first.trim().toLowerCase();
        return key != 'rate' && key != 'tenure';
      })
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  return parts.isEmpty ? null : parts.join('|');
}

String? _firstCategoryId(LedgerState state, {String? preferred}) {
  return firstActiveCategory(state, preferred: preferred)?.id;
}

_LoanProjection _loanProjection(LedgerState state, Account loan) {
  final remaining = accountBalance(state, loan).amountMinor.abs();
  final details = _effectiveLoanDetails(state, loan);
  final emi =
      details.repaymentAmount?.amountMinor.abs() ??
      _existingLoanEmi(state, loan.id)?.amount.amountMinor.abs() ??
      0;
  final rate = details.interestRatePercent ?? 0;
  if (remaining == 0) {
    return const _LoanProjection(
      monthlyEmi: 0,
      monthsRemaining: 0,
      estimatedInterestMinor: 0,
    );
  }
  if (emi <= 0) {
    return const _LoanProjection(
      monthlyEmi: 0,
      monthsRemaining: null,
      estimatedInterestMinor: 0,
    );
  }
  final forecast = _simulateLoanForecast(
    principalMinor: remaining,
    monthlyEmiMinor: emi,
    annualRatePercent: rate,
  );
  return _LoanProjection(
    monthlyEmi: emi,
    monthsRemaining: forecast.monthsRemaining,
    estimatedInterestMinor: forecast.totalInterestMinor,
  );
}

({int? monthsRemaining, int totalInterestMinor, int remainingMinor})
_simulateLoanForecast({
  required int principalMinor,
  required int monthlyEmiMinor,
  required double annualRatePercent,
  int maxMonths = 1200,
}) {
  var balance = principalMinor;
  var interest = 0;
  var months = 0;
  final monthlyRate = annualRatePercent <= 0 ? 0 : annualRatePercent / 100 / 12;
  while (balance > 0 && months < maxMonths) {
    final interestMinor = (balance * monthlyRate).round();
    final principalPaid = (monthlyEmiMinor - interestMinor)
        .clamp(0, balance)
        .toInt();
    if (principalPaid <= 0) break;
    balance -= principalPaid;
    interest += interestMinor;
    months++;
  }
  return (
    monthsRemaining: balance <= 0 ? months : null,
    totalInterestMinor: interest,
    remainingMinor: balance,
  );
}

class _LoanProjection {
  const _LoanProjection({
    required this.monthlyEmi,
    required this.monthsRemaining,
    required this.estimatedInterestMinor,
  });

  final int monthlyEmi;
  final int? monthsRemaining;
  final int estimatedInterestMinor;

  String get payoffLabel {
    final months = monthsRemaining;
    if (months == null) {
      if (monthlyEmi > 0) return 'EMI too low to cover interest';
      return 'Add an EMI to estimate payoff';
    }
    if (months == 0) return 'Paid off';
    final years = months ~/ 12;
    final extraMonths = months % 12;
    if (years == 0) return '$months months remaining';
    if (extraMonths == 0) return '$years years remaining';
    return '$years years $extraMonths months remaining';
  }
}

String _formatAmountInput(int amountMinor) {
  if (amountMinor == 0) return '';
  final integer = amountMinor ~/ 100;
  final fraction = amountMinor % 100;
  if (fraction == 0) return '$integer';
  return '$integer.${fraction.toString().padLeft(2, '0')}';
}

int _amountMinorFromInput(String value) {
  final clean = value.replaceAll(RegExp(r'[^0-9.]'), '');
  if (clean.isEmpty) return 0;
  final parts = clean.split('.');
  final integer = int.tryParse(parts[0]) ?? 0;
  final fraction = parts.length > 1
      ? (int.tryParse(parts[1].padRight(2, '0').substring(0, 2)) ?? 0)
      : 0;
  return integer * 100 + fraction;
}

void _showRouteMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
}
