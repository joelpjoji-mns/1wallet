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
    this.tagLabel = 'All tags',
    this.tagValue = 'all',
    this.tagActive = false,
    this.tagOptions,
    this.onTagSelected,
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
    this.onPreviousDate,
    this.onNextDate,
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
  final String tagLabel;
  final String tagValue;
  final bool tagActive;
  final List<GlassDropdownOption<String>>? tagOptions;
  final ValueChanged<String>? onTagSelected;
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
  final VoidCallback? onPreviousDate;
  final VoidCallback? onNextDate;
  final VoidCallback onAccountTap;
  final VoidCallback onCategoryTap;
  final ValueChanged<String> onStatusSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasTags = tagOptions != null && tagOptions!.length > 1;
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
        () {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final isAmoled = AppSurfaces.isAmoled(context);
          final innerContent = Material(
            color: Colors.transparent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width =
                        (constraints.maxWidth - 2 * AppSpacing.sm) / 3;
                    final filters = <Widget>[
                      FilterPill(
                        compact: true,
                        displayLabel: typeValue == 'all' ? 'Type' : typeLabel,
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
                        compact: true,
                        displayLabel: switch (dateLabel) {
                          'This week' => 'Week',
                          'This month' => 'Month',
                          'This year' => 'Year',
                          'Custom range' => 'Custom',
                          _ => dateLabel,
                        },
                        icon: Icons.date_range_outlined,
                        label: dateLabel,
                        active: dateActive,
                        value: dateValue,
                        onPrevious: onPreviousDate,
                        onNext: onNextDate,
                        options: [
                          const GlassDropdownOption('today', 'Today'),
                          const GlassDropdownOption('this_week', 'This week'),
                          const GlassDropdownOption('this_month', 'This month'),
                          GlassDropdownOption(
                            dateValue == 'last_30_days'
                                ? 'last_30_days'
                                : '30_days',
                            '30 days',
                          ),
                          const GlassDropdownOption('6_months', '6 months'),
                          const GlassDropdownOption('this_year', 'This year'),
                          const GlassDropdownOption('all', 'All time'),
                          GlassDropdownOption(
                            dateValue.startsWith('custom:')
                                ? dateValue
                                : 'custom',
                            dateValue.startsWith('custom:')
                                ? dateLabel
                                : 'Custom range',
                            icon: Icons.date_range_rounded,
                          ),
                        ],
                        onSelected: onDateSelected,
                      ),
                      FilterPill(
                        compact: true,
                        displayLabel: accountActive ? accountLabel : 'Account',
                        icon: Icons.wallet_outlined,
                        label: accountLabel,
                        active: accountActive,
                        onTap: onAccountTap,
                      ),
                      FilterPill(
                        compact: true,
                        displayLabel: categoryActive
                            ? categoryLabel
                            : 'Category',
                        icon: Icons.category_outlined,
                        label: categoryLabel,
                        active: categoryActive,
                        onTap: onCategoryTap,
                      ),
                      FilterPill(
                        compact: true,
                        displayLabel: tagActive ? tagLabel : 'Tags',
                        icon: Icons.label_outline_rounded,
                        label: hasTags || tagActive ? tagLabel : 'No tags yet',
                        active: tagActive,
                        value: tagValue,
                        options: tagOptions,
                        onSelected: hasTags ? onTagSelected : null,
                      ),
                      FilterPill(
                        compact: true,
                        displayLabel: statusValue == 'all'
                            ? 'Status'
                            : statusLabel,
                        icon: Icons.info_outline_rounded,
                        label: statusLabel,
                        active: statusActive,
                        value: statusValue,
                        options: const [
                          GlassDropdownOption('all', 'All statuses'),
                          GlassDropdownOption(
                            'cleared',
                            'Cleared',
                            icon: Icons.check_circle_outline_rounded,
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
                    ];
                    return Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final filter in filters)
                          SizedBox(width: width, child: filter),
                      ],
                    );
                  },
                ),
              ],
            ),
          );
          if (isDark && !isAmoled) {
            return GlassCard(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(AppSpacing.sm),
              shape: const LiquidRoundedSuperellipse(borderRadius: AppRadii.md),
              quality: GlassQuality.standard,
              child: innerContent,
            );
          }
          return Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: AppSurfaces.panel(context, color: scheme.surface),
            child: innerContent,
          );
        }(),
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
    this.onPrevious,
    this.onNext,
    this.compact = false,
    this.displayLabel,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final String? value;
  final List<GlassDropdownOption<String>>? options;
  final ValueChanged<String>? onSelected;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final bool compact;
  final String? displayLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (options != null && value != null && onSelected != null) {
      return GlassDropdownPill<String>(
        value: value!,
        options: options!,
        onChanged: onSelected!,
        icon: icon,
        semanticLabel: label,
        onPrevious: onPrevious,
        onNext: onNext,
        compact: compact,
        displayLabel: displayLabel,
        active: active,
      );
    }

    final bg = active
        ? (isDark
              ? scheme.primary.withValues(alpha: 0.22)
              : scheme.primary.withValues(alpha: 0.15))
        : (isDark
              ? scheme.surfaceContainerHigh.withValues(alpha: 0.6)
              : scheme.surfaceContainerHigh.withValues(alpha: 0.85));
    final enabled = onTap != null;
    final fg = compact && !enabled
        ? scheme.onSurface.withValues(alpha: 0.38)
        : active
        ? scheme.primary
        : scheme.onSurface;
    final borderColor = active
        ? scheme.primary.withValues(alpha: isDark ? 0.35 : 0.25)
        : scheme.outlineVariant.withValues(alpha: 0.4);

    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          onTap: onTap,
          child: Container(
            constraints: compact ? const BoxConstraints(minHeight: 48) : null,
            alignment: compact ? Alignment.center : null,
            padding: EdgeInsets.symmetric(
              horizontal: compact ? AppSpacing.xs : AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: compact
                ? MediaQuery.textScalerOf(context).scale(12) > 18
                      ? Icon(icon, size: 24, color: fg, semanticLabel: label)
                      : Text(
                          displayLabel ?? label,
                          semanticsLabel: label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: fg,
                                fontWeight: FontWeight.w700,
                              ),
                        )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 15, color: scheme.primary),
                      const SizedBox(width: AppSpacing.xxs),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: fg,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xxxs),
                      Icon(Icons.expand_more_rounded, size: 17, color: fg),
                    ],
                  ),
          ),
        ),
      ),
    );
    return compact
        ? Tooltip(
            message: label,
            excludeFromSemantics: true,
            child: Semantics(button: true, enabled: enabled, child: content),
          )
        : content;
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
    final stats = [
      MiniFlowStat(label: 'NET', value: net, color: scheme.primary),
      MiniFlowStat(label: 'INCOME', value: income, color: scheme.positive),
      MiniFlowStat(label: 'EXPENSE', value: expense, color: scheme.error),
    ];
    Widget box(MiniFlowStat stat) => Container(
      key: ValueKey('mini-flow-${stat.label.toLowerCase()}'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: stat,
    );
    // Accessibility text sizes stack the boxes so amounts stay legible.
    if (MediaQuery.textScalerOf(context).scale(14) > 20) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, stat) in stats.indexed) ...[
            if (index > 0) const SizedBox(height: AppSpacing.xs),
            box(stat),
          ],
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, stat) in stats.indexed) ...[
            if (index > 0) const SizedBox(width: AppSpacing.xxs),
            Expanded(child: box(stat)),
          ],
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
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxxs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            softWrap: false,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: color,
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
