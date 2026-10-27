// Updater methods and spool-cache refresh are copied from shipped commit 7d1895fe.
// Keep their behavior unchanged: only platform/network/installer boundaries
// below are synthetic, so a client-only fix cannot hide legacy failures.
import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart' as firestore;
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:one_wallet_flutter/src/features/updates/app_update_provider.dart';

class LegacyShippedUpdateClient extends AppUpdateProvider {
  LegacyShippedUpdateClient({
    required Map<String, dynamic> channel,
    required Map<String, dynamic> release,
    required this.downloadDirectory,
    required List<int> apkBytes,
  }) : _firestore = _LegacyFirestore({
         'appUpdates/android/channels/stable': channel,
         'appUpdates/android/releases/stable-${release['versionCode']}':
             release,
       }),
       _dio = _LegacyDio(apkBytes);

  final _LegacyFirestore _firestore;
  final _LegacyDio _dio;
  final Directory downloadDirectory;
  CancelToken? _downloadCancelToken;
  DateTime? _lastCheckedAt;
  bool installerOpened = false;
  String? installerPath;

  void seedVersion() => state = AppUpdateState();
  Future<Directory> getTemporaryDirectory() async => downloadDirectory;
  @override
  Future<void> installUpdate() async {
    installerOpened = true;
    installerPath = state.downloadedApkPath;
  }

