import 'dart:io';
import 'package:firebase_core/firebase_core.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/notification_service.dart';

const _updateChannelPreferenceKey = 'appUpdate.channel';

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
    final nested = _mapValue(json['changelog']);
    return Changelog(
      newFeatures: _stringList(
        json['newFeatures'] ??
            json['features'] ??
            nested['newFeatures'] ??
            nested['features'],
      ),
      bugFixes: _stringList(
        json['bugFixes'] ??
            json['fixes'] ??
            nested['bugFixes'] ??
            nested['fixes'],
      ),
      notes: _stringList(json['notes'] ?? nested['notes']),
    );
  }

  bool get isEmpty => newFeatures.isEmpty && bugFixes.isEmpty && notes.isEmpty;
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
      downloadUrl: _stringValue(json['downloadUrl'] ?? json['url']),
      fileName: _stringValue(json['fileName'], fallback: 'update.apk'),
      sizeBytes: _intValue(json['sizeBytes']),
      sha256: _stringValue(json['sha256']),
      architecture: _stringValue(json['architecture']),
      minSdk: _nullableIntValue(json['minSdk']),
      estimatedDownloadSeconds: _nullableIntValue(
        json['estimatedDownloadSeconds'],
      ),
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
    return AppUpdateRelease.fromJson(doc.id, data);
  }

  factory AppUpdateRelease.fromJson(String id, Map<String, dynamic> data) {
    return AppUpdateRelease(
      id: id,
      platform: _stringValue(data['platform'], fallback: 'android'),
      channel: _stringValue(data['channel'], fallback: 'stable'),
      status: _stringValue(data['status'], fallback: 'published'),
      versionName: _stringValue(data['versionName'] ?? data['version']),
      versionCode: _intValue(data['versionCode']),
      runtimeVersion: _stringValue(data['runtimeVersion']),
      releaseType: _stringValue(data['releaseType']),
      requirement: _stringValue(data['requirement'], fallback: 'optional'),
      mandatory: data['mandatory'] == true,
      minimumSupportedVersionCode: _intValue(
        data['minimumSupportedVersionCode'],
      ),
      publishedAt: _dateString(data['publishedAt'] ?? data['generatedAt']),
      changelog: Changelog.fromJson(data['changelog'] ?? {}),
      apk: data['apk'] != null
          ? ApkMetadata.fromJson(_mapValue(data['apk']))
          : null,
    );
  }
}

enum UpdateStatus { idle, checking, downloading, downloaded, installing, error }

class AppUpdateState {
  final UpdateStatus status;
  final AppUpdateRelease? latestRelease;
  final AppUpdateRelease? currentRelease;
  final String currentVersionName;
  final int currentVersionCode;
  final String channel;
  final double progress;
  final int bytesWritten;
  final int bytesExpected;
  final String? errorMessage;
  final String? downloadedApkPath;

  AppUpdateState({
    this.status = UpdateStatus.idle,
    this.latestRelease,
    this.currentRelease,
    this.currentVersionName = '',
    this.currentVersionCode = 0,
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
    AppUpdateRelease? currentRelease,
    String? currentVersionName,
    int? currentVersionCode,
    String? channel,
    double? progress,
    int? bytesWritten,
    int? bytesExpected,
    String? errorMessage,
    String? downloadedApkPath,
    bool clearLatestRelease = false,
    bool clearCurrentRelease = false,
    bool clearErrorMessage = false,
    bool clearDownloadedApkPath = false,
  }) {
    return AppUpdateState(
      status: status ?? this.status,
      latestRelease: clearLatestRelease
          ? null
          : latestRelease ?? this.latestRelease,
      currentRelease: clearCurrentRelease
          ? null
          : currentRelease ?? this.currentRelease,
      currentVersionName: currentVersionName ?? this.currentVersionName,
      currentVersionCode: currentVersionCode ?? this.currentVersionCode,
      channel: channel ?? this.channel,
      progress: progress ?? this.progress,
      bytesWritten: bytesWritten ?? this.bytesWritten,
      bytesExpected: bytesExpected ?? this.bytesExpected,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      downloadedApkPath: clearDownloadedApkPath
          ? null
          : downloadedApkPath ?? this.downloadedApkPath,
    );
  }
}

class AppUpdateProvider extends StateNotifier<AppUpdateState> {
  final Dio _dio = Dio();

  AppUpdateProvider() : super(AppUpdateState()) {
    _loadChannelAndCheck();
  }

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  Future<void> _loadChannelAndCheck() async {
    try {
      if (Firebase.apps.isEmpty) return;
    } catch (_) {
      return; // If Firebase is not linked
    }
    final prefs = await SharedPreferences.getInstance();
    final savedChannel = prefs.getString(_updateChannelPreferenceKey);
    if (savedChannel == 'beta' || savedChannel == 'stable') {
      state = state.copyWith(channel: savedChannel);
    }
    await checkForUpdates();
  }

  Future<void> setChannel(String channel) async {
    state = state.copyWith(
      status: UpdateStatus.checking,
      channel: channel,
      clearLatestRelease: true,
      clearErrorMessage: true,
      clearDownloadedApkPath: true,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_updateChannelPreferenceKey, channel);
    await checkForUpdates();
  }

