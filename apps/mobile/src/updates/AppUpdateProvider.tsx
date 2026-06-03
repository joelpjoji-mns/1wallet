import AsyncStorage from '@react-native-async-storage/async-storage';
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
import { AppState, Linking, type AppStateStatus } from 'react-native';
import { deliverNativeUpdateNotification } from '../nativeNotifications';
import {
    createApkDownloadTask,
    removeDownloadedUpdate,
    UpdateDownloadCancelledError,
    type UpdateDownloadTask,
} from './downloadManager';
import { checkForJsUpdate, fetchJsUpdate, reloadIntoJsUpdate } from './expoOta';
import { checkForAppUpdate, fetchPublishedReleaseByCode } from './firebaseUpdates';
import { canRequestPackageInstalls, installApk, openInstallSettings } from './nativeInstaller';
import {
    DEFAULT_UPDATE_CHANNEL,
    isUpdateChannel,
    type AppUpdateRelease,
    type AppUpdateState,
    type DownloadedUpdate,
    type UpdateChannel,
} from './types';
import { getInstalledAppVersion, isReleaseNewerThanInstalled } from './version';

const UPDATE_STATE_STORAGE_KEY = 'onewallet.updates.state.v1';
const UPDATE_NATIVE_NOTIFICATION_STORAGE_KEY = 'onewallet.updates.nativeNotification.v1';
const AUTO_CHECK_INTERVAL_MS = 6 * 60 * 60 * 1000;

const initialCurrent = getInstalledAppVersion();
const initialState: AppUpdateState = {
  status: 'idle',
  channel: DEFAULT_UPDATE_CHANNEL,
  current: initialCurrent,
  installedRelease: null,
  release: null,
  downloaded: null,
  download: null,
  jsUpdate: { available: false, downloaded: false },
};

type StoredUpdateState = {
  channel?: UpdateChannel;
  lastCheckedAt?: string;
  downloaded?: DownloadedUpdate | null;
};

type AppUpdateContextValue = {
  state: AppUpdateState;
  drawerBadge?: string;
  checkForUpdates: (manual?: boolean) => Promise<void>;
  setUpdateChannel: (channel: UpdateChannel) => Promise<void>;
  downloadUpdate: () => Promise<void>;
  cancelDownload: () => Promise<void>;
  installDownloadedUpdate: () => Promise<void>;
  openInstallerSettings: () => Promise<void>;
  downloadJsUpdate: () => Promise<void>;
  applyJsUpdate: () => Promise<void>;
  clearMessage: () => void;
};

const AppUpdateContext = createContext<AppUpdateContextValue | null>(null);

