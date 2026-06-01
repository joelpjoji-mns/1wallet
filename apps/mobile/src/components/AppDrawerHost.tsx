import { router, usePathname } from 'expo-router';
import {
    createContext,
    useCallback,
    useContext,
    useEffect,
    useMemo,
    useRef,
    useState,
    type ReactNode,
} from 'react';
import { Alert, PanResponder, StyleSheet, View, type PanResponderGestureState } from 'react-native';
import { Portal } from 'react-native-paper';
import { useAuth } from '../auth';
import { EDGE_DRAWER_GESTURE } from '../gestureDefaults';
import { useWalletSignOut } from '../useWalletSignOut';
import { useBackLayer } from './AppBackLayer';
import { AppDrawer } from './AppDrawer';

type AppDrawerContextValue = {
  openDrawer: () => void;
  closeDrawer: () => void;
};

const AppDrawerContext = createContext<AppDrawerContextValue | undefined>(undefined);
const DRAWER_CLOSE_UNMOUNT_DELAY_MS = 260;

export function AppDrawerHost({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const { user } = useAuth();
  const { signOutWallet } = useWalletSignOut();
  const drawerEnabled = Boolean(user) && isDrawerEnabledPath(pathname);
  const [drawerMounted, setDrawerMounted] = useState(false);
  const [drawerVisible, setDrawerVisible] = useState(false);
  const drawerVisibleRef = useRef(drawerVisible);
  const closeTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const clearCloseTimer = useCallback(() => {
    if (!closeTimerRef.current) return;
    clearTimeout(closeTimerRef.current);
    closeTimerRef.current = null;
  }, []);

  const finishDrawerClose = useCallback(() => {
    clearCloseTimer();
    setDrawerVisible(false);
    setDrawerMounted(false);
  }, [clearCloseTimer]);

  const closeDrawer = useCallback(() => {
    setDrawerVisible(false);
    clearCloseTimer();
    closeTimerRef.current = setTimeout(finishDrawerClose, DRAWER_CLOSE_UNMOUNT_DELAY_MS);
  }, [clearCloseTimer, finishDrawerClose]);
  const openDrawer = useCallback(() => {
    if (!drawerEnabled) return;
    clearCloseTimer();
    setDrawerMounted(true);
    setDrawerVisible(true);
  }, [clearCloseTimer, drawerEnabled]);

  useEffect(() => {
    drawerVisibleRef.current = drawerVisible || drawerMounted;
  }, [drawerMounted, drawerVisible]);

  useEffect(() => {
    if (!drawerEnabled) finishDrawerClose();
  }, [drawerEnabled, finishDrawerClose]);

  useEffect(() => () => clearCloseTimer(), [clearCloseTimer]);

  const drawerRailResponder = useMemo(
    () =>
      PanResponder.create({
        onStartShouldSetPanResponderCapture: (event) =>
          drawerEnabled &&
          !drawerVisibleRef.current &&
          event.nativeEvent.pageX <= EDGE_DRAWER_GESTURE.captureWidth,
        onStartShouldSetPanResponder: (event) =>
          drawerEnabled &&
          !drawerVisibleRef.current &&
          event.nativeEvent.pageX <= EDGE_DRAWER_GESTURE.captureWidth,
        onMoveShouldSetPanResponderCapture: (_event, gesture) =>
          drawerEnabled && !drawerVisibleRef.current && shouldStartDrawerOpenGesture(gesture),
        onMoveShouldSetPanResponder: (_event, gesture) =>
          drawerEnabled && !drawerVisibleRef.current && shouldStartDrawerOpenGesture(gesture),
        onPanResponderRelease: (_event, gesture) => {
          if (shouldCompleteDrawerOpenGesture(gesture)) openDrawer();
        },
        onPanResponderTerminationRequest: () => false,
        onShouldBlockNativeResponder: () => false,
      }),
    [drawerEnabled, openDrawer],
  );

  const handleSignOut = useCallback(async () => {
    closeDrawer();
    try {
      await signOutWallet();
      router.replace('/login' as never);
    } catch (err) {
      Alert.alert('Sign-out paused', drawerSignOutErrorMessage(err));
    }
  }, [closeDrawer, signOutWallet]);

  useBackLayer(drawerMounted, () => {
    closeDrawer();
    return true;
  });

  const value = useMemo(() => ({ openDrawer, closeDrawer }), [closeDrawer, openDrawer]);

  return (
    <AppDrawerContext.Provider value={value}>
      <View style={styles.host}>{children}</View>
      {drawerEnabled ? (
        <Portal>
          <View
            collapsable={false}
            pointerEvents={drawerMounted ? 'none' : 'auto'}
            style={styles.drawerGestureRail}
            {...drawerRailResponder.panHandlers}
          />
        </Portal>
      ) : null}
      {drawerEnabled && drawerMounted ? (
        <AppDrawer
          visible={drawerVisible}
          email={user?.email}
          displayName={user?.displayName}
          photoUrl={user?.photoUrl}
          currentPath={pathname}
          onDismiss={closeDrawer}
          onClosed={finishDrawerClose}
          onSignOut={() => void handleSignOut()}
        />
      ) : null}
    </AppDrawerContext.Provider>
  );
}

export function useAppDrawer() {
  const context = useContext(AppDrawerContext);
  if (!context) throw new Error('useAppDrawer must be used inside AppDrawerHost');
  return context;
}

export function useOptionalAppDrawer() {
  return useContext(AppDrawerContext);
}

function isDrawerEnabledPath(pathname: string | null | undefined): boolean {
  const path = pathname ?? '';
  return !['/login', '/signup', '/onboarding', '/permissions-setup'].includes(path);
}

function drawerSignOutErrorMessage(err: unknown): string {
  return err instanceof Error && err.message
    ? err.message
    : 'Could not back up and sign out. Your wallet stayed on this device.';
}

function shouldStartDrawerOpenGesture(
  gesture: PanResponderGestureState,
  startLimit = EDGE_DRAWER_GESTURE.startWidth,
): boolean {
  const startX = gesture.x0 > 0 ? gesture.x0 : gesture.moveX - gesture.dx;
  const horizontal =
    gesture.dx > EDGE_DRAWER_GESTURE.slop &&
    Math.abs(gesture.dx) > Math.abs(gesture.dy) * EDGE_DRAWER_GESTURE.verticalRatio;
  return startX <= startLimit && horizontal;
}

function shouldCompleteDrawerOpenGesture(gesture: PanResponderGestureState): boolean {
  return (
    gesture.dx > EDGE_DRAWER_GESTURE.distance ||
    (gesture.vx > EDGE_DRAWER_GESTURE.velocity && gesture.dx > EDGE_DRAWER_GESTURE.slop)
  );
}

const styles = StyleSheet.create({
  host: { flex: 1 },
  drawerGestureRail: {
    position: 'absolute',
    left: 0,
    top: 0,
    bottom: 0,
    width: EDGE_DRAWER_GESTURE.captureWidth,
    zIndex: 20,
    elevation: 20,
    backgroundColor: 'transparent',
  },
});
