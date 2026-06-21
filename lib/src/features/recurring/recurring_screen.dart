import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../common/route_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';


import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../utils/recurrence_utils.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/currency_picker.dart';
import '../common/category_hierarchy_picker.dart';
import '../common/full_screen_picker.dart';
import '../transactions/transaction_row.dart';
import '../transactions/transactions_components.dart';

class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key, this.mode = 'overview', this.recordId});

  final String mode;
  final String? recordId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ledgerProvider);
    final scheduled = _orderedRecurringTransactions(
      scheduledTransactions(state),
    );
    final recurringHistory = _recurringHistoryTransactions(state);
    final selected = recordId == null
        ? null
        : state.transactions.firstWhereOrNull(
            (transaction) => transaction.id == recordId,
          );
    final listed = mode == 'past' ? recurringHistory : scheduled;
    
    final targetCurrency = state.preferences.displayCurrency;
    
    int plannedIncomeMinor = 0;
    int plannedExpenseMinor = 0;
    
    for (final t in listed) {
      if (t.status == 'paused') continue;

      final moneyToConvert = t.originalAmount ?? t.amount;
      final converted = convertMoneyForDisplay(state, moneyToConvert, targetCurrency);
      final amount = converted.amountMinor.abs();

      if (incomeTypes.contains(t.type)) {
        plannedIncomeMinor += amount;
      } else if (t.type != 'transfer') {
        plannedExpenseMinor += amount;
      }
    }

    final netMinor = plannedIncomeMinor - plannedExpenseMinor;

    final displayIncome = Money(amountMinor: plannedIncomeMinor, currency: targetCurrency);
    final displayExpense = Money(amountMinor: plannedExpenseMinor, currency: targetCurrency);
    final displayNet = Money(amountMinor: netMinor, currency: targetCurrency);
    
    final incomeText = formatMoney(displayIncome, state.preferences.locale);
    final expenseText = formatMoney(displayExpense, state.preferences.locale);
    final netText = formatMoney(displayNet, state.preferences.locale);

    return RouteScaffold(
      title: switch (mode) {
        'new' => 'New recurring',
        'past' => 'Past recurring',
        'edit' => 'Edit recurring',
        _ when recordId != null => 'Planned detail',
        _ => 'Planned payments',
      },
      actions: [
        if (recordId != null && mode != 'edit' && mode != 'new' && selected != null)
          IconButton(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete plan?'),
                  content: const Text(
                      'This will permanently delete this scheduled payment. Historical payments posted from this plan will not be deleted.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await ref.read(ledgerProvider.notifier).deleteTransaction(selected.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Plan deleted.')),
                  );
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/recurring');
                  }
                }
              }
            },
            icon: const Icon(Icons.delete_outline_rounded),
            color: Theme.of(context).colorScheme.error,
          )
        else if (mode != 'edit' && mode != 'new' && mode != 'past')
          IconButton(
            onPressed: () => context.push('/recurring/new'),
            icon: const Icon(Icons.add_rounded),
          ),
      ],
      child: Column(
        children: [
          if (recordId == null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Card(
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            mode == 'past' ? 'Historical summary' : 'Planned summary',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(AppRadii.pill),
                            ),
                            child: Text(
                              '${listed.length} items',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      MiniFlowRail(income: incomeText, expense: expenseText, net: netText),
                    ],
                  ),
                ),
              ),
            ),
            const Gap(AppSpacing.lg),
          ],
          if (mode == 'new' || mode == 'edit')
            RecurringForm(recordId: recordId)
          else if (recordId != null)
            selected == null
                ? EmptyState(
                    icon: Icons.event_busy_outlined,
                    title: 'Planned record not found',
                    body:
                        'This scheduled record is not available in the local ledger.',
                    actionLabel: 'Back to planned payments',
                    onAction: () => context.push('/recurring'),
                  )
                : RecurringDetailView(transaction: selected)
          else if (listed.isEmpty)
            EmptyState(
              icon: mode == 'past'
                  ? Icons.history_rounded
                  : Icons.event_repeat_outlined,
              title: mode == 'past'
                  ? 'No posted recurring history yet'
                  : 'No planned payments yet',
              body: mode == 'past'
                  ? 'Posted recurring records will appear here once a scheduled item is completed.'
                  : 'Create a scheduled record to keep bills, transfers, and repayments on track.',
              actionLabel: mode == 'past'
                  ? 'Back to planned payments'
                  : 'Create recurring',
              onAction: () => context.push(
                mode == 'past' ? '/recurring' : '/recurring/new',
              ),
            )
          else
            for (final transaction in listed) ...[
              if (mode == 'past')
                TransactionRow(
                  state: state,
                  transaction: transaction,
                  onTap: () => context.push('/records/${transaction.id}'),
                )
              else
                _RecurringCompactCard(
                  state: state,
                  transaction: transaction,
                  onTap: () => context.push('/recurring/${transaction.id}'),
                  historyMode: false,
                ),
              const SizedBox(height: AppSpacing.sm),
            ],
        ],
      ),
    );
  }
}

