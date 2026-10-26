# ADR-002: Single-Document Snapshot Offline Sync with Write Guards

## Context
Personal finance users frequently record transactions in environments without stable network connectivity (e.g., subway stations, foreign flights, underground stores). Furthermore, cross-platform syncing between mobile and a web PWA requires instant reconciliation without massive Firestore billing overhead caused by per-record document listeners.

## Decision
1. Persist the entire wallet state into a single compressed JSON document per user in Cloud Firestore: `users/{uid}`.
2. Structure the synchronization engine around optimistic local commits backed by `CloudSyncWriteGuard`:
   - Every local mutation updates in-memory `LedgerState` and local encrypted storage immediately with `unsyncedChanges = true`.
   - Before uploading, the client reads the remote document metadata (`updatedAt`, `remoteRevision`).
   - If the remote revision is newer, an automated non-destructive merge or conflict dialog is initiated rather than an unverified overwrite.
3. Compress large document bodies using Pako (PWA) and Gzip/Archive (Flutter) when payload size approaches Firestore document limits.

## Consequences
### Positive
- True offline-first operation: 100% of features function with zero network connection.
- Drastically reduced Firestore read/write costs (one write per batch sync instead of hundreds of writes per transaction).
- Clean security boundaries: `firestore.rules` enforces single document ownership (`request.auth.uid == uid`).

### Negative / Trade-offs
- Document size is constrained by Firestore's 1MB single-document limit. Large historical transaction archives require compression or archiving past years into separate storage bundles.
