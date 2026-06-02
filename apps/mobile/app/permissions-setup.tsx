import { normalizeAutoCapturePreferences } from '@1wallet/ledger/store/types';
import { useLedger } from '@1wallet/state';
import { Redirect, router } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Alert, StyleSheet, View } from 'react-native';
import { Button, Divider, HelperText, Text, useTheme } from 'react-native-paper';
import {
    openAndroidAppSettings,
    requestAndroidLocationPermission,
    requestAndroidNotificationPermission,
    requestDeviceCameraPermission,
    requestDevicePhotoLibraryPermission,
    type AndroidRuntimePermissionStatus,
} from '../src/androidPermissions';
import {
    requestAndroidSmsPermission,
    type AndroidSmsPermissionState,
    type AndroidSmsPermissionStatus,
} from '../src/androidSmsInbox';
import { useAuth } from '../src/auth';
import { AppScreen, InfoRow, SectionCard } from '../src/components/AppKit';
import {
    getWalletPermissionSetupStatus,
    markWalletPermissionSetupReviewed,
    type WalletPermissionSetupStatus,
} from '../src/permissionSetup';

type PermissionBusy = 'sms' | 'notifications' | 'camera' | 'photos' | 'location' | null;

export default function PermissionsSetup() {
  const theme = useTheme();
  const { user } = useAuth();
  const { state, mutate } = useLedger();
  const [status, setStatus] = useState<WalletPermissionSetupStatus | null>(null);
  const [permissionBusy, setPermissionBusy] = useState<PermissionBusy>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const autoCapture = normalizeAutoCapturePreferences(state.preferences.autoCapture);

  const refreshPermissions = useCallback(async () => {
    const nextStatus = await getWalletPermissionSetupStatus();
    setStatus(nextStatus);
    return nextStatus;
  }, []);

  useEffect(() => {
    void refreshPermissions().catch((err) => {
      setError(err instanceof Error ? err.message : 'Could not check device permissions.');
    });
  }, [refreshPermissions]);

  if (!user) return <Redirect href={'/login' as never} />;
  if (state.accounts.length === 0) return <Redirect href={'/' as never} />;

  const smsReady = status?.sms.overall === 'granted' || status?.sms.overall === 'unavailable';
  const notificationReady = runtimePermissionReady(status?.notifications);
  const cameraReady = runtimePermissionReady(status?.camera);
  const photoLibraryReady = runtimePermissionReady(status?.photos);
  const locationReady = runtimePermissionReady(status?.location);
  const smsButtonLabel = smsReady
    ? autoCapture.sms.backgroundEnabled
      ? 'SMS ready'
      : 'Turn on capture'
    : 'Allow SMS';

  const enableSmsAutoCapture = async () => {
    await mutate(
      (draft) => {
        const current = normalizeAutoCapturePreferences(draft.preferences.autoCapture);
        draft.preferences.autoCapture = normalizeAutoCapturePreferences({
          ...current,
          enabled: true,
          sms: {
            ...current.sms,
            enabled: true,
            backgroundEnabled: true,
          },
        });
      },
      { slices: ['preferences'] },
    );
  };

  const requestSmsAccess = async () => {
    if (smsReady) {
      await enableSmsAutoCapture();
      await refreshPermissions();
      return;
    }
    setPermissionBusy('sms');
    try {
      const nextSmsStatus = await requestAndroidSmsPermission();
      const next = await refreshPermissions();
      if (nextSmsStatus === 'granted' || next.sms.overall === 'granted') {
        await enableSmsAutoCapture();
        return;
      }
      showSmsPermissionAlert(nextSmsStatus);
    } catch (err) {
      Alert.alert('SMS permission failed', permissionErrorMessage(err));
    } finally {
      setPermissionBusy(null);
    }
  };

  const requestNotifications = async () => {
    setPermissionBusy('notifications');
    try {
      const nextStatus = await requestAndroidNotificationPermission();
      await refreshPermissions();
      if (nextStatus !== 'granted' && nextStatus !== 'unavailable') {
        showNotificationPermissionAlert(nextStatus);
      }
    } catch (err) {
      Alert.alert('Notification permission failed', permissionErrorMessage(err));
    } finally {
      setPermissionBusy(null);
    }
  };

  const requestCamera = async () => {
    setPermissionBusy('camera');
    try {
      const nextStatus = await requestDeviceCameraPermission();
      await refreshPermissions();
      if (nextStatus !== 'granted' && nextStatus !== 'unavailable') {
        showRuntimePermissionAlert('Camera', nextStatus);
      }
    } catch (err) {
      Alert.alert('Camera permission failed', permissionErrorMessage(err));
    } finally {
      setPermissionBusy(null);
    }
  };

  const requestPhotos = async () => {
    setPermissionBusy('photos');
    try {
      const nextStatus = await requestDevicePhotoLibraryPermission();
      await refreshPermissions();
      if (nextStatus !== 'granted' && nextStatus !== 'unavailable') {
        showRuntimePermissionAlert('Photos', nextStatus);
      }
    } catch (err) {
      Alert.alert('Photos permission failed', permissionErrorMessage(err));
    } finally {
      setPermissionBusy(null);
    }
  };

  const requestLocation = async () => {
    setPermissionBusy('location');
    try {
      const nextStatus = await requestAndroidLocationPermission();
      await refreshPermissions();
      if (nextStatus !== 'granted' && nextStatus !== 'unavailable') {
        showRuntimePermissionAlert('Location', nextStatus);
      }
    } catch (err) {
      Alert.alert('Location permission failed', permissionErrorMessage(err));
    } finally {
      setPermissionBusy(null);
    }
  };

  const finish = async () => {
    setSaving(true);
    setError(null);
    try {
      const latestStatus = await refreshPermissions();
      await markWalletPermissionSetupReviewed(user.id, latestStatus);
      router.replace('/(tabs)/home' as never);
    } catch (err) {
      setError(permissionErrorMessage(err, 'Could not save permission setup.'));
    } finally {
      setSaving(false);
    }
  };

  return (
    <AppScreen
      title="Permissions"
      subtitle="Finish device access for capture, alerts, receipts, and transaction context."
      back={false}
    >
      <SectionCard title="Auto Capture" subtitle="SMS stays local and queued items go to Review.">
        <InfoRow
          icon="message-processing-outline"
          label="SMS access"
          value={smsPermissionLabel(status?.sms)}
          tone={smsPermissionTone(status?.sms)}
        />
        <Button
          mode={smsReady && autoCapture.sms.backgroundEnabled ? 'outlined' : 'contained'}
          icon={smsReady ? 'check-circle-outline' : 'message-processing-outline'}
          onPress={() => void requestSmsAccess()}
          loading={permissionBusy === 'sms'}
          disabled={permissionBusy !== null || (smsReady && autoCapture.sms.backgroundEnabled)}
          contentStyle={styles.buttonContent}
        >
          {smsButtonLabel}
        </Button>
        <Divider />
        <InfoRow
          icon="bell-badge-outline"
          label="Notifications"
          value={runtimePermissionLabel(status?.notifications)}
          tone={runtimePermissionTone(status?.notifications)}
        />
        <Button
          mode={notificationReady ? 'outlined' : 'contained'}
          icon={notificationReady ? 'check-circle-outline' : 'bell-outline'}
          onPress={() => void requestNotifications()}
          loading={permissionBusy === 'notifications'}
          disabled={permissionBusy !== null || notificationReady}
          contentStyle={styles.buttonContent}
        >
          {notificationReady ? 'Notifications ready' : 'Allow notifications'}
        </Button>
        <Divider />
        <InfoRow
          icon="battery-heart-outline"
          label="Battery behavior"
          value={autoCapture.sms.backgroundEnabled ? 'Background on' : 'Needs SMS'}
          tone={autoCapture.sms.backgroundEnabled ? 'positive' : 'warning'}
        />
        <Button
          mode="outlined"
          icon="cog-outline"
          onPress={() => void openAndroidAppSettings()}
          contentStyle={styles.buttonContent}
        >
          Open app settings
        </Button>
      </SectionCard>

      <SectionCard
        title="Receipts and context"
        subtitle="These permissions power receipt capture and transaction details."
      >
        <InfoRow
          icon="camera-outline"
          label="Camera"
          value={runtimePermissionLabel(status?.camera)}
          tone={runtimePermissionTone(status?.camera)}
        />
        <Text variant="bodySmall" style={[styles.reason, { color: theme.colors.onSurfaceVariant }]}>
          Why: scan receipt and bill photos for OCR and attachments.
        </Text>
        <Button
          mode={cameraReady ? 'outlined' : 'contained'}
          icon={cameraReady ? 'check-circle-outline' : 'camera-outline'}
          onPress={() => void requestCamera()}
          loading={permissionBusy === 'camera'}
          disabled={permissionBusy !== null || cameraReady}
          contentStyle={styles.buttonContent}
        >
          {cameraReady ? 'Camera ready' : 'Allow camera'}
        </Button>
        <Divider />
        <InfoRow
          icon="image-outline"
          label="Photos"
          value={runtimePermissionLabel(status?.photos)}
          tone={runtimePermissionTone(status?.photos)}
        />
        <Text variant="bodySmall" style={[styles.reason, { color: theme.colors.onSurfaceVariant }]}>
          Why: choose existing receipt and bill images from your photo library.
        </Text>
        <Button
          mode={photoLibraryReady ? 'outlined' : 'contained'}
          icon={photoLibraryReady ? 'check-circle-outline' : 'image-outline'}
          onPress={() => void requestPhotos()}
          loading={permissionBusy === 'photos'}
          disabled={permissionBusy !== null || photoLibraryReady}
          contentStyle={styles.buttonContent}
        >
          {photoLibraryReady ? 'Photos ready' : 'Allow photos'}
        </Button>
        <Divider />
        <InfoRow
          icon="map-marker-outline"
          label="Location"
          value={runtimePermissionLabel(status?.location)}
          tone={runtimePermissionTone(status?.location)}
        />
        <Text variant="bodySmall" style={[styles.reason, { color: theme.colors.onSurfaceVariant }]}>
          Why: tag where a transaction or receipt happened when you choose to save place details.
        </Text>
        <Button
          mode={locationReady ? 'outlined' : 'contained'}
          icon={locationReady ? 'check-circle-outline' : 'map-marker-outline'}
          onPress={() => void requestLocation()}
          loading={permissionBusy === 'location'}
          disabled={permissionBusy !== null || locationReady}
          contentStyle={styles.buttonContent}
        >
          {locationReady ? 'Location ready' : 'Allow location'}
        </Button>
      </SectionCard>

      <HelperText type="error" visible={Boolean(error)}>
        {error}
      </HelperText>
      <View style={styles.actions}>
        <Button
          mode="contained"
          icon="check-circle-outline"
          onPress={() => void finish()}
          loading={saving}
          disabled={saving || permissionBusy !== null}
          contentStyle={styles.buttonContent}
        >
          Continue
        </Button>
      </View>
    </AppScreen>
  );
}

