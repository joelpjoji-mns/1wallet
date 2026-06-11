import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ledger_models.dart';
import '../data/ledger_providers.dart';
import 'rn_archive_compat.dart';

const cloudWalletId = 'default';

final cloudWalletRestoreRepositoryProvider =
    Provider<CloudWalletRestoreRepository>((ref) {
      return CloudWalletRestoreRepository(FirebaseFirestore.instance);
    });

final cloudRestoreControllerProvider =
    StateNotifierProvider<CloudRestoreController, CloudRestoreState>((ref) {
      return CloudRestoreController(
        ref.watch(cloudWalletRestoreRepositoryProvider),
        ref.read(ledgerProvider.notifier),
      );
    });

enum CloudRestorePhase { initial, checking, restored, empty, error }

@immutable
class CloudRestoreState {
  const CloudRestoreState({
    this.phase = CloudRestorePhase.initial,
    this.userId,
    this.snapshotId,
    this.summary,
    this.errorMessage,
  });

  final CloudRestorePhase phase;
  final String? userId;
  final String? snapshotId;
  final CloudRestoreSummary? summary;
  final String? errorMessage;

  bool get isChecking => phase == CloudRestorePhase.checking;
  bool get isComplete =>
      phase == CloudRestorePhase.restored || phase == CloudRestorePhase.empty;

