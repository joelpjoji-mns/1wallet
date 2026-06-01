import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { StyleSheet, View, type StyleProp, type ViewStyle } from 'react-native';
import { Text, TouchableRipple, useTheme } from 'react-native-paper';
import { IconBubble, premiumFieldColors, type AppIconName } from '../AppKit';

export function RecordSelectorRow({
  label,
  value,
  supporting,
  icon,
  iconBackgroundColor,
  iconColor,
  valueNumberOfLines = 1,
  compact = false,
  style,
  onPress,
}: {
  label: string;
  value: string;
  supporting?: string;
  icon: AppIconName;
  iconBackgroundColor?: string;
  iconColor?: string;
  valueNumberOfLines?: number;
  compact?: boolean;
  style?: StyleProp<ViewStyle>;
  onPress: () => void;
}) {
  const theme = useTheme();
  const fieldColors = premiumFieldColors(theme);

  return (
    <TouchableRipple
      onPress={onPress}
      borderless
      style={[
        styles.selectorRow,
        {
          backgroundColor: fieldColors.background,
          borderColor: fieldColors.border,
        },
        style,
      ]}
    >
      <View style={[styles.selectorRowInner, compact && styles.selectorRowInnerCompact]}>
        <IconBubble
          icon={icon}
          tone="primary"
          size={compact ? 36 : 40}
          backgroundColor={iconBackgroundColor}
          iconColor={iconColor}
        />
        <View style={styles.selectorCopy}>
          <Text variant="labelMedium" style={{ color: theme.colors.onSurfaceVariant }}>
            {label}
          </Text>
          <Text
            variant="titleSmall"
            numberOfLines={valueNumberOfLines}
            style={[styles.selectorValue, { color: theme.colors.onSurface }]}
          >
            {value}
          </Text>
          {supporting ? (
            <Text
              variant="bodySmall"
              numberOfLines={1}
              style={{ color: theme.colors.onSurfaceVariant }}
            >
              {supporting}
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
  selectorRow: {
    flex: 1,
    minHeight: tokens.size.rowLarge,
    borderRadius: tokens.radius.lg,
    borderWidth: 1,
    overflow: 'hidden',
  },
  selectorRowInner: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.md,
    paddingHorizontal: tokens.space.md,
    paddingVertical: tokens.space.sm,
  },
  selectorRowInnerCompact: {
    gap: tokens.space.sm,
    paddingHorizontal: tokens.space.sm,
    paddingVertical: tokens.space.xs,
  },
  selectorCopy: { flex: 1, minWidth: 0, gap: 1 },
  selectorValue: { fontWeight: '800' },
});
