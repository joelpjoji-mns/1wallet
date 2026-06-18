import 'package:flutter/material.dart';

import '../../data/ledger_models.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';

Future<String?> showCategoryHierarchyPicker({
  required BuildContext context,
  required LedgerState state,
  String? selectedCategoryId,
  String title = 'Choose category',
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (context) => _CategoryHierarchyPicker(
        state: state,
        selectedCategoryId: selectedCategoryId,
        title: title,
      ),
    ),
  );
}

class _CategoryHierarchyPicker extends StatefulWidget {
  const _CategoryHierarchyPicker({
    required this.state,
    required this.title,
    this.selectedCategoryId,
  });

  final LedgerState state;
  final String title;
  final String? selectedCategoryId;

  @override
  State<_CategoryHierarchyPicker> createState() =>
      _CategoryHierarchyPickerState();
}

class _CategoryHierarchyPickerState extends State<_CategoryHierarchyPicker> {
  Category? _activeRoot;
  var _query = '';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final root = _activeRoot;
    final showingSubcategories = root != null;
    final selectedCategory = categoryById(
      widget.state,
      widget.selectedCategoryId,
    );
    final selectedChildId = selectedCategory?.parentId == root?.id
        ? selectedCategory?.id
        : null;
    final selectedRoot = selectedCategory == null
      ? null
      : rootCategoryFor(widget.state, selectedCategory);
    final options = showingSubcategories
        ? childCategories(widget.state, root.id)
        : rootCategories(widget.state);
    final visibleOptions = _filtered(options);

    return PopScope<String?>(
      canPop: !showingSubcategories,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _showCategoryList();
      },
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: scheme.surface,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: scheme.onSurface),
            tooltip: showingSubcategories ? 'Categories' : 'Back',
            onPressed: _handleBack,
          ),
          title: Text(
            showingSubcategories ? 'Choose subcategory' : widget.title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
              fontSize: 20,
            ),
          ),
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
              Text(
                showingSubcategories
                    ? 'Pick a subcategory under ${root.name}. Back returns to categories.'
                    : 'Pick the closest category. The most-used categories are shown first.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              PremiumSearchInput(
                hintText: showingSubcategories
                    ? 'Search subcategories'
                    : 'Search categories',
                value: _query,
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: AppSpacing.md),
              if (showingSubcategories) ...[
                PremiumRow(
                  icon: Icons.swap_horiz_rounded,
                  title: 'All categories',
                  subtitle: 'Go back to parent categories',
                  iconColor: scheme.primary,
                  onTap: _showCategoryList,
                ),
                const SizedBox(height: AppSpacing.sm),
                PremiumRow(
                  icon: categoryIcon(root),
                  title: 'Use ${root.name}',
                  subtitle: 'Save without a subcategory',
                  iconColor: categoryColor(root, context),
                  selected: widget.selectedCategoryId == root.id,
                  onTap: () => Navigator.of(context).pop(root.id),
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
                for (final category in visibleOptions) ...[
                  PremiumRow(
                    icon: categoryIcon(category),
                    title: category.name,
                    subtitle: showingSubcategories
                        ? categoryPath(widget.state, category)
                        : _rootSubtitle(widget.state, category),
                    iconColor: categoryColor(category, context),
                    selected: showingSubcategories
                        ? selectedChildId == category.id
                      : selectedRoot?.id == category.id,
                    onTap: () => _select(category),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
            ],
          ),
        ),
      ),
    );
  }

  void _handleBack() {
    if (_activeRoot != null) {
      _showCategoryList();
      return;
    }
    Navigator.of(context).pop();
  }

  void _showCategoryList() {
    setState(() {
      _activeRoot = null;
      _query = '';
    });
  }

  List<Category> _filtered(List<Category> options) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return options;
    
    // Always search all categories, not just the currently active group
    return activeCategories(widget.state).where((category) {
      final searchable = [
        category.name,
        categoryPath(widget.state, category),
      ].join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList();
  }

  void _select(Category category) {
    final root = _activeRoot;
    if (root != null) {
      Navigator.of(context).pop(category.id);
      return;
    }

    final children = childCategories(widget.state, category.id);
    if (children.isEmpty) {
      Navigator.of(context).pop(category.id);
      return;
    }

    setState(() {
      _activeRoot = category;
      _query = '';
    });
  }
}

String _rootSubtitle(LedgerState state, Category category) {
  final children = childCategories(state, category.id);
  if (children.isEmpty) return 'No subcategories';
  final count = children.length;
  return '$count ${count == 1 ? 'subcategory' : 'subcategories'}';
}
