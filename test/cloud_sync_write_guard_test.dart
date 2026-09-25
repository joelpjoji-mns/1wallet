import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/cloud_sync/cloud_sync_write_guard.dart';

void main() {
  group('hasCloudSyncConflict', () {
    test('no conflict on the very first sync (nothing observed yet)', () {
      final conflict = hasCloudSyncConflict(
        expected: CloudWriteState.unknown,
        live: CloudWriteState.unknown,
        localDeviceId: 'device-a',
      );
      expect(conflict, isFalse);
    });

    test(
      'revision path: no conflict when live revision matches expected',
      () {
        final conflict = hasCloudSyncConflict(
          expected: const CloudWriteState(cloudRevision: 5),
          live: const CloudWriteState(cloudRevision: 5),
          localDeviceId: 'device-a',
        );
        expect(conflict, isFalse);
      },
    );

    test(
      'revision path: conflict when another writer already bumped the '
      'revision past what this writer expected',
      () {
        final conflict = hasCloudSyncConflict(
          expected: const CloudWriteState(cloudRevision: 5),
          live: const CloudWriteState(cloudRevision: 6),
          localDeviceId: 'device-a',
        );
        expect(conflict, isTrue);
      },
    );

    test(
      'revision path catches same-device races once both sides adopt '
      'cloudRevision — unlike the legacy device-id heuristic',
      () {
        // Two writers sharing the same device id (e.g. two same-device PWA
        // tabs) previously always passed the legacy lastWriterDeviceId
        // check. The revision counter closes that gap: whoever committed
        // last bumped the shared revision, so the other stale writer still
        // conflicts even though the device id is identical.
        final conflict = hasCloudSyncConflict(
          expected: const CloudWriteState(
            cloudRevision: 5,
            lastWriterDeviceId: 'device-a',
          ),
          live: const CloudWriteState(
            cloudRevision: 6,
            lastWriterDeviceId: 'device-a',
          ),
          localDeviceId: 'device-a',
        );
        expect(conflict, isTrue);
      },
    );

    test(
      'legacy fallback: no conflict when neither side has ever written '
      'cloudRevision yet and the live doc is untouched since baseline',
      () {
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
          localDeviceId: 'device-a',
        );
        expect(conflict, isFalse);
      },
    );

    test(
      'legacy fallback: conflict when another device wrote a newer '
      'updatedAt than this writer expected',
      () {
        final baseline = DateTime.utc(2026, 1, 1, 12);
        final conflict = hasCloudSyncConflict(
          expected: CloudWriteState(updatedAt: baseline),
          live: CloudWriteState(
            updatedAt: baseline.add(const Duration(minutes: 1)),
            lastWriterDeviceId: 'device-b',
          ),
          localDeviceId: 'device-a',
        );
        expect(conflict, isTrue);
      },
    );

    test(
      'legacy fallback: no conflict when the newer updatedAt was written '
      'by this same writer (its own prior successful push)',
      () {
        final baseline = DateTime.utc(2026, 1, 1, 12);
        final conflict = hasCloudSyncConflict(
          expected: CloudWriteState(updatedAt: baseline),
          live: CloudWriteState(
            updatedAt: baseline.add(const Duration(minutes: 1)),
            lastWriterDeviceId: 'device-a',
          ),
          localDeviceId: 'device-a',
        );
        expect(conflict, isFalse);
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
          localDeviceId: 'device-a',
        );
        expect(conflict, isTrue);
      },
    );
  });

  group('nextCloudRevision', () {
    test('starts at 1 when the cloud has never had a revision', () {
      expect(nextCloudRevision(null), 1);
    });

    test('increments the live revision by exactly 1', () {
      expect(nextCloudRevision(41), 42);
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
          limit: 500,
        ),
        returnsNormally,
      );
    });

    test(
      'throws CloudSyncOversizeException instead of letting a partial '
      'commit be attempted when the write budget would be exceeded',
      () {
        expect(
          () => ensureWithinCloudSyncWriteBudget(
            newChunkCount: 300,
            staleChunkCount: 250,
            limit: 500,
          ),
          throwsA(isA<CloudSyncOversizeException>()),
        );
      },
    );

    test('accounts for the +1 profile-document write in the ceiling', () {
      // 499 chunks + 0 stale + 1 profile doc == 500, exactly at the limit.
      expect(
        () => ensureWithinCloudSyncWriteBudget(
          newChunkCount: 499,
          staleChunkCount: 0,
          limit: 500,
        ),
        returnsNormally,
      );
      // One more tips it over.
      expect(
        () => ensureWithinCloudSyncWriteBudget(
          newChunkCount: 500,
          staleChunkCount: 0,
          limit: 500,
        ),
        throwsA(isA<CloudSyncOversizeException>()),
      );
    });
  });
}