export function AppUpdateProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<AppUpdateState>(initialState);
  const downloadTaskRef = useRef<UpdateDownloadTask | null>(null);
  const lastAutoCheckRef = useRef(0);
  const nativeUpdateNotificationKeyRef = useRef<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    void readStoredState().then((stored) => {
      if (cancelled || !stored) return;
      const channel = normalizeStoredChannel(stored.channel);
      const downloaded = normalizeDownloadedUpdate(stored.downloaded, channel);
      setState((current) => ({
        ...current,
        channel,
        lastCheckedAt: stored.lastCheckedAt ?? current.lastCheckedAt,
        downloaded,
        status: downloaded ? 'downloaded' : current.status,
      }));
    });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    let cancelled = false;
    void readLastNativeUpdateNotificationKey().then((key) => {
      if (!cancelled) nativeUpdateNotificationKeyRef.current = key;
    });
    return () => {
      cancelled = true;
    };
  }, []);

  const checkForUpdates = useCallback(
    async (manual = false, requestedChannel?: UpdateChannel) => {
      const selectedChannel = requestedChannel ?? state.channel;
      const now = Date.now();
      if (!manual && now - lastAutoCheckRef.current < AUTO_CHECK_INTERVAL_MS) return;
      lastAutoCheckRef.current = now;

      const current = getInstalledAppVersion();
      setState((previous) => ({
        ...previous,
        channel: selectedChannel,
        current,
        status: 'checking',
        error: undefined,
        message: manual ? 'Checking for updates...' : previous.message,
      }));

      const [nativeOutcome, jsUpdate, installedRelease] = await Promise.all([
        checkForAppUpdate(current, selectedChannel),
        checkForJsUpdate(),
        fetchInstalledRelease(current.versionCode),
      ]);

      if (nativeOutcome.status === 'available') {
        const downloaded =
          nativeOutcome.release.platform === 'android' &&
          state.downloaded &&
          state.downloaded.channel === nativeOutcome.release.channel &&
          state.downloaded.versionCode === nativeOutcome.release.versionCode
            ? state.downloaded
            : null;
        const nextStatus = downloaded ? 'downloaded' : 'available';
        const nextState: AppUpdateState = {
          status: nextStatus,
          channel: selectedChannel,
          current,
          installedRelease,
          release: nativeOutcome.release,
          downloaded,
          download: null,
          jsUpdate,
          lastCheckedAt: nativeOutcome.checkedAt,
          message: downloaded ? 'Update downloaded successfully' : undefined,
        };
        setState(nextState);
        await writeStoredState({
          channel: selectedChannel,
          lastCheckedAt: nativeOutcome.checkedAt,
          downloaded,
        });
        await notifyNativeUpdateAvailable(nativeOutcome.release, nativeUpdateNotificationKeyRef);
        return;
      }

      if (nativeOutcome.status === 'error') {
        const downloaded = state.downloaded?.channel === selectedChannel ? state.downloaded : null;
        setState((previous) => ({
          ...previous,
          channel: selectedChannel,
          current,
          installedRelease,
          status: 'error',
          release: null,
          download: null,
          jsUpdate,
          lastCheckedAt: nativeOutcome.checkedAt,
          error: nativeOutcome.message,
          message: nativeOutcome.message,
        }));
        await writeStoredState({
          channel: selectedChannel,
          lastCheckedAt: nativeOutcome.checkedAt,
          downloaded,
        });
        return;
      }

      if (nativeOutcome.status === 'not-configured') {
        const checkedAt = new Date().toISOString();
        const nextStatus = jsUpdate.available ? 'js-update-ready' : 'up-to-date';
        setState((previous) => ({
          ...previous,
          channel: selectedChannel,
          current,
          installedRelease,
          status: nextStatus,
          release: null,
          downloaded: null,
          download: null,
          jsUpdate,
          lastCheckedAt: checkedAt,
          message: jsUpdate.available ? 'JavaScript update available' : nativeOutcome.message,
          error: undefined,
        }));
        await writeStoredState({
          channel: selectedChannel,
          lastCheckedAt: checkedAt,
          downloaded: null,
        });
        return;
      }

      const nextStatus = jsUpdate.available ? 'js-update-ready' : 'up-to-date';
      const aheadRelease =
        nativeOutcome.status === 'ahead-of-channel' ? nativeOutcome.release : null;
      setState((previous) => ({
        ...previous,
        channel: selectedChannel,
        current,
        installedRelease,
        status: aheadRelease ? 'ahead-of-channel' : nextStatus,
        release: null,
        downloaded: null,
        download: null,
        jsUpdate,
        lastCheckedAt: nativeOutcome.checkedAt,
        message: aheadRelease
          ? aheadOfChannelMessage(selectedChannel, current.versionCode, aheadRelease.versionCode)
          : jsUpdate.available
            ? 'JavaScript update available'
            : undefined,
        error: undefined,
      }));
      await writeStoredState({
        channel: selectedChannel,
        lastCheckedAt: nativeOutcome.checkedAt,
        downloaded: null,
      });
    },
    [state.channel, state.downloaded],
  );

  const setUpdateChannel = useCallback(
    async (channel: UpdateChannel) => {
      if (channel === state.channel) {
        await checkForUpdates(true, channel);
        return;
      }

      const task = downloadTaskRef.current;
      if (task) await task.cancel().catch(() => undefined);
      downloadTaskRef.current = null;
      await removeDownloadedUpdate(state.downloaded?.localUri);
      lastAutoCheckRef.current = 0;

      const current = getInstalledAppVersion();
      setState((previous) => ({
        ...previous,
        channel,
        current,
        status: 'checking',
        release: null,
        downloaded: null,
        download: null,
        error: undefined,
        message: channel === 'beta' ? 'Beta updates enabled' : 'Stable updates enabled',
      }));
      await writeStoredState({ channel, lastCheckedAt: state.lastCheckedAt, downloaded: null });
      await checkForUpdates(true, channel);
    },
    [checkForUpdates, state.channel, state.downloaded?.localUri, state.lastCheckedAt],
  );

  const downloadUpdate = useCallback(async () => {
    const release = state.release;
    if (!release) return;
    if (release.platform === 'ios') {
      const url = iosReleaseUrl(release);
      if (!url) {
        setState((previous) => ({
          ...previous,
          status: 'error',
          error: 'This iOS release does not include an App Store or TestFlight link yet.',
          message: 'This iOS release does not include an App Store or TestFlight link yet.',
        }));
        return;
      }
      setState((previous) => ({
        ...previous,
        status: 'available',
        error: undefined,
        message: release.channel === 'beta' ? 'Opening TestFlight...' : 'Opening App Store...',
      }));
      await Linking.openURL(url);
      return;
    }

    await removeDownloadedUpdate(state.downloaded?.localUri);
    setState((previous) => ({
      ...previous,
      status: 'downloading',
      downloaded: null,
      error: undefined,
      message: 'Downloading update...',
      download: {
        bytesWritten: 0,
        bytesExpected: release.apk.sizeBytes,
        progress: 0,
        etaSeconds: release.apk.estimatedDownloadSeconds,
      },
    }));

    const task = createApkDownloadTask(release, (progress) => {
      setState((previous) => ({ ...previous, download: progress }));
    });
    downloadTaskRef.current = task;

    try {
      const downloaded = await task.promise;
      downloadTaskRef.current = null;
      setState((previous) => ({
        ...previous,
        status: 'downloaded',
        downloaded,
        download: {
          ...previous.download,
          localUri: downloaded.localUri,
          progress: 1,
        } as AppUpdateState['download'],
        error: undefined,
        message: 'Update downloaded successfully',
      }));
      await writeStoredState({
        channel: state.channel,
        lastCheckedAt: state.lastCheckedAt,
        downloaded,
      });
    } catch (error) {
      downloadTaskRef.current = null;
      if (error instanceof UpdateDownloadCancelledError) {
        setState((previous) => ({
          ...previous,
          status: 'cancelled',
          downloaded: null,
          download: null,
          error: undefined,
          message: 'Update cancelled',
        }));
        await writeStoredState({
          channel: state.channel,
          lastCheckedAt: state.lastCheckedAt,
          downloaded: null,
        });
        return;
      }
      setState((previous) => ({
        ...previous,
        status: 'error',
        downloaded: null,
        download: null,
        error: updateMessage(error),
        message: 'Error updating app. Please try again later.',
      }));
    }
  }, [state.channel, state.downloaded?.localUri, state.lastCheckedAt, state.release]);

  const cancelDownload = useCallback(async () => {
    const task = downloadTaskRef.current;
    if (!task) return;
    await task.cancel();
  }, []);

  const installDownloadedUpdate = useCallback(async () => {
    const downloaded = state.downloaded;
    if (!downloaded) return;

    setState((previous) => ({
      ...previous,
      status: 'installing',
      error: undefined,
      message: 'Installing update...',
    }));

    try {
      const installAllowed = await canRequestPackageInstalls();
      if (!installAllowed) {
        await openInstallSettings();
        setState((previous) => ({
          ...previous,
          status: 'downloaded',
          error: 'Allow 1wallet to install updates, then return and tap Install update.',
          message: 'Allow 1wallet to install updates, then return and tap Install update.',
        }));
        return;
      }
      await installApk(downloaded.localUri);
    } catch (error) {
      setState((previous) => ({
        ...previous,
        status: 'error',
        error: updateMessage(error),
        message: 'Error updating app. Please try again later.',
      }));
    }
  }, [state.downloaded]);

  const openInstallerSettings = useCallback(async () => {
    await openInstallSettings();
  }, []);

  const downloadJsUpdate = useCallback(async () => {
    setState((previous) => ({ ...previous, status: 'checking', message: 'Downloading update...' }));
    try {
      const jsUpdate = await fetchJsUpdate();
      setState((previous) => ({
        ...previous,
        status: jsUpdate.downloaded ? 'js-update-ready' : previous.status,
        jsUpdate,
        message: jsUpdate.downloaded ? 'Update downloaded successfully' : jsUpdate.message,
      }));
    } catch (error) {
      setState((previous) => ({
        ...previous,
        status: 'error',
        error: updateMessage(error),
        message: 'Error updating app. Please try again later.',
      }));
    }
  }, []);

  const applyJsUpdate = useCallback(async () => {
    setState((previous) => ({
      ...previous,
      status: 'installing',
      message: 'Installing update...',
    }));
    await reloadIntoJsUpdate();
  }, []);

  const clearMessage = useCallback(() => {
    setState((previous) => ({ ...previous, message: undefined }));
  }, []);

  useEffect(() => {
    void checkForUpdates(false);
  }, [checkForUpdates]);

  useEffect(() => {
    const onAppStateChange = (nextState: AppStateStatus) => {
      if (nextState === 'active') void checkForUpdates(false);
    };
    const subscription = AppState.addEventListener('change', onAppStateChange);
    return () => subscription.remove();
  }, [checkForUpdates]);

  const drawerBadge = useMemo(() => drawerBadgeForState(state), [state]);
  const value = useMemo(
    () => ({
      state,
      drawerBadge,
      checkForUpdates,
      setUpdateChannel,
      downloadUpdate,
      cancelDownload,
      installDownloadedUpdate,
      openInstallerSettings,
      downloadJsUpdate,
      applyJsUpdate,
      clearMessage,
    }),
    [
      applyJsUpdate,
      cancelDownload,
      checkForUpdates,
      clearMessage,
      downloadJsUpdate,
      downloadUpdate,
      drawerBadge,
      installDownloadedUpdate,
      openInstallerSettings,
      setUpdateChannel,
      state,
    ],
  );

  return <AppUpdateContext.Provider value={value}>{children}</AppUpdateContext.Provider>;
}

