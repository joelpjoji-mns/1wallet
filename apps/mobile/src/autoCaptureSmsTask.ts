import { processTransactionMessageCapture } from '@1wallet/ledger/capture/messages';
import { normalizeAutoCapturePreferences } from '@1wallet/ledger/store/types';
import { ledgerStore } from './storage';

type HeadlessSmsPayload = {
  sender?: unknown;
  body?: unknown;
  receivedAt?: unknown;
};

export async function processIncomingSmsHeadlessTask(payload: HeadlessSmsPayload) {
  const body = typeof payload.body === 'string' ? payload.body.trim() : '';
  if (!body) return;

  try {
    const state = await ledgerStore.load();
    const preferences = normalizeAutoCapturePreferences(state.preferences.autoCapture);
    if (!preferences.enabled || !preferences.sms.enabled || !preferences.sms.backgroundEnabled) {
      return;
    }

    const receivedAt = receivedAtIso(payload.receivedAt);
    const result = processTransactionMessageCapture(
      state,
      {
        source: 'sms',
        sender: typeof payload.sender === 'string' ? payload.sender : undefined,
        body,
        receivedAt,
      },
      {
        triggerKeywords: preferences.sms.triggerKeywords,
        ignoredSenderIds: preferences.sms.ignoredSenderIds,
        autoPost: preferences.autoPost,
        autoPostConfidence: preferences.autoPostConfidence,
      },
    );

    const reason = smsCaptureReason(result);
    if (result.outcome === 'posted' || result.outcome === 'queued') {
      const summary = {
        ranAt: new Date().toISOString(),
        scanned: 1,
        recognized: result.parseResult?.candidateInput ? 1 : 0,
        posted: result.outcome === 'posted' ? 1 : 0,
        queued: result.outcome === 'queued' ? 1 : 0,
        duplicates: 0,
        ignored: 0,
        unrecognized: 0,
        ignoredReasons: reason ? { [reason]: 1 } : undefined,
        lastOutcome: result.outcome,
        lastReason: reason,
      };
      state.preferences.autoCapture = normalizeAutoCapturePreferences({
        ...preferences,
        sms: {
          ...preferences.sms,
          lastRun: summary,
        },
      });
      await ledgerStore.save(state);
    }
    console.info('[1wallet] SMS auto-capture processed', {
      outcome: result.outcome,
      reason,
      hasSender: typeof payload.sender === 'string' && payload.sender.trim().length > 0,
    });
  } catch (error) {
    console.warn(
      '[1wallet] SMS auto-capture failed',
      error instanceof Error ? error.message : error,
    );
  }
}

function smsCaptureReason(
  result: ReturnType<typeof processTransactionMessageCapture>,
): string | undefined {
  if (result.outcome === 'ignored') return result.trigger.ignoredReason ?? 'ignored';
  if (result.outcome === 'unrecognized') return result.parseResult?.warnings[0] ?? 'unrecognized';
  if (result.outcome === 'duplicate') return 'duplicate';
  if (result.error) return result.error;
  return undefined;
}

function receivedAtIso(value: unknown): string {
  if (typeof value === 'string' && !Number.isNaN(new Date(value).getTime())) return value;
  if (typeof value === 'number' && Number.isFinite(value)) return new Date(value).toISOString();
  return new Date().toISOString();
}
