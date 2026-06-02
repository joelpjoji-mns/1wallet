import { router, usePathname } from 'expo-router';
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import { Alert, StyleSheet, View, useWindowDimensions } from 'react-native';
import { Drawer } from 'react-native-drawer-layout';
import { useTheme } from 'react-native-paper';
import { useAuth } from '../auth';
import { withColorAlpha } from '../colorAlpha';
import { EDGE_DRAWER_GESTURE } from '../gestureDefaults';
import { useWalletSignOut } from '../useWalletSignOut';
import { useBackLayer } from './AppBackLayer';
import { AppDrawer } from './AppDrawer';

type AppDrawerContextValue = {
  openDrawer: () => void;
  closeDrawer: () => void;
};

const AppDrawerContext = createContext<AppDrawerContextValue | undefined>(undefined);
const DRAWER_STANDARD_WIDTH = 304;
const DRAWER_MAX_WIDTH = 360;
const DRAWER_WIDTH_RATIO = 0.8;

export function AppDrawerHost({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const theme = useTheme();
  const { width: windowWidth } = useWindowDimensions();
  const { user } = useAuth();
  const { signOutWallet } = useWalletSignOut();
  const drawerEnabled = Boolean(user) && isDrawerEnabledPath(pathname);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const drawerWidth = Math.min(
    Math.max(DRAWER_STANDARD_WIDTH, Math.round(windowWidth * DRAWER_WIDTH_RATIO)),
    DRAWER_MAX_WIDTH,
  );

  const closeDrawer = useCallback(() => {
    setDrawerOpen(false);
  }, []);
  const openDrawer = useCallback(() => {
    if (!drawerEnabled) return;
    setDrawerOpen(true);
  }, [drawerEnabled]);

  useEffect(() => {
    if (!drawerEnabled) closeDrawer();
  }, [closeDrawer, drawerEnabled]);

  const handleSignOut = useCallback(async () => {
    closeDrawer();
    try {
      await signOutWallet();
      router.replace('/login' as never);
    } catch (err) {
      Alert.alert('Sign-out paused', drawerSignOutErrorMessage(err));
    }
  }, [closeDrawer, signOutWallet]);

  useBackLayer(drawerOpen, () => {
    closeDrawer();
    return true;
  });

  const handleNativeOpen = useCallback(() => {
    if (drawerEnabled) setDrawerOpen(true);
  }, [drawerEnabled]);
  const handleNativeClose = useCallback(() => setDrawerOpen(false), []);
  const renderDrawerContent = useCallback(
    () =>
      drawerEnabled && drawerOpen ? (
        <AppDrawer
          email={user?.email}
          displayName={user?.displayName}
          photoUrl={user?.photoUrl}
          currentPath={pathname}
          onDismiss={closeDrawer}
          onSignOut={() => void handleSignOut()}
        />
      ) : null,
    [
      closeDrawer,
      drawerEnabled,
      drawerOpen,
      handleSignOut,
      pathname,
      user?.displayName,
      user?.email,
      user?.photoUrl,
    ],
  );
  const value = useMemo(() => ({ openDrawer, closeDrawer }), [closeDrawer, openDrawer]);

  return (
    <AppDrawerContext.Provider value={value}>
      <Drawer
        drawerPosition="left"
        drawerStyle={[
          styles.drawer,
          {
            width: drawerWidth,
            backgroundColor: theme.colors.elevation.level1,
            borderRightColor: withColorAlpha(theme.colors.outline, theme.dark ? 0.24 : 0.16),
          },
        ]}
        drawerType="front"
        keyboardDismissMode="on-drag"
        onClose={handleNativeClose}
        onOpen={handleNativeOpen}
        open={drawerEnabled && drawerOpen}
        overlayAccessibilityLabel="Close navigation"
        overlayStyle={{
          backgroundColor: withColorAlpha(theme.colors.scrim, theme.dark ? 0.64 : 0.46),
        }}
        renderDrawerContent={renderDrawerContent}
        swipeEdgeWidth={EDGE_DRAWER_GESTURE.startWidth}
        swipeEnabled={drawerEnabled}
        swipeMinDistance={EDGE_DRAWER_GESTURE.distance}
        swipeMinVelocity={EDGE_DRAWER_GESTURE.velocity * 1000}
        style={styles.host}
      >
        <View style={styles.host}>{children}</View>
      </Drawer>
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

const styles = StyleSheet.create({
  host: { flex: 1 },
  drawer: { borderRightWidth: StyleSheet.hairlineWidth },
});
