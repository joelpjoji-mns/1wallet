import { InteractionManager } from 'react-native';

export type DeferredInteractionTask = {
  cancel: () => void;
};

type InteractionHandle = { cancel?: () => void };

export function runAfterInteractionsWithTimeout(
  task: () => void,
  timeoutMs = 750,
): DeferredInteractionTask {
  let done = false;
  let timeoutHandle: ReturnType<typeof setTimeout> | null = null;
  let interactionHandle: InteractionHandle | null = null;

  const finish = () => {
    if (done) return;
    done = true;
    if (timeoutHandle) {
      clearTimeout(timeoutHandle);
      timeoutHandle = null;
    }
    interactionHandle?.cancel?.();
    task();
  };

  interactionHandle = InteractionManager.runAfterInteractions(finish) as InteractionHandle;
  timeoutHandle = setTimeout(finish, timeoutMs);

  return {
    cancel: () => {
      if (done) return;
      done = true;
      if (timeoutHandle) {
        clearTimeout(timeoutHandle);
        timeoutHandle = null;
      }
      interactionHandle?.cancel?.();
    },
  };
}
