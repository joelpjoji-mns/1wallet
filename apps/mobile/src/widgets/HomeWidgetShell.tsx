import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import type { ReactNode } from 'react';
import { createContext, useContext, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { Button, Menu, Surface, Text, TouchableRipple, useTheme } from 'react-native-paper';
import type { AppIconName } from '../components/AppKit';
import { iconSurfaceForThemeTone, type IconSurfaceTone } from '../iconSystem';
import {
    HOME_WIDGET_DATE_LABELS,
    HOME_WIDGET_DATE_PRESETS,
    type HomeWidgetDatePreset,
    type HomeWidgetSize,
} from './homeWidgetTypes';

export const HOME_WIDGET_REORDER_LONG_PRESS_DELAY_MS = 520;
const HomeWidgetReorderContext = createContext<(() => void) | undefined>(undefined);

export function HomeWidgetReorderProvider({
  children,
  onLongPress,
}: {
  children: ReactNode;
  onLongPress?: () => void;
}) {
  return (
    <HomeWidgetReorderContext.Provider value={onLongPress}>
      {children}
    </HomeWidgetReorderContext.Provider>
  );
}

export function useHomeWidgetReorderLongPress() {
  return useContext(HomeWidgetReorderContext);
}

export type WidgetDropdownItem<TValue extends string = string> = {
  value: TValue;
  label: string;
  icon?: AppIconName;
  disabled?: boolean;
};

export function HomeWidgetShell({
  title,
  subtitle,
  icon,
  iconTone = 'widget',
  size,
  actionLabel,
  onAction,
  datePreset,
  onDatePresetChange,
  datePresets,
  onTouchStart,
  children,
}: {
  title: string;
  subtitle?: string;
  icon: AppIconName;
  iconTone?: IconSurfaceTone;
  size: HomeWidgetSize;
  actionLabel?: string;
  onAction?: () => void;
  datePreset?: HomeWidgetDatePreset;
  onDatePresetChange?: (preset: HomeWidgetDatePreset) => void;
  datePresets?: HomeWidgetDatePreset[];
  onTouchStart?: () => void;
  children: ReactNode;
}) {
  const theme = useTheme();
  const onReorderLongPress = useHomeWidgetReorderLongPress();
  const headerIconSurface = iconSurfaceForThemeTone(theme, iconTone);

  return (
    <Surface
      elevation={1}
      style={[
        styles.shell,
        size === 'compact' && styles.compactShell,
        size === 'wide' && styles.wideShell,
        {
          backgroundColor: theme.colors.elevation.level1,
          borderColor: theme.colors.outlineVariant,
        },
      ]}
      onTouchStart={onTouchStart}
    >
      <View style={styles.header}>
        <View style={[styles.iconWrap, { backgroundColor: headerIconSurface.backgroundColor }]}>
          <MaterialCommunityIcons name={icon} size={20} color={headerIconSurface.iconColor} />
        </View>
        <TitlePressArea onLongPress={onReorderLongPress}>
          <Text variant="titleMedium" numberOfLines={1} style={styles.title}>
            {title}
          </Text>
          {subtitle ? (
            <Text
              variant="bodySmall"
              numberOfLines={2}
              style={{ color: theme.colors.onSurfaceVariant }}
            >
              {subtitle}
            </Text>
          ) : null}
        </TitlePressArea>
        <View style={styles.headerActions}>
          {datePreset && onDatePresetChange ? (
            <WidgetDateFilterButton
              value={datePreset}
              onChange={onDatePresetChange}
              presets={datePresets}
            />
          ) : null}
          {actionLabel && onAction ? (
            <Button compact mode="text" onPress={onAction}>
              {actionLabel}
            </Button>
          ) : null}
        </View>
      </View>
      {children}
    </Surface>
  );
}

function TitlePressArea({
  children,
  onLongPress,
}: {
  children: ReactNode;
  onLongPress?: () => void;
}) {
  if (!onLongPress) return <View style={styles.copy}>{children}</View>;
  return (
    <Pressable
      onLongPress={onLongPress}
      delayLongPress={HOME_WIDGET_REORDER_LONG_PRESS_DELAY_MS}
      hitSlop={6}
      style={styles.copy}
    >
      {children}
    </Pressable>
  );
}

export function WidgetDateFilterButton({
  value,
  onChange,
  presets = HOME_WIDGET_DATE_PRESETS,
  buttonLabel,
  menuWidth = 176,
}: {
  value: HomeWidgetDatePreset;
  onChange: (preset: HomeWidgetDatePreset) => void;
  presets?: HomeWidgetDatePreset[];
  buttonLabel?: string;
  menuWidth?: number;
}) {
  return (
    <WidgetDropdownButton
      value={value}
      label={buttonLabel ?? HOME_WIDGET_DATE_LABELS[value]}
      icon="calendar-range"
      items={presets.map((preset) => ({
        value: preset,
        label: HOME_WIDGET_DATE_LABELS[preset],
        icon: preset === value ? 'calendar-check-outline' : 'calendar-blank-outline',
      }))}
      onSelect={onChange}
      menuWidth={menuWidth}
    />
  );
}

export function WidgetDropdownButton<TValue extends string>({
  value,
  label,
  icon,
  items,
  menuWidth = 172,
  onSelect,
}: {
  value: TValue;
  label: string;
  icon: AppIconName;
  items: readonly WidgetDropdownItem<TValue>[];
  menuWidth?: number;
  onSelect: (value: TValue) => void;
}) {
  const theme = useTheme();
  const [visible, setVisible] = useState(false);

  return (
    <Menu
      visible={visible}
      onDismiss={() => setVisible(false)}
      contentStyle={[
        styles.dropdownMenuContent,
        {
          minWidth: menuWidth,
          backgroundColor: theme.colors.elevation.level3,
          borderColor: theme.colors.outlineVariant,
        },
      ]}
      anchor={
        <TouchableRipple
          onPress={() => setVisible(true)}
          borderless
          style={[
            styles.dropdownButton,
            {
              backgroundColor: theme.colors.secondaryContainer,
              borderColor: theme.colors.outlineVariant,
            },
          ]}
        >
          <View style={styles.dropdownButtonContent}>
            <MaterialCommunityIcons
              name={icon}
              size={14}
              color={theme.colors.onSecondaryContainer}
            />
            <Text
              variant="labelMedium"
              numberOfLines={1}
              style={[styles.dropdownButtonLabel, { color: theme.colors.onSecondaryContainer }]}
            >
              {label}
            </Text>
          </View>
        </TouchableRipple>
      }
    >
      <ScrollView
        style={styles.dropdownMenuScroll}
        contentContainerStyle={styles.dropdownMenuScrollContent}
        keyboardShouldPersistTaps="handled"
        showsVerticalScrollIndicator={false}
      >
        {items.map((item) => {
          const selected = item.value === value;
          return (
            <Menu.Item
              key={item.value}
              leadingIcon={item.icon}
              trailingIcon={selected ? 'check-circle' : undefined}
              title={item.label}
              disabled={item.disabled}
              style={[
                styles.dropdownMenuItem,
                selected && { backgroundColor: theme.colors.primaryContainer },
              ]}
              titleStyle={[
                styles.dropdownMenuItemTitle,
                { color: selected ? theme.colors.onPrimaryContainer : theme.colors.onSurface },
              ]}
              onPress={() => {
                if (item.disabled) return;
                onSelect(item.value);
                setVisible(false);
              }}
            />
          );
        })}
      </ScrollView>
    </Menu>
  );
}

export function WidgetEmpty({ text }: { text: string }) {
  const theme = useTheme();

  return (
    <Text variant="bodyMedium" style={[styles.empty, { color: theme.colors.onSurfaceVariant }]}>
      {text}
    </Text>
  );
}

const styles = StyleSheet.create({
  shell: {
    borderRadius: tokens.radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    padding: tokens.space.md,
    gap: tokens.space.md,
  },
  compactShell: { padding: tokens.space.sm, gap: tokens.space.sm },
  wideShell: { padding: tokens.space.md, gap: tokens.space.md },
  header: { flexDirection: 'row', alignItems: 'flex-start', gap: tokens.space.sm },
  headerActions: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'flex-end',
    flexShrink: 0,
    flexWrap: 'wrap',
    gap: tokens.space.sm,
  },
  iconWrap: {
    width: 36,
    height: 36,
    borderRadius: tokens.radius.md,
    alignItems: 'center',
    justifyContent: 'center',
  },
  copy: { flex: 1, minWidth: 0 },
  title: { fontWeight: '700' },
  empty: { paddingVertical: tokens.space.sm },
  dropdownButton: {
    borderRadius: tokens.radius.pill,
    borderWidth: StyleSheet.hairlineWidth,
    height: 30,
    minWidth: 0,
    overflow: 'hidden',
  },
  dropdownButtonContent: {
    height: 30,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 4,
    paddingHorizontal: 8,
  },
  dropdownButtonLabel: { fontSize: 12, lineHeight: 15, fontWeight: '800', letterSpacing: 0 },
  dropdownMenuContent: {
    borderRadius: tokens.radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    paddingVertical: 2,
    overflow: 'hidden',
  },
  dropdownMenuScroll: { maxHeight: 260 },
  dropdownMenuScrollContent: { paddingHorizontal: tokens.space.xs, gap: 2 },
  dropdownMenuItem: { borderRadius: tokens.radius.sm, minHeight: 36 },
  dropdownMenuItemTitle: { fontSize: 12, fontWeight: '700', letterSpacing: 0 },
});
