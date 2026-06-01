import type { Account, Category, CategoryKind } from '@1wallet/domain/types';
import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import {
    Appbar,
    IconButton,
    Portal,
    Surface,
    Text,
    TouchableRipple,
    useTheme,
} from 'react-native-paper';
import { SafeAreaView } from 'react-native-safe-area-context';
import { accountTypeLabel, resolveAccountIconVisual } from '../../accountOptions';
import { resolveCategoryIconVisual } from '../../categoryIcons';
import {
    buildCategoryTree,
    categoryBreadcrumb,
    categoryChildCount,
    categoryLevel,
} from '../../categoryTree';
import type { AppIconName } from '../../iconSystem';
import { iconSurfaceForThemeTone } from '../../iconSystem';
import { useBackLayer } from '../AppBackLayer';
import { PremiumSearchInput, premiumFieldColors } from '../AppKit';

type CategoryPickerKind = Extract<CategoryKind, 'expense' | 'income'>;

const CATEGORY_FILTER_KINDS: CategoryPickerKind[] = ['expense', 'income'];
const CATEGORY_KIND_META: Record<CategoryPickerKind, { label: string; description: string }> = {
  expense: { label: 'Expense categories', description: 'Spending and outgoing records' },
  income: { label: 'Income categories', description: 'Money-in records' },
};

export function AccountPickerOverlay({
  visible,
  title,
  accounts,
  selectedId,
  balances,
  onDismiss,
  onCreate,
  onSelect,
}: {
  visible: boolean;
  title: string;
  accounts: Account[];
  selectedId?: string;
  balances: (account: Account) => string;
  onDismiss: () => void;
  onCreate: () => void;
  onSelect: (account: Account) => void;
}) {
  const theme = useTheme();
  const [query, setQuery] = useState('');

  useBackLayer(visible, onDismiss);

  useEffect(() => {
    if (!visible) setQuery('');
  }, [visible]);

  const filtered = useMemo(() => {
    const normalized = query.trim().toLowerCase();
    return accounts.filter((account) => {
      if (!normalized) return true;
      return [account.name, account.type, account.institution ?? '', account.groupName ?? '']
        .join(' ')
        .toLowerCase()
        .includes(normalized);
    });
  }, [accounts, query]);

  if (!visible) return null;

  return (
    <Portal>
      <Surface
        style={[styles.fullScreenOverlay, { backgroundColor: theme.colors.background }]}
        elevation={0}
      >
        <SafeAreaView style={styles.overlaySafeArea} edges={['top', 'left', 'right']}>
          <Appbar.Header elevated={false} style={{ backgroundColor: theme.colors.background }}>
            <Appbar.BackAction onPress={onDismiss} />
            <Appbar.Content title={title} titleStyle={styles.appbarTitle} />
            <Appbar.Action icon="plus" onPress={onCreate} />
          </Appbar.Header>
          <View style={styles.overlayContent}>
            <PremiumSearchInput
              placeholder="Search accounts"
              value={query}
              onChangeText={setQuery}
            />
            <ScrollView keyboardShouldPersistTaps="handled" showsVerticalScrollIndicator={false}>
              {filtered.map((account) => {
                const selected = selectedId === account.id;
                const fieldColors = premiumFieldColors(theme, { selected });
                const visual = resolveAccountIconVisual(account);
                return (
                  <TouchableRipple
                    key={account.id}
                    style={[
                      styles.pickerChoice,
                      {
                        backgroundColor: selected
                          ? theme.colors.primaryContainer
                          : fieldColors.background,
                        borderColor: selected ? fieldColors.activeBorder : fieldColors.border,
                      },
                      !account.includeInTotals && styles.excludedRow,
                    ]}
                    onPress={() => onSelect(account)}
                    borderless
                  >
                    <View style={styles.pickerRow}>
                      <View
                        style={[styles.selectorIcon, { backgroundColor: visual.backgroundColor }]}
                      >
                        <MaterialCommunityIcons
                          name={visual.icon}
                          size={20}
                          color={visual.iconColor}
                        />
                      </View>
                      <View style={styles.selectorCopy}>
                        <Text variant="titleMedium" numberOfLines={2} style={styles.pickerTitle}>
                          {account.name}
                        </Text>
                        <Text
                          variant="bodySmall"
                          numberOfLines={1}
                          style={{ color: theme.colors.onSurfaceVariant }}
                        >
                          {accountTypeLabel(account.type)} - {balances(account)}
                        </Text>
                        {!account.includeInTotals ? (
                          <Text variant="labelSmall" style={{ color: theme.colors.secondary }}>
                            Excluded from totals
                          </Text>
                        ) : null}
                      </View>
                      {selected ? <IconButton icon="check" size={20} /> : null}
                    </View>
                  </TouchableRipple>
                );
              })}
            </ScrollView>
          </View>
        </SafeAreaView>
      </Surface>
    </Portal>
  );
}

