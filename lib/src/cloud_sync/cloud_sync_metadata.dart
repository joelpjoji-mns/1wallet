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