function smsPermissionLabel(state?: AndroidSmsPermissionState) {
  if (!state) return 'Checking';
  if (state.overall === 'granted') return 'Granted';
  if (state.overall === 'partial') return 'Partial';
  if (state.overall === 'unavailable') return 'Unavailable';
  return 'Needed';
}

function smsPermissionTone(
  state?: AndroidSmsPermissionState,
): 'default' | 'positive' | 'warning' | 'danger' {
  if (!state) return 'default';
  if (state.overall === 'granted') return 'positive';
  if (state.overall === 'unavailable') return 'default';
  return 'warning';
}

function runtimePermissionLabel(status?: AndroidRuntimePermissionStatus) {
  if (!status) return 'Checking';
  if (status === 'granted') return 'Granted';
  if (status === 'blocked') return 'Blocked';
  if (status === 'unavailable') return 'Not needed';
  return 'Needed';
}

function runtimePermissionTone(
  status?: AndroidRuntimePermissionStatus,
): 'default' | 'positive' | 'warning' | 'danger' {
  if (!status || status === 'unavailable') return 'default';
  if (status === 'granted') return 'positive';
  if (status === 'blocked') return 'danger';
  return 'warning';
}

function runtimePermissionReady(status?: AndroidRuntimePermissionStatus) {
  return status === 'granted' || status === 'unavailable';
}