export function CategoryPickerOverlay({
  visible,
  kind,
  categories,
  selectedId,
  allowClear = true,
  leafOnly = false,
  onDismiss,
  onClear,
  onSelect,
}: {
  visible: boolean;
  kind: CategoryPickerKind;
  categories: Category[];
  selectedId?: string;
  allowClear?: boolean;
  leafOnly?: boolean;
  onDismiss: () => void;
  onClear?: () => void;
  onSelect: (category: Category) => void;
}) {
  const theme = useTheme();
  const [query, setQuery] = useState('');
  const [parentId, setParentId] = useState<string | undefined>();

  useEffect(() => {
    if (!visible) {
      setQuery('');
      setParentId(undefined);
    }
  }, [visible]);

  useEffect(() => {
    setQuery('');
    setParentId(undefined);
  }, [kind]);

  useEffect(() => {
    if (!parentId) return;
    const parentVisible = categories.some(
      (category) => category.id === parentId && category.kind === kind && !category.isArchived,
    );
    if (!parentVisible) setParentId(undefined);
  }, [categories, kind, parentId]);

  const searchRows = useMemo(() => {
    return buildCategoryTree(categories, { kind, query });
  }, [categories, kind, query]);

  const levelCategories = useMemo(() => {
    return categoryLevel(categories, { kind, parentId });
  }, [categories, kind, parentId]);

  const currentParent = useMemo(() => {
    if (!parentId) return undefined;
    return categories.find((category) => category.id === parentId);
  }, [categories, parentId]);
  const currentParentVisual = currentParent
    ? resolveCategoryIconVisual(currentParent, categories)
    : undefined;

  const currentPath = categoryBreadcrumb(categories, parentId);
  const searchMode = query.trim().length > 0;
  const canClear = allowClear && Boolean(onClear);
  const handleBack = useCallback(() => {
    if (currentParent && !searchMode) {
      setParentId(currentParent.parentId);
      return true;
    }

    onDismiss();
    return true;
  }, [currentParent, onDismiss, searchMode]);

  useBackLayer(visible, handleBack);

  if (!visible) return null;

  return (
    <Portal>
      <Surface
        style={[styles.fullScreenOverlay, { backgroundColor: theme.colors.background }]}
        elevation={0}
      >
        <SafeAreaView style={styles.overlaySafeArea} edges={['top', 'left', 'right']}>
          <Appbar.Header
            elevated={false}
            statusBarHeight={0}
            style={[styles.appbarHeader, { backgroundColor: theme.colors.background }]}
          >
            <Appbar.BackAction
              onPress={() => {
                if (currentParent && !searchMode) setParentId(currentParent.parentId);
                else onDismiss();
              }}
            />
            <Appbar.Content
              title={searchMode ? 'Search categories' : (currentParent?.name ?? 'Choose category')}
              titleStyle={styles.appbarTitle}
            />
            {currentParent && !searchMode ? (
              <Appbar.Action icon="close" onPress={onDismiss} />
            ) : null}
          </Appbar.Header>
          <View style={styles.categoryOverlayContent}>
            <PremiumSearchInput
              placeholder="Search categories"
              value={query}
              onChangeText={setQuery}
            />
            {currentPath && !searchMode ? (
              <View
                style={[
                  styles.pathPill,
                  {
                    backgroundColor: theme.colors.secondaryContainer,
                    borderColor: theme.colors.outlineVariant,
                  },
                ]}
              >
                <MaterialCommunityIcons
                  name="subdirectory-arrow-right"
                  size={16}
                  color={theme.colors.onSecondaryContainer}
                />
                <Text
                  variant="labelMedium"
                  numberOfLines={1}
                  style={{ color: theme.colors.onSecondaryContainer }}
                >
                  {currentPath}
                </Text>
              </View>
            ) : null}
            <ScrollView keyboardShouldPersistTaps="handled" showsVerticalScrollIndicator={false}>
              {canClear && !searchMode && !currentParent ? (
                <TouchableRipple
                  onPress={onClear}
                  style={[
                    styles.pickerChoice,
                    {
                      backgroundColor: !selectedId
                        ? theme.colors.secondaryContainer
                        : premiumFieldColors(theme).background,
                      borderColor: !selectedId
                        ? theme.colors.secondary
                        : premiumFieldColors(theme).border,
                    },
                  ]}
                  borderless
                >
                  <View style={styles.pickerRow}>
                    <View
                      style={[
                        styles.selectorIcon,
                        { backgroundColor: theme.colors.surfaceVariant },
                      ]}
                    >
                      <MaterialCommunityIcons
                        name="minus-circle-outline"
                        size={20}
                        color={theme.colors.onSurfaceVariant}
                      />
                    </View>
                    <View style={styles.selectorCopy}>
                      <Text variant="titleMedium">Uncategorized</Text>
                      <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                        Keep this record without a category
                      </Text>
                    </View>
                  </View>
                </TouchableRipple>
              ) : null}

              {!leafOnly && !searchMode && currentParent ? (
                <TouchableRipple
                  onPress={() => onSelect(currentParent)}
                  style={[
                    styles.pickerChoice,
                    {
                      backgroundColor:
                        selectedId === currentParent.id
                          ? theme.colors.secondaryContainer
                          : premiumFieldColors(theme).background,
                      borderColor:
                        selectedId === currentParent.id
                          ? theme.colors.secondary
                          : premiumFieldColors(theme).border,
                    },
                  ]}
                  borderless
                >
                  <View style={styles.pickerRow}>
                    <View
                      style={[
                        styles.selectorIcon,
                        { backgroundColor: currentParentVisual?.backgroundColor },
                      ]}
                    >
                      <MaterialCommunityIcons
                        name={currentParentVisual?.icon ?? 'shape-outline'}
                        size={22}
                        color={currentParentVisual?.iconColor ?? theme.colors.onTertiaryContainer}
                      />
                    </View>
                    <View style={styles.selectorCopy}>
                      <Text variant="titleMedium" numberOfLines={2} style={styles.pickerTitle}>
                        Use {currentParent.name}
                      </Text>
                      <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                        Select this parent category
                      </Text>
                      {selectedId === currentParent.id ? (
                        <Text variant="labelSmall" style={{ color: theme.colors.primary }}>
                          Selected
                        </Text>
                      ) : null}
                    </View>
                  </View>
                </TouchableRipple>
              ) : null}

              {searchMode && searchRows.length === 0 ? (
                <View style={styles.emptyPickerState}>
                  <MaterialCommunityIcons
                    name="shape-outline"
                    size={24}
                    color={theme.colors.onSurfaceVariant}
                  />
                  <Text variant="bodyMedium" style={{ color: theme.colors.onSurfaceVariant }}>
                    No categories found
                  </Text>
                </View>
              ) : null}

              {!searchMode && levelCategories.length === 0 ? (
                <View style={styles.emptyPickerState}>
                  <MaterialCommunityIcons
                    name="shape-outline"
                    size={24}
                    color={theme.colors.onSurfaceVariant}
                  />
                  <Text variant="bodyMedium" style={{ color: theme.colors.onSurfaceVariant }}>
                    No subcategories here
                  </Text>
                </View>
              ) : null}

              {searchMode
                ? searchRows.map((row) => {
                    const childCount = categoryChildCount(categories, row.category.id, { kind });
                    return (
                      <CategoryPickerRow
                        key={row.category.id}
                        category={row.category}
                        categories={categories}
                        supporting={row.breadcrumb}
                        selected={selectedId === row.category.id}
                        showChevron={childCount > 0}
                        onSelect={() => {
                          if (leafOnly && childCount > 0) {
                            setParentId(row.category.id);
                            setQuery('');
                          } else {
                            onSelect(row.category);
                          }
                        }}
                      />
                    );
                  })
                : levelCategories.map((category) => {
                    const childCount = categoryChildCount(categories, category.id, { kind });
                    return (
                      <CategoryPickerRow
                        key={category.id}
                        category={category}
                        categories={categories}
                        supporting={
                          childCount > 0
                            ? `${childCount} ${childCount === 1 ? 'subcategory' : 'subcategories'}`
                            : (currentParent?.name ?? 'Category')
                        }
                        selected={selectedId === category.id}
                        showChevron={childCount > 0}
                        onSelect={() => {
                          if (childCount > 0) setParentId(category.id);
                          else onSelect(category);
                        }}
                      />
                    );
                  })}
            </ScrollView>
          </View>
        </SafeAreaView>
      </Surface>
    </Portal>
  );
}

