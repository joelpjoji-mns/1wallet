import { useLedger } from '@1wallet/state';
import { tokens } from '@1wallet/ui';
import { router } from 'expo-router';
import {
  Component,
  memo,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ErrorInfo,
  type ReactNode,
} from 'react';
import {
  InteractionManager,
  StyleSheet,
  View,
  type GestureResponderEvent,
  type LayoutChangeEvent,
  type ViewToken,
} from 'react-native';
import DraggableFlatList from 'react-native-draggable-flatlist';
import {
  Gesture,
  GestureDetector,
  type FlatList as GestureFlatList,
} from 'react-native-gesture-handler';
import { Appbar, Button, FAB, IconButton, Text, useTheme } from 'react-native-paper';
import { openAddRecord as openAddRecordRoute } from '../../src/addRecordNavigation';
import { useAuth } from '../../src/auth';
import { useAppDrawer } from '../../src/components/AppDrawerHost';
import {
  AppMenuAction,
  TAB_BAR_OVERLAY_CLEARANCE,
  TAB_FAB_BOTTOM_OFFSET,
} from '../../src/components/AppKit';
import { NotificationBellButton } from '../../src/components/NotificationBellButton';
import { ReviewQueueButton } from '../../src/components/ReviewQueueButton';
import { UserProfileButton } from '../../src/components/UserProfileButton';
import {
  GESTURE_IGNORE_OFFSET,
  HOME_DRAWER_GESTURE,
  REORDER_GESTURE,
} from '../../src/gestureDefaults';
import { unreadNotificationCount } from '../../src/notifications';
import { HomeWidgetRenderer } from '../../src/widgets/homeWidgetRegistry';
import {
  HOME_WIDGET_META,
  hideHomeWidgetPreference,
  normalizeHomeWidgetPreferences,
  resetHomeWidgetPreferences,
  toStoredHomeWidgetPreferences,
  type HomeWidgetDatePreset,
  type HomeWidgetId,
  type HomeWidgetSize,
} from '../../src/widgets/homeWidgetTypes';

const WIDGET_REORDER_AUTOSCROLL_THRESHOLD = 184;
const WIDGET_REORDER_AUTOSCROLL_SPEED = 920;
const WIDGET_EDGE_SCROLL_STEP = 360;
const WIDGET_EDGE_SCROLL_DELAY_MS = 80;
const WIDGET_EDGE_SCROLL_INTERVAL_MS = 160;
const WIDGET_EDGE_VISIBLE_BUFFER = 1;
const WIDGET_CELL_BOTTOM_PADDING = tokens.space.lg;
const WIDGET_VIEWABILITY_CONFIG = { itemVisiblePercentThreshold: 12 };
const WIDGET_PLACEHOLDER_MIN_HEIGHT: Record<HomeWidgetSize, number> = {
  compact: 116,
  medium: 152,
  wide: 196,
};

