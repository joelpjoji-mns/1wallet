import { tokens } from '@1wallet/ui';
import { MaterialCommunityIcons } from '@expo/vector-icons';
import { withLayoutContext } from 'expo-router';
import type {
  MaterialTopTabBarProps,
  MaterialTopTabNavigationEventMap,
  MaterialTopTabNavigationOptions,
} from 'expo-router/js-top-tabs';
import { createMaterialTopTabNavigator } from 'expo-router/js-top-tabs';
import type { ParamListBase, TabNavigationState } from 'expo-router/react-navigation';
import { useEffect, useMemo, useRef, useState, type ComponentProps } from 'react';
import {
  Animated,
  Platform,
  Pressable,
  StyleSheet,
  useWindowDimensions,
  View,
  type LayoutChangeEvent,
} from 'react-native';
import { Text, useTheme } from 'react-native-paper';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

type TabIconName = ComponentProps<typeof MaterialCommunityIcons>['name'];
type TabConfig = {
  name: string;
  title: string;
  icon: TabIconName;
  activeIcon?: TabIconName;
  visible?: boolean;
};

const TAB_CONFIG: TabConfig[] = [
  { name: 'home', title: 'Home', icon: 'view-dashboard-outline', activeIcon: 'view-dashboard' },
  { name: 'transactions', title: 'Transactions', icon: 'format-list-bulleted' },
  {
    name: 'calendar',
    title: 'Calendar',
    icon: 'calendar-month-outline',
    activeIcon: 'calendar-month',
  },
  { name: 'planner', title: 'Planner', icon: 'chart-timeline-variant' },
  {
    name: 'accounts',
    title: 'Accounts',
    icon: 'wallet-outline',
    activeIcon: 'wallet',
  },
];

const TAB_BY_NAME = new Map(TAB_CONFIG.map((tab) => [tab.name, tab]));
const ANDROID_NAV_BAR_FALLBACK_PADDING = tokens.space.xl;
const { Navigator } = createMaterialTopTabNavigator();

const PagerTabs = withLayoutContext<
  MaterialTopTabNavigationOptions,
  typeof Navigator,
  TabNavigationState<ParamListBase>,
  MaterialTopTabNavigationEventMap
>(Navigator);

export default function TabsLayout() {
  const theme = useTheme();
  const { width } = useWindowDimensions();

  return (
    <PagerTabs
      initialLayout={{ width }}
      initialRouteName="home"
      backBehavior="initialRoute"
      tabBarPosition="bottom"
      tabBar={(props: MaterialTopTabBarProps) => <BottomPagerBar {...props} />}
      screenOptions={{
        swipeEnabled: true,
        animationEnabled: true,
        sceneStyle: { backgroundColor: theme.colors.background },
        lazy: true,
        lazyPreloadDistance: 1,
        freezeOnBlur: true,
      }}
    >
      {TAB_CONFIG.map((tab) => (
        <PagerTabs.Screen
          key={tab.name}
          name={tab.name}
          options={{
            title: tab.title,
            tabBarAccessibilityLabel: `${tab.title} tab`,
          }}
        />
      ))}
    </PagerTabs>
  );
}

