import type { Category, CategoryKind } from '@1wallet/domain/types';
import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { router } from 'expo-router';
import { useCallback, useMemo, useState } from 'react';
import {
    ScrollView,
    StyleSheet,
    useWindowDimensions,
    View,
    type StyleProp,
    type ViewStyle,
} from 'react-native';
import {
    Appbar,
    Button,
    HelperText,
    IconButton,
    Menu,
    Portal,
    Snackbar,
    Surface,
    Text,
    TextInput,
    TouchableRipple,
    useTheme,
} from 'react-native-paper';
import { SafeAreaView } from 'react-native-safe-area-context';
import {
    CATEGORY_ICON_OPTIONS,
    categoryIconLabel,
    inferCategoryIcon,
    resolveCategoryIcon,
    resolveCategoryIconVisual,
    shouldSuggestCategoryIcon,
} from '../src/categoryIcons';
import { categoryBreadcrumb, categoryChildCount, categoryLevel } from '../src/categoryTree';
import { CATEGORY_COLOR_OPTIONS, DEFAULT_CATEGORY_COLOR } from '../src/colorPalettes';
import { useBackLayer } from '../src/components/AppBackLayer';
import {
    AppScreen,
    EmptyState,
    InlineMeta,
    isAppIconName,
    PremiumSearchInput,
    PremiumTextInput,
    SectionCard,
    type AppIconName,
} from '../src/components/AppKit';
import { ColorPickerIconPreview, ColorPickerOverlay } from '../src/components/ColorPickerOverlay';
import {
    OptionListOverlay,
    OptionSelectorRow,
    type OptionListItem,
} from '../src/components/OptionListOverlay';
import { iconSurfaceForThemeTone } from '../src/iconSystem';
import { normalizeHexColor } from '../src/theme';

const CATEGORY_KIND_OPTIONS: OptionListItem<CategoryKind>[] = [
  {
    value: 'expense',
    label: 'Expense',
    description: 'Spending categories and subcategories',
    icon: 'arrow-down-circle-outline',
  },
  {
    value: 'income',
    label: 'Income',
    description: 'Salary, refunds, interest, and other inflows',
    icon: 'arrow-up-circle-outline',
  },
  {
    value: 'transfer',
    label: 'Transfer',
    description: 'Internal movement and balancing categories',
    icon: 'swap-horizontal-circle-outline',
  },
  {
    value: 'system',
    label: 'System',
    description: 'Generated categories used by the ledger engine',
    icon: 'shield-star-outline',
  },
];

const EDITABLE_CATEGORY_KIND_OPTIONS = CATEGORY_KIND_OPTIONS.filter(
  (item) => item.value !== 'system',
);

const ARCHIVE_FILTER_OPTIONS: OptionListItem<'active' | 'all'>[] = [
  {
    value: 'active',
    label: 'Active only',
    description: 'Hide archived categories from this manager',
    icon: 'eye-outline',
  },
  {
    value: 'all',
    label: 'Include archived',
    description: 'Show archived categories beside active ones',
    icon: 'archive-outline',
  },
];

type CategoryDraft =
  | {
      mode: 'create';
      parentId?: string;
      kind: CategoryKind;
      name: string;
      icon: string;
      color: string;
    }
  | {
      mode: 'edit';
      category: Category;
      kind: CategoryKind;
      name: string;
      icon: string;
      color: string;
    };

