import 'package:flutter/foundation.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import 'sms_inbox_reader.dart';

/// How far back a Review pull-to-refresh scans the SMS inbox.
const Duration kReviewRefreshSmsWindow = Duration(days: 1);

/// Device readers used by [rescanRecentDeviceCaptures]; injectable for tests.
class DeviceCaptureSources {
  const DeviceCaptureSources({
    this.smsAvailable = isAndroidSmsInboxAvailable,
    this.smsPermission = getAndroidSmsPermissionState,
    this.readSms = readAndroidSmsInbox,
    this.notificationAccess = getAndroidNotificationPermissionState,
    this.readNotifications = readActiveAndroidNotifications,
  });

  final Future<bool> Function() smsAvailable;
  final Future<AndroidSmsPermissionState> Function() smsPermission;
  final Future<List<AndroidSmsInboxMessage>> Function({
    int maxCount,
    int? minDate,
    int? maxDate,
  })
  readSms;
  final Future<bool> Function() notificationAccess;
  final Future<List<AndroidActiveNotification>> Function({
    List<String>? packageNames,
  })
  readNotifications;
}

/// Silently rescans the last day of SMS and the active notifications and adds
/// any new transactions to Review.
///
/// Follows the same rules as live capture: a source is only scanned when its
/// capture switch is on and its permission is already granted (never
/// prompted), and notifications are limited to the monitored apps. Messages
/// already in Review, already posted, or already confirmed/dismissed are
/// skipped. Returns the number of new Review items; never throws.
Future<int> rescanRecentDeviceCaptures(
  LedgerController controller,
  LedgerPreferences preferences, {
  DeviceCaptureSources sources = const DeviceCaptureSources(),
  DateTime? now,
}) async {
  if (kIsWeb) return 0;
  var added = 0;

  if (preferences.smsCaptureEnabled) {
    try {
      if (await sources.smsAvailable() &&
          (await sources.smsPermission()).overall == 'granted') {
        final since = (now ?? DateTime.now()).subtract(kReviewRefreshSmsWindow);
        final messages = await sources.readSms(
          maxCount: 0,
          minDate: since.millisecondsSinceEpoch,
        );
        if (messages.isNotEmpty) {
          final results = await controller.importSmsMessagesBatchDetailed([
            for (final m in messages)
              (
                text: m.body,
                receivedAt: (DateTime.tryParse(m.receivedAt) ?? DateTime.now())
                    .toLocal(),
              ),
          ], skipReviewed: true);
          added += results.where((r) => r.queued).length;
        }
      }
    } catch (error) {
      debugPrint('Review refresh SMS scan failed: $error');
    }
  }

  final packages = preferences.notificationTargetPackages;
  if (preferences.notificationCaptureEnabled && packages.isNotEmpty) {
    try {
      if (await sources.notificationAccess()) {
        final notifications = await sources.readNotifications(
          packageNames: packages,
        );
        if (notifications.isNotEmpty) {
          final results = await controller.importNotificationsBatchDetailed([
            for (final n in notifications)
              (
                text: n.body,
                receivedAt: (DateTime.tryParse(n.receivedAt) ?? DateTime.now())
                    .toLocal(),
                sender: n.appName.isNotEmpty ? n.appName : n.title,
              ),
          ], skipReviewed: true);
          added += results.where((r) => r.queued).length;
        }
      }
    } catch (error) {
      debugPrint('Review refresh notification scan failed: $error');
    }
  }
  return added;
}