function BottomPagerBar({ state, descriptors, navigation, position }: MaterialTopTabBarProps) {
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const { width } = useWindowDimensions();
  const visibleRoutes = useMemo(
    () =>
      state.routes.filter(
        (route: TabNavigationState<ParamListBase>['routes'][number]) =>
          TAB_BY_NAME.get(route.name)?.visible !== false,
      ),
    [state.routes],
  );
  const [islandWidth, setIslandWidth] = useState(0);
  const settleProgress = useRef(new Animated.Value(1)).current;

  const bottomSafePadding = Math.max(
    insets.bottom,
    Platform.OS === 'android' ? ANDROID_NAV_BAR_FALLBACK_PADDING : tokens.space.xs,
  );
  const compact = width < 370;
  const islandPadding = compact ? 4 : tokens.space.xs;
  const indicatorSize = compact ? 34 : 38;
  const indicatorTop = compact ? 7 : 8;
  const routeIndexes = useMemo(
    () =>
      Array.from(
        { length: Math.max(visibleRoutes.length, 2) },
        (_unused: unknown, index: number) => index,
      ),
    [visibleRoutes.length],
  );
  const indicatorTranslateX = useMemo(() => {
    const usableWidth = Math.max(0, islandWidth - islandPadding * 2);
    const tabWidth = usableWidth / Math.max(visibleRoutes.length, 1);
    const outputRange = routeIndexes.map(
      (index: number) => islandPadding + tabWidth * index + (tabWidth - indicatorSize) / 2,
    );

    return position.interpolate({
      inputRange: routeIndexes,
      outputRange,
      extrapolate: 'clamp',
    });
  }, [indicatorSize, islandPadding, islandWidth, position, routeIndexes, visibleRoutes.length]);
  const indicatorTravelScale = useMemo(() => {
    const inputRange = routeIndexes.flatMap((index: number) =>
      index === 0 ? [index] : [index - 0.5, index],
    );
    const outputRange = routeIndexes.flatMap((index: number) => (index === 0 ? [1] : [0.24, 1]));

    return position.interpolate({
      inputRange,
      outputRange,
      extrapolate: 'clamp',
    });
  }, [position, routeIndexes]);
  const indicatorDotOpacity = useMemo(() => {
    const inputRange = routeIndexes.flatMap((index: number) =>
      index === 0 ? [index] : [index - 0.5, index],
    );
    const outputRange = routeIndexes.flatMap((index: number) => (index === 0 ? [0] : [1, 0]));

    return position.interpolate({
      inputRange,
      outputRange,
      extrapolate: 'clamp',
    });
  }, [position, routeIndexes]);
  const indicatorScaleX = settleProgress.interpolate({
    inputRange: [0, 1],
    outputRange: [1.14, 1],
  });
  const indicatorScaleY = settleProgress.interpolate({
    inputRange: [0, 1],
    outputRange: [0.92, 1],
  });
  const indicatorTravelScaleX = Animated.multiply(indicatorScaleX, indicatorTravelScale);
  const indicatorTravelScaleY = Animated.multiply(indicatorScaleY, indicatorTravelScale);
  const indicatorOpacity = settleProgress.interpolate({
    inputRange: [0, 1],
    outputRange: [0.7, 1],
  });

  useEffect(() => {
    settleProgress.setValue(0);
    Animated.spring(settleProgress, {
      toValue: 1,
      speed: 20,
      bounciness: 8,
      useNativeDriver: true,
    }).start();
  }, [settleProgress, state.index]);

  const handleIslandLayout = (event: LayoutChangeEvent) => {
    const nextWidth = event.nativeEvent.layout.width;
    setIslandWidth((currentWidth) =>
      Math.abs(currentWidth - nextWidth) < 1 ? currentWidth : nextWidth,
    );
  };

  return (
    <View
      pointerEvents="box-none"
      style={[
        styles.tabBarWrap,
        compact && styles.tabBarWrapCompact,
        {
          paddingBottom: bottomSafePadding + tokens.space.xs,
        },
      ]}
    >
      <View
        onLayout={handleIslandLayout}
        style={[
          styles.tabBarIsland,
          compact && styles.tabBarIslandCompact,
          {
            backgroundColor: theme.colors.elevation.level2,
            borderColor: theme.colors.outlineVariant,
            shadowColor: theme.colors.shadow,
          },
        ]}
      >
        <View
          pointerEvents="none"
          style={[styles.tabBarHighlight, { backgroundColor: theme.colors.elevation.level4 }]}
        />
        {islandWidth > 0 ? (
          <Animated.View
            pointerEvents="none"
            style={[
              styles.activeTabHalo,
              {
                width: indicatorSize,
                height: indicatorSize,
                borderRadius: indicatorSize / 2,
                top: indicatorTop,
                transform: [{ translateX: indicatorTranslateX }],
              },
            ]}
          >
            <Animated.View
              style={[
                styles.activeTabRing,
                {
                  borderRadius: indicatorSize / 2,
                  borderColor: theme.colors.primary,
                  opacity: indicatorOpacity,
                  shadowColor: theme.colors.primary,
                  transform: [{ scaleX: indicatorTravelScaleX }, { scaleY: indicatorTravelScaleY }],
                },
              ]}
            />
            <Animated.View
              style={[
                styles.activeTabDot,
                { backgroundColor: theme.colors.primary, opacity: indicatorDotOpacity },
              ]}
            />
          </Animated.View>
        ) : null}
        {visibleRoutes.map(
          (route: TabNavigationState<ParamListBase>['routes'][number], index: number) => {
            const focused = state.index === index;
            const options = descriptors[route.key]?.options;
            const tab = TAB_BY_NAME.get(route.name);
            const title = options?.title ?? tab?.title ?? route.name;
            const icon = tab?.icon ?? 'circle-outline';
            const activeIcon = tab?.activeIcon ?? icon;

            const onPress = () => {
              const event = navigation.emit({
                type: 'tabPress',
                target: route.key,
                canPreventDefault: true,
              });

              if (!focused && !event.defaultPrevented) {
                navigation.navigate(route.name, route.params);
              }
            };

            const onLongPress = () => {
              navigation.emit({ type: 'tabLongPress', target: route.key });
            };

            return (
              <BottomPagerTabButton
                key={route.key}
                accessibilityLabel={options?.tabBarAccessibilityLabel ?? `${title} tab`}
                focused={focused}
                activeIcon={activeIcon}
                icon={icon}
                compact={compact}
                title={title}
                onLongPress={onLongPress}
                onPress={onPress}
              />
            );
          },
        )}
      </View>
    </View>
  );
}