export function useAppUpdate(): AppUpdateContextValue {
  const context = useContext(AppUpdateContext);
  if (!context) {
    throw new Error('useAppUpdate must be used inside AppUpdateProvider');
  }
  return context;
}

function drawerBadgeForState(state: AppUpdateState): string | undefined {
  if (state.release && isReleaseNewerThanInstalled(state.release, state.current)) {
    return state.release.mandatory ? 'Required' : 'Update';
  }
  if (state.jsUpdate.available) return 'Update';
  if (state.channel === 'beta') return 'Beta';
  return undefined;
}

async function fetchInstalledRelease(versionCode: number): Promise<AppUpdateRelease | null> {
  try {
    return await fetchPublishedReleaseByCode(versionCode);
  } catch {
    return null;
  }
}

function iosReleaseUrl(release: AppUpdateRelease): string | undefined {
  if (release.platform !== 'ios') return undefined;
  if (release.channel === 'beta') {
    return release.ios.testFlightUrl ?? release.ios.buildUrl ?? release.ios.appStoreUrl;
  }
  return release.ios.appStoreUrl ?? release.ios.buildUrl ?? release.ios.testFlightUrl;
}

function aheadOfChannelMessage(
  channel: UpdateChannel,
  installedVersionCode: number,
  latestVersionCode: number,
): string {
  return `This installed build (${installedVersionCode}) is newer than the latest ${channel} build (${latestVersionCode}). Stay on this build until a higher ${channel} release is published.`;
}

