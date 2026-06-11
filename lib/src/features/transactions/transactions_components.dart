import 'package:flutter/material.dart';

import '../../design/tokens.dart';

class TransactionCommandStrip extends StatelessWidget {
  const TransactionCommandStrip({
    required this.query,
    required this.income,
    required this.expense,
    required this.net,
    required this.typeLabel,
    required this.dateLabel,
    required this.accountLabel,
    required this.categoryLabel,
    required this.typeActive,
    required this.dateActive,
    required this.accountActive,
    required this.categoryActive,
    required this.hasActiveFilters,
    required this.onQueryChanged,
    required this.onClear,
    required this.onTypeTap,
    required this.onDateTap,
    required this.onAccountTap,
    required this.onCategoryTap,
    super.key,
  });

  final String query;
  final String income;
  final String expense;
  final String net;
  final String typeLabel;
  final String dateLabel;
  final String accountLabel;
  final String categoryLabel;
  final bool typeActive;
  final bool dateActive;
  final bool accountActive;
  final bool categoryActive;
  final bool hasActiveFilters;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClear;
  final VoidCallback onTypeTap;
  final VoidCallback onDateTap;
  final VoidCallback onAccountTap;
  final VoidCallback onCategoryTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                  const SizedBox(width: AppSpacing.xs),
                  Tooltip(
                    message: 'Clear filters',
                    child: IconButton.filledTonal(
                      visualDensity: VisualDensity.compact,
                      onPressed: onClear,
                      icon: const Icon(Icons.filter_alt_off_rounded),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
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
                          onTap: onTypeTap,
                        ),
                        FilterPill(
                          icon: Icons.date_range_outlined,
                          label: dateLabel,
                          active: dateActive,
                          onTap: onDateTap,
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
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            MiniFlowRail(income: income, expense: expense, net: net),
          ],
        ),
      ),
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
    final controller = TextEditingController(text: value)
      ..selection = TextSelection.collapsed(offset: value.length);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 42,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: 'Search records',
          prefixIcon: Icon(Icons.search_rounded, color: scheme.primary),
          prefixIconConstraints: const BoxConstraints(minWidth: 38),
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          filled: true,
          fillColor: scheme.surfaceContainerHigh,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            borderSide: BorderSide(color: scheme.primary, width: 1.4),
          ),
        ),
      ),
    );
  }
}

class FilterPill extends StatelessWidget {
  const FilterPill({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = active
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final foreground = active ? scheme.onPrimaryContainer : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: ActionChip(
        visualDensity: VisualDensity.compact,
        avatar: Icon(icon, size: 16, color: foreground),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 128),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: foreground, fontWeight: FontWeight.w800),
          ),
        ),
        backgroundColor: background,
        side: BorderSide(
          color: active ? scheme.primary : scheme.outlineVariant,
        ),
        onPressed: onTap,
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
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Row(
        children: [
          Expanded(
            child: MiniFlowStat(
              label: 'In',
              value: income,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.positiveDark
                  : AppColors.positiveLight,
            ),
          ),
          RailDivider(color: scheme.outlineVariant),
          Expanded(
            child: MiniFlowStat(
              label: 'Out',
              value: expense,
              color: scheme.error,
            ),
          ),
          RailDivider(color: scheme.outlineVariant),
          Expanded(
            child: MiniFlowStat(
              label: 'Net',
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '$label ',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
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