List<TransactionRecord> _recurringHistoryTransactions(LedgerState state) {
  final items = state.transactions
      .where(
        (transaction) =>
            _isRecurringHistorySource(transaction.source) &&
            transaction.status != 'void' &&
            _isHistoricalRecurringTransaction(transaction),
      )
      .toList();
  items.sort(_compareRecurringHistory);
  return items;
}

bool _isRecurringHistorySource(String source) {
  return source == 'recurring' || source == 'rule';
}

bool _isHistoricalRecurringTransaction(TransactionRecord transaction) {
  if (transaction.status != 'scheduled') return true;
  final today = _startOfToday();
  final occurredDay = DateTime(
    transaction.occurredAt.year,
    transaction.occurredAt.month,
    transaction.occurredAt.day,
  );
  return occurredDay.isBefore(today);
}

DateTime _startOfToday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

List<TransactionRecord> _orderedRecurringTransactions(
  List<TransactionRecord> transactions,
) {
  final items = [...transactions];
  items.sort((left, right) {
    if (left.status == 'paused' && right.status != 'paused') return 1;
    if (left.status != 'paused' && right.status == 'paused') return -1;
    final dateCompare = left.occurredAt.compareTo(right.occurredAt);
    if (dateCompare != 0) return dateCompare;
    final amountCompare = right.amount.amountMinor.abs().compareTo(
      left.amount.amountMinor.abs(),
    );
    if (amountCompare != 0) return amountCompare;
    return left.id.compareTo(right.id);
  });
  return items;
}

int _compareRecurringHistory(TransactionRecord left, TransactionRecord right) {
  final dateCompare = right.occurredAt.compareTo(left.occurredAt);
  if (dateCompare != 0) return dateCompare;
  final amountCompare = right.amount.amountMinor.abs().compareTo(
    left.amount.amountMinor.abs(),
  );
  if (amountCompare != 0) return amountCompare;
  return right.id.compareTo(left.id);
}

class _RecurringCompactCard extends StatelessWidget {
  const _RecurringCompactCard({
    required this.state,
    required this.transaction,
    required this.onTap,
    required this.historyMode,
  });

  final LedgerState state;
  final TransactionRecord transaction;
  final VoidCallback onTap;
  final bool historyMode;