export default function Categories() {
  const theme = useTheme();
  const { width } = useWindowDimensions();
  const { state, addCategory, editCategory } = useLedger();
  const [kind, setKind] = useState<CategoryKind>('expense');
  const [showArchived, setShowArchived] = useState(false);
  const [categoryQuery, setCategoryQuery] = useState('');
  const [picker, setPicker] = useState<'kind' | 'archive' | null>(null);
  const [currentParentId, setCurrentParentId] = useState<string | undefined>();
  const [menuCategoryId, setMenuCategoryId] = useState<string | null>(null);
  const [draft, setDraft] = useState<CategoryDraft | null>(null);
  const [formError, setFormError] = useState<string | null>(null);
  const [snackbar, setSnackbar] = useState<string | null>(null);

  const currentParent = useMemo(
    () =>
      currentParentId
        ? state.categories.find(
            (category) =>
              category.id === currentParentId &&
              category.kind === kind &&
              (showArchived || !category.isArchived),
          )
        : undefined,
    [currentParentId, kind, showArchived, state.categories],
  );
  const currentParentPath = categoryBreadcrumb(state.categories, currentParent?.id);
  const levelCategories = useMemo(
    () =>
      categoryLevel(state.categories, {
        kind,
        includeArchived: showArchived,
        parentId: currentParent?.id,
      }),
    [currentParent?.id, kind, showArchived, state.categories],
  );
  const filteredCategories = useMemo(() => {
    const needle = categoryQuery.trim().toLowerCase();
    if (!needle) return levelCategories;
    return levelCategories.filter((category) => {
      const breadcrumb = categoryBreadcrumb(state.categories, category.id) ?? category.name;
      return `${category.name} ${breadcrumb}`.toLowerCase().includes(needle);
    });
  }, [categoryQuery, levelCategories, state.categories]);
  const categoryColumnCount = width >= 720 ? 3 : width >= 360 ? 2 : 1;
  const categoryCardBasis =
    categoryColumnCount === 1 ? '100%' : categoryColumnCount === 2 ? '48%' : '31%';
  const categoryCardStyle = useMemo<StyleProp<ViewStyle>>(
    () => ({ flexBasis: categoryCardBasis, maxWidth: categoryCardBasis }),
    [categoryCardBasis],
  );
  const archivedCount = state.categories.filter(
    (category) => category.kind === kind && category.isArchived,
  ).length;
  const activeCount = state.categories.filter(
    (category) => category.kind === kind && !category.isArchived,
  ).length;
  const kindOption = CATEGORY_KIND_OPTIONS.find((option) => option.value === kind);
  const levelTitle =
    currentParent?.name ?? `${optionLabel(CATEGORY_KIND_OPTIONS, kind)} categories`;
  const levelSubtitle = currentParent
    ? `${currentParentPath ?? currentParent.name} - ${countLabel(filteredCategories.length, 'subcategory', 'subcategories')}`
    : `${countLabel(activeCount, 'active category', 'active categories')} - ${countLabel(archivedCount, 'archived', 'archived')}`;

  const startCreate = (parent?: Category) => {
    setMenuCategoryId(null);
    setFormError(null);
    setDraft({
      mode: 'create',
      parentId: parent?.id,
      kind: parent?.kind ?? kind,
      name: '',
      icon: parent ? resolveCategoryIcon(parent, state.categories) : inferCategoryIcon('', kind),
      color: parent
        ? resolveCategoryIconVisual(parent, state.categories).backgroundColor
        : DEFAULT_CATEGORY_COLOR,
    });
  };

  const startEdit = (category: Category) => {
    setMenuCategoryId(null);
    setFormError(null);
    setDraft({
      mode: 'edit',
      category,
      kind: category.kind,
      name: category.name,
      icon: resolveCategoryIcon(category, state.categories),
      color: category.color ?? '',
    });
  };

  const openCategory = useCallback((category: Category) => {
    setDraft(null);
    setMenuCategoryId(null);
    setCategoryQuery('');
    setCurrentParentId(category.id);
  }, []);

  const goToParentCategory = useCallback(() => {
    const parentId = currentParentId
      ? state.categories.find((category) => category.id === currentParentId)?.parentId
      : undefined;
    setDraft(null);
    setMenuCategoryId(null);
    setCategoryQuery('');
    setCurrentParentId(parentId);
  }, [currentParentId, state.categories]);

  const handleBackLayer = useCallback(() => {
    if (draft) {
      setDraft(null);
      return true;
    }
    if (currentParentId) {
      goToParentCategory();
      return true;
    }
    return false;
  }, [currentParentId, draft, goToParentCategory]);

  useBackLayer(Boolean(draft) || Boolean(currentParentId), handleBackLayer);

  const saveDraft = async () => {
    if (!draft) return;
    const name = draft.name.trim();
    if (!name) {
      setFormError('Enter a category name');
      return;
    }
    const icon = draft.icon.trim();
    if (icon && !isAppIconName(icon)) {
      setFormError('Enter a valid MaterialCommunityIcons name');
      return;
    }
    const normalizedColor = normalizeHexColor(draft.color);
    if (draft.color.trim() && !normalizedColor) {
      setFormError('Choose a valid category color');
      return;
    }
    try {
      if (draft.mode === 'create') {
        await addCategory({
          name,
          kind: draft.kind,
          parentId: draft.parentId,
          icon: icon || undefined,
          color: normalizedColor ?? undefined,
        });
        setSnackbar(draft.parentId ? 'Subcategory added' : 'Category added');
      } else {
        await editCategory(draft.category.id, {
          name,
          kind: draft.kind,
          icon: icon || null,
          color: normalizedColor ?? null,
        });
        setSnackbar('Category updated');
      }
      setDraft(null);
      setFormError(null);
    } catch (error) {
      setFormError(error instanceof Error ? error.message : 'Could not save category');
    }
  };

  const toggleHidden = async (category: Category) => {
    setMenuCategoryId(null);
    await editCategory(category.id, { isHiddenInStats: !category.isHiddenInStats });
  };

  const toggleArchive = async (category: Category) => {
    setMenuCategoryId(null);
    await editCategory(category.id, { isArchived: !category.isArchived });
  };

  return (
    <>
      <AppScreen
        title="Categories"
        back={false}
        drawer
        actions={[
          { icon: 'cog-outline', label: 'Settings', onPress: () => router.push('/settings') },
        ]}
      >
        <Surface
          elevation={1}
          style={[
            styles.categoryCommandPanel,
            {
              backgroundColor: theme.colors.elevation.level1,
              borderColor: theme.colors.outlineVariant,
            },
          ]}
        >
          <PremiumSearchInput
            placeholder="Search categories"
            value={categoryQuery}
            onChangeText={setCategoryQuery}
            style={styles.categorySearch}
          />
          <View style={styles.controlRow}>
            <FilterPill
              label="Type"
              value={optionLabel(CATEGORY_KIND_OPTIONS, kind)}
              icon={kindOption?.icon ?? 'shape-outline'}
              onPress={() => setPicker('kind')}
            />
            <FilterPill
              label="View"
              value={showArchived ? 'All categories' : 'Active only'}
              icon={showArchived ? 'archive-outline' : 'eye-outline'}
              onPress={() => setPicker('archive')}
            />
          </View>
        </Surface>

        {draft ? (
          <CategoryEditorCard
            draft={draft}
            parentName={
              draft.mode === 'create' && draft.parentId
                ? categoryBreadcrumb(state.categories, draft.parentId)
                : draft.mode === 'edit' && draft.category.parentId
                  ? categoryBreadcrumb(state.categories, draft.category.parentId)
                  : undefined
            }
            categories={state.categories}
            canChangeKind={draft.mode === 'create' && !draft.parentId}
            formError={formError}
            onChange={setDraft}
            onCancel={() => setDraft(null)}
            onSave={() => void saveDraft()}
          />
        ) : null}

        <View style={styles.categoryPanel}>
          <View style={styles.categoryPanelHeader}>
            {currentParentId ? (
              <IconButton
                icon="arrow-left"
                mode="contained-tonal"
                size={20}
                accessibilityLabel="Back to parent category"
                onPress={goToParentCategory}
              />
            ) : null}
            <View style={styles.categoryPanelCopy}>
              <Text variant="titleLarge" numberOfLines={2} style={styles.categoryPanelTitle}>
                {levelTitle}
              </Text>
              <Text
                variant="bodySmall"
                numberOfLines={2}
                style={{ color: theme.colors.onSurfaceVariant }}
              >
                {levelSubtitle}
              </Text>
            </View>
            {currentParent ? (
              <IconButton
                icon="pencil-outline"
                mode="contained-tonal"
                size={20}
                accessibilityLabel="Edit category"
                onPress={() => startEdit(currentParent)}
              />
            ) : null}
            <IconButton
              icon="plus"
              mode="contained-tonal"
              size={20}
              accessibilityLabel={currentParent ? 'Add subcategory' : 'Add category'}
              onPress={() => startCreate(currentParent)}
            />
          </View>

          {levelCategories.length === 0 ? (
            <EmptyState
              icon="shape-outline"
              title={currentParent ? 'No subcategories here' : 'No categories here'}
              body={
                currentParent
                  ? `Add a subcategory for ${currentParent.name}.`
                  : 'Add a top-level category to start this list.'
              }
              actionLabel={currentParent ? 'Add subcategory' : 'Add category'}
              onAction={() => startCreate(currentParent)}
            />
          ) : filteredCategories.length === 0 ? (
            <EmptyState
              icon="magnify"
              title="No matching categories"
              body="Try another search or clear the search field."
              actionLabel="Clear search"
              onAction={() => setCategoryQuery('')}
            />
          ) : (
            <View style={styles.categoryGrid}>
              {filteredCategories.map((category) => {
                const childCount = categoryChildCount(state.categories, category.id, {
                  kind,
                  includeArchived: showArchived,
                });
                return (
                  <CategoryRow
                    key={category.id}
                    category={category}
                    categories={state.categories}
                    childCount={childCount}
                    style={categoryCardStyle}
                    onOpen={() => openCategory(category)}
                    onAddChild={() => startCreate(category)}
                    onEdit={() => startEdit(category)}
                    onToggleHidden={() => void toggleHidden(category)}
                    onToggleArchive={() => void toggleArchive(category)}
                    menuVisible={menuCategoryId === category.id}
                    onOpenMenu={() => setMenuCategoryId(category.id)}
                    onDismissMenu={() => setMenuCategoryId(null)}
                  />
                );
              })}
            </View>
          )}
        </View>
      </AppScreen>
      <OptionListOverlay
        visible={picker === 'kind'}
        title="Category type"
        options={CATEGORY_KIND_OPTIONS}
        selectedValue={kind}
        searchable={false}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          setKind(option.value);
          setCurrentParentId(undefined);
          setDraft(null);
          setPicker(null);
        }}
      />
      <OptionListOverlay
        visible={picker === 'archive'}
        title="Archive visibility"
        options={ARCHIVE_FILTER_OPTIONS}
        selectedValue={showArchived ? 'all' : 'active'}
        searchable={false}
        onDismiss={() => setPicker(null)}
        onSelect={(option) => {
          setShowArchived(option.value === 'all');
          setCurrentParentId(undefined);
          setPicker(null);
        }}
      />
      <Snackbar visible={Boolean(snackbar)} onDismiss={() => setSnackbar(null)} duration={2200}>
        {snackbar}
      </Snackbar>
    </>
  );
}

