import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { router } from 'expo-router';
import { useCallback, useMemo, useRef } from 'react';
import { Animated, PanResponder, StyleSheet, View, useWindowDimensions } from 'react-native';
import {
    Divider,
    Surface,
    Text,
    TouchableRipple,
    useTheme,
    type MD3Theme,
} from 'react-native-paper';
import { AppScreen, EmptyState, InlineMeta, SectionCard } from '../src/components/AppKit';
import { ROW_DISMISS_GESTURE } from '../src/gestureDefaults';
import { APP_ICONS, iconSurfaceForThemeTone, type IconSurfaceTone } from '../src/iconSystem';
import {
    buildNotificationInbox,
    dismissAllNotifications,
    dismissNotification,
    markAllNotificationsRead,
    markNotificationRead,
    normalizeNotificationPreferences,
    notificationChannelLabel,
    type AppNotification,
    type AppNotificationSeverity,
} from '../src/notifications';

export default function Notifications() {
  const { state, mutate } = useLedger();
  const settings = normalizeNotificationPreferences(state.preferences.notifications);
  const notifications = useMemo(() => buildNotificationInbox(state), [state]);
  const unreadCount = useMemo(
    () => notifications.filter((notification) => !notification.read).length,
    [notifications],
  );

  const markAllRead = async () => {
    await mutate((draft) => markAllNotificationsRead(draft, notifications), {
      slices: ['preferences'],
    });
  };

  const dismissAll = async () => {
    await mutate((draft) => dismissAllNotifications(draft, notifications), {
      slices: ['preferences'],
    });
  };

  const dismiss = async (notification: AppNotification) => {
    await mutate((draft) => dismissNotification(draft, notification.id), {
      slices: ['preferences'],
    });
  };

  const openNotification = async (notification: AppNotification) => {
    await mutate((draft) => markNotificationRead(draft, notification.id, true), {
      slices: ['preferences'],
    });
    openTarget(notification);
  };

  return (
    <AppScreen
      title="Notifications"
      back={false}
      drawer
      actions={
        unreadCount
          ? [
              {
                icon: APP_ICONS.action.markAllRead,
                label: 'Mark all read',
                onPress: () => void markAllRead(),
              },
            ]
          : []
      }
    >
      <SectionCard
        title="Inbox"
        subtitle={`${notifications.length} active item${notifications.length === 1 ? '' : 's'}`}
        actionLabel={notifications.length ? 'Dismiss all' : undefined}
        actionIcon={APP_ICONS.status.archive}
        onAction={notifications.length ? () => void dismissAll() : undefined}
      >
        {notifications.length === 0 ? (
          <EmptyState
            icon="bell-check-outline"
            title={settings.enabled ? 'Nothing waiting' : 'Notifications paused'}
            body={
              settings.enabled
                ? 'No finance alerts right now.'
                : 'Notification settings are available in Settings.'
            }
          />
        ) : (
          notifications.map((notification, index) => (
            <View key={notification.id}>
              <NotificationRow
                notification={notification}
                onOpen={() => void openNotification(notification)}
                onDismiss={() => void dismiss(notification)}
              />
              {index < notifications.length - 1 ? <Divider /> : null}
            </View>
          ))
        )}
      </SectionCard>
    </AppScreen>
  );
}

