import { useEffect, useMemo, useRef, useState } from 'react';

import { useDebouncedValue } from './useDebouncedValue';

export type AutoSaveStatus = 'idle' | 'dirty' | 'saving' | 'saved' | 'error';

type UseAutoSaveDraftOptions<TValue, TNormalized = TValue> = {
  value: TValue;
  savedValue: TValue;
  sourceKey: string | number | null | undefined;
  save: (value: TNormalized) => Promise<void> | void;
  delayMs?: number;
  disabled?: boolean;
  normalize?: (value: TValue) => TNormalized;
  validate?: (value: TNormalized) => boolean;
  isEqual?: (left: TNormalized, right: TNormalized) => boolean;
  onError?: (error: unknown) => void;
};

export function useAutoSaveDraft<TValue, TNormalized = TValue>({
  value,
  savedValue,
  sourceKey,
  save,
  delayMs = 600,
  disabled = false,
  normalize,
  validate,
  isEqual,
  onError,
}: UseAutoSaveDraftOptions<TValue, TNormalized>) {
  const [status, setStatus] = useState<AutoSaveStatus>('idle');
  const [error, setError] = useState<unknown>(null);
  const debouncedValue = useDebouncedValue(value, delayMs);
  const latestValueRef = useRef(value);
  const saveRef = useRef(save);
  const onErrorRef = useRef(onError);
  const saveVersionRef = useRef(0);

  const normalizeValue = useMemo(
    () => normalize ?? ((nextValue: TValue) => nextValue as unknown as TNormalized),
    [normalize],
  );
  const areEqual = useMemo(
    () => isEqual ?? ((left: TNormalized, right: TNormalized) => Object.is(left, right)),
    [isEqual],
  );

  useEffect(() => {
    latestValueRef.current = value;
  }, [value]);

  useEffect(() => {
    saveRef.current = save;
  }, [save]);

  useEffect(() => {
    onErrorRef.current = onError;
  }, [onError]);

  const normalizedSavedValue = useMemo(
    () => normalizeValue(savedValue),
    [normalizeValue, savedValue],
  );

  useEffect(() => {
    if (disabled) {
      setStatus('idle');
      setError(null);
      return;
    }

    const normalizedCurrent = normalizeValue(value);
    if (areEqual(normalizedCurrent, normalizedSavedValue)) {
      setStatus('idle');
      setError(null);
      return;
    }

    setStatus((current) => (current === 'saving' ? current : 'dirty'));
  }, [areEqual, disabled, normalizeValue, normalizedSavedValue, sourceKey, value]);

  useEffect(() => {
    if (disabled) return;

    const normalizedDraft = normalizeValue(debouncedValue);
    if (areEqual(normalizedDraft, normalizedSavedValue)) {
      setStatus('idle');
      setError(null);
      return;
    }
    if (validate && !validate(normalizedDraft)) {
      setStatus('dirty');
      return;
    }

    let cancelled = false;
    const saveVersion = saveVersionRef.current + 1;
    saveVersionRef.current = saveVersion;
    setStatus('saving');
    setError(null);

    Promise.resolve(saveRef.current(normalizedDraft))
      .then(() => {
        if (cancelled || saveVersion !== saveVersionRef.current) return;
        const latestNormalizedValue = normalizeValue(latestValueRef.current);
        setStatus(areEqual(latestNormalizedValue, normalizedDraft) ? 'saved' : 'dirty');
      })
      .catch((nextError: unknown) => {
        if (cancelled || saveVersion !== saveVersionRef.current) return;
        setError(nextError);
        setStatus('error');
        onErrorRef.current?.(nextError);
      });

    return () => {
      cancelled = true;
    };
  }, [
    areEqual,
    debouncedValue,
    disabled,
    normalizeValue,
    normalizedSavedValue,
    sourceKey,
    validate,
  ]);

  return {
    status,
    error,
    isDirty: status === 'dirty' || status === 'saving' || status === 'error',
  };
}
