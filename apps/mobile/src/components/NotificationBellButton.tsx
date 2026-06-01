import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { StyleSheet, View } from 'react-native';
import { Text, TouchableRipple, useTheme } from 'react-native-paper';

export function NotificationBellButton({ count, onPress }: { count: number; onPress: () => void }) {
  const theme = useTheme();
  const label = count > 99 ? '99+' : String(count);

  return (
    <TouchableRipple
      borderless
      onPress={onPress}
      accessibilityRole="button"
      accessibilityLabel="Open notifications"
      style={styles.button}
    >
      <View style={styles.inner}>
        <MaterialCommunityIcons
          name={count > 0 ? 'bell-badge-outline' : 'bell-outline'}
          size={25}
          color={theme.colors.onSurfaceVariant}
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
