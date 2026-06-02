import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { useCallback, useEffect, useMemo, useState } from 'react';
import {
    FlatList,
    Modal,
    Platform,
    StyleSheet,
    View,
    type ListRenderItem,
    type ViewStyle,
} from 'react-native';
import { Appbar, Surface, Text, TouchableRipple, useTheme } from 'react-native-paper';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useBackLayer } from './AppBackLayer';
import {
    IconBubble,
    PremiumRow,
    PremiumSearchInput,
    premiumFieldColors,
    resolveAppIconName,
    type AppIconName,
} from './AppKit';

export type OptionListItem<TValue extends string = string> = {
  value: TValue;
  label: string;
  description?: string;
  icon?: AppIconName;
  iconBackgroundColor?: string;
  iconColor?: string;
  disabled?: boolean;
};

export function OptionListOverlay<TValue extends string>({
  visible,
  title,
  options,
  selectedValue,
  searchPlaceholder = 'Search',
  emptyText = 'No options found',
  searchable = options.length > 8,
  onDismiss,
  onSelect,
}: {
  visible: boolean;
  title: string;
  options: readonly OptionListItem<TValue>[];
  selectedValue?: TValue;
  searchPlaceholder?: string;
  emptyText?: string;
  searchable?: boolean;
  onDismiss: () => void;
  onSelect: (option: OptionListItem<TValue>) => void;
}) {
  const theme = useTheme();
  const [query, setQuery] = useState('');

  useBackLayer(visible, onDismiss);

  useEffect(() => {
    if (!visible) setQuery('');
  }, [visible]);

  const filtered = useMemo(() => {
    const normalized = query.trim().toLowerCase();
    if (!normalized) return options;
    return options.filter((option) =>
      [option.label, option.description ?? '', option.value]
        .join(' ')
        .toLowerCase()
        .includes(normalized),
    );
  }, [options, query]);

  const keyExtractor = useCallback((option: OptionListItem<TValue>) => option.value, []);
  const renderOption = useCallback<ListRenderItem<OptionListItem<TValue>>>(
    ({ item: option }) => (
      <PremiumRow
        icon={resolveAppIconName(option.icon, 'format-list-bulleted')}
        title={option.label}
        subtitle={option.description}
        iconBackgroundColor={option.iconBackgroundColor}
        iconColor={option.iconColor}
        titleNumberOfLines={2}
        selected={selectedValue === option.value}
        disabled={option.disabled}
        onPress={() => onSelect(option)}
      />
    ),
    [onSelect, selectedValue],
  );
  const emptyState = useMemo(
    () => (
      <View style={styles.emptyState}>
        <MaterialCommunityIcons
          name="text-search"
          size={28}
          color={theme.colors.onSurfaceVariant}
        />
        <Text variant="bodyMedium" style={{ color: theme.colors.onSurfaceVariant }}>
          {emptyText}
        </Text>
      </View>
    ),
    [emptyText, theme.colors.onSurfaceVariant],
  );

  if (!visible) return null;

  return (
    <Modal visible animationType="fade" presentationStyle="fullScreen" onRequestClose={onDismiss}>
      <Surface
        style={[styles.fullScreenOverlay, { backgroundColor: theme.colors.background }]}
        elevation={0}
      >
        <SafeAreaView style={styles.safeArea} edges={['top', 'left', 'right']}>
          <Appbar.Header elevated={false} style={{ backgroundColor: theme.colors.background }}>
            <Appbar.BackAction onPress={onDismiss} />
            <Appbar.Content title={title} titleStyle={styles.appbarTitle} />
          </Appbar.Header>
          <View style={styles.content}>
            {searchable ? (
              <PremiumSearchInput
                placeholder={searchPlaceholder}
                value={query}
                onChangeText={setQuery}
              />
            ) : null}
            <FlatList
              data={filtered}
              keyExtractor={keyExtractor}
              renderItem={renderOption}
              ListEmptyComponent={emptyState}
              contentContainerStyle={styles.optionListContent}
              initialNumToRender={18}
              keyboardShouldPersistTaps="handled"
              maxToRenderPerBatch={16}
              removeClippedSubviews={Platform.OS === 'android'}
              showsVerticalScrollIndicator={false}
              updateCellsBatchingPeriod={32}
              windowSize={8}
            />
          </View>
        </SafeAreaView>
      </Surface>
    </Modal>
  );
}

export function OptionSelectorRow({
  label,
  value,
  description,
  icon = 'format-list-bulleted',
  iconBackgroundColor,
  iconColor,
  valueNumberOfLines = 1,
  compact = false,
  disabled = false,
  style,
  onPress,
}: {
  label: string;
  value: string;
  description?: string;
  icon?: AppIconName;
  iconBackgroundColor?: string;
  iconColor?: string;
  valueNumberOfLines?: number;
  compact?: boolean;
  disabled?: boolean;
  style?: ViewStyle;
  onPress: () => void;
}) {
  const theme = useTheme();
  const fieldColors = premiumFieldColors(theme, { disabled });

  return (
    <TouchableRipple
      disabled={disabled}
      style={[
        styles.selectorField,
        { backgroundColor: fieldColors.background, borderColor: fieldColors.border },
        disabled && { opacity: 0.5 },
        style,
      ]}
      onPress={onPress}
      borderless
    >
      <View style={[styles.selectorInner, compact && styles.selectorInnerCompact]}>
        <IconBubble
          icon={icon}
          tone="secondary"
          size={compact ? 36 : 40}
          backgroundColor={iconBackgroundColor}
          iconColor={iconColor}
        />
        <View style={styles.copy}>
          <Text variant="labelLarge" style={{ color: theme.colors.onSurfaceVariant }}>
            {label}
          </Text>
          <Text variant="titleMedium" numberOfLines={valueNumberOfLines}>
            {value}
          </Text>
          {description ? (
            <Text
              variant="bodySmall"
              numberOfLines={1}
              style={{ color: theme.colors.onSurfaceVariant }}
            >
              {description}
            </Text>
          ) : null}
        </View>
        <MaterialCommunityIcons
          name="chevron-right"
          size={tokens.icon.lg}
          color={theme.colors.onSurfaceVariant}
        />
      </View>
    </TouchableRipple>
  );
}

const styles = StyleSheet.create({
  fullScreenOverlay: {
    ...StyleSheet.absoluteFill,
    zIndex: 20,
  },
  safeArea: { flex: 1 },
  appbarTitle: { fontWeight: '700' },
  content: { flex: 1, gap: tokens.space.md, padding: tokens.space.lg, paddingTop: 0 },
  optionListContent: { flexGrow: 1, gap: tokens.space.sm, paddingBottom: tokens.space.lg },
  copy: { flex: 1, minWidth: 0, gap: 2 },
  emptyState: {
    minHeight: 180,
    alignItems: 'center',
    justifyContent: 'center',
    gap: tokens.space.sm,
  },
  selectorField: {
    borderWidth: 1,
    borderRadius: tokens.radius.lg,
    overflow: 'hidden',
  },
  selectorInner: {
    minHeight: tokens.size.rowLarge,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.md,
    paddingHorizontal: tokens.space.md,
    paddingVertical: tokens.space.sm,
  },
  selectorInnerCompact: {
    minHeight: 56,
    gap: tokens.space.sm,
    paddingHorizontal: tokens.space.sm,
    paddingVertical: 6,
  },
});