function NotificationRow({
  notification,
  onOpen,
  onDismiss,
}: {
  notification: AppNotification;
  onOpen: () => void;
  onDismiss: () => void;
}) {
  const theme = useTheme();
  const { width } = useWindowDimensions();
  const translateX = useRef(new Animated.Value(0)).current;
  const severityColor = colorForSeverity(notification.severity, theme.colors);
  const iconSurface = iconSurfaceForThemeTone(theme, iconToneForSeverity(notification.severity));
  const dismissOpacity = translateX.interpolate({
    inputRange: [-ROW_DISMISS_GESTURE.distance, 0, ROW_DISMISS_GESTURE.distance],
    outputRange: [1, 0, 1],
    extrapolate: 'clamp',
  });

  const resetPosition = useCallback(() => {
    Animated.spring(translateX, {
      toValue: 0,
      damping: ROW_DISMISS_GESTURE.spring.damping,
      stiffness: ROW_DISMISS_GESTURE.spring.stiffness,
      mass: ROW_DISMISS_GESTURE.spring.mass,
      useNativeDriver: true,
    }).start();
  }, [translateX]);

  const dismissFromSwipe = useCallback(
    (distance: number) => {
      Animated.timing(translateX, {
        toValue: distance < 0 ? -width : width,
        duration: 180,
        useNativeDriver: true,
      }).start(({ finished }) => {
        if (finished) onDismiss();
      });
    },
    [onDismiss, translateX, width],
  );

  const panResponder = useMemo(
    () =>
      PanResponder.create({
        onMoveShouldSetPanResponder: (_, gesture) =>
          Math.abs(gesture.dx) > ROW_DISMISS_GESTURE.captureDistance &&
          Math.abs(gesture.dx) > Math.abs(gesture.dy) * ROW_DISMISS_GESTURE.verticalRatio,
        onPanResponderMove: (_, gesture) => {
          translateX.setValue(gesture.dx);
        },
        onPanResponderRelease: (_, gesture) => {
          if (
            Math.abs(gesture.dx) >= ROW_DISMISS_GESTURE.distance ||
            Math.abs(gesture.vx) >= ROW_DISMISS_GESTURE.velocity
          ) {
            dismissFromSwipe(gesture.dx || gesture.vx);
            return;
          }
          resetPosition();
        },
        onPanResponderTerminate: resetPosition,
      }),
    [dismissFromSwipe, resetPosition, translateX],
  );

  return (
    <View style={styles.swipeFrame}>
      <Animated.View
        pointerEvents="none"
        style={[
          styles.dismissBackground,
          { opacity: dismissOpacity, backgroundColor: `${theme.colors.error}14` },
        ]}
      >
        <MaterialCommunityIcons
          name={APP_ICONS.status.archive}
          size={22}
          color={theme.colors.error}
        />
        <MaterialCommunityIcons
          name={APP_ICONS.status.archive}
          size={22}
          color={theme.colors.error}
        />
      </Animated.View>
      <Animated.View style={{ transform: [{ translateX }] }} {...panResponder.panHandlers}>
        <Surface
          elevation={0}
          style={[
            styles.notificationCard,
            {
              backgroundColor: notification.read ? 'transparent' : theme.colors.elevation.level2,
              borderColor: notification.read ? theme.colors.outlineVariant : severityColor,
            },
          ]}
        >
          <TouchableRipple borderless onPress={onOpen} style={styles.notificationPressable}>
            <View style={styles.notificationContent}>
              <View
                style={[styles.notificationIcon, { backgroundColor: iconSurface.backgroundColor }]}
              >
                <MaterialCommunityIcons
                  name={notification.icon}
                  size={22}
                  color={iconSurface.iconColor}
                />
              </View>
              <View style={styles.notificationCopy}>
                <View style={styles.notificationTitleRow}>
                  <Text variant="titleSmall" numberOfLines={2} style={styles.notificationTitle}>
                    {notification.title}
                  </Text>
                  {!notification.read ? (
                    <View style={[styles.unreadDot, { backgroundColor: severityColor }]} />
                  ) : null}
                </View>
                <Text variant="bodySmall" style={{ color: theme.colors.onSurfaceVariant }}>
                  {notification.body}
                </Text>
                <InlineMeta
                  numberOfLines={2}
                  items={[
                    notificationChannelLabel(notification.channel),
                    severityLabel(notification.severity),
                    ...notification.badges,
                  ]}
                />
              </View>
            </View>
          </TouchableRipple>
        </Surface>
      </Animated.View>
    </View>
  );
}

function openTarget(notification: AppNotification) {
  const target = notification.target;
  if (target.type === 'account') {
    router.push({ pathname: '/account/[id]', params: { id: target.accountId } });
    return;
  }
  if (target.type === 'transaction') {
    router.push({ pathname: '/transaction/[id]', params: { id: target.transactionId } });
    return;
  }
  router.push(target.route as never);
}

function colorForSeverity(severity: AppNotificationSeverity, colors: MD3Theme['colors']): string {
  if (severity === 'critical') return colors.error;
  if (severity === 'warning') return colors.secondary;
  if (severity === 'success') return colors.tertiary;
  return colors.primary;
}

function severityLabel(severity: AppNotificationSeverity): string {
  if (severity === 'critical') return 'critical';
  if (severity === 'warning') return 'warning';
  if (severity === 'success') return 'done';
  return 'info';
}

function iconToneForSeverity(severity: AppNotificationSeverity): IconSurfaceTone {
  if (severity === 'critical') return 'danger';
  if (severity === 'warning') return 'warning';
  if (severity === 'success') return 'positive';
  return 'primary';
}

const styles = StyleSheet.create({
  swipeFrame: { position: 'relative', overflow: 'hidden', borderRadius: tokens.radius.md },
  dismissBackground: {
    position: 'absolute',
    top: 0,
    right: 0,
    bottom: 0,
    left: 0,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: tokens.space.lg,
    borderRadius: tokens.radius.md,
  },
  notificationCard: {
    borderRadius: tokens.radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  notificationPressable: { borderRadius: tokens.radius.md, overflow: 'hidden' },
  notificationContent: { flexDirection: 'row', gap: tokens.space.md, padding: tokens.space.md },
  notificationIcon: {
    width: 42,
    height: 42,
    borderRadius: tokens.radius.md,
    alignItems: 'center',
    justifyContent: 'center',
  },
  notificationCopy: { flex: 1, gap: 8 },
  notificationTitleRow: { flexDirection: 'row', alignItems: 'flex-start', gap: 8 },
  notificationTitle: { flex: 1, fontWeight: '700' },
  unreadDot: { width: 8, height: 8, borderRadius: 4, marginTop: 6 },
});