function CategoryEditorCard({
  draft,
  parentName,
  categories,
  canChangeKind,
  formError,
  onChange,
  onCancel,
  onSave,
}: {
  draft: CategoryDraft;
  parentName?: string;
  categories: Category[];
  canChangeKind: boolean;
  formError: string | null;
  onChange: (draft: CategoryDraft) => void;
  onCancel: () => void;
  onSave: () => void;
}) {
  const theme = useTheme();
  const [kindPickerVisible, setKindPickerVisible] = useState(false);
  const [iconPickerVisible, setIconPickerVisible] = useState(false);
  const [colorPickerVisible, setColorPickerVisible] = useState(false);
  const draftCategorySource = {
    id: draft.mode === 'edit' ? draft.category.id : 'draft',
    name: draft.name,
    kind: draft.kind,
    icon: draft.icon,
    parentId: draft.mode === 'create' ? draft.parentId : draft.category.parentId,
    color: draft.color || undefined,
  };
  const selectedIcon = resolveCategoryIcon(draftCategorySource, categories);
  const selectedVisual = resolveCategoryIconVisual(
    draftCategorySource,
    categories,
    DEFAULT_CATEGORY_COLOR,
  );
  const selectedIconLabel = categoryIconLabel(selectedIcon);
  const explicitColor = normalizeHexColor(draft.color);

  const changeName = (name: string) => {
    const nextIcon = shouldSuggestCategoryIcon(draft.icon)
      ? inferCategoryIcon(name, draft.kind, parentName ?? '')
      : draft.icon;
    onChange({ ...draft, name, icon: nextIcon });
  };

  const changeKind = (kind: CategoryKind) => {
    const nextIcon = shouldSuggestCategoryIcon(draft.icon)
      ? inferCategoryIcon(draft.name, kind, parentName ?? '')
      : draft.icon;
    onChange({ ...draft, kind, icon: nextIcon });
  };

  return (
    <>
      <Portal>
        <Surface
          elevation={0}
          style={[styles.editorOverlay, { backgroundColor: theme.colors.background }]}
        >
          <SafeAreaView style={styles.editorSafeArea} edges={['top', 'left', 'right']}>
            <Appbar.Header elevated={false} style={{ backgroundColor: theme.colors.background }}>
              <Appbar.BackAction onPress={onCancel} />
              <Appbar.Content
                title={
                  draft.mode === 'edit'
                    ? 'Edit category'
                    : parentName
                      ? 'Add subcategory'
                      : 'Add category'
                }
                titleStyle={styles.appbarTitle}
              />
              <Appbar.Action icon="check" accessibilityLabel="Save category" onPress={onSave} />
            </Appbar.Header>
            <ScrollView
              keyboardShouldPersistTaps="handled"
              contentContainerStyle={styles.editorContent}
              showsVerticalScrollIndicator={false}
            >
              <SectionCard title="Details">
                {parentName ? (
                  <Text
                    variant="bodySmall"
                    numberOfLines={2}
                    style={{ color: theme.colors.onSurfaceVariant }}
                  >
                    Parent: {parentName}
                  </Text>
                ) : null}
                {canChangeKind ? (
                  <OptionSelectorRow
                    label="Category type"
                    value={optionLabel(EDITABLE_CATEGORY_KIND_OPTIONS, draft.kind)}
                    description="Used for reports, Add Record, and import matching"
                    icon="shape-outline"
                    onPress={() => setKindPickerVisible(true)}
                  />
                ) : null}
                <PremiumTextInput
                  label="Name"
                  value={draft.name}
                  onChangeText={changeName}
                  left={<TextInput.Icon icon={selectedIcon} />}
                />
                <OptionSelectorRow
                  label="Icon"
                  value={selectedIconLabel}
                  description="Labeled symbols for pickers, reports, and records"
                  icon={selectedIcon}
                  iconBackgroundColor={selectedVisual.backgroundColor}
                  iconColor={selectedVisual.iconColor}
                  onPress={() => setIconPickerVisible(true)}
                />
                <OptionSelectorRow
                  label="Color"
                  value={
                    explicitColor
                      ? 'Selected color'
                      : parentName
                        ? 'Inherit color'
                        : 'Default color'
                  }
                  description="Icon accent"
                  icon={selectedIcon}
                  iconBackgroundColor={selectedVisual.backgroundColor}
                  iconColor={selectedVisual.iconColor}
                  onPress={() => setColorPickerVisible(true)}
                />
                <HelperText type="error" visible={Boolean(formError)}>
                  {formError ?? ' '}
                </HelperText>
                <View style={styles.formActions}>
                  <Button onPress={onCancel}>Cancel</Button>
                  <Button mode="contained" icon="check" onPress={onSave}>
                    Save
                  </Button>
                </View>
              </SectionCard>
            </ScrollView>
          </SafeAreaView>
        </Surface>
      </Portal>
      <OptionListOverlay
        visible={kindPickerVisible}
        title="Category type"
        options={EDITABLE_CATEGORY_KIND_OPTIONS}
        selectedValue={draft.kind}
        searchable={false}
        onDismiss={() => setKindPickerVisible(false)}
        onSelect={(option) => {
          changeKind(option.value);
          setKindPickerVisible(false);
        }}
      />
      <OptionListOverlay
        visible={iconPickerVisible}
        title="Category icon"
        options={CATEGORY_ICON_OPTIONS}
        selectedValue={selectedIcon}
        searchable
        onDismiss={() => setIconPickerVisible(false)}
        onSelect={(option) => {
          onChange({ ...draft, icon: option.value });
          setIconPickerVisible(false);
        }}
      />
      <ColorPickerOverlay
        visible={colorPickerVisible}
        title="Category color"
        selectedColor={explicitColor ?? selectedVisual.backgroundColor}
        fallbackColor={selectedVisual.backgroundColor}
        swatches={CATEGORY_COLOR_OPTIONS}
        saveLabel="Apply category color"
        allowClear
        clearLabel={parentName ? 'Use parent color' : 'Use default color'}
        accessibilityLabelPrefix="Category color"
        onDismiss={() => setColorPickerVisible(false)}
        onClear={() => {
          onChange({ ...draft, color: '' });
          setColorPickerVisible(false);
        }}
        onSave={(color) => {
          onChange({ ...draft, color });
          setColorPickerVisible(false);
        }}
        renderPreview={(color) => (
          <ColorPickerIconPreview
            color={color}
            icon={selectedIcon}
            title={draft.name.trim() || 'Category'}
            subtitle={
              parentName ? `Under ${parentName}` : optionLabel(CATEGORY_KIND_OPTIONS, draft.kind)
            }
          />
        )}
      />
    </>
  );
}

