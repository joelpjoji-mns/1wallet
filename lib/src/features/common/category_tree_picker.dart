import 'package:flutter/material.dart';

import '../../data/ledger_models.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_glass_page.dart';
import '../../widgets/app_kit.dart';
import 'route_scaffold.dart';

const String categoryTreeUncategorizedKey = '__uncategorized__';

/// Opens a full-screen multi-select category tree picker styled like the Categories page.
///
/// Parent categories are displayed with their subcategories indented below them.
/// Categories are selected/deselected by tapping their card directly (no checkboxes).
Future<Set<String>?> showCategoryTreeMultiSelectPicker({
  required BuildContext context,
  required LedgerState state,
  required Set<String> initialSelectedCategoryIds,
  bool initialIncludeUncategorized = false,
  String title = 'Choose categories',
}) {
  final initial = Set<String>.from(initialSelectedCategoryIds);
  if (initialIncludeUncategorized) {
    initial.add(categoryTreeUncategorizedKey);
  }

  return Navigator.of(context).push<Set<String>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => _CategoryTreeMultiSelectPicker(
        state: state,
        initialSelected: initial,
        title: title,
      ),
    ),
  );
}

class _CategoryTreeMultiSelectPicker extends StatefulWidget {
  const _CategoryTreeMultiSelectPicker({
    required this.state,
    required this.initialSelected,
    required this.title,
  });

  final LedgerState state;
  final Set<String> initialSelected;
  final String title;

  @override
  State<_CategoryTreeMultiSelectPicker> createState() =>
      _CategoryTreeMultiSelectPickerState();
}

class _CategoryTreeMultiSelectPickerState
    extends State<_CategoryTreeMultiSelectPicker> {
  late final Set<String> _selectedIds;
  var _query = '';

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<String>.from(widget.initialSelected);
  }

  void _toggle(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final allActive = widget.state.categories
        .where((c) => !c.isArchived)
        .toList();

    final hasQuery = _query.trim().isNotEmpty;
    final queryLower = _query.trim().toLowerCase();

    return PopScope<Set<String>?>(
      canPop: true,
      child: AppGlassPage(
        child: RouteScaffold(
          title: widget.title,
          leading: HeaderIconButton(
            icon: Icons.arrow_back_rounded,
            semanticLabel: 'Back',
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).pop(),
          ),
        actions: [
          if (_selectedIds.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _selectedIds.clear()),
              child: const Text('Clear all'),
            ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(_selectedIds),
            child: Text(
              _selectedIds.isEmpty
                  ? 'All categories'
                  : 'Apply (${_selectedIds.length})',
            ),
          ),
        ],
        scrollView: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.xxl,
          ),
          children: [
            Text(
              'Select categories to filter. Tap any category to toggle selection.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: AppSpacing.md),
            PremiumSearchInput(
              hintText: 'Search categories...',
              value: _query,
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: AppSpacing.md),

            if (hasQuery) ...[
              // Flat search results
              _buildSearchResults(allActive, queryLower, scheme),
            ] else ...[
              // Tree structure like CategoriesScreen
              _buildUncategorizedTile(scheme),
              const SizedBox(height: AppSpacing.sm),
              _buildCategoryTree(allActive, scheme),
            ],
          ],
        ),
      ),
    ),
  );
}

  Widget _buildUncategorizedTile(ColorScheme scheme) {
    final isSelected = _selectedIds.contains(categoryTreeUncategorizedKey);

    return _SelectableCategoryCard(
      isSelected: isSelected,
      icon: Icons.help_outline_rounded,
      iconColor: scheme.onSurfaceVariant,
      title: 'Uncategorized',
      subtitle: 'Transactions without an assigned category',
      onTap: () => _toggle(categoryTreeUncategorizedKey),
    );
  }

  Widget _buildCategoryTree(List<Category> source, ColorScheme scheme) {
    final byId = {for (final c in source) c.id: c};
    final roots = source.where((c) {
      final directParentId =
          c.parentId != null && byId.containsKey(c.parentId) ? c.parentId : null;
      return directParentId == null;
    }).toList()
      ..sort((a, b) => compareCategoriesByUsage(widget.state, a, b));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < roots.length; i++) ...[
          _buildTreeNode(roots[i], source, byId, scheme),
          if (i != roots.length - 1) const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }

  Widget _buildTreeNode(
    Category root,
    List<Category> source,
    Map<String, Category> byId,
    ColorScheme scheme,
  ) {
    final children = source.where((c) => c.parentId == root.id).toList()
      ..sort((a, b) => compareCategoriesByUsage(widget.state, a, b));

    final isRootSelected = _selectedIds.contains(root.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SelectableCategoryCard(
          isSelected: isRootSelected,
          icon: categoryIcon(root),
          iconColor: categoryColor(root, context),
          title: root.name,
          subtitle: children.isNotEmpty
              ? '${children.length} subcategories'
              : null,
          onTap: () => _toggle(root.id),
        ),
        if (children.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final child in children) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _SelectableCategoryCard(
                    isSelected: _selectedIds.contains(child.id),
                    icon: categoryIcon(child),
                    iconColor: categoryColor(child, context),
                    title: child.name,
                    compact: true,
                    onTap: () => _toggle(child.id),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSearchResults(
    List<Category> source,
    String query,
    ColorScheme scheme,
  ) {
    final matches = source.where((c) {
      final nameMatches = c.name.toLowerCase().contains(query);
      final pathMatches =
          categoryPath(widget.state, c).toLowerCase().contains(query);
      return nameMatches || pathMatches;
    }).toList()
      ..sort((a, b) => compareCategoriesByUsage(widget.state, a, b));

    final matchesUncategorized =
        'uncategorized'.contains(query) || 'none'.contains(query);

    if (matches.isEmpty && !matchesUncategorized) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
          child: Text(
            'No matching categories',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (matchesUncategorized) ...[
          _buildUncategorizedTile(scheme),
          const SizedBox(height: AppSpacing.sm),
        ],
        for (var i = 0; i < matches.length; i++) ...[
          _SelectableCategoryCard(
            isSelected: _selectedIds.contains(matches[i].id),
            icon: categoryIcon(matches[i]),
            iconColor: categoryColor(matches[i], context),
            title: matches[i].name,
            subtitle: categoryPath(widget.state, matches[i]),
            onTap: () => _toggle(matches[i].id),
          ),
          if (i != matches.length - 1) const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }
}

class _SelectableCategoryCard extends StatelessWidget {
  const _SelectableCategoryCard({
    required this.isSelected,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.compact = false,
  });

  final bool isSelected;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: compact ? AppSpacing.xs : AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? scheme.primaryContainer.withValues(alpha: 0.35)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: isSelected
                  ? scheme.primary
                  : scheme.outlineVariant.withValues(alpha: 0.4),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              IconBubble(
                icon: icon,
                color: iconColor,
                compact: true,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight:
                                isSelected ? FontWeight.w800 : FontWeight.w600,
                            color: isSelected
                                ? scheme.onSurface
                                : scheme.onSurface,
                          ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              if (isSelected)
                Icon(
                  Icons.check_circle_rounded,
                  color: scheme.primary,
                  size: 22,
                )
              else
                Icon(
                  Icons.circle_outlined,
                  color: scheme.outlineVariant,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
