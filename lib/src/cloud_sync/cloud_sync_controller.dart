import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:firebase_core/firebase_core.dart';
import 'package:archive/archive.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_controller.dart';
import '../data/ledger_codec.dart';
import '../data/ledger_models.dart';
import '../data/ledger_providers.dart';
import '../data/ledger_defaults.dart';
import 'cloud_sync_metadata.dart';
import 'cloud_sync_write_guard.dart';

const uploadDebounceMs = 2500;
const uploadCircuitBreakerMs = 30000;
const uploadFailureCircuitBreakerThreshold = 5;
const cloudSyncReadTimeout = Duration(seconds: 30);

final cloudSyncControllerProvider =
    StateNotifierProvider<CloudSyncController, CloudSyncState>((ref) {
      return CloudSyncController(ref);
    });

enum CloudSyncPhase { disabled, idle, checking, restoring, uploading, error }

@immutable
class CloudSyncState {
  const CloudSyncState({
    this.phase = CloudSyncPhase.disabled,
    this.error,
    this.disabledReason,
    this.metadata,
    this.pendingUpload = false,
    this.bootstrapComplete = false,
    this.bootstrappedUserId,
    this.progress,
    this.progressMessage,
  });

  final CloudSyncPhase phase;
  final String? error;
  final String? disabledReason;
  final CloudSyncMetadata? metadata;
  final bool pendingUpload;
  final bool bootstrapComplete;
  final String? bootstrappedUserId;
  final double? progress;
  final String? progressMessage;

  bool get isChecking => phase == CloudSyncPhase.checking;
  bool get isRestoring => phase == CloudSyncPhase.restoring;

  CloudSyncState copyWith({
    CloudSyncPhase? phase,
    Object? error = _unset,
    Object? disabledReason = _unset,
    Object? metadata = _unset,
    bool? pendingUpload,
    bool? bootstrapComplete,
    Object? bootstrappedUserId = _unset,
    Object? progress = _unset,
    Object? progressMessage = _unset,
  }) {
    return CloudSyncState(
      phase: phase ?? this.phase,
      error: identical(error, _unset) ? this.error : error as String?,
      disabledReason: identical(disabledReason, _unset)
          ? this.disabledReason
          : disabledReason as String?,
      metadata: identical(metadata, _unset)
          ? this.metadata
          : metadata as CloudSyncMetadata?,
      pendingUpload: pendingUpload ?? this.pendingUpload,
      bootstrapComplete: bootstrapComplete ?? this.bootstrapComplete,
      bootstrappedUserId: identical(bootstrappedUserId, _unset)
          ? this.bootstrappedUserId
          : bootstrappedUserId as String?,
      progress: identical(progress, _unset)
          ? this.progress
          : progress as double?,
      progressMessage: identical(progressMessage, _unset)
          ? this.progressMessage
          : progressMessage as String?,
    );
  }
}

const _unset = Object();

class CloudSyncController extends StateNotifier<CloudSyncState> {
  CloudSyncController(this._ref) : super(const CloudSyncState()) {
    _init();
  }

  final Ref _ref;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  LedgerController get _ledger => _ref.read(ledgerProvider.notifier);

  Timer? _uploadTimer;
  Timer? _retryTimer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _userDocSubscription;
  int _uploadFailureCount = 0;
  int _uploadCircuitOpenUntil = 0;
  bool _localClearInProgress = false;

  void _init() {
    try {
      if (Firebase.apps.isEmpty) return;
    } catch (_) {
      return;
    }
    _ref.listen(ledgerLoadStateProvider, (previous, next) {
      if (!next.isReady) return;
      final auth = _ref.read(authControllerProvider);
      final user = auth.user;
      if (user == null) return;
      if (state.bootstrappedUserId == user.id && state.bootstrapComplete) {
        return;
      }
      _bootstrap(user.id);
    });

    _ref.listen(authControllerProvider, (previous, next) {
      if (next.user != null) {
        final loadState = _ref.read(ledgerLoadStateProvider);
        if (!loadState.isReady) {
          state = state.copyWith(
            phase: CloudSyncPhase.checking,
            error: null,
            disabledReason: null,
            bootstrapComplete: false,
            bootstrappedUserId: null,
          );
          return;
        }
        _bootstrap(next.user!.id);
      } else {
        _disableSync();
      }
    });

    _ref.listen(ledgerProvider, (previous, next) {
      final user = _ref.read(authControllerProvider).user;
      if (user == null) return;
      if (state.bootstrappedUserId != user.id) return;
      if (_localClearInProgress) return;
      if (state.phase == CloudSyncPhase.restoring ||
          state.phase == CloudSyncPhase.checking) {
        return;
      }

      unawaited(checkAndTriggerSync());
    });

    final initialUser = _ref.read(authControllerProvider).user;
    final loadState = _ref.read(ledgerLoadStateProvider);
    if (initialUser != null) {
      if (loadState.isReady) {
        _bootstrap(initialUser.id);
      } else {
        state = state.copyWith(
          phase: CloudSyncPhase.checking,
          error: null,
          disabledReason: null,
          bootstrapComplete: false,
          bootstrappedUserId: null,
        );
      }
    } else {
      _disableSync();
    }
  }

  void _disableSync() {
    _userDocSubscription?.cancel();
    _userDocSubscription = null;
    _cancelTimers();
    state = const CloudSyncState(
      phase: CloudSyncPhase.disabled,
      disabledReason: 'Sign in with Google to enable sync.',
    );
  }