export default function Home() {
  const theme = useTheme();
  const { user } = useAuth();
  const { openDrawer } = useAppDrawer();
  const { state, indexes, mutate } = useLedger();
  const [selectedAccountId, setSelectedAccountId] = useState<string | undefined>();
  const [dashboardSelectedAccountId, setDashboardSelectedAccountId] = useState<
    string | undefined
  >();
  const [selectedWidgetId, setSelectedWidgetId] = useState<HomeWidgetId>();
  const [isWidgetDragging, setIsWidgetDragging] = useState(false);
  const selectionDelayRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const widgetListRef = useRef<GestureFlatList<HomeWidgetId>>(null);
  const widgetVisibleRangeRef = useRef({ first: 0, last: 0 });
  const widgetScrollOffsetRef = useRef(0);
  const widgetViewportHeightRef = useRef(0);
  const widgetContentHeightRef = useRef(0);
  const widgetEdgeScrollTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const widgetEdgeScrollDirectionRef = useRef<-1 | 0 | 1>(0);
  const [widgetMeasuredHeights, setWidgetMeasuredHeights] = useState<
    Partial<Record<HomeWidgetId, number>>
  >({});
  const preferences = useMemo(
    () => normalizeHomeWidgetPreferences(state.preferences.homeWidgets),
    [state.preferences.homeWidgets],
  );
  const [widgetOrder, setWidgetOrder] = useState<HomeWidgetId[]>(preferences.order);
  const unreadNotifications = useMemo(() => unreadNotificationCount(state), [state]);
  const { pendingReviewCount, pendingReviewHasWarnings } = useMemo(() => {
    const pendingReviewItems = indexes.captureCandidatesByStatus.get('pending') ?? [];
    return {
      pendingReviewCount: pendingReviewItems.length,
      pendingReviewHasWarnings: pendingReviewItems.some(
        (candidate) => (candidate.warnings?.length ?? 0) > 0,
      ),
    };
  }, [indexes.captureCandidatesByStatus]);
  const drawerSwipeOpenedRef = useRef(false);
  const openDrawerFromSwipe = useCallback(() => {
    if (drawerSwipeOpenedRef.current) return;
    drawerSwipeOpenedRef.current = true;
    openDrawer();
  }, [openDrawer]);

  useEffect(
    () => () => {
      if (selectionDelayRef.current) clearTimeout(selectionDelayRef.current);
      if (widgetEdgeScrollTimerRef.current) clearTimeout(widgetEdgeScrollTimerRef.current);
    },
    [],
  );

  const applySelectedAccount = useCallback((accountId?: string) => {
    setSelectedAccountId(accountId);
    if (selectionDelayRef.current) clearTimeout(selectionDelayRef.current);
    selectionDelayRef.current = setTimeout(() => {
      selectionDelayRef.current = null;
      InteractionManager.runAfterInteractions(() => setDashboardSelectedAccountId(accountId));
    }, 90);
  }, []);

  const stopWidgetEdgeScroll = useCallback(() => {
    widgetEdgeScrollDirectionRef.current = 0;
    if (widgetEdgeScrollTimerRef.current) {
      clearTimeout(widgetEdgeScrollTimerRef.current);
      widgetEdgeScrollTimerRef.current = null;
    }
  }, []);

  const scrollWidgetListBy = useCallback((delta: number) => {
    const maxOffset = Math.max(0, widgetContentHeightRef.current - widgetViewportHeightRef.current);
    const nextOffset = Math.max(0, Math.min(maxOffset, widgetScrollOffsetRef.current + delta));
    if (Math.abs(nextOffset - widgetScrollOffsetRef.current) < 1) return false;
    widgetScrollOffsetRef.current = nextOffset;
    widgetListRef.current?.scrollToOffset({ offset: nextOffset, animated: true });
    return true;
  }, []);

  const scheduleWidgetEdgeScroll = useCallback(
    (direction: -1 | 1) => {
      if (widgetEdgeScrollDirectionRef.current === direction && widgetEdgeScrollTimerRef.current) {
        return;
      }

      if (widgetEdgeScrollTimerRef.current) clearTimeout(widgetEdgeScrollTimerRef.current);
      widgetEdgeScrollDirectionRef.current = direction;

      const scrollAgain = () => {
        if (widgetEdgeScrollDirectionRef.current !== direction) return;
        if (!scrollWidgetListBy(direction * WIDGET_EDGE_SCROLL_STEP)) {
          widgetEdgeScrollDirectionRef.current = 0;
          widgetEdgeScrollTimerRef.current = null;
          return;
        }
        widgetEdgeScrollTimerRef.current = setTimeout(scrollAgain, WIDGET_EDGE_SCROLL_INTERVAL_MS);
      };

      widgetEdgeScrollTimerRef.current = setTimeout(scrollAgain, WIDGET_EDGE_SCROLL_DELAY_MS);
    },
    [scrollWidgetListBy],
  );

  const handleWidgetPlaceholderIndexChange = useCallback(
    (index: number) => {
      const { first, last } = widgetVisibleRangeRef.current;
      const maxOffset = Math.max(
        0,
        widgetContentHeightRef.current - widgetViewportHeightRef.current,
      );

      if (index <= first + WIDGET_EDGE_VISIBLE_BUFFER && widgetScrollOffsetRef.current > 0) {
        scheduleWidgetEdgeScroll(-1);
        return;
      }

      if (index >= last - WIDGET_EDGE_VISIBLE_BUFFER && widgetScrollOffsetRef.current < maxOffset) {
        scheduleWidgetEdgeScroll(1);
        return;
      }

      stopWidgetEdgeScroll();
    },
    [scheduleWidgetEdgeScroll, stopWidgetEdgeScroll],
  );

  const handleWidgetViewableItemsChanged = useRef(
    ({ viewableItems }: { viewableItems: ViewToken<HomeWidgetId>[] }) => {
      const visibleIndexes = viewableItems
        .map((item) => item.index)
        .filter((index): index is number => typeof index === 'number');
      if (!visibleIndexes.length) return;
      widgetVisibleRangeRef.current = {
        first: Math.min(...visibleIndexes),
        last: Math.max(...visibleIndexes),
      };
    },
  ).current;

  const handleWidgetContainerLayout = useCallback(({ layout }: { layout: { height: number } }) => {
    widgetViewportHeightRef.current = layout.height;
  }, []);

  const handleWidgetContentSizeChange = useCallback((_width: number, height: number) => {
    widgetContentHeightRef.current = height;
  }, []);

  const handleWidgetScrollOffsetChange = useCallback((offset: number) => {
    widgetScrollOffsetRef.current = offset;
  }, []);

  const setWidgetMeasuredHeight = useCallback((id: HomeWidgetId, height: number) => {
    setWidgetMeasuredHeights((current) => {
      const previous = current[id];
      if (previous !== undefined && Math.abs(previous - height) < 1) return current;
      return { ...current, [id]: height };
    });
  }, []);

  useEffect(() => {
    setWidgetOrder(preferences.order);
    setSelectedWidgetId((current) =>
      current && preferences.order.includes(current) ? current : undefined,
    );
  }, [preferences.order]);

  const openAddRecord = () => {
    openAddRecordRoute({ accountId: selectedAccountId, entryOrigin: 'fab' });
  };

  const dismissSelectedWidget = useCallback(() => {
    if (!isWidgetDragging) setSelectedWidgetId(undefined);
  }, [isWidgetDragging]);

  const keepSelectedWidgetTouch = useCallback((event: GestureResponderEvent) => {
    event.stopPropagation();
  }, []);

  const setWidgetFilter = useCallback(
    (id: HomeWidgetId, preset: HomeWidgetDatePreset) => {
      void mutate(
        (draft) => {
          const current = normalizeHomeWidgetPreferences(draft.preferences.homeWidgets);
          draft.preferences.homeWidgets = toStoredHomeWidgetPreferences({
            ...current,
            filters: { ...current.filters, [id]: preset },
          });
        },
        { slices: ['preferences'] },
      );
    },
    [mutate],
  );

  const persistWidgetOrder = useCallback(
    async (order: HomeWidgetId[]) => {
      await mutate(
        (draft) => {
          const current = normalizeHomeWidgetPreferences(draft.preferences.homeWidgets);
          const changed =
            order.length !== current.order.length ||
            order.some((id, index) => id !== current.order[index]);
          if (!changed) return;
          draft.preferences.homeWidgets = toStoredHomeWidgetPreferences({
            ...current,
            order,
          });
        },
        { slices: ['preferences'] },
      );
    },
    [mutate],
  );

  const removeWidget = useCallback(
    (id: HomeWidgetId) => {
      setSelectedWidgetId(undefined);
      setWidgetOrder((currentOrder) => currentOrder.filter((widgetId) => widgetId !== id));
      void mutate(
        (draft) => {
          const current = normalizeHomeWidgetPreferences(draft.preferences.homeWidgets);
          draft.preferences.homeWidgets = toStoredHomeWidgetPreferences(
            hideHomeWidgetPreference(current, id),
          );
        },
        { slices: ['preferences'] },
      );
    },
    [mutate],
  );

  const resetDashboardWidgets = useCallback(async () => {
    const resetPreferences = resetHomeWidgetPreferences();
    setSelectedWidgetId(undefined);
    setWidgetOrder(resetPreferences.order);
    await mutate(
      (draft) => {
        draft.preferences.homeWidgets = toStoredHomeWidgetPreferences(resetPreferences);
      },
      { slices: ['preferences'] },
    );
  }, [mutate]);

  const drawerSwipeGesture = useMemo(
    () =>
      Gesture.Pan()
        .enabled(!isWidgetDragging)
        .maxPointers(1)
        .runOnJS(true)
        .minDistance(HOME_DRAWER_GESTURE.slop)
        .activeOffsetX([-GESTURE_IGNORE_OFFSET, HOME_DRAWER_GESTURE.slop])
        .failOffsetX([-HOME_DRAWER_GESTURE.negativeFail, GESTURE_IGNORE_OFFSET])
        .failOffsetY([-HOME_DRAWER_GESTURE.failY, HOME_DRAWER_GESTURE.failY])
        .onBegin(() => {
          drawerSwipeOpenedRef.current = false;
        })
        .onUpdate((event) => {
          if (
            event.translationX > HOME_DRAWER_GESTURE.distance ||
            (event.velocityX > HOME_DRAWER_GESTURE.velocity * 1000 &&
              event.translationX > HOME_DRAWER_GESTURE.slop)
          ) {
            openDrawerFromSwipe();
          }
        })
        .onEnd((event) => {
          if (
            event.translationX > HOME_DRAWER_GESTURE.distance ||
            (event.velocityX > HOME_DRAWER_GESTURE.velocity * 1000 &&
              event.translationX > HOME_DRAWER_GESTURE.slop)
          ) {
            openDrawerFromSwipe();
          }
        }),
    [isWidgetDragging, openDrawerFromSwipe],
  );

  const homeSwipeGesture = drawerSwipeGesture;
  const renderWidgetItem = useCallback(
    ({ item: id, drag, isActive }: { item: HomeWidgetId; drag: () => void; isActive: boolean }) => (
      <HomeWidgetListItem
        id={id}
        size={preferences.sizes[id] ?? HOME_WIDGET_META[id].defaultSize}
        datePreset={preferences.filters[id]}
        isSelected={selectedWidgetId === id || isActive}
        isDragging={isActive}
        selectedAccountId={id === 'accountGrid' ? selectedAccountId : dashboardSelectedAccountId}
        onSelectedAccountChange={id === 'accountGrid' ? applySelectedAccount : undefined}
        onDatePresetChange={setWidgetFilter}
        onHeightChange={setWidgetMeasuredHeight}
        onRemoveWidget={removeWidget}
        onKeepSelectedWidgetTouch={keepSelectedWidgetTouch}
        onReorderLongPress={() => {
          setSelectedWidgetId(id);
          drag();
        }}
      />
    ),
    [
      applySelectedAccount,
      dashboardSelectedAccountId,
      keepSelectedWidgetTouch,
      preferences.filters,
      preferences.sizes,
      removeWidget,
      selectedAccountId,
      selectedWidgetId,
      setWidgetMeasuredHeight,
      setWidgetFilter,
    ],
  );

  return (
    <GestureDetector gesture={homeSwipeGesture}>
      <View
        style={[styles.screen, { backgroundColor: theme.colors.background }]}
        onTouchStart={dismissSelectedWidget}
      >
        <Appbar.Header elevated={false} style={{ backgroundColor: theme.colors.background }}>
          <AppMenuAction onPress={openDrawer} />
          <Appbar.Content title="1Wallet" titleStyle={styles.appTitle} />
          <Appbar.Action
            icon="magnify"
            onPress={() => router.push('/(tabs)/transactions' as never)}
          />
          <ReviewQueueButton
            count={pendingReviewCount}
            hasWarnings={pendingReviewHasWarnings}
            onPress={() => router.push('/review' as never)}
          />
          <NotificationBellButton
            count={unreadNotifications}
            onPress={() => router.push('/notifications' as never)}
          />
          <UserProfileButton
            email={user?.email}
            displayName={user?.displayName}
            photoUrl={user?.photoUrl}
            onPress={() => router.push('/settings' as never)}
          />
        </Appbar.Header>

        <DraggableFlatList
          ref={widgetListRef}
          data={widgetOrder}
          keyExtractor={(id) => id}
          activationDistance={REORDER_GESTURE.activationDistance}
          animationConfig={REORDER_GESTURE.animationConfig}
          autoscrollThreshold={WIDGET_REORDER_AUTOSCROLL_THRESHOLD}
          autoscrollSpeed={WIDGET_REORDER_AUTOSCROLL_SPEED}
          dragItemOverflow={false}
          containerStyle={styles.widgetList}
          contentContainerStyle={styles.content}
          extraData={preferences}
          onContainerLayout={handleWidgetContainerLayout}
          onContentSizeChange={handleWidgetContentSizeChange}
          onPlaceholderIndexChange={handleWidgetPlaceholderIndexChange}
          onScrollOffsetChange={handleWidgetScrollOffsetChange}
          onViewableItemsChanged={handleWidgetViewableItemsChanged}
          viewabilityConfig={WIDGET_VIEWABILITY_CONFIG}
          showsVerticalScrollIndicator={false}
          ListEmptyComponent={
            <View style={styles.emptyDashboard}>
              <Text variant="titleMedium">No dashboard widgets visible</Text>
              <Text variant="bodyMedium" style={{ color: theme.colors.onSurfaceVariant }}>
                Open Widgets to add tiles back.
              </Text>
              <Button mode="contained" icon="plus" onPress={() => router.push('/widgets' as never)}>
                Open widgets
              </Button>
              <Button
                mode="contained-tonal"
                icon="restart"
                onPress={() => void resetDashboardWidgets()}
              >
                Reset layout
              </Button>
            </View>
          }
          onDragBegin={(index) => {
            stopWidgetEdgeScroll();
            const activeWidgetId = widgetOrder[index];
            if (activeWidgetId) setSelectedWidgetId(activeWidgetId);
            setIsWidgetDragging(true);
          }}
          onDragEnd={({ data }) => {
            stopWidgetEdgeScroll();
            setIsWidgetDragging(false);
            setSelectedWidgetId(undefined);
            setWidgetOrder(data);
            void persistWidgetOrder(data);
          }}
          onRelease={stopWidgetEdgeScroll}
          onScrollBeginDrag={dismissSelectedWidget}
          renderPlaceholder={({ item }) => {
            const placeholderSize = preferences.sizes[item] ?? HOME_WIDGET_META[item].defaultSize;
            const measuredCellHeight = widgetMeasuredHeights[item];
            const placeholderHeight = Math.max(
              WIDGET_PLACEHOLDER_MIN_HEIGHT[placeholderSize],
              (measuredCellHeight ?? 0) - WIDGET_CELL_BOTTOM_PADDING,
            );
            return (
              <View collapsable={false} pointerEvents="none" style={styles.widgetCell}>
                <View
                  style={[
                    styles.widgetPlaceholder,
                    { height: placeholderHeight },
                    {
                      backgroundColor: theme.colors.surfaceVariant,
                      borderColor: theme.colors.outlineVariant,
                    },
                  ]}
                />
              </View>
            );
          }}
          renderItem={renderWidgetItem}
        />

        <FAB
          icon="plus"
          style={[styles.fab, { backgroundColor: theme.colors.primaryContainer }]}
          color={theme.colors.onPrimaryContainer}
          onPress={openAddRecord}
        />
      </View>
    </GestureDetector>
  );
}

