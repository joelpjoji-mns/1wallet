import * as ImagePicker from 'expo-image-picker';
import * as Notifications from 'expo-notifications';
import { Linking, PermissionsAndroid, Platform } from 'react-native';

export type DeviceRuntimePermissionStatus = 'granted' | 'denied' | 'blocked' | 'unavailable';
export type AndroidRuntimePermissionStatus = DeviceRuntimePermissionStatus;

const POST_NOTIFICATIONS_PERMISSION = 'android.permission.POST_NOTIFICATIONS' as Parameters<
  typeof PermissionsAndroid.check
>[0];

type ExpoPermissionResponse = {
  granted: boolean;
  canAskAgain?: boolean;
  status?: string;
};

export async function getDeviceNotificationPermissionStatus(): Promise<DeviceRuntimePermissionStatus> {
  if (Platform.OS !== 'android' && Platform.OS !== 'ios') return 'unavailable';
  if (Platform.OS === 'ios') {
    const response = await Notifications.getPermissionsAsync();
    return normalizeExpoPermissionResponse(response);
  }
  if (!requiresRuntimeNotificationPermission()) return 'granted';
  return (await PermissionsAndroid.check(POST_NOTIFICATIONS_PERMISSION)) ? 'granted' : 'denied';
}

export async function requestDeviceNotificationPermission(): Promise<DeviceRuntimePermissionStatus> {
  if (Platform.OS !== 'android' && Platform.OS !== 'ios') return 'unavailable';
  if (Platform.OS === 'ios') {
    const response = await Notifications.requestPermissionsAsync();
    return normalizeExpoPermissionResponse(response);
  }
  if (!requiresRuntimeNotificationPermission()) return 'granted';
  const result = await PermissionsAndroid.request(POST_NOTIFICATIONS_PERMISSION, {
    title: 'Allow 1wallet notifications?',
    message:
      '1wallet can show review, reminder, and capture alerts when something needs attention.',
    buttonPositive: 'Allow',
    buttonNegative: 'Not now',
  });
  if (result === PermissionsAndroid.RESULTS.GRANTED) return 'granted';
  if (result === PermissionsAndroid.RESULTS.NEVER_ASK_AGAIN) return 'blocked';
  return 'denied';
}

export async function getAndroidNotificationPermissionStatus(): Promise<DeviceRuntimePermissionStatus> {
  return getDeviceNotificationPermissionStatus();
}

export async function requestAndroidNotificationPermission(): Promise<DeviceRuntimePermissionStatus> {
  return requestDeviceNotificationPermission();
}

export async function getDeviceCameraPermissionStatus(): Promise<DeviceRuntimePermissionStatus> {
  const response = await ImagePicker.getCameraPermissionsAsync();
  return normalizeExpoPermissionResponse(response);
}

export async function requestDeviceCameraPermission(): Promise<DeviceRuntimePermissionStatus> {
  const response = await ImagePicker.requestCameraPermissionsAsync();
  return normalizeExpoPermissionResponse(response);
}

export async function getDevicePhotoLibraryPermissionStatus(): Promise<DeviceRuntimePermissionStatus> {
  const response = await ImagePicker.getMediaLibraryPermissionsAsync(false);
  return normalizeExpoPermissionResponse(response);
}

export async function requestDevicePhotoLibraryPermission(): Promise<DeviceRuntimePermissionStatus> {
  const response = await ImagePicker.requestMediaLibraryPermissionsAsync(false);
  return normalizeExpoPermissionResponse(response);
}

export async function openDeviceAppSettings() {
  await Linking.openSettings();
}

export async function openAndroidAppSettings() {
  await openDeviceAppSettings();
}

function requiresRuntimeNotificationPermission(): boolean {
  const version =
    typeof Platform.Version === 'number' ? Platform.Version : Number(Platform.Version);
  return Number.isFinite(version) && version >= 33;
}

function normalizeExpoPermissionResponse(
  response: ExpoPermissionResponse,
): DeviceRuntimePermissionStatus {
  if (response.granted) return 'granted';
  if (response.status === 'denied' && response.canAskAgain === false) return 'blocked';
  return 'denied';
}
