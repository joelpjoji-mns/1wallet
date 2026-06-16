import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  });

  final CloudSyncPhase phase;
  final String? error;
  final String? disabledReason;
  final CloudSyncMetadata? metadata;
  final bool pendingUpload;
  final bool bootstrapComplete;
  final String? bootstrappedUserId;

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

      _scheduleUpload();
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
          
      final bool shouldPull = userDoc.exists &&
          userDoc.data()?['lastWriterDeviceId'] != metadata.deviceId;

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
        final bool shouldPull = !userDoc.exists ||
            userDoc.data()?['lastWriterDeviceId'] != metadata.deviceId ||
            !_walletHasUserData(_ref.read(ledgerProvider));

        if (shouldPull) {
          // We have cloud data. Restore it locally.
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
        } else if (_walletHasUserData(_ref.read(ledgerProvider))) {
          // No cloud data, but we have local data. Push local to cloud.
          await uploadSnapshot(reason: 'seed');
        } else {
          state = state.copyWith(phase: CloudSyncPhase.idle);
        }
      }

      state = state.copyWith(
        bootstrappedUserId: userId,
        bootstrapComplete: true,
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
      int opCount = 0;

      Future<void> addWrite(
        DocumentReference doc,
        Map<String, dynamic> data,
      ) async {
        currentBatch.set(doc, data, SetOptions(merge: true));
        opCount++;
        if (opCount >= 450) {
          await currentBatch.commit();
          currentBatch = _firestore.batch();
          opCount = 0;
        }
      }

      // Write metadata
      await addWrite(
        _firestore.doc('users/${user.id}/metadata/preferences'),
        preferencesToJson(currentLedger.preferences).cast<String, dynamic>(),
      );

      await addWrite(_firestore.doc('users/${user.id}'), {
        'email': user.email,
        'displayName': user.displayName,
        'authProvider': 'google',
        'updatedAt': FieldValue.serverTimestamp(),
        'lastWriterDeviceId': metadata.deviceId,
      });

      final encodedData = await compute(
        _encodeCloudSnapshotData,
        currentLedger,
      );
      
      final newSyncedHashes = Map<String, String>.from(metadata.syncedDocumentHashes ?? {});

      Future<void> processCollection(
          String collection, List<Map<String, dynamic>> items, List<String>? syncedIds) async {
        final currentIds = items.map((item) => item['id'] as String).toSet();
        
        for (final item in items) {
          final docId = item['id'] as String;
          final hashKey = '$collection/$docId';
          final currentHash = jsonEncode(item).hashCode.toString();
          
          if (newSyncedHashes[hashKey] == currentHash) {
            continue; // Skip writing this document because it hasn't changed
          }
          
          await addWrite(_firestore.doc('users/${user.id}/$collection/$docId'), item);
          newSyncedHashes[hashKey] = currentHash;
        }
        
        if (syncedIds != null) {
          for (final id in syncedIds) {
            if (!currentIds.contains(id)) {
              final hashKey = '$collection/$id';
              currentBatch.delete(_firestore.doc('users/${user.id}/$collection/$id'));
              newSyncedHashes.remove(hashKey);
              opCount++;
              if (opCount >= 450) {
                await currentBatch.commit();
                currentBatch = _firestore.batch();
                opCount = 0;
              }
            }
          }
        } else {
          // Fallback if syncedIds is null (e.g. first sync after upgrade and didn't reinstall)
          final cloudDocs = await _firestore
              .collection('users/${user.id}/$collection')
              .get()
              .timeout(cloudSyncReadTimeout);
          for (final doc in cloudDocs.docs) {
            if (currentIds.contains(doc.id)) continue;
            currentBatch.delete(doc.reference);
            opCount++;
            if (opCount >= 450) {
              await currentBatch.commit();
              currentBatch = _firestore.batch();
              opCount = 0;
            }
          }
        }
      }

      await processCollection('accounts', encodedData['accounts']!, metadata.syncedAccountIds);
      await processCollection('categories', encodedData['categories']!, metadata.syncedCategoryIds);
      await processCollection('transactions', encodedData['transactions']!, metadata.syncedTransactionIds);
      await processCollection('budgets', encodedData['budgets']!, metadata.syncedBudgetIds);
      await processCollection('goals', encodedData['goals']!, metadata.syncedGoalIds);
      await processCollection('captureCandidates', encodedData['captureCandidates']!, metadata.syncedCaptureCandidateIds);
      await processCollection('importBatches', encodedData['importBatches']!, metadata.syncedImportBatchIds);

      if (opCount > 0) {
        await currentBatch.commit();
      }

      final now = DateTime.now().toIso8601String();
      metadata = metadata.copyWith(
        userId: user.id, 
        lastPushedAt: now,
        syncedAccountIds: encodedData['accounts']!.map((m) => m['id'] as String).toList(),
        syncedCategoryIds: encodedData['categories']!.map((m) => m['id'] as String).toList(),
        syncedTransactionIds: encodedData['transactions']!.map((m) => m['id'] as String).toList(),
        syncedBudgetIds: encodedData['budgets']!.map((m) => m['id'] as String).toList(),
        syncedGoalIds: encodedData['goals']!.map((m) => m['id'] as String).toList(),
        syncedCaptureCandidateIds: encodedData['captureCandidates']!.map((m) => m['id'] as String).toList(),
        syncedImportBatchIds: encodedData['importBatches']!.map((m) => m['id'] as String).toList(),
        syncedDocumentHashes: newSyncedHashes,
      );
      await metadata.save();

      _uploadFailureCount = 0;
      _uploadCircuitOpenUntil = 0;
      state = state.copyWith(phase: CloudSyncPhase.idle, metadata: metadata);
    } catch (e) {
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
    CloudSyncMetadata metadata,
  ) async {
    state = state.copyWith(phase: CloudSyncPhase.restoring, error: null);

    try {
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
      final categoriesQuery = results[1] as QuerySnapshot<Map<String, dynamic>>;
      final txnsQuery = results[2] as QuerySnapshot<Map<String, dynamic>>;
      final budgetsQuery = results[3] as QuerySnapshot<Map<String, dynamic>>;
      final goalsQuery = results[4] as QuerySnapshot<Map<String, dynamic>>;
      final captureQuery = results[5] as QuerySnapshot<Map<String, dynamic>>;
      final importsQuery = results[6] as QuerySnapshot<Map<String, dynamic>>;
      final prefsDoc = results[7] as DocumentSnapshot<Map<String, dynamic>>;

      final restoreData = {
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

      final ledger = await compute(_parseCloudRestoreData, restoreData);

      final currentLedger = _ref.read(ledgerProvider);
      if (!_walletHasUserData(ledger) && _walletHasUserData(currentLedger)) {
        state = state.copyWith(
          phase: CloudSyncPhase.idle,
          error:
              'Cloud backup is empty, so the existing local wallet was kept.',
        );
        return;
      }

      await _ledger.restoreLedgerState(ledger);

      metadata = metadata.copyWith(
        userId: userId,
        lastPulledAt: DateTime.now().toIso8601String(),
        syncedAccountIds: ledger.accounts.map((a) => a.id).toList(),
        syncedCategoryIds: ledger.categories.map((c) => c.id).toList(),
        syncedTransactionIds: ledger.transactions.map((t) => t.id).toList(),
        syncedBudgetIds: ledger.budgets.map((b) => b.id).toList(),
        syncedGoalIds: ledger.goals.map((g) => g.id).toList(),
        syncedCaptureCandidateIds: ledger.captureCandidates.map((c) => c.id).toList(),
        syncedImportBatchIds: ledger.importBatches.map((i) => i.id).toList(),
      );
      await metadata.save();

      state = state.copyWith(phase: CloudSyncPhase.idle, metadata: metadata);
    } catch (e) {
      state = state.copyWith(
        phase: CloudSyncPhase.error,
        error: 'Restore failed: $e',
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
    return ledger.accounts.isNotEmpty ||
        ledger.transactions.isNotEmpty ||
        ledger.captureCandidates.isNotEmpty ||
        ledger.importBatches.isNotEmpty ||
        ledger.budgets.isNotEmpty ||
        ledger.goals.isNotEmpty;
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
    ),
  );
}

Map<String, List<Map<String, dynamic>>> _encodeCloudSnapshotData(
  LedgerState ledger,
) {
  return {
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
  };
}
