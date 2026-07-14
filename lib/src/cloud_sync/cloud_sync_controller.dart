import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';
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
import 'cloud_restore_controller.dart';
import 'cloud_sync_metadata.dart';

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
  Timer? _periodicSyncTimer;
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

      if (state.metadata?.syncIntervalHours == null) {
        _scheduleUpload();
      } else {
        state = state.copyWith(pendingUpload: true);
        // If they have an interval set but haven't synced in that interval, we should trigger it.
        final lastSync = state.metadata?.lastPushedAt;
        if (lastSync != null) {
          final lastSyncDate = DateTime.tryParse(lastSync);
          if (lastSyncDate != null && DateTime.now().difference(lastSyncDate).inHours >= state.metadata!.syncIntervalHours!) {
            _scheduleUpload();
          }
        }
      }
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
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
  }

  void _setupPeriodicSync() {
    _periodicSyncTimer?.cancel();
    final interval = state.metadata?.syncIntervalHours;
    if (interval == null || interval <= 0) return;

    _periodicSyncTimer = Timer.periodic(Duration(hours: interval), (timer) {
      final user = _ref.read(authControllerProvider).user;
      if (user != null && state.phase == CloudSyncPhase.idle) {
        fullSync(reason: 'periodic');
      }
    });
  }

  Future<void> updateSyncInterval(int? hours) async {
    var metadata = state.metadata ?? await CloudSyncMetadata.load();
    metadata = metadata.copyWith(syncIntervalHours: hours);
    await metadata.save();
    state = state.copyWith(metadata: metadata);
    _setupPeriodicSync();
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

      final lastWriterDeviceId = userDoc.data()?['lastWriterDeviceId'];
      final cloudUpdatedAtTemp = userDoc.data()?['updatedAt'];
      DateTime? cloudUpdatedAt;
      if (cloudUpdatedAtTemp is Timestamp) {
        cloudUpdatedAt = cloudUpdatedAtTemp.toDate();
      } else if (cloudUpdatedAtTemp is String) {
        cloudUpdatedAt = DateTime.tryParse(cloudUpdatedAtTemp);
      }

      final prefs = await SharedPreferences.getInstance();
      final hasUnsyncedChanges = prefs.getBool('has_unsynced_changes') ?? false;
      final localModifiedAtStr = prefs.getString('last_local_modified_at');
      final localModifiedAt = localModifiedAtStr != null ? DateTime.tryParse(localModifiedAtStr) : null;

      final bool shouldPull;
      if (!userDoc.exists) {
        shouldPull = false;
      } else {
        final hasUserData = _walletHasUserData(_ref.read(ledgerProvider));
        final isCloudNewer = cloudUpdatedAt != null &&
            localModifiedAt != null &&
            cloudUpdatedAt.isAfter(localModifiedAt);

        if (!hasUserData) {
          shouldPull = true;
        } else if (isCloudNewer) {
          shouldPull = true;
        } else if (hasUnsyncedChanges) {
          shouldPull = false;
        } else if (lastWriterDeviceId != null &&
            lastWriterDeviceId != metadata.deviceId) {
          shouldPull = true;
        } else {
          shouldPull = false;
        }
      }

      if (shouldPull) {
        await _restoreFromCloud(user.id, metadata, cloudUpdatedAt);
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

  Future<void> _bootstrap(String userId) async {
    if (state.bootstrappedUserId == userId) return;
    try {
      state = state.copyWith(
        phase: CloudSyncPhase.checking,
        error: null,
        bootstrappedUserId: null,
      );

      var metadata = await CloudSyncMetadata.load();
      if (metadata.userId != userId) {
        metadata = metadata.copyWith(userId: userId);
        await metadata.save();
      }
      state = state.copyWith(metadata: metadata);
      _setupPeriodicSync();

      final prefsDoc = await _firestore
          .doc('users/$userId/metadata/preferences')
          .get()
          .timeout(cloudSyncReadTimeout);

      if (prefsDoc.exists) {
        final userDoc = await _firestore
            .doc('users/$userId')
            .get()
            .timeout(cloudSyncReadTimeout);
        final lastWriterDeviceId = userDoc.data()?['lastWriterDeviceId'];
        final cloudUpdatedAtTemp = userDoc.data()?['updatedAt'];
        DateTime? cloudUpdatedAt;
        if (cloudUpdatedAtTemp is Timestamp) {
          cloudUpdatedAt = cloudUpdatedAtTemp.toDate();
        } else if (cloudUpdatedAtTemp is String) {
          cloudUpdatedAt = DateTime.tryParse(cloudUpdatedAtTemp);
        }

        final hasUserData = _walletHasUserData(_ref.read(ledgerProvider));
        final prefs = await SharedPreferences.getInstance();
        final hasUnsyncedChanges =
            prefs.getBool('has_unsynced_changes') ?? false;
        final localModifiedAtStr = prefs.getString('last_local_modified_at');
        final localModifiedAt = localModifiedAtStr != null ? DateTime.tryParse(localModifiedAtStr) : null;

        debugPrint(
          'CloudSync _bootstrap: userDoc.exists=${userDoc.exists}, lastWriterDeviceId=$lastWriterDeviceId, metadata.deviceId=${metadata.deviceId}, hasUserData=$hasUserData, hasUnsyncedChanges=$hasUnsyncedChanges, localModifiedAt=$localModifiedAt, cloudUpdatedAt=$cloudUpdatedAt',
        );

        final isCloudNewer = cloudUpdatedAt != null &&
            localModifiedAt != null &&
            cloudUpdatedAt.isAfter(localModifiedAt);

        final bool shouldPull =
            !hasUserData ||
            isCloudNewer ||
            (lastWriterDeviceId != null &&
                lastWriterDeviceId != metadata.deviceId &&
                !hasUnsyncedChanges);

        if (shouldPull && userDoc.exists) {
          // We have cloud data. Restore it locally.
          await _restoreFromCloud(userId, metadata, cloudUpdatedAt);
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

        // 2. If no rules at all, try fetching from legacy
        if (rulesToConvert.isEmpty &&
            (currentLedger.preferences.futureGenerationRules == null ||
                currentLedger.preferences.futureGenerationRules!.isEmpty)) {
          final restoreRepo = _ref.read(cloudWalletRestoreRepositoryProvider);
          final legacyWallet = await _readLegacyWalletIfUsable(
            restoreRepo,
            userId,
          );
          if (legacyWallet != null &&
              legacyWallet.ledger.preferences.futureGenerationRules != null) {
            for (final rule
                in legacyWallet.ledger.preferences.futureGenerationRules!) {
              if (!existingRuleIds.contains(rule.id)) {
                rulesToConvert.add(rule);
              }
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
      } else {
        // Migration check
        final restoreRepo = _ref.read(cloudWalletRestoreRepositoryProvider);
        final legacyWallet = await _readLegacyWalletIfUsable(
          restoreRepo,
          userId,
        );
        if (legacyWallet != null) {
          // Found legacy data! Restore it and immediately push to the new schema.
          await _ledger.restoreLedgerState(legacyWallet.ledger);
          await uploadSnapshot(reason: 'migration');
        } else if (!userDoc.exists && _walletHasUserData(_ref.read(ledgerProvider))) {
          // No cloud data, but we have local data. Push local to cloud.
          await uploadSnapshot(reason: 'seed');
        } else if (hasUnsyncedChanges) {
          if (metadata.syncIntervalHours == null) {
             await uploadSnapshot(reason: 'unsynced_startup');
          } else {
             state = state.copyWith(phase: CloudSyncPhase.idle, pendingUpload: true);
          }
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

      WriteBatch currentBatch = _firestore.batch();

      // Update user document
      currentBatch.set(_firestore.doc('users/${user.id}'), {
        'email': user.email,
        'displayName': user.displayName,
        'authProvider': 'google',
        'updatedAt': FieldValue.serverTimestamp(),
        'lastWriterDeviceId': metadata.deviceId,
      }, SetOptions(merge: true));

      final encodedData = await compute(
        _encodeCloudSnapshotData,
        currentLedger,
      );

      final jsonStr = jsonEncode(encodedData);
      final bytes = utf8.encode(jsonStr);
      final compressedBytes = GZipEncoder().encode(bytes)!;

      const chunkSize = 900 * 1024; // 900 KB limit for Firestore Blobs
      final chunks = <Uint8List>[];
      for (var i = 0; i < compressedBytes.length; i += chunkSize) {
        final end = (i + chunkSize < compressedBytes.length)
            ? i + chunkSize
            : compressedBytes.length;
        chunks.add(Uint8List.fromList(compressedBytes.sublist(i, end)));
      }

      // Overwrite chunks 0 to N
      for (var i = 0; i < chunks.length; i++) {
        currentBatch
            .set(_firestore.doc('users/${user.id}/wallet_backups/chunk_$i'), {
              'index': i,
              'data': Blob(chunks[i]),
              'updatedAt': FieldValue.serverTimestamp(),
            });
      }
      // Delete any old trailing chunks left over from a previous, larger backup.
      final existingChunksSnapshot = await _firestore
          .collection('users/${user.id}/wallet_backups')
          .get();
      for (final doc in existingChunksSnapshot.docs) {
        final match = RegExp(r'^chunk_(\d+)$').firstMatch(doc.id);
        final index = match != null ? int.tryParse(match.group(1)!) : null;
        if (index != null && index >= chunks.length) {
          currentBatch.delete(doc.reference);
        }
      }

      await currentBatch.commit().timeout(cloudSyncReadTimeout);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_unsynced_changes', false);

      final now = DateTime.now().toIso8601String();
      metadata = metadata.copyWith(
        userId: user.id,
        lastPushedAt: now,
        // We no longer track individual synced IDs since the whole blob is synced
        syncedDocumentHashes: {},
      );
      await metadata.save();

      _uploadFailureCount = 0;
      _uploadCircuitOpenUntil = 0;
      state = state.copyWith(phase: CloudSyncPhase.idle, metadata: metadata);
      debugPrint('uploadSnapshot: completed successfully!');
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

  Future<void> _restoreFromCloud(
    String userId,
    CloudSyncMetadata currentMetadata, [
    DateTime? cloudUpdatedAt,
  ]) async {
    state = state.copyWith(phase: CloudSyncPhase.restoring);
    try {
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
        restoreData =
            await compute(jsonDecode, jsonStr) as Map<String, dynamic>;
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
          _firestore.collection('users/$userId/budgets').get(),
          _firestore.collection('users/$userId/goals').get(),
          _firestore.collection('users/$userId/captureCandidates').get(),
          _firestore.collection('users/$userId/importBatches').get(),
          _firestore.doc('users/$userId/metadata/preferences').get(),
        ]).timeout(const Duration(seconds: 45));

        final accountsQuery = results[0] as QuerySnapshot<Map<String, dynamic>>;
        final categoriesQuery =
            results[1] as QuerySnapshot<Map<String, dynamic>>;
        final txnsQuery = results[2] as QuerySnapshot<Map<String, dynamic>>;
        final budgetsQuery = results[3] as QuerySnapshot<Map<String, dynamic>>;
        final goalsQuery = results[4] as QuerySnapshot<Map<String, dynamic>>;
        final captureQuery = results[5] as QuerySnapshot<Map<String, dynamic>>;
        final importsQuery = results[6] as QuerySnapshot<Map<String, dynamic>>;
        final prefsDoc = results[7] as DocumentSnapshot<Map<String, dynamic>>;

        restoreData = {
          'userId': userId,
          'preferences': prefsDoc.exists ? prefsDoc.data() : null,
          'accounts': accountsQuery.docs.map((d) => d.data()).toList(),
          'categories': categoriesQuery.docs.map((d) => d.data()).toList(),
          'transactions': txnsQuery.docs.map((d) => d.data()).toList(),
          'budgets': budgetsQuery.docs.map((d) => d.data()).toList(),
          'goals': goalsQuery.docs.map((d) => d.data()).toList(),
          'captureCandidates': captureQuery.docs.map((d) => d.data()).toList(),
          'importBatches': importsQuery.docs.map((d) => d.data()).toList(),
        };
      }

      state = state.copyWith(
        progressMessage: 'Loading transactions...',
        progress: 0.95,
      );
      final ledger = await compute(_parseCloudRestoreData, restoreData);

      final currentLedger = _ref.read(ledgerProvider);
      if (!_walletHasUserData(ledger) && _walletHasUserData(currentLedger)) {
        state = state.copyWith(
          phase: CloudSyncPhase.idle,
          progress: 1.0,
          error:
              'Cloud backup is empty, so the existing local wallet was kept.',
        );
        return;
      }

      await _ledger.restoreLedgerState(ledger);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_unsynced_changes', false);
      if (cloudUpdatedAt != null) {
        await prefs.setString(
          'last_local_modified_at',
          cloudUpdatedAt.toUtc().toIso8601String(),
        );
      } else {
        await prefs.remove('last_local_modified_at');
      }

      final newMetadata = currentMetadata.copyWith(
        userId: userId,
        lastPulledAt: DateTime.now().toIso8601String(),
        syncedDocumentHashes: {},
      );
      await newMetadata.save();

      state = state.copyWith(
        phase: CloudSyncPhase.idle,
        metadata: newMetadata,
        progress: 1.0,
      );
    } catch (e, st) {
      developer.log('Firebase restore failed', error: e, stackTrace: st);
      state = state.copyWith(
        phase: CloudSyncPhase.error,
        error: 'Failed to restore your wallet data.',
      );
    }
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

  Future<RestoredCloudLedger?> _readLegacyWalletIfUsable(
    CloudWalletRestoreRepository restoreRepo,
    String userId,
  ) async {
    try {
      return await restoreRepo
          .readLatestLedger(userId)
          .timeout(cloudSyncReadTimeout);
    } on FormatException catch (error) {
      debugPrint('Ignoring unusable legacy cloud wallet: ${error.message}');
      return null;
    } on TimeoutException catch (error) {
      debugPrint('Ignoring slow legacy cloud wallet restore: $error');
      return null;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        debugPrint('Ignoring inaccessible legacy cloud wallet: $error');
        return null;
      }
      rethrow;
    }
  }

  bool _walletHasUserData(LedgerState ledger) {
    return ledger.accounts.isNotEmpty || ledger.transactions.isNotEmpty;
  }
}

LedgerState _parseCloudRestoreData(Map<String, dynamic> data) {
  final userId = data['userId'] as String;
  final prefsData = data['preferences'] as Map<String, dynamic>?;
  final accountsData = data['accounts'] as List;
  final categoriesData = data['categories'] as List;
  final transactionsData = data['transactions'] as List;
  final budgetsData = data['budgets'] as List;
  final goalsData = data['goals'] as List;
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
      budgets: budgetsData
          .map((d) => budgetFromJson(d as Map<String, dynamic>))
          .toList(),
      goals: goalsData
          .map((d) => goalFromJson(d as Map<String, dynamic>))
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
  );
}

Map<String, dynamic> _encodeCloudSnapshotData(LedgerState ledger) {
  return {
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
    'budgets': ledger.budgets
        .map((b) => budgetToJson(b).cast<String, dynamic>())
        .toList(),
    'goals': ledger.goals
        .map((g) => goalToJson(g).cast<String, dynamic>())
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
