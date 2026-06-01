import { NativeModules, PermissionsAndroid, Platform } from 'react-native';

export type AndroidSmsPermissionStatus = 'granted' | 'denied' | 'blocked' | 'unavailable';

export interface AndroidSmsPermissionState {
  read: AndroidSmsPermissionStatus;
  receive: AndroidSmsPermissionStatus;
  overall: 'granted' | 'partial' | 'denied' | 'unavailable';
}

export interface AndroidSmsInboxMessage {
  id: string;
  sender?: string;
  body: string;
  receivedAt: string;
}

type NativeSmsMessage = {
  _id?: unknown;
  id?: unknown;
  address?: unknown;
  body?: unknown;
  date?: unknown;
};

type SmsAndroidNativeModule = {
  list: (
    filter: string,
    fail: (error: unknown) => void,
    success: (count: number, smsList: string) => void,
  ) => void;
};

const DEFAULT_MAX_COUNT = 200;
const READ_SMS_PERMISSION = 'android.permission.READ_SMS' as Parameters<
  typeof PermissionsAndroid.check
>[0];
const RECEIVE_SMS_PERMISSION = 'android.permission.RECEIVE_SMS' as Parameters<
  typeof PermissionsAndroid.check
>[0];

export function isAndroidSmsInboxAvailable(): boolean {
  return Platform.OS === 'android' && Boolean(smsModule()?.list);
}

export async function getAndroidSmsPermissionState(): Promise<AndroidSmsPermissionState> {
  if (Platform.OS !== 'android') {
    return { read: 'unavailable', receive: 'unavailable', overall: 'unavailable' };
  }
  const read = (await PermissionsAndroid.check(READ_SMS_PERMISSION)) ? 'granted' : 'denied';
  const receive = (await PermissionsAndroid.check(RECEIVE_SMS_PERMISSION)) ? 'granted' : 'denied';
  const overall =
    read === 'granted' && receive === 'granted'
      ? 'granted'
      : read === receive
        ? 'denied'
        : 'partial';
  return { read, receive, overall };
}

export async function requestAndroidSmsPermission(): Promise<AndroidSmsPermissionStatus> {
  if (Platform.OS !== 'android') return 'unavailable';
  const readGranted = await PermissionsAndroid.check(READ_SMS_PERMISSION);
  const receiveGranted = await PermissionsAndroid.check(RECEIVE_SMS_PERMISSION);
  const alreadyGranted = readGranted && receiveGranted;
  if (alreadyGranted) return 'granted';

  const readResult = readGranted
    ? PermissionsAndroid.RESULTS.GRANTED
    : await PermissionsAndroid.request(READ_SMS_PERMISSION, {
        title: 'Allow 1wallet to read payment SMS?',
        message:
          '1wallet scans your local inbox for bank, card, and UPI alerts and queues matches for Review.',
        buttonPositive: 'Allow',
        buttonNegative: 'Not now',
      });
  const receiveResult = receiveGranted
    ? PermissionsAndroid.RESULTS.GRANTED
    : await PermissionsAndroid.request(RECEIVE_SMS_PERMISSION, {
        title: 'Allow new payment SMS capture?',
        message:
          '1wallet listens for new bank, card, and UPI SMS alerts so matching transactions can go to Review.',
        buttonPositive: 'Allow',
        buttonNegative: 'Not now',
      });

  if (
    readResult === PermissionsAndroid.RESULTS.NEVER_ASK_AGAIN ||
    receiveResult === PermissionsAndroid.RESULTS.NEVER_ASK_AGAIN
  ) {
    return 'blocked';
  }

  return readResult === PermissionsAndroid.RESULTS.GRANTED &&
    receiveResult === PermissionsAndroid.RESULTS.GRANTED
    ? 'granted'
    : 'denied';
}

export async function readAndroidSmsInbox({
  maxCount = DEFAULT_MAX_COUNT,
  minDate,
  maxDate,
}: {
  maxCount?: number;
  minDate?: number;
  maxDate?: number;
} = {}): Promise<AndroidSmsInboxMessage[]> {
  const nativeSms = smsModule();
  if (Platform.OS !== 'android' || !nativeSms?.list) {
    throw new Error('Android SMS inbox is not available in this build.');
  }

  const filter = JSON.stringify({
    box: 'inbox',
    maxCount,
    sortOrder: 'date DESC',
    ...(validSmsTimestamp(minDate) ? { minDate } : {}),
    ...(validSmsTimestamp(maxDate) ? { maxDate } : {}),
  });
  return new Promise((resolve, reject) => {
    nativeSms.list(
      filter,
      (error) => reject(new Error(String(error || 'Could not read SMS inbox.'))),
      (_count, smsList) => {
        try {
          const parsed = JSON.parse(smsList) as NativeSmsMessage[];
          resolve(parsed.map(normalizeMessage).filter(isInboxMessage));
        } catch (error) {
          reject(error instanceof Error ? error : new Error('Could not parse SMS inbox.'));
        }
      },
    );
  });
}

function validSmsTimestamp(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}

function smsModule(): SmsAndroidNativeModule | undefined {
  return (NativeModules.Sms ?? NativeModules.SmsAndroid) as SmsAndroidNativeModule | undefined;
}

function normalizeMessage(message: NativeSmsMessage): AndroidSmsInboxMessage | undefined {
  const body = typeof message.body === 'string' ? message.body.trim() : '';
  if (!body) return undefined;
  const idValue =
    typeof message._id === 'string' || typeof message._id === 'number' ? message._id : message.id;
  const dateValue = Number(message.date);
  const receivedAt = Number.isFinite(dateValue)
    ? new Date(dateValue).toISOString()
    : new Date().toISOString();
  return {
    id: idValue !== undefined ? String(idValue) : `${receivedAt}:${body.slice(0, 32)}`,
    sender: typeof message.address === 'string' ? message.address : undefined,
    body,
    receivedAt,
  };
}

function isInboxMessage(
  message: AndroidSmsInboxMessage | undefined,
): message is AndroidSmsInboxMessage {
  return Boolean(message);
}
