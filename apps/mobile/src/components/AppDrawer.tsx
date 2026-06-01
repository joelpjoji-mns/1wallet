import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { router } from 'expo-router';
import { memo, useCallback, useEffect, useMemo, useRef } from 'react';
import { Image, Pressable, ScrollView, StyleSheet, View, useWindowDimensions } from 'react-native';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import { Divider, Portal, Surface, Text, TouchableRipple, useTheme } from 'react-native-paper';
import Animated, {
  Easing,
  runOnJS,
  useAnimatedStyle,
  useSharedValue,
  withTiming,
} from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { withColorAlpha } from '../colorAlpha';
import { DRAWER_DISMISS_GESTURE, GESTURE_IGNORE_OFFSET } from '../gestureDefaults';
import { APP_ICONS, type AppIconName } from '../iconSystem';
import { useAppUpdate } from '../updates/AppUpdateProvider';

type DrawerIcon = AppIconName;
type DrawerItemConfig = {
  label: string;
  icon: DrawerIcon;
  route: string;
  badge?: string;
  activePrefixes?: string[];
  inactivePrefixes?: string[];
};

const DRAWER_WIDTH_RATIO = 0.7;
const DRAWER_MAX_WIDTH = 392;
const DRAWER_OPEN_DURATION = tokens.motion.normal;
const DRAWER_CLOSE_DURATION = tokens.motion.fast;

const ACTIVE_ROUTE_PREFIXES: Record<string, string[]> = {
  '/(tabs)/home': ['/', '/home'],
  '/notifications': ['/notifications'],
  '/add': ['/add'],
  '/review': ['/review', '/capture'],
  '/imports': ['/imports', '/import-wallet-csv', '/data-backup'],
  '/auto-capture': ['/auto-capture', '/import-sms'],
  '/widgets': ['/widgets', '/reports'],
  '/currencies': ['/currencies'],
  '/categories': ['/categories'],
  '/cards': ['/cards'],
  '/loans': ['/loans'],
  '/loans/forecast': ['/loans/forecast'],
  '/recurring': ['/recurring'],
  '/sync': ['/sync'],
  '/updates': ['/updates'],
  '/settings': ['/settings'],
};

const PRIMARY_ITEMS: DrawerItemConfig[] = [
  { label: 'Home', icon: APP_ICONS.navigation.home, route: '/(tabs)/home' },
  { label: 'Add record', icon: APP_ICONS.navigation.addRecord, route: '/add' },
  { label: 'Review', icon: APP_ICONS.navigation.review, route: '/review' },
];

const MONEY_ITEMS: DrawerItemConfig[] = [
  { label: 'Widgets', icon: APP_ICONS.navigation.widgets, route: '/widgets' },
  { label: 'Categories', icon: APP_ICONS.navigation.categories, route: '/categories' },
  { label: 'Cards', icon: APP_ICONS.navigation.cards, route: '/cards' },
  { label: 'Currencies', icon: APP_ICONS.navigation.currencies, route: '/currencies' },
];

const PLANNING_ITEMS: DrawerItemConfig[] = [
  { label: 'Planned payments', icon: APP_ICONS.navigation.plannedPayments, route: '/recurring' },
];

const CREDIT_ITEMS: DrawerItemConfig[] = [
  {
    label: 'Loans',
    icon: APP_ICONS.navigation.loans,
    route: '/loans',
    inactivePrefixes: ['/loans/forecast'],
  },
  { label: 'Loan forecast', icon: APP_ICONS.navigation.loanForecast, route: '/loans/forecast' },
];

const TOOL_ITEMS: DrawerItemConfig[] = [
  { label: 'Sync', icon: APP_ICONS.navigation.sync, route: '/sync' },
  { label: 'Auto Capture', icon: APP_ICONS.navigation.autoCapture, route: '/auto-capture' },
  { label: 'Import & backup', icon: APP_ICONS.navigation.imports, route: '/imports' },
  { label: 'Notifications', icon: APP_ICONS.navigation.notifications, route: '/notifications' },
  { label: 'Updates', icon: APP_ICONS.navigation.updates, route: '/updates' },
];