interface HomeWidgetListItemProps {
  id: HomeWidgetId;
  size: HomeWidgetSize;
  datePreset: HomeWidgetDatePreset;
  isSelected: boolean;
  isDragging: boolean;
  selectedAccountId?: string;
  onSelectedAccountChange?: (accountId?: string) => void;
  onDatePresetChange: (id: HomeWidgetId, preset: HomeWidgetDatePreset) => void;
  onHeightChange: (id: HomeWidgetId, height: number) => void;
  onRemoveWidget: (id: HomeWidgetId) => void;
  onKeepSelectedWidgetTouch: (event: GestureResponderEvent) => void;
  onReorderLongPress: () => void;
}

const HomeWidgetListItem = memo(
  function HomeWidgetListItem({
    id,
    size,
    datePreset,
    isSelected,
    isDragging,
    selectedAccountId,
    onSelectedAccountChange,
    onDatePresetChange,
    onHeightChange,
    onRemoveWidget,
    onKeepSelectedWidgetTouch,
    onReorderLongPress,
  }: HomeWidgetListItemProps) {
    const theme = useTheme();
    const handleDatePresetChange = useCallback(
      (preset: HomeWidgetDatePreset) => onDatePresetChange(id, preset),
      [id, onDatePresetChange],
    );
    const handleLayout = useCallback(
      (event: LayoutChangeEvent) => onHeightChange(id, event.nativeEvent.layout.height),
      [id, onHeightChange],
    );
    const errorBoundaryColors = useMemo(
      () => ({
        backgroundColor: theme.colors.errorContainer,
        borderColor: theme.colors.error,
        textColor: theme.colors.onErrorContainer,
      }),
      [theme.colors.error, theme.colors.errorContainer, theme.colors.onErrorContainer],
    );

    return (
      <View
        collapsable={false}
        onLayout={handleLayout}
        style={styles.widgetCell}
        onTouchStart={isSelected ? onKeepSelectedWidgetTouch : undefined}
      >
        <View
          style={[
            styles.widgetFrame,
            {
              borderColor: isSelected ? theme.colors.primary : 'transparent',
              backgroundColor: isDragging ? theme.colors.primaryContainer : 'transparent',
            },
          ]}
        >
          <HomeWidgetErrorBoundary
            id={id}
            title={HOME_WIDGET_META[id].title}
            colors={errorBoundaryColors}
            onRemoveWidget={onRemoveWidget}
          >
            <HomeWidgetRenderer
              id={id}
              size={size}
              datePreset={datePreset}
              onDatePresetChange={handleDatePresetChange}
              selectedAccountId={selectedAccountId}
              onSelectedAccountChange={onSelectedAccountChange}
              onReorderLongPress={onReorderLongPress}
            />
          </HomeWidgetErrorBoundary>
        </View>
        {isSelected ? (
          <IconButton
            accessibilityLabel={`Remove ${HOME_WIDGET_META[id].title} from Home`}
            icon="minus"
            mode="contained"
            size={18}
            iconColor={theme.colors.onErrorContainer}
            containerColor={theme.colors.errorContainer}
            style={styles.removeWidgetButton}
            onPress={() => onRemoveWidget(id)}
          />
        ) : null}
      </View>
    );
  },
  (previous, next) =>
    previous.id === next.id &&
    previous.size === next.size &&
    previous.datePreset === next.datePreset &&
    previous.isSelected === next.isSelected &&
    previous.isDragging === next.isDragging &&
    previous.selectedAccountId === next.selectedAccountId &&
    previous.onSelectedAccountChange === next.onSelectedAccountChange &&
    previous.onDatePresetChange === next.onDatePresetChange &&
    previous.onHeightChange === next.onHeightChange &&
    previous.onRemoveWidget === next.onRemoveWidget &&
    previous.onKeepSelectedWidgetTouch === next.onKeepSelectedWidgetTouch &&
    previous.onReorderLongPress === next.onReorderLongPress,
);

