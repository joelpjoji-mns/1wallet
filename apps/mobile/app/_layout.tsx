import type { ThemePreference } from '@1wallet/ledger';
import { LedgerProvider, useLedger } from '@1wallet/state';
import { Stack } from 'expo-router';
import * as SplashScreen from 'expo-splash-screen';
import {
  Component,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ErrorInfo,
  type ReactNode,
} from 'react';
import {
  AppState,
  Button,
  InteractionManager,
  StatusBar,
  StyleSheet,
  Text,
  View,
  useColorScheme,
} from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { PaperProvider } from 'react-native-paper';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { syncAndroidHomeWidgets } from '../src/androidHomeWidgets';
import { syncAndroidSmsCapturePreferences } from '../src/androidSmsCapture';
import { AuthProvider, useAuth } from '../src/auth';
import { LedgerCloudSyncProvider } from '../src/cloudSync/LedgerCloudSyncProvider';
import { AppBackLayerProvider } from '../src/components/AppBackLayer';
import { AppDrawerHost } from '../src/components/AppDrawerHost';
import { BrandedLoadingState, RecoveryState } from '../src/components/Brand';
import { useMaterial3Theme } from '../src/material3Theme';
import {
  addNativeNotificationResponseListener,
  deliverNativeNotificationInbox,
} from '../src/nativeNotifications';
import { normalizeNotificationPreferences } from '../src/notifications';
import { ledgerStore } from '../src/storage';
import { runMobileStorageMaintenance } from '../src/storageMaintenance';
import {
  DEFAULT_THEME_SOURCE_COLOR,
  createAppPaperTheme,
  normalizeThemeAccentPreference,
  resolveThemeMode,
} from '../src/theme';
import {
  loadCachedThemePreference,
  saveCachedThemePreference,
} from '../src/themePreferenceStorage';
import { AppUpdateProvider } from '../src/updates/AppUpdateProvider';

const SCREEN_TRANSITION_DURATION_MS = 0;
const ANDROID_WIDGET_SYNC_DEBOUNCE_MS = 3000;
const APP_RESUME_REFRESH_SETTLE_MS = 1500;
const STARTUP_LOADING_SHOW_DELAY_MS = 1200;
const STARTUP_READY_STAGE_MS = 80;
const STARTUP_RECOVERY_TIMEOUT_MS = 15000;
const MODAL_SCREEN_OPTIONS = {
  headerShown: false,
  presentation: 'modal' as const,
  animation: 'none' as const,
  animationDuration: SCREEN_TRANSITION_DURATION_MS,
  animationTypeForReplace: 'push' as const,
  gestureDirection: 'vertical' as const,
};

const ADD_RECORD_SCREEN_OPTIONS = {
  headerShown: false,
  presentation: 'transparentModal' as const,
  animation: 'none' as const,
  animationDuration: 0,
  animationTypeForReplace: 'push' as const,
  contentStyle: { backgroundColor: 'transparent' },
  gestureEnabled: false,
};

type StartupStage = 'session' | 'wallet' | 'sync';

void SplashScreen.preventAutoHideAsync();

export default function RootLayout() {
  return (
    <GestureHandlerRootView style={styles.root}>
      <AppErrorBoundary>
        <SafeAreaProvider>
          <AuthProvider>
            <LedgerProvider store={ledgerStore}>
              <LedgerCloudSyncProvider>
                <AppUpdateProvider>
                  <ThemedNavigation />
                </AppUpdateProvider>
              </LedgerCloudSyncProvider>
            </LedgerProvider>
          </AuthProvider>
        </SafeAreaProvider>
      </AppErrorBoundary>
    </GestureHandlerRootView>
  );
}

