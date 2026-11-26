import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../data/ledger_models.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/privacy_text.dart';

class AddRecordTypeTabs extends StatelessWidget {
  const AddRecordTypeTabs({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLoan = value == 'loan_repayment';
    final options = isLoan
        ? ['expense', 'income', 'transfer', 'loan_repayment']
        : ['expense', 'income', 'transfer'];
    final selectedIndex = options.indexOf(value).clamp(0, options.length - 1);

    return LayoutBuilder(
      builder: (context, constraints) {
        const labels = ['Expense', 'Income', 'Transfer', 'Loan'];
        const icons = [
          Icons.arrow_upward_rounded,
          Icons.arrow_downward_rounded,
          Icons.swap_horiz_rounded,
          Icons.account_balance_outlined,
        ];
        final colors = [
          scheme.error,
          scheme.tertiary,
          scheme.primary,
          scheme.primary,
        ];
        final textStyle = Theme.of(context).textTheme.labelMedium;
        final widestLabel = labels
            .take(options.length)
            .map((label) {
              final painter = TextPainter(
                text: TextSpan(text: label, style: textStyle),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              final width = painter.width;
              painter.dispose();
              return width;
            })
            .reduce((a, b) => a > b ? a : b);
        if (widestLabel + 32 > constraints.maxWidth / options.length) {
          return Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (var index = 0; index < options.length; index++)
                ChoiceChip(
                  label: Text(labels[index], softWrap: false),
                  avatar: Icon(icons[index], color: colors[index], size: 16),
                  selected: selectedIndex == index,
                  onSelected: (_) => onChanged(options[index]),
                ),
            ],
          );
        }
        return GlassSegmentedControl(
          selectedIndex: selectedIndex,
          onSegmentSelected: (index) => onChanged(options[index]),
          height: 42,
          useOwnLayer: true,
          quality: GlassQuality.standard,
          segments: [
            GlassSegment(
              icon: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_upward_rounded,
                    size: 16,
                    color: scheme.error,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    'Expense',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: selectedIndex == 0
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: selectedIndex == 0
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            GlassSegment(
              icon: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_downward_rounded,
                    size: 16,
                    color: scheme.tertiary,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    'Income',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: selectedIndex == 1
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: selectedIndex == 1
                          ? scheme.tertiary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            GlassSegment(
              icon: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.swap_horiz_rounded,
                    size: 16,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    'Transfer',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: selectedIndex == 2
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: selectedIndex == 2
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (isLoan)
              GlassSegment(
                icon: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.account_balance_outlined,
                      size: 16,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      'Loan',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: selectedIndex == 3
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: selectedIndex == 3
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class AddRecordTypeTabPill extends StatelessWidget {
  const AddRecordTypeTabPill({
    required this.selected,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    super.key,
  });

  final bool selected;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 36,
        decoration: BoxDecoration(
          color: selected
              ? color.withAlphaFactor(0.18)
              : Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(
            color: selected
                ? color.withAlphaFactor(0.6)
                : color.withAlphaFactor(0.2),
            width: selected ? 1.2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected ? color : color.withAlphaFactor(0.6),
            ),
            const SizedBox(width: AppSpacing.xxs),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: selected
                      ? color
                      : Theme.of(
                          context,
                        ).colorScheme.onSurface.withAlphaFactor(0.7),
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AddRecordSelectorGrid extends StatelessWidget {
  const AddRecordSelectorGrid({
    required this.state,
    required this.sourceAccount,
    required this.counterAccount,
    required this.category,
    required this.type,
    required this.onSelectAccount,
    required this.onSelectCounter,
    required this.onSelectCategory,
    super.key,
  });

  final LedgerState state;
  final Account? sourceAccount;
  final Account? counterAccount;
  final Category? category;
  final String type;
  final VoidCallback onSelectAccount;
  final VoidCallback onSelectCounter;
  final VoidCallback onSelectCategory;

  @override
  Widget build(BuildContext context) {
    final isDoubleEntry =
        type == 'transfer' ||
        type == 'loan_repayment' ||
        type == 'card_payment';
    final isLoan = type == 'loan_repayment';
    final isCard = type == 'card_payment';
    final account = AddRecordSelectorBox(
      icon: sourceAccount == null
          ? Icons.wallet_outlined
          : accountIcon(sourceAccount!),
      label: type == 'transfer' ? 'From' : 'Account',
      title: sourceAccount?.name ?? 'Choose',
      subtitle: sourceAccount == null
          ? 'Required'
          : maskMoneyIfPrivate(
              state,
              '${sourceAccount!.currency} · ${formatMoney(accountBalance(state, sourceAccount!), state.preferences.locale)}',
            ),
      iconColor: sourceAccount == null
          ? null
          : accountDisplayColor(sourceAccount!),
      onTap: onSelectAccount,
    );
    final other = isDoubleEntry
        ? AddRecordSelectorBox(
            icon: isLoan
                ? Icons.account_balance_outlined
                : (isCard
                      ? Icons.credit_card_outlined
                      : Icons.swap_horiz_rounded),
            label: isLoan
                ? 'Loan account'
                : (isCard ? 'Card account' : 'To account'),
            title: counterAccount?.name ?? 'Choose',
            subtitle: counterAccount == null
                ? 'Required'
                : maskMoneyIfPrivate(
                    state,
                    '${counterAccount!.currency} · ${formatMoney(accountBalance(state, counterAccount!), state.preferences.locale)}',
                  ),
            iconColor: counterAccount == null
                ? null
                : accountDisplayColor(counterAccount!),
            onTap: onSelectCounter,
          )
        : AddRecordSelectorBox(
            icon: categoryIcon(category),
            label: 'Category',
            title: category?.name ?? 'Choose',
            subtitle: category == null
                ? 'Required'
                : categoryPath(state, category),
            iconColor: categoryColor(category, context),
            onTap: onSelectCategory,
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (constraints.maxWidth < 220 * textScale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              account,
              const SizedBox(height: AppSpacing.xs),
              other,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: account),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: other),
          ],
        );
      },
    );
  }
}

class AddRecordSelectorBox extends StatelessWidget {
  const AddRecordSelectorBox({
    required this.icon,
    required this.label,
    required this.title,
    required this.subtitle,
    super.key,
    this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final String title;
  final String subtitle;
  final Color? iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color:
                      iconColor?.withAlphaFactor(0.18) ??
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color:
                      iconColor ??
                      Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withAlphaFactor(0.75),
                        ),
                      ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 16,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class AddRecordCalculatorPad extends StatelessWidget {
  const AddRecordCalculatorPad({
    required this.type,
    required this.onKey,
    super.key,
  });

  final String type;
  final ValueChanged<String> onKey;

  static const _rows = [
    ['AC', '+/-', '%', '/'],
    ['7', '8', '9', 'x'],
    ['4', '5', '6', '-'],
    ['1', '2', '3', '+'],
    ['0', '.', '⌫', '='],
  ];

  @override
  Widget build(BuildContext context) {
    final colors = addRecordCalculatorPadColors(context, type);

    Color bgColor(String key) {
      if (key == '=') return colors.equalsBackground;
      if (['+/-', '%', '/', 'x', '-', '+'].contains(key)) {
        return colors.operatorBackground;
      }
      if (key == 'AC') {
        return Theme.of(
          context,
        ).colorScheme.errorContainer.withValues(alpha: 0.31);
      }
      return Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.31);
    }

    Color fgColor(String key) {
      if (key == '=') return colors.equalsForeground;
      if (['+/-', '%', '/', 'x', '-', '+'].contains(key)) {
        return colors.operatorForeground;
      }
      if (key == 'AC') return Theme.of(context).colorScheme.error;
      if (key == '⌫') return Theme.of(context).colorScheme.onSurfaceVariant;
      return Theme.of(context).colorScheme.onSurface;
    }

    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        children: [
          for (final row in _rows)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: row == _rows.last ? 0 : AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    for (final key in row) ...[
                      Expanded(
                        child: AddRecordCalcKey(
                          label: key,
                          backgroundColor: bgColor(key),
                          foregroundColor: fgColor(key),
                          onTap: () => onKey(key),
                        ),
                      ),
                      if (key != row.last) const SizedBox(width: AppSpacing.sm),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

({
  Color operatorBackground,
  Color operatorForeground,
  Color equalsBackground,
  Color equalsForeground,
})
addRecordCalculatorPadColors(BuildContext context, String type) {
  final scheme = Theme.of(context).colorScheme;
  return switch (type) {
    'income' => (
      operatorBackground: scheme.tertiaryContainer.withValues(alpha: 0.43),
      operatorForeground: scheme.tertiary,
      equalsBackground: scheme.tertiary,
      equalsForeground: scheme.onTertiary,
    ),
    'transfer' => (
      operatorBackground: scheme.primaryContainer.withValues(alpha: 0.43),
      operatorForeground: scheme.primary,
      equalsBackground: scheme.primary,
      equalsForeground: scheme.onPrimary,
    ),
    _ => (
      operatorBackground: scheme.errorContainer.withValues(alpha: 0.43),
      operatorForeground: scheme.error,
      equalsBackground: scheme.error,
      equalsForeground: scheme.onError,
    ),
  };
}

class AddRecordCalcKey extends StatefulWidget {
  const AddRecordCalcKey({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
    super.key,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onTap;

  @override
  State<AddRecordCalcKey> createState() => _AddRecordCalcKeyState();
}

class _AddRecordCalcKeyState extends State<AddRecordCalcKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 100),
        scale: _pressed ? 0.90 : 1.0,
        curve: Curves.easeOutQuart,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _pressed
                ? widget.backgroundColor.withValues(alpha: 0.78)
                : widget.backgroundColor,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: widget.foregroundColor.withValues(alpha: 0.06),
            ),
          ),
          child: Center(
            child: widget.label == '⌫'
                ? Icon(
                    Icons.backspace_rounded,
                    semanticLabel: 'Backspace',
                    color: widget.foregroundColor,
                    size: 24,
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: widget.foregroundColor,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.5,
                            ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class AddRecordTappableDetailField extends StatelessWidget {
  const AddRecordTappableDetailField({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(
                Icons.edit_outlined,
                size: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
