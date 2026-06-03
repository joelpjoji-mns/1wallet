import * as SecureStore from 'expo-secure-store';
import {
    getDeviceNotificationPermissionStatus,
    getDeviceCameraPermissionStatus,
    getDevicePhotoLibraryPermissionStatus,
    type DeviceRuntimePermissionStatus,
} from './androidPermissions';
import { getAndroidSmsPermissionState, type AndroidSmsPermissionState } from './androidSmsInbox';

const PERMISSION_REVIEW_KEY_PREFIX = '1wallet.permission-setup.review.v1.';

export type WalletPermissionSetupStatus = {
  sms: AndroidSmsPermissionState;
  notifications: DeviceRuntimePermissionStatus;
  camera: DeviceRuntimePermissionStatus;
  photos: DeviceRuntimePermissionStatus;
};

export async function getWalletPermissionSetupStatus(): Promise<WalletPermissionSetupStatus> {
  const [sms, notifications, camera, photos] = await Promise.all([
    getAndroidSmsPermissionState(),
    getDeviceNotificationPermissionStatus(),
    getDeviceCameraPermissionStatus(),
    getDevicePhotoLibraryPermissionStatus(),
  ]);
  return { sms, notifications, camera, photos };
}

export function isWalletPermissionSetupReady(status: WalletPermissionSetupStatus): boolean {
  return (
    smsPermissionReady(status.sms) &&
    runtimePermissionReady(status.notifications) &&
    runtimePermissionReady(status.camera) &&
    runtimePermissionReady(status.photos)
  );
}

export async function shouldShowWalletPermissionSetup(userId: string): Promise<boolean> {
  const status = await getWalletPermissionSetupStatus();
  if (isWalletPermissionSetupReady(status)) return false;
  return !(await hasReviewedWalletPermissionSetup(userId, status));
}

export async function hasReviewedWalletPermissionSetup(
  userId: string,
  status: WalletPermissionSetupStatus,
): Promise<boolean> {
  const reviewedSignature = await SecureStore.getItemAsync(permissionReviewKey(userId));
  return reviewedSignature === walletPermissionSetupSignature(status);
}

export async function markWalletPermissionSetupReviewed(
  userId: string,
  status: WalletPermissionSetupStatus,
): Promise<void> {
  await SecureStore.setItemAsync(
    permissionReviewKey(userId),
    walletPermissionSetupSignature(status),
  );
}

export function walletPermissionSetupSignature(status: WalletPermissionSetupStatus): string {
  return [
    `sms:${status.sms.overall}:${status.sms.read}:${status.sms.receive}`,
    `notifications:${status.notifications}`,
    `camera:${status.camera}`,
    `photos:${status.photos}`,
  ].join('|');
}

function smsPermissionReady(status: AndroidSmsPermissionState): boolean {
  return status.overall === 'granted' || status.overall === 'unavailable';
}

function runtimePermissionReady(status: DeviceRuntimePermissionStatus): boolean {
  return status === 'granted' || status === 'unavailable';
}

function permissionReviewKey(userId: string): string {
  const safeUserId = userId.replace(/[^a-zA-Z0-9._-]/g, '_') || 'unknown';
  return `${PERMISSION_REVIEW_KEY_PREFIX}${safeUserId}`;
}
