import type { Category, CategoryKind } from '@1wallet/domain/types';

export type CategoryTreeItem = {
  category: Category;
  depth: number;
  breadcrumb: string;
  hasChildren: boolean;
};

type CategoryLevelOptions = {
  kind?: CategoryKind;
  includeArchived?: boolean;
  parentId?: string;
};

export function categoryLevel(
  categories: Category[],
  { kind, includeArchived = false, parentId }: CategoryLevelOptions = {},
): Category[] {
  const source = visibleCategorySource(categories, { kind, includeArchived });
  const byId = new Map(source.map((category) => [category.id, category]));

  return source
    .filter((category) => {
      const directParentId =
        category.parentId && byId.has(category.parentId) ? category.parentId : undefined;
      return directParentId === parentId;
    })
    .sort(sortCategories);
}

export function categoryChildCount(
  categories: Category[],
  categoryId: string,
  { kind, includeArchived = false }: Omit<CategoryLevelOptions, 'parentId'> = {},
): number {
  return categoryLevel(categories, { kind, includeArchived, parentId: categoryId }).length;
}

export function buildCategoryTree(
  categories: Category[],
  {
    kind,
    includeArchived = false,
    query = '',
  }: { kind?: CategoryKind; includeArchived?: boolean; query?: string } = {},
): CategoryTreeItem[] {
  const normalizedQuery = query.trim().toLowerCase();
  const source = visibleCategorySource(categories, { kind, includeArchived });
  const byParent = new Map<string, Category[]>();
  const byId = new Map(source.map((category) => [category.id, category]));

  for (const category of source) {
    const parentKey = category.parentId && byId.has(category.parentId) ? category.parentId : 'root';
    const siblings = byParent.get(parentKey) ?? [];
    siblings.push(category);
    byParent.set(parentKey, siblings);
  }

  for (const siblings of byParent.values()) {
    siblings.sort(sortCategories);
  }

  const rows: CategoryTreeItem[] = [];
  const visit = (category: Category, depth: number, lineage: string[]) => {
    const breadcrumb = [...lineage, category.name].join(' > ');
    const children = byParent.get(category.id) ?? [];
    const item: CategoryTreeItem = {
      category,
      depth,
      breadcrumb,
      hasChildren: children.length > 0,
    };
    if (!normalizedQuery || breadcrumb.toLowerCase().includes(normalizedQuery)) {
      rows.push(item);
    }
    for (const child of children) visit(child, depth + 1, [...lineage, category.name]);
  };

  for (const root of byParent.get('root') ?? []) visit(root, 0, []);
  return rows;
}

export function categoryBreadcrumb(
  categories: Category[],
  categoryId?: string,
): string | undefined {
  if (!categoryId) return undefined;
  const byId = new Map(categories.map((category) => [category.id, category]));
  const names: string[] = [];
  const seen = new Set<string>();
  let current = byId.get(categoryId);
  while (current && !seen.has(current.id)) {
    seen.add(current.id);
    names.unshift(current.name);
    current = current.parentId ? byId.get(current.parentId) : undefined;
  }
  return names.length ? names.join(' > ') : undefined;
}

export function categoryDescendantIds(categories: Category[], categoryId: string): Set<string> {
  const descendants = new Set<string>();
  const collect = (parentId: string) => {
    for (const category of categories) {
      if (category.parentId !== parentId || descendants.has(category.id)) continue;
      descendants.add(category.id);
      collect(category.id);
    }
  };
  collect(categoryId);
  return descendants;
}

function visibleCategorySource(
  categories: Category[],
  { kind, includeArchived }: { kind?: CategoryKind; includeArchived: boolean },
) {
  return categories
    .filter((category) => (kind ? category.kind === kind : true))
    .filter((category) => includeArchived || !category.isArchived);
}

function sortCategories(left: Category, right: Category) {
  return left.sortOrder - right.sortOrder || left.name.localeCompare(right.name);
}