  @override
  Widget build(BuildContext context) {
    final account = accountById(state, transaction.accountId);
    final counter = accountById(state, transaction.counterAccountId);
    final category = categoryById(state, transaction.categoryId);
    final scheme = Theme.of(context).colorScheme;
    final headerTitle = _recurringHeaderTitle(state, transaction);
    final defaultPrimaryTitle = _recurringPrimaryTitle(state, transaction);
    final hasName = transaction.name?.trim().isNotEmpty == true;
    final primaryTitle = hasName ? transaction.name!.trim() : defaultPrimaryTitle;
    final categorySubtitle = hasName ? defaultPrimaryTitle : null;
    
    final recurrence = _recurringCadenceLabel(transaction.recurrenceFrequency, transaction.recurrenceInterval);
    final extraLine = _recurringExtraLine(
      state,
      transaction,
      account,
      counter,
      defaultPrimaryTitle,
      headerTitle,
    );
    final status = _recurringStatus(
      context,
      transaction.occurredAt,
      locale: state.preferences.locale,
      historyMode: historyMode,
      isVoid: transaction.status == 'void',
      isPaused: transaction.status == 'paused',
    );
    final amountText = _recurringAmountLabel(state, transaction);

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
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RoundRecurringIcon(
                    icon: category != null ? categoryIcon(category) : transactionIcon(transaction),
                    color: categoryColor(category, context),
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
                        if (categorySubtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            categorySubtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                        const SizedBox(height: 2),
                        Text(
                          recurrence,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                        if (extraLine != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            extraLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                              fontSize: 13,
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
                        amountText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: (transaction.status == 'void' || transaction.status == 'paused') ? scheme.outline : _recurringAmountColor(
                                context,
                                transaction,
                              ),
                              decoration: transaction.status == 'void' ? TextDecoration.lineThrough : null,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Icon(status.icon, color: status.color, size: 14),
                          const SizedBox(width: 4),
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
                ],
              ),
              if (!historyMode && (account?.loanDetails != null || counter?.loanDetails != null))
                Builder(builder: (context) {
                  final loanAccount = account?.loanDetails != null ? account : counter;
                  final total = loanAccount?.loanDetails?.repaymentCount;
                  if (total == null || total <= 0) return const SizedBox();
                  final postedCount = state.transactions.where((t) =>
                     (t.status == 'posted' || t.status == 'cleared') &&
                     (t.accountId == loanAccount!.id || t.counterAccountId == loanAccount.id) &&
                     t.type == 'loan_repayment'
                  ).length;
                  final progress = (postedCount / total).clamp(0.0, 1.0);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Payment $postedCount of $total',
                            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${total - postedCount} left',
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
          ),
        ),
      ),
    );
  }
}

class _RoundRecurringIcon extends StatelessWidget {
  const _RoundRecurringIcon({required this.icon, required this.color});

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

class RecurringForm extends ConsumerStatefulWidget {
  const RecurringForm({super.key, this.recordId});

  final String? recordId;