function optionLabel<TValue extends string>(
  options: readonly OptionListItem<TValue>[],
  value: TValue,
) {
  return options.find((option) => option.value === value)?.label ?? value;
}

function countLabel(count: number, singular: string, plural: string) {
  return `${count} ${count === 1 ? singular : plural}`;
}

function FilterPill({
  label,
  value,
  icon,
  onPress,
}: {
  label: string;
  value: string;
  icon: AppIconName;
  onPress: () => void;
}) {
  const theme = useTheme();
  const iconSurface = iconSurfaceForThemeTone(theme, 'category');
  return (
    <TouchableRipple
      style={[
        styles.filterPill,
        {
          backgroundColor: theme.colors.elevation.level1,
          borderColor: theme.colors.outlineVariant,
        },
      ]}
      borderless
      onPress={onPress}
    >
      <View style={styles.filterPillInner}>
        <View style={[styles.filterIcon, { backgroundColor: iconSurface.backgroundColor }]}>
          <MaterialCommunityIcons name={icon} size={18} color={iconSurface.iconColor} />
        </View>
        <View style={styles.filterCopy}>
          <Text variant="labelSmall" style={{ color: theme.colors.onSurfaceVariant }}>
            {label}
          </Text>
          <Text variant="titleSmall" numberOfLines={1} style={styles.filterValue}>
            {value}
          </Text>
        </View>
        <MaterialCommunityIcons
          name="chevron-down"
          size={18}
          color={theme.colors.onSurfaceVariant}
        />
      </View>
    </TouchableRipple>
  );
}

