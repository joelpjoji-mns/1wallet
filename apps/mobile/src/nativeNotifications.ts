import type { LedgerState } from '@1wallet/ledger/store/types';
import * as Notifications from 'expo-notifications';
import { router } from 'expo-router';
import { Platform } from 'react-native';
import { getAndroidNotificationPermissionStatus } from './androidPermissions';
import {
    buildNotificationInbox,
    normalizeNotificationPreferences,
    type AppNotification,
} from './notifications';

const FINANCE_ALERTS_CHANNEL_ID = 'onewallet-finance-alerts';
const MAX_NATIVE_NOTIFICATIONS_PER_SYNC = 4;
const inMemoryDeliveredIds = new Set<string>();
let handlerConfigured = false;
let channelConfigured = false;

export function configureNativeNotificationHandler() {
  if (handlerConfigured) return;
  handlerConfigured = true;
  Notifications.setNotificationHandler({
    handleNotification: async () => ({
      shouldShowBanner: true,
      shouldShowList: true,
      shouldPlaySound: false,
      shouldSetBadge: true,
      priority: Notifications.AndroidNotificationPriority.DEFAULT,
    }),
  });
}

export function addNativeNotificationResponseListener() {
  configureNativeNotificationHandler();
  const subscription = Notifications.addNotificationResponseReceivedListener((response) => {
    openNativeNotificationTarget(response.notification.request.content.data ?? {});
  });
  return () => subscription.remove();
}

export async function deliverNativeNotificationInbox(
  state: LedgerState,
  now = new Date(),
): Promise<string[]> {
  configureNativeNotificationHandler();
  const preferences = normalizeNotificationPreferences(state.preferences.notifications);
  if (!preferences.enabled || !preferences.pushEnabled) return [];
  if (isQuietHoursActive(preferences.quietHours, now)) return [];
  if (!(await hasNativeNotificationPermission())) return [];

  await ensureFinanceAlertsChannel();

  const deliveredIds = new Set([...preferences.nativeDeliveredIds, ...inMemoryDeliveredIds]);
  const notifications = buildNotificationInbox(state, now)
    .filter((notification) => !notification.read && !deliveredIds.has(notification.id))
    .slice(0, MAX_NATIVE_NOTIFICATIONS_PER_SYNC);

  const nextDeliveredIds: string[] = [];
  for (const notification of notifications) {
    await Notifications.scheduleNotificationAsync({
      identifier: nativeIdentifier(notification.id),
      content: {
        title: notification.title,
        body: notification.body,
        data: nativeNotificationData(notification),
      },
      trigger: Platform.OS === 'android' ? { channelId: FINANCE_ALERTS_CHANNEL_ID } : null,
    });
    inMemoryDeliveredIds.add(notification.id);
    nextDeliveredIds.push(notification.id);
  }

  return nextDeliveredIds;
}

async function ensureFinanceAlertsChannel() {
  if (Platform.OS !== 'android' || channelConfigured) return;
  channelConfigured = true;
  await Notifications.setNotificationChannelAsync(FINANCE_ALERTS_CHANNEL_ID, {
    name: '1wallet finance alerts',
    importance: Notifications.AndroidImportance.DEFAULT,
    showBadge: true,
    enableVibrate: true,
    vibrationPattern: [0, 180, 80, 180],
  });
}

async function hasNativeNotificationPermission(): Promise<boolean> {
  if (Platform.OS === 'android') {
    return (await getAndroidNotificationPermissionStatus()) === 'granted';
  }
  const permissions = await Notifications.getPermissionsAsync();
  return permissions.granted;
}

function nativeNotificationData(notification: AppNotification): Record<string, string> {
  const target = notification.target;
  if (target.type === 'account') {
    return {
      oneWalletNotificationId: notification.id,
      oneWalletTargetType: target.type,
      accountId: target.accountId,
    };
  }
  if (target.type === 'transaction') {
    return {
      oneWalletNotificationId: notification.id,
      oneWalletTargetType: target.type,
      transactionId: target.transactionId,
    };
  }
  return {
    oneWalletNotificationId: notification.id,
    oneWalletTargetType: target.type,
    route: target.route,
  };
}

function openNativeNotificationTarget(data: Record<string, unknown>) {
  const targetType = data.oneWalletTargetType;
  if (targetType === 'account' && typeof data.accountId === 'string') {
    router.push({ pathname: '/account/[id]', params: { id: data.accountId } });
    return;
  }
  if (targetType === 'transaction' && typeof data.transactionId === 'string') {
    router.push({ pathname: '/transaction/[id]', params: { id: data.transactionId } });
    return;
  }
  if (targetType === 'route' && typeof data.route === 'string') {
    router.push(data.route as never);
  }
}

function nativeIdentifier(notificationId: string): string {
  return `onewallet:${notificationId.replace(/[^a-zA-Z0-9_.:-]/g, '-')}`;
}

function isQuietHoursActive(
  quietHours: { enabled: boolean; start: string; end: string },
  now: Date,
): boolean {
  if (!quietHours.enabled) return false;
  const start = timeToMinutes(quietHours.start);
  const end = timeToMinutes(quietHours.end);
  if (start === null || end === null || start === end) return false;
  const current = now.getHours() * 60 + now.getMinutes();
  return start < end ? current >= start && current < end : current >= start || current < end;
}

function timeToMinutes(value: string): number | null {
  const match = /^(\d{1,2}):(\d{2})$/.exec(value.trim());
  if (!match) return null;
  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  if (!Number.isInteger(hours) || !Number.isInteger(minutes)) return null;
  if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) return null;
  return hours * 60 + minutes;
}
