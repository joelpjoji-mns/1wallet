import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _cloudSyncStorageKey = 'one_wallet_flutter.cloud_sync.v1';

@immutable
class CloudSyncMetadata {
  const CloudSyncMetadata({
    this.version = 1,
    required this.deviceId,
    this.userId,
    this.lastCloudRevision,
    this.lastLocalChecksum,
    this.lastSnapshotChecksum,
    this.lastSnapshotPath,
    this.lastPushedAt,
    this.lastPulledAt,
    this.lastRestoreBackupUri,
    this.syncedAccountIds,
    this.syncedCategoryIds,
    this.syncedTransactionIds,
    this.syncedBudgetIds,
    this.syncedGoalIds,
    this.syncedCaptureCandidateIds,
    this.syncedImportBatchIds,
    this.syncedDocumentHashes,
    this.syncIntervalHours,
  });

  final int version;
  final String deviceId;
  final String? userId;
  final int? lastCloudRevision;
  final String? lastLocalChecksum;
  final String? lastSnapshotChecksum;
  final String? lastSnapshotPath;
  final String? lastPushedAt;
  final String? lastPulledAt;
  final String? lastRestoreBackupUri;
  final List<String>? syncedAccountIds;
  final List<String>? syncedCategoryIds;
  final List<String>? syncedTransactionIds;
  final List<String>? syncedBudgetIds;
  final List<String>? syncedGoalIds;
  final List<String>? syncedCaptureCandidateIds;
  final List<String>? syncedImportBatchIds;
  final Map<String, String>? syncedDocumentHashes;
  final int? syncIntervalHours;

  CloudSyncMetadata copyWith({
    int? version,
    String? deviceId,
    String? userId,
    int? lastCloudRevision,
    String? lastLocalChecksum,
    String? lastSnapshotChecksum,
    String? lastSnapshotPath,
    String? lastPushedAt,
    String? lastPulledAt,
    String? lastRestoreBackupUri,
    List<String>? syncedAccountIds,
    List<String>? syncedCategoryIds,
    List<String>? syncedTransactionIds,
    List<String>? syncedBudgetIds,
    List<String>? syncedGoalIds,
    List<String>? syncedCaptureCandidateIds,
    List<String>? syncedImportBatchIds,
    Map<String, String>? syncedDocumentHashes,
    int? syncIntervalHours,
  }) {
    return CloudSyncMetadata(
      version: version ?? this.version,
      deviceId: deviceId ?? this.deviceId,
      userId: userId ?? this.userId,
      lastCloudRevision: lastCloudRevision ?? this.lastCloudRevision,
      lastLocalChecksum: lastLocalChecksum ?? this.lastLocalChecksum,
      lastSnapshotChecksum: lastSnapshotChecksum ?? this.lastSnapshotChecksum,
      lastSnapshotPath: lastSnapshotPath ?? this.lastSnapshotPath,
      lastPushedAt: lastPushedAt ?? this.lastPushedAt,
      lastPulledAt: lastPulledAt ?? this.lastPulledAt,
      lastRestoreBackupUri: lastRestoreBackupUri ?? this.lastRestoreBackupUri,
      syncedAccountIds: syncedAccountIds ?? this.syncedAccountIds,
      syncedCategoryIds: syncedCategoryIds ?? this.syncedCategoryIds,
      syncedTransactionIds: syncedTransactionIds ?? this.syncedTransactionIds,
      syncedBudgetIds: syncedBudgetIds ?? this.syncedBudgetIds,
      syncedGoalIds: syncedGoalIds ?? this.syncedGoalIds,
      syncedCaptureCandidateIds: syncedCaptureCandidateIds ?? this.syncedCaptureCandidateIds,
      syncedImportBatchIds: syncedImportBatchIds ?? this.syncedImportBatchIds,
      syncedDocumentHashes: syncedDocumentHashes ?? this.syncedDocumentHashes,
      syncIntervalHours: syncIntervalHours ?? this.syncIntervalHours,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'deviceId': deviceId,
      'userId': userId,
      'lastCloudRevision': lastCloudRevision,
      'lastLocalChecksum': lastLocalChecksum,
      'lastSnapshotChecksum': lastSnapshotChecksum,
      'lastSnapshotPath': lastSnapshotPath,
      'lastPushedAt': lastPushedAt,
      'lastPulledAt': lastPulledAt,
      'lastRestoreBackupUri': lastRestoreBackupUri,
      'syncedAccountIds': syncedAccountIds,
      'syncedCategoryIds': syncedCategoryIds,
      'syncedTransactionIds': syncedTransactionIds,
      'syncedBudgetIds': syncedBudgetIds,
      'syncedGoalIds': syncedGoalIds,
      'syncedCaptureCandidateIds': syncedCaptureCandidateIds,
      'syncedImportBatchIds': syncedImportBatchIds,
      'syncedDocumentHashes': syncedDocumentHashes,
      'syncIntervalHours': syncIntervalHours,
    };
  }

  static CloudSyncMetadata fromJson(Map<String, dynamic> json) {
    return CloudSyncMetadata(
      version: json['version'] as int? ?? 1,
      deviceId: json['deviceId'] as String? ?? const Uuid().v4(),
      userId: json['userId'] as String?,
      lastCloudRevision: json['lastCloudRevision'] as int?,
      lastLocalChecksum: json['lastLocalChecksum'] as String?,
      lastSnapshotChecksum: json['lastSnapshotChecksum'] as String?,
      lastSnapshotPath: json['lastSnapshotPath'] as String?,
      lastPushedAt: json['lastPushedAt'] as String?,
      lastPulledAt: json['lastPulledAt'] as String?,
      lastRestoreBackupUri: json['lastRestoreBackupUri'] as String?,
      syncedAccountIds: (json['syncedAccountIds'] as List?)?.cast<String>(),
      syncedCategoryIds: (json['syncedCategoryIds'] as List?)?.cast<String>(),
      syncedTransactionIds: (json['syncedTransactionIds'] as List?)?.cast<String>(),
      syncedBudgetIds: (json['syncedBudgetIds'] as List?)?.cast<String>(),
      syncedGoalIds: (json['syncedGoalIds'] as List?)?.cast<String>(),
      syncedCaptureCandidateIds: (json['syncedCaptureCandidateIds'] as List?)?.cast<String>(),
      syncedImportBatchIds: (json['syncedImportBatchIds'] as List?)?.cast<String>(),
      syncedDocumentHashes: (json['syncedDocumentHashes'] as Map?)?.cast<String, String>(),
      syncIntervalHours: json['syncIntervalHours'] as int?,
    );
  }

  static Future<CloudSyncMetadata> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_cloudSyncStorageKey);
    if (jsonStr == null || jsonStr.isEmpty) {
      final initial = CloudSyncMetadata(deviceId: const Uuid().v4());
      await initial.save();
      return initial;
    }
    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return fromJson(json);
    } catch (e) {
      final initial = CloudSyncMetadata(deviceId: const Uuid().v4());
      await initial.save();
      return initial;
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cloudSyncStorageKey, jsonEncode(toJson()));
  }
}
