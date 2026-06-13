import 'package:flutter/material.dart';

import '../../data/ledger_models.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';

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
    final options = [
      (
        'expense',
        'Expense',
        Icons.arrow_upward_rounded,
        scheme.error,
      ),
      (
        'income',
        'Income',
        Icons.arrow_downward_rounded,
        scheme.tertiary,
      ),
      (
        'transfer',
        'Transfer',
        Icons.swap_horiz_rounded,
        scheme.primary,
      ),
      ('adjustment', 'Adjust', Icons.tune_rounded, scheme.secondary),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final option in options)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: option == options.last ? 0 : AppSpacing.xs,
              ),
              child: AddRecordTypeTabPill(
                selected: value == option.$1,
                label: option.$2,
                icon: option.$3,
                color: option.$4,
                onTap: () => onChanged(option.$1),
              ),
            ),
          ),
      ],
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
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? color
                      : Theme.of(
                          context,
                        ).colorScheme.onSurface.withAlphaFactor(0.7),
                  fontSize: 11.5,
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
    return Row(
      children: [
        Expanded(
          child: AddRecordSelectorBox(
            icon: sourceAccount == null
                ? Icons.wallet_outlined
                : accountIcon(sourceAccount!),
            label: type == 'transfer' ? 'From' : 'Account',
            title: sourceAccount?.name ?? 'Choose account',
            subtitle: sourceAccount == null
                ? (type == 'transfer' ? 'Required' : '')
                : '${sourceAccount!.currency} · ${formatMoney(accountBalance(state, sourceAccount!), state.preferences.locale)}',
            iconColor: sourceAccount == null
                ? null
                : accountDisplayColor(sourceAccount!),
            onTap: onSelectAccount,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: type == 'transfer'
              ? AddRecordSelectorBox(
                  icon: Icons.swap_horiz_rounded,
                  label: 'To account',
                  title: counterAccount?.name ?? 'Choose',
                  subtitle: counterAccount == null
                      ? 'Required'
                      : '${counterAccount!.currency} · ${formatMoney(accountBalance(state, counterAccount!), state.preferences.locale)}',
                  iconColor: counterAccount == null
                      ? null
                      : accountDisplayColor(counterAccount!),
                  onTap: onSelectCounter,
                )
              : type == 'adjustment'
              ? const AddRecordSelectorBox(
                  icon: Icons.tune_rounded,
                  label: 'Adjustment',
                  title: 'Balance',
                  subtitle: 'Correction',
                )
              : AddRecordSelectorBox(
                  icon: Icons.category_outlined,
                  label: 'Category',
                  title: category?.name ?? 'Choose category',
                  subtitle: category == null ? 'Required' : category!.kind,
                  iconColor: categoryColor(category, context),
                  onTap: onSelectCategory,
                ),
        ),
      ],
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
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
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
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withAlphaFactor(0.75),
                          fontSize: 10,
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
        return Theme.of(context).colorScheme.errorContainer.withAlpha(80);
      }
      return Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withAlpha(80);
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
      operatorBackground: scheme.tertiaryContainer.withAlpha(110),
      operatorForeground: scheme.tertiary,
      equalsBackground: scheme.tertiary,
      equalsForeground: scheme.onTertiary,
    ),
    'transfer' => (
      operatorBackground: scheme.primaryContainer.withAlpha(110),
      operatorForeground: scheme.primary,
      equalsBackground: scheme.primary,
      equalsForeground: scheme.onPrimary,
    ),
    'adjustment' => (
      operatorBackground: scheme.secondaryContainer.withAlpha(110),
      operatorForeground: scheme.secondary,
      equalsBackground: scheme.secondary,
      equalsForeground: scheme.onSecondary,
    ),
    _ => (
      operatorBackground: scheme.errorContainer.withAlpha(110),
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
        child: Container(
          decoration: BoxDecoration(
            color: _pressed
                ? widget.backgroundColor.withAlpha(200)
                : widget.backgroundColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.foregroundColor.withAlpha(15),
              width: 1,
            ),
          ),
          child: Center(
            child: widget.label == '⌫'
                ? Icon(
                    Icons.backspace_rounded,
                    color: widget.foregroundColor,
                    size: 24,
                  )
                : Text(
                    widget.label,
                    style: TextStyle(
                      color: widget.foregroundColor,
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.5,
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
              color: Theme.of(context).colorScheme.outlineVariant,
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
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