export function CategoryMultiPickerOverlay({
  visible,
  categories,
  selectedIds,
  includeUncategorized = false,
  onDismiss,
  onToggleCategory,
  onToggleUncategorized,
  onClear,
}: {
  visible: boolean;
  categories: Category[];
  selectedIds: string[];
  includeUncategorized?: boolean;
  onDismiss: () => void;
  onToggleCategory: (category: Category) => void;
  onToggleUncategorized?: () => void;
  onClear?: () => void;
}) {
  const theme = useTheme();
  const [query, setQuery] = useState('');
  const [kind, setKind] = useState<CategoryPickerKind | undefined>();
  const [parentId, setParentId] = useState<string | undefined>();
  const selectedIdSet = useMemo(() => new Set(selectedIds), [selectedIds]);

  useEffect(() => {
    if (!visible) {
      setQuery('');
      setKind(undefined);
      setParentId(undefined);
    }
  }, [visible]);

  useEffect(() => {
    if (!kind || !parentId) return;
    const parentVisible = categories.some(
      (category) => category.id === parentId && category.kind === kind && !category.isArchived,
    );
    if (!parentVisible) setParentId(undefined);
  }, [categories, kind, parentId]);

  const searchMode = query.trim().length > 0;
  const searchRows = useMemo(() => {
    return buildCategoryTree(categories, { query });
  }, [categories, query]);
  const levelCategories = useMemo(() => {
    if (!kind) return [];
    return categoryLevel(categories, { kind, parentId });
  }, [categories, kind, parentId]);
  const currentParent = useMemo(() => {
    if (!parentId) return undefined;
    return categories.find((category) => category.id === parentId);
  }, [categories, parentId]);
  const currentParentVisual = currentParent
    ? resolveCategoryIconVisual(currentParent, categories)
    : undefined;
  const currentPath = categoryBreadcrumb(categories, parentId);
  const hasSelection = selectedIds.length > 0 || includeUncategorized;

  const handleBack = useCallback(() => {
    if (searchMode) {
      setQuery('');
      return true;
    }
    if (currentParent) {
      setParentId(currentParent.parentId);
      return true;
    }
    if (kind) {
      setKind(undefined);
      return true;
    }
    onDismiss();
    return true;
  }, [currentParent, kind, onDismiss, searchMode]);

  useBackLayer(visible, handleBack);

  if (!visible) return null;

  const openCategory = (category: Category, childCount: number) => {
    if (childCount > 0) {
      setKind(category.kind as CategoryPickerKind);
      setParentId(category.id);
      setQuery('');
      return;
    }
    onToggleCategory(category);
  };

  const title = searchMode
    ? 'Search categories'
    : (currentParent?.name ?? (kind ? CATEGORY_KIND_META[kind].label : 'Choose categories'));

  return (
    <Portal>
      <Surface
        style={[styles.fullScreenOverlay, { backgroundColor: theme.colors.background }]}
        elevation={0}
      >
        <SafeAreaView style={styles.overlaySafeArea} edges={['top', 'left', 'right']}>
          <Appbar.Header
            elevated={false}
            statusBarHeight={0}
            style={[styles.appbarHeader, { backgroundColor: theme.colors.background }]}
          >
            <Appbar.BackAction onPress={handleBack} />
            <Appbar.Content title={title} titleStyle={styles.appbarTitle} />
            {hasSelection && onClear ? (
              <Appbar.Action icon="filter-remove" onPress={onClear} />
            ) : null}
            <Appbar.Action icon="check" onPress={onDismiss} />
          </Appbar.Header>
          <View style={styles.categoryOverlayContent}>
            <PremiumSearchInput
              placeholder="Search categories"
              value={query}
              onChangeText={setQuery}
            />
            {currentPath && !searchMode ? (
              <View
                style={[
                  styles.pathPill,
                  {
                    backgroundColor: theme.colors.secondaryContainer,
                    borderColor: theme.colors.outlineVariant,
                  },
                ]}
              >
                <MaterialCommunityIcons
                  name="subdirectory-arrow-right"
                  size={16}
                  color={theme.colors.onSecondaryContainer}
                />
                <Text
                  variant="labelMedium"
                  numberOfLines={1}
                  style={{ color: theme.colors.onSecondaryContainer }}
                >
                  {currentPath}
                </Text>
              </View>
            ) : null}
            <ScrollView keyboardShouldPersistTaps="handled" showsVerticalScrollIndicator={false}>
              {!searchMode && !kind ? (
                <>
                  {onToggleUncategorized ? (
                    <CategoryMultiPickerSpecialRow
                      icon="shape-outline"
                      title="Uncategorized"
                      supporting="Records without a category"
                      selected={includeUncategorized}
                      onPress={onToggleUncategorized}
                    />
                  ) : null}
                  {CATEGORY_FILTER_KINDS.map((item) => {
                    const meta = CATEGORY_KIND_META[item];
                    const count = categoryLevel(categories, { kind: item }).length;
                    return (
                      <CategoryMultiPickerSpecialRow
                        key={item}
                        icon={item === 'income' ? 'bank-plus' : 'bank-minus'}
                        title={meta.label}
                        supporting={`${count} top-level ${count === 1 ? 'category' : 'categories'}`}
                        selected={false}
                        onPress={() => setKind(item)}
                      />
                    );
                  })}
                </>
              ) : null}

              {!searchMode && currentParent ? (
                <CategoryMultiPickerRow
                  category={currentParent}
                  categories={categories}
                  supporting="Select this parent category"
                  selected={selectedIdSet.has(currentParent.id)}
                  showChevron={false}
                  onOpen={() => onToggleCategory(currentParent)}
                  onToggleSelect={() => onToggleCategory(currentParent)}
                  titlePrefix="Use "
                  visualOverride={currentParentVisual}
                />
              ) : null}

              {searchMode && searchRows.length === 0 ? (
                <View style={styles.emptyPickerState}>
                  <MaterialCommunityIcons
                    name="shape-outline"
                    size={24}
                    color={theme.colors.onSurfaceVariant}
                  />
                  <Text variant="bodyMedium" style={{ color: theme.colors.onSurfaceVariant }}>
                    No categories found
                  </Text>
                </View>
              ) : null}

              {!searchMode && kind && levelCategories.length === 0 ? (
                <View style={styles.emptyPickerState}>
                  <MaterialCommunityIcons
                    name="shape-outline"
                    size={24}
                    color={theme.colors.onSurfaceVariant}
                  />
                  <Text variant="bodyMedium" style={{ color: theme.colors.onSurfaceVariant }}>
                    No subcategories here
                  </Text>
                </View>
              ) : null}

              {searchMode
                ? searchRows.map((row) => {
                    const childCount = categoryChildCount(categories, row.category.id, {
                      kind: row.category.kind,
                    });
                    return (
                      <CategoryMultiPickerRow
                        key={row.category.id}
                        category={row.category}
                        categories={categories}
                        supporting={row.breadcrumb}
                        selected={selectedIdSet.has(row.category.id)}
                        showChevron={childCount > 0}
                        onOpen={() => openCategory(row.category, childCount)}
                        onToggleSelect={() => onToggleCategory(row.category)}
                      />
                    );
                  })
                : levelCategories.map((category) => {
                    const childCount = categoryChildCount(categories, category.id, { kind });
                    return (
                      <CategoryMultiPickerRow
                        key={category.id}
                        category={category}
                        categories={categories}
                        supporting={
                          childCount > 0
                            ? `${childCount} ${childCount === 1 ? 'subcategory' : 'subcategories'}`
                            : (currentParent?.name ??
                              CATEGORY_KIND_META[category.kind as CategoryPickerKind].label)
                        }
                        selected={selectedIdSet.has(category.id)}
                        showChevron={childCount > 0}
                        onOpen={() => openCategory(category, childCount)}
                        onToggleSelect={() => onToggleCategory(category)}
                      />
                    );
                  })}
            </ScrollView>
          </View>
        </SafeAreaView>
      </Surface>
    </Portal>
  );
}

