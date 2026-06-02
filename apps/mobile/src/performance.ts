type PerfDetails = Record<string, unknown>;

const DEFAULT_SLOW_THRESHOLD_MS = 16;

export function perfNow(): number {
  return typeof performance !== 'undefined' && typeof performance.now === 'function'
    ? performance.now()
    : Date.now();
}

export function shouldLogPerformance(): boolean {
  const runtime = globalThis as { __DEV__?: boolean };
  return runtime.__DEV__ === true;
}

export function warnSlowOperation(
  name: string,
  startedAt: number,
  thresholdMs = DEFAULT_SLOW_THRESHOLD_MS,
  details?: PerfDetails,
): number {
  const durationMs = perfNow() - startedAt;
  if (shouldLogPerformance() && durationMs >= thresholdMs) {
    console.warn(`[perf] ${name} ${durationMs.toFixed(1)}ms`, details ?? '');
  }
  return durationMs;
}

export function timeOperation<T>(
  name: string,
  run: () => T,
  thresholdMs = DEFAULT_SLOW_THRESHOLD_MS,
  details?: PerfDetails,
): T {
  const startedAt = perfNow();
  try {
    return run();
  } finally {
    warnSlowOperation(name, startedAt, thresholdMs, details);
  }
}
