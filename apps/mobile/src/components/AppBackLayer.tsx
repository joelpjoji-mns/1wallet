import { router, usePathname } from 'expo-router';
import {
    createContext,
    useCallback,
    useContext,
    useEffect,
    useLayoutEffect,
    useMemo,
    useRef,
    useState,
    type MutableRefObject,
    type ReactNode,
} from 'react';
import { BackHandler, DeviceEventEmitter, NativeModules, Platform } from 'react-native';

type BackLayerHandler = () => boolean | void;
type BackLayerEntry = {
  enabledRef: MutableRefObject<boolean>;
  onBackRef: MutableRefObject<BackLayerHandler>;
};
type RegisterBackLayer = (entry: BackLayerEntry) => () => void;
type BackLayerContextValue = {
  registerLayer: RegisterBackLayer;
  refreshSubscription: () => void;
};

const AppBackLayerContext = createContext<BackLayerContextValue | null>(null);
const BACK_LAYER_EVENT = 'oneWalletBackLayerBack';
const nativeBackLayer = NativeModules.OneWalletBackLayer as
  | { setEnabled?: (enabled: boolean) => void }
  | undefined;

export function AppBackLayerProvider({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const layersRef = useRef<BackLayerEntry[]>([]);
  const routeBackFallbackRef = useRef<string | null>(null);
  const [subscriptionVersion, setSubscriptionVersion] = useState(0);

  const refreshSubscription = useCallback(() => {
    setSubscriptionVersion((version) => version + 1);
  }, []);

  const registerLayer = useCallback<RegisterBackLayer>(
    (entry) => {
      layersRef.current = [...layersRef.current, entry];
      refreshSubscription();
      return () => {
        layersRef.current = layersRef.current.filter((item) => item !== entry);
        refreshSubscription();
      };
    },
    [refreshSubscription],
  );

  const handleBackPress = useCallback(() => {
    for (let index = layersRef.current.length - 1; index >= 0; index -= 1) {
      const layer = layersRef.current[index];
      if (!layer) continue;
      if (!layer.enabledRef.current) continue;

      const handled = layer.onBackRef.current();
      if (handled !== false) return true;
    }

    const routeBackFallback = routeBackFallbackRef.current;
    if (routeBackFallback) {
      if (router.canGoBack()) {
        router.back();
      } else {
        router.replace(routeBackFallback as never);
      }
      return true;
    }

    routeBackFallbackRef.current = null;
    return false;
  }, []);

  useLayoutEffect(() => {
    routeBackFallbackRef.current = routeBackFallback(pathname);
    refreshSubscription();
  }, [pathname, refreshSubscription]);

  useEffect(() => {
    if (Platform.OS !== 'android') return undefined;

    const subscription = BackHandler.addEventListener('hardwareBackPress', handleBackPress);

    return () => subscription.remove();
  }, [handleBackPress, subscriptionVersion]);

  useEffect(() => {
    if (Platform.OS !== 'android') return undefined;

    const subscription = DeviceEventEmitter.addListener(BACK_LAYER_EVENT, handleBackPress);
    return () => subscription.remove();
  }, [handleBackPress]);

  useEffect(() => {
    if (Platform.OS !== 'android') return;

    const hasEnabledLayer = layersRef.current.some((layer) => layer.enabledRef.current);
    nativeBackLayer?.setEnabled?.(hasEnabledLayer || Boolean(routeBackFallbackRef.current));
  }, [subscriptionVersion]);

  const contextValue = useMemo(
    () => ({ registerLayer, refreshSubscription }),
    [refreshSubscription, registerLayer],
  );

  return (
    <AppBackLayerContext.Provider value={contextValue}>{children}</AppBackLayerContext.Provider>
  );
}

function routeBackFallback(pathname: string | null | undefined): string | null {
  const path = pathname ?? '';
  if (
    [
      '',
      '/',
      '/home',
      '/transactions',
      '/calendar',
      '/planner',
      '/accounts',
      '/login',
      '/signup',
      '/onboarding',
    ].includes(path)
  ) {
    return null;
  }

  if (path.startsWith('/capture/')) return '/review';
  if (path === '/review') return '/(tabs)/home';
  if (path === '/add' || path.startsWith('/transaction/')) return '/(tabs)/home';
  if (path.startsWith('/account/')) return '/(tabs)/home';
  if (path.startsWith('/loans/')) return '/loans';
  if (path.startsWith('/recurring/')) return '/recurring';
  if (path.startsWith('/budgets/') || path.startsWith('/goals/')) return '/(tabs)/home';
  if (path.startsWith('/import-')) return '/imports';
  if (path === '/device-permissions' || path === '/currencies' || path === '/notifications') {
    return '/settings';
  }

  return '/(tabs)/home';
}

export function useBackLayer(enabled: boolean, onBack: BackLayerHandler) {
  const contextValue = useContext(AppBackLayerContext);
  const enabledRef = useRef(enabled);
  const onBackRef = useRef(onBack);

  useLayoutEffect(() => {
    enabledRef.current = enabled;
    contextValue?.refreshSubscription();
  }, [contextValue, enabled]);

  useLayoutEffect(() => {
    onBackRef.current = onBack;
  }, [onBack]);

  useEffect(() => {
    if (Platform.OS !== 'android') return undefined;

    if (contextValue) return contextValue.registerLayer({ enabledRef, onBackRef });

    const subscription = BackHandler.addEventListener('hardwareBackPress', () => {
      if (!enabledRef.current) return false;

      const handled = onBackRef.current();
      return handled !== false;
    });

    return () => subscription.remove();
  }, [contextValue]);
}
