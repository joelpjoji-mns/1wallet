import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';

class TransactionCommandStrip extends StatelessWidget {
  const TransactionCommandStrip({
    required this.query,
    required this.typeLabel,
    required this.typeValue,
    required this.dateLabel,
    required this.dateValue,
    required this.accountLabel,
    required this.categoryLabel,
    required this.statusLabel,
    required this.statusValue,
    required this.typeActive,
    required this.dateActive,
    required this.accountActive,
    required this.categoryActive,
    required this.statusActive,
    required this.hasActiveFilters,
    required this.onQueryChanged,
    required this.onClear,
    required this.onTypeSelected,
    required this.onDateSelected,
    required this.onAccountTap,
    required this.onCategoryTap,
    required this.onStatusSelected,
    super.key,
  });

  final String query;
  final String typeLabel;
  final String typeValue;
  final String dateLabel;
  final String dateValue;
  final String accountLabel;
  final String categoryLabel;
  final String statusLabel;
  final String statusValue;
  final bool typeActive;
  final bool dateActive;
  final bool accountActive;
  final bool categoryActive;
  final bool statusActive;
  final bool hasActiveFilters;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClear;
  final ValueChanged<String> onTypeSelected;
  final ValueChanged<String> onDateSelected;
  final VoidCallback onAccountTap;
  final VoidCallback onCategoryTap;
  final ValueChanged<String> onStatusSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: CompactSearchField(
                value: query,
                onChanged: onQueryChanged,
              ),
            ),
            if (hasActiveFilters) ...[
              const SizedBox(width: AppSpacing.sm),
              Tooltip(
                message: 'Clear filters',
                child: GlassIconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.filter_alt_off_rounded),
                  semanticLabel: 'Clear filters',
                  quality: GlassQuality.standard,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        GlassCard(
          padding: const EdgeInsets.all(AppSpacing.sm),
          shape: LiquidRoundedSuperellipse(borderRadius: AppRadii.md),
          quality: GlassQuality.standard,
          child: Material(
            color: Colors.transparent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            FilterPill(
                              icon: Icons.filter_alt_outlined,
                              label: typeLabel,
                              active: typeActive,
                              value: typeValue,
                              options: const [
                                GlassDropdownOption('all', 'All records'),
                                GlassDropdownOption(
                                  'income',
                                  'Income',
                                  icon: Icons.trending_up_rounded,
                                ),
                                GlassDropdownOption(
                                  'expense',
                                  'Expense',
                                  icon: Icons.trending_down_rounded,
                                ),
                                GlassDropdownOption(
                                  'transfer',
                                  'Transfer',
                                  icon: Icons.swap_horiz_rounded,
                                ),
                              ],
                              onSelected: onTypeSelected,
                            ),
                            FilterPill(
                              icon: Icons.date_range_outlined,
                              label: dateLabel,
                              active: dateActive,
                              value: dateValue,
                              options: const [
                                GlassDropdownOption('all', 'All time'),
                                GlassDropdownOption('today', 'Today'),
                                GlassDropdownOption('this_week', 'This week'),
                                GlassDropdownOption('this_month', 'This month'),
                                GlassDropdownOption(
                                  'last_30_days',
                                  'Last 30 days',
                                ),
                                GlassDropdownOption('this_year', 'This year'),
                              ],
                              onSelected: onDateSelected,
                            ),
                            FilterPill(
                              icon: Icons.wallet_outlined,
                              label: accountLabel,
                              active: accountActive,
                              onTap: onAccountTap,
                            ),
                            FilterPill(
                              icon: Icons.category_outlined,
                              label: categoryLabel,
                              active: categoryActive,
                              onTap: onCategoryTap,
                            ),
                            FilterPill(
                              icon: Icons.info_outline,
                              label: statusLabel,
                              active: statusActive,
                              value: statusValue,
                              options: const [
                                GlassDropdownOption('all', 'All statuses'),
                                GlassDropdownOption(
                                  'cleared',
                                  'Cleared',
                                  icon: Icons.check_circle_outline,
                                ),
                                GlassDropdownOption(
                                  'pending',
                                  'Pending',
                                  icon: Icons.hourglass_empty_rounded,
                                ),
                                GlassDropdownOption(
                                  'void',
                                  'Skipped / Void',
                                  icon: Icons.block_rounded,
                                ),
                              ],
                              onSelected: onStatusSelected,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class CompactSearchField extends StatelessWidget {
  const CompactSearchField({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: PremiumSearchInput(
        hintText: 'Search records',
        value: value,
        onChanged: onChanged,
        height: 42,
      ),
    );
  }
}

class FilterPill extends StatelessWidget {
  const FilterPill({
    required this.icon,
    required this.label,
    required this.active,
    this.onTap,
    this.value,
    this.options,
    this.onSelected,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final String? value;
  final List<GlassDropdownOption<String>>? options;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (options != null && value != null && onSelected != null) {
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.xs),
        child: GlassDropdownPill<String>(
          value: value!,
          options: options!,
          onChanged: onSelected!,
          icon: icon,
          semanticLabel: label,
        ),
      );
    }
    final foreground = active ? scheme.onPrimaryContainer : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: GlassChip(
        label: label,
        icon: Icon(icon, size: 16, color: foreground),
        selected: active,
        selectedColor: scheme.primaryContainer,
        labelStyle: TextStyle(color: foreground, fontWeight: FontWeight.w800),
        onTap: onTap ?? () {},
        quality: GlassQuality.standard,
        useOwnLayer: true,
      ),
    );
  }
}

class MiniFlowRail extends StatelessWidget {
  const MiniFlowRail({
    required this.income,
    required this.expense,
    required this.net,
    super.key,
  });

  final String income;
  final String expense;
  final String net;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: MiniFlowStat(
              label: 'INCOME',
              value: income,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.positiveDark
                  : AppColors.positiveLight,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: MiniFlowStat(
              label: 'EXPENSE',
              value: expense,
              color: scheme.error,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: MiniFlowStat(
              label: 'NET',
              value: net,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class MiniFlowStat extends StatelessWidget {
  const MiniFlowStat({
    required this.label,
    required this.value,
    required this.color,
    super.key,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
            fontSize: 9,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              fontFamily: 'Inter',
            ),
          ),
        ),
      ],
    );
  }
}

class RailDivider extends StatelessWidget {
  const RailDivider({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 18, color: color);
  }
}
