import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/app_glass_page.dart';

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

    return AppGlassPage(
      child: Scaffold(
        appBar: GlassAppBar(
          leading: GlassIconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            semanticLabel: 'Back',
            useOwnLayer: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            widget.title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          centerTitle: false,
          actions: [
            if (widget.actionIcon != null && widget.onAction != null)
              Tooltip(
                message: widget.actionTooltip ?? '',
                child: GlassIconButton(
                  icon: Icon(widget.actionIcon),
                  semanticLabel: widget.actionTooltip,
                  useOwnLayer: true,
                  onPressed: widget.onAction,
                ),
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
                Semantics(
                  selected: widget.selectedValue == null,
                  child: PremiumRow(
                    icon: Icons.clear_rounded,
                    title: widget.clearLabel,
                    subtitle: 'Show every option',
                    selected: widget.selectedValue == null,
                    onTap: () => Navigator.of(context).pop(null),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (visibleOptions.isEmpty)
                if (query.isEmpty)
                  // The caller supplied zero options - this is not a search
                  // dead-end, so don't offer a "Clear search" action that
                  // has nothing to clear.
                  const EmptyState(
                    icon: Icons.inbox_outlined,
                    title: 'Nothing to choose from',
                    body: 'No options are available right now.',
                  )
                else
                  EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No matches',
                    body: 'Try a different search term.',
                    actionLabel: 'Clear search',
                    onAction: () => setState(() => _query = ''),
                  )
              else
                for (final option in visibleOptions) ...[
                  Semantics(
                    selected: option.value == widget.selectedValue,
                    child: PremiumRow(
                      icon: option.icon ?? Icons.circle_outlined,
                      title: option.title,
                      subtitle: option.subtitle,
                      iconColor: option.iconColor,
                      selected: option.value == widget.selectedValue,
                      onTap: () => Navigator.of(context).pop(option.value),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
            ],
          ),
        ),
      ),
    );
  }
}
