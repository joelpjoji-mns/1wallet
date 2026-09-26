import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/cloud_sync/cloud_sync_metadata.dart';
import 'package:one_wallet_flutter/src/cloud_sync/cloud_sync_write_guard.dart';
import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';

/// Builds the same `CloudWriteState` baseline `uploadSnapshot()` derives
/// from `CloudSyncMetadata` — i.e. what the in-memory ledger was last known
/// to be consistent with — so tests exercise the exact production mapping
/// instead of hand-rolling an equivalent-looking `CloudWriteState`.
CloudWriteState _expectedStateFromMetadata(CloudSyncMetadata metadata) {
  return CloudWriteState(
    cloudRevision: metadata.lastCloudRevision,
    updatedAt: metadata.lastObservedCloudUpdatedAt != null
        ? DateTime.tryParse(metadata.lastObservedCloudUpdatedAt!)
        : null,
  );
}

void main() {
  group('hasCloudSyncConflict', () {
    test('no conflict on the very first sync (nothing observed yet)', () {
      final conflict = hasCloudSyncConflict(
        expected: CloudWriteState.unknown,
        live: CloudWriteState.unknown,
      );
      expect(conflict, isFalse);
    });

    test('revision path: no conflict when live revision matches expected', () {
      final conflict = hasCloudSyncConflict(
        expected: const CloudWriteState(cloudRevision: 5),
        live: const CloudWriteState(cloudRevision: 5),
      );
      expect(conflict, isFalse);
    });

    test('revision path: conflict when another writer already bumped the '
        'revision past what this writer expected', () {
      final conflict = hasCloudSyncConflict(
        expected: const CloudWriteState(cloudRevision: 5),
        live: const CloudWriteState(cloudRevision: 6),
      );
      expect(conflict, isTrue);
    });

    test('revision path catches same-device races once both sides adopt '
        'cloudRevision — unlike a naive device-id-exemption heuristic', () {
      // Two writers sharing the same device id (e.g. two same-device PWA
      // tabs, or two app installs sharing a restored/cloned device id)
      // must still conflict with each other. The revision counter closes
      // that gap: whoever committed last bumped the shared revision, so
      // the other stale writer still conflicts even though the device id
      // is identical.
      final conflict = hasCloudSyncConflict(
        expected: const CloudWriteState(
          cloudRevision: 5,
          lastWriterDeviceId: 'device-a',
        ),
        live: const CloudWriteState(
          cloudRevision: 6,
          lastWriterDeviceId: 'device-a',
        ),
      );
      expect(conflict, isTrue);
    });

    test('legacy fallback: no conflict when neither side has ever written '
        'cloudRevision yet and the live doc is untouched since baseline', () {
      final baseline = DateTime.utc(2026, 1, 1, 12);
      final conflict = hasCloudSyncConflict(
        expected: CloudWriteState(
          updatedAt: baseline,
          lastWriterDeviceId: 'device-a',
        ),
        live: CloudWriteState(
          updatedAt: baseline,
          lastWriterDeviceId: 'device-a',
        ),
      );
      expect(conflict, isFalse);
    });

    test('legacy fallback: conflict when another device wrote a newer '
        'updatedAt than this writer expected', () {
      final baseline = DateTime.utc(2026, 1, 1, 12);
      final conflict = hasCloudSyncConflict(
        expected: CloudWriteState(updatedAt: baseline),
        live: CloudWriteState(
          updatedAt: baseline.add(const Duration(minutes: 1)),
          lastWriterDeviceId: 'device-b',
        ),
      );
      expect(conflict, isTrue);
    });

    test(
      'legacy fallback: conflict even when the newer updatedAt was written '
      'by a writer sharing this same device id — no same-device exemption',
      () {
        // Matches `pwa/src/lib/walletSyncGuards.ts`'s `hasWriteConflict()`
        // byte for byte: an earlier version of this check exempted "same
        // last writer device id" from conflicting, which looked safe for a
        // single native app instance but silently reopens the exact
        // same-device race the PWA side found with two browser tabs (they
        // share one persisted device id). Any newer `updatedAt` since the
        // expected baseline is a conflict, regardless of who wrote it.
        final baseline = DateTime.utc(2026, 1, 1, 12);
        final conflict = hasCloudSyncConflict(
          expected: CloudWriteState(updatedAt: baseline),
          live: CloudWriteState(
            updatedAt: baseline.add(const Duration(minutes: 1)),
            lastWriterDeviceId: 'device-a',
          ),
        );
        expect(conflict, isTrue);
      },
    );

    test(
      'legacy fallback: an old client (no cloudRevision) writing after a '
      'new client observed cloudRevision is still detected via updatedAt',
      () {
        // The new client's `expected` still has a cloudRevision from its own
        // last observation, but the live doc — written by an old peer that
        // doesn't know about cloudRevision — no longer carries one. Falling
        // straight to "no conflict" here would silently let the old peer's
        // write be clobbered, so the check must still compare updatedAt.
        final baseline = DateTime.utc(2026, 1, 1, 12);
        final conflict = hasCloudSyncConflict(
          expected: CloudWriteState(cloudRevision: 3, updatedAt: baseline),
          live: CloudWriteState(
            updatedAt: baseline.add(const Duration(minutes: 1)),
            lastWriterDeviceId: 'device-b',
          ),
        );
        expect(conflict, isTrue);
      },
    );

    test('regression: a stale local ledger baseline correctly conflicts '
        'against a snapshot that landed after the ledger was last synced', () {
      // Mirrors `uploadSnapshot()`'s real baseline source: `expected` here
      // is what the in-memory ledger was last known to be consistent with
      // (persisted CloudSyncMetadata.lastCloudRevision from the previous
      // successful push/pull), *not* a value re-read moments before this
      // upload attempt. If another writer already advanced the cloud
      // past that baseline — even if it happened well before this upload
      // attempt even started serializing — the stale-relative-to-that-
      // write local ledger must still be flagged as conflicting rather
      // than silently overwriting the newer remote snapshot.
      final conflict = hasCloudSyncConflict(
        expected: const CloudWriteState(cloudRevision: 12),
        live: const CloudWriteState(cloudRevision: 13),
      );
      expect(conflict, isTrue);
    });

    test('regression: PWA commits N+1 after the local ledger was loaded but '
        'before upload starts — baseline tied to the last local sync still '
        'conflicts instead of adopting N+1 and overwriting as N+2', () {
      // The exact scenario this fix closes: this device last
      // successfully synced at cloudRevision 5 (persisted in
      // CloudSyncMetadata from that push/pull). Sometime after this
      // device's ledger was loaded into memory — but before it starts
      // uploading — a peer (PWA or another Flutter device) commits
      // revision 6. `uploadSnapshot()` must build its `expected` baseline
      // from the persisted metadata (revision 5), *not* a value read
      // fresh at the start of this upload attempt (which would already
      // show revision 6 and wrongly look like "no conflict", letting the
      // stale ledger be written as revision 7 over the peer's revision-6
      // data).
      final metadata = CloudSyncMetadata(
        deviceId: 'device-a',
        lastCloudRevision: 5,
      );
      final expected = _expectedStateFromMetadata(metadata);

      // The live read inside the transaction, at actual commit time.
      const live = CloudWriteState(
        cloudRevision: 6,
        lastWriterDeviceId: 'device-b',
      );

      expect(hasCloudSyncConflict(expected: expected, live: live), isTrue);
    });

    test('regression: same scenario via the legacy updatedAt fallback (older '
        'peer that does not write cloudRevision yet)', () {
      final lastSyncedAt = DateTime.utc(2026, 1, 1, 12);
      final metadata = CloudSyncMetadata(
        deviceId: 'device-a',
        lastObservedCloudUpdatedAt: lastSyncedAt.toIso8601String(),
      );
      final expected = _expectedStateFromMetadata(metadata);

      // A peer committed after this device's last known sync point, but
      // (being old) never wrote cloudRevision.
      final live = CloudWriteState(
        updatedAt: lastSyncedAt.add(const Duration(minutes: 5)),
        lastWriterDeviceId: 'device-b',
      );

      expect(hasCloudSyncConflict(expected: expected, live: live), isTrue);
    });

    test('regression: conflict when revisions match but updatedAt changed — an '
        'old client wrote users/{uid} (e.g. profile fields only) without '
        'bumping cloudRevision', () {
      // Both sides agree on cloudRevision (5), which the naive
      // revision-only check would treat as "no change". But updatedAt
      // still advanced between expected and live, meaning some writer did
      // touch the document without going through the atomic
      // revision-bumping transaction. Trusting the matching revision
      // alone here would silently let that write be clobbered.
      final baseline = DateTime.utc(2026, 1, 1, 12);
      final conflict = hasCloudSyncConflict(
        expected: CloudWriteState(cloudRevision: 5, updatedAt: baseline),
        live: CloudWriteState(
          cloudRevision: 5,
          updatedAt: baseline.add(const Duration(minutes: 1)),
          lastWriterDeviceId: 'device-old',
        ),
      );
      expect(conflict, isTrue);
    });

    test('regression: a device does not falsely conflict with its own last '
        'write when the exact committed Timestamp round-trips through '
        'persisted metadata', () {
      // Mirrors uploadSnapshot()'s real flow: a millisecond-precision
      // Timestamp (Timestamp.fromMillisecondsSinceEpoch(DateTime.now()
      // .millisecondsSinceEpoch) — deliberately normalized down from Dart's
      // native microsecond precision to match the PWA Firestore JS SDK's
      // millisecond-only Timestamp.now()) is captured once client-side and
      // written verbatim as `users/{uid}.updatedAt` (not
      // FieldValue.serverTimestamp(), whose resolved value the writer never
      // sees). That same instant is persisted as
      // CloudSyncMetadata.lastObservedCloudUpdatedAt via an ISO-8601 string
      // round trip. The next upload's `expected` baseline (rebuilt from that
      // persisted metadata) must compare exactly equal to a `live` read
      // carrying the identical instant — an approximated "now, taken
      // separately" (or a value with leftover sub-millisecond precision)
      // would drift by enough to falsely conflict with the device's own
      // prior write once equal-revision writes are also compared by
      // updatedAt.
      final committedInstant = DateTime.utc(2026, 3, 4, 5, 6, 7, 890);
      final metadata = CloudSyncMetadata(
        deviceId: 'device-a',
        lastCloudRevision: 7,
        lastObservedCloudUpdatedAt: committedInstant.toIso8601String(),
      );
      final expected = _expectedStateFromMetadata(metadata);

      final live = CloudWriteState(
        cloudRevision: 7,
        updatedAt: committedInstant,
        lastWriterDeviceId: 'device-a',
      );

      expect(hasCloudSyncConflict(expected: expected, live: live), isFalse);
    });

    test('regression: a Flutter-normalized millisecond timestamp still exposes '
        'a genuinely different write at the same equal revision (not '
        'incorrectly masked by rounding)', () {
      // Two writers both happen to have committed cloudRevision 7, but at
      // two different millisecond-precision instants — e.g. an old client
      // wrote via FieldValue.serverTimestamp() at a different real moment
      // than this device's last-known baseline. Millisecond normalization
      // must only make each side's *own* captured value exact and stable
      // — it must not blur together two writes that actually differ.
      final baseline = DateTime.utc(2026, 3, 4, 5, 6, 7, 890);
      final conflict = hasCloudSyncConflict(
        expected: CloudWriteState(cloudRevision: 7, updatedAt: baseline),
        live: CloudWriteState(
          cloudRevision: 7,
          updatedAt: baseline.add(const Duration(milliseconds: 1)),
          lastWriterDeviceId: 'device-old',
        ),
      );
      expect(conflict, isTrue);
    });

    test('no conflict when revisions match and updatedAt (when present on '
        'both sides) is also unchanged', () {
      final baseline = DateTime.utc(2026, 1, 1, 12);
      final conflict = hasCloudSyncConflict(
        expected: CloudWriteState(cloudRevision: 5, updatedAt: baseline),
        live: CloudWriteState(cloudRevision: 5, updatedAt: baseline),
      );
      expect(conflict, isFalse);
    });

    test('no conflict on matching revision when updatedAt is missing on one '
        'side (nothing to compare, trust the revision match)', () {
      final conflict = hasCloudSyncConflict(
        expected: const CloudWriteState(cloudRevision: 5),
        live: CloudWriteState(
          cloudRevision: 5,
          updatedAt: DateTime.utc(2026, 1, 1, 12),
        ),
      );
      expect(conflict, isFalse);
    });
  });

  group('hasCloudWalletData', () {
    test('regression: detects a PWA-created wallet (userDoc + wallet_backups '
        'present) even though metadata/preferences was never written', () {
      // The PWA only ever writes users/{uid} and wallet_backups/chunk_N —
      // it never writes the legacy metadata/preferences marker. Gating
      // `_bootstrap` solely on that legacy doc's existence would make an
      // empty local ledger wrongly take the "no cloud data" path instead
      // of pulling this wallet, and a non-empty local ledger could seed
      // right over it.
      final detected = hasCloudWalletData(
        userDocExists: true,
        legacyPreferencesDocExists: false,
      );
      expect(detected, isTrue);
    });

    test('true for an ancient legacy-only account (no userDoc yet)', () {
      final detected = hasCloudWalletData(
        userDocExists: false,
        legacyPreferencesDocExists: true,
      );
      expect(detected, isTrue);
    });

    test('false for a genuinely fresh account (neither doc exists)', () {
      final detected = hasCloudWalletData(
        userDocExists: false,
        legacyPreferencesDocExists: false,
      );
      expect(detected, isFalse);
    });
  });

  group('shouldPullCloudSnapshot', () {
    test('regression: pulls a PWA-created wallet into an empty local ledger '
        'with no other distinguishing signals', () {
      // This is the decision made *after* hasCloudWalletData() above has
      // already let `_bootstrap` into the pull-vs-push branch: an empty
      // local ledger, and none of the other heuristics (revision,
      // updatedAt, device id) have anything to go on yet either — the
      // "no local data to lose" rule alone must be enough to pull.
      final pull = shouldPullCloudSnapshot(
        hasLocalUserData: false,
        hasUnsyncedLocalChanges: false,
        cloudUpdatedAt: null,
        localModifiedAt: null,
        cloudRevision: null,
        lastKnownCloudRevision: null,
        cloudLastWriterDeviceId: null,
        localDeviceId: 'device-a',
      );
      expect(pull, isTrue);
    });

    test('does not pull when nothing indicates the cloud has moved on', () {
      final pull = shouldPullCloudSnapshot(
        hasLocalUserData: true,
        hasUnsyncedLocalChanges: false,
        cloudUpdatedAt: null,
        localModifiedAt: null,
        cloudRevision: 5,
        lastKnownCloudRevision: 5,
        cloudLastWriterDeviceId: 'device-a',
        localDeviceId: 'device-a',
      );
      expect(pull, isFalse);
    });

    test(
      'pulls when the cloud revision has advanced past what we last saw',
      () {
        final pull = shouldPullCloudSnapshot(
          hasLocalUserData: true,
          hasUnsyncedLocalChanges: false,
          cloudUpdatedAt: null,
          localModifiedAt: null,
          cloudRevision: 6,
          lastKnownCloudRevision: 5,
          cloudLastWriterDeviceId: 'device-b',
          localDeviceId: 'device-a',
        );
        expect(pull, isTrue);
      },
    );

    test('unsynced local changes suppress the last-writer-device-id pull '
        'signal (protects a pending local edit from being discarded)', () {
      final pull = shouldPullCloudSnapshot(
        hasLocalUserData: true,
        hasUnsyncedLocalChanges: true,
        cloudUpdatedAt: null,
        localModifiedAt: null,
        cloudRevision: null,
        lastKnownCloudRevision: null,
        cloudLastWriterDeviceId: 'device-b',
        localDeviceId: 'device-a',
      );
      expect(pull, isFalse);
    });

    test('pulls when another device wrote most recently and there are no '
        'unsynced local changes to protect', () {
      final pull = shouldPullCloudSnapshot(
        hasLocalUserData: true,
        hasUnsyncedLocalChanges: false,
        cloudUpdatedAt: null,
        localModifiedAt: null,
        cloudRevision: null,
        lastKnownCloudRevision: null,
        cloudLastWriterDeviceId: 'device-b',
        localDeviceId: 'device-a',
      );
      expect(pull, isTrue);
    });
  });

  group('shouldAcceptCloudRestore', () {
    test(
      'regression: a version-verified cloud snapshot with fewer transactions '
      'than local (a legitimate deletion synced from another device) is '
      'accepted when there are no unsynced local edits — the old '
      'count-based heuristic rejected exactly this case, permanently '
      'preventing deletions from ever syncing down',
      () {
        // `LedgerState.isIncomingLedgerSafer` (lib/src/data/ledger_models.dart)
        // is the heuristic `_restoreFromCloud()` used to gate on, and it
        // really does reject this: prove the bug exists...
        final local = emptyLedgerState(userId: 'user-1').copyWith(
          transactions: [
            TransactionRecord(
              id: 'tx-1',
              type: 'expense',
              status: 'posted',
              source: 'manual',
              accountId: 'acc-1',
              amount: const Money(amountMinor: -500, currency: 'USD'),
              baseAmount: const Money(amountMinor: -500, currency: 'USD'),
              occurredAt: DateTime.utc(2026, 1, 1),
            ),
            TransactionRecord(
              id: 'tx-2',
              type: 'expense',
              status: 'posted',
              source: 'manual',
              accountId: 'acc-1',
              amount: const Money(amountMinor: -700, currency: 'USD'),
              baseAmount: const Money(amountMinor: -700, currency: 'USD'),
              occurredAt: DateTime.utc(2026, 1, 2),
            ),
          ],
        );
        // Another device deleted `tx-2` and synced up; this is the
        // version-consistent snapshot for the newer cloudRevision, verified
        // by `readCloudSyncVersionConsistent` — it is the correct current
        // cloud state, just with fewer transactions than local.
        final incoming = emptyLedgerState(
          userId: 'user-1',
        ).copyWith(transactions: [local.transactions.first]);
        expect(LedgerState.isIncomingLedgerSafer(local, incoming), isFalse);

        // ...then prove `shouldAcceptCloudRestore` — the version-aware
        // replacement `_restoreFromCloud()` now gates on instead — doesn't
        // share that flaw: it accepts the deletion outright, because it
        // never looks at transaction counts/timestamps at all, only at
        // whether *this* device has unsynced edits worth protecting.
        expect(
          shouldAcceptCloudRestore(hasUnsyncedLocalChanges: false),
          isTrue,
        );
      },
    );

    test('regression: an entirely empty incoming snapshot (wallet cleared on '
        'another device) on a newer cloud revision is accepted when there '
        'are no unsynced local edits', () {
      final local = emptyLedgerState(userId: 'user-1').copyWith(
        transactions: [
          TransactionRecord(
            id: 'tx-1',
            type: 'expense',
            status: 'posted',
            source: 'manual',
            accountId: 'acc-1',
            amount: const Money(amountMinor: -500, currency: 'USD'),
            baseAmount: const Money(amountMinor: -500, currency: 'USD'),
            occurredAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      final incoming = emptyLedgerState(userId: 'user-1');
      expect(LedgerState.isIncomingLedgerSafer(local, incoming), isFalse);

      expect(shouldAcceptCloudRestore(hasUnsyncedLocalChanges: false), isTrue);
    });

    test('preserves local state and reports a conflict instead of applying '
        'the cloud snapshot when this device has unsynced local edits — even '
        'though the cloud read was version-verified', () {
      expect(shouldAcceptCloudRestore(hasUnsyncedLocalChanges: true), isFalse);
    });
  });

  group('resolveCloudSyncConflict', () {
    test('regression: exhaustive truth table — no combination of inputs ever '
        'resolves to "retry the push" (there is no such outcome to return in '
        'the first place), which is exactly what let the previous '
        '`unawaited(fullSync(reason: \'conflict-recheck\'))` handler recurse '
        'into an unbounded blind stale-write retry loop', () {
      expect(
        resolveCloudSyncConflict(
          hasUnsyncedLocalChanges: true,
          shouldPull: true,
        ),
        CloudSyncConflictResolution.preserveLocalAndSurfaceConflict,
      );
      expect(
        resolveCloudSyncConflict(
          hasUnsyncedLocalChanges: true,
          shouldPull: false,
        ),
        CloudSyncConflictResolution.preserveLocalAndSurfaceConflict,
      );
      expect(
        resolveCloudSyncConflict(
          hasUnsyncedLocalChanges: false,
          shouldPull: true,
        ),
        CloudSyncConflictResolution.pullCloudSnapshot,
      );
      expect(
        resolveCloudSyncConflict(
          hasUnsyncedLocalChanges: false,
          shouldPull: false,
        ),
        CloudSyncConflictResolution.surfaceConflictOnly,
      );
    });

    test('regression: unsynced local edits are never pulled over, even when '
        'the cloud is also verifiably ahead — preserves local data and '
        'surfaces a conflict instead of restoring', () {
      final resolution = resolveCloudSyncConflict(
        hasUnsyncedLocalChanges: true,
        shouldPull: true,
      );
      expect(
        resolution,
        CloudSyncConflictResolution.preserveLocalAndSurfaceConflict,
      );
    });

    test('pulls the newer cloud snapshot when there are no unsynced local '
        'edits and the cloud is verifiably ahead', () {
      final resolution = resolveCloudSyncConflict(
        hasUnsyncedLocalChanges: false,
        shouldPull: true,
      );
      expect(resolution, CloudSyncConflictResolution.pullCloudSnapshot);
    });

    test('regression: does not blind-retry the stale write when the cloud is '
        'not recognized as ahead (e.g. an equal-revision, changed-updatedAt '
        'conflict shouldPullCloudSnapshot cannot see via cloudRevision '
        'alone) — surfaces the conflict instead of pushing again', () {
      // This is the exact scenario that made the previous
      // `unawaited(fullSync(reason: 'conflict-recheck'))` handler recurse
      // indefinitely: a conflict was detected, but the cloud isn't
      // recognized as "ahead" by shouldPullCloudSnapshot either, so
      // fullSync's own decision logic would fall through to pushing
      // again — reproducing the exact same conflict against the exact
      // same stale baseline, forever, with no backoff.
      final resolution = resolveCloudSyncConflict(
        hasUnsyncedLocalChanges: false,
        shouldPull: false,
      );
      expect(resolution, CloudSyncConflictResolution.surfaceConflictOnly);
    });

    test('distinguishes "unsynced edits at risk" from "nothing to pull, '
        'nothing to protect" even though both currently result in "do not '
        'restore" — the reasons are not interchangeable', () {
      final unsyncedNoShouldPull = resolveCloudSyncConflict(
        hasUnsyncedLocalChanges: true,
        shouldPull: false,
      );
      final noUnsyncedNoShouldPull = resolveCloudSyncConflict(
        hasUnsyncedLocalChanges: false,
        shouldPull: false,
      );
      expect(unsyncedNoShouldPull, isNot(equals(noUnsyncedNoShouldPull)));
    });
  });

  group('nextCloudRevision', () {
    test('starts at 1 when the cloud has never had a revision', () {
      expect(nextCloudRevision(null), 1);
    });

    test('increments the live revision by exactly 1', () {
      expect(nextCloudRevision(41), 42);
    });

    test('regression: increments right up to the int32 ceiling matching '
        "Firestore rules' isOptionalBoundedInt(data, 'cloudRevision', 0, "
        '2147483647) — one below the max still increments normally', () {
      expect(nextCloudRevision(cloudSyncMaxRevision - 1), cloudSyncMaxRevision);
    });

    test('regression: throws CloudSyncRevisionOverflowException instead of '
        'silently computing a value past the int32 ceiling — matching '
        "pwa/src/lib/walletSyncGuards.ts's nextCloudRevision()/"
        'WalletSyncRevisionOverflowError, so this surfaces as a clear, '
        'distinct error before any write is staged rather than an opaque '
        'Firestore rules permission-denied rejection at commit time', () {
      expect(
        () => nextCloudRevision(cloudSyncMaxRevision),
        throwsA(isA<CloudSyncRevisionOverflowException>()),
      );
    });

    test('throws for any live revision already at or beyond the ceiling, not '
        'just exactly at it', () {
      expect(
        () => nextCloudRevision(cloudSyncMaxRevision + 1),
        throwsA(isA<CloudSyncRevisionOverflowException>()),
      );
    });
  });

  group('staleCloudSyncChunkIndices', () {
    test('finds trailing indices left over from a larger previous backup', () {
      final stale = staleCloudSyncChunkIndices(
        existingChunkIndices: [0, 1, 2, 3, 4],
        newChunkCount: 3,
      );
      expect(stale, [3, 4]);
    });

    test('is empty when the new backup is the same size or larger', () {
      expect(
        staleCloudSyncChunkIndices(
          existingChunkIndices: [0, 1, 2],
          newChunkCount: 3,
        ),
        isEmpty,
      );
      expect(
        staleCloudSyncChunkIndices(
          existingChunkIndices: [0, 1, 2],
          newChunkCount: 5,
        ),
        isEmpty,
      );
    });
  });

  group('ensureWithinCloudSyncWriteBudget', () {
    test('does not throw when comfortably under the limit', () {
      expect(
        () => ensureWithinCloudSyncWriteBudget(
          newChunkCount: 10,
          staleChunkCount: 2,
          totalBytes: 1024,
          writeLimit: 500,
        ),
        returnsNormally,
      );
    });

    test('throws CloudSyncOversizeException instead of letting a partial '
        'commit be attempted when the write budget would be exceeded', () {
      expect(
        () => ensureWithinCloudSyncWriteBudget(
          newChunkCount: 300,
          staleChunkCount: 250,
          totalBytes: 1024,
          writeLimit: 500,
        ),
        throwsA(isA<CloudSyncOversizeException>()),
      );
    });

    test('accounts for the +1 profile-document write in the ceiling', () {
      // 499 chunks + 0 stale + 1 profile doc == 500, exactly at the limit.
      expect(
        () => ensureWithinCloudSyncWriteBudget(
          newChunkCount: 499,
          staleChunkCount: 0,
          totalBytes: 1024,
          writeLimit: 500,
        ),
        returnsNormally,
      );
      // One more tips it over.
      expect(
        () => ensureWithinCloudSyncWriteBudget(
          newChunkCount: 500,
          staleChunkCount: 0,
          totalBytes: 1024,
          writeLimit: 500,
        ),
        throwsA(isA<CloudSyncOversizeException>()),
      );
    });

    test('regression: a wallet under the write-count limit but over the ~10 '
        'MiB Firestore commit-byte ceiling still fails fast, matching '
        "pwa/src/lib/walletSyncGuards.ts's assertFitsInOneCommit()", () {
      // 11 chunks is comfortably under the 500-write limit, but at 900KB
      // each that's ~9.9MB — over the 9 MiB byte budget.
      expect(
        () => ensureWithinCloudSyncWriteBudget(
          newChunkCount: 11,
          staleChunkCount: 0,
          totalBytes: 10 * 1024 * 1024,
        ),
        throwsA(isA<CloudSyncOversizeException>()),
      );
    });

    test('does not throw when comfortably under the byte limit', () {
      expect(
        () => ensureWithinCloudSyncWriteBudget(
          newChunkCount: 5,
          staleChunkCount: 0,
          totalBytes: 1024 * 1024,
        ),
        returnsNormally,
      );
    });
  });

  group('exceedsCloudSyncByteBudget', () {
    test('false at exactly the byte limit', () {
      expect(
        exceedsCloudSyncByteBudget(
          totalBytes: 9 * 1024 * 1024,
          limit: 9 * 1024 * 1024,
        ),
        isFalse,
      );
    });

    test('true one byte over the limit', () {
      expect(
        exceedsCloudSyncByteBudget(
          totalBytes: 9 * 1024 * 1024 + 1,
          limit: 9 * 1024 * 1024,
        ),
        isTrue,
      );
    });
  });

  group('isCloudSyncVersionStable', () {
    test('stable when both reads agree on cloudRevision', () {
      final stable = isCloudSyncVersionStable(
        before: const CloudWriteState(cloudRevision: 5),
        after: const CloudWriteState(cloudRevision: 5),
      );
      expect(stable, isTrue);
    });

    test('unstable when a write landed mid-read and bumped cloudRevision', () {
      final stable = isCloudSyncVersionStable(
        before: const CloudWriteState(cloudRevision: 5),
        after: const CloudWriteState(cloudRevision: 6),
      );
      expect(stable, isFalse);
    });

    test('legacy fallback: stable when neither read has cloudRevision and '
        'updatedAt is unchanged', () {
      final at = DateTime.utc(2026, 1, 1, 12);
      final stable = isCloudSyncVersionStable(
        before: CloudWriteState(updatedAt: at),
        after: CloudWriteState(updatedAt: at),
      );
      expect(stable, isTrue);
    });

    test('legacy fallback: unstable when updatedAt changed between reads', () {
      final at = DateTime.utc(2026, 1, 1, 12);
      final stable = isCloudSyncVersionStable(
        before: CloudWriteState(updatedAt: at),
        after: CloudWriteState(updatedAt: at.add(const Duration(seconds: 1))),
      );
      expect(stable, isFalse);
    });

    test('stable for a brand-new account with no data on either read', () {
      final stable = isCloudSyncVersionStable(
        before: CloudWriteState.unknown,
        after: CloudWriteState.unknown,
      );
      expect(stable, isTrue);
    });

    test('regression: unstable when revisions match but updatedAt changed '
        'between reads — an old client wrote in between without bumping '
        'cloudRevision', () {
      final at = DateTime.utc(2026, 1, 1, 12);
      final stable = isCloudSyncVersionStable(
        before: CloudWriteState(cloudRevision: 5, updatedAt: at),
        after: CloudWriteState(
          cloudRevision: 5,
          updatedAt: at.add(const Duration(seconds: 1)),
        ),
      );
      expect(stable, isFalse);
    });

    test('stable when revisions match and updatedAt (when present on both '
        'reads) is also unchanged', () {
      final at = DateTime.utc(2026, 1, 1, 12);
      final stable = isCloudSyncVersionStable(
        before: CloudWriteState(cloudRevision: 5, updatedAt: at),
        after: CloudWriteState(cloudRevision: 5, updatedAt: at),
      );
      expect(stable, isTrue);
    });
  });

  group('readCloudSyncVersionConsistent', () {
    test(
      'returns immediately when the first attempt is already stable',
      () async {
        var versionReads = 0;
        var payloadReads = 0;

        final (payload, version) = await readCloudSyncVersionConsistent<String>(
          readVersionToken: () async {
            versionReads++;
            return const CloudWriteState(cloudRevision: 5);
          },
          fetchPayload: () async {
            payloadReads++;
            return 'snapshot-at-5';
          },
        );

        expect(payload, 'snapshot-at-5');
        expect(version.cloudRevision, 5);
        expect(versionReads, 2); // before + after
        expect(payloadReads, 1);
      },
    );

    test(
      'regression: a write landing mid-download is detected and the whole '
      'cycle (including the download) is retried, not just the version read',
      () async {
        // Simulates exactly the bug this guard closes: attempt 1's "before"
        // read sees revision 5, but a peer's atomic write commits revision
        // 6 while `fetchPayload` (the chunk download) is in flight, so
        // attempt 1's "after" read already shows 6 — mismatch. The payload
        // must be re-fetched (not just re-checked) on the retry so the
        // content and the version we end up recording actually agree.
        var attempt = 0;
        final revisionsPerVersionRead = [
          5,
          6,
          7,
          7,
        ]; // before1, after1(=before2), after2...
        var versionReadIndex = 0;
        final payloadFetchesForRevision = <int>[];

        final (payload, version) = await readCloudSyncVersionConsistent<int>(
          readVersionToken: () async {
            final revision = revisionsPerVersionRead[versionReadIndex];
            versionReadIndex++;
            return CloudWriteState(cloudRevision: revision);
          },
          fetchPayload: () async {
            attempt++;
            // Whatever the payload "download" would have returned at the
            // time it ran — for this test, tag it with the attempt number.
            payloadFetchesForRevision.add(attempt);
            return attempt;
          },
        );

        // First attempt's before(5)/after(6) disagreed, so the payload had
        // to be re-fetched on a second attempt, which then stabilized.
        expect(payloadFetchesForRevision, [1, 2]);
        expect(payload, 2);
        expect(version.cloudRevision, 7);
      },
    );

    test('throws CloudSyncUnstableException when the cloud never stabilizes '
        'within maxAttempts', () async {
      var revision = 0;

      expect(
        () => readCloudSyncVersionConsistent<int>(
          readVersionToken: () async {
            // Every read sees a different value — permanently unstable.
            revision++;
            return CloudWriteState(cloudRevision: revision);
          },
          fetchPayload: () async => 0,
          maxAttempts: 3,
        ),
        throwsA(isA<CloudSyncUnstableException>()),
      );
    });
  });
}
