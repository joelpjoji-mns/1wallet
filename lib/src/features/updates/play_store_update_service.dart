import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'play_update_gateway.dart';

export 'play_update_gateway.dart';

enum PlayStoreUpdateStatus {
  idle,
  checking,
  updateAvailable,
  upToDate,
  downloading,
  readyToInstall,
  installing,
  failed,
  notSupported,
}

class PlayStoreUpdateState {
  const PlayStoreUpdateState({
    this.status = PlayStoreUpdateStatus.idle,
    this.updateInfo,
    this.errorMessage,
    this.progress,
    this.promptPending = false,
  });

  final PlayStoreUpdateStatus status;
  final AppUpdateInfo? updateInfo;
  final String? errorMessage;
  final PlayUpdateProgress? progress;

  /// Set when the custom update sheet should be presented once the app is
  /// unlocked and showing its navigator.
  final bool promptPending;

  bool get isBusy =>
      status == PlayStoreUpdateStatus.checking ||
      status == PlayStoreUpdateStatus.downloading ||
      status == PlayStoreUpdateStatus.installing;

  PlayStoreUpdateState copyWith({
    PlayStoreUpdateStatus? status,
    AppUpdateInfo? updateInfo,
    String? errorMessage,
    bool clearError = false,
    PlayUpdateProgress? progress,
    bool clearProgress = false,
    bool? promptPending,
  }) {
    return PlayStoreUpdateState(
      status: status ?? this.status,
      updateInfo: updateInfo ?? this.updateInfo,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      progress: clearProgress ? null : (progress ?? this.progress),
      promptPending: promptPending ?? this.promptPending,
    );
  }
}

class PlayStoreUpdateService extends StateNotifier<PlayStoreUpdateState> {
  PlayStoreUpdateService({
    this.gateway = const InAppUpdatePlayGateway(),
    Future<SharedPreferences> Function()? preferences,
    DateTime Function()? now,
    this.autoInstall = true,
    this.autoInstallDelay = const Duration(milliseconds: 1500),
  }) : _preferences = preferences ?? SharedPreferences.getInstance,
       _now = now ?? DateTime.now,
       super(const PlayStoreUpdateState());

  static const String playStorePackageId = 'com.joelpjoji.one.wallet';
  static const String playStoreWebUrl =
      'https://play.google.com/store/apps/details?id=$playStorePackageId';

  /// Local calendar day (yyyy-mm-dd) of the last completed Play check.
  static const lastCheckDayKey = 'one_wallet.play_update.last_check_day.v1';

  /// Epoch millis of the last failed automatic check, for back-off.
  static const lastFailureKey = 'one_wallet.play_update.last_failure_at.v1';

  /// How long a transient failure (offline, Play busy) waits before the next
  /// app open may try again the same day.
  static const failureRetryDelay = Duration(hours: 3);

  /// Play Core install error codes that will not fix themselves today:
  /// API not available, Play Store missing, app not installed from Play.
  static const _permanentErrorCodes = {-3, -9, -10};

  final PlayUpdateGateway gateway;

  /// Installs (and restarts) as soon as a flexible download finishes.
  final bool autoInstall;
  final Duration autoInstallDelay;
  Timer? _autoInstallTimer;
  final Future<SharedPreferences> Function() _preferences;
  final DateTime Function() _now;
  Future<AppUpdateInfo?>? _inFlight;
  StreamSubscription<PlayUpdateProgress>? _progressSubscription;

  bool get isSupported => gateway.isSupported;

