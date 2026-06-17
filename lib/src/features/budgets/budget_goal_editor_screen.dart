import 'package:flutter/material.dart';
import '../common/route_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/currency_picker.dart';

class BudgetGoalEditorScreen extends ConsumerStatefulWidget {
  const BudgetGoalEditorScreen({required this.kind, super.key});

  final String kind;

  @override
  ConsumerState<BudgetGoalEditorScreen> createState() =>
      _BudgetGoalEditorScreenState();
}

class _BudgetGoalEditorScreenState
    extends ConsumerState<BudgetGoalEditorScreen> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  var _primaryRuleEnabled = true;
  var _secondaryRuleEnabled = false;
  String? _selectedCurrency;
  DateTime? _targetDate;
  String _frequency = 'once';
  int _interval = 1;
  final Set<int> _daysOfWeek = {};
  final Set<int> _daysOfMonth = {};

  @override
  void initState() {
    super.initState();
    _frequency = widget.kind == 'budget' ? 'monthly' : 'once';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isBudget = widget.kind == 'budget';
    final state = ref.watch(ledgerProvider);
    return RouteScaffold(
      title: isBudget ? 'New budget' : 'New goal',
      actions: [
        IconButton(onPressed: _save, icon: const Icon(Icons.check_rounded)),
      ],
      child: Column(
        children: [
          SectionCard(
            title: isBudget ? 'Budget setup' : 'Goal setup',
            subtitle: isBudget
                ? 'Category-based budget with rollover and overspend flags.'
                : 'Save-up goal with target amount and target date.',
            child: Column(
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: isBudget ? 'Budget name' : 'Goal name',
                    prefixIcon: Icon(
                      isBudget
                          ? Icons.donut_large_outlined
                          : Icons.flag_outlined,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Target amount',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _DetailField(
                  icon: isBudget
                      ? Icons.category_outlined
                      : Icons.today_outlined,
                  label: isBudget 
                      ? 'Choose category' 
                      : (_targetDate == null ? 'Target date' : '${_targetDate!.day}/${_targetDate!.month}/${_targetDate!.year}'),
                  onTap: _chooseDate,
                ),
                const SizedBox(height: AppSpacing.sm),
                _DetailField(
                  icon: Icons.currency_exchange_outlined,
                  label: _selectedCurrency ?? state.preferences.baseCurrency,
                  onTap: () => _chooseCurrency(context, state),
                ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Recurrence',
            subtitle: 'How often should this plan repeat?',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _frequency,
                  decoration: const InputDecoration(labelText: 'Frequency'),
                  items: const [
                    DropdownMenuItem(value: 'once', child: Text('Once')),
                    DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                  ],
                  onChanged: (value) => setState(() => _frequency = value ?? 'once'),
                ),
                if (_frequency != 'once') ...[
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    initialValue: _interval.toString(),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Every X ${_frequency == 'daily' ? 'day' : _frequency.replaceAll('ly', '')}s',
                    ),
                    onChanged: (value) => _interval = int.tryParse(value) ?? 1,
                  ),
                ],
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
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          SectionCard(
            title: isBudget ? 'Rules' : 'Pace',
            child: Column(
              children: [
                LiquidGlassSwitchListTile(
                  value: _primaryRuleEnabled,
                  onChanged: (value) =>
                      setState(() => _primaryRuleEnabled = value),
                  title: Text(
                    isBudget ? 'Warn on overspend' : 'Show on dashboard',
                  ),
                ),
                LiquidGlassSwitchListTile(
                  value: _secondaryRuleEnabled,
                  onChanged: (value) =>
                      setState(() => _secondaryRuleEnabled = value),
                  title: Text(
                    isBudget
                        ? 'Rollover unused amount'
                        : 'Auto-allocate monthly surplus',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) {
      setState(() => _targetDate = picked);
    }
  }

  Future<void> _chooseCurrency(BuildContext context, LedgerState state) async {
    final next = await showCurrencyPicker(
      context: context,
      state: state,
      selectedValue: _selectedCurrency ?? state.preferences.baseCurrency,
    );
    if (next != null) {
      setState(() => _selectedCurrency = next);
    }
  }

  Future<void> _save() async {
    final isBudget = widget.kind == 'budget';
    final name = _nameController.text.trim();
    final amountMinor = _amountMinorFromInput(_amountController.text);
    if (name.isEmpty) {
      final label = isBudget ? 'budget' : 'goal';
      _showBudgetGoalMessage('Enter a $label name.');
      return;
    }
    if (amountMinor <= 0) {
      _showBudgetGoalMessage('Enter a target amount.');
      return;
    }
    final controller = ref.read(ledgerProvider.notifier);
    if (isBudget) {
      await controller.addBudget(
        name: name,
        amountMinor: amountMinor,
        currency: _selectedCurrency,
        targetDate: _targetDate,
        frequency: _frequency,
        interval: _interval,
        daysOfWeek: _daysOfWeek.isEmpty ? null : (List<int>.from(_daysOfWeek)..sort()),
        daysOfMonth: _daysOfMonth.isEmpty ? null : (List<int>.from(_daysOfMonth)..sort()),
      );
    } else {
      await controller.addGoal(
        name: name,
        targetMinor: amountMinor,
        currency: _selectedCurrency,
        targetDate: _targetDate,
        frequency: _frequency,
        interval: _interval,
        daysOfWeek: _daysOfWeek.isEmpty ? null : (List<int>.from(_daysOfWeek)..sort()),
        daysOfMonth: _daysOfMonth.isEmpty ? null : (List<int>.from(_daysOfMonth)..sort()),
      );
    }
    if (!mounted) return;
    _showBudgetGoalMessage(isBudget ? 'Budget created.' : 'Goal created.');
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  void _showBudgetGoalMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.md),
            Text(label, style: Theme.of(context).textTheme.bodyLarge),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}


int _amountMinorFromInput(String value) {
  final normalized = value.replaceAll(',', '').trim();
  final parsed = double.tryParse(normalized) ?? 0;
  return (parsed * 100).round();
}