  Future<void> checkForUpdates() async {
    state = state.copyWith(
      status: UpdateStatus.checking,
      clearErrorMessage: true,
      clearDownloadedApkPath: true,
    );

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 0;
      final currentVersionName = packageInfo.version;
      state = state.copyWith(
        currentVersionName: currentVersionName,
        currentVersionCode: currentVersionCode,
      );

      final currentRelease = await _releaseForVersionCode(
        currentVersionCode,
        channel: state.channel,
      );

      final channelDoc = await _firestore
          .collection('appUpdates/android/channels')
          .doc(state.channel)
          .get();

      if (!channelDoc.exists) {
        state = state.copyWith(
          status: UpdateStatus.idle,
          currentRelease: currentRelease,
          clearCurrentRelease: currentRelease == null,
          clearLatestRelease: true,
        );
        return;
      }

      final latestVersionCode = _nullableIntValue(
        channelDoc.data()?['latestVersionCode'],
      );
      final latestReleaseId = _stringValue(
        channelDoc.data()?['latestReleaseId'],
      );
      if (latestVersionCode == null) {
        state = state.copyWith(
          status: UpdateStatus.idle,
          currentRelease: currentRelease,
          clearCurrentRelease: currentRelease == null,
          clearLatestRelease: true,
        );
        return;
      }

      if (latestVersionCode > currentVersionCode) {
        final release = await _releaseForVersionCode(
          latestVersionCode,
          channel: state.channel,
          releaseId: latestReleaseId,
        );

        if (release != null && release.channel == state.channel) {
          state = state.copyWith(
            status: UpdateStatus.idle,
            latestRelease: release,
            currentRelease: currentRelease,
            clearCurrentRelease: currentRelease == null,
          );

          final prefs = await SharedPreferences.getInstance();
          final notificationKey = 'lastNotifiedVersionCode.${state.channel}';
          final lastNotifiedVersionCode = prefs.getInt(notificationKey) ?? 0;
          if (latestVersionCode > lastNotifiedVersionCode) {
            await NotificationService.showUpdateNotification(
              release.versionName,
              release.channel,
            );
            await prefs.setInt(notificationKey, latestVersionCode);
          }
          return;
        }
      }

      state = state.copyWith(
        status: UpdateStatus.idle,
        currentRelease: currentRelease,
        clearCurrentRelease: currentRelease == null,
        clearLatestRelease: true,
      );
    } catch (e) {
      final message = e is FirebaseException && e.code == 'permission-denied'
          ? 'Update metadata is not available yet. Please try again later.'
          : 'Failed to check for updates: $e';
      state = state.copyWith(status: UpdateStatus.error, errorMessage: message);
    }
  }

  Future<AppUpdateRelease?> _releaseForVersionCode(
    int versionCode, {
    required String channel,
    String? releaseId,
  }) async {
    if (versionCode <= 0) return null;
    final ids = <String>[
      if (releaseId != null && releaseId.trim().isNotEmpty) releaseId.trim(),
      '$channel-$versionCode',
      versionCode.toString(),
    ];

    try {
      for (final id in ids.toSet()) {
        final releaseDoc = await _firestore
            .collection('appUpdates/android/releases')
            .doc(id)
            .get();
        if (!releaseDoc.exists) continue;
        final release = AppUpdateRelease.fromFirestore(releaseDoc);
        if (release.channel == channel) {
          return release;
        }
      }
      return null;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') return null;
      rethrow;
    }
  }

  Future<void> downloadUpdate() async {
    if (state.latestRelease?.apk == null) return;

    state = state.copyWith(
      status: UpdateStatus.downloading,
      progress: 0.0,
      bytesWritten: 0,
      bytesExpected: state.latestRelease!.apk!.sizeBytes,
      clearErrorMessage: true,
      clearDownloadedApkPath: true,
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
      if (!await File(apkPath).exists()) {
        throw Exception(
          'Downloaded APK was not found. Please download it again.',
        );
      }
      final result = await OpenFilex.open(
        apkPath,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        throw Exception(result.message);
      }
      state = state.copyWith(
        status: UpdateStatus.downloaded,
        errorMessage:
            'Installer opened. If Android blocks it, allow installs from 1wallet or uninstall the debug build first.',
      );
    } catch (e) {
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: 'Failed to install update: $e',
      );
    }
  }
}

final appUpdateProvider =
    StateNotifierProvider<AppUpdateProvider, AppUpdateState>((ref) {
      return AppUpdateProvider();
    });

Map<String, dynamic> _mapValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value
      .map((item) => item.toString())
      .where((item) => item.trim().isNotEmpty)
      .toList();
}

String _stringValue(Object? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final string = value.toString().trim();
  return string.isEmpty ? fallback : string;
}

int _intValue(Object? value) => _nullableIntValue(value) ?? 0;

int? _nullableIntValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

String _dateString(Object? value) {
  if (value is Timestamp) return value.toDate().toIso8601String();
  return _stringValue(value);
}