function CategoryMultiPickerSpecialRow({
  icon,
  title,
  supporting,
  selected,
  onPress,
}: {
  icon: AppIconName;
  title: string;
  supporting: string;
  selected: boolean;
  onPress: () => void;
}) {
  const theme = useTheme();
  const fieldColors = premiumFieldColors(theme, { selected });
  const iconSurface = iconSurfaceForThemeTone(theme, 'record');
  return (
    <TouchableRipple
      onPress={onPress}
      style={[
        styles.categoryChoice,
        {
          backgroundColor: selected ? theme.colors.secondaryContainer : fieldColors.background,
          borderColor: selected ? fieldColors.activeBorder : fieldColors.border,
        },
      ]}
      borderless
    >
      <View style={styles.categoryMainInner}>
        <View style={[styles.selectorIcon, { backgroundColor: iconSurface.backgroundColor }]}>
          <MaterialCommunityIcons name={icon} size={22} color={iconSurface.iconColor} />
        </View>
        <View style={styles.selectorCopy}>
          <Text variant="titleMedium" numberOfLines={2} style={styles.pickerTitle}>
            {title}
          </Text>
          <Text
            variant="bodySmall"
            numberOfLines={1}
            style={{ color: theme.colors.onSurfaceVariant }}
          >
            {supporting}
          </Text>
        </View>
        <MaterialCommunityIcons
          name={selected ? 'check-circle' : 'chevron-right'}
          size={24}
          color={selected ? theme.colors.primary : theme.colors.onSurfaceVariant}
        />
      </View>
    </TouchableRipple>
  );
}

