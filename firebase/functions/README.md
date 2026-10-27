# Account deletion backend

This package owns the server-side deletion protocol. It does not deploy itself.
Use Node 22, Java 21 for emulators, and the repository's Firebase configuration.

## API and ownership

- `requestAccountDeletion`: POST with a recently authenticated Firebase bearer
  ID token and a client-generated 256-bit base64url `receipt`. The server derives
  the target UID from the verified token; a caller-supplied UID is never trusted.
  Authentication must be fresh within five minutes.
- `accountDeletionStatus`: POST with that receipt. It exposes only operation
  status and `remoteComplete`; it neither returns wallet data nor authorizes
  additional deletion. The job stores a SHA-256 receipt hash, never the secret.
- `deleteAccountWorker`: private Cloud Tasks handler. It leases the immutable
  owner job, recursively removes `users/{uid}`, then removes Firebase Auth.
  Retries are idempotent and only `auth/user-not-found` is accepted as an
  already-completed credential deletion.

Jobs live at `accountDeletionJobs/{uid}`, outside the erased subtree. Rules
prevent wallet reads/writes while the tombstone exists, including from old
clients with cached tokens. Clients cannot create/update/delete job documents.
Do not delete tombstones while outstanding ID tokens may remain valid.

The client saves the receipt before requesting deletion and retains it until
both remote erasure and this device's cleanup are confirmed. Network loss, auth
loss, receipt corruption, and local purge failure are not completion. An opaque
receipt allows status recovery after credentials are gone. It is not a recovery
key for financial data.

Disconnected devices and user-exported copies cannot be remotely guaranteed
erased. Minimal job/tombstone metadata remains after financial data deletion.
Define and disclose its operational retention policy before production rollout;
do not enable an aggressive TTL that reopens writes or strands pending receipts.

## Local verification

From the repository root, after installing locked dependencies:

```powershell
npm ci --prefix firebase
npm ci --prefix firebase\functions
npm --prefix firebase\functions test
```

Set Java 21 in this process only, check that emulator ports are free, and use a
demo project:

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
$env:FUNCTIONS_REGION = 'us-central1'
firebase emulators:exec --only 'auth,firestore,functions' --project demo-1wallet-rules "npm --prefix firebase\functions run test:emulator && npm --prefix firebase test"
```

The integration test uses synthetic accounts and actual emulated task dispatch.
The request handler fails closed if a Functions emulator is not attached to a
demo project and a Cloud Tasks emulator. Tests require emulator host variables
and will not silently contact production.

The local Functions base URL is
`http://127.0.0.1:5001/demo-1wallet-rules/us-central1`; on an Android emulator
use host `10.0.2.2` instead. Set Flutter's `ACCOUNT_DELETION_BASE_URL` and
`FIREBASE_USE_EMULATOR` accordingly. Do not put an ID token, receipt, password,
or service-account key in configuration files.
Android debug builds permit cleartext only to these loopback/emulator hosts.
Release configuration still requires HTTPS and rejects emulator mode. Physical
device LAN testing needs an explicit development-only network policy or HTTPS.

## Explicit production rollout checklist

Deployment is a separate operator action, not part of local implementation.

1. Select the Firebase project and region deliberately, including data residency.
   A billing-enabled project and Functions/Cloud Tasks/Firestore/Auth APIs are
   required. Do not select a project implicitly from a developer's default CLI.
2. Set `FUNCTIONS_REGION` and the exact allowed browser `APP_ORIGINS`; the example
   file is not production configuration. The backend refuses discovery without
   a configured region outside the emulator.
3. Configure dedicated service identities. The enqueuer needs task creation and
   permission to use the task dispatch identity. The dispatch identity needs
   permission to invoke the worker. The worker needs only the required
   Firestore deletion/job-update and Firebase Auth deletion privileges.
   Do not grant public invocation to the task worker.
   Set `FUNCTIONS_REQUEST_SERVICE_ACCOUNT`, `FUNCTIONS_STATUS_SERVICE_ACCOUNT`,
   and `FUNCTIONS_WORKER_SERVICE_ACCOUNT` explicitly. Outside isolated demo
   emulation, missing identities fail discovery rather than selecting a broad
   ambient default. Status needs job-read access, not wallet deletion privileges.
4. Build and verify this package, then explicitly deploy backend/functions and
   rules to the chosen staging environment before enabling client endpoints.
   Validate actual IAM, task retries, quota behavior, and auth freshness there.
   The emulator does not establish production IAM or billing correctness.
5. Configure the client HTTPS base URL for the chosen environment. Missing
   configuration produces an explicit unavailable error; there is no fallback
   to unsafe client-side erasure. Flutter observes deletion jobs only when its
   endpoint is configured (or emulator mode is enabled). Set
   `VITE_ACCOUNT_DELETION_ENABLED=true` for the PWA only after the new rules are
   deployed. Default-disabled observation preserves compatibility with existing
   deployments whose rules do not yet expose deletion job documents.
6. Exercise a synthetic staging account: cross-UID rejection, duplicate requests,
   task interruption/retry, nested data removal, post-auth status, and a client
   local-cleanup failure. Publish enabled clients only after these checks.
7. Monitor failed jobs without logging receipts, tokens, or ledger contents.
   Retrying a failed job must preserve its original owner and receipt hash.
   Keep completed tombstones and pending receipts during rollback.

After those prerequisites and explicit operator approval, the deployment
commands are:

```powershell
npm --prefix firebase\functions test
firebase deploy --only 'functions,firestore:rules' --project YOUR_EXPLICIT_STAGING_PROJECT
```

Replace the staging project and backend environment values deliberately.
These commands are documentation, not actions performed by this change.

## Failure and rollback handling

- Never restore the former best-effort client deletion path as a rollback.
- Stop new requests/disable client activation if the backend is unavailable;
  retain durable jobs and let existing workers finish or be retried.
- Do not remove deletion fences or recreate an erased user's wallet.
- An expired lease can be reclaimed; active leases must not be bypassed.
- A missing/corrupt client receipt requires an operator-assisted status review.
  Do not reset recovery state merely to make the UI show success.
- A remote-complete/local-failed operation remains retryable on that device.
  Do not erase its receipt or claim that inaccessible/unverified local files
  were removed.
- Do not downgrade clients that edit secure account fields after authenticated
  field migration. Older binaries cannot interpret the v2 key/envelope format.
  Keep the original secure-store keys and a verified encrypted recovery backup;
  recover by moving forward to a compatible client rather than resetting keys.
- New diagnostic history is owner-scoped and erased with that owner's wallet.
  Older unassigned diagnostic history is hidden by default and is not attributed
  to a wallet. It can be removed only through the explicit legacy-history action
  in Capture diagnostics; never silently erase another owner's history.