function showRuntimePermissionAlert(
  label: 'Camera' | 'Photos' | 'Location',
  status: AndroidRuntimePermissionStatus,
) {
  const blocked = status === 'blocked';
  Alert.alert(
    blocked ? `${label} permission is blocked` : `${label} permission not granted`,
    blocked
      ? `Open Android settings and allow ${label.toLowerCase()} permission for 1wallet.`
      : `You can continue now and allow ${label.toLowerCase()} permission later from Android settings.`,
    blocked
      ? [
          { text: 'Not now', style: 'cancel' },
          { text: 'Open settings', onPress: () => void openAndroidAppSettings() },
        ]
      : [{ text: 'OK' }],
  );
}

function showSmsPermissionAlert(status: AndroidSmsPermissionStatus) {
  const blocked = status === 'blocked';
  Alert.alert(
    blocked ? 'SMS permission is blocked' : 'SMS permission not granted',
    blocked
      ? 'Open Android settings and allow SMS permissions for 1wallet.'
      : 'You can continue now and allow SMS capture later from Auto Capture.',
    blocked
      ? [
          { text: 'Not now', style: 'cancel' },
          { text: 'Open settings', onPress: () => void openAndroidAppSettings() },
        ]
      : [{ text: 'OK' }],
  );
}

function showNotificationPermissionAlert(status: AndroidRuntimePermissionStatus) {
  const blocked = status === 'blocked';
  Alert.alert(
    blocked ? 'Notifications are blocked' : 'Notifications not granted',
    blocked
      ? 'Open Android settings and allow notifications for 1wallet.'
      : 'You can continue now and allow notifications later from Android settings.',
    blocked
      ? [
          { text: 'Not now', style: 'cancel' },
          { text: 'Open settings', onPress: () => void openAndroidAppSettings() },
        ]
      : [{ text: 'OK' }],
  );
}

function permissionErrorMessage(err: unknown, fallback = 'Permission setup failed.'): string {
  return err instanceof Error && err.message ? err.message : fallback;
}

const styles = StyleSheet.create({
  buttonContent: { minHeight: 48 },
  reason: { marginTop: -4 },
  actions: { gap: 12 },
});