function CategoryMultiPickerRow({
  category,
  categories,
  supporting,
  selected,
  showChevron,
  titlePrefix = '',
  visualOverride,
  onOpen,
  onToggleSelect,
}: {
  category: Category;
  categories: Category[];
  supporting: string;
  selected: boolean;
  showChevron: boolean;
  titlePrefix?: string;
  visualOverride?: ReturnType<typeof resolveCategoryIconVisual>;
  onOpen: () => void;
  onToggleSelect: () => void;
}) {
  const theme = useTheme();
  const fieldColors = premiumFieldColors(theme, { selected });
  const visual = visualOverride ?? resolveCategoryIconVisual(category, categories);
  return (
    <View
      style={[
        styles.categoryChoice,
        {
          backgroundColor: selected ? theme.colors.secondaryContainer : fieldColors.background,
          borderColor: selected ? fieldColors.activeBorder : fieldColors.border,
        },
      ]}
    >
      <View style={styles.categoryMainInner}>
        <TouchableRipple
          onPress={onToggleSelect}
          style={[
            styles.selectorIconHit,
            { borderColor: selected ? theme.colors.primary : 'transparent' },
          ]}
          borderless
        >
          <View style={[styles.selectorIcon, { backgroundColor: visual.backgroundColor }]}>
            <MaterialCommunityIcons name={visual.icon} size={22} color={visual.iconColor} />
            {selected ? (
              <View style={[styles.selectorCheckBadge, { backgroundColor: theme.colors.primary }]}>
                <MaterialCommunityIcons name="check" size={12} color={theme.colors.onPrimary} />
              </View>
            ) : null}
          </View>
        </TouchableRipple>
        <TouchableRipple onPress={onOpen} style={styles.categoryOpenArea} borderless>
          <View style={styles.categoryOpenInner}>
            <View style={styles.selectorCopy}>
              <Text variant="titleMedium" numberOfLines={2} style={styles.pickerTitle}>
                {titlePrefix}
                {category.name}
              </Text>
              <Text
                variant="bodySmall"
                numberOfLines={1}
                style={{ color: theme.colors.onSurfaceVariant }}
              >
                {supporting}
              </Text>
              <Text
                variant="labelSmall"
                numberOfLines={1}
                style={{ color: theme.colors.onSurfaceVariant }}
              >
                {selected ? 'Selected' : `${visual.iconLabel} icon`}
              </Text>
            </View>
            <MaterialCommunityIcons
              name={
                showChevron ? 'chevron-right' : selected ? 'check-circle' : 'plus-circle-outline'
              }
              size={24}
              color={selected ? theme.colors.primary : theme.colors.onSurfaceVariant}
            />
          </View>
        </TouchableRipple>
      </View>
    </View>
  );
}

