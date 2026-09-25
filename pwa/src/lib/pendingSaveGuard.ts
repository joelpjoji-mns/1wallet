// Pure, framework-free helper that binds a debounced save to the Firebase
// uid that was active when it was scheduled, so a user switch (sign-out /
// sign-in as someone else) while a save is still pending can never cause one
// user's data to be written to another user's Firestore document tree.
//
// Kept dependency-free (no React, no Firebase) specifically so it can be unit
// tested directly with Node's built-in test runner — see
// `pendingSaveGuard.test.ts`.

export interface PendingSave<T> {
  uid: string;
  payload: T;
}

export class PendingSaveGuard<T> {
  private pending: PendingSave<T> | null = null;
  private activeUid: string | null = null;

  /** Current uid this guard considers "safe to flush for". */
  getActiveUid(): string | null {
    return this.activeUid;
  }

  /**
   * Call whenever the signed-in user changes (including signing out, where
   * `uid` is `null`). Always drops whatever was queued for the previous
   * user — an in-flight edit for a user who is no longer active must never
   * be silently redirected to the new user's document tree.
   */
  setActiveUid(uid: string | null): void {
    this.activeUid = uid;
    this.pending = null;
  }

  /** Queues `payload` to be flushed for `uid` (coalesces prior pending saves for the same uid). */
  schedule(uid: string, payload: T): void {
    this.pending = { uid, payload };
  }

  /**
   * Consumes and returns the pending save, but only if it still targets the
   * currently active uid. Returns `null` (and drops the stale entry) if the
   * active uid has changed since `schedule()` was called — e.g. the timer
   * fired after the user signed out or switched accounts.
   */
  take(): PendingSave<T> | null {
    const pending = this.pending;
    this.pending = null;
    if (!pending) return null;
    if (pending.uid !== this.activeUid) return null;
    return pending;
  }

  /** Drops any pending save without consuming it (e.g. on unmount). */
  clear(): void {
    this.pending = null;
  }

  hasPending(): boolean {
    return this.pending !== null;
  }
}