export function AppDrawer({
  visible,
  email,
  displayName,
  photoUrl,
  currentPath,
  onDismiss,
  onClosed,
  onSignOut,
}: {
  visible: boolean;
  email?: string;
  displayName?: string;
  photoUrl?: string;
  currentPath?: string;
  onDismiss: () => void;
  onClosed: () => void;
  onSignOut: () => void;
}) {
  const theme = useTheme();
  const updates = useAppUpdate();
  const insets = useSafeAreaInsets();
  const { width: windowWidth } = useWindowDimensions();
  const progress = useSharedValue(0);
  const gestureStartProgress = useSharedValue(0);
  const pendingRouteRef = useRef<string | null>(null);
  const drawerWidth = Math.min(windowWidth * DRAWER_WIDTH_RATIO, DRAWER_MAX_WIDTH);
  const profileName = profileDisplayName(email, displayName);
  const drawerPaddingTop = Math.max(insets.top, tokens.space.sm) + tokens.space.sm;
  const drawerPaddingBottom = Math.max(insets.bottom, tokens.space.sm);

  const animateTo = useCallback(
    (toValue: number, onFinished?: () => void) => {
      progress.value = withTiming(
        toValue,
        {
          duration: toValue > 0 ? DRAWER_OPEN_DURATION : DRAWER_CLOSE_DURATION,
          easing: Easing.out(toValue > 0 ? Easing.cubic : Easing.quad),
        },
        (finished) => {
          if (finished && onFinished) runOnJS(onFinished)();
        },
      );
    },
    [progress],
  );

  useEffect(() => {
    animateTo(visible ? 1 : 0, visible ? undefined : onClosed);
  }, [animateTo, onClosed, visible]);

  useEffect(() => {
    pendingRouteRef.current = null;
  }, [currentPath]);

  const dismiss = useCallback(() => onDismiss(), [onDismiss]);
  const dismissGesture = useMemo(
    () =>
      Gesture.Pan()
        .activeOffsetX([-DRAWER_DISMISS_GESTURE.slop, GESTURE_IGNORE_OFFSET])
        .failOffsetY([-DRAWER_DISMISS_GESTURE.failY, DRAWER_DISMISS_GESTURE.failY])
        .onBegin(() => {
          gestureStartProgress.value = progress.value;
        })
        .onUpdate((event) => {
          progress.value = Math.max(
            0,
            Math.min(1, gestureStartProgress.value + event.translationX / drawerWidth),
          );
        })
        .onEnd((event) => {
          const shouldDismiss =
            event.translationX < -DRAWER_DISMISS_GESTURE.distance ||
            (event.velocityX < -DRAWER_DISMISS_GESTURE.velocity &&
              event.translationX < -DRAWER_DISMISS_GESTURE.slop);
          progress.value = withTiming(shouldDismiss ? 0 : 1, {
            duration: shouldDismiss ? DRAWER_CLOSE_DURATION : DRAWER_OPEN_DURATION,
            easing: Easing.out(shouldDismiss ? Easing.quad : Easing.cubic),
          });
          if (shouldDismiss) runOnJS(onDismiss)();
        })
        .onFinalize((_event, success) => {
          if (!success && progress.value > 0 && progress.value < 1) {
            progress.value = withTiming(1, {
              duration: DRAWER_OPEN_DURATION,
              easing: Easing.out(Easing.cubic),
            });
          }
        }),
    [drawerWidth, gestureStartProgress, onDismiss, progress],
  );

  const openRoute = useCallback(
    (route: string, active?: boolean) => {
      onDismiss();
      const isActive = active ?? isDrawerItemActive(route, currentPath);
      if (pendingRouteRef.current || isActive) return;
      pendingRouteRef.current = route;
      router.push(route as never);
    },
    [currentPath, onDismiss],
  );
  const dividerTheme = useMemo(
    () => ({ colors: { outlineVariant: theme.colors.outlineVariant } }),
    [theme.colors.outlineVariant],
  );
  const toolItems = useMemo(
    () =>
      TOOL_ITEMS.map((item) =>
        item.route === '/updates' ? { ...item, badge: updates.drawerBadge } : item,
      ),
    [updates.drawerBadge],
  );

  const drawerAnimatedStyle = useAnimatedStyle(
    () => ({
      transform: [{ translateX: -drawerWidth * (1 - progress.value) }],
    }),
    [drawerWidth],
  );
  const scrimAnimatedStyle = useAnimatedStyle(() => ({ opacity: progress.value }));

  return (
    <Portal>
      <GestureDetector gesture={dismissGesture}>
        <View pointerEvents="auto" style={styles.overlay}>
          <Animated.View style={[styles.scrimLayer, scrimAnimatedStyle]}>
            <Pressable
              style={[
                styles.scrim,
                { backgroundColor: withColorAlpha(theme.colors.scrim, theme.dark ? 0.64 : 0.46) },
              ]}
              onPress={dismiss}
            />
          </Animated.View>
          <Animated.View style={[{ width: drawerWidth }, drawerAnimatedStyle]}>
            <Surface
              style={[
                styles.drawer,
                {
                  backgroundColor: theme.colors.elevation.level1,
                  borderRightColor: withColorAlpha(theme.colors.outline, theme.dark ? 0.24 : 0.16),
                  paddingTop: drawerPaddingTop,
                  paddingBottom: drawerPaddingBottom,
                },
              ]}
              elevation={3}
            >
              <View
                style={[
                  styles.profileBlock,
                  {
                    backgroundColor: withColorAlpha(theme.colors.primary, theme.dark ? 0.16 : 0.08),
                    borderColor: withColorAlpha(theme.colors.primary, theme.dark ? 0.3 : 0.18),
                  },
                ]}
              >
                <View style={[styles.profileCircle, { backgroundColor: theme.colors.primary }]}>
                  {photoUrl ? (
                    <Image
                      source={{ uri: photoUrl }}
                      resizeMode="contain"
                      style={styles.profilePhoto}
                    />
                  ) : (
                    <Text variant="titleMedium" style={{ color: theme.colors.onPrimary }}>
                      {profileInitials(email, displayName)}
                    </Text>
                  )}
                </View>
                <View style={styles.profileCopy}>
                  <Text
                    variant="titleMedium"
                    numberOfLines={1}
                    style={[styles.profileTitle, { color: theme.colors.onSurface }]}
                  >
                    {profileName}
                  </Text>
                  <Text
                    variant="bodySmall"
                    numberOfLines={1}
                    style={[styles.profileSubtitle, { color: theme.colors.onSurfaceVariant }]}
                  >
                    My Wallet
                  </Text>
                </View>
              </View>

              <ScrollView
                contentContainerStyle={styles.scrollContent}
                showsVerticalScrollIndicator={false}
              >
                <DrawerSection
                  title="Daily"
                  items={PRIMARY_ITEMS}
                  currentPath={currentPath}
                  onPress={openRoute}
                />
                <Divider theme={dividerTheme} />
                <DrawerSection
                  title="Money"
                  items={MONEY_ITEMS}
                  currentPath={currentPath}
                  onPress={openRoute}
                />
                <Divider theme={dividerTheme} />
                <DrawerSection
                  title="Planning"
                  items={PLANNING_ITEMS}
                  currentPath={currentPath}
                  onPress={openRoute}
                />
                <Divider theme={dividerTheme} />
                <DrawerSection
                  title="Loans & credit"
                  items={CREDIT_ITEMS}
                  currentPath={currentPath}
                  onPress={openRoute}
                />
                <Divider theme={dividerTheme} />
                <DrawerSection
                  title="Tools"
                  items={toolItems}
                  currentPath={currentPath}
                  onPress={openRoute}
                />
              </ScrollView>

              <View
                style={[
                  styles.footer,
                  {
                    backgroundColor: withColorAlpha(
                      theme.colors.elevation.level2,
                      theme.dark ? 0.74 : 0.92,
                    ),
                    borderTopColor: withColorAlpha(theme.colors.outline, theme.dark ? 0.2 : 0.12),
                  },
                ]}
              >
                <DrawerRow
                  label="Settings"
                  icon="cog-outline"
                  active={isDrawerItemActive('/settings', currentPath)}
                  route="/settings"
                  onRoutePress={openRoute}
                />
                <DrawerRow label="Sign out" icon="logout-variant" onPress={onSignOut} danger />
              </View>
            </Surface>
          </Animated.View>
        </View>
      </GestureDetector>
    </Portal>
  );
}

