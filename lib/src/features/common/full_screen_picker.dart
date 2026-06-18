import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';

class PickerOption<T> {
  const PickerOption({
    required this.value,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.color,
    this.searchText,
  });

  final T value;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Color? color;
  final String? searchText;
}

Future<T?> showFullScreenPicker<T>({
  required BuildContext context,
  required String title,
  required List<PickerOption<T>> options,
  T? selectedValue,
  String? subtitle,
  String searchHint = 'Search',
  bool searchable = true,
  bool allowClear = false,
  String clearLabel = 'Clear selection',
  IconData? actionIcon,
  String? actionTooltip,
  VoidCallback? onAction,
}) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => _FullScreenPicker<T>(
        title: title,
        subtitle: subtitle,
        options: options,
        selectedValue: selectedValue,
        searchHint: searchHint,
        searchable: searchable,
        allowClear: allowClear,
        clearLabel: clearLabel,
        actionIcon: actionIcon,
        actionTooltip: actionTooltip,
        onAction: onAction,
      ),
    ),
  );
}

class _FullScreenPicker<T> extends StatefulWidget {
  const _FullScreenPicker({
    required this.title,
    required this.options,
    required this.searchHint,
    required this.searchable,
    required this.allowClear,
    required this.clearLabel,
    this.actionIcon,
    this.actionTooltip,
    this.onAction,
    this.subtitle,
    this.selectedValue,
  });

  final String title;
  final String? subtitle;
  final List<PickerOption<T>> options;
  final T? selectedValue;
  final String searchHint;
  final bool searchable;
  final bool allowClear;
  final String clearLabel;
  final IconData? actionIcon;
  final String? actionTooltip;
  final VoidCallback? onAction;

  @override
  State<_FullScreenPicker<T>> createState() => _FullScreenPickerState<T>();
}

class _FullScreenPickerState<T> extends State<_FullScreenPicker<T>> {
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final visibleOptions = query.isEmpty
        ? widget.options
        : widget.options.where((option) {
            final searchable = [
              option.title,
              option.subtitle,
              option.searchText,
            ].whereType<String>().join(' ').toLowerCase();
            return searchable.contains(query);
          }).toList();

    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: scheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
            fontSize: 20,
          ),
        ),
        actions: [
          if (widget.actionIcon != null && widget.onAction != null)
            IconButton(
              tooltip: widget.actionTooltip,
              icon: Icon(widget.actionIcon, color: scheme.primary),
              onPressed: widget.onAction,
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.xxl,
          ),
          children: [
            if (widget.subtitle != null) ...[
              Text(
                widget.subtitle!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (widget.searchable) ...[
              PremiumSearchInput(
                hintText: widget.searchHint,
                value: _query,
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (widget.allowClear) ...[
              PremiumRow(
                icon: Icons.clear_rounded,
                title: widget.clearLabel,
                subtitle: 'Show every option',
                selected: widget.selectedValue == null,
                onTap: () => Navigator.of(context).pop(null),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (visibleOptions.isEmpty)
              EmptyState(
                icon: Icons.search_off_rounded,
                title: 'No matches',
                body: 'Try a different search term.',
                actionLabel: 'Clear search',
                onAction: () => setState(() => _query = ''),
              )
            else
              for (final option in visibleOptions) ...[
                PremiumRow(
                  icon: option.icon ?? Icons.circle_outlined,
                  title: option.title,
                  subtitle: option.subtitle,
                  iconColor: option.iconColor,
                  selected: option.value == widget.selectedValue,
                  onTap: () => Navigator.of(context).pop(option.value),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
          ],
        ),
      ),
    );
  }
}