function BottomPagerTabButton({
  accessibilityLabel,
  focused,
  activeIcon,
  icon,
  compact,
  title,
  onLongPress,
  onPress,
}: {
  accessibilityLabel: string;
  focused: boolean;
  activeIcon: TabIconName;
  icon: TabIconName;
  compact: boolean;
  title: string;
  onLongPress: () => void;
  onPress: () => void;
}) {
  const theme = useTheme();
  const focusProgress = useRef(new Animated.Value(focused ? 1 : 0)).current;
  const pressProgress = useRef(new Animated.Value(0)).current;

  useEffect(() => {
    Animated.spring(focusProgress, {
      toValue: focused ? 1 : 0,
      speed: 20,
      bounciness: 8,
      useNativeDriver: true,
    }).start();
  }, [focusProgress, focused]);

  const lift = focusProgress.interpolate({
    inputRange: [0, 1],
    outputRange: [0, -2],
  });
  const iconScale = focusProgress.interpolate({
    inputRange: [0, 1],
    outputRange: [1, 1.04],
  });
  const labelOpacity = focusProgress.interpolate({
    inputRange: [0, 1],
    outputRange: [0.62, 1],
  });
  const labelLift = focusProgress.interpolate({
    inputRange: [0, 1],
    outputRange: [0.5, 0],
  });
  const pressScale = pressProgress.interpolate({
    inputRange: [0, 1],
    outputRange: [1, 0.94],
  });
  const color = focused ? theme.colors.primary : theme.colors.onSurfaceVariant;

  const animatePress = (toValue: number) => {
    Animated.spring(pressProgress, {
      toValue,
      speed: 34,
      bounciness: 0,
      useNativeDriver: true,
    }).start();
  };

  return (
    <Pressable
      accessibilityLabel={accessibilityLabel}
      accessibilityRole="tab"
      accessibilityState={focused ? { selected: true } : undefined}
      onLongPress={onLongPress}
      onPress={onPress}
      onPressIn={() => animatePress(1)}
      onPressOut={() => animatePress(0)}
      style={styles.tabButton}
    >
      <Animated.View
        style={[
          styles.tabButtonInner,
          compact && styles.tabButtonInnerCompact,
          {
            transform: [{ translateY: lift }, { scale: pressScale }],
          },
        ]}
      >
        <Animated.View
          style={[
            styles.iconPill,
            compact && styles.iconPillCompact,
            { transform: [{ scale: iconScale }] },
          ]}
        >
          <MaterialCommunityIcons
            name={focused ? activeIcon : icon}
            size={compact ? 22 : 23}
            color={color}
          />
        </Animated.View>
        <Animated.View
          style={[
            styles.tabLabelWrap,
            { opacity: labelOpacity, transform: [{ translateY: labelLift }] },
          ]}
        >
          <Text
            variant="labelSmall"
            numberOfLines={1}
            style={[styles.tabLabel, focused && styles.tabLabelFocused, { color }]}
          >
            {title}
          </Text>
        </Animated.View>
      </Animated.View>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  tabBarWrap: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    zIndex: 20,
    backgroundColor: 'transparent',
    minHeight: 90,
    justifyContent: 'flex-end',
    paddingHorizontal: tokens.space.md,
    paddingTop: tokens.space.xs,
  },
  tabBarWrapCompact: {
    minHeight: 82,
    paddingHorizontal: tokens.space.sm,
  },
  tabBarIsland: {
    flexDirection: 'row',
    alignItems: 'center',
    minHeight: tokens.size.bottomBar,
    borderRadius: tokens.radius.xl,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: tokens.space.xs,
    paddingVertical: 6,
    elevation: 14,
    shadowOpacity: 0.18,
    shadowRadius: 18,
    shadowOffset: { width: 0, height: 8 },
    position: 'relative',
  },
  tabBarIslandCompact: {
    minHeight: 64,
    paddingHorizontal: 4,
    paddingVertical: 4,
  },
  tabBarHighlight: {
    position: 'absolute',
    left: 22,
    right: 22,
    top: 1,
    height: StyleSheet.hairlineWidth,
    borderRadius: tokens.radius.pill,
  },
  tabButton: {
    flex: 1,
    minWidth: 0,
    borderRadius: tokens.radius.xl,
    zIndex: 1,
  },
  tabButtonInner: {
    minHeight: 60,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 4,
    borderRadius: tokens.radius.lg,
    paddingHorizontal: tokens.space.xs,
  },
  tabButtonInnerCompact: {
    minHeight: 54,
    gap: 2,
    paddingHorizontal: 2,
  },
  activeTabHalo: {
    position: 'absolute',
    left: 0,
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 0,
  },
  activeTabRing: {
    width: '100%',
    height: '100%',
    borderWidth: 1.8,
    backgroundColor: 'transparent',
    shadowOpacity: 0.16,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 2 },
  },
  activeTabDot: {
    position: 'absolute',
    width: 6,
    height: 6,
    borderRadius: 3,
  },
  iconPill: {
    width: 46,
    height: 32,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: tokens.radius.pill,
  },
  iconPillCompact: { width: 40, height: 29 },
  tabLabelWrap: { width: '100%' },
  tabLabel: {
    width: '100%',
    textAlign: 'center',
    fontWeight: '600',
    fontSize: 10.5,
    lineHeight: 13,
    letterSpacing: 0,
    includeFontPadding: false,
  },
  tabLabelFocused: {
    fontWeight: '700',
  },
});