function ThemedNavigation() {
  const systemScheme = useColorScheme();
  const { state, ready, error: ledgerError, reload, reset } = useLedger();
  const { loading: authLoading, error: authError, retry: retryAuth } = useAuth();
  const [startupRecoveryTimedOut, setStartupRecoveryTimedOut] = useState(false);
  const [startupRetryKey, setStartupRetryKey] = useState(0);
  const [layoutReady, setLayoutReady] = useState(false);
  const [cachedThemeLoaded, setCachedThemeLoaded] = useState(false);
  const [cachedThemePreference, setCachedThemePreference] = useState<ThemePreference | undefined>();
  const splashHiddenRef = useRef(false);
  const startup = useStartupSequence({
    authLoading,
    disabled: Boolean(authError || ledgerError),
    hasLocalWalletData: state.accounts.length > 0,
    walletReady: ready,
  });
  const accentPreference = normalizeThemeAccentPreference(state.preferences.themeAccent);
  const materialThemeOptions = useMemo(
    () => ({
      fallbackSourceColor: DEFAULT_THEME_SOURCE_COLOR,
      sourceColor: accentPreference.source === 'custom' ? accentPreference.customColor : undefined,
      colorFidelity: true,
    }),
    [accentPreference.customColor, accentPreference.source],
  );
  const { theme: materialTheme } = useMaterial3Theme(materialThemeOptions);
  const themePreference = ready ? state.preferences.theme : cachedThemePreference;
  const mode = resolveThemeMode(
    themePreference,
    systemScheme === 'light' || systemScheme === 'dark' ? systemScheme : null,
  );
  const theme = useMemo(
    () =>
      createAppPaperTheme(mode, materialTheme, {
        customAccentColor:
          accentPreference.source === 'custom' ? accentPreference.customColor : undefined,
      }),
    [accentPreference.customColor, accentPreference.source, materialTheme, mode],
  );
  const startupPending = !authError && !ledgerError && startup.pending;
  const startupRecoveryActive = startupPending && startupRecoveryTimedOut;

  const hideNativeSplash = useCallback(() => {
    if (splashHiddenRef.current) return;
    splashHiddenRef.current = true;
    requestAnimationFrame(() => {
      void SplashScreen.hideAsync().catch(() => undefined);
    });
  }, []);

  const handleRootLayout = useCallback(() => {
    setLayoutReady(true);
  }, []);

  useEffect(() => {
    let mounted = true;
    void loadCachedThemePreference()
      .then((preference) => {
        if (mounted) setCachedThemePreference(preference);
      })
      .finally(() => {
        if (mounted) setCachedThemeLoaded(true);
      });
    return () => {
      mounted = false;
    };
  }, []);

  useEffect(() => {
    if (!ready) return;
    setCachedThemePreference(state.preferences.theme);
    void saveCachedThemePreference(state.preferences.theme).catch(() => undefined);
  }, [ready, state.preferences.theme]);

  useEffect(() => {
    if (!layoutReady || !cachedThemeLoaded) return;
    hideNativeSplash();
  }, [cachedThemeLoaded, hideNativeSplash, layoutReady]);

  useEffect(() => {
    if (!startupPending) {
      setStartupRecoveryTimedOut(false);
      return;
    }

    const timeout = setTimeout(() => {
      setStartupRecoveryTimedOut(true);
    }, STARTUP_RECOVERY_TIMEOUT_MS);
    return () => clearTimeout(timeout);
  }, [startupPending, startupRetryKey]);

  const retryStartup = useCallback(() => {
    setStartupRecoveryTimedOut(false);
    setStartupRetryKey((value) => value + 1);
    retryAuth();
    void reload();
  }, [reload, retryAuth]);

  return (
    <PaperProvider theme={theme}>
      <View
        onLayout={handleRootLayout}
        style={[styles.appShell, { backgroundColor: theme.colors.background }]}
      >
        <StatusBar
          barStyle={theme.dark ? 'light-content' : 'dark-content'}
          backgroundColor={theme.colors.background}
          translucent={false}
        />
        <LedgerPersistenceLifecycle />
        <LedgerUserLinkLifecycle />
        <MobileStorageMaintenance enabled={startup.complete && !authError && !ledgerError} />
        <AndroidSmsCapturePreferenceSync />
        <AndroidHomeWidgetSync />
        <NativeNotificationSync />
        {authError ? (
          <RecoveryState
            title="Sign-in needs attention"
            body={authError}
            actionLabel="Try again"
            onAction={retryAuth}
          />
        ) : ledgerError ? (
          <RecoveryState
            title="Wallet data needs attention"
            body={ledgerError}
            actionLabel="Try again"
            onAction={() => void reload()}
            secondaryActionLabel="Reset local wallet"
            onSecondaryAction={() => void reset()}
          />
        ) : startupRecoveryActive ? (
          <RecoveryState
            title="Startup needs attention"
            body="1wallet is taking longer than expected to prepare your session and wallet."
            actionLabel="Try again"
            onAction={retryStartup}
            secondaryActionLabel="Reset local wallet"
            onSecondaryAction={() => void reset()}
          />
        ) : startup.showLoader ? (
          <BrandedLoadingState stage={startup.stage} message={startup.message} />
        ) : !startup.complete ? (
          <BrandedLoadingState stage={startup.stage} message={startup.message} />
        ) : (
          <AppBackLayerProvider>
            <AppDrawerHost>
              <Stack
                screenOptions={{
                  headerStyle: { backgroundColor: theme.colors.background },
                  headerTitleStyle: { color: theme.colors.onSurface, fontWeight: '600' },
                  headerTintColor: theme.colors.onSurface,
                  contentStyle: { backgroundColor: theme.colors.background },
                  animation: 'none',
                  animationDuration: SCREEN_TRANSITION_DURATION_MS,
                  animationTypeForReplace: 'push',
                  fullScreenGestureEnabled: true,
                  gestureEnabled: true,
                }}
              >
                <Stack.Screen name="index" options={{ headerShown: false }} />
                <Stack.Screen name="login" options={{ headerShown: false }} />
                <Stack.Screen name="signup" options={{ headerShown: false }} />
                <Stack.Screen name="onboarding" options={{ headerShown: false }} />
                <Stack.Screen name="permissions-setup" options={{ headerShown: false }} />
                <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
                <Stack.Screen name="settings" options={{ headerShown: false }} />
                <Stack.Screen name="sync" options={{ headerShown: false }} />
                <Stack.Screen name="updates" options={{ headerShown: false }} />
                <Stack.Screen name="device-permissions" options={{ headerShown: false }} />
                <Stack.Screen name="currencies" options={{ headerShown: false }} />
                <Stack.Screen name="notifications" options={{ headerShown: false }} />
                <Stack.Screen name="categories" options={{ headerShown: false }} />
                <Stack.Screen name="widgets" options={{ headerShown: false }} />
                <Stack.Screen name="reports" options={{ headerShown: false }} />
                <Stack.Screen name="imports" options={{ headerShown: false }} />
                <Stack.Screen name="data-backup" options={{ headerShown: false }} />
                <Stack.Screen name="auto-capture" options={{ headerShown: false }} />
                <Stack.Screen name="import-wallet-csv" options={{ headerShown: false }} />
                <Stack.Screen name="import-sms" options={{ headerShown: false }} />
                <Stack.Screen name="cards" options={{ headerShown: false }} />
                <Stack.Screen name="loans" options={{ headerShown: false }} />
                <Stack.Screen name="loans/new" options={{ headerShown: false }} />
                <Stack.Screen name="loans/forecast" options={{ headerShown: false }} />
                <Stack.Screen name="loans/past" options={{ headerShown: false }} />
                <Stack.Screen name="loans/[id]" options={{ headerShown: false }} />
                <Stack.Screen name="loans/[id]/edit" options={{ headerShown: false }} />
                <Stack.Screen name="recurring" options={{ headerShown: false }} />
                <Stack.Screen name="recurring/new" options={{ headerShown: false }} />
                <Stack.Screen name="recurring/past" options={{ headerShown: false }} />
                <Stack.Screen name="recurring/[id]" options={{ headerShown: false }} />
                <Stack.Screen name="recurring/[id]/edit" options={{ headerShown: false }} />
                <Stack.Screen name="add" options={ADD_RECORD_SCREEN_OPTIONS} />
                <Stack.Screen name="review" options={{ headerShown: false }} />
                <Stack.Screen name="capture/[id]" options={{ headerShown: false }} />
                <Stack.Screen name="transaction/[id]" options={{ headerShown: false }} />
                <Stack.Screen name="account/[id]" options={{ headerShown: false }} />
                <Stack.Screen name="account/new" options={MODAL_SCREEN_OPTIONS} />
                <Stack.Screen name="budgets/new" options={MODAL_SCREEN_OPTIONS} />
                <Stack.Screen name="goals/new" options={MODAL_SCREEN_OPTIONS} />
                <Stack.Screen name="+not-found" options={{ headerShown: false }} />
              </Stack>
            </AppDrawerHost>
          </AppBackLayerProvider>
        )}
      </View>
    </PaperProvider>
  );
}