  @override
  ConsumerState<RecurringForm> createState() => _RecurringFormState();
}

class _RecurringFormState extends ConsumerState<RecurringForm> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  String? _loadedRecordId;
  var _type = 'expense';
  String? _currency;
  var _frequency = 'monthly';
  int _interval = 1;
  final Set<int> _daysOfWeek = {};
  final Set<int> _daysOfMonth = {};
  String? _accountId;
  String? _counterAccountId;
  String? _categoryId;
  DateTime _nextDate = DateTime.now().add(const Duration(days: 1));
  String? _postMode;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerProvider);
    final record = widget.recordId == null
        ? null
        : state.transactions.firstWhereOrNull(
            (transaction) => transaction.id == widget.recordId,
          );
    _syncRecurringDraft(state, record);
    final account = accountById(state, _accountId);
    final counterAccount = accountById(state, _counterAccountId);
    final category = categoryById(state, _categoryId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: record == null ? 'Recurring rule' : 'Edit recurring rule',
          subtitle:
              'Creates a scheduled ledger record for the next occurrence.',
          child: Column(
            children: [
              PremiumRow(
                icon: transactionIcon(
                  TransactionRecord(
                    id: 'draft',
                    type: _type,
                    status: 'scheduled',
                    source: 'recurring',
                    accountId: _accountId ?? '',
                    amount: Money(
                      amountMinor: 0,
                      currency: _currency ?? state.preferences.baseCurrency,
                    ),
                    baseAmount: Money(
                      amountMinor: 0,
                      currency: _currency ?? state.preferences.baseCurrency,
                    ),
                    occurredAt: _nextDate,
                  ),
                ),
                title: 'Type',
                subtitle: transactionTypeLabel(_type),
                onTap: _showRecurringTypePicker,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Plan Name (optional)',
                  prefixIcon: Icon(Icons.title_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 100,
                    child: OutlinedButton(
                      onPressed: () => _showCurrencyPicker(state),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size.fromHeight(56),
                      ),
                      child: Text(_currency ?? state.preferences.baseCurrency),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              PremiumRow(
                icon: account == null
                    ? Icons.wallet_outlined
                    : accountIcon(account),
                title: _type == 'transfer' ? 'From account' : 'Account',
                subtitle: account?.name ?? 'Choose account',
                iconColor: account?.color,
                onTap: () => _showRecurringAccountPicker(state, counter: false),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_needsCounterAccount)
                PremiumRow(
                  icon: counterAccount == null
                      ? Icons.swap_horiz_rounded
                      : accountIcon(counterAccount),
                  title: _type == 'transfer' ? 'To account' : 'Linked account',
                  subtitle: counterAccount?.name ?? 'Choose destination',
                  iconColor: counterAccount?.color,
                  onTap: () =>
                      _showRecurringAccountPicker(state, counter: true),
                )
              else
                PremiumRow(
                  icon: categoryIcon(category),
                  title: 'Category',
                  subtitle: category == null
                      ? 'Choose category'
                      : categoryPath(state, category),
                  iconColor: categoryColor(category, context),
                  onTap: () => _showRecurringCategoryPicker(state),
                ),
            ],
          ),
        ),
        const Gap(AppSpacing.lg),
        SectionCard(
          title: 'Schedule',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _postMode == 'auto' ? 'auto' : 'manual',
                decoration: const InputDecoration(
                  labelText: 'Automation',
                  prefixIcon: Icon(Icons.smart_toy_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'manual', child: Text('Manual review (Require confirmation)')),
                  DropdownMenuItem(value: 'auto', child: Text('Auto-post payment on date')),
                ],
                onChanged: (value) => setState(() => _postMode = value == 'auto' ? 'auto' : null),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _frequency,
                decoration: const InputDecoration(
                  labelText: 'Frequency',
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
                              _daysOfWeek.add(i);
                              _updateNextDateToMatchRecurrence();
                            } else {
                              _daysOfWeek.remove(i);
                              _updateNextDateToMatchRecurrence();
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
                              _daysOfMonth.add(i);
                              _updateNextDateToMatchRecurrence();
                            } else {
                              _daysOfMonth.remove(i);
                              _updateNextDateToMatchRecurrence();
                            }
                          });
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              PremiumRow(
                icon: Icons.calendar_month_outlined,
                title: 'Next date',
                subtitle: formatLedgerDate(_nextDate, state.preferences.locale),
                onTap: _pickRecurringDate,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
            ],
          ),
        ),
        const Gap(AppSpacing.lg),
        FilledButton.icon(
          onPressed: () => _saveRecurring(state, record),
          icon: const Icon(Icons.save_outlined),
          label: Text(
            record == null
                ? 'Create scheduled record'
                : 'Save scheduled record',
          ),
        ),
      ],
    );
  }

  bool get _needsCounterAccount =>
      _type == 'transfer' ||
      _type == 'card_payment' ||
      _type == 'loan_repayment';

  void _syncRecurringDraft(LedgerState state, TransactionRecord? record) {
    final key = record?.id ?? '__new__';
    if (_loadedRecordId == key) return;
    _loadedRecordId = key;
    _type = record?.type ?? 'expense';
    
    final draftMoney = record?.originalAmount ?? record?.amount;
    _currency = draftMoney?.currency ?? state.preferences.baseCurrency;
    _amountController.text = draftMoney == null
        ? ''
        : _formatAmountInput(draftMoney.amountMinor.abs(), _currency!);
        
    _nameController.text = record?.name ?? '';
    _accountId = record?.accountId ?? state.accounts.firstOrNull?.id;
    _counterAccountId = record?.counterAccountId;
    _categoryId = record?.categoryId ?? _firstCategoryId(state);
    _nextDate =
        record?.occurredAt ?? DateTime.now().add(const Duration(days: 1));
    _notesController.text = record?.notes ?? '';
    _postMode = record?.postMode;
    _frequency = record?.recurrenceFrequency ?? 'monthly';
    _interval = record?.recurrenceInterval ?? 1;
    _daysOfWeek.clear();
    if (record?.recurrenceDaysOfWeek != null) {
      _daysOfWeek.addAll(record!.recurrenceDaysOfWeek!);
    }
    _daysOfMonth.clear();
    if (record?.recurrenceDaysOfMonth != null) {
      _daysOfMonth.addAll(record!.recurrenceDaysOfMonth!);
    }
  }

  void _updateNextDateToMatchRecurrence() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Subtract one day so that if today is a valid day, it gets picked immediately.
    final currentCursor = today.subtract(const Duration(days: 1));
    
    _nextDate = advanceRecurrenceCursor(
      current: currentCursor,
      frequency: _frequency,
      interval: _interval,
      daysOfWeek: _daysOfWeek.toList(),
      daysOfMonth: _daysOfMonth.toList(),
    );
  }

  Future<void> _showCurrencyPicker(LedgerState state) async {
    final next = await showCurrencyPicker(
      context: context,
      state: state,
      selectedValue: _currency ?? state.preferences.baseCurrency,
    );
    if (next == null) return;
    setState(() => _currency = next);
  }

  Future<void> _showRecurringTypePicker() async {
    final next = await showFullScreenPicker<String>(
      context: context,
      title: 'Recurring type',
      searchable: false,
      selectedValue: _type,
      options: const [
        PickerOption(
          value: 'expense',
          title: 'Expense',
          icon: Icons.arrow_upward_rounded,
        ),
        PickerOption(
          value: 'income',
          title: 'Income',
          icon: Icons.arrow_downward_rounded,
        ),
        PickerOption(
          value: 'transfer',
          title: 'Transfer',
          icon: Icons.swap_horiz_rounded,
        ),
        PickerOption(
          value: 'card_payment',
          title: 'Card payment',
          icon: Icons.credit_card_outlined,
        ),
        PickerOption(
          value: 'loan_repayment',
          title: 'Loan repayment',
          icon: Icons.account_balance_outlined,
        ),
      ],
    );
    if (next == null) return;
    setState(() {
      _type = next;
      if (!_needsCounterAccount) _counterAccountId = null;
    });
  }

  Future<void> _showRecurringAccountPicker(
    LedgerState state, {
    required bool counter,
  }) async {
    final next = await showFullScreenPicker<String>(
      context: context,
      title: counter ? 'Choose linked account' : 'Choose account',
      searchHint: 'Search accounts',
      selectedValue: counter ? _counterAccountId : _accountId,
      options: [
        for (final account in sortAccounts(state.accounts.where(
          (account) =>
              !account.isArchived && (!counter || account.id != _accountId),
        )))
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
    setState(() {
      if (counter) {
        _counterAccountId = next;
      } else {
        _accountId = next;
        if (_counterAccountId == next) _counterAccountId = null;
      }
    });
  }

  Future<void> _showRecurringCategoryPicker(LedgerState state) async {
    final next = await showCategoryHierarchyPicker(
      context: context,
      state: state,
      selectedCategoryId: _categoryId,
    );
    if (next == null) return;
    setState(() => _categoryId = next);
  }

  Future<void> _pickRecurringDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _nextDate = picked);
  }

  Future<void> _saveRecurring(
    LedgerState state,
    TransactionRecord? existing,
  ) async {
    final amountMinor = _amountMinorFromInput(_amountController.text, _currency ?? state.preferences.baseCurrency).abs();
    final account = accountById(state, _accountId);
    if (amountMinor <= 0) {
      _showRouteMessage(context, 'Enter an amount.');
      return;
    }
    if (account == null) {
      _showRouteMessage(context, 'Choose an account.');
      return;
    }
    if (_needsCounterAccount && _counterAccountId == null) {
      _showRouteMessage(context, 'Choose the linked account.');
      return;
    }
    try {
      final originalCurrency = _currency ?? state.preferences.baseCurrency;
      
      int finalAmountMinor = amountMinor;
      if (originalCurrency != account.currency) {
        final converted = convertMoneyForDisplay(
          state, 
          Money(amountMinor: amountMinor, currency: originalCurrency), 
          account.currency,
        );
        finalAmountMinor = converted.amountMinor;
      }

      await ref
          .read(ledgerProvider.notifier)
          .upsertTransaction(
            id: existing?.id,
            type: _type,
            accountId: account.id,
            counterAccountId: _needsCounterAccount ? _counterAccountId : null,
            categoryId: _needsCounterAccount ? null : _categoryId,
            amountMinor: finalAmountMinor,
            originalCurrency: originalCurrency != account.currency ? originalCurrency : null,
            originalAmountMinor: originalCurrency != account.currency ? amountMinor : null,
            status: 'scheduled',
            source: 'recurring',
            name: _nameController.text,
            notes: _notesController.text,
            occurredAt: _nextDate,
            recurrenceFrequency: _frequency,
            recurrenceInterval: _interval,
            recurrenceDaysOfWeek: _daysOfWeek.isEmpty ? null : (List<int>.from(_daysOfWeek)..sort()),
            recurrenceDaysOfMonth: _daysOfMonth.isEmpty ? null : (List<int>.from(_daysOfMonth)..sort()),
            postMode: _postMode == 'auto' ? 'auto' : null,
          );
      if (!mounted) return;
      _showRouteMessage(
        context,
        existing == null
            ? 'Scheduled record created.'
            : 'Scheduled record saved.',
      );
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/recurring');
      }
    } catch (error) {
      if (!mounted) return;
      _showRouteMessage(context, error.toString());
    }
  }
}

