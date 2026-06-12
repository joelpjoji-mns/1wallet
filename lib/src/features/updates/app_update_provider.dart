import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class Changelog {
  final List<String> newFeatures;
  final List<String> bugFixes;
  final List<String> notes;

  Changelog({
    required this.newFeatures,
    required this.bugFixes,
    required this.notes,
  });

  factory Changelog.fromJson(Map<String, dynamic> json) {
    return Changelog(
      newFeatures: List<String>.from(json['newFeatures'] ?? []),
      bugFixes: List<String>.from(json['bugFixes'] ?? []),
      notes: List<String>.from(json['notes'] ?? []),
    );
  }
}

class ApkMetadata {
  final String downloadUrl;
  final String fileName;
  final int sizeBytes;
  final String sha256;
  final String architecture;
  final int? minSdk;
  final int? estimatedDownloadSeconds;

  ApkMetadata({
    required this.downloadUrl,
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
    required this.architecture,
    this.minSdk,
    this.estimatedDownloadSeconds,
  });

  factory ApkMetadata.fromJson(Map<String, dynamic> json) {
    return ApkMetadata(
      downloadUrl: json['downloadUrl'] ?? '',
      fileName: json['fileName'] ?? 'update.apk',
      sizeBytes: json['sizeBytes'] ?? 0,
      sha256: json['sha256'] ?? '',
      architecture: json['architecture'] ?? '',
      minSdk: json['minSdk'],
      estimatedDownloadSeconds: json['estimatedDownloadSeconds'],
    );
  }
}

class AppUpdateRelease {
  final String id;
  final String platform;
  final String channel;
  final String status;
  final String versionName;
  final int versionCode;
  final String runtimeVersion;
  final String releaseType;
  final String requirement;
  final bool mandatory;
  final int minimumSupportedVersionCode;
  final String publishedAt;
  final Changelog changelog;
  final ApkMetadata? apk;

  AppUpdateRelease({
    required this.id,
    required this.platform,
    required this.channel,
    required this.status,
    required this.versionName,
    required this.versionCode,
    required this.runtimeVersion,
    required this.releaseType,
    required this.requirement,
    required this.mandatory,
    required this.minimumSupportedVersionCode,
    required this.publishedAt,
    required this.changelog,
    this.apk,
  });

  factory AppUpdateRelease.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppUpdateRelease(
      id: doc.id,
      platform: data['platform'] ?? 'android',
      channel: data['channel'] ?? 'stable',
      status: data['status'] ?? 'published',
      versionName: data['versionName'] ?? '',
      versionCode: data['versionCode'] ?? 0,
      runtimeVersion: data['runtimeVersion'] ?? '',
      releaseType: data['releaseType'] ?? '',
      requirement: data['requirement'] ?? 'optional',
      mandatory: data['mandatory'] ?? false,
      minimumSupportedVersionCode: data['minimumSupportedVersionCode'] ?? 0,
      publishedAt: data['publishedAt']?.toString() ?? '',
      changelog: Changelog.fromJson(data['changelog'] ?? {}),
      apk: data['apk'] != null ? ApkMetadata.fromJson(data['apk']) : null,
    );
  }
}

enum UpdateStatus {
  idle,
  checking,
  downloading,
  downloaded,
  installing,
  error,
}

class AppUpdateState {
  final UpdateStatus status;
  final AppUpdateRelease? latestRelease;
  final String channel;
  final double progress;
  final int bytesWritten;
  final int bytesExpected;
  final String? errorMessage;
  final String? downloadedApkPath;

  AppUpdateState({
    this.status = UpdateStatus.idle,
    this.latestRelease,
    this.channel = 'stable',
    this.progress = 0.0,
    this.bytesWritten = 0,
    this.bytesExpected = 0,
    this.errorMessage,
    this.downloadedApkPath,
  });

  AppUpdateState copyWith({
    UpdateStatus? status,
    AppUpdateRelease? latestRelease,
    String? channel,
    double? progress,
    int? bytesWritten,
    int? bytesExpected,
    String? errorMessage,
    String? downloadedApkPath,
  }) {
    return AppUpdateState(
      status: status ?? this.status,
      latestRelease: latestRelease ?? this.latestRelease,
      channel: channel ?? this.channel,
      progress: progress ?? this.progress,
      bytesWritten: bytesWritten ?? this.bytesWritten,
      bytesExpected: bytesExpected ?? this.bytesExpected,
      errorMessage: errorMessage ?? this.errorMessage,
      downloadedApkPath: downloadedApkPath ?? this.downloadedApkPath,
    );
  }
}

class AppUpdateProvider extends StateNotifier<AppUpdateState> {
  final FirebaseFirestore _firestore;
  final Dio _dio = Dio();

  AppUpdateProvider(this._firestore) : super(AppUpdateState()) {
    checkForUpdates();
  }

  Future<void> setChannel(String channel) async {
    state = state.copyWith(channel: channel);
    await checkForUpdates();
  }

  Future<void> checkForUpdates() async {
    state = state.copyWith(status: UpdateStatus.checking, errorMessage: null);

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 0;

      final channelDoc = await _firestore
          .collection('appUpdates/android/channels')
          .doc(state.channel)
          .get();

      if (!channelDoc.exists) {
        state = state.copyWith(status: UpdateStatus.idle);
        return;
      }

      final latestVersionCode = channelDoc.data()?['latestVersionCode'] as int?;
      if (latestVersionCode == null) {
        state = state.copyWith(status: UpdateStatus.idle);
        return;
      }

      if (latestVersionCode > currentVersionCode) {
        final releaseDoc = await _firestore
            .collection('appUpdates/android/releases')
            .doc(latestVersionCode.toString())
            .get();

        if (releaseDoc.exists) {
          final release = AppUpdateRelease.fromFirestore(releaseDoc);
          state = state.copyWith(
            status: UpdateStatus.idle,
            latestRelease: release,
          );
          return;
        }
      }

      state = state.copyWith(status: UpdateStatus.idle, latestRelease: null);
    } catch (e) {
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: 'Failed to check for updates: $e',
      );
    }
  }

  Future<void> downloadUpdate() async {
    if (state.latestRelease?.apk == null) return;
    
    state = state.copyWith(
      status: UpdateStatus.downloading,
      progress: 0.0,
      bytesWritten: 0,
      bytesExpected: state.latestRelease!.apk!.sizeBytes,
    );

    try {
      final dir = await getTemporaryDirectory();
      final savePath = '${dir.path}/${state.latestRelease!.apk!.fileName}';

      await _dio.download(
        state.latestRelease!.apk!.downloadUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            state = state.copyWith(
              progress: received / total,
              bytesWritten: received,
              bytesExpected: total,
            );
          }
        },
      );

      state = state.copyWith(
        status: UpdateStatus.downloaded,
        downloadedApkPath: savePath,
      );
    } catch (e) {
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: 'Failed to download update: $e',
      );
    }
  }

  Future<void> installUpdate() async {
    final apkPath = state.downloadedApkPath;
    if (apkPath == null) return;
    
    state = state.copyWith(status: UpdateStatus.installing);
    try {
      final result = await OpenFilex.open(apkPath);
      if (result.type != ResultType.done) {
        throw Exception(result.message);
      }
      state = state.copyWith(status: UpdateStatus.idle);
    } catch (e) {
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: 'Failed to install update: $e',
      );
    }
  }
}

final appUpdateProvider = StateNotifierProvider<AppUpdateProvider, AppUpdateState>((ref) {
  return AppUpdateProvider(FirebaseFirestore.instance);
});
