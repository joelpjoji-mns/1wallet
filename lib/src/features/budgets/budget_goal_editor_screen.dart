import 'package:flutter/material.dart';
import '../common/route_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';

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

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isBudget = widget.kind == 'budget';
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
                  label: isBudget ? 'Choose category' : 'Target date',
                ),
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
      await controller.addBudget(name: name, amountMinor: amountMinor);
    } else {
      await controller.addGoal(name: name, targetMinor: amountMinor);
    }
    if (!mounted) return;
    _showBudgetGoalMessage(isBudget ? 'Budget created.' : 'Goal created.');
    if (context.canPop()) {
      context.pop();
    } else {
      context.push('/');
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
  const _DetailField({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

int _amountMinorFromInput(String value) {
  final normalized = value.replaceAll(',', '').trim();
  final parsed = double.tryParse(normalized) ?? 0;
  return (parsed * 100).round();
}