function MobileStorageMaintenance({ enabled }: { enabled: boolean }) {
  const startedRef = useRef(false);

  useEffect(() => {
    if (!enabled || startedRef.current) return;
    startedRef.current = true;
    const timeout = setTimeout(() => {
      InteractionManager.runAfterInteractions(() => {
        void runMobileStorageMaintenance()
          .then((summary) => {
            console.info('1Wallet storage maintenance completed', summary);
          })
          .catch((error) => {
            console.warn('1Wallet storage maintenance failed', error);
          });
      });
    }, 1800);
    return () => clearTimeout(timeout);
  }, [enabled]);

  return null;
}

function useStartupSequence({
  authLoading,
  disabled,
  hasLocalWalletData,
  walletReady,
}: {
  authLoading: boolean;
  disabled: boolean;
  hasLocalWalletData: boolean;
  walletReady: boolean;
}) {
  const pendingStage = startupStageForPending({ authLoading, hasLocalWalletData, walletReady });
  const rawComplete = disabled || (walletReady && (hasLocalWalletData || !authLoading));
  const [displayComplete, setDisplayComplete] = useState(rawComplete);
  const [showLoader, setShowLoader] = useState(false);
  const [stage, setStage] = useState<StartupStage>(pendingStage);

  useEffect(() => {
    if (disabled) {
      setStage('sync');
      setShowLoader(false);
      setDisplayComplete(true);
      return;
    }

    if (!rawComplete) {
      setDisplayComplete(false);
      setStage((current) => maxStartupStage(current, pendingStage));
      if (showLoader) return;

      const timeout = setTimeout(() => {
        setShowLoader(true);
      }, STARTUP_LOADING_SHOW_DELAY_MS);
      return () => clearTimeout(timeout);
    }

    setStage('sync');
    if (!showLoader) {
      setDisplayComplete(true);
      return;
    }

    const timeout = setTimeout(() => {
      setShowLoader(false);
      setDisplayComplete(true);
    }, STARTUP_READY_STAGE_MS);
    return () => clearTimeout(timeout);
  }, [disabled, pendingStage, rawComplete, showLoader]);

  return {
    complete: displayComplete,
    pending: !disabled && !rawComplete,
    showLoader: showLoader && !displayComplete,
    stage,
    message: startupStageMessage(stage),
  };
}

