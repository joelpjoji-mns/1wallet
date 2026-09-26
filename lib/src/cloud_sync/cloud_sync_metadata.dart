import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _cloudSyncStorageKey = 'one_wallet_flutter.cloud_sync.v1';
const _metadataUnset = Object();

@immutable
class CloudSyncMetadata {
  const CloudSyncMetadata({
    this.version = 1,
    required this.deviceId,
    this.userId,
    this.lastCloudRevision,
    this.lastObservedCloudUpdatedAt,
    this.lastLocalChecksum,
    this.lastSnapshotChecksum,
    this.lastSnapshotPath,
    this.lastPushedAt,
    this.lastPulledAt,
    this.lastRestoreBackupUri,
    this.syncedAccountIds,
    this.syncedCategoryIds,
    this.syncedTransactionIds,

    this.syncedCaptureCandidateIds,
    this.syncedImportBatchIds,
    this.syncedDocumentHashes,
    this.syncIntervalHours,
  });

  final int version;
  final String deviceId;
  final String? userId;
  final int? lastCloudRevision;

  /// ISO-8601 UTC timestamp of the remote `users/{uid}.updatedAt` this
  /// device's in-memory ledger is known to be consistent with — i.e. the
  /// value observed at the moment of the last successful push or pull, not
  /// a value read fresh right before a write attempt. Used as the
  /// [uploadSnapshot] conflict baseline's legacy (pre-`cloudRevision`)
  /// fallback, so a remote write that landed after this ledger was last
  /// synced — but before an upload attempt starts serializing it — is still
  /// correctly detected as a conflict instead of being silently clobbered.
  final String? lastObservedCloudUpdatedAt;
  final String? lastLocalChecksum;
  final String? lastSnapshotChecksum;
  final String? lastSnapshotPath;
  final String? lastPushedAt;
  final String? lastPulledAt;
  final String? lastRestoreBackupUri;
  final List<String>? syncedAccountIds;
  final List<String>? syncedCategoryIds;
  final List<String>? syncedTransactionIds;

  final List<String>? syncedCaptureCandidateIds;
  final List<String>? syncedImportBatchIds;
  final Map<String, String>? syncedDocumentHashes;
  final int? syncIntervalHours;

  CloudSyncMetadata copyWith({
    int? version,
    String? deviceId,
    String? userId,
    int? lastCloudRevision,
    String? lastObservedCloudUpdatedAt,
    String? lastLocalChecksum,
    String? lastSnapshotChecksum,
    String? lastSnapshotPath,
    String? lastPushedAt,
    String? lastPulledAt,
    String? lastRestoreBackupUri,
    List<String>? syncedAccountIds,
    List<String>? syncedCategoryIds,
    List<String>? syncedTransactionIds,

    List<String>? syncedCaptureCandidateIds,
    List<String>? syncedImportBatchIds,
    Map<String, String>? syncedDocumentHashes,
    Object? syncIntervalHours = _metadataUnset,
  }) {
    return CloudSyncMetadata(
      version: version ?? this.version,
      deviceId: deviceId ?? this.deviceId,
      userId: userId ?? this.userId,
      lastCloudRevision: lastCloudRevision ?? this.lastCloudRevision,
      lastObservedCloudUpdatedAt:
          lastObservedCloudUpdatedAt ?? this.lastObservedCloudUpdatedAt,
      lastLocalChecksum: lastLocalChecksum ?? this.lastLocalChecksum,
      lastSnapshotChecksum: lastSnapshotChecksum ?? this.lastSnapshotChecksum,
      lastSnapshotPath: lastSnapshotPath ?? this.lastSnapshotPath,
      lastPushedAt: lastPushedAt ?? this.lastPushedAt,
      lastPulledAt: lastPulledAt ?? this.lastPulledAt,
      lastRestoreBackupUri: lastRestoreBackupUri ?? this.lastRestoreBackupUri,
      syncedAccountIds: syncedAccountIds ?? this.syncedAccountIds,
      syncedCategoryIds: syncedCategoryIds ?? this.syncedCategoryIds,
      syncedTransactionIds: syncedTransactionIds ?? this.syncedTransactionIds,

      syncedCaptureCandidateIds:
          syncedCaptureCandidateIds ?? this.syncedCaptureCandidateIds,
      syncedImportBatchIds: syncedImportBatchIds ?? this.syncedImportBatchIds,
      syncedDocumentHashes: syncedDocumentHashes ?? this.syncedDocumentHashes,
      syncIntervalHours: identical(syncIntervalHours, _metadataUnset)
          ? this.syncIntervalHours
          : syncIntervalHours as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'deviceId': deviceId,
      'userId': userId,
      'lastCloudRevision': lastCloudRevision,
      'lastObservedCloudUpdatedAt': lastObservedCloudUpdatedAt,
      'lastLocalChecksum': lastLocalChecksum,
      'lastSnapshotChecksum': lastSnapshotChecksum,
      'lastSnapshotPath': lastSnapshotPath,
      'lastPushedAt': lastPushedAt,
      'lastPulledAt': lastPulledAt,
      'lastRestoreBackupUri': lastRestoreBackupUri,
      'syncedAccountIds': syncedAccountIds,
      'syncedCategoryIds': syncedCategoryIds,
      'syncedTransactionIds': syncedTransactionIds,

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
      lastObservedCloudUpdatedAt: json['lastObservedCloudUpdatedAt'] as String?,
      lastLocalChecksum: json['lastLocalChecksum'] as String?,
      lastSnapshotChecksum: json['lastSnapshotChecksum'] as String?,
      lastSnapshotPath: json['lastSnapshotPath'] as String?,
      lastPushedAt: json['lastPushedAt'] as String?,
      lastPulledAt: json['lastPulledAt'] as String?,
      lastRestoreBackupUri: json['lastRestoreBackupUri'] as String?,
      syncedAccountIds: (json['syncedAccountIds'] as List?)?.cast<String>(),
      syncedCategoryIds: (json['syncedCategoryIds'] as List?)?.cast<String>(),
      syncedTransactionIds: (json['syncedTransactionIds'] as List?)
          ?.cast<String>(),

      syncedCaptureCandidateIds: (json['syncedCaptureCandidateIds'] as List?)
          ?.cast<String>(),
      syncedImportBatchIds: (json['syncedImportBatchIds'] as List?)
          ?.cast<String>(),
      syncedDocumentHashes: (json['syncedDocumentHashes'] as Map?)
          ?.cast<String, String>(),
      syncIntervalHours: json.containsKey('syncIntervalHours')
          ? json['syncIntervalHours'] as int?
          : null,
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
