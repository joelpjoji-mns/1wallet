import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { StyleSheet, View } from 'react-native';
import { Text, TouchableRipple, useTheme } from 'react-native-paper';

export function ReviewQueueButton({
  count,
  hasWarnings,
  onPress,
}: {
  count: number;
  hasWarnings?: boolean;
  onPress: () => void;
}) {
  const theme = useTheme();
  const label = count > 99 ? '99+' : String(count);

  return (
    <TouchableRipple
      borderless
      onPress={onPress}
      accessibilityRole="button"
      accessibilityLabel="Open review queue"
      style={styles.button}
    >
      <View style={styles.inner}>
        <MaterialCommunityIcons
          name={hasWarnings ? 'robot-confused-outline' : 'robot-outline'}
          size={25}
          color={count > 0 ? theme.colors.primary : theme.colors.onSurfaceVariant}
        />
        {count > 0 ? (
          <View style={[styles.badge, { backgroundColor: theme.colors.error }]}>
            <Text variant="labelSmall" style={[styles.badgeText, { color: theme.colors.onError }]}>
              {label}
            </Text>
          </View>
        ) : null}
      </View>
    </TouchableRipple>
  );
}

const styles = StyleSheet.create({
  button: {
    width: 44,
    height: 44,
    borderRadius: tokens.radius.pill,
    overflow: 'hidden',
  },
  inner: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  badge: {
    position: 'absolute',
    top: 4,
    right: 4,
    minWidth: 18,
    height: 18,
    borderRadius: 9,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 4,
  },
  badgeText: { fontWeight: '800', includeFontPadding: false },
});