class RecurringDetailView extends ConsumerWidget {
  const RecurringDetailView({required this.transaction, super.key});

  final TransactionRecord transaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ledgerProvider);
    final account = accountById(state, transaction.accountId);
    final counter = accountById(state, transaction.counterAccountId);
    final category = categoryById(state, transaction.categoryId);
    final frequency = transaction.recurrenceFrequency ?? 'manual';
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: scheme.primaryContainer,
                      foregroundColor: scheme.onPrimaryContainer,
                      child: Icon(
                        category == null ? Icons.event_repeat_rounded : Icons.category_rounded,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            transaction.name?.trim().isNotEmpty == true
                                ? transaction.name!.trim()
                                : (category?.name ?? transactionTypeLabel(transaction.type)),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${transaction.status.toUpperCase()} · ${transactionTypeLabel(frequency).toUpperCase()}${transaction.postMode == 'auto' ? ' (AUTO)' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _recurringAmountLabel(state, transaction),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Next payment', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                          Text(formatLedgerDate(transaction.occurredAt, state.preferences.locale), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(counter != null ? 'From account' : 'Account', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                          Text(account?.name ?? 'Unknown', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      if (counter != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('To account', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                            Text(counter.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (account?.loanDetails != null || counter?.loanDetails != null)
                  Builder(builder: (context) {
                    final loanAccount = account?.loanDetails != null ? account : counter;
                    final total = loanAccount?.loanDetails?.repaymentCount;
                    if (total == null || total <= 0) return const SizedBox();
                    final postedCount = state.transactions.where((t) =>
                       (t.status == 'posted' || t.status == 'cleared') &&
                       (t.accountId == loanAccount!.id || t.counterAccountId == loanAccount.id) &&
                       t.type == 'loan_repayment'
                    ).length;
                    final progress = (postedCount / total).clamp(0.0, 1.0);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Payment $postedCount of $total',
                              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${total - postedCount} left',
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
            ),
          ),
        ),
        const Gap(AppSpacing.lg),

        // Action Buttons
        if (transaction.status == 'scheduled')
          FilledButton.icon(
            onPressed: () => _postNow(context, ref),
            icon: const Icon(Icons.check_circle_rounded),
            label: const Text('Post payment now'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        const Gap(AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: transaction.status == 'scheduled' ? () => _postpone(context, ref) : null,
              icon: const Icon(Icons.snooze_outlined, size: 18),
              label: const Text('Postpone'),
            ),
            OutlinedButton.icon(
              onPressed: transaction.status == 'scheduled' ? () => _skip(context, ref) : null,
              icon: const Icon(Icons.skip_next_rounded, size: 18),
              label: const Text('Skip next'),
            ),
            OutlinedButton.icon(
              onPressed: () => context.push('/recurring/${transaction.id}/edit'),
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text('Edit'),
            ),
            if (transaction.status == 'scheduled' || transaction.status == 'paused')
              OutlinedButton.icon(
                onPressed: () => transaction.status == 'paused' ? _resume(context, ref) : _pause(context, ref),
                icon: Icon(transaction.status == 'paused' ? Icons.play_circle_outline_rounded : Icons.pause_circle_outline_rounded, size: 18),
                label: Text(transaction.status == 'paused' ? 'Resume' : 'Pause'),
                style: transaction.status == 'paused' 
                    ? OutlinedButton.styleFrom(foregroundColor: scheme.primary)
                    : null,
              ),
          ],
        ),
        const Gap(AppSpacing.xxl),

        // History
        _RecurringHistoryList(plan: transaction),
      ],
    );
  }

  Future<void> _postNow(BuildContext context, WidgetRef ref) async {
    context.push('/add?plannedId=${transaction.id}');
  }

  Future<void> _postpone(BuildContext context, WidgetRef ref) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: transaction.occurredAt.isBefore(DateTime.now())
          ? DateTime.now().add(const Duration(days: 1))
          : transaction.occurredAt.add(const Duration(days: 1)),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked == null) return;

    await ref
        .read(ledgerProvider.notifier)
        .postponeTransaction(transaction.id, picked);
    if (!context.mounted) return;

    final locale = ref.read(ledgerProvider).preferences.locale;
    _showRouteMessage(
      context,
      'Scheduled record postponed to ${formatLedgerDate(picked, locale)}.',
    );
    context.go('/recurring');
  }

  Future<void> _skip(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(ledgerProvider.notifier);
    final nextDate = advanceTransactionRecurrence(transaction.occurredAt, transaction);
    
    await notifier.upsertTransaction(
      type: transaction.type,
      accountId: transaction.accountId,
      amountMinor: transaction.amount.amountMinor,
      status: 'void',
      source: transaction.source,
      counterAccountId: transaction.counterAccountId,
      categoryId: transaction.categoryId,
      paymentMethod: transaction.paymentMethod,
      notes: 'Skipped',
      occurredAt: transaction.occurredAt,
      originalTransactionId: transaction.id,
      recurrenceFrequency: transaction.recurrenceFrequency,
      originalAmountMinor: transaction.originalAmount?.amountMinor,
      originalCurrency: transaction.originalAmount?.currency,
      counterAmountMinor: transaction.counterAmount?.amountMinor,
    );
    
    await notifier.updateTransactionStatus(
      transaction.id,
      'scheduled',
      occurredAt: nextDate,
    );
    if (!context.mounted) return;
    _showRouteMessage(context, 'Scheduled record skipped.');
    context.go('/recurring');
  }

  Future<void> _pause(BuildContext context, WidgetRef ref) async {
    await ref.read(ledgerProvider.notifier).updateTransactionStatus(
      transaction.id,
      'paused',
    );
    if (!context.mounted) return;
    _showRouteMessage(context, 'Scheduled record paused.');
    context.go('/recurring');
  }

  Future<void> _resume(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var nextDate = transaction.occurredAt;
    final notifier = ref.read(ledgerProvider.notifier);

    // Advance the date until it's tomorrow or later
    while (!nextDate.isAfter(today)) {
      await notifier.upsertTransaction(
        type: transaction.type,
        accountId: transaction.accountId,
        amountMinor: transaction.amount.amountMinor,
        status: 'void',
        source: transaction.source,
        counterAccountId: transaction.counterAccountId,
        categoryId: transaction.categoryId,
        paymentMethod: transaction.paymentMethod,
        notes: 'Skipped (Paused)',
        occurredAt: nextDate,
        originalTransactionId: transaction.id,
        recurrenceFrequency: transaction.recurrenceFrequency,
        originalAmountMinor: transaction.originalAmount?.amountMinor,
        originalCurrency: transaction.originalAmount?.currency,
        counterAmountMinor: transaction.counterAmount?.amountMinor,
      );
      nextDate = advanceTransactionRecurrence(nextDate, transaction);
    }

    await notifier.updateTransactionStatus(
      transaction.id,
      'scheduled',
      occurredAt: nextDate,
    );
    if (!context.mounted) return;
    final locale = ref.read(ledgerProvider).preferences.locale;
    _showRouteMessage(context, 'Scheduled record resumed for ${formatLedgerDate(nextDate, locale)}.');
    context.go('/recurring');
  }
}