function CategoryPickerRow({
  category,
  categories,
  supporting,
  selected,
  showChevron = false,
  onSelect,
}: {
  category: Category;
  categories: Category[];
  supporting: string;
  selected: boolean;
  showChevron?: boolean;
  onSelect: () => void;
}) {
  const theme = useTheme();
  const fieldColors = premiumFieldColors(theme, { selected });
  const visual = resolveCategoryIconVisual(category, categories);
  return (
    <TouchableRipple
      onPress={onSelect}
      style={[
        styles.categoryChoice,
        {
          backgroundColor: selected ? theme.colors.secondaryContainer : fieldColors.background,
          borderColor: selected ? fieldColors.activeBorder : fieldColors.border,
        },
      ]}
      borderless
    >
      <View style={styles.categoryMainInner}>
        <View style={[styles.selectorIcon, { backgroundColor: visual.backgroundColor }]}>
          <MaterialCommunityIcons name={visual.icon} size={22} color={visual.iconColor} />
        </View>
        <View style={styles.selectorCopy}>
          <Text variant="titleMedium" numberOfLines={2} style={styles.pickerTitle}>
            {category.name}
          </Text>
          <Text
            variant="bodySmall"
            numberOfLines={1}
            style={{ color: theme.colors.onSurfaceVariant }}
          >
            {supporting}
          </Text>
          <Text
            variant="labelSmall"
            numberOfLines={1}
            style={{ color: theme.colors.onSurfaceVariant }}
          >
            {visual.iconLabel} icon
          </Text>
        </View>
        {selected ? (
          <MaterialCommunityIcons name="check-circle" size={22} color={theme.colors.primary} />
        ) : showChevron ? (
          <MaterialCommunityIcons
            name="chevron-right"
            size={24}
            color={theme.colors.onSurfaceVariant}
          />
        ) : null}
      </View>
    </TouchableRipple>
  );
}

