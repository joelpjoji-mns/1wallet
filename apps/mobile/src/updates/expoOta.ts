import * as Updates from 'expo-updates';
import type { JsUpdateStatus } from './types';

export async function checkForJsUpdate(): Promise<JsUpdateStatus> {
  if (!Updates.isEnabled) {
    return {
      available: false,
      downloaded: false,
      message: 'JavaScript updates are not configured in this build.',
    };
  }

  try {
    const result = await Updates.checkForUpdateAsync();
    if (result.isAvailable) return { available: true, downloaded: false };
    return { available: false, downloaded: false };
  } catch (error) {
    return { available: false, downloaded: false, message: updateMessage(error) };
  }
}

export async function fetchJsUpdate(): Promise<JsUpdateStatus> {
  if (!Updates.isEnabled) {
    throw new Error('JavaScript updates are not configured in this build.');
  }
  const result = await Updates.fetchUpdateAsync();
  if (result.isNew || result.isRollBackToEmbedded) {
    return { available: true, downloaded: true };
  }
  return { available: false, downloaded: false, message: 'No JavaScript update was downloaded.' };
}

export async function reloadIntoJsUpdate(): Promise<void> {
  if (!Updates.isEnabled) throw new Error('JavaScript updates are not configured in this build.');
  await Updates.reloadAsync();
}

function updateMessage(error: unknown): string {
  return error instanceof Error && error.message.trim()
    ? error.message
    : 'Error updating app. Please try again later.';
}