class _RecurringHistoryList extends ConsumerWidget {
  const _RecurringHistoryList({required this.plan});

  final TransactionRecord plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ledgerProvider);
    final history = state.transactions
        .where((t) =>
            t.originalTransactionId == plan.id &&
            (t.status != 'scheduled' || (t.status == 'void' && t.notes?.toLowerCase() == 'skipped')) &&
            t.id != plan.id)
        .toList();

    if (history.isEmpty) return const SizedBox.shrink();

    history.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Text(
            'Past payments',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final item in history) ...[
          _RecurringCompactCard(
            state: state,
            transaction: item,
            onTap: () => context.push('/transaction/${item.id}'),
            historyMode: true,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
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
  final clean = value.replaceAll(RegExp(r'[^0-9.]'), '');
  if (clean.isEmpty) return 0;
  final parts = clean.split('.');
  final integer = int.tryParse(parts[0]) ?? 0;
  final fraction = parts.length > 1
      ? (int.tryParse(parts[1].padRight(minorUnits(currency), '0').substring(0, minorUnits(currency))) ?? 0)
      : 0;
  return integer * math.pow(10, minorUnits(currency)).toInt() + fraction;
}

void _showRouteMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
}

String _recurringHeaderTitle(LedgerState state, TransactionRecord transaction) {
  final notes = transaction.notes?.trim();
  if (notes != null && notes.isNotEmpty) {
    return notes.replaceFirst(
      RegExp(r'^Scheduled EMI for\s+', caseSensitive: false),
      '',
    );
  }
  final counter = accountById(state, transaction.counterAccountId);
  if (transaction.type == 'loan_repayment' && counter != null) {
    return counter.name;
  }
  final category = categoryById(state, transaction.categoryId);
  return category?.name ?? transactionTypeLabel(transaction.type);
}