const styles = StyleSheet.create({
  appbarTitle: { fontWeight: '700' },
  appbarHeader: { elevation: 0 },
  fullScreenOverlay: {
    ...StyleSheet.absoluteFill,
    zIndex: 1000,
  },
  overlaySafeArea: { flex: 1 },
  overlayContent: { flex: 1, gap: 12, paddingHorizontal: tokens.space.lg, paddingBottom: 24 },
  categoryOverlayContent: {
    flex: 1,
    gap: 12,
    paddingHorizontal: tokens.space.lg,
    paddingTop: 2,
    paddingBottom: 24,
  },
  pathPill: {
    minHeight: 34,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    borderRadius: tokens.radius.pill,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 12,
  },
  pickerChoice: {
    borderRadius: tokens.radius.lg,
    borderWidth: 1,
    marginBottom: tokens.space.sm,
    overflow: 'hidden',
  },
  pickerRow: {
    minHeight: 64,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  categoryChoice: {
    minHeight: 72,
    borderRadius: tokens.radius.lg,
    borderWidth: 1,
    marginBottom: 8,
    overflow: 'hidden',
  },
  categoryMainInner: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  categoryOpenArea: { flex: 1, minWidth: 0, borderRadius: tokens.radius.md, overflow: 'hidden' },
  categoryOpenInner: {
    minHeight: 52,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingLeft: 2,
  },
  selectorIcon: {
    width: 42,
    height: 42,
    borderRadius: tokens.radius.pill,
    alignItems: 'center',
    justifyContent: 'center',
  },
  selectorIconHit: {
    borderWidth: 2,
    borderRadius: tokens.radius.pill,
    padding: 2,
    overflow: 'visible',
  },
  selectorCheckBadge: {
    position: 'absolute',
    right: -2,
    bottom: -2,
    width: 18,
    height: 18,
    borderRadius: 9,
    alignItems: 'center',
    justifyContent: 'center',
  },
  pickerTitle: { lineHeight: 20 },
  selectorCopy: { flex: 1, minWidth: 0, gap: 2 },
  excludedRow: { opacity: 0.56 },
  emptyPickerState: { minHeight: 120, alignItems: 'center', justifyContent: 'center', gap: 8 },
});
