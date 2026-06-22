import 'dart:math' as math;
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
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
import '../../utils/recurrence_utils.dart';
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
          if (mode == 'forecast') ...[
            const Gap(AppSpacing.lg),
            LoanForecastView(state: state, loans: activeLoans),
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
  final _emiController = TextEditingController();
  final _rateController = TextEditingController();
  final _tenureController = TextEditingController();
  String? _loadedAccountId;
  String? _sourceAccountId;
  var _loanKind = 'loan';
  var _currency = kDefaultCurrency; // will be synced from state in _syncLoanDraft
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
    
    if (principalMinor > 0 && rate != null && rate > 0 && tenure != null && tenure > 0 && _frequency == 'monthly' && _interval == 1) {
      final monthlyRate = rate / 100 / 12;
      final numerator = principalMinor * monthlyRate * math.pow(1 + monthlyRate, tenure);
      final denominator = math.pow(1 + monthlyRate, tenure) - 1;
      final emiMinor = (numerator / denominator).round();
      
      final newText = _formatAmountInput(emiMinor);
      if (_emiController.text != newText && _emiController.text.isEmpty) {
        _emiController.text = newText;
      } else if (_emiController.text != newText && !_emiController.text.isEmpty) {
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
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [ThousandsSeparatorInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Principal',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      controller: _emiController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [ThousandsSeparatorInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Repayment amount',
                        prefixIcon: Icon(Icons.event_repeat_outlined),
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
                      controller: _rateController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [ThousandsSeparatorInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Rate %',
                        prefixIcon: Icon(Icons.percent_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      controller: _tenureController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Tenure count',
                        prefixIcon: Icon(Icons.timelapse_outlined),
                      ),
                    ),
                  ),
                ],
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
                onChanged: (value) => setState(() => _frequency = value ?? 'monthly'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                initialValue: _interval.toString(),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Every X ${_frequency == 'daily' ? 'day' : _frequency.replaceAll('ly', '')}s',
                  prefixIcon: const Icon(Icons.timer_outlined),
                ),
                onChanged: (value) => _interval = int.tryParse(value) ?? 1,
              ),
              if (_frequency == 'weekly') ...[
                const SizedBox(height: AppSpacing.md),
                Text('On these days:', style: Theme.of(context).textTheme.bodySmall),
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
                Text('On these days of the month:', style: Theme.of(context).textTheme.bodySmall),
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
                iconColor: sourceAccount == null ? null : accountDisplayColor(sourceAccount),
                onTap: () => _showSourceAccountPicker(state),
              ),
              const SizedBox(height: AppSpacing.sm),
              LiquidGlassSwitchListTile(
                title: const Text('Hide interest in main ledger'),
                value: _hideInterestInLedger,
                onChanged: (value) => setState(() => _hideInterestInLedger = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              PremiumRow(
                icon: Icons.calendar_month_outlined,
                title: 'Start date',
                subtitle: formatLedgerDate(_nextEmiDate, state.preferences.locale),
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
    final existingEmi = _existingLoanEmi(state, loan?.id);
    final repaymentAmount = details?.repaymentAmount;
    _emiController.text = repaymentAmount == null && existingEmi == null
        ? ''
        : _formatAmountInput(
            (repaymentAmount ?? existingEmi!.amount).amountMinor.abs(),
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
    _frequency = details?.recurrenceFrequency ?? 'monthly';
    _interval = details?.recurrenceInterval ?? 1;
    _daysOfWeek.clear();
    if (details?.recurrenceDaysOfWeek != null) {
      _daysOfWeek.addAll(details!.recurrenceDaysOfWeek!);
    }
    _daysOfMonth.clear();
    if (details?.recurrenceDaysOfMonth != null) {
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
        recurrenceDaysOfWeek: _daysOfWeek.isEmpty ? null : (List<int>.from(_daysOfWeek)..sort()),
        recurrenceDaysOfMonth: _daysOfMonth.isEmpty ? null : (List<int>.from(_daysOfMonth)..sort()),
        hideInterestInLedger: _hideInterestInLedger,
      );
      final loan = await ref
          .read(ledgerProvider.notifier)
          .upsertAccount(
            id: existingLoan?.id,
            name: name,
            type: _loanKind,
            currency: _currency,
            openingBalanceMinor: -principalMinor,
            institution: _lenderController.text,
            groupName: _nonLoanGroupName(existingLoan?.groupName),
            loanDetails: loanDetails,
            includeInTotals: false,
            includeInReports: true,
            includeInNetWorth: true,
            showOnHome: false,
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
              categoryId: _firstCategoryId(
                latestState,
                preferred: 'emi',
              ),
              paymentMethod: 'Auto debit',
              notes: 'Scheduled EMI for ${loan.name}',
              occurredAt: _nextEmiDate,
              recurrenceFrequency: _frequency,
              recurrenceInterval: _interval,
              recurrenceDaysOfWeek: _daysOfWeek.isEmpty ? null : (List<int>.from(_daysOfWeek)..sort()),
              recurrenceDaysOfMonth: _daysOfMonth.isEmpty ? null : (List<int>.from(_daysOfMonth)..sort()),
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
      context.go('/loans/${loan.id}');
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
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
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
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'LOAN ACCOUNT',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      formatMoney(
                        balance.copyWith(amountMinor: balance.amountMinor.abs()),
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
                  Builder(builder: (context) {
                    final principal = details.principal!.amountMinor.abs();
                    // Fix: calculate repayments inside scope
                    final repayments = _postedLoanRepayments(state, loan.id);
                    final paid = repayments.fold<int>(0, (sum, t) {
                      final amountInBase = convertMoneyForDisplay(
                        state,
                        t.amount,
                        loan.currency,
                      ).amountMinor.abs();
                      return sum + amountInBase;
                    });
                    final progress = principal > 0 ? (paid / principal).clamp(0.0, 1.0) : 0.0;
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
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (projection.monthsRemaining != null)
                              Text(
                                '${projection.monthsRemaining} mos left',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    );
                  }),
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
                tone: projection.monthlyEmi <= 0 ? MetricTone.warning : MetricTone.danger,
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
                value: details.interestRatePercent != null ? '${_formatOptionalDecimal(details.interestRatePercent)}% p.a.' : 'N/A',
                icon: Icons.percent_rounded,
                tone: MetricTone.standard,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: MetricTile(
                label: 'Tenure',
                value: details.repaymentCount != null ? '${details.repaymentCount} mo' : 'N/A',
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
    context.go('/loans');
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
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
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
                Builder(builder: (context) {
                  final principal = details.principal!.amountMinor.abs();
                  final repayments = _postedLoanRepayments(state, loan.id);
                  final paid = repayments.fold<int>(0, (sum, t) {
                    final amountInBase = convertMoneyForDisplay(
                      state,
                      t.amount,
                      loan.currency,
                    ).amountMinor.abs();
                    return sum + amountInBase;
                  });
                  final progress = principal > 0 ? (paid / principal).clamp(0.0, 1.0) : 0.0;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Paid: ${formatMoney(Money(amountMinor: paid, currency: loan.currency), state.preferences.locale)}',
                            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                          ),
                          if (projection.monthsRemaining != null)
                            Text(
                              '${projection.monthsRemaining} mos left',
                              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
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
                }),
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

class LoanForecastView extends ConsumerStatefulWidget {
  const LoanForecastView({required this.state, required this.loans, super.key});

  final LedgerState state;
  final List<Account> loans;

  @override
  ConsumerState<LoanForecastView> createState() => _LoanForecastViewState();
}

class _LoanForecastViewState extends ConsumerState<LoanForecastView> {
  final _incomeController = TextEditingController();
  final _emergencyController = TextEditingController();
  double _extraAllocationPercent = 0.5; // 50% extra to loans
  String _strategy = 'avalanche';

  @override
  void dispose() {
    _incomeController.dispose();
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

    final incomeMinor = _amountMinorFromInput(_incomeController.text).abs();
    final emergencyMinor = _amountMinorFromInput(_emergencyController.text).abs();

    final result = simulateAcceleratedPayoff(
      state: widget.state,
      loans: widget.loans,
      monthlyIncomeMinor: incomeMinor,
      monthlyEmergencySavingMinor: emergencyMinor,
      extraPaymentAllocationPercent: _extraAllocationPercent,
      priorityStrategy: _strategy,
    );

    final locale = widget.state.preferences.locale;
    final currency = widget.state.preferences.baseCurrency;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Budget & Control',
          subtitle: 'Adjust your expected income and emergency targets.',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _incomeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Monthly Income',
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      controller: _emergencyController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Emergency Save',
                        prefixIcon: Icon(Icons.savings_outlined),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Extra Cash Allocation', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                      Text('${(_extraAllocationPercent * 100).toInt()}% to Loans', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: scheme.primary)),
                    ],
                  ),
                  Slider(
                    value: _extraAllocationPercent,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    onChanged: (val) => setState(() => _extraAllocationPercent = val),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('0% (Base EMI only)', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                      Text('100% (Aggressive)', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                value: _strategy,
                decoration: const InputDecoration(
                  labelText: 'Payoff Priority Strategy',
                  prefixIcon: Icon(Icons.sort_rounded),
                ),
                items: const [
                  DropdownMenuItem(value: 'avalanche', child: Text('Avalanche (Highest Interest First)')),
                  DropdownMenuItem(value: 'snowball', child: Text('Snowball (Lowest Balance First)')),
                ],
                onChanged: (val) => setState(() => _strategy = val ?? 'avalanche'),
              ),
            ],
          ),
        ),
        const Gap(AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: MetricTile(
                label: 'Interest Saved',
                value: formatMoney(Money(amountMinor: result.totalInterestSavedMinor, currency: currency), locale),
                icon: Icons.savings_rounded,
                tone: result.totalInterestSavedMinor > 0 ? MetricTone.positive : MetricTone.standard,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: MetricTile(
                label: 'Months Saved',
                value: '${result.totalBaseMonths - result.totalAcceleratedMonths} mos',
                icon: Icons.calendar_month_rounded,
                tone: (result.totalBaseMonths - result.totalAcceleratedMonths) > 0 ? MetricTone.positive : MetricTone.standard,
              ),
            ),
          ],
        ),
        const Gap(AppSpacing.lg),
        for (final proj in result.projections) ...[
          SectionCard(
            title: proj.loan.name,
            subtitle: proj.monthsSaved > 0 ? 'Payoff accelerated by ${proj.monthsSaved} months' : 'Standard payoff schedule',
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('New Payoff Date', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                    Text(
                      formatLedgerDate(DateTime.now().add(Duration(days: proj.acceleratedMonthsRemaining * 30)), locale),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Interest Saved', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                    Text(
                      formatMoney(Money(amountMinor: proj.interestSavedMinor, currency: proj.loan.currency), locale),
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: proj.interestSavedMinor > 0 ? scheme.primary : null),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Gap(AppSpacing.md),
        ],
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
                (transaction.status == 'void' && transaction.notes?.toLowerCase() == 'skipped')),
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

bool _isHistoricalLoanRepayment(TransactionRecord transaction) {
  if (transaction.status == 'void' && transaction.notes == 'Skipped') return true;
  if (transaction.status != 'scheduled') return true;
  final today = _loanStartOfToday();
  final occurredDay = DateTime(
    transaction.occurredAt.year,
    transaction.occurredAt.month,
    transaction.occurredAt.day,
  );
  return occurredDay.isBefore(today);
}

DateTime _loanStartOfToday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
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
  final existing = loan.loanDetails;
  if (existing != null) return existing;
  final existingEmi = _existingLoanEmi(state, loan.id);
  return AccountLoanDetails(
    loanKind: loan.type,
    principal: Money(
      amountMinor: loan.openingBalance.amountMinor.abs(),
      currency: loan.currency,
    ),
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
  final amount = details.repaymentAmount ?? scheduledEmi?.amount;
  final date = details.repaymentStartsOn ?? scheduledEmi?.occurredAt;
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

int _projectedLoanRemaining(LedgerState state, Account loan, int months) {
  final remaining = accountBalance(state, loan).amountMinor.abs();
  final details = _effectiveLoanDetails(state, loan);
  final emi =
      details.repaymentAmount?.amountMinor.abs() ??
      _existingLoanEmi(state, loan.id)?.amount.amountMinor.abs() ??
      0;
  final rate = details.interestRatePercent ?? 0;
  if (months <= 0 || remaining == 0 || emi <= 0) return remaining;
  return _simulateLoanForecast(
    principalMinor: remaining,
    monthlyEmiMinor: emi,
    annualRatePercent: rate,
    maxMonths: months,
  ).remainingMinor;
}

List<int> _forecastMonthsForLoan(LedgerState state, Account loan) {
  final projection = _loanProjection(state, loan);
  final months = projection.monthsRemaining;
  final values = <int>{0, 3, 6, 12};
  if (months != null && months > 0) values.add(months);
  final sorted = values.toList()..sort();
  return sorted
      .where((month) => months == null || month == 0 || month <= months)
      .toList();
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