type HomeWidgetErrorBoundaryProps = {
  children: ReactNode;
  colors: { backgroundColor: string; borderColor: string; textColor: string };
  id: HomeWidgetId;
  title: string;
  onRemoveWidget: (id: HomeWidgetId) => void;
};

class HomeWidgetErrorBoundary extends Component<
  HomeWidgetErrorBoundaryProps,
  { hasError: boolean }
> {
  override state = { hasError: false };

  static getDerivedStateFromError() {
    return { hasError: true };
  }

  override componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('Home widget failed', this.props.id, error, info.componentStack);
  }

  override componentDidUpdate(previousProps: Readonly<HomeWidgetErrorBoundaryProps>) {
    if (previousProps.id !== this.props.id && this.state.hasError) {
      this.setState({ hasError: false });
    }
  }

  override render() {
    if (!this.state.hasError) return this.props.children;

    return (
      <View
        style={[
          styles.widgetError,
          {
            backgroundColor: this.props.colors.backgroundColor,
            borderColor: this.props.colors.borderColor,
          },
        ]}
      >
        <Text variant="titleMedium" style={{ color: this.props.colors.textColor }}>
          {this.props.title} could not load
        </Text>
        <View style={styles.widgetErrorActions}>
          <Button compact mode="contained-tonal" onPress={() => this.setState({ hasError: false })}>
            Try again
          </Button>
          <Button compact mode="text" onPress={() => this.props.onRemoveWidget(this.props.id)}>
            Hide
          </Button>
        </View>
      </View>
    );
  }
}

