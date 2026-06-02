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
import { withColorAlpha } from '../../src/colorAlpha';

type TabIconName = ComponentProps<typeof MaterialCommunityIcons>['name'];
type TabConfig = {
  name: string;
  title: string;
  icon: TabIconName;
  activeIcon?: TabIconName;
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
  { name: 'accounts', title: 'Accounts', icon: 'wallet-outline', activeIcon: 'wallet' },
];

const TAB_BY_NAME = new Map(TAB_CONFIG.map((tab) => [tab.name, tab]));
const ANDROID_NAV_BAR_FALLBACK_PADDING = tokens.space.xl;
const ISLAND_HORIZONTAL_MARGIN = tokens.space.lg;
const ISLAND_MAX_WIDTH = 430;
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
      tabBar={(props: MaterialTopTabBarProps) => <BottomIslandTabBar {...props} />}
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

function BottomIslandTabBar({ state, descriptors, navigation }: MaterialTopTabBarProps) {
  const theme = useTheme();
  const insets = useSafeAreaInsets();
  const { width } = useWindowDimensions();
  const [islandWidth, setIslandWidth] = useState(0);
  const indicatorProgress = useRef(new Animated.Value(state.index)).current;
  const settleProgress = useRef(new Animated.Value(1)).current;
  const visibleRoutes = useMemo(() => state.routes, [state.routes]);
  const compact = width < 390;
  const bottomSafePadding = Math.max(
    insets.bottom,
    Platform.OS === 'android' ? ANDROID_NAV_BAR_FALLBACK_PADDING : tokens.space.xs,
  );
  const islandMaxWidth = Math.min(width - ISLAND_HORIZONTAL_MARGIN * 2, ISLAND_MAX_WIDTH);
  const islandPadding = compact ? 4 : 5;
  const indicatorHeight = compact ? 42 : 46;
  const routeIndexes = useMemo(
    () =>
      Array.from(
        { length: Math.max(visibleRoutes.length, 2) },
        (_unused: unknown, index: number) => index,
      ),
    [visibleRoutes.length],
  );
  const indicatorMetrics = useMemo(() => {
    const usableWidth = Math.max(0, islandWidth - islandPadding * 2);
    const tabWidth = usableWidth / Math.max(visibleRoutes.length, 1);
    const pillWidth = Math.max(44, tabWidth - (compact ? 2 : 4));
    const outputRange = routeIndexes.map(
      (index: number) => islandPadding + tabWidth * index + (tabWidth - pillWidth) / 2,
    );

    return { pillWidth, outputRange };
  }, [compact, islandPadding, islandWidth, routeIndexes, visibleRoutes.length]);
  const indicatorTranslateX = indicatorProgress.interpolate({
    inputRange: routeIndexes,
    outputRange: indicatorMetrics.outputRange,
    extrapolate: 'clamp',
  });
  const indicatorScaleX = settleProgress.interpolate({
    inputRange: [0, 1],
    outputRange: [0.96, 1],
  });
  const indicatorOpacity = settleProgress.interpolate({
    inputRange: [0, 1],
    outputRange: [0.72, 1],
  });

  useEffect(() => {
    indicatorProgress.setValue(state.index);
    settleProgress.setValue(1);
  }, [indicatorProgress, settleProgress, state.index]);

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
            maxWidth: islandMaxWidth,
            backgroundColor: theme.colors.elevation.level2,
            borderColor: withColorAlpha(theme.colors.outline, theme.dark ? 0.22 : 0.14),
            shadowColor: theme.colors.shadow,
          },
        ]}
      >
        {islandWidth > 0 ? (
          <Animated.View
            pointerEvents="none"
            style={[
              styles.activeTabPill,
              {
                width: indicatorMetrics.pillWidth,
                height: indicatorHeight,
                borderRadius: indicatorHeight / 2,
                backgroundColor: withColorAlpha(theme.colors.primary, theme.dark ? 0.2 : 0.1),
                opacity: indicatorOpacity,
                transform: [{ translateX: indicatorTranslateX }, { scaleX: indicatorScaleX }],
              },
            ]}
          />
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
              <IslandTabButton
                key={route.key}
                accessibilityLabel={options?.tabBarAccessibilityLabel ?? `${title} tab`}
                activeIcon={activeIcon}
                compact={compact}
                focused={focused}
                icon={icon}
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

function IslandTabButton({
  accessibilityLabel,
  activeIcon,
  compact,
  focused,
  icon,
  title,
  onLongPress,
  onPress,
}: {
  accessibilityLabel: string;
  activeIcon: TabIconName;
  compact: boolean;
  focused: boolean;
  icon: TabIconName;
  title: string;
  onLongPress: () => void;
  onPress: () => void;
}) {
  const theme = useTheme();
  const focusProgress = useRef(new Animated.Value(focused ? 1 : 0)).current;
  const pressProgress = useRef(new Animated.Value(0)).current;
  const activeColor = theme.colors.primary;
  const inactiveColor = theme.dark ? theme.colors.onSurface : theme.colors.onSurfaceVariant;
  const color = focused ? activeColor : inactiveColor;

  useEffect(() => {
    focusProgress.setValue(focused ? 1 : 0);
  }, [focusProgress, focused]);

  const iconScale = focusProgress.interpolate({
    inputRange: [0, 1],
    outputRange: [1, 1.05],
  });
  const labelOpacity = focusProgress.interpolate({
    inputRange: [0, 1],
    outputRange: [0.72, 1],
  });
  const pressScale = pressProgress.interpolate({
    inputRange: [0, 1],
    outputRange: [1, 0.95],
  });

  const animatePress = (toValue: number) => {
    pressProgress.setValue(toValue);
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
          { transform: [{ scale: pressScale }] },
        ]}
      >
        <Animated.View style={{ transform: [{ scale: iconScale }] }}>
          <MaterialCommunityIcons
            name={focused ? activeIcon : icon}
            size={compact ? 21 : 22}
            color={color}
          />
        </Animated.View>
        <Animated.View style={[styles.tabLabelWrap, { opacity: labelOpacity }]}>
          <Text
            variant="labelSmall"
            numberOfLines={1}
            style={[
              styles.tabLabel,
              compact && styles.tabLabelCompact,
              focused && styles.tabLabelFocused,
              { color },
            ]}
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
    minHeight: 88,
    justifyContent: 'flex-end',
    alignItems: 'center',
    paddingHorizontal: ISLAND_HORIZONTAL_MARGIN,
    paddingTop: tokens.space.xs,
  },
  tabBarIsland: {
    width: '100%',
    minHeight: 58,
    flexDirection: 'row',
    alignItems: 'center',
    borderRadius: 31,
    borderWidth: StyleSheet.hairlineWidth,
    padding: 5,
    elevation: 18,
    shadowOpacity: 0.2,
    shadowRadius: 20,
    shadowOffset: { width: 0, height: 10 },
    overflow: 'hidden',
  },
  tabBarIslandCompact: {
    minHeight: 54,
    borderRadius: 29,
    padding: 4,
  },
  activeTabPill: {
    position: 'absolute',
    left: 0,
    top: 5,
  },
  tabButton: {
    flex: 1,
    minWidth: 0,
    borderRadius: tokens.radius.pill,
    zIndex: 1,
  },
  tabButtonInner: {
    minHeight: 46,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 1,
    borderRadius: tokens.radius.pill,
    paddingHorizontal: 2,
  },
  tabButtonInnerCompact: {
    minHeight: 42,
  },
  tabLabelWrap: {
    width: '100%',
    minWidth: 0,
  },
  tabLabel: {
    width: '100%',
    textAlign: 'center',
    fontWeight: '600',
    fontSize: 9.5,
    lineHeight: 12,
    letterSpacing: 0,
    includeFontPadding: false,
  },
  tabLabelCompact: {
    fontSize: 8.5,
    lineHeight: 11,
  },
  tabLabelFocused: {
    fontWeight: '700',
  },
});
