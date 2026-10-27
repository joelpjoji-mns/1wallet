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
    this.lastPushedAt,
    this.lastPulledAt,
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
  final String? lastPushedAt;
  final String? lastPulledAt;
  final int? syncIntervalHours;

  CloudSyncMetadata copyWith({
    int? version,
    String? deviceId,
    String? userId,
    Object? lastCloudRevision = _metadataUnset,
    Object? lastObservedCloudUpdatedAt = _metadataUnset,
    String? lastPushedAt,
    String? lastPulledAt,
    Object? syncIntervalHours = _metadataUnset,
  }) {
    return CloudSyncMetadata(
      version: version ?? this.version,
      deviceId: deviceId ?? this.deviceId,
      userId: userId ?? this.userId,
      lastCloudRevision: identical(lastCloudRevision, _metadataUnset)
          ? this.lastCloudRevision
          : lastCloudRevision as int?,
      lastObservedCloudUpdatedAt:
          identical(lastObservedCloudUpdatedAt, _metadataUnset)
          ? this.lastObservedCloudUpdatedAt
          : lastObservedCloudUpdatedAt as String?,
      lastPushedAt: lastPushedAt ?? this.lastPushedAt,
      lastPulledAt: lastPulledAt ?? this.lastPulledAt,
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
      'lastPushedAt': lastPushedAt,
      'lastPulledAt': lastPulledAt,
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
      lastPushedAt: json['lastPushedAt'] as String?,
      lastPulledAt: json['lastPulledAt'] as String?,
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

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cloudSyncStorageKey);
  }
}