function CategoryRow({
  category,
  categories,
  childCount,
  style,
  onOpen,
  onAddChild,
  onEdit,
  onToggleHidden,
  onToggleArchive,
  menuVisible,
  onOpenMenu,
  onDismissMenu,
}: {
  category: Category;
  categories: Category[];
  childCount: number;
  style?: StyleProp<ViewStyle>;
  onOpen: () => void;
  onAddChild: () => void;
  onEdit: () => void;
  onToggleHidden: () => void;
  onToggleArchive: () => void;
  menuVisible: boolean;
  onOpenMenu: () => void;
  onDismissMenu: () => void;
}) {
  const theme = useTheme();
  const childLabel = countLabel(childCount, 'subcategory', 'subcategories');
  const visual = resolveCategoryIconVisual(category, categories);
  return (
    <Surface
      elevation={0}
      style={[
        styles.categoryCard,
        style,
        {
          backgroundColor: theme.colors.elevation.level1,
          borderColor: theme.colors.outlineVariant,
          opacity: category.isArchived ? 0.62 : 1,
        },
      ]}
    >
      <TouchableRipple onPress={onOpen} style={styles.categoryMain} borderless>
        <View style={styles.categoryCardInner}>
          <View style={styles.categoryCardTopRow}>
            <View style={[styles.categoryIcon, { backgroundColor: visual.backgroundColor }]}>
              <MaterialCommunityIcons name={visual.icon} size={24} color={visual.iconColor} />
            </View>
            <View style={styles.categoryCopy}>
              <Text variant="titleSmall" numberOfLines={2} style={styles.categoryName}>
                {category.name}
              </Text>
              <Text
                variant="bodySmall"
                numberOfLines={1}
                style={{ color: theme.colors.onSurfaceVariant }}
              >
                {childLabel}
              </Text>
            </View>
          </View>
          {category.isArchived || category.isHiddenInStats ? (
            <InlineMeta
              items={[
                category.isArchived ? 'Archived' : null,
                category.isHiddenInStats ? 'Hidden' : null,
              ]}
            />
          ) : null}
          <View style={styles.categoryCardFooter}>
            <Text
              variant="labelSmall"
              numberOfLines={1}
              style={{ color: theme.colors.onSurfaceVariant }}
            >
              {visual.iconLabel} icon
            </Text>
            <MaterialCommunityIcons
              name="chevron-right"
              size={18}
              color={theme.colors.onSurfaceVariant}
            />
          </View>
        </View>
      </TouchableRipple>
      <Menu
        visible={menuVisible}
        onDismiss={onDismissMenu}
        anchor={
          <IconButton
            icon="dots-vertical"
            size={20}
            style={styles.categoryMenuButton}
            onPress={onOpenMenu}
          />
        }
      >
        <Menu.Item
          leadingIcon="pencil-outline"
          title="Edit"
          onPress={() => {
            onDismissMenu();
            onEdit();
          }}
        />
        <Menu.Item
          leadingIcon="plus"
          title="Add subcategory"
          onPress={() => {
            onDismissMenu();
            onAddChild();
          }}
        />
        <Menu.Item
          leadingIcon={category.isHiddenInStats ? 'eye-outline' : 'eye-off-outline'}
          title={category.isHiddenInStats ? 'Show in stats' : 'Hide in stats'}
          onPress={() => {
            onDismissMenu();
            onToggleHidden();
          }}
        />
        <Menu.Item
          leadingIcon={category.isArchived ? 'archive-arrow-up-outline' : 'archive-outline'}
          title={category.isArchived ? 'Restore' : 'Archive'}
          onPress={() => {
            onDismissMenu();
            onToggleArchive();
          }}
        />
      </Menu>
      <IconButton
        icon="pencil-outline"
        size={18}
        style={styles.categoryEditButton}
        accessibilityLabel={`Edit ${category.name}`}
        onPress={onEdit}
      />
    </Surface>
  );
}