String _recurringPrimaryTitle(
  LedgerState state,
  TransactionRecord transaction,
) {
  final category = categoryById(state, transaction.categoryId);
  final counter = accountById(state, transaction.counterAccountId);
  if (transaction.type == 'loan_repayment' && counter != null) {
    return counter.name;
  }
  if (transaction.type == 'transfer' && counter != null) {
    return 'Transfer to ${counter.name}';
  }
  return category?.name ?? transactionTypeLabel(transaction.type);
}

String _recurringCadenceLabel(String? frequency, [int interval = 1]) {
  final n = interval < 1 ? 1 : interval;
  final unit = switch (frequency) {
    'daily' => n == 1 ? 'day' : 'days',
    'weekly' => n == 1 ? 'week' : 'weeks',
    'yearly' => n == 1 ? 'year' : 'years',
    'monthly' || null => n == 1 ? 'month' : 'months',
    _ => frequency,
  };
  return 'Every $n $unit';
}

String? _recurringExtraLine(
  LedgerState state,
  TransactionRecord transaction,
  Account? account,
  Account? counter,
  String primaryTitle,
  String headerTitle,
) {
  if (transaction.type == 'loan_repayment' && counter != null) {
    return '"${counter.name}"';
  }
  final accountName = transaction.type == 'transfer'
      ? [
          account?.name,
          if (counter != null) counter.name,
        ].whereType<String>().join(' → ')
      : account?.name;
  if (accountName != null &&
      accountName.trim().isNotEmpty &&
      accountName != primaryTitle &&
      accountName != headerTitle) {
    return '"$accountName"';
  }
  return null;
}