const DrawerSection = memo(function DrawerSection({
  title,
  items,
  currentPath,
  onPress,
}: {
  title: string;
  items: DrawerItemConfig[];
  currentPath?: string;
  onPress: (route: string, active?: boolean) => void;
}) {
  const theme = useTheme();

  return (
    <View style={styles.section}>
      <Text
        variant="labelSmall"
        style={[styles.sectionTitle, { color: theme.colors.onSurfaceVariant }]}
      >
        {title.toUpperCase()}
      </Text>
      {items.map((item) => {
        const active = isDrawerItemActive(
          item.route,
          currentPath,
          item.activePrefixes,
          item.inactivePrefixes,
        );
        return (
          <DrawerRow
            key={`${item.label}-${item.route}`}
            label={item.label}
            icon={item.icon}
            badge={item.badge}
            active={active}
            route={item.route}
            onRoutePress={onPress}
          />
        );
      })}
    </View>
  );
});

const DrawerRow = memo(function DrawerRow({
  label,
  icon,
  route,
  badge,
  active,
  danger,
  onRoutePress,
  onPress,
}: {
  label: string;
  icon: DrawerIcon;
  route?: string;
  badge?: string;
  active?: boolean;
  danger?: boolean;
  onRoutePress?: (route: string, active?: boolean) => void;
  onPress?: () => void;
}) {
  const theme = useTheme();
  const handlePress = useCallback(() => {
    if (route && onRoutePress) {
      onRoutePress(route, active);
      return;
    }
    onPress?.();
  }, [active, onPress, onRoutePress, route]);
  const color = danger
    ? theme.colors.error
    : active
      ? theme.colors.primary
      : theme.colors.onSurface;
  const iconColor = danger
    ? theme.colors.error
    : active
      ? theme.colors.onPrimary
      : theme.colors.onSurfaceVariant;
  const iconBackground = active
    ? theme.colors.primary
    : danger
      ? withColorAlpha(theme.colors.error, theme.dark ? 0.18 : 0.1)
      : theme.colors.elevation.level2;
  const rowBackground = active
    ? withColorAlpha(theme.colors.primary, theme.dark ? 0.16 : 0.08)
    : 'transparent';
  const rowBorder = active
    ? withColorAlpha(theme.colors.primary, theme.dark ? 0.32 : 0.18)
    : 'transparent';

  return (
    <TouchableRipple
      style={[
        styles.row,
        {
          backgroundColor: rowBackground,
          borderColor: rowBorder,
        },
      ]}
      rippleColor={
        danger
          ? withColorAlpha(theme.colors.error, theme.dark ? 0.18 : 0.12)
          : withColorAlpha(theme.colors.primary, theme.dark ? 0.18 : 0.1)
      }
      borderless
      onPress={handlePress}
    >
      <View style={styles.rowInner}>
        {active ? (
          <View style={[styles.rowActiveRail, { backgroundColor: theme.colors.primary }]} />
        ) : null}
        <View style={[styles.rowIcon, { backgroundColor: iconBackground }]}>
          <MaterialCommunityIcons name={icon} size={20} color={iconColor} />
        </View>
        <Text variant="bodyLarge" numberOfLines={1} style={[styles.rowLabel, { color }]}>
          {label}
        </Text>
        {badge ? (
          <View style={[styles.badge, { backgroundColor: theme.colors.secondaryContainer }]}>
            <Text variant="labelSmall" style={{ color: theme.colors.onSecondaryContainer }}>
              {badge}
            </Text>
          </View>
        ) : null}
      </View>
    </TouchableRipple>
  );
});

