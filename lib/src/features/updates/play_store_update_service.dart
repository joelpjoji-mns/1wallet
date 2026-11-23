import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../routing/app_router.dart';
import '../../widgets/app_kit.dart';

enum PlayStoreUpdateStatus {
  idle,
  checking,
  updateAvailable,
  upToDate,
  downloading,
  readyToInstall,
  failed,
  notSupported,
}

class PlayStoreUpdateState {
  const PlayStoreUpdateState({
    this.status = PlayStoreUpdateStatus.idle,
    this.updateInfo,
    this.errorMessage,
  });

  final PlayStoreUpdateStatus status;
  final AppUpdateInfo? updateInfo;
  final String? errorMessage;

  PlayStoreUpdateState copyWith({
    PlayStoreUpdateStatus? status,
    AppUpdateInfo? updateInfo,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PlayStoreUpdateState(
      status: status ?? this.status,
      updateInfo: updateInfo ?? this.updateInfo,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class PlayStoreUpdateService extends StateNotifier<PlayStoreUpdateState> {
  PlayStoreUpdateService() : super(const PlayStoreUpdateState());

  static const String playStorePackageId = 'com.joelpjoji.one.wallet';
  static const String playStoreWebUrl =
      'https://play.google.com/store/apps/details?id=$playStorePackageId';

  bool get isSupported =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      !WidgetsBinding.instance.runtimeType.toString().contains('Test');

  /// Checks Google Play Store for an in-app update.
  /// If [autoTrigger] is true and an update is available, it immediately initiates
  /// either the flexible or immediate update flow.
  Future<AppUpdateInfo?> checkForUpdate({bool autoTrigger = false}) async {
    if (!isSupported) {
      state = state.copyWith(status: PlayStoreUpdateStatus.notSupported);
      return null;
    }

    state = state.copyWith(
      status: PlayStoreUpdateStatus.checking,
      clearError: true,
    );

    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        state = state.copyWith(
          status: PlayStoreUpdateStatus.updateAvailable,
          updateInfo: info,
        );
        if (autoTrigger) {
          if (info.immediateUpdateAllowed) {
            await performImmediateUpdate();
          } else if (info.flexibleUpdateAllowed) {
            await startFlexibleUpdate();
          }
        }
        return info;
      } else {
        state = state.copyWith(
          status: PlayStoreUpdateStatus.upToDate,
          updateInfo: info,
        );
        return info;
      }
    } catch (e) {
      debugPrint('PlayStoreUpdateService check error (ignored): $e');
      state = state.copyWith(
        status: PlayStoreUpdateStatus.failed,
        errorMessage: e.toString(),
      );
      return null;
    }
  }

  /// Initiates background flexible download while the user continues using the app.
  Future<void> startFlexibleUpdate() async {
    if (!isSupported) return;
    try {
      state = state.copyWith(
        status: PlayStoreUpdateStatus.downloading,
        clearError: true,
      );
      final result = await InAppUpdate.startFlexibleUpdate();
      if (result == AppUpdateResult.success) {
        state = state.copyWith(status: PlayStoreUpdateStatus.readyToInstall);
        rootScaffoldMessengerKey.currentState?.showAppSnackBar(
          'Update downloaded and ready to install.',
          duration: const Duration(seconds: 15),
          action: SnackBarAction(
            label: 'Restart',
            onPressed: () {
              completeFlexibleUpdate();
            },
          ),
        );
      } else if (result == AppUpdateResult.userDeniedUpdate) {
        state = state.copyWith(status: PlayStoreUpdateStatus.updateAvailable);
      } else {
        state = state.copyWith(status: PlayStoreUpdateStatus.failed);
      }
    } catch (e) {
      debugPrint('PlayStoreUpdateService flexible update error: $e');
      state = state.copyWith(
        status: PlayStoreUpdateStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }

  /// Installs the downloaded flexible update and restarts the application.
  Future<void> completeFlexibleUpdate() async {
    if (!isSupported) return;
    try {
      await InAppUpdate.completeFlexibleUpdate();
    } catch (e) {
      debugPrint('PlayStoreUpdateService completeFlexibleUpdate error: $e');
      state = state.copyWith(
        status: PlayStoreUpdateStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }

  /// Launches Google Play's full-screen modal update flow.
  Future<AppUpdateResult?> performImmediateUpdate() async {
    if (!isSupported) return null;
    try {
      state = state.copyWith(
        status: PlayStoreUpdateStatus.downloading,
        clearError: true,
      );
      final result = await InAppUpdate.performImmediateUpdate();
      if (result == AppUpdateResult.success) {
        state = state.copyWith(status: PlayStoreUpdateStatus.upToDate);
      } else if (result == AppUpdateResult.userDeniedUpdate) {
        state = state.copyWith(status: PlayStoreUpdateStatus.updateAvailable);
      } else {
        state = state.copyWith(status: PlayStoreUpdateStatus.failed);
      }
      return result;
    } catch (e) {
      debugPrint('PlayStoreUpdateService immediate update error: $e');
      state = state.copyWith(
        status: PlayStoreUpdateStatus.failed,
        errorMessage: e.toString(),
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
    } catch (e) {
      debugPrint('Could not open store listing: $e');
    }
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
