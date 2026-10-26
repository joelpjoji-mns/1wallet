# Rule: Offline Sync & Write Guard Safety

## Invariants

1. **Write Guards Before Cloud Mutation**:
   - `CloudSyncWriteGuard` must inspect the remote Firestore snapshot's `updatedAt` and `remoteRevision` before any write.
   - If the remote revision is newer, never overwrite blindly. Trigger conflict resolution or non-destructive merging.

2. **Session / UID Isolation**:
   - When Firebase Auth state changes (`user.uid` changes or logs out):
     - Immediately stop any in-flight cloud sync jobs.
     - Reset `LedgerController` state and load the corresponding user-scoped storage to prevent cross-account contamination.

3. **Optimistic Local Commits**:
   - Local ledger modifications are committed immediately to on-device storage. Cloud sync executes asynchronously without blocking the user.
