import { normalizeAutoCapturePreferences, type LedgerState } from '@1wallet/ledger/store/types';
import { NativeModules, Platform } from 'react-native';

type OneWalletSmsCaptureModule = {
  syncPreferences?: (payload: AndroidSmsCapturePreferencesPayload) => Promise<void> | void;
};

type AndroidSmsCapturePreferencesPayload = {
  enabled: boolean;
  smsEnabled: boolean;
  backgroundEnabled: boolean;
  triggerKeywords: string[];
  ignoredSenderIds: string[];
};

export function isAndroidSmsCapturePreferenceSyncAvailable(): boolean {
  return Platform.OS === 'android' && Boolean(smsCaptureModule()?.syncPreferences);
}

export async function syncAndroidSmsCapturePreferences(state: LedgerState): Promise<void> {
  const module = smsCaptureModule();
  if (Platform.OS !== 'android' || !module?.syncPreferences) return;

  const preferences = normalizeAutoCapturePreferences(state.preferences.autoCapture);
  await module.syncPreferences({
    enabled: preferences.enabled,
    smsEnabled: preferences.sms.enabled,
    backgroundEnabled: preferences.sms.backgroundEnabled,
    triggerKeywords: preferences.sms.triggerKeywords,
    ignoredSenderIds: preferences.sms.ignoredSenderIds,
  });
}

function smsCaptureModule(): OneWalletSmsCaptureModule | undefined {
  return NativeModules.OneWalletSmsCapture as OneWalletSmsCaptureModule | undefined;
}