function startupStageForPending({
  authLoading,
  hasLocalWalletData,
  walletReady,
}: {
  authLoading: boolean;
  hasLocalWalletData: boolean;
  walletReady: boolean;
}): StartupStage {
  if (authLoading && !hasLocalWalletData && !walletReady) return 'session';
  if (!walletReady) return 'wallet';
  if (authLoading && !hasLocalWalletData) return 'session';
  return 'sync';
}

function maxStartupStage(left: StartupStage, right: StartupStage): StartupStage {
  return STARTUP_STAGE_INDEX[left] >= STARTUP_STAGE_INDEX[right] ? left : right;
}

function startupStageMessage(stage: StartupStage) {
  if (stage === 'session') return 'Checking your secure session';
  if (stage === 'wallet') return 'Restoring your wallet';
  return 'Wallet ready';
}

const STARTUP_STAGE_INDEX: Record<StartupStage, number> = {
  session: 0,
  wallet: 1,
  sync: 2,
};

function NativeNotificationSync() {
  const { state, ready, mutate } = useLedger();

  useEffect(() => addNativeNotificationResponseListener(), []);

  useEffect(() => {
    if (!ready) return;
    let cancelled = false;
    void deliverNativeNotificationInbox(state)
      .then((deliveredIds) => {
        if (cancelled || deliveredIds.length === 0) return;
        void mutate(
          (draft) => {
            const settings = normalizeNotificationPreferences(draft.preferences.notifications);
            const nativeDeliveredIds = Array.from(
              new Set([...settings.nativeDeliveredIds, ...deliveredIds]),
            ).slice(-200);
            draft.preferences.notifications = { ...settings, nativeDeliveredIds };
          },
          { slices: ['preferences'] },
        );
      })
      .catch(() => undefined);

    return () => {
      cancelled = true;
    };
  }, [mutate, ready, state]);

  return null;
}