const styles = StyleSheet.create({
  screen: { flex: 1 },
  appTitle: { fontSize: 20, fontWeight: '700' },
  widgetList: { flex: 1 },
  content: { padding: tokens.space.lg, paddingBottom: 112 },
  widgetCell: { paddingBottom: tokens.space.lg },
  widgetFrame: {
    borderRadius: tokens.radius.md + 2,
    borderWidth: 2,
    overflow: 'visible',
  },
  widgetPlaceholder: {
    borderRadius: tokens.radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    opacity: 0.34,
  },
  widgetError: {
    minHeight: 128,
    borderRadius: tokens.radius.md,
    borderWidth: StyleSheet.hairlineWidth,
    gap: tokens.space.md,
    justifyContent: 'center',
    padding: tokens.space.lg,
  },
  widgetErrorActions: { flexDirection: 'row', flexWrap: 'wrap', gap: tokens.space.sm },
  removeWidgetButton: {
    position: 'absolute',
    top: -8,
    right: -8,
    zIndex: 20,
    elevation: 20,
  },
  emptyDashboard: { alignItems: 'center', gap: tokens.space.sm, padding: tokens.space.xl },
  fab: {
    position: 'absolute',
    right: tokens.space.lg,
    bottom: TAB_BAR_OVERLAY_CLEARANCE + TAB_FAB_BOTTOM_OFFSET,
    zIndex: 40,
    elevation: 40,
    width: 56,
    height: 56,
    borderRadius: tokens.radius.pill,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