  static String dayKey(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)}';
  }

  /// Runs the automatic Play check at most once per local calendar day.
  ///
  /// Safe to call on every launch, sign-in and resume: repeated opens on the
  /// same day, several days away (one check, not one per missed day), a clock
  /// moved backwards, or overlapping calls all collapse to a single check.
  /// Returns true when a check actually ran.
  Future<bool> checkOnAppOpen() async {
    if (!isSupported) {
      state = state.copyWith(status: PlayStoreUpdateStatus.notSupported);
      return false;
    }
    if (_inFlight != null || _hasActiveUpdate) return false;
    SharedPreferences? prefs;
    try {
      prefs = await _preferences();
    } catch (error) {
      debugPrint('PlayStoreUpdateService prefs unavailable: $error');
    }
    final now = _now();
    if (prefs != null) {
      if (prefs.getString(lastCheckDayKey) == dayKey(now)) return false;
      final failedAt = prefs.getInt(lastFailureKey);
      if (failedAt != null) {
        final elapsed = now.difference(
          DateTime.fromMillisecondsSinceEpoch(failedAt),
        );
        if (!elapsed.isNegative && elapsed < failureRetryDelay) return false;
      }
    }
    // Another caller may have started while preferences were loading.
    if (_inFlight != null || _hasActiveUpdate) return false;
    await _check(prompt: true, automatic: true);
    return true;
  }

  /// Manual check from Settings. Never throttled; shows the update sheet when
  /// [showPrompt] is true and Play offers an update.
  Future<AppUpdateInfo?> checkForUpdate({bool showPrompt = false}) {
    if (!isSupported) {
      state = state.copyWith(status: PlayStoreUpdateStatus.notSupported);
      return Future.value();
    }
    return _check(prompt: showPrompt, automatic: false);
  }

  bool get _hasActiveUpdate =>
      state.status == PlayStoreUpdateStatus.downloading ||
      state.status == PlayStoreUpdateStatus.readyToInstall ||
      state.status == PlayStoreUpdateStatus.installing;

  Future<AppUpdateInfo?> _check({
    required bool prompt,
    required bool automatic,
  }) {
    final running = _inFlight;
    if (running != null) return running;
    final future = _runCheck(prompt: prompt, automatic: automatic);
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  Future<AppUpdateInfo?> _runCheck({
    required bool prompt,
    required bool automatic,
  }) async {
    final previous = state.status;
    if (!_hasActiveUpdate) {
      state = state.copyWith(
        status: PlayStoreUpdateStatus.checking,
        clearError: true,
      );
    }
    try {
      final info = await gateway.checkForUpdate();
      await _recordCheck(succeeded: true);
      _applyCheck(info, prompt: prompt);
      return info;
    } catch (error) {
      debugPrint('PlayStoreUpdateService check error: $error');
      final permanent = _isPermanentError(error);
      await _recordCheck(succeeded: permanent);
      state = state.copyWith(
        status: automatic && previous != PlayStoreUpdateStatus.idle
            ? previous
            : PlayStoreUpdateStatus.failed,
        errorMessage: error.toString(),
      );
      return null;
    }
  }

  void _applyCheck(AppUpdateInfo info, {required bool prompt}) {
    final canUpdate = info.flexibleUpdateAllowed || info.immediateUpdateAllowed;
    switch (info.installStatus) {
      case InstallStatus.downloaded:
        state = state.copyWith(
          status: PlayStoreUpdateStatus.readyToInstall,
          updateInfo: info,
          progress: const PlayUpdateProgress(status: InstallStatus.downloaded),
          promptPending: prompt || state.promptPending,
        );
        _scheduleAutoInstall();
        return;
      case InstallStatus.pending:
      case InstallStatus.downloading:
        state = state.copyWith(
          status: PlayStoreUpdateStatus.downloading,
          updateInfo: info,
          progress:
              state.progress ?? PlayUpdateProgress(status: info.installStatus),
        );
        _listenForProgress();
        return;
      case InstallStatus.installing:
        state = state.copyWith(
          status: PlayStoreUpdateStatus.installing,
          updateInfo: info,
        );
        return;
      default:
        break;
    }
    if (info.updateAvailability == UpdateAvailability.updateAvailable &&
        canUpdate) {
      state = state.copyWith(
        status: PlayStoreUpdateStatus.updateAvailable,
        updateInfo: info,
        clearProgress: true,
        promptPending: prompt || state.promptPending,
      );
    } else if (info.updateAvailability ==
        UpdateAvailability.developerTriggeredUpdateInProgress) {
      // Play resumes an interrupted immediate update on its own.
      state = state.copyWith(
        status: PlayStoreUpdateStatus.downloading,
        updateInfo: info,
      );
      _listenForProgress();
    } else {
      state = state.copyWith(
        status: PlayStoreUpdateStatus.upToDate,
        updateInfo: info,
        clearProgress: true,
        promptPending: false,
      );
    }
  }

  Future<void> _recordCheck({required bool succeeded}) async {
    try {
      final prefs = await _preferences();
      if (succeeded) {
        await prefs.setString(lastCheckDayKey, dayKey(_now()));
        await prefs.remove(lastFailureKey);
      } else {
        await prefs.setInt(lastFailureKey, _now().millisecondsSinceEpoch);
      }
    } catch (error) {
      debugPrint('PlayStoreUpdateService could not save check time: $error');
    }
  }

  static bool _isPermanentError(Object error) {
    final text = error is PlatformException
        ? '${error.code} ${error.message}'
        : error.toString();
    final match =
        RegExp(r'\((-\d+)\)').firstMatch(text) ??
        RegExp(r'(?:^|\s)(-\d+)(?::|\s|$)').firstMatch(text);
    final code = int.tryParse(match?.group(1) ?? '');
    return code != null && _permanentErrorCodes.contains(code);
  }

  /// Called by the prompt host once it has presented the sheet.
  void consumePrompt() {
    if (state.promptPending) state = state.copyWith(promptPending: false);
  }

  /// Asks the host to present the update sheet (for example from Settings).
  void requestPrompt() {
    state = state.copyWith(promptPending: true);
  }

  /// Starts the best update flow Play allows: flexible (background download
  /// with our own progress UI) or, if only that is allowed, immediate.
  Future<void> startUpdate() async {
    var info = state.updateInfo;
    if (info == null ||
        state.status == PlayStoreUpdateStatus.failed ||
        state.status == PlayStoreUpdateStatus.idle) {
      info = await checkForUpdate();
    }
    if (info == null) return;
    if (info.flexibleUpdateAllowed) {
      await startFlexibleUpdate();
    } else if (info.immediateUpdateAllowed) {
      await performImmediateUpdate();
    }
  }

  /// Google Play shows its own short consent dialog, then downloads in the
  /// background while [progress] drives the custom sheet.
  Future<void> startFlexibleUpdate() async {
    if (!isSupported || _hasActiveUpdate) return;
    state = state.copyWith(
      status: PlayStoreUpdateStatus.downloading,
      progress: const PlayUpdateProgress(status: InstallStatus.pending),
      clearError: true,
    );
    _listenForProgress();
    try {
      final result = await gateway.startFlexibleUpdate();
      if (result == AppUpdateResult.success) {
        _markDownloaded();
      } else if (result == AppUpdateResult.userDeniedUpdate) {
        state = state.copyWith(
          status: PlayStoreUpdateStatus.updateAvailable,
          clearProgress: true,
        );
      } else {
        state = state.copyWith(
          status: PlayStoreUpdateStatus.failed,
          errorMessage: 'Google Play could not start the download.',
          clearProgress: true,
        );
      }
    } catch (error) {
      debugPrint('PlayStoreUpdateService flexible update error: $error');
      if (state.status == PlayStoreUpdateStatus.readyToInstall) return;
      state = state.copyWith(
        status: PlayStoreUpdateStatus.failed,
        errorMessage: error.toString(),
        clearProgress: true,
      );
    }
  }

  void _markDownloaded() {
    if (state.status == PlayStoreUpdateStatus.readyToInstall ||
        state.status == PlayStoreUpdateStatus.installing) {
      return;
    }
    final total = state.progress?.totalBytes ?? 0;
    state = state.copyWith(
      status: PlayStoreUpdateStatus.readyToInstall,
      progress: PlayUpdateProgress(
        status: InstallStatus.downloaded,
        bytesDownloaded: total,
        totalBytes: total,
      ),
    );
    _scheduleAutoInstall();
  }

  void _scheduleAutoInstall() {
    if (!autoInstall || _autoInstallTimer != null) return;
    _autoInstallTimer = Timer(autoInstallDelay, () {
      _autoInstallTimer = null;
      if (mounted && state.status == PlayStoreUpdateStatus.readyToInstall) {
        completeFlexibleUpdate();
      }
    });
  }

  void _listenForProgress() {
    if (_progressSubscription != null) return;
    try {
      _progressSubscription = gateway.progress.listen(
        _onProgress,
        onError: (Object error) {
          debugPrint('PlayStoreUpdateService progress unavailable: $error');
          _progressSubscription?.cancel();
          _progressSubscription = null;
        },
        cancelOnError: true,
      );
    } catch (error) {
      debugPrint('PlayStoreUpdateService progress unavailable: $error');
    }
  }

  void _onProgress(PlayUpdateProgress event) {
    if (!mounted) return;
    switch (event.status) {
      case InstallStatus.pending:
      case InstallStatus.downloading:
        if (state.status == PlayStoreUpdateStatus.readyToInstall ||
            state.status == PlayStoreUpdateStatus.installing) {
          return;
        }
        state = state.copyWith(
          status: PlayStoreUpdateStatus.downloading,
          progress: event,
        );
      case InstallStatus.downloaded:
        state = state.copyWith(progress: event);
        _markDownloaded();
      case InstallStatus.installing:
        state = state.copyWith(status: PlayStoreUpdateStatus.installing);
      case InstallStatus.installed:
        state = state.copyWith(
          status: PlayStoreUpdateStatus.upToDate,
          clearProgress: true,
        );
      case InstallStatus.failed:
        state = state.copyWith(
          status: PlayStoreUpdateStatus.failed,
          errorMessage: 'The download did not finish. Try again.',
          clearProgress: true,
        );
      case InstallStatus.canceled:
        state = state.copyWith(
          status: PlayStoreUpdateStatus.updateAvailable,
          clearProgress: true,
        );
      case InstallStatus.unknown:
        break;
    }
  }

  /// Installs the downloaded flexible update; Android restarts 1Wallet.
  Future<void> completeFlexibleUpdate() async {
    if (!isSupported) return;
    state = state.copyWith(status: PlayStoreUpdateStatus.installing);
    try {
      await gateway.completeFlexibleUpdate();
    } catch (error) {
      debugPrint('PlayStoreUpdateService completeFlexibleUpdate error: $error');
      state = state.copyWith(
        status: PlayStoreUpdateStatus.failed,
        errorMessage: error.toString(),
      );
    }
  }

  /// Launches Google Play's full-screen update flow (used only when Play does
  /// not allow a flexible update).
  Future<AppUpdateResult?> performImmediateUpdate() async {
    if (!isSupported) return null;
    try {
      state = state.copyWith(
        status: PlayStoreUpdateStatus.downloading,
        clearError: true,
      );
      final result = await gateway.performImmediateUpdate();
      if (result == AppUpdateResult.success) {
        state = state.copyWith(status: PlayStoreUpdateStatus.upToDate);
      } else if (result == AppUpdateResult.userDeniedUpdate) {
        state = state.copyWith(status: PlayStoreUpdateStatus.updateAvailable);
      } else {
        state = state.copyWith(status: PlayStoreUpdateStatus.failed);
      }
      return result;
    } catch (error) {
      debugPrint('PlayStoreUpdateService immediate update error: $error');
      state = state.copyWith(
        status: PlayStoreUpdateStatus.failed,
        errorMessage: error.toString(),
      );
      return null;
    }
  }

  /// Opens the Google Play Store app or web page as a fallback.
  Future<void> openStoreListing() async {
    final marketUri = Uri.parse('market://details?id=$playStorePackageId');
    final webUri = Uri.parse(playStoreWebUrl);

    try {
      if (await canLaunchUrl(marketUri)) {
        await launchUrl(marketUri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (error) {
      debugPrint('Could not open store listing: $error');
    }
  }

  @override
  void dispose() {
    _autoInstallTimer?.cancel();
    _progressSubscription?.cancel();
    super.dispose();
  }
}

final playStoreUpdateProvider =
    StateNotifierProvider<PlayStoreUpdateService, PlayStoreUpdateState>((ref) {
      return PlayStoreUpdateService();
    });

final packageInfoProvider = FutureProvider<PackageInfo>((ref) async {
  try {
    return await PackageInfo.fromPlatform();
  } catch (_) {
    return PackageInfo(
      appName: '1Wallet',
      packageName: 'com.joelpjoji.one.wallet',
      version: '1.0.14',
      buildNumber: '14',
      buildSignature: '',
    );
  }
});