function normalizeStoredChannel(value: unknown): UpdateChannel {
  return isUpdateChannel(value) ? value : DEFAULT_UPDATE_CHANNEL;
}

function normalizeDownloadedUpdate(
  downloaded: DownloadedUpdate | null | undefined,
  channel: UpdateChannel,
): DownloadedUpdate | null {
  if (!downloaded) return null;
  const downloadedChannel = normalizeStoredChannel(downloaded.channel);
  if (downloadedChannel !== channel) return null;
  return { ...downloaded, channel: downloadedChannel };
}

async function readStoredState(): Promise<StoredUpdateState | null> {
  const raw = await AsyncStorage.getItem(UPDATE_STATE_STORAGE_KEY).catch(() => null);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as StoredUpdateState;
  } catch {
    return null;
  }
}

async function writeStoredState(state: StoredUpdateState): Promise<void> {
  await AsyncStorage.setItem(UPDATE_STATE_STORAGE_KEY, JSON.stringify(state)).catch(
    () => undefined,
  );
}

async function readLastNativeUpdateNotificationKey(): Promise<string | null> {
  const value = await AsyncStorage.getItem(UPDATE_NATIVE_NOTIFICATION_STORAGE_KEY).catch(
    () => null,
  );
  return value?.trim() || null;
}

async function writeLastNativeUpdateNotificationKey(key: string): Promise<void> {
  await AsyncStorage.setItem(UPDATE_NATIVE_NOTIFICATION_STORAGE_KEY, key).catch(() => undefined);
}

async function notifyNativeUpdateAvailable(
  release: AppUpdateRelease,
  notifiedKeyRef: { current: string | null },
): Promise<void> {
  const key = `${release.channel}:${release.versionCode}`;
  if (notifiedKeyRef.current === key) return;
  const delivered = await deliverNativeUpdateNotification(release).catch(() => false);
  if (!delivered) return;
  notifiedKeyRef.current = key;
  await writeLastNativeUpdateNotificationKey(key);
}

function updateMessage(error: unknown): string {
  if (error instanceof Error && error.message.trim()) return error.message;
  return 'Error updating app. Please try again later.';
}
