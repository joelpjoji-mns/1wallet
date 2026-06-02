import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { useMemo } from 'react';
import { StyleSheet, View } from 'react-native';
import { Text, useTheme } from 'react-native-paper';
import { ACCENT_COLOR_SWATCHES } from '../colorPalettes';
import { createMaterial3Theme } from '../material3Theme';
import { createAppPaperTheme, DEFAULT_CUSTOM_ACCENT_COLOR } from '../theme';
import { ColorPickerOverlay } from './ColorPickerOverlay';

export function ThemeAccentPicker({
  visible,
  initialColor,
  onDismiss,
  onSave,
}: {
  visible: boolean;
  initialColor?: string;
  onDismiss: () => void;
  onSave: (color: string) => void;
}) {
  return (
    <ColorPickerOverlay
      visible={visible}
      title="Custom accent"
      selectedColor={initialColor ?? DEFAULT_CUSTOM_ACCENT_COLOR}
      fallbackColor={DEFAULT_CUSTOM_ACCENT_COLOR}
      swatches={ACCENT_COLOR_SWATCHES}
      saveLabel="Apply accent"
      accessibilityLabelPrefix="Accent"
      onDismiss={onDismiss}
      onSave={onSave}
      renderPreview={(color) => <ThemeAccentPreview color={color} />}
    />
  );
}

function ThemeAccentPreview({ color }: { color: string }) {
  const theme = useTheme();
  const previewColors = useMemo(
    () =>
      createAppPaperTheme(
        theme.dark ? 'dark' : 'light',
        createMaterial3Theme(color, { colorFidelity: true }),
        { customAccentColor: color },
      ).colors,
    [color, theme.dark],
  );

  return (
    <View
      style={[
        styles.previewPanel,
        {
          backgroundColor: previewColors.elevation.level1,
          borderColor: previewColors.outlineVariant,
        },
      ]}
    >
      <View style={[styles.previewHero, { backgroundColor: previewColors.primaryContainer }]}>
        <View style={[styles.previewAvatar, { backgroundColor: previewColors.primary }]}>
          <Text variant="titleSmall" style={{ color: previewColors.onPrimary }}>
            Q
          </Text>
        </View>
        <View style={styles.previewCopy}>
          <Text variant="titleMedium" style={{ color: previewColors.onPrimaryContainer }}>
            My Wallet
          </Text>
          <Text variant="bodySmall" style={{ color: previewColors.onPrimaryContainer }}>
            Drawer accent
          </Text>
        </View>
      </View>

      <View style={[styles.previewRow, { backgroundColor: previewColors.primaryContainer }]}>
        <View style={[styles.previewIcon, { backgroundColor: previewColors.primary }]}>
          <MaterialCommunityIcons
            name="view-dashboard-outline"
            size={18}
            color={previewColors.onPrimary}
          />
        </View>
        <Text variant="bodyLarge" style={{ color: previewColors.onPrimaryContainer }}>
          Home
        </Text>
      </View>

      <View style={styles.previewTagRow}>
        <View
          style={[
            styles.previewTag,
            {
              backgroundColor: previewColors.primaryContainer,
              borderColor: previewColors.primary,
            },
          ]}
        >
          <MaterialCommunityIcons name="filter-variant" size={16} color={previewColors.primary} />
          <Text variant="labelLarge" style={{ color: previewColors.onPrimaryContainer }}>
            Filter
          </Text>
        </View>
        <View style={[styles.previewDot, { backgroundColor: previewColors.primary }]} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  previewPanel: {
    gap: tokens.space.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: tokens.radius.lg,
    padding: tokens.space.md,
  },
  previewHero: {
    minHeight: 82,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.md,
    borderRadius: tokens.radius.md,
    padding: tokens.space.md,
  },
  previewAvatar: {
    width: 44,
    height: 44,
    borderRadius: tokens.radius.pill,
    alignItems: 'center',
    justifyContent: 'center',
  },
  previewCopy: { flex: 1, minWidth: 0 },
  previewRow: {
    minHeight: 54,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.md,
    borderRadius: tokens.radius.md,
    paddingHorizontal: tokens.space.md,
  },
  previewIcon: {
    width: 34,
    height: 34,
    borderRadius: tokens.radius.pill,
    alignItems: 'center',
    justifyContent: 'center',
  },
  previewTagRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: tokens.space.md,
  },
  previewTag: {
    minHeight: 38,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.sm,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: tokens.radius.pill,
    paddingHorizontal: tokens.space.md,
  },
  previewDot: {
    width: 28,
    height: 28,
    borderRadius: tokens.radius.pill,
  },
});