  @override
  Future<void> checkForUpdates({bool force = false}) async {
    try {
      if (Firebase.apps.isEmpty) {
        state = state.copyWith(status: UpdateStatus.idle);
        return;
      }
    } catch (_) {
      state = state.copyWith(status: UpdateStatus.idle);
      return;
    }

    if (!force &&
        _lastCheckedAt != null &&
        DateTime.now().difference(_lastCheckedAt!) < const Duration(hours: 6)) {
      return;
    }
    _lastCheckedAt = DateTime.now();

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

      final currentRelease = await _releaseForVersionCode(currentVersionCode);

      List<AppUpdateRelease> fetchedReleases = [];
      try {
        final res = await _dio.get(
          'https://api.github.com/repos/joelpjoji-mns/1wallet/releases?per_page=30',
          options: Options(
            headers: {'User-Agent': '1Wallet-App'},
            sendTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
          ),
        );
        if (res.statusCode == 200 && res.data is List) {
          for (final item in res.data) {
            if (item is Map) {
              final r = _parseGitHubRelease(Map<String, dynamic>.from(item));
              if (r != null) fetchedReleases.add(r);
            }
          }
        }
      } catch (_) {}

      try {
        final querySnap = await _firestore
            .collection('appUpdates/android/releases')
            .orderBy('versionCode', descending: true)
            .limit(200)
            .get();
        if (querySnap.docs.isNotEmpty) {
          final firestoreReleases = querySnap.docs
              .map((doc) => AppUpdateRelease.fromFirestore(doc))
              .toList();
          fetchedReleases = _mergeReleases(fetchedReleases, firestoreReleases);
        }
      } catch (_) {}

      final allReleases = _mergeReleases(
        fetchedReleases,
        kBuiltInReleaseHistory,
      );

      DocumentSnapshot? channelDoc;
      try {
        channelDoc = await _firestore
            .collection('appUpdates/android/channels')
            .doc('stable')
            .get();
      } catch (_) {
        channelDoc = null;
      }

      int? latestVersionCode;
      String latestReleaseId = '';
      String rawVersionName = '';
      AppUpdateRelease? candidateRelease;

      if (channelDoc != null && channelDoc.exists) {
        final data = channelDoc.data() as Map<String, dynamic>?;
        if (data != null) {
          latestVersionCode = _nullableIntValue(data['latestVersionCode']);
          latestReleaseId = _stringValue(data['latestReleaseId']);
          rawVersionName = _stringValue(
            data['latestVersionName'] ?? data['versionName'],
          );
          if (latestVersionCode != null) {
            try {
              candidateRelease = await _releaseForVersionCode(
                latestVersionCode,
                releaseId: latestReleaseId,
              );
            } catch (_) {}
          }
        }
      }

      // If Firestore channel document was unavailable, permission denied,
      // or unpopulated, seamlessly fallback to the newest release discovered
      // from GitHub Releases API:
      if (candidateRelease == null && allReleases.isNotEmpty) {
        final newestFromApi = allReleases.first;
        candidateRelease = newestFromApi;
        latestVersionCode = newestFromApi.versionCode;
        latestReleaseId = newestFromApi.id;
        rawVersionName = newestFromApi.versionName;
      }

      if (latestVersionCode == null) {
        state = state.copyWith(
          status: UpdateStatus.idle,
          currentRelease: currentRelease,
          allReleases: allReleases,
          clearCurrentRelease: currentRelease == null,
          clearLatestRelease: true,
        );
        return;
      }
      final latestName = candidateRelease?.versionName.isNotEmpty == true
          ? candidateRelease!.versionName
          : rawVersionName;

      final isNewer = isReleaseNewer(
        latestVersionCode: latestVersionCode,
        latestVersionName: latestName,
        currentVersionCode: currentVersionCode,
        currentVersionName: currentVersionName,
      );

      if (isNewer) {
        final release =
            candidateRelease ??
            AppUpdateRelease.fromJson(
              latestReleaseId.isNotEmpty
                  ? latestReleaseId
                  : 'stable-$latestVersionCode',
              {
                'versionName': rawVersionName.isNotEmpty
                    ? rawVersionName
                    : 'v$latestVersionCode',
                'versionCode': latestVersionCode,
                'platform': 'android',
                'channel': 'stable',
                'status': 'published',
                'publishedAt': DateTime.now().toIso8601String(),
                'changelog': {
                  'newFeatures': ['New update is available to install.'],
                  'bugFixes': <String>[],
                  'notes': <String>[],
                },
              },
            );

        state = state.copyWith(
          status: UpdateStatus.idle,
          latestRelease: release,
          currentRelease: currentRelease,
          allReleases: allReleases,
          clearCurrentRelease: currentRelease == null,
        );

        final prefs = await SharedPreferences.getInstance();
        const notificationKey = 'lastNotifiedVersionCode.stable';
        final lastNotifiedVersionCode = prefs.getInt(notificationKey) ?? 0;
        if (latestVersionCode > lastNotifiedVersionCode) {
          await NotificationService.showUpdateNotification(release.versionName);
          await prefs.setInt(notificationKey, latestVersionCode);
        }
        return;
      }

      state = state.copyWith(
        status: UpdateStatus.idle,
        currentRelease: currentRelease ?? candidateRelease,
        allReleases: allReleases,
        clearCurrentRelease: currentRelease == null && candidateRelease == null,
        clearLatestRelease: true,
      );
    } catch (e) {
      final message = e is FirebaseException && e.code == 'permission-denied'
          ? 'Update metadata is not available yet. Please try again later.'
          : 'Failed to check for updates: $e';
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: message,
        allReleases: state.allReleases.isNotEmpty
            ? state.allReleases
            : kBuiltInReleaseHistory,
      );
    }
  }

  static bool isReleaseNewer({
    required int latestVersionCode,
    required String latestVersionName,
    required int currentVersionCode,
    required String currentVersionName,
  }) => AppUpdateProvider.isReleaseNewer(
    latestVersionCode: latestVersionCode,
    latestVersionName: latestVersionName,
    currentVersionCode: currentVersionCode,
    currentVersionName: currentVersionName,
  );

  Future<AppUpdateRelease?> _releaseForVersionCode(
    int versionCode, {
    String? releaseId,
  }) async {
    if (versionCode <= 0) return null;
    for (final id in {
      if (releaseId != null && releaseId.trim().isNotEmpty) releaseId.trim(),
      'stable-$versionCode',
      versionCode.toString(),
    }) {
      final doc = await _firestore
          .collection('appUpdates/android/releases')
          .doc(id)
          .get();
      if (doc.exists) return AppUpdateRelease.fromJson(doc.id, doc.payload!);
    }
    return null;
  }

  static List<AppUpdateRelease> _mergeReleases(
    List<AppUpdateRelease> primary,
    List<AppUpdateRelease> secondary,
  ) {
    final seen = <String>{};
    final result = [
      for (final release in [...primary, ...secondary])
        if (seen.add(release.versionName)) release,
    ];
    result.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return result;
  }

  AppUpdateRelease? _parseGitHubRelease(Map<String, dynamic> json) =>
      json.isEmpty ? null : AppUpdateRelease.fromJson('github-release', json);

  @override
  Future<void> downloadUpdate() async {
    if (state.status == UpdateStatus.downloading) return;
    if (state.latestRelease?.apk == null) return;

    _downloadCancelToken?.cancel();
    _downloadCancelToken = CancelToken();

    state = state.copyWith(
      status: UpdateStatus.downloading,
      progress: 0.0,
      bytesWritten: 0,
      bytesExpected: state.latestRelease!.apk!.sizeBytes,
      clearErrorMessage: true,
      clearDownloadedApkPath: true,
    );

    final apk = state.latestRelease!.apk!;

    try {
      final dir = await getTemporaryDirectory();
      final savePath = '${dir.path}/${apk.fileName}';

      await _dio.download(
        apk.downloadUrl,
        savePath,
        cancelToken: _downloadCancelToken,
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

      // -----------------------------------------------------------------------
      // SHA-256 integrity check — verify the downloaded file matches the hash
      // stored in Firestore before allowing installation.
      // -----------------------------------------------------------------------
      state = state.copyWith(progress: 1.0);

      final downloadedFile = File(savePath);
      final fileBytes = await downloadedFile.readAsBytes();
      final computedHash = sha256.convert(fileBytes).toString();

      // Normalise: Firestore value may include a 'sha256:' prefix.
      final expectedHash = apk.sha256.startsWith('sha256:')
          ? apk.sha256.substring('sha256:'.length)
          : apk.sha256;

      if (computedHash != expectedHash) {
        // Delete the corrupted / tampered file immediately.
        await downloadedFile.delete();
        state = state.copyWith(
          status: UpdateStatus.error,
          clearDownloadedApkPath: true,
          errorMessage:
              'Download integrity check failed. The file may be corrupted or '
              'tampered with. Please try again.',
        );
        return;
      }

      state = state.copyWith(
        status: UpdateStatus.downloaded,
        downloadedApkPath: savePath,
      );
      await installUpdate();
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        state = state.copyWith(
          status: UpdateStatus.idle,
          progress: 0.0,
          bytesWritten: 0,
          clearErrorMessage: true,
        );
        return;
      }
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: 'Failed to download update: $e',
      );
    } finally {
      _downloadCancelToken = null;
    }
  }
}