function isDrawerItemActive(
  route: string,
  currentPath?: string,
  activePrefixes?: string[],
  inactivePrefixes?: string[],
): boolean {
  const normalizedPath = normalizePath(currentPath);
  if (
    inactivePrefixes?.some(
      (prefix) => normalizedPath === prefix || normalizedPath.startsWith(`${prefix}/`),
    )
  ) {
    return false;
  }
  const prefixes = activePrefixes ?? ACTIVE_ROUTE_PREFIXES[route] ?? [route];

  return prefixes.some((prefix) => {
    if (prefix === '/') return normalizedPath === '/' || normalizedPath === '/home';
    return normalizedPath === prefix || normalizedPath.startsWith(`${prefix}/`);
  });
}

function normalizePath(path?: string): string {
  const normalized = path?.replace(/\/$/, '') || '/';
  return normalized.length === 0 ? '/' : normalized;
}

function profileInitials(email?: string, displayName?: string): string {
  const name = (displayName || email?.split('@')[0])
    ?.split('@')[0]
    ?.replace(/[._-]+/g, ' ')
    .trim();
  if (!name) return '1W';
  return name
    .split(' ')
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join('');
}

function profileDisplayName(email?: string, displayName?: string): string {
  const name = (displayName || email?.split('@')[0])
    ?.split('@')[0]
    ?.replace(/[._-]+/g, ' ')
    .trim();
  if (!name) return '1wallet';
  return name
    .split(' ')
    .filter(Boolean)
    .map((part) => `${part[0]?.toUpperCase() ?? ''}${part.slice(1)}`)
    .join(' ');
}

