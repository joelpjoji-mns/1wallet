import 'package:flutter/material.dart';
import '../design/tokens.dart';

/// A single option in the [OptionListOverlay].
class OptionItem<T> {
  const OptionItem({
    required this.value,
    required this.label,
    this.description,
    this.icon,
  });

  final T value;
  final String label;
  final String? description;
  final IconData? icon;
}

/// A row that displays the current value of a setting and opens the picker
/// on tap, matching the React Native `OptionSelectorRow`.
class OptionSelectorRow extends StatelessWidget {
  const OptionSelectorRow({
    required this.label,
    required this.value,
    required this.onPressed,
    super.key,
    this.description,
    this.icon,
  });

  final String label;
  final String value;
  final String? description;
  final IconData? icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.lg),
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: theme.colorScheme.primary, size: 22),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (description != null)
                    Text(
                      description!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurfaceVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows a modal bottom sheet with a searchable option list.
///
/// Returns the selected value or `null` if dismissed.
Future<T?> showOptionListOverlay<T>({
  required BuildContext context,
  required String title,
  required List<OptionItem<T>> options,
  T? selectedValue,
  String? searchPlaceholder,
  bool searchable = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
    ),
    builder: (context) => _OptionListSheet<T>(
      title: title,
      options: options,
      selectedValue: selectedValue,
      searchPlaceholder: searchPlaceholder ?? 'Search',
      searchable: searchable,
    ),
  );
}

class _OptionListSheet<T> extends StatefulWidget {
  const _OptionListSheet({
    required this.title,
    required this.options,
    required this.searchPlaceholder,
    required this.searchable,
    this.selectedValue,
  });

  final String title;
  final List<OptionItem<T>> options;
  final T? selectedValue;
  final String searchPlaceholder;
  final bool searchable;

  @override
  State<_OptionListSheet<T>> createState() => _OptionListSheetState<T>();
}

class _OptionListSheetState<T> extends State<_OptionListSheet<T>> {
  String _query = '';

  List<OptionItem<T>> get _filtered {
    if (_query.isEmpty) return widget.options;
    final lower = _query.toLowerCase();
    return widget.options.where((option) {
      return option.label.toLowerCase().contains(lower) ||
          (option.description?.toLowerCase().contains(lower) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filtered;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, controller) => Column(
        children: [
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(
              widget.title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (widget.searchable)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: TextField(
                autofocus: widget.options.length > 6,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: widget.searchPlaceholder,
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: filtered.length,
              padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
              itemBuilder: (context, index) {
                final option = filtered[index];
                final selected = option.value == widget.selectedValue;
                return ListTile(
                  leading: option.icon != null
                      ? Icon(
                          option.icon,
                          color: selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        )
                      : null,
                  title: Text(
                    option.label,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  subtitle: option.description != null
                      ? Text(option.description!)
                      : null,
                  trailing: selected
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: theme.colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.of(context).pop(option.value),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