function LedgerUserLinkLifecycle() {
  const { user } = useAuth();
  const { state, ready, mutate } = useLedger();
  const userId = user?.id;

  useEffect(() => {
    if (!ready || !userId || state.userId === userId) return;
    void mutate((draft) => {
      draft.userId = userId;
    }).catch(() => undefined);
  }, [mutate, ready, state.userId, userId]);

  return null;
}

function LedgerPersistenceLifecycle() {
  const { flushSaves, ready, reload } = useLedger();
  const appStateRef = useRef(AppState.currentState);
  const resumeRefreshTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const clearResumeRefresh = useCallback(() => {
    if (!resumeRefreshTimerRef.current) return;
    clearTimeout(resumeRefreshTimerRef.current);
    resumeRefreshTimerRef.current = null;
  }, []);

  const refreshFromStore = useCallback(() => {
    if (!ready) return;
    void reload().catch(() => undefined);
  }, [ready, reload]);

  useEffect(() => {
    const subscription = AppState.addEventListener('change', (status) => {
      const previousStatus = appStateRef.current;
      appStateRef.current = status;

      if (status === 'background' || status === 'inactive') {
        clearResumeRefresh();
        void flushSaves();
        return;
      }

      if (status === 'active' && previousStatus !== 'active') {
        refreshFromStore();
        clearResumeRefresh();
        resumeRefreshTimerRef.current = setTimeout(() => {
          resumeRefreshTimerRef.current = null;
          refreshFromStore();
        }, APP_RESUME_REFRESH_SETTLE_MS);
      }
    });

    return () => {
      subscription.remove();
      clearResumeRefresh();
    };
  }, [clearResumeRefresh, flushSaves, refreshFromStore]);

  return null;
}

function AndroidHomeWidgetSync() {
  const { state, ready } = useLedger();
  const latestStateRef = useRef(state);
  const syncTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  latestStateRef.current = state;

  const clearScheduledSync = useCallback(() => {
    if (!syncTimerRef.current) return;
    clearTimeout(syncTimerRef.current);
    syncTimerRef.current = null;
  }, []);

  useEffect(() => {
    if (!ready) return;
    clearScheduledSync();
    syncTimerRef.current = setTimeout(() => {
      syncTimerRef.current = null;
      void syncAndroidHomeWidgets(latestStateRef.current).catch(() => undefined);
    }, ANDROID_WIDGET_SYNC_DEBOUNCE_MS);

    return clearScheduledSync;
  }, [clearScheduledSync, ready, state]);

  useEffect(() => {
    const subscription = AppState.addEventListener('change', (status) => {
      if (!ready || (status !== 'background' && status !== 'inactive')) return;
      clearScheduledSync();
      void syncAndroidHomeWidgets(latestStateRef.current).catch(() => undefined);
    });

    return () => subscription.remove();
  }, [clearScheduledSync, ready]);

  return null;
}

function AndroidSmsCapturePreferenceSync() {
  const { state, ready } = useLedger();
  const latestStateRef = useRef(state);

  useEffect(() => {
    latestStateRef.current = state;
  }, [state]);

  useEffect(() => {
    if (!ready) return;
    void syncAndroidSmsCapturePreferences(latestStateRef.current).catch(() => undefined);
  }, [ready, state.preferences.autoCapture]);

  return null;
}

class AppErrorBoundary extends Component<
  { children: ReactNode },
  { error: Error | null; details: string | null }
> {
  override state: { error: Error | null; details: string | null } = {
    error: null,
    details: null,
  };

  static getDerivedStateFromError(error: Error) {
    return { error, details: error.message };
  }

  override componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('Unhandled app error', error, info.componentStack);
  }

  override render() {
    if (!this.state.error) return this.props.children;

    return (
      <View style={styles.errorScreen}>
        <Text style={styles.errorTitle}>1wallet needs a restart</Text>
        <Text style={styles.errorBody}>
          {this.state.details ?? 'An unexpected error occurred.'}
        </Text>
        <Button title="Try again" onPress={() => this.setState({ error: null, details: null })} />
      </View>
    );
  }
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  appShell: { flex: 1 },
  errorScreen: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
    padding: 24,
    backgroundColor: '#FBF8F3',
  },
  errorTitle: { fontSize: 22, fontWeight: '800', textAlign: 'center', color: '#1B1B1F' },
  errorBody: { textAlign: 'center', color: '#5F6368' },
});
