import { tokens } from '@1wallet/ui';
import { useCallback, useEffect, useState } from 'react';
import { Alert, StyleSheet } from 'react-native';
import { Button, Divider, Text, useTheme } from 'react-native-paper';
import {
    getDeviceCameraPermissionStatus,
    getDevicePhotoLibraryPermissionStatus,
    openAndroidAppSettings,
    requestDeviceCameraPermission,
    requestDevicePhotoLibraryPermission,
    type AndroidRuntimePermissionStatus,
} from '../src/androidPermissions';
import { AppScreen, InfoRow, SectionCard } from '../src/components/AppKit';

type PermissionBusyState = 'camera' | 'photos' | null;

export default function DevicePermissions() {
  const theme = useTheme();
  const [cameraStatus, setCameraStatus] = useState<AndroidRuntimePermissionStatus>();
  const [photoLibraryStatus, setPhotoLibraryStatus] = useState<AndroidRuntimePermissionStatus>();
  const [permissionBusy, setPermissionBusy] = useState<PermissionBusyState>(null);

  const refreshPermissions = useCallback(async () => {
    const [nextCameraStatus, nextPhotoLibraryStatus] = await Promise.all([
      getDeviceCameraPermissionStatus(),
      getDevicePhotoLibraryPermissionStatus(),
    ]);
    setCameraStatus(nextCameraStatus);
    setPhotoLibraryStatus(nextPhotoLibraryStatus);
  }, []);

  useEffect(() => {
    void refreshPermissions().catch(() => undefined);
  }, [refreshPermissions]);

  const requestPermission = async (
    permission: Exclude<PermissionBusyState, null>,
    label: 'Camera' | 'Photos',
    request: () => Promise<AndroidRuntimePermissionStatus>,
  ) => {
    setPermissionBusy(permission);
    try {
      const status = await request();
      await refreshPermissions();
      if (status !== 'granted' && status !== 'unavailable') {
        showPermissionAlert(label, status);
      }
    } catch (err) {
      Alert.alert(`${label} permission failed`, err instanceof Error ? err.message : String(err));
    } finally {
      setPermissionBusy(null);
    }
  };

  const cameraReady = permissionReady(cameraStatus);
  const photoLibraryReady = permissionReady(photoLibraryStatus);

  return (
    <AppScreen
      title="Device permissions"
      subtitle="Allow only the device access you want 1wallet to use."
      contentStyle={styles.content}
    >
      <SectionCard title="Receipts and context" subtitle="Each permission has a separate purpose.">
        <InfoRow
          icon="camera-outline"
          label="Camera"
          value={permissionLabel(cameraStatus)}
          tone={permissionTone(cameraStatus)}
        />
        <Text variant="bodySmall" style={[styles.reason, { color: theme.colors.onSurfaceVariant }]}>
          Why: scan receipt and bill photos for OCR and attachments.
        </Text>
        <Button
          mode={cameraReady ? 'outlined' : 'contained'}
          icon={cameraReady ? 'check-circle-outline' : 'camera-outline'}
          onPress={() => void requestPermission('camera', 'Camera', requestDeviceCameraPermission)}
          loading={permissionBusy === 'camera'}
          disabled={permissionBusy !== null || cameraReady}
        >
          {cameraReady ? 'Camera ready' : 'Allow camera'}
        </Button>

        <Divider />

        <InfoRow
          icon="image-outline"
          label="Photos"
          value={permissionLabel(photoLibraryStatus)}
          tone={permissionTone(photoLibraryStatus)}
        />
        <Text variant="bodySmall" style={[styles.reason, { color: theme.colors.onSurfaceVariant }]}>
          Why: choose existing receipt and bill images from your photo library.
        </Text>
        <Button
          mode={photoLibraryReady ? 'outlined' : 'contained'}
          icon={photoLibraryReady ? 'check-circle-outline' : 'image-outline'}
          onPress={() =>
            void requestPermission('photos', 'Photos', requestDevicePhotoLibraryPermission)
          }
          loading={permissionBusy === 'photos'}
          disabled={permissionBusy !== null || photoLibraryReady}
        >
          {photoLibraryReady ? 'Photos ready' : 'Allow photos'}
        </Button>
      </SectionCard>

      <Button mode="outlined" icon="cog-outline" onPress={() => void openAndroidAppSettings()}>
        Open app settings
      </Button>
    </AppScreen>
  );
}

function permissionLabel(status?: AndroidRuntimePermissionStatus) {
  if (!status) return 'Checking';
  if (status === 'granted') return 'Granted';
  if (status === 'blocked') return 'Blocked';
  if (status === 'unavailable') return 'Not needed';
  return 'Needed';
}

function permissionTone(
  status?: AndroidRuntimePermissionStatus,
): 'default' | 'positive' | 'warning' | 'danger' {
  if (!status || status === 'unavailable') return 'default';
  if (status === 'granted') return 'positive';
  if (status === 'blocked') return 'danger';
  return 'warning';
}

function permissionReady(status?: AndroidRuntimePermissionStatus) {
  return status === 'granted' || status === 'unavailable';
}

function showPermissionAlert(label: 'Camera' | 'Photos', status: AndroidRuntimePermissionStatus) {
  const blocked = status === 'blocked';
  Alert.alert(
    blocked ? `${label} permission is blocked` : `${label} permission not granted`,
    blocked
      ? `Open Android settings and allow ${label.toLowerCase()} permission for 1wallet.`
      : `You can allow ${label.toLowerCase()} permission later from Android settings.`,
    blocked
      ? [
          { text: 'Not now', style: 'cancel' },
          { text: 'Open settings', onPress: () => void openAndroidAppSettings() },
        ]
      : [{ text: 'OK' }],
  );
}

const styles = StyleSheet.create({
  content: { gap: tokens.space.md },
  reason: { marginTop: -tokens.space.xs },
});