  void _cancelTimers() {
    _uploadTimer?.cancel();
    _uploadTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<void> updateSyncInterval(int? hours) async {
    var metadata = state.metadata ?? await CloudSyncMetadata.load();
    metadata = metadata.copyWith(syncIntervalHours: hours);
    await metadata.save();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_unsynced_changes', true);

    state = state.copyWith(metadata: metadata, pendingUpload: true);
    unawaited(checkAndTriggerSync());
  }

  Future<void> checkAndTriggerSync({
    bool fromResume = false,
    bool fromScreen = false,
  }) async {
    final user = _ref.read(authControllerProvider).user;
    if (user == null || state.phase == CloudSyncPhase.disabled) return;
    if (_localClearInProgress) return;
    if (state.phase == CloudSyncPhase.restoring ||
        state.phase == CloudSyncPhase.checking ||
        state.phase == CloudSyncPhase.uploading) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final hasUnsynced = prefs.getBool('has_unsynced_changes') ?? false;
    final isPending = hasUnsynced || state.pendingUpload;

    if (state.pendingUpload != isPending) {
      state = state.copyWith(pendingUpload: isPending);
    }

    if (!isPending) return;

    final interval = state.metadata?.syncIntervalHours;
    if (interval == null || interval <= 0) {
      _scheduleUpload();
      return;
    }

    final lastSyncStr = state.metadata?.lastPushedAt;
    if (lastSyncStr == null) {
      _scheduleUpload();
      return;
    }

    final lastSyncDate = DateTime.tryParse(lastSyncStr);
    if (lastSyncDate == null ||
        DateTime.now().difference(lastSyncDate).inMinutes >= (interval * 60)) {
      _scheduleUpload();
    }
  }

  Future<void> fullSync({required String reason}) async {
    final user = _ref.read(authControllerProvider).user;
    if (user == null) return;

    try {
      state = state.copyWith(phase: CloudSyncPhase.checking, error: null);

      final metadata = state.metadata ?? await CloudSyncMetadata.load();

      final userDoc = await _firestore
          .doc('users/${user.id}')
          .get()
          .timeout(cloudSyncReadTimeout);

      final cloudState = _cloudWriteStateFromDocData(userDoc.data());
      final lastWriterDeviceId = cloudState.lastWriterDeviceId;
      final cloudUpdatedAt = cloudState.updatedAt;
      final cloudRevision = cloudState.cloudRevision;

      final prefs = await SharedPreferences.getInstance();
      final hasUnsyncedChanges = prefs.getBool('has_unsynced_changes') ?? false;
      final localModifiedAtStr = prefs.getString('last_local_modified_at');
      final localModifiedAt = localModifiedAtStr != null
          ? DateTime.tryParse(localModifiedAtStr)
          : null;

      final bool shouldPull;
      if (!userDoc.exists) {
        shouldPull = false;
      } else {
        shouldPull = shouldPullCloudSnapshot(
          hasLocalUserData: _walletHasUserData(_ref.read(ledgerProvider)),
          hasUnsyncedLocalChanges: hasUnsyncedChanges,
          cloudUpdatedAt: cloudUpdatedAt,
          localModifiedAt: localModifiedAt,
          cloudRevision: cloudRevision,
          lastKnownCloudRevision: metadata.lastCloudRevision,
          cloudLastWriterDeviceId: lastWriterDeviceId,
          localDeviceId: metadata.deviceId,
        );
      }

      if (shouldPull) {
        await _restoreFromCloud(user.id, metadata);
      } else {
        await uploadSnapshot(reason: reason);
      }
    } catch (e) {
      state = state.copyWith(
        phase: CloudSyncPhase.error,
        error: 'Full sync failed: $e',
      );
    }
  }

  /// Explicitly replace the cloud wallet with this device's current ledger.
  ///
  /// The caller must obtain confirmation before invoking this method. We
  /// adopt a fresh cloud baseline here, then `uploadSnapshot` checks that
  /// baseline again inside its Firestore transaction so a write racing this
  /// read is still reported as a conflict instead of being overwritten.
  Future<void> overwriteCloudWithLocal() async {
    final user = _ref.read(authControllerProvider).user;
    if (user == null || state.phase == CloudSyncPhase.disabled) return;
    if (state.phase == CloudSyncPhase.checking ||
        state.phase == CloudSyncPhase.restoring ||
        state.phase == CloudSyncPhase.uploading) {
      return;
    }

    try {
      state = state.copyWith(
        phase: CloudSyncPhase.checking,
        error: null,
        pendingUpload: true,
      );
      final doc = await _firestore
          .doc('users/${user.id}')
          .get(const GetOptions(source: Source.server))
          .timeout(cloudSyncReadTimeout);
      final live = _cloudWriteStateFromDocData(doc.data());
      final metadata = state.metadata ?? await CloudSyncMetadata.load();
      final adopted = metadata.copyWith(
        lastCloudRevision: live.cloudRevision,
        lastObservedCloudUpdatedAt: live.updatedAt?.toUtc().toIso8601String(),
      );
      await adopted.save();
      state = state.copyWith(metadata: adopted, phase: CloudSyncPhase.idle);
      await uploadSnapshot(reason: 'user-overwrite');
    } catch (error) {
      state = state.copyWith(
        phase: CloudSyncPhase.error,
        pendingUpload: true,
        error: 'Could not prepare the cloud overwrite: $error',
      );
    }
  }

  /// Explicitly discard local unsynced changes and restore the current cloud
  /// snapshot. The caller must obtain confirmation before invoking this.
  Future<void> useCloudCopy() async {
    final user = _ref.read(authControllerProvider).user;
    if (user == null || state.phase == CloudSyncPhase.disabled) return;
    if (state.phase == CloudSyncPhase.checking ||
        state.phase == CloudSyncPhase.restoring ||
        state.phase == CloudSyncPhase.uploading) {
      return;
    }
    final metadata = state.metadata ?? await CloudSyncMetadata.load();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_unsynced_changes', false);
    await _restoreFromCloud(user.id, metadata);
    if (state.phase == CloudSyncPhase.error) {
      // A failed cloud read must never turn a local-only wallet into an
      // apparent clean state; otherwise a later background upload might
      // replace the cloud wallet without another explicit choice.
      await prefs.setBool('has_unsynced_changes', true);
      state = state.copyWith(pendingUpload: true);
    }
  }

  Future<void> _bootstrap(String userId) async {
    if (state.bootstrappedUserId == userId) return;
    try {
      state = state.copyWith(
        phase: CloudSyncPhase.checking,
        error: null,
        bootstrappedUserId: null,
      );

      await _userDocSubscription?.cancel();
      _userDocSubscription = null;

      var metadata = await CloudSyncMetadata.load();
      if (metadata.userId != userId) {
        metadata = metadata.copyWith(userId: userId);
        await metadata.save();
      }
      state = state.copyWith(metadata: metadata);

      final docs = await Future.wait([
        _firestore
            .doc('users/$userId/metadata/preferences')
            .get()
            .timeout(cloudSyncReadTimeout),
        _firestore.doc('users/$userId').get().timeout(cloudSyncReadTimeout),
      ]);
      final prefsDoc = docs[0];
      final userDoc = docs[1];

      // `metadata/preferences` is a legacy, pre-chunked-backup marker that
      // neither the current Flutter client nor the PWA writes anymore — the
      // PWA in particular only ever writes `users/{uid}` and
      // `wallet_backups/chunk_N`. Gating on `prefsDoc.exists` alone would
      // make Flutter blind to any PWA-created (or modern Flutter-created)
      // wallet: an empty local ledger would wrongly fall into the
      // "no cloud data" seed/idle path instead of pulling it, and a
      // non-empty local ledger could seed right over it. `userDoc.exists`
      // is written by every client on every successful upload (chunked or
      // legacy), so it's a strictly more complete "has this account ever
      // synced" signal; `prefsDoc.exists` is kept only as a belt-and-braces
      // fallback for the (practically unreachable today) case of an
      // ancient account that has legacy per-document data but somehow never
      // wrote `users/{uid}` either.
      final walletDataExists = hasCloudWalletData(
        userDocExists: userDoc.exists,
        legacyPreferencesDocExists: prefsDoc.exists,
      );

      if (walletDataExists) {
        final cloudState = _cloudWriteStateFromDocData(userDoc.data());
        final lastWriterDeviceId = cloudState.lastWriterDeviceId;
        final cloudUpdatedAt = cloudState.updatedAt;
        final cloudRevision = cloudState.cloudRevision;

        final hasUserData = _walletHasUserData(_ref.read(ledgerProvider));
        final prefs = await SharedPreferences.getInstance();
        final hasUnsyncedChanges =
            prefs.getBool('has_unsynced_changes') ?? false;
        final localModifiedAtStr = prefs.getString('last_local_modified_at');
        final localModifiedAt = localModifiedAtStr != null
            ? DateTime.tryParse(localModifiedAtStr)
            : null;

        debugPrint(
          'CloudSync _bootstrap: userDoc.exists=${userDoc.exists}, lastWriterDeviceId=$lastWriterDeviceId, metadata.deviceId=${metadata.deviceId}, hasUserData=$hasUserData, hasUnsyncedChanges=$hasUnsyncedChanges, localModifiedAt=$localModifiedAt, cloudUpdatedAt=$cloudUpdatedAt',
        );

        final bool shouldPull = shouldPullCloudSnapshot(
          hasLocalUserData: hasUserData,
          hasUnsyncedLocalChanges: hasUnsyncedChanges,
          cloudUpdatedAt: cloudUpdatedAt,
          localModifiedAt: localModifiedAt,
          cloudRevision: cloudRevision,
          lastKnownCloudRevision: metadata.lastCloudRevision,
          cloudLastWriterDeviceId: lastWriterDeviceId,
          localDeviceId: metadata.deviceId,
        );

        if (shouldPull) {
          // We have cloud data (chunked, via `userDoc`/`wallet_backups`, or
          // the ancient legacy per-document fallback via `prefsDoc` alone —
          // `_restoreFromCloud` itself already handles that fallback
          // regardless of whether `userDoc` exists). Restore it locally.
          await _restoreFromCloud(userId, metadata);
        }

        // Migrate rules from preferences to transactions if needed
        final currentLedger = _ref.read(ledgerProvider);

        final existingRuleIds = currentLedger.transactions
            .map((t) => t.id)
            .toSet();
        final rulesToConvert = <FutureGenerationRule>[];

        // 1. Check if we already have rules in current preferences
        if (currentLedger.preferences.futureGenerationRules != null) {
          for (final rule in currentLedger.preferences.futureGenerationRules!) {
            if (!existingRuleIds.contains(rule.id)) {
              rulesToConvert.add(rule);
            }
          }
        }

        if (rulesToConvert.isNotEmpty) {
          final newTransactions = <TransactionRecord>[];
          for (final rule in rulesToConvert) {
            newTransactions.add(
              TransactionRecord(
                id: rule.id,
                type: rule.type,
                status: 'scheduled',
                source: 'recurring',
                accountId: rule.accountId,
                counterAccountId: rule.counterAccountId,
                amount: Money(
                  amountMinor: rule.amountMinor,
                  currency: rule.currency,
                ),
                baseAmount: Money(
                  amountMinor: rule.amountMinor,
                  currency: rule.currency,
                ),
                occurredAt: rule.startsOn,
                categoryId: rule.categoryId,
                recurrenceFrequency: rule.frequency,
                notes: rule.name,
                paymentMethod: rule.paymentMethod,
              ),
            );
          }

          final mergedPreferences = currentLedger.preferences.copyWith(
            futureGenerationRules: rulesToConvert.toList(),
          );

          // Fix any already-migrated rules that accidentally got 'planned' status
          final updatedTransactions = currentLedger.transactions.map((t) {
            if (t.status == 'planned') {
              return t.copyWith(status: 'scheduled');
            }
            return t;
          }).toList();

          final mergedTransactions = [
            ...updatedTransactions,
            ...newTransactions,
          ];
          await _ledger.restoreLedgerState(
            currentLedger.copyWith(
              preferences: mergedPreferences,
              transactions: mergedTransactions,
            ),
          );
          await uploadSnapshot(reason: 'migration_rules');
        } else {
          // If no new rules to convert, just check if we need to fix statuses
          final hasPlannedStatus = currentLedger.transactions.any(
            (t) => t.status == 'planned',
          );
          if (hasPlannedStatus) {
            final updatedTransactions = currentLedger.transactions.map((t) {
              if (t.status == 'planned') {
                return t.copyWith(status: 'scheduled');
              }
              return t;
            }).toList();
            await _ledger.restoreLedgerState(
              currentLedger.copyWith(transactions: updatedTransactions),
            );
            await uploadSnapshot(reason: 'migration_fix_status');
          }
        }

        if (!shouldPull && hasUnsyncedChanges) {
          state = state.copyWith(
            phase: CloudSyncPhase.idle,
            pendingUpload: true,
          );
        }
      } else {
        // No cloud wallet data of any kind (neither the modern chunked
        // backup nor the legacy per-document collections) — a genuinely
        // fresh account.
        if (_walletHasUserData(_ref.read(ledgerProvider))) {
          // No cloud data, but we have local data. Push local to cloud.
          await uploadSnapshot(reason: 'seed');
        } else {
          state = state.copyWith(phase: CloudSyncPhase.idle);
        }
      }

      state = state.copyWith(
        phase: state.phase == CloudSyncPhase.checking
            ? CloudSyncPhase.idle
            : state.phase,
        bootstrappedUserId: userId,
        bootstrapComplete: true,
      );

      _userDocSubscription = _firestore
          .doc('users/$userId')
          .snapshots()
          .skip(1)
          .listen(
            (snapshot) {
              _handleCloudUpdate(snapshot);
            },
            onError: (e) {
              debugPrint('CloudSync userDoc subscription error: $e');
            },
          );

      unawaited(checkAndTriggerSync());
    } on TimeoutException catch (e) {
      debugPrint('Cloud sync bootstrap timeout, fetching actual error...');
      Object actualError = e;
      try {
        await _firestore
            .doc('users/$userId')
            .get(const GetOptions(source: Source.server));
      } catch (fe) {
        actualError = fe;
      }
      state = state.copyWith(
        phase: CloudSyncPhase.error,
        error: 'Network timeout / Quota hit. Actual error: $actualError',
        bootstrappedUserId: null,
      );
    } catch (e) {
      debugPrint('Cloud sync bootstrap error: $e');
      state = state.copyWith(
        phase: CloudSyncPhase.error,
        error: 'Could not prepare sync: $e',
        bootstrappedUserId: null,
      );
    }
  }

  void _scheduleUpload() {
    state = state.copyWith(pendingUpload: true);
    _uploadTimer?.cancel();
    _uploadTimer = Timer(const Duration(milliseconds: uploadDebounceMs), () {
      _uploadTimer = null;
      uploadSnapshot(reason: 'auto');
    });
  }

  Future<void> uploadSnapshot({required String reason}) async {
    final user = _ref.read(authControllerProvider).user;
    if (user == null) return;

    if (reason == 'auto') {
      if (state.phase == CloudSyncPhase.checking ||
          state.phase == CloudSyncPhase.restoring) {
        state = state.copyWith(pendingUpload: true);
        return;
      }
      if (DateTime.now().millisecondsSinceEpoch < _uploadCircuitOpenUntil) {
        state = state.copyWith(pendingUpload: true);
        return;
      }
    }

    try {
      final currentLedger = _ref.read(ledgerProvider);
      var metadata = state.metadata ?? await CloudSyncMetadata.load();

      state = state.copyWith(
        pendingUpload: false,
        phase: CloudSyncPhase.uploading,
        error: null,
      );

      final userRef = _firestore.doc('users/${user.id}');

      // Baseline for the conflict check: what this device's *in-memory
      // ledger* (about to be serialized below) is actually known to be
      // consistent with — i.e. the cloud state observed at the last
      // successful push or pull — not a value read fresh right before this
      // write attempt. A fresh pre-write read would reflect any remote
      // write that landed between this ledger being loaded and this upload
      // starting, and comparing against *that* would make the conflict
      // check see "no change" even though this ledger doesn't actually
      // contain whatever just landed remotely, silently clobbering it.
      final expectedState = CloudWriteState(
        cloudRevision: metadata.lastCloudRevision,
        updatedAt: metadata.lastObservedCloudUpdatedAt != null
            ? DateTime.tryParse(metadata.lastObservedCloudUpdatedAt!)
            : null,
      );

      final encodedData = await compute(_encodeCloudSnapshotData, (
        currentLedger,
        {'syncIntervalHours': metadata.syncIntervalHours},
      ));

      final jsonStr = jsonEncode(encodedData);
      final bytes = utf8.encode(jsonStr);
      final compressedBytes = GZipEncoder().encode(bytes);

      const chunkSize = 900 * 1024; // 900 KB limit for Firestore Blobs
      final chunks = <Uint8List>[];
      for (var i = 0; i < compressedBytes.length; i += chunkSize) {
        final end = (i + chunkSize < compressedBytes.length)
            ? i + chunkSize
            : compressedBytes.length;
        chunks.add(Uint8List.fromList(compressedBytes.sublist(i, end)));
      }

      // Discover existing trailing chunks to prune *before* the transaction
      // (Firestore transactions can't run collection queries, only get()
      // individual doc refs) so we can enforce the write-count ceiling up
      // front and pass exact doc refs into the transaction to delete.
      final existingChunksSnapshot = await _firestore
          .collection('users/${user.id}/wallet_backups')
          .get();
      final existingChunkIndices = <int>[];
      for (final doc in existingChunksSnapshot.docs) {
        final match = RegExp(r'^chunk_(\d+)$').firstMatch(doc.id);
        final index = match != null ? int.tryParse(match.group(1)!) : null;
        if (index != null) existingChunkIndices.add(index);
      }
      final staleChunkIndices = staleCloudSyncChunkIndices(
        existingChunkIndices: existingChunkIndices,
        newChunkCount: chunks.length,
      );

      ensureWithinCloudSyncWriteBudget(
        newChunkCount: chunks.length,
        staleChunkCount: staleChunkIndices.length,
        totalBytes: compressedBytes.length,
      );

      // Captured once, client-side, right before the transaction — and
      // written verbatim as `users/{uid}.updatedAt` below — instead of
      // `FieldValue.serverTimestamp()`. A server timestamp resolves lazily
      // on the server and is never visible to this client, so persisting
      // "now" as an approximation of it after commit would always be a
      // slightly different value than what actually landed; since the
      // conflict/version-stability checks now compare `updatedAt` for
      // *exact* equality even when `cloudRevision` matches (to catch an old
      // client bumping only `updatedAt`), that mismatch would make this
      // device's own next upload look like a conflict against itself. Using
      // one concrete `Timestamp` for both the write and the persisted
      // baseline makes the round trip exact, so a genuine self-comparison
      // never false-positives.
      //
      // Normalized to millisecond precision — `DateTime.now()` (and
      // `Timestamp.now()`, which derives from it) carries microsecond
      // precision on Dart, but the PWA's Firestore JS SDK `Timestamp.now()`
      // is built from `Date.now()`, which is millisecond-only. Writing a
      // sub-millisecond-precision value here would make an old
      // `FieldValue.serverTimestamp()` write from another client (which
      // Firestore *does* resolve with full precision server-side) merely
      // *coincidentally* line up with a microsecond-truncated comparison,
      // while making it impossible for the two clients to ever agree
      // bit-for-bit on a value either of them captured client-side.
      // Truncating to milliseconds on both sides keeps "exact equality"
      // well-defined across clients, and any other writer's timestamp
      // landing at a different moment (even a different millisecond) is
      // still observably different, so the conflict check still fires.
      final writeTimestamp = Timestamp.fromMillisecondsSinceEpoch(
        DateTime.now().millisecondsSinceEpoch,
      );

      final nextRevision = await _firestore
          .runTransaction<int>((transaction) async {
            final liveSnap = await transaction.get(userRef);
            final liveState = _cloudWriteStateFromDocData(liveSnap.data());

            if (hasCloudSyncConflict(
              expected: expectedState,
              live: liveState,
            )) {
              throw const CloudSyncConflictException();
            }

            final revision = nextCloudRevision(liveState.cloudRevision);

            transaction.set(userRef, {
              'email': user.email,
              'displayName': user.displayName,
              'authProvider': 'google',
              'updatedAt': writeTimestamp,
              'lastWriterDeviceId': metadata.deviceId,
              'cloudRevision': revision,
            }, SetOptions(merge: true));

            for (var i = 0; i < chunks.length; i++) {
              transaction.set(
                _firestore.doc('users/${user.id}/wallet_backups/chunk_$i'),
                {
                  'index': i,
                  'data': Blob(chunks[i]),
                  'updatedAt': FieldValue.serverTimestamp(),
                },
              );
            }
            for (final index in staleChunkIndices) {
              transaction.delete(
                _firestore.doc('users/${user.id}/wallet_backups/chunk_$index'),
              );
            }

            return revision;
          })
          .timeout(cloudSyncReadTimeout);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_unsynced_changes', false);

      final now = DateTime.now().toIso8601String();
      metadata = metadata.copyWith(
        userId: user.id,
        lastPushedAt: now,
        lastCloudRevision: nextRevision,
        // The exact same millisecond-precision `Timestamp` just committed as
        // `users/{uid}.updatedAt` (converted through `.toDate().toUtc()` the
        // same way `_cloudWriteStateFromDocData` does when reading it back),
        // not a separately-captured `DateTime.now()` approximation — see the
        // comment above `writeTimestamp` for why an approximation, or a
        // sub-millisecond-precision value, would make this device's own next
        // upload falsely conflict with itself (or with a PWA-written
        // timestamp of matching millisecond but no finer precision).
        lastObservedCloudUpdatedAt: writeTimestamp
            .toDate()
            .toUtc()
            .toIso8601String(),
        // We no longer track individual synced IDs since the whole blob is synced
        syncedDocumentHashes: {},
      );
      await metadata.save();

      _uploadFailureCount = 0;
      _uploadCircuitOpenUntil = 0;
      state = state.copyWith(phase: CloudSyncPhase.idle, metadata: metadata);
      debugPrint(
        'uploadSnapshot: completed successfully! revision=$nextRevision',
      );
    } on CloudSyncConflictException catch (e) {
      debugPrint(
        'uploadSnapshot: conflict detected ($e), resolving without blind retry',
      );
      // Never blindly retry the same stale write — see
      // `CloudSyncConflictResolution`'s doc comment in
      // `cloud_sync_write_guard.dart` for why the previous
      // `unawaited(fullSync(reason: 'conflict-recheck'))` here could recurse
      // indefinitely. `_resolveUploadConflict` below can only ever pull (if
      // safe) or leave this conflict state as-is; it never re-invokes
      // `uploadSnapshot()`.
      state = state.copyWith(
        pendingUpload: true,
        phase: CloudSyncPhase.error,
        error: '$e',
      );
      unawaited(_resolveUploadConflict(user.id));
    } on CloudSyncOversizeException catch (e) {
      debugPrint('uploadSnapshot: oversize snapshot ($e)');
      // Retrying automatically cannot fix this; surface it distinctly and
      // don't schedule another attempt until the underlying data shrinks.
      state = state.copyWith(
        pendingUpload: false,
        phase: CloudSyncPhase.error,
        error: '$e',
      );
    } on CloudSyncRevisionOverflowException catch (e) {
      debugPrint('uploadSnapshot: cloudRevision overflow ($e)');
      // Practically unreachable (2^31-1 successful syncs), but retrying
      // automatically cannot fix this either — surface it distinctly rather
      // than let it hit Firestore rules' int32 bound and come back as an
      // opaque permission-denied rejection.
      state = state.copyWith(
        pendingUpload: false,
        phase: CloudSyncPhase.error,
        error: '$e',
      );
    } on TimeoutException catch (e) {
      debugPrint('uploadSnapshot: timeout exception, fetching actual error...');
      _uploadFailureCount++;
      if (_uploadFailureCount >= uploadFailureCircuitBreakerThreshold) {
        _uploadCircuitOpenUntil =
            DateTime.now().millisecondsSinceEpoch + uploadCircuitBreakerMs;
      }
      Object actualError = e;
      try {
        await _firestore
            .doc('users/${user.id}')
            .get(const GetOptions(source: Source.server));
      } catch (fe) {
        actualError = fe;
      }
      state = state.copyWith(
        pendingUpload: true,
        phase: CloudSyncPhase.error,
        error: 'Network timeout / Quota hit. Actual error: $actualError',
      );
    } catch (e) {
      debugPrint('uploadSnapshot: caught error $e');
      _uploadFailureCount++;
      if (_uploadFailureCount >= uploadFailureCircuitBreakerThreshold) {
        _uploadCircuitOpenUntil =
            DateTime.now().millisecondsSinceEpoch + uploadCircuitBreakerMs;
      }
      state = state.copyWith(
        pendingUpload: true,
        phase: CloudSyncPhase.error,
        error: 'Could not sync your wallet to Firebase collections: $e',
      );
    }
  }

  /// Resolves an `uploadSnapshot()` conflict without ever blindly retrying
  /// the same stale write and without ever pulling over unsynced local
  /// edits — see the comment above [CloudSyncConflictResolution].
  ///
  /// Re-reads the live cloud state fresh (the conflict may already be
  /// resolved, or superseded again, by the time this runs), feeds it
  /// through the same [shouldPullCloudSnapshot] signal `fullSync`/
  /// `_bootstrap` use, then [resolveCloudSyncConflict] to decide what to do.
  /// That decision has no "push again" outcome, so this method can never
  /// recurse back into `uploadSnapshot()`.
  Future<void> _resolveUploadConflict(String userId) async {
    try {
      final metadata = state.metadata ?? await CloudSyncMetadata.load();

      final userDoc = await _firestore
          .doc('users/$userId')
          .get()
          .timeout(cloudSyncReadTimeout);
      final cloudState = _cloudWriteStateFromDocData(userDoc.data());

      final prefs = await SharedPreferences.getInstance();
      final hasUnsyncedChanges = prefs.getBool('has_unsynced_changes') ?? false;
      final localModifiedAtStr = prefs.getString('last_local_modified_at');
      final localModifiedAt = localModifiedAtStr != null
          ? DateTime.tryParse(localModifiedAtStr)
          : null;

      final shouldPull =
          userDoc.exists &&
          shouldPullCloudSnapshot(
            hasLocalUserData: _walletHasUserData(_ref.read(ledgerProvider)),
            hasUnsyncedLocalChanges: hasUnsyncedChanges,
            cloudUpdatedAt: cloudState.updatedAt,
            localModifiedAt: localModifiedAt,
            cloudRevision: cloudState.cloudRevision,
            lastKnownCloudRevision: metadata.lastCloudRevision,
            cloudLastWriterDeviceId: cloudState.lastWriterDeviceId,
            localDeviceId: metadata.deviceId,
          );

      final resolution = resolveCloudSyncConflict(
        hasUnsyncedLocalChanges: hasUnsyncedChanges,
        shouldPull: shouldPull,
      );

      if (resolution == CloudSyncConflictResolution.pullCloudSnapshot) {
        await _restoreFromCloud(userId, metadata);
      }
      // The other two outcomes are deliberately no-ops here: uploadSnapshot()
      // already left `pendingUpload: true` and a conflict error in state, so
      // local data stays exactly as it is until a later legitimate trigger
      // (a new local edit, app resume, or explicit user action) re-attempts
      // the sync from scratch.
    } catch (e) {
      // A failure re-checking the cloud state (e.g. offline) shouldn't
      // clobber the conflict error uploadSnapshot() already surfaced —
      // leave it as-is; the next legitimate trigger will try again.
      debugPrint('_resolveUploadConflict: re-check failed ($e)');
    }
  }

  Future<void> _restoreFromCloud(
    String userId,
    CloudSyncMetadata currentMetadata,
  ) async {
    state = state.copyWith(phase: CloudSyncPhase.restoring, error: null);
    try {
      // Bracket the bulk chunk/legacy-collection download with two cheap
      // `users/{uid}` version reads, retrying the whole cycle if they
      // disagree — otherwise, if another atomic snapshot write lands while
      // the download is in flight, the downloaded content and the
      // `cloudRevision`/`updatedAt` we'd record as "what we just synced to"
      // could describe two different versions (e.g. we download the OLD
      // chunks but record the NEW cloudRevision, or vice versa).
      final (
        restoreData,
        verifiedVersion,
      ) = await readCloudSyncVersionConsistent<Map<String, dynamic>>(
        readVersionToken: () async {
          final snap = await _firestore
              .doc('users/$userId')
              .get()
              .timeout(cloudSyncReadTimeout);
          return _cloudWriteStateFromDocData(snap.data());
        },
        fetchPayload: () => _fetchCloudRestoreData(userId),
      );
      final cloudUpdatedAt = verifiedVersion.updatedAt;
      final cloudRevision = verifiedVersion.cloudRevision;

      state = state.copyWith(
        progressMessage: 'Loading transactions...',
        progress: 0.95,
      );
      final ledger = await compute(_parseCloudRestoreData, restoreData);

      final prefs = await SharedPreferences.getInstance();
      final hasUnsyncedChanges = prefs.getBool('has_unsynced_changes') ?? false;

      // `readCloudSyncVersionConsistent` above already positively verified
      // `ledger` accurately reflects this specific cloud revision — it is
      // not a heuristic guess, it *is* the current cloud state. The only
      // thing left worth protecting is this device's own unsynced edits: a
      // legitimate deletion (or an emptied wallet) must be allowed through
      // even though it has fewer transactions than local — the previous
      // count/timestamp heuristic (`LedgerState.isIncomingLedgerSafer`)
      // rejected exactly that case, permanently preventing deletions from
      // ever syncing down to this device.
      if (!shouldAcceptCloudRestore(
        hasUnsyncedLocalChanges: hasUnsyncedChanges,
      )) {
        state = state.copyWith(
          phase: CloudSyncPhase.idle,
          progress: 1.0,
          error:
              'Cloud sync conflict: local changes have not been uploaded '
              'yet. Local data kept; upload will retry automatically.',
          pendingUpload: true,
        );
        return;
      }

      await _ledger.restoreLedgerState(ledger);

      await prefs.setBool('has_unsynced_changes', false);
      if (cloudUpdatedAt != null) {
        await prefs.setString(
          'last_local_modified_at',
          cloudUpdatedAt.toUtc().toIso8601String(),
        );
      } else {
        await prefs.remove('last_local_modified_at');
      }

      final syncSettings = restoreData['syncSettings'] as Map<String, dynamic>?;
      int? restoredInterval = currentMetadata.syncIntervalHours;
      if (syncSettings != null &&
          syncSettings.containsKey('syncIntervalHours')) {
        restoredInterval = syncSettings['syncIntervalHours'] as int?;
      }

      final newMetadata = currentMetadata.copyWith(
        userId: userId,
        lastPulledAt: DateTime.now().toIso8601String(),
        lastCloudRevision: cloudRevision ?? currentMetadata.lastCloudRevision,
        lastObservedCloudUpdatedAt: cloudUpdatedAt != null
            ? cloudUpdatedAt.toUtc().toIso8601String()
            : currentMetadata.lastObservedCloudUpdatedAt,
        syncedDocumentHashes: {},
        syncIntervalHours: restoredInterval,
      );
      await newMetadata.save();

      state = state.copyWith(
        phase: CloudSyncPhase.idle,
        metadata: newMetadata,
        progress: 1.0,
        error: null,
      );
    } on CloudSyncUnstableException catch (e) {
      developer.log('Firebase restore unstable', error: e);
      state = state.copyWith(phase: CloudSyncPhase.error, error: '$e');
    } catch (e, st) {
      developer.log('Firebase restore failed', error: e, stackTrace: st);
      state = state.copyWith(
        phase: CloudSyncPhase.error,
        error: 'Failed to restore your wallet data.',
      );
    }
  }

  /// Downloads and decodes the wallet snapshot: the compressed
  /// `wallet_backups/chunk_N` blobs, falling back to the legacy
  /// per-document collections if no compressed backup exists yet. Pulled
  /// out of `_restoreFromCloud` so it can be re-run wholesale by
  /// [readCloudSyncVersionConsistent] if the cloud state turns out to have
  /// changed mid-download.
  Future<Map<String, dynamic>> _fetchCloudRestoreData(String userId) async {
    final backupQuery = await _firestore
        .collection('users/$userId/wallet_backups')
        .orderBy('index')
        .get()
        .timeout(cloudSyncReadTimeout);

    Map<String, dynamic> restoreData;

    if (backupQuery.docs.isNotEmpty) {
      state = state.copyWith(
        progressMessage: 'Downloading backup...',
        progress: 0.1,
      );
      final compressedBytes = <int>[];
      int processedChunks = 0;
      final totalChunks = backupQuery.docs.length;

      for (final doc in backupQuery.docs) {
        final blob = doc.data()['data'] as Blob?;
        if (blob != null) {
          compressedBytes.addAll(blob.bytes);
        }
        processedChunks++;
        state = state.copyWith(
          progressMessage:
              'Downloading chunk $processedChunks of $totalChunks...',
          progress: 0.1 + (0.7 * (processedChunks / totalChunks)),
        );
      }

      state = state.copyWith(
        progressMessage: 'Extracting data...',
        progress: 0.85,
      );
      // Using compute for heavy unzipping
      final bytes = await compute(_decodeGzipBytes, compressedBytes);
      final jsonStr = await compute(utf8.decode, bytes);
      restoreData = await compute(jsonDecode, jsonStr) as Map<String, dynamic>;
      restoreData['userId'] = userId;
    } else {
      state = state.copyWith(
        progressMessage: 'Loading legacy collections...',
        progress: 0.5,
      );
      // Fallback to legacy uncompressed collections if no compressed backup exists
      final results = await Future.wait([
        _firestore.collection('users/$userId/accounts').get(),
        _firestore.collection('users/$userId/categories').get(),
        _firestore.collection('users/$userId/transactions').get(),
        _firestore.collection('users/$userId/captureCandidates').get(),
        _firestore.collection('users/$userId/importBatches').get(),
        _firestore.doc('users/$userId/metadata/preferences').get(),
      ]).timeout(const Duration(seconds: 45));

      final accountsQuery = results[0] as QuerySnapshot<Map<String, dynamic>>;
      final categoriesQuery = results[1] as QuerySnapshot<Map<String, dynamic>>;
      final txnsQuery = results[2] as QuerySnapshot<Map<String, dynamic>>;
      final captureQuery = results[3] as QuerySnapshot<Map<String, dynamic>>;
      final importsQuery = results[4] as QuerySnapshot<Map<String, dynamic>>;
      final prefsDoc = results[5] as DocumentSnapshot<Map<String, dynamic>>;

      restoreData = {
        'userId': userId,
        'preferences': prefsDoc.exists ? prefsDoc.data() : null,
        'accounts': accountsQuery.docs.map((d) => d.data()).toList(),
        'categories': categoriesQuery.docs.map((d) => d.data()).toList(),
        'transactions': txnsQuery.docs.map((d) => d.data()).toList(),
        'captureCandidates': captureQuery.docs.map((d) => d.data()).toList(),
        'importBatches': importsQuery.docs.map((d) => d.data()).toList(),
      };
    }

    return restoreData;
  }

  Future<void> prepareForLocalClear() async {
    _localClearInProgress = true;
    _cancelTimers();
    final user = _ref.read(authControllerProvider).user;
    if (user == null) return;
    if (state.pendingUpload) {
      await uploadSnapshot(reason: 'auto');
    }
  }

  void resumeAfterLocalClear() {
    _localClearInProgress = false;
  }

  void skipBootstrap() {
    final user = _ref.read(authControllerProvider).user;
    if (user == null) return;

    state = state.copyWith(
      phase: CloudSyncPhase.idle,
      bootstrapComplete: true,
      bootstrappedUserId: user.id,
      error: 'Restoration skipped. You are working with local data.',
    );
  }

  void retryBootstrap() {
    _cancelTimers();
    _uploadFailureCount = 0;
    _uploadCircuitOpenUntil = 0;

    final user = _ref.read(authControllerProvider).user;
    if (user == null) {
      _disableSync();
      return;
    }

    state = state.copyWith(
      phase: CloudSyncPhase.checking,
      error: null,
      disabledReason: null,
      pendingUpload: false,
      bootstrapComplete: false,
      bootstrappedUserId: null,
    );

    final loadState = _ref.read(ledgerLoadStateProvider);
    if (loadState.isReady) {
      _bootstrap(user.id);
    }
  }

  bool _walletHasUserData(LedgerState ledger) {
    return ledger.accounts.isNotEmpty || ledger.transactions.isNotEmpty;
  }

  Future<void> _handleCloudUpdate(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) async {
    final user = _ref.read(authControllerProvider).user;
    if (user == null || state.phase == CloudSyncPhase.disabled) return;
    if (_localClearInProgress) return;
    if (state.phase == CloudSyncPhase.restoring ||
        state.phase == CloudSyncPhase.checking ||
        state.phase == CloudSyncPhase.uploading) {
      return;
    }
    if (!snapshot.exists) return;

    // Reuse the exact same `shouldPullCloudSnapshot()` decision
    // `fullSync()`/`_bootstrap()`/`_resolveUploadConflict()` use, instead of
    // a hand-rolled duplicate — an earlier version of this handler computed
    // its own `isCloudNewer`/`shouldPull` inline and, in doing so, silently
    // dropped the `cloudRevision`-ahead signal entirely (relying on
    // `updatedAt` alone, which clock skew can make an unreliable proxy for
    // "the cloud actually moved forward"). Note this is only the "is it
    // worth checking" decision: the actual apply is still independently
    // gated by `shouldAcceptCloudRestore()` inside `_restoreFromCloud()`,
    // which refuses to overwrite unsynced local edits regardless of what
    // triggered the call.
    final cloudState = _cloudWriteStateFromDocData(snapshot.data());
    if (cloudState.updatedAt == null) return;

    final metadata = state.metadata ?? await CloudSyncMetadata.load();
    final prefs = await SharedPreferences.getInstance();
    final hasUnsyncedChanges = prefs.getBool('has_unsynced_changes') ?? false;
    final localModifiedAtStr = prefs.getString('last_local_modified_at');
    final localModifiedAt = localModifiedAtStr != null
        ? DateTime.tryParse(localModifiedAtStr)
        : null;

    final shouldPull = shouldPullCloudSnapshot(
      hasLocalUserData: _walletHasUserData(_ref.read(ledgerProvider)),
      hasUnsyncedLocalChanges: hasUnsyncedChanges,
      cloudUpdatedAt: cloudState.updatedAt,
      localModifiedAt: localModifiedAt,
      cloudRevision: cloudState.cloudRevision,
      lastKnownCloudRevision: metadata.lastCloudRevision,
      cloudLastWriterDeviceId: cloudState.lastWriterDeviceId,
      localDeviceId: metadata.deviceId,
    );

    if (shouldPull) {
      debugPrint('Real-time sync: Cloud update detected. Pulling changes...');
      await _restoreFromCloud(user.id, metadata);
    }
  }

  @override
  void dispose() {
    _userDocSubscription?.cancel();
    _cancelTimers();
    super.dispose();
  }
}

/// Builds a [CloudWriteState] from a `users/{uid}` document's raw data,
/// tolerating both the legacy string-encoded `updatedAt` and the current
/// server [Timestamp], and a missing/absent `cloudRevision` (old clients).
CloudWriteState _cloudWriteStateFromDocData(Map<String, dynamic>? data) {
  if (data == null) return CloudWriteState.unknown;

  DateTime? updatedAt;
  final updatedAtRaw = data['updatedAt'];
  if (updatedAtRaw is Timestamp) {
    updatedAt = updatedAtRaw.toDate();
  } else if (updatedAtRaw is String) {
    updatedAt = DateTime.tryParse(updatedAtRaw);
  }

  return CloudWriteState(
    cloudRevision: data['cloudRevision'] as int?,
    updatedAt: updatedAt,
    lastWriterDeviceId: data['lastWriterDeviceId'] as String?,
  );
}

LedgerState _parseCloudRestoreData(Map<String, dynamic> data) {
  final userId = data['userId'] as String;
  final prefsData = data['preferences'] as Map<String, dynamic>?;
  final accountsData = data['accounts'] as List;
  final categoriesData = data['categories'] as List;
  final transactionsData = data['transactions'] as List;
  final captureData = data['captureCandidates'] as List?;
  final importsData = data['importBatches'] as List?;
  final exchangeRatesData = data['exchangeRates'] as List?;

  return normalizeLedgerState(
    emptyLedgerState(userId: userId).copyWith(
      preferences: prefsData != null
          ? preferencesFromJson(prefsData)
          : const LedgerPreferences(),
      accounts: accountsData
          .map((d) => accountFromJson(d as Map<String, dynamic>))
          .toList(),
      categories: categoriesData
          .map((d) => categoryFromJson(d as Map<String, dynamic>))
          .toList(),
      transactions: transactionsData
          .map((d) => transactionFromJson(d as Map<String, dynamic>))
          .toList(),

      captureCandidates:
          captureData
              ?.map((d) => captureCandidateFromJson(d as Map<String, dynamic>))
              .toList() ??
          [],
      importBatches:
          importsData
              ?.map((d) => importBatchFromJson(d as Map<String, dynamic>))
              .toList() ??
          [],
      exchangeRates:
          exchangeRatesData
              ?.map((d) => exchangeRateFromJson(d as Map<String, dynamic>))
              .toList() ??
          [],
    ),
    // Cloud snapshots can arrive from a peer (another device, or the PWA)
    // whose own local state has since diverged — e.g. a category deleted on
    // one device after this snapshot's transactions last referenced it — so
    // orphaned category references can't be assumed absent the way they can
    // for `_commit()`'s own incrementally-maintained local state. Force the
    // full scan here; `_commit()` itself keeps the default fast no-op path
    // since its state is already known-consistent incrementally.
    forceFullCategoryReferenceScan: true,
  );
}

/// Test-only public alias for [_parseCloudRestoreData]. Dart's privacy is
/// per-library (per-file, since this file has no `part`/`part of`), so a
/// `test/`-side test can't otherwise call this file-private top-level
/// function directly to verify it passes `forceFullCategoryReferenceScan:
/// true` to [normalizeLedgerState]. Behaves identically to the private
/// function — this only widens visibility for testing.
@visibleForTesting
LedgerState parseCloudRestoreDataForTesting(Map<String, dynamic> data) =>
    _parseCloudRestoreData(data);

Map<String, dynamic> _encodeCloudSnapshotData(
  (LedgerState, Map<String, dynamic>?) input,
) {
  final ledger = input.$1;
  final syncSettings = input.$2;
  return {
    'syncSettings': syncSettings,
    'preferences': preferencesToJson(
      ledger.preferences,
    ).cast<String, dynamic>(),
    'accounts': ledger.accounts
        .map((a) => accountToJson(a).cast<String, dynamic>())
        .toList(),
    'categories': ledger.categories
        .map((c) => categoryToJson(c).cast<String, dynamic>())
        .toList(),
    'transactions': ledger.transactions
        .map((t) => transactionToJson(t).cast<String, dynamic>())
        .toList(),

    'captureCandidates': ledger.captureCandidates
        .map((c) => captureCandidateToJson(c).cast<String, dynamic>())
        .toList(),
    'importBatches': ledger.importBatches
        .map((i) => importBatchToJson(i).cast<String, dynamic>())
        .toList(),
    'exchangeRates': ledger.exchangeRates
        .map((r) => exchangeRateToJson(r).cast<String, dynamic>())
        .toList(),
  };
}

List<int> _decodeGzipBytes(List<int> bytes) {
  return GZipDecoder().decodeBytes(bytes);
}