({String label, IconData icon, Color color}) _recurringStatus(
  BuildContext context,
  DateTime date, {
  required String locale,
  required bool historyMode,
  bool isVoid = false,
  bool isPaused = false,
}) {
  final scheme = Theme.of(context).colorScheme;
  if (historyMode) {
    if (isVoid) {
      return (
        label: 'Skipped ${formatLedgerDate(date, locale)}',
        icon: Icons.block_rounded,
        color: scheme.outline,
      );
    }
    return (
      label: formatLedgerDate(date, locale),
      icon: Icons.history_rounded,
      color: scheme.primary,
    );
  }
  if (isPaused) {
    return (
      label: 'Paused',
      icon: Icons.pause_circle_outline_rounded,
      color: scheme.outline,
    );
  }
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final diff = target.difference(today).inDays;
  if (diff < 0) {
    return (
      label: formatDueDate(date, locale),
      icon: Icons.warning_rounded,
      color: scheme.error,
    );
  }
  if (diff == 0) {
    return (
      label: formatDueDate(date, locale),
      icon: Icons.notification_important_outlined,
      color: scheme.secondary,
    );
  }
  if (diff == 1) {
    return (
      label: formatDueDate(date, locale),
      icon: Icons.history_toggle_off_rounded,
      color: scheme.secondary,
    );
  }
  return (
    label: formatDueDate(date, locale),
    icon: Icons.history_toggle_off_rounded,
    color: scheme.secondary,
  );
}

String _recurringAmountLabel(LedgerState state, TransactionRecord transaction) {
  final isNegative = !incomeTypes.contains(transaction.type);
  final sign = isNegative ? '-' : '+';
  final displayMoney = transaction.originalAmount ?? transaction.amount;
  return '$sign${formatMoney(displayMoney.copyWith(amountMinor: displayMoney.amountMinor.abs()), state.preferences.locale)}';
}

Color _recurringAmountColor(
  BuildContext context,
  TransactionRecord transaction,
) {
  if (incomeTypes.contains(transaction.type)) {
    return amountColor(context, transaction.amount.amountMinor.abs());
  }
  return Theme.of(context).colorScheme.error;
}