const styles = StyleSheet.create({
  appbarTitle: { fontWeight: '700' },
  editorOverlay: { ...StyleSheet.absoluteFill, zIndex: 10 },
  editorSafeArea: { flex: 1 },
  editorContent: {
    gap: tokens.space.md,
    padding: tokens.space.lg,
    paddingTop: 0,
    paddingBottom: 32,
  },
  categoryCommandPanel: {
    borderRadius: tokens.radius.lg,
    borderWidth: StyleSheet.hairlineWidth,
    padding: tokens.space.md,
    gap: tokens.space.sm,
  },
  categorySearch: { borderRadius: tokens.radius.lg, elevation: 0 },
  controlRow: { flexDirection: 'row', gap: 8 },
  filterPill: {
    flex: 1,
    borderRadius: tokens.radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  filterPillInner: {
    minHeight: 52,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 10,
    paddingVertical: 8,
  },
  filterIcon: {
    width: 32,
    height: 32,
    borderRadius: tokens.radius.pill,
    alignItems: 'center',
    justifyContent: 'center',
  },
  filterCopy: { flex: 1, minWidth: 0, gap: 2 },
  filterValue: { fontWeight: '800' },
  categoryPanel: { gap: tokens.space.md },
  categoryPanelHeader: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 8,
  },
  categoryPanelCopy: { flex: 1, minWidth: 0 },
  categoryPanelTitle: { fontWeight: '800' },
  categoryGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: tokens.space.sm },
  formActions: { flexDirection: 'row', justifyContent: 'flex-end', gap: 8 },
  categoryCard: {
    minHeight: 168,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: tokens.radius.lg,
    overflow: 'hidden',
    position: 'relative',
  },
  categoryMain: { flex: 1, alignSelf: 'stretch' },
  categoryCardInner: {
    flex: 1,
    justifyContent: 'space-between',
    gap: tokens.space.sm,
    padding: tokens.space.md,
    paddingRight: 44,
  },
  categoryCardTopRow: {
    flexDirection: 'column',
    alignItems: 'flex-start',
    gap: tokens.space.sm,
  },
  categoryIcon: {
    width: 44,
    height: 44,
    borderRadius: tokens.radius.pill,
    alignItems: 'center',
    justifyContent: 'center',
  },
  categoryCopy: { alignSelf: 'stretch', flex: 1, minWidth: 0, gap: 4 },
  categoryName: { fontWeight: '800', lineHeight: 18, minHeight: 36 },
  categoryCardFooter: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: tokens.space.sm,
  },
  categoryMenuButton: { position: 'absolute', top: 4, right: 4 },
  categoryEditButton: { position: 'absolute', right: 4, bottom: 4 },
});
