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
        IconButton(
          onPressed: () => _openCategoryEditor(context, state),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
      child: Column(
        children: [
          SectionCard(
            title: 'Category tree',
            subtitle:
                'Same grouping as the RN app: parents first, subcategories nested below.',
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
                        tone: MetricTone.standard,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: MetricTile(
                        label: 'Subcategories',
                        value: '$subcategoryCount',
                        icon: Icons.account_tree_outlined,
                        compact: true,
                        tone: MetricTone.standard,
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

  Future<void> _openCategoryEditor(
    BuildContext context,
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
      context: context,
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
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_tree_outlined),
                  title: const Text('Parent group'),
                  subtitle: Text(
                    parentId == null
                        ? 'Top-level category'
                        : categoryPath(state, categoryById(state, parentId)),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
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
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor:
                        color ?? Theme.of(context).colorScheme.primary,
                    radius: 12,
                  ),
                  title: const Text('Color'),
                  subtitle: const Text('Choose a custom color'),
                  trailing: const Icon(Icons.palette_outlined),
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
                  LiquidGlassSwitchListTile(
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
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                        category == null
                            ? parentId == null
                                  ? 'Category created.'
                                  : 'Subcategory created.'
                            : 'Category saved.',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text('Are you sure you want to delete "${category.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

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
        Container(
          decoration: BoxDecoration(
            color: depth == 0
                ? scheme.surfaceContainerLow
                : scheme.surfaceContainerHighest.withAlpha(120),
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: depth == 0
                  ? scheme.outlineVariant
                  : scheme.outlineVariant.withAlpha(140),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.md),
            onTap: () => onEdit(category),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
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
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
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
                        child: Text(
                          category.isArchived ? 'Restore' : 'Archive',
                        ),
                      ),
                      const PopupMenuItem(
                        value: _CategoryAction.delete,
                        child: Text(
                          'Delete',
                          style: TextStyle(color: Colors.red),
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
                  left: BorderSide(color: scheme.outlineVariant.withAlpha(120)),
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
