import 'dart:async';
import 'dart:math' as math;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import '../common/route_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/currency_picker.dart';
import '../common/full_screen_picker.dart';
import '../transactions/transaction_row.dart';
import '../../utils/number_formatter.dart';
import '../../widgets/privacy_text.dart';
import 'loan_forecast_simulator.dart';

class LoansScreen extends ConsumerWidget {
  const LoansScreen({super.key, this.mode = 'overview', this.accountId});

  final String mode;
  final String? accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ledgerProvider);
    if (mode == 'new' || mode == 'edit') {
      return LoanForm(accountId: accountId);
    }
    final allLoans = state.accounts
        .where(
          (account) => account.type == 'loan' || account.type == 'overdraft',
        )
        .toList();
    final activeLoans = allLoans
        .where((account) => !isPastLoan(state, account))
        .toList();
    final pastLoans = allLoans
        .where((account) => isPastLoan(state, account))
        .toList();
    final listedLoans = mode == 'past' ? pastLoans : activeLoans;
    final selectedLoan = accountById(state, accountId);
    final displayCurrency = state.preferences.displayCurrency;
    final emi = scheduledTransactions(state)
        .where((record) => record.type == 'loan_repayment')
        .fold<int>(0, (sum, record) {
          final converted = convertMoneyForDisplay(
            state,
            record.amount,
            displayCurrency,
          );
          return sum + converted.amountMinor;
        });
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
        HeaderIconButton(
          icon: Icons.add_rounded,
          tooltip: 'Add loan',
          semanticLabel: 'Add loan',
          onPressed: () => context.push('/loans/new'),
        ),
      ],
      child: Column(
        children: [
          if (mode != 'detail' &&
              mode != 'edit' &&
              mode != 'new' &&
              mode != 'forecast') ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: SectionCard(
                title: 'Loan control center',
                subtitle: 'Loan count and next scheduled EMI.',
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
                        label: mode == 'past' ? 'Archived' : 'Total EMI',
                        value: mode == 'past'
                            ? '${pastLoans.length}'
                            : maskMoneyIfPrivate(
                                state,
                                formatMoney(
                                  Money(
                                    amountMinor: emi,
                                    currency: displayCurrency,
                                  ),
                                  state.preferences.locale,
                                ),
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
                  ? 'Paid-off loans automatically close here. You can also manually archive a loan from its detail page.'
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
              const SizedBox(height: AppSpacing.xs),
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
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _principalController.addListener(_autoCalculateEmi);
    _rateController.addListener(_autoCalculateEmi);
    _tenureController.addListener(_autoCalculateEmi);
  }

  String? _lastAutoEmiText;

  void _autoCalculateEmi() {
    final principalMinor = _amountMinorFromInput(
      _principalController.text,
      _currency,
    );
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

      final newText = _formatAmountInput(emiMinor, _currency);
      // Only auto-fill when the field is empty or still shows the last
      // value we auto-calculated; never clobber a user-typed EMI.
      if (_emiController.text.isEmpty ||
          _emiController.text == _lastAutoEmiText) {
        _emiController.text = newText;
      }
      _lastAutoEmiText = newText;
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
    return RouteScaffold(
      title: loan == null ? 'New loan' : 'Edit loan',
      actions: [HeaderSaveAction(onPressed: () => _saveLoan(state, loan))],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: SectionCard(
              title: loan == null ? 'Loan details' : 'Edit loan details',
              subtitle: 'Create a loan account and optional scheduled EMI.',
              child: Column(
                children: [
                  GlassTextField(
                    controller: _nameController,
                    placeholder: 'Loan name',
                    prefixIcon: const Icon(Icons.account_balance_outlined),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  GlassTextField(
                    controller: _lenderController,
                    placeholder: 'Lender / institution',
                    prefixIcon: const Icon(Icons.business_outlined),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: GlassTextField(
                          controller: _principalController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            ThousandsSeparatorInputFormatter(
                              state.preferences.locale,
                            ),
                          ],
                          placeholder: 'Original Principal',
                          prefixIcon: const Icon(Icons.payments_outlined),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: GlassTextField(
                          controller: _currentBalanceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            ThousandsSeparatorInputFormatter(
                              state.preferences.locale,
                            ),
                          ],
                          placeholder: 'Current Balance',
                          prefixIcon: const Icon(
                            Icons.account_balance_wallet_outlined,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: GlassTextField(
                          controller: _emiController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            ThousandsSeparatorInputFormatter(
                              state.preferences.locale,
                            ),
                          ],
                          placeholder: 'Repayment amount',
                          prefixIcon: const Icon(Icons.event_repeat_outlined),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: GlassTextField(
                          controller: _rateController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            ThousandsSeparatorInputFormatter(
                              state.preferences.locale,
                            ),
                          ],
                          placeholder: 'Rate %',
                          prefixIcon: const Icon(Icons.percent_rounded),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  GlassTextField(
                    controller: _tenureController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    placeholder: 'Tenure count',
                    prefixIcon: const Icon(Icons.timelapse_outlined),
                  ),
                ],
              ),
            ),
          ),
          const Gap(AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: SectionCard(
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
                    initialValue:
                        const [
                          'daily',
                          'weekly',
                          'monthly',
                          'yearly',
                        ].contains(_frequency)
                        ? _frequency
                        : 'monthly',
                    decoration: const InputDecoration(
                      labelText: 'EMI Frequency',
                      prefixIcon: Icon(Icons.repeat_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'daily', child: Text('Daily')),
                      DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                      DropdownMenuItem(
                        value: 'monthly',
                        child: Text('Monthly'),
                      ),
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
                      spacing: AppSpacing.xs,
                      children: [
                        for (var i = 1; i <= 7; i++)
                          FilterChip(
                            label: Text(
                              ['', 'M', 'T', 'W', 'T', 'F', 'S', 'S'][i],
                            ),
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
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xxs,
                      children: [
                        for (var i = 1; i <= 31; i++)
                          FilterChip(
                            label: Text('$i'),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
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
                        FilterChip(
                          label: const Text('Last day of month'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xxs,
                          ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          selected: _daysOfMonth.contains(32),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                if (_daysOfMonth.length < _interval) {
                                  _daysOfMonth.add(32);
                                }
                              } else {
                                _daysOfMonth.remove(32);
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
                  AppSwitchListTile(
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
          ),
          const Gap(AppSpacing.lg),
        ],
      ),
    );
  }

  void _syncLoanDraft(LedgerState state, Account? loan) {
    final key = loan?.id ?? '__new__';
    if (_loadedAccountId == key) return;
    _loadedAccountId = key;
    final details = loan == null ? null : effectiveLoanDetails(state, loan);
    _currency = loan?.currency ?? state.preferences.baseCurrency;
    _loanKind = loan?.type ?? 'loan';
    _nameController.text = loan?.name ?? '';
    _lenderController.text = loan?.institution ?? '';
    _principalController.text = details?.principal == null
        ? loan == null
              ? ''
              : _formatAmountInput(
                  loan.openingBalance.amountMinor.abs(),
                  _currency,
                )
        : _formatAmountInput(details!.principal!.amountMinor.abs(), _currency);
    final balance = loan == null ? null : accountBalance(state, loan);
    _currentBalanceController.text = balance == null
        ? ''
        : _formatAmountInput(balance.amountMinor.abs(), _currency);
    final existingEmi = existingLoanEmi(state, loan?.id);
    final repaymentAmount = details?.repaymentAmount;
    _emiController.text = repaymentAmount == null && existingEmi == null
        ? ''
        : _formatAmountInput(
            (existingEmi?.amount ?? repaymentAmount!).amountMinor.abs(),
            _currency,
          );
    _rateController.text = _formatOptionalDecimal(details?.interestRatePercent);
    _tenureController.text = (details?.repaymentCount ?? '').toString();
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
    if (next == null || !mounted) return;
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
                '${accountTypeLabel(account.type)} · ${maskMoneyIfPrivate(state, formatMoney(accountBalance(state, account), state.preferences.locale))}',
            icon: accountIcon(account),
            iconColor: accountDisplayColor(account),
          ),
      ],
    );
    if (next == null || !mounted) return;
    setState(() => _sourceAccountId = next);
  }

  Future<void> _showCurrencyPicker(LedgerState state) async {
    final next = await showCurrencyPicker(
      context: context,
      state: state,
      selectedValue: _currency,
    );
    if (next == null || !mounted) return;
    setState(() => _currency = next);
  }

  Future<void> _pickNextEmiDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextEmiDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _nextEmiDate = picked);
  }

  Future<void> _saveLoan(LedgerState state, Account? existingLoan) async {
    // Guard against double-tap re-entry while a save is already in flight.
    if (_isSaving) return;
    final name = _nameController.text.trim();
    final principalMinor = _amountMinorFromInput(
      _principalController.text,
      _currency,
    ).abs();
    final currentBalanceInput = _amountMinorFromInput(
      _currentBalanceController.text,
      _currency,
    ).abs();
    final effectiveCurrentBalanceMinor = _currentBalanceController.text.isEmpty
        ? principalMinor
        : currentBalanceInput;
    final emiMinor = _amountMinorFromInput(
      _emiController.text,
      _currency,
    ).abs();
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
    if (rate != null && rate < 0) {
      _showRouteMessage(context, 'Interest rate cannot be negative.');
      return;
    }
    if (tenure != null && tenure <= 0) {
      _showRouteMessage(
        context,
        'Tenure must be a positive number of payments.',
      );
      return;
    }
    final sourceAccount = accountById(state, _sourceAccountId);
    if (emiMinor > 0 && sourceAccount == null) {
      _showRouteMessage(context, 'Choose the account that pays the EMI.');
      return;
    }
    setState(() => _isSaving = true);
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
        final existingEmi = existingLoanEmi(latestState, loan.id);
        await ref
            .read(ledgerProvider.notifier)
            .upsertTransaction(
              id: existingEmi?.id,
              type: 'loan_repayment',
              accountId: sourceAccount.id,
              counterAccountId: loan.id,
              amountMinor: emiMinor,
              clearOriginalAmount: true,
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
        final existingEmi = existingLoanEmi(latestState, loan.id);
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
    } finally {
      if (mounted) setState(() => _isSaving = false);
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
    final nextEmi = existingLoanEmi(state, loan.id);
    final details = effectiveLoanDetails(state, loan);
    final projection = loanProjection(state, loan);
    final repaymentHistory = _loanHistoryRepayments(state, loan.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          key: const ValueKey('loanDetailHeaderCard'),
          margin: EdgeInsets.zero,
          padding: EdgeInsets.zero,
          shape: const LiquidRoundedSuperellipse(borderRadius: AppRadii.md),
          quality: GlassQuality.standard,
          child: Material(
            color: Colors.transparent,
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
                            const SizedBox(height: AppSpacing.xxxs),
                            Text(
                              '${accountTypeLabel(loan.type).toUpperCase()} ACCOUNT',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: PrivacyText(
                          formatMoney(
                            balance.copyWith(
                              amountMinor: balance.amountMinor.abs(),
                            ),
                            state.preferences.locale,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  if (details.principal != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Builder(
                      builder: (context) {
                        final principal = details.principal!.amountMinor.abs();
                        final remaining = balance.amountMinor < 0
                            ? -balance.amountMinor
                            : 0;
                        final paid = (principal - remaining).clamp(
                          0,
                          principal,
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
                                Flexible(
                                  child: PrivacyText(
                                    'Paid: ${formatMoney(Money(amountMinor: paid, currency: loan.currency), state.preferences.locale)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                if (projection.monthsRemaining != null) ...[
                                  const SizedBox(width: AppSpacing.sm),
                                  Flexible(
                                    child: Text(
                                      '${projection.monthsRemaining} mos left',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.end,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            LinearProgressIndicator(value: progress),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
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
          style: AppButtonStyles.cta,
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: SectionCard(
            title: 'Repayment history',
            subtitle: repaymentHistory.isEmpty
                ? 'Posted EMI and repayment entries will appear here.'
                : '${repaymentHistory.length} posted repayment${repaymentHistory.length == 1 ? '' : 's'}',
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
                          glass: false,
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
        ),
      ],
    );
  }

  Future<void> _confirmArchiveLoan(
    BuildContext context,
    WidgetRef ref,
    Account loan,
  ) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Archive loan?',
      message:
          'This hides the loan if linked transactions exist, or removes it if unused.',
      confirmLabel: 'Archive',
    );
    if (!confirmed) return;
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
    final details = effectiveLoanDetails(state, loan);
    final projection = loanProjection(state, loan);
    final repayments = _postedLoanRepayments(state, loan.id);
    final nextEmi = existingLoanEmi(state, loan.id);
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
      if (details.repaymentCount != null)
        'for ${details.repaymentCount} time${details.repaymentCount == 1 ? '' : 's'}',
      if (mode == 'past' && repayments.isNotEmpty)
        '${repayments.length} repayment${repayments.length == 1 ? '' : 's'}',
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

    return AppPanel(
      glass: true,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxxs),
                    Text(
                      cadenceSummary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (tertiaryLine != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        tertiaryLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    if (mode == 'past') ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        projection.payoffLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.primary,
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
                  PrivacyText(
                    rightAmountText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: mode == 'past' ? scheme.onSurface : scheme.error,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
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
                final remaining = balance.amountMinor < 0
                    ? -balance.amountMinor
                    : 0;
                final paid = (principal - remaining).clamp(0, principal);
                final progress = principal > 0
                    ? (paid / principal).clamp(0.0, 1.0)
                    : 0.0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: PrivacyText(
                            'Paid: ${formatMoney(Money(amountMinor: paid, currency: loan.currency), state.preferences.locale)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        if (projection.monthsRemaining != null) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Flexible(
                            child: Text(
                              '${projection.monthsRemaining} mos left',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    LinearProgressIndicator(value: progress),
                  ],
                );
              },
            ),
          ],
        ],
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
    final foreground =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;
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
  final TextStyle? labelStyle;
  final double radius;

  NumberedDotPainter(
    this.label, {
    required this.color,
    required this.textColor,
    this.labelStyle,
    this.radius = 10,
  });

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) {
    final paint = Paint()..color = color;
    canvas.drawCircle(offsetInCanvas, radius, paint);

    final textSpan = TextSpan(
      text: label,
      style: (labelStyle ?? const TextStyle()).copyWith(
        color: textColor,
        fontWeight: FontWeight.bold,
      ),
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
  List<Object?> get props => [label, color, textColor, labelStyle, radius];
}

class DynamicForecastLineChart extends StatefulWidget {
  final List<FlSpot> spots;
  final double chartWidth;
  final Color lineColor;
  final List<dynamic> balanceCurve;
  final String locale;
  final Map<double, String> payoffDots;
  final String currencySymbol;
  final bool isPrivate;

  const DynamicForecastLineChart({
    super.key,
    required this.spots,
    required this.chartWidth,
    required this.lineColor,
    required this.balanceCurve,
    required this.locale,
    required this.payoffDots,
    required this.currencySymbol,
    this.isPrivate = false,
  });

  @override
  State<DynamicForecastLineChart> createState() =>
      _DynamicForecastLineChartState();
}

class _DynamicForecastLineChartState extends State<DynamicForecastLineChart> {
  double _currentMinX = 0;
  double _currentMaxX = 100;
  double _currentMinY = 0;
  double _currentMaxY = 100;

  static const double _minRange = 14; // most zoomed-in: ~2 weeks visible

  // Window captured at the start of a pinch/drag gesture, used for stable
  // scale + pan math.
  double _startMinX = 0;
  double _startMaxX = 0;
  double _startFocalPx = 0;

  @override
  void initState() {
    super.initState();
    _initBounds();
  }

  double get _totalRange {
    if (widget.spots.length < 2) return 0;
    return widget.spots.last.x - widget.spots.first.x;
  }

  void _initBounds() {
    if (widget.spots.isEmpty) return;
    final firstX = widget.spots.first.x;
    final lastX = widget.spots.last.x;
    // Default view: focus on the near term (~3 months back to ~15 months
    // ahead of today at x=0), the most actionable window. Pinch/scroll to
    // explore the full 6-year range.
    double minX = math.max(firstX, -90);
    double maxX = math.min(lastX, 455);
    if (maxX - minX < _minRange) {
      minX = firstX;
      maxX = lastX;
    }
    _setWindow(minX, maxX);
  }

  /// Applies a visible X window, clamping it to the data bounds and the
  /// minimum zoom range, then refreshes the Y limits to fit what's visible.
  void _setWindow(double minX, double maxX) {
    if (widget.spots.isEmpty) return;
    final first = widget.spots.first.x;
    final last = widget.spots.last.x;
    final total = last - first;
    if (total <= 0) {
      _currentMinX = first - 1;
      _currentMaxX = last + 1;
      _updateYLimits();
      return;
    }
    double range = maxX - minX;
    if (range < _minRange) range = _minRange;
    if (range >= total) {
      minX = first;
      maxX = last;
    } else {
      if (minX < first) {
        minX = first;
        maxX = first + range;
      }
      if (maxX > last) {
        maxX = last;
        minX = last - range;
      }
    }
    _currentMinX = minX;
    _currentMaxX = maxX;
    _updateYLimits();
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

  /// Zoom around a fractional focal point (0 = left edge .. 1 = right edge) by
  /// [factor] (< 1 zooms in, > 1 zooms out).
  void _applyZoom(double factor, double focalFrac) {
    if (_totalRange <= 0) return;
    final range = _currentMaxX - _currentMinX;
    final newRange = (range * factor).clamp(_minRange, _totalRange);
    final focalDataX = _currentMinX + focalFrac * range;
    final newMinX = focalDataX - focalFrac * newRange;
    setState(() => _setWindow(newMinX, newMinX + newRange));
  }

  void _onScaleStart(ScaleStartDetails details) {
    _startMinX = _currentMinX;
    _startMaxX = _currentMaxX;
    _startFocalPx = details.localFocalPoint.dx;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_totalRange <= 0) return;
    final width = context.size?.width ?? 300;
    if (width <= 0) return;
    final startRange = _startMaxX - _startMinX;
    final focalFrac = (_startFocalPx / width).clamp(0.0, 1.0);
    // Pinch to zoom relative to the window captured at gesture start.
    final newRange = (startRange / details.scale).clamp(_minRange, _totalRange);
    final focalDataX = _startMinX + focalFrac * startRange;
    double newMinX = focalDataX - focalFrac * newRange;
    // Drag to pan by how far the focal point moved since the gesture started.
    final panPx = details.localFocalPoint.dx - _startFocalPx;
    newMinX -= (panPx / width) * newRange;
    setState(() => _setWindow(newMinX, newMinX + newRange));
  }

  // Mouse-wheel / trackpad zoom for web & desktop, centred on the pointer.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final width = context.size?.width ?? 300;
      final focalFrac = width <= 0
          ? 0.5
          : (event.localPosition.dx / width).clamp(0.0, 1.0);
      final zoomingIn = event.scrollDelta.dy < 0;
      _applyZoom(zoomingIn ? 0.85 : 1.0 / 0.85, focalFrac);
    }
  }

  double get _xInterval {
    final range = _currentMaxX - _currentMinX;
    if (range <= 0) return 1;
    const idealCount = 4.0;
    final interval = (range / idealCount).ceilToDouble();
    return interval < 1 ? 1 : interval;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.spots.isEmpty) return const SizedBox.shrink();

    double yInterval = ((_currentMaxY - _currentMinY) / 5).roundToDouble();
    if (yInterval < 1) yInterval = 1;

    final numberFormat = NumberFormat.compactCurrency(
      locale: widget.locale,
      symbol: widget.currencySymbol,
    );
    // Themed marker color for payoff milestones so they stay legible (and
    // don't clash with the primary "today" line) across light/dark/AMOLED.
    final scheme = Theme.of(context).colorScheme;
    final payoffColor = scheme.tertiary;
    final onPayoffColor = scheme.onTertiary;

    return Stack(
      fit: StackFit.expand,
      children: [
        Listener(
          onPointerSignal: _onPointerSignal,
          child: GestureDetector(
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            child: Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.xs,
                bottom: AppSpacing.xs,
                right: AppSpacing.md,
              ),
              child: RepaintBoundary(
                child: LineChart(
                  LineChartData(
                    minY: _currentMinY,
                    maxY: _currentMaxY,
                    minX: _currentMinX,
                    maxX: _currentMaxX,
                    clipData: const FlClipData.all(),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (spot) =>
                            Theme.of(context).colorScheme.surfaceContainerHigh,
                        getTooltipItems: (touchedSpots) {
                          return touchedSpots.map((spot) {
                            final now = DateTime.now();
                            final today = DateTime(
                              now.year,
                              now.month,
                              now.day,
                            );
                            final date = today.add(
                              Duration(days: spot.x.toInt()),
                            );
                            final dateStr = DateFormat(
                              'dd MMM yyyy',
                            ).format(date);

                            final amt = NumberFormat.decimalPattern(
                              widget.locale,
                            ).format(spot.y);
                            final rawMoneyStr = '${widget.currencySymbol}$amt';
                            final moneyStr = widget.isPrivate
                                ? maskAmountDigits(rawMoneyStr)
                                : rawMoneyStr;

                            return LineTooltipItem(
                              '$moneyStr\n',
                              TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                              children: [
                                TextSpan(
                                  text: dateStr,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
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
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.5),
                          dashArray: [5, 5],
                          label: VerticalLineLabel(
                            show: true,
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.xl,
                              left: AppSpacing.xxs,
                            ),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
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
                            color: payoffColor.withValues(alpha: 0.5),
                            strokeWidth: 1,
                            dashArray: [3, 3],
                            label: VerticalLineLabel(
                              show: true,
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.xxs,
                                left: AppSpacing.xxs,
                              ),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: payoffColor,
                                    fontWeight: FontWeight.bold,
                                  ),
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
                          cutOffY: _currentMinY,
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
                          checkToShowDot: (spot, barData) =>
                              widget.payoffDots.containsKey(spot.x),
                          getDotPainter: (spot, percent, barData, index) {
                            final label = widget.payoffDots[spot.x];
                            if (label != null) {
                              return NumberedDotPainter(
                                label,
                                color: payoffColor,
                                textColor: onPayoffColor,
                                labelStyle: Theme.of(
                                  context,
                                ).textTheme.labelMedium,
                              );
                            }
                            return FlDotCirclePainter(
                              radius: 0,
                              color: Colors.transparent,
                            );
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
                            final today = DateTime(
                              now.year,
                              now.month,
                              now.day,
                            );
                            final date = today.add(
                              Duration(days: value.toInt()),
                            );

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
                              padding: const EdgeInsets.only(
                                top: AppSpacing.xs,
                              ),
                              child: Text(
                                dateStr,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
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
                            final formatted = numberFormat.format(value);
                            return Padding(
                              padding: const EdgeInsets.only(
                                right: AppSpacing.xs,
                              ),
                              child: Text(
                                widget.isPrivate
                                    ? maskAmountDigits(formatted)
                                    : formatted,
                                textAlign: TextAlign.right,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            );
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                    ),
                    gridData: FlGridData(
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
        ),
        Positioned(
          right: AppSpacing.xs,
          bottom: AppSpacing.xs,
          child: _ChartZoomControls(
            onZoomIn: () => _applyZoom(0.6, 0.5),
            onZoomOut: () => _applyZoom(1.0 / 0.6, 0.5),
            onReset: () => setState(_initBounds),
          ),
        ),
      ],
    );
  }
}

/// Google-Maps-style floating zoom controls overlaid on the forecast chart,
/// so zoom works on web/desktop (no pinch) too.
class _ChartZoomControls extends StatelessWidget {
  const _ChartZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget button(IconData icon, VoidCallback onTap, String tooltip) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Material(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.92),
          shape: const CircleBorder(),
          elevation: 2,
          child: IconButton(
            tooltip: tooltip,
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 38, height: 38),
            padding: EdgeInsets.zero,
            onPressed: onTap,
            icon: Icon(icon, color: scheme.onSurface),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(Icons.add_rounded, onZoomIn, 'Zoom in'),
        button(Icons.remove_rounded, onZoomOut, 'Zoom out'),
        button(Icons.center_focus_strong_outlined, onReset, 'Reset view'),
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
  final bool isPrivate;

  const DynamicForecastBarChart({
    super.key,
    required this.barGroups,
    required this.chartWidth,
    required this.timeKeys,
    required this.locale,
    required this.currencySymbol,
    this.isPrivate = false,
  });

  @override
  State<DynamicForecastBarChart> createState() =>
      _DynamicForecastBarChartState();
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
      const minRange = 4.0;
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
    const idealCount = 4.0;
    final interval = (range / idealCount).ceilToDouble();
    return interval < 1 ? 1 : interval;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.barGroups.isEmpty) return const SizedBox.shrink();

    double yInterval = ((_currentMaxY - _currentMinY) / 5).roundToDouble();
    if (yInterval < 1) yInterval = 1;

    final numberFormat = NumberFormat.compactCurrency(
      locale: widget.locale,
      symbol: widget.currencySymbol,
    );

    final visibleGroups = widget.barGroups
        .where((g) => g.x >= _currentMinX.floor() && g.x <= _currentMaxX.ceil())
        .toList();

    final widthAvailable = MediaQuery.of(context).size.width - 64;
    final visibleCount = visibleGroups.length;
    double dynamicBarWidth = visibleCount > 0
        ? (widthAvailable / visibleCount) * 0.5
        : 12.0;
    if (dynamicBarWidth > 20) dynamicBarWidth = 20;
    if (dynamicBarWidth < 2) dynamicBarWidth = 2;

    final updatedVisibleGroups = visibleGroups.map((g) {
      final oldRod = g.barRods.first;
      return BarChartGroupData(
        x: g.x,
        barRods: [oldRod.copyWith(width: dynamicBarWidth)],
      );
    }).toList();

    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onHorizontalDragUpdate: _onPanUpdate,
            child: Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.xs,
                bottom: AppSpacing.xs,
                right: AppSpacing.md,
              ),
              child: RepaintBoundary(
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
                                padding: const EdgeInsets.only(
                                  top: AppSpacing.xs,
                                ),
                                child: Text(
                                  str,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
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
                            final formatted = numberFormat.format(value);
                            return Padding(
                              padding: const EdgeInsets.only(
                                right: AppSpacing.xs,
                              ),
                              child: Text(
                                widget.isPrivate
                                    ? maskAmountDigits(formatted)
                                    : formatted,
                                textAlign: TextAlign.right,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            );
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                    ),
                    gridData: FlGridData(
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
        ),
        Row(
          children: [
            Icon(
              Icons.zoom_out_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            Expanded(
              child: Slider(value: _zoomPercent, onChanged: _onSliderChange),
            ),
            Icon(
              Icons.zoom_in_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
  late double _debouncedExtraAllocationPercent;
  late List<Account> _priorityLoans;
  Timer? _forecastDebounce;
  Timer? _emergencyDebounce;
  LoanForecastSimulationResult? _cachedResult;
  List<FlSpot>? _cachedSpots;
  Map<double, String>? _cachedPayoffDots;
  Object? _cachedSimKey;

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

      final aRate =
          effectiveLoanDetails(widget.state, a).interestRatePercent ?? 0;
      final bRate =
          effectiveLoanDetails(widget.state, b).interestRatePercent ?? 0;
      return bRate.compareTo(aRate);
    });
  }

  @override
  void initState() {
    super.initState();
    final prefs = widget.state.preferences;
    final baseMinors = math.pow(10, minorUnits(prefs.baseCurrency)).toInt();
    _emergencyController = TextEditingController(
      text: (prefs.forecastEmergencyCashMinor / baseMinors).toInt().toString(),
    );
    _extraAllocationPercent = prefs.forecastExtraAllocationPercent;
    _debouncedExtraAllocationPercent = _extraAllocationPercent;
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
      final newLoansMap = {for (var l in widget.loans) l.id: l};
      for (int i = 0; i < _priorityLoans.length; i++) {
        if (newLoansMap.containsKey(_priorityLoans[i].id)) {
          _priorityLoans[i] = newLoansMap[_priorityLoans[i].id]!;
        }
      }
    }
  }

  void _flushEmergencyCash() {
    _emergencyDebounce?.cancel();
    if (!mounted) return;
    final newMinor = _amountMinorFromInput(
      _emergencyController.text,
      widget.state.preferences.baseCurrency,
    ).abs();
    ref
        .read(ledgerProvider.notifier)
        .updatePreferencesWith(
          (livePreferences) =>
              livePreferences.copyWith(forecastEmergencyCashMinor: newMinor),
        );
  }

  @override
  void dispose() {
    _forecastDebounce?.cancel();
    _emergencyDebounce?.cancel();
    _emergencyController.dispose();
    super.dispose();
  }

  // Snap a stored allocation fraction to the nearest preset segment.
  double _snapAllocation(double value) {
    if (value < 0.25) return 0.0;
    if (value < 0.75) return 0.5;
    return 1.0;
  }

  String _allocationHint(double value) {
    if (value <= 0.0) {
      return 'Only the scheduled EMI is paid — no early payoff.';
    }
    if (value < 1.0) {
      return 'Half of your spare cash accelerates the priority loan.';
    }
    return 'All spare cash above your buffer goes to the priority loan.';
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

    final baseCurrency = widget.state.preferences.baseCurrency;
    final baseMinorsScale = math.pow(10, minorUnits(baseCurrency)).toInt();
    final emergencyMinor = _amountMinorFromInput(
      _emergencyController.text,
      baseCurrency,
    ).abs();

    final activeLoans = widget.loans.map((loan) {
      final details = effectiveLoanDetails(widget.state, loan);
      final emiTx = existingLoanEmi(widget.state, loan.id);
      final rawEmi =
          details.repaymentAmount?.amountMinor.abs() ??
          emiTx?.amount.amountMinor.abs() ??
          0;
      final frequency =
          emiTx?.recurrenceFrequency ?? details.recurrenceFrequency;
      final interval = emiTx?.recurrenceInterval ?? details.recurrenceInterval;

      double monthlyMultiplier = 1.0;
      if (frequency == 'yearly') {
        monthlyMultiplier = 1 / 12;
      } else if (frequency == 'weekly') {
        monthlyMultiplier = 52 / 12;
      } else if (frequency == 'daily') {
        monthlyMultiplier = 365 / 12;
      }
      final effectiveInterval = interval > 0 ? interval : 1;
      monthlyMultiplier = monthlyMultiplier / effectiveInterval;

      final emi = (rawEmi * monthlyMultiplier).round();
      final rate = details.interestRatePercent ?? 0;
      final bal = accountBalance(widget.state, loan).amountMinor;
      final remaining = bal < 0 ? -bal : 0;
      return ActiveLoan(
        account: loan,
        principalMinor: remaining,
        monthlyEmiMinor: emi,
        annualRatePercent: rate,
      );
    }).toList();

    final simKey = (
      widget.state,
      widget.loans,
      emergencyMinor,
      _debouncedExtraAllocationPercent,
      _priorityLoans,
      widget.state.preferences.loanPayoffDelayDays,
      baseMinorsScale,
    );

    if (_cachedSimKey != simKey ||
        _cachedResult == null ||
        _cachedSpots == null ||
        _cachedPayoffDots == null) {
      final computedResult = simulateForecastPayoffGraph(
        state: widget.state,
        activeLoans: activeLoans,
        emergencySavingMinor: emergencyMinor,
        extraPaymentAllocationPercent: _debouncedExtraAllocationPercent,
        loanPriorityIds: _priorityLoans.map((l) => l.id).toList(),
        payoffDelayDays: widget.state.preferences.loanPayoffDelayDays,
      );

      final computedSpots = <FlSpot>[];
      final now = DateTime.now();
      final todayMillis = DateTime(
        now.year,
        now.month,
        now.day,
      ).millisecondsSinceEpoch.toDouble();

      for (int i = 0; i < computedResult.balanceCurve.length; i++) {
        final pt = computedResult.balanceCurve[i];
        final x = (pt.date.millisecondsSinceEpoch - todayMillis) / 86400000.0;
        final y = pt.netBalanceMinor / baseMinorsScale;
        computedSpots.add(FlSpot(x, y));
      }

      if (computedSpots.isEmpty) {
        computedSpots.add(const FlSpot(0, 0));
      }

      final loanNumberMap = <String, int>{};
      for (int i = 0; i < _priorityLoans.length; i++) {
        loanNumberMap[_priorityLoans[i].id] = i + 1;
      }

      final computedPayoffDots = <double, String>{};
      for (final event in computedResult.payoffEvents) {
        final eventX =
            (event.payoffDate.millisecondsSinceEpoch - todayMillis) /
            86400000.0;
        final number = loanNumberMap[event.loan.id]?.toString() ?? '';

        double closestX = 0;
        double minDiff = double.infinity;
        for (final spot in computedSpots) {
          final diff = (spot.x - eventX).abs();
          if (diff < minDiff) {
            minDiff = diff;
            closestX = spot.x;
          }
        }

        if (computedPayoffDots.containsKey(closestX)) {
          computedPayoffDots[closestX] =
              '${computedPayoffDots[closestX]},$number';
        } else {
          computedPayoffDots[closestX] = number;
        }
      }

      _cachedSimKey = simKey;
      _cachedResult = computedResult;
      _cachedSpots = computedSpots;
      _cachedPayoffDots = computedPayoffDots;
    }

    final result = _cachedResult!;
    final spots = _cachedSpots!;
    final payoffDots = _cachedPayoffDots!;

    final locale = widget.state.preferences.locale;
    final scheme = Theme.of(context).colorScheme;
    final currencyFormat = NumberFormat.simpleCurrency(
      locale: locale,
      name: widget.state.preferences.displayCurrency,
    );
    final currencySymbol = currencyFormat.currencySymbol;
    final lineChartWidth = math.max(
      MediaQuery.of(context).size.width - 64,
      spots.length * 1.5,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (result.impact.interestSavedMinor > 0 ||
            result.impact.monthsSaved > 0)
          Container(
            margin: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.tertiary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadii.md),
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
                    Icon(Icons.bolt_rounded, color: scheme.onPrimary, size: 28),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'Accelerated Impact',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: scheme.onPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Builder(
                  builder: (context) {
                    final savedText = maskMoneyIfPrivate(
                      widget.state,
                      formatMoney(
                        Money(
                          amountMinor: result.impact.interestSavedMinor,
                          currency: widget.state.preferences.baseCurrency,
                        ),
                        locale,
                      ),
                    );
                    final monthsSaved = result.impact.monthsSaved;
                    return Text(
                      'You could save $savedText in interest and finish $monthsSaved month${monthsSaved == 1 ? '' : 's'} early!',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: scheme.onPrimary,
                            fontWeight: FontWeight.w900,
                            height: 1.2,
                          ),
                    );
                  },
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: SectionCard(
            title: 'Payoff Simulation',
            subtitle:
                'Adjust your emergency fund and extra cash allocation to see the payoff graph.',
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Text(
                      'Emergency Fund / Savings Buffer',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                GlassTextField(
                  controller: _emergencyController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    ThousandsSeparatorInputFormatter(
                      widget.state.preferences.locale,
                    ),
                  ],
                  placeholder: 'Enter amount to protect ($currencySymbol)',
                  prefixIcon: const Icon(Icons.savings_outlined),
                  onSubmitted: (_) => _flushEmergencyCash(),
                  onChanged: (val) {
                    final newMinor = _amountMinorFromInput(
                      val,
                      baseCurrency,
                    ).abs();
                    _emergencyDebounce?.cancel();
                    _emergencyDebounce = Timer(
                      const Duration(milliseconds: 120),
                      () {
                        if (!mounted) return;
                        ref
                            .read(ledgerProvider.notifier)
                            .updatePreferencesWith(
                              (livePreferences) => livePreferences.copyWith(
                                forecastEmergencyCashMinor: newMinor,
                              ),
                            );
                        setState(() {});
                      },
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue:
                      const [
                        0,
                        7,
                        14,
                        30,
                      ].contains(widget.state.preferences.loanPayoffDelayDays)
                      ? widget.state.preferences.loanPayoffDelayDays
                      : 0,
                  decoration: const InputDecoration(
                    labelText: 'Delay before closing loan',
                    prefixIcon: Icon(Icons.timer_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 0,
                      child: Text('Close immediately'),
                    ),
                    DropdownMenuItem(value: 7, child: Text('Wait 1 week')),
                    DropdownMenuItem(value: 14, child: Text('Wait 2 weeks')),
                    DropdownMenuItem(value: 30, child: Text('Wait 1 month')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      ref
                          .read(ledgerProvider.notifier)
                          .updatePreferencesWith(
                            (livePreferences) => livePreferences.copyWith(
                              loanPayoffDelayDays: val,
                            ),
                          );
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Extra cash toward loans',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<double>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 0.0, label: Text('Base')),
                      ButtonSegment(value: 0.5, label: Text('Balanced')),
                      ButtonSegment(value: 1.0, label: Text('Max')),
                    ],
                    selected: {
                      _snapAllocation(_debouncedExtraAllocationPercent),
                    },
                    onSelectionChanged: (selection) {
                      final val = selection.first;
                      setState(() {
                        _extraAllocationPercent = val;
                        _debouncedExtraAllocationPercent = val;
                      });
                      ref
                          .read(ledgerProvider.notifier)
                          .updatePreferencesWith(
                            (livePreferences) => livePreferences.copyWith(
                              forecastExtraAllocationPercent: val,
                            ),
                          );
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _allocationHint(
                    _snapAllocation(_debouncedExtraAllocationPercent),
                  ),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Gap(AppSpacing.lg),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: SectionCard(
            title: 'Projected Liquid Cash',
            subtitle:
                'Pinch, scroll, or tap +/− to zoom · drag to pan. Numbered dots mark when each loan is paid off.',
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
                isPrivate: widget.state.preferences.privacyModeEnabled,
              ),
            ),
          ),
        ),

        const Gap(AppSpacing.lg),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: SectionCard(
            title: 'Payoff Priority & Timeline',
            subtitle:
                'Drag and drop to change priority. The timeline reflects exactly when each loan pays off.',
            child: ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  final item = _priorityLoans.removeAt(oldIndex);
                  _priorityLoans.insert(newIndex, item);
                });
                final newOrder = _priorityLoans.map((l) => l.id).toList();
                // Important: Delay updatePreferences slightly so the ReorderableListView finishes its animation
                // before the parent triggers a rebuild with the new state.
                Future.delayed(const Duration(milliseconds: 50), () {
                  if (mounted) {
                    ref
                        .read(ledgerProvider.notifier)
                        .updatePreferencesWith(
                          (livePreferences) => livePreferences.copyWith(
                            loanPriorityIds: newOrder,
                          ),
                        );
                  }
                });
              },
              children: _priorityLoans.asMap().entries.map((entry) {
                final index = entry.key;
                final loan = entry.value;
                final event = result.payoffEvents.firstWhereOrNull(
                  (e) => e.loan.id == loan.id,
                );
                final payoffStr = event != null
                    ? ' · Pays off ${formatLedgerDate(event.payoffDate, locale)}'
                    : ' · No payoff date (check EMI)';
                final rawBal = accountBalance(widget.state, loan);
                final outstandingBal = rawBal.copyWith(
                  amountMinor: rawBal.amountMinor < 0 ? -rawBal.amountMinor : 0,
                );
                final balStr = maskMoneyIfPrivate(
                  widget.state,
                  'Outstanding: ${formatMoney(outstandingBal, locale)}',
                );

                return AppGroupedTile(
                  key: ValueKey(loan.id),
                  leading: ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle_rounded),
                  ),
                  title: Row(
                    children: [
                      Semantics(
                        label: 'Priority ${index + 1}',
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: scheme.primary,
                          child: Text(
                            '${index + 1}',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: scheme.onPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(child: Text(loan.name)),
                    ],
                  ),
                  subtitle: Text('$balStr$payoffStr'),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
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
  final color = tone.resolve(scheme);
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
    if (amount != null)
      maskMoneyIfPrivate(state, formatMoney(amount, state.preferences.locale)),
  ];
  return parts.join(' · ');
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

final _trailingZerosRegex = RegExp(r'0+$');
final _trailingDotRegex = RegExp(r'\.$');
final _nonNumericDotRegex = RegExp(r'[^0-9.]');

String _formatOptionalDecimal(double? value) {
  if (value == null) return '';
  if (value == value.roundToDouble()) return value.round().toString();
  return value
      .toStringAsFixed(2)
      .replaceFirst(_trailingZerosRegex, '')
      .replaceFirst(_trailingDotRegex, '');
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

String _formatAmountInput(int amountMinor, String currency) {
  if (amountMinor == 0) return '';
  final minors = math.pow(10, minorUnits(currency)).toInt();
  final integer = amountMinor ~/ minors;
  final fraction = amountMinor % minors;
  if (fraction == 0) return '$integer';
  return '$integer.${fraction.toString().padLeft(minorUnits(currency), '0')}';
}

int _amountMinorFromInput(String value, String currency) {
  final clean = value.replaceAll(_nonNumericDotRegex, '');
  if (clean.isEmpty) return 0;
  final parts = clean.split('.');
  final integer = int.tryParse(parts[0]) ?? 0;
  final fraction = parts.length > 1
      ? (int.tryParse(
              parts[1]
                  .padRight(minorUnits(currency), '0')
                  .substring(0, minorUnits(currency)),
            ) ??
            0)
      : 0;
  return integer * math.pow(10, minorUnits(currency)).toInt() + fraction;
}

void _showRouteMessage(BuildContext context, String message) =>
    showAppSnackBar(context, message);