const styles = StyleSheet.create({
  overlay: { ...StyleSheet.absoluteFill, zIndex: 140, flexDirection: 'row' },
  scrimLayer: { ...StyleSheet.absoluteFill },
  scrim: { ...StyleSheet.absoluteFill },
  drawer: {
    width: '100%',
    height: '100%',
    borderRightWidth: StyleSheet.hairlineWidth,
  },
  profileBlock: {
    minHeight: 88,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: tokens.radius.lg,
    marginHorizontal: tokens.space.md,
    marginBottom: tokens.space.sm,
    padding: tokens.space.md,
  },
  profileCircle: {
    width: 54,
    height: 54,
    borderRadius: tokens.radius.pill,
    alignItems: 'center',
    justifyContent: 'center',
    overflow: 'hidden',
  },
  profilePhoto: { width: '100%', height: '100%' },
  profileCopy: { flex: 1, minWidth: 0, gap: 2 },
  profileTitle: { fontWeight: '700' },
  profileSubtitle: { fontWeight: '600' },
  scrollContent: {
    paddingHorizontal: tokens.space.sm,
    paddingBottom: tokens.space.md,
    gap: tokens.space.xs,
  },
  section: { gap: tokens.space.xs, paddingVertical: tokens.space.xs },
  sectionTitle: {
    paddingHorizontal: tokens.space.md,
    paddingTop: tokens.space.sm,
    paddingBottom: tokens.space.xs,
    fontSize: 11,
    lineHeight: 14,
    fontWeight: '700',
    letterSpacing: 0,
  },
  row: {
    borderRadius: tokens.radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
  rowInner: {
    minHeight: 50,
    flexDirection: 'row',
    alignItems: 'center',
    gap: tokens.space.sm,
    position: 'relative',
    paddingHorizontal: tokens.space.sm,
  },
  rowActiveRail: {
    position: 'absolute',
    left: 0,
    width: 4,
    height: 30,
    borderRadius: tokens.radius.pill,
  },
  rowIcon: {
    width: 38,
    height: 38,
    borderRadius: 13,
    alignItems: 'center',
    justifyContent: 'center',
  },
  rowLabel: { flex: 1, fontWeight: '600' },
  badge: {
    minWidth: 28,
    minHeight: 24,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: tokens.radius.pill,
    paddingHorizontal: tokens.space.sm,
  },
  footer: {
    borderTopWidth: StyleSheet.hairlineWidth,
    padding: tokens.space.sm,
    gap: tokens.space.sm,
  },
});
