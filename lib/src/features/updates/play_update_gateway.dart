import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';

/// Byte-level progress for a flexible Google Play download.
@immutable
class PlayUpdateProgress {
  const PlayUpdateProgress({
    required this.status,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
  });

  final InstallStatus status;
  final int bytesDownloaded;
  final int totalBytes;

  /// 0..1, or null while Play has not reported a size yet.
  double? get fraction => totalBytes > 0
      ? (bytesDownloaded / totalBytes).clamp(0.0, 1.0).toDouble()
      : null;
}

/// Thin seam over Google Play Core so the update flow can be unit tested and
/// simulated in Screen Studio.
abstract class PlayUpdateGateway {
  bool get isSupported;
  Future<AppUpdateInfo> checkForUpdate();
  Future<AppUpdateResult> startFlexibleUpdate();
  Future<AppUpdateResult> performImmediateUpdate();
  Future<void> completeFlexibleUpdate();
  Stream<PlayUpdateProgress> get progress;
}

class InAppUpdatePlayGateway implements PlayUpdateGateway {
  const InAppUpdatePlayGateway();

  static const _progressChannel = EventChannel(
    'com.joelpjoji.one.wallet/play_update_progress',
  );

  @override
  bool get isSupported =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      !WidgetsBindingName.isTest;

  @override
  Future<AppUpdateInfo> checkForUpdate() => InAppUpdate.checkForUpdate();

  @override
  Future<AppUpdateResult> startFlexibleUpdate() =>
      InAppUpdate.startFlexibleUpdate();

  @override
  Future<AppUpdateResult> performImmediateUpdate() =>
      InAppUpdate.performImmediateUpdate();

  @override
  Future<void> completeFlexibleUpdate() => InAppUpdate.completeFlexibleUpdate();

  @override
  Stream<PlayUpdateProgress> get progress => _progressChannel
      .receiveBroadcastStream()
      .map((event) => playUpdateProgressFromEvent(event))
      .where((event) => event != null)
      .cast<PlayUpdateProgress>();
}

PlayUpdateProgress? playUpdateProgressFromEvent(Object? event) {
  if (event is! Map) return null;
  final rawStatus = event['status'];
  if (rawStatus is! int) return null;
  final status = InstallStatus.values.firstWhere(
    (value) => value.value == rawStatus,
    orElse: () => InstallStatus.unknown,
  );
  int asInt(Object? value) => value is num ? value.toInt() : 0;
  return PlayUpdateProgress(
    status: status,
    bytesDownloaded: asInt(event['bytesDownloaded']),
    totalBytes: asInt(event['totalBytes']),
  );
}

/// Avoids importing widgets just to detect the flutter_test binding.
abstract final class WidgetsBindingName {
  static bool get isTest {
    try {
      return ServicesBinding.instance.runtimeType.toString().contains('Test');
    } catch (_) {
      return false;
    }
  }
}
