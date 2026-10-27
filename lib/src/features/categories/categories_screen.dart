import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/color_picker_dialog.dart';
import '../common/full_screen_picker.dart';
import '../common/route_scaffold.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  var _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerProvider);
    final source = _visibleCategories(
      state.categories,
      includeArchived: _showArchived,
    );
    final rootCount = _categoryLevel(state, source).length;
    final subcategoryCount = source.length - rootCount;
    final archivedCount = state.categories
        .where((item) => item.isArchived)
        .length;

    return RouteScaffold(
      title: 'Categories',
      actions: [
        HeaderIconButton(
          tooltip: 'Add category',
          semanticLabel: 'Add category',
          onPressed: () => _openCategoryEditor(context, state),
          icon: Icons.add_rounded,
        ),
        PopupMenuButton<String>(
          tooltip: 'Category options',
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (action) {
            if (action == 'reset') {
              _confirmResetDefaults();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'reset',
              child: Row(
                children: [
                  Icon(Icons.restart_alt_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('Reset to default categories'),
                ],
              ),
            ),
          ],
        ),
      ],
      child: Column(
        children: [
          SectionCard(
            title: 'Category tree',
            subtitle:
                'Parent categories are listed first, with subcategories nested below.',
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: MetricTile(
                        label: 'Categories',
                        value: '$rootCount',
                        icon: Icons.folder_outlined,
                        compact: true,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: MetricTile(
                        label: 'Subcategories',
                        value: '$subcategoryCount',
                        icon: Icons.account_tree_outlined,
                        compact: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                PremiumRow(
                  icon: Icons.account_tree_outlined,
                  title: 'Grouping & archive visibility',
                  subtitle: _showArchived
                      ? 'Showing active and archived categories'
                      : 'Showing active categories only',
                  meta: '$archivedCount archived',
                  onTap: () => setState(() => _showArchived = !_showArchived),
                ),
                const SizedBox(height: AppSpacing.xs),
                PremiumRow(
                  icon: Icons.restart_alt_rounded,
                  title: 'Reset to default categories',
                  subtitle:
                      'Restore the standard 100 categories and reset rules',
                  onTap: _confirmResetDefaults,
                ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          if (source.isEmpty)
            EmptyState(
              icon: Icons.category_outlined,
              title: 'No categories yet',
              body:
                  'Add top-level categories and subcategories instead of one long flat list.',
              actionLabel: 'Add category',
              onAction: () => _openCategoryEditor(context, state),
            )
          else ...[
            _CategoryKindSection(
              title: 'Shared categories',
              subtitle:
                  'One category tree shared by income and expense records.',
              tone: MetricTone.standard,
              icon: Icons.category_outlined,
              state: state,
              source: source,
              onEdit: (category) =>
                  _openCategoryEditor(context, state, category: category),
              onAddChild: (category) =>
                  _openCategoryEditor(context, state, parentCategory: category),
              onToggleArchive: _toggleArchive,
              onDelete: _deleteCategory,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmResetDefaults() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Reset categories?',
      message:
          'This will reset your categories to the 100 standard built-in categories and subcategories, clear custom category overrides, and reset merchant categorization rules.',
      confirmLabel: 'Reset to defaults',
      destructive: true,
    );

    if (confirmed && mounted) {
      await ref.read(ledgerProvider.notifier).resetCategoriesToDefault();
      if (!mounted) return;
      showAppSnackBar(context, 'Categories and rules reset to defaults.');
    }
  }

  Future<void> _openCategoryEditor(
    BuildContext screenContext,
    LedgerState state, {
    Category? category,
    Category? parentCategory,
  }) async {
    var name = category?.name ?? '';
    var kind = parentCategory?.kind ?? category?.kind ?? 'expense';
    var archived = category?.isArchived ?? false;
    String? parentId = category?.parentId ?? parentCategory?.id;
    Color? color = category?.color;
    String? errorText;

    await showDialog<void>(
      context: screenContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            category == null
                ? parentId == null
                      ? 'New category'
                      : 'New subcategory'
                : 'Edit category',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: name,
                  onChanged: (value) => name = value,
                  decoration: InputDecoration(
                    labelText: 'Category name',
                    errorText: errorText,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                PremiumRow(
                  icon: Icons.account_tree_outlined,
                  title: 'Parent group',
                  subtitle: parentId == null
                      ? 'Top-level category'
                      : categoryPath(state, categoryById(state, parentId)),
                  onTap: () async {
                    final next = await showFullScreenPicker<String>(
                      context: dialogContext,
                      title: 'Parent category',
                      searchHint: 'Search categories',
                      selectedValue: parentId ?? '__root__',
                      options: [
                        const PickerOption(
                          value: '__root__',
                          title: 'Top-level category',
                          subtitle: 'No parent group',
                          icon: Icons.vertical_align_top_rounded,
                        ),
                        for (final parent in _parentCategoryOptions(
                          state,
                          category: category,
                        ))
                          PickerOption(
                            value: parent.id,
                            title: parent.name,
                            subtitle: categoryPath(state, parent),
                            icon: categoryIcon(parent),
                            iconColor: categoryColor(parent, context),
                          ),
                      ],
                    );
                    if (next == null) return;
                    setDialogState(() {
                      parentId = next == '__root__' ? null : next;
                      final parent = categoryById(state, parentId);
                      if (parent != null) kind = parent.kind;
                    });
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                PremiumRow(
                  icon: Icons.palette_outlined,
                  iconColor: color ?? Theme.of(context).colorScheme.primary,
                  title: 'Color',
                  subtitle: 'Choose a custom color',
                  onTap: () async {
                    final selected = await showAppColorPicker(
                      context: context,
                      initialColor:
                          color ?? Theme.of(context).colorScheme.primary,
                      title: 'Category color',
                    );
                    if (selected != null) {
                      setDialogState(() => color = selected);
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                if (category != null)
                  AppSwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: archived,
                    onChanged: (value) =>
                        setDialogState(() => archived = value),
                    title: const Text('Archive category'),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final trimmedName = name.trim();
                if (trimmedName.isEmpty) {
                  setDialogState(() => errorText = 'Enter a category name.');
                  return;
                }
                await ref
                    .read(ledgerProvider.notifier)
                    .upsertCategory(
                      id: category?.id,
                      name: trimmedName,
                      kind: kind,
                      parentId: parentId,
                      isArchived: archived,
                      color: color,
                    );
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                if (!screenContext.mounted) return;
                showAppSnackBar(
                  screenContext,
                  category == null
                      ? parentId == null
                            ? 'Category created.'
                            : 'Subcategory created.'
                      : 'Category saved.',
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleArchive(Category category) async {
    await ref
        .read(ledgerProvider.notifier)
        .archiveCategory(category.id, archived: !category.isArchived);
  }

  Future<void> _deleteCategory(Category category) async {
    final confirm = await showAppConfirmDialog(
      context,
      title: 'Delete category?',
      message: 'Are you sure you want to delete "${category.name}"?',
      confirmLabel: 'Delete',
      destructive: true,
    );

    if (!confirm) return;

    await ref.read(ledgerProvider.notifier).deleteCategory(category.id);
  }
}

class _CategoryKindSection extends StatelessWidget {
  const _CategoryKindSection({
    required this.title,
    required this.subtitle,
    required this.tone,
    required this.icon,
    required this.state,
    required this.source,
    required this.onEdit,
    required this.onAddChild,
    required this.onToggleArchive,
    required this.onDelete,
  });

  final String title;
  final String subtitle;
  final MetricTone tone;
  final IconData icon;
  final LedgerState state;
  final List<Category> source;
  final ValueChanged<Category> onEdit;
  final ValueChanged<Category> onAddChild;
  final ValueChanged<Category> onToggleArchive;
  final ValueChanged<Category> onDelete;

  @override
  Widget build(BuildContext context) {
    final roots = _categoryLevel(state, source);
    return SectionCard(
      title: title,
      subtitle: subtitle,
      child: roots.isEmpty
          ? EmptyState(
              icon: icon,
              title: 'Nothing here yet',
              body:
                  'Create a parent category first, then add subcategories under it.',
            )
          : Column(
              children: [
                for (var index = 0; index < roots.length; index++) ...[
                  _CategoryTreeNode(
                    category: roots[index],
                    source: source,
                    state: state,
                    depth: 0,
                    tone: tone,
                    onEdit: onEdit,
                    onAddChild: onAddChild,
                    onToggleArchive: onToggleArchive,
                    onDelete: onDelete,
                  ),

                  if (index != roots.length - 1)
                    const SizedBox(height: AppSpacing.md),
                ],
              ],
            ),
    );
  }
}

class _CategoryTreeNode extends StatelessWidget {
  const _CategoryTreeNode({
    required this.category,
    required this.source,
    required this.state,
    required this.depth,
    required this.tone,
    required this.onEdit,
    required this.onAddChild,
    required this.onToggleArchive,
    required this.onDelete,
  });

  final Category category;
  final List<Category> source;
  final LedgerState state;
  final int depth;
  final MetricTone tone;
  final ValueChanged<Category> onEdit;
  final ValueChanged<Category> onAddChild;
  final ValueChanged<Category> onToggleArchive;
  final ValueChanged<Category> onDelete;

  @override
  Widget build(BuildContext context) {
    final children = _categoryLevel(state, source, parentId: category.id);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppPanel(
          color: depth == 0
              ? null
              : scheme.surfaceContainerHighest.withValues(alpha: 0.47),
          padding: const EdgeInsets.all(AppSpacing.sm),
          onTap: () => onEdit(category),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBubble(
                icon: categoryIcon(category),
                color: categoryColor(category, context),
                compact: true,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _categoryNodeSubtitle(
                        category,
                        childCount: children.length,
                        depth: depth,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_CategoryAction>(
                onSelected: (action) {
                  switch (action) {
                    case _CategoryAction.edit:
                      onEdit(category);
                      break;
                    case _CategoryAction.addChild:
                      onAddChild(category);
                      break;
                    case _CategoryAction.toggleArchive:
                      onToggleArchive(category);
                      break;
                    case _CategoryAction.delete:
                      onDelete(category);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _CategoryAction.edit,
                    child: Text('Edit'),
                  ),
                  const PopupMenuItem(
                    value: _CategoryAction.addChild,
                    child: Text('Add subcategory'),
                  ),
                  PopupMenuItem(
                    value: _CategoryAction.toggleArchive,
                    child: Text(category.isArchived ? 'Restore' : 'Archive'),
                  ),
                  PopupMenuItem(
                    value: _CategoryAction.delete,
                    child: Text(
                      'Delete',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],

                icon: Icon(
                  Icons.more_vert_rounded,
                  color: switch (tone) {
                    MetricTone.positive => amountColor(context, 1),
                    MetricTone.danger => scheme.error,
                    MetricTone.warning => scheme.secondary,
                    MetricTone.standard => scheme.primary,
                  },
                ),
              ),
            ],
          ),
        ),
        if (children.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 18.0 + 14.0),
            child: Container(
              margin: const EdgeInsets.only(top: AppSpacing.xs),
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.47),
                  ),
                ),
              ),
              child: Column(
                children: [
                  for (var index = 0; index < children.length; index++) ...[
                    _CategoryTreeNode(
                      category: children[index],
                      source: source,
                      state: state,
                      depth: depth + 1,
                      tone: tone,
                      onEdit: onEdit,
                      onAddChild: onAddChild,
                      onToggleArchive: onToggleArchive,
                      onDelete: onDelete,
                    ),

                    if (index != children.length - 1)
                      const SizedBox(height: AppSpacing.xs),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

enum _CategoryAction { edit, addChild, toggleArchive, delete }

List<Category> _visibleCategories(
  List<Category> categories, {
  required bool includeArchived,
}) {
  return categories
      .where((category) => includeArchived || !category.isArchived)
      .toList();
}

List<Category> _categoryLevel(
  LedgerState state,
  List<Category> source, {
  String? parentId,
}) {
  final byId = {for (final category in source) category.id: category};
  final items = source.where((category) {
    final directParentId =
        category.parentId != null && byId.containsKey(category.parentId)
        ? category.parentId
        : null;
    return directParentId == parentId;
  }).toList();
  items.sort((left, right) => compareCategoriesByUsage(state, left, right));
  return items;
}

List<Category> _parentCategoryOptions(LedgerState state, {Category? category}) {
  final descendants = category == null
      ? <String>{}
      : _categoryDescendantIds(state.categories, category.id);
  final items = state.categories.where((item) {
    if (item.isArchived) return false;
    if (category != null && item.id == category.id) return false;
    if (descendants.contains(item.id)) return false;
    return true;
  }).toList();
  items.sort((left, right) {
    return categoryPath(state, left).compareTo(categoryPath(state, right));
  });
  return items;
}

Set<String> _categoryDescendantIds(
  List<Category> categories,
  String categoryId,
) {
  final descendants = <String>{};

  void collect(String parentId) {
    for (final category in categories) {
      if (category.parentId != parentId || descendants.contains(category.id)) {
        continue;
      }
      descendants.add(category.id);
      collect(category.id);
    }
  }

  collect(categoryId);
  return descendants;
}

String _categoryNodeSubtitle(
  Category category, {
  required int childCount,
  required int depth,
}) {
  final parts = <String>[
    depth == 0 ? 'Category' : 'Subcategory',
    if (childCount > 0)
      '$childCount ${childCount == 1 ? 'subcategory' : 'subcategories'}',
    if (category.isArchived) 'archived',
  ];
  return parts.join(' · ');
}