  CloudRestoreState copyWith({
    CloudRestorePhase? phase,
    Object? userId = _unset,
    Object? snapshotId = _unset,
    Object? summary = _unset,
    Object? errorMessage = _unset,
  }) {
    return CloudRestoreState(
      phase: phase ?? this.phase,
      userId: identical(userId, _unset) ? this.userId : userId as String?,
      snapshotId: identical(snapshotId, _unset)
          ? this.snapshotId
          : snapshotId as String?,
      summary: identical(summary, _unset)
          ? this.summary
          : summary as CloudRestoreSummary?,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

class CloudRestoreController extends StateNotifier<CloudRestoreState> {
  CloudRestoreController(this._repository, this._ledgerController)
    : super(const CloudRestoreState());

  final CloudWalletRestoreRepository _repository;
  final LedgerController _ledgerController;

  Future<void> restoreLatestForUser(String userId) async {
    if (state.userId == userId && state.isChecking) return;
    if (state.userId == userId && state.isComplete) return;

    state = CloudRestoreState(
      phase: CloudRestorePhase.checking,
      userId: userId,
    );
    try {
      final restored = await _repository.readLatestLedger(userId);
      if (!mounted) return;
      if (restored == null) {
        state = CloudRestoreState(
          phase: CloudRestorePhase.empty,
          userId: userId,
        );
        return;
      }

      await _ledgerController.restoreLedgerState(restored.ledger);
      if (!mounted) return;
      state = CloudRestoreState(
        phase: CloudRestorePhase.restored,
        userId: userId,
        snapshotId: restored.snapshotId,
        summary: restored.summary,
      );
    } catch (error) {
      if (!mounted) return;
      state = CloudRestoreState(
        phase: CloudRestorePhase.error,
        userId: userId,
        errorMessage: _friendlyCloudError(error),
      );
    }
  }

  void reset() {
    state = const CloudRestoreState();
  }
}

class CloudWalletRestoreRepository {
  const CloudWalletRestoreRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Future<RestoredCloudLedger?> readLatestLedger(String uid) async {
    final walletSnapshot = await _firestore
        .doc('users/$uid/wallets/$cloudWalletId')
        .get();
    if (!walletSnapshot.exists) return null;

    final wallet = CloudWalletDocument.fromJson(walletSnapshot.data());
    if (wallet.latestSnapshotId == null) return null;

    final archiveContent = await _readSnapshotContent(uid, wallet);
    final ledger = decodeReactNativeOneWalletArchive(
      archiveContent,
      userId: uid,
      expectedChecksum: wallet.latestSnapshotChecksum,
      expectedLedgerStateVersion: wallet.ledgerStateVersion,
    );

    return RestoredCloudLedger(
      ledger: ledger,
      snapshotId: wallet.latestSnapshotId!,
      summary: CloudRestoreSummary(
        accounts: ledger.accounts.length,
        categories: ledger.categories.length,
        transactions: ledger.transactions.length,
        budgets: ledger.budgets.length,
        goals: ledger.goals.length,
        captureCandidates: ledger.captureCandidates.length,
        chunks: wallet.latestSnapshotChunks ?? 0,
        size: archiveContent.length,
      ),
    );
  }

  Future<String> _readSnapshotContent(
    String uid,
    CloudWalletDocument wallet,
  ) async {
    final snapshotId = wallet.latestSnapshotId;
    if (snapshotId == null || snapshotId.isEmpty) {
      throw const FormatException('Cloud wallet snapshot is missing.');
    }

    final chunksSnapshot = await _firestore
        .collection(
          'users/$uid/wallets/$cloudWalletId/snapshots/$snapshotId/chunks',
        )
        .orderBy('index')
        .get();

    if (wallet.latestSnapshotChunks != null &&
        chunksSnapshot.docs.length != wallet.latestSnapshotChunks) {
      throw const FormatException('Cloud wallet backup is missing chunks.');
    }

    final chunks = <String>[];
    for (final document in chunksSnapshot.docs) {
      final content = document.data()['content'];
      if (content is! String) {
        throw const FormatException(
          'Cloud wallet backup contains an invalid chunk.',
        );
      }
      chunks.add(content);
    }

    final joined = chunks.join();
    if (joined.isEmpty) {
      throw const FormatException('Cloud wallet backup is empty.');
    }
    if (wallet.latestSnapshotSize != null &&
        joined.length != wallet.latestSnapshotSize) {
      throw const FormatException('Cloud wallet backup size mismatch.');
    }
    return joined;
  }
}

@immutable
class CloudWalletDocument {
  const CloudWalletDocument({
    this.latestSnapshotId,
    this.latestSnapshotChecksum,
    this.latestSnapshotChunks,
    this.latestSnapshotSize,
    this.ledgerStateVersion,
    this.cloudRevision,
    this.summary,
  });

  final String? latestSnapshotId;
  final String? latestSnapshotChecksum;
  final int? latestSnapshotChunks;
  final int? latestSnapshotSize;
  final int? ledgerStateVersion;
  final int? cloudRevision;
  final CloudWalletSummary? summary;

  static CloudWalletDocument fromJson(Map<String, dynamic>? json) {
    final data = json ?? const <String, dynamic>{};
    return CloudWalletDocument(
      latestSnapshotId: _string(data['latestSnapshotId']),
      latestSnapshotChecksum: _string(data['latestSnapshotChecksum']),
      latestSnapshotChunks: _int(data['latestSnapshotChunks']),
      latestSnapshotSize: _int(data['latestSnapshotSize']),
      ledgerStateVersion: _int(data['ledgerStateVersion']),
      cloudRevision: _int(data['cloudRevision']),
      summary: CloudWalletSummary.fromJson(data['summary']),
    );
  }
}

@immutable
class CloudWalletSummary {
  const CloudWalletSummary({
    this.accounts,
    this.categories,
    this.transactions,
    this.captureCandidates,
    this.dateRangeEnd,
  });

  final int? accounts;
  final int? categories;
  final int? transactions;
  final int? captureCandidates;
  final DateTime? dateRangeEnd;

  static CloudWalletSummary? fromJson(Object? value) {
    if (value is! Map) return null;
    final dateRange = value['dateRange'];
    DateTime? end;
    if (dateRange is Map) {
      end = _date(dateRange['end']);
    }
    return CloudWalletSummary(
      accounts: _int(value['accounts']),
      categories: _int(value['categories']),
      transactions: _int(value['transactions']),
      captureCandidates: _int(value['captureCandidates']),
      dateRangeEnd: end,
    );
  }
}

@immutable
class RestoredCloudLedger {
  const RestoredCloudLedger({
    required this.ledger,
    required this.snapshotId,
    required this.summary,
  });

  final LedgerState ledger;
  final String snapshotId;
  final CloudRestoreSummary summary;
}

@immutable
class CloudRestoreSummary {
  const CloudRestoreSummary({
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.budgets,
    required this.goals,
    required this.captureCandidates,
    required this.chunks,
    required this.size,
  });

  final int accounts;
  final int categories;
  final int transactions;
  final int budgets;
  final int goals;
  final int captureCandidates;
  final int chunks;
  final int size;
}

const _unset = Object();

String? _string(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return value;
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

DateTime? _date(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String && value.trim().isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

String _friendlyCloudError(Object error) {
  if (error is FirebaseException) {
    return error.message ?? 'Firebase restore failed (${error.code}).';
  }
  if (error is FormatException) return error.message;
  return 'Could not restore your Firebase wallet backup.';
}