class _LegacyDio {
  _LegacyDio(this.bytes);
  final List<int> bytes;
  Future<Response<dynamic>> get(String url, {Options? options}) async =>
      Response(
        data: [],
        statusCode: 200,
        requestOptions: RequestOptions(path: url),
      );
  Future<void> download(
    String url,
    String path, {
    CancelToken? cancelToken,
    void Function(int, int)? onReceiveProgress,
  }) async {
    await File(path).writeAsBytes(bytes);
    onReceiveProgress?.call(bytes.length, bytes.length);
  }
}

class _LegacyFirestore {
  _LegacyFirestore(this.documents);
  final Map<String, Map<String, dynamic>> documents;
  _LegacyCollection collection(String path) => _LegacyCollection(this, path);
}

class _LegacyCollection {
  _LegacyCollection(this.store, this.path);
  final _LegacyFirestore store;
  final String path;
  _LegacyCollection orderBy(String field, {bool descending = false}) => this;
  _LegacyCollection limit(int count) => this;
  _LegacyReference doc(String id) => _LegacyReference(store, '$path/$id', id);
  Future<_LegacyQuery> get() async => _LegacyQuery();
}

class _LegacyQuery {
  final List<firestore.DocumentSnapshot<Map<String, dynamic>>> docs = [];
}

class _LegacyReference {
  _LegacyReference(this.store, this.path, this.id);
  final _LegacyFirestore store;
  final String path;
  final String id;
  Future<DocumentSnapshot> get() async =>
      DocumentSnapshot(id, store.documents[path]);
}

class DocumentSnapshot {
  DocumentSnapshot(this.id, this.payload);
  final String id;
  final Map<String, dynamic>? payload;
  bool get exists => payload != null;
  Object? data() => payload;
}

class Firebase {
  static const apps = [true];
}

class NotificationService {
  static int attempts = 0;
  static Future<void> showUpdateNotification(String version) async {
    attempts++;
    throw PlatformException(
      code: 'invalid_icon',
      message: 'The resource @drawable/ic_notification could not be found.',
    );
  }
}

String _stringValue(Object? value, {String fallback = ''}) =>
    value is String ? value : fallback;
int? _nullableIntValue(Object? value) => value is int ? value : null;

class LegacySmsSpooler {
  static const _spoolKey = 'one_wallet_flutter.sms_spool';
  static Future<List<Map<String, dynamic>>> popSpooledMessages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final raw = prefs.getString(_spoolKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }

    List<dynamic> spooled;
    try {
      spooled = (jsonDecode(raw) as List).cast<dynamic>();
    } catch (_) {
      await prefs.remove(_spoolKey);
      return [];
    }

    final messages = <Map<String, dynamic>>[];
    for (final payload in spooled) {
      try {
        if (payload is String) {
          messages.add(jsonDecode(payload) as Map<String, dynamic>);
        } else if (payload is Map) {
          messages.add(Map<String, dynamic>.from(payload));
        }
      } catch (_) {}
    }

    await prefs.remove(_spoolKey);
    return messages;
  }
}
