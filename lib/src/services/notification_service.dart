import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/ledger_models.dart';
import '../design/tokens.dart';
import '../features/notifications/notification_engine.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static const _deliveredKey = 'one_wallet_flutter.native_delivered_ids.v1';

  static Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _notificationsPlugin.initialize(settings: initSettings);

    _initialized = true;
  }

  static Future<void> requestPermissions() async {
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> showUpdateNotification(
    String version,
    String channel,
  ) async {
    await requestPermissions();

    final androidDetails = AndroidNotificationDetails(
      'app_updates',
      'App Updates',
      channelDescription: 'Notifications for new app versions',
      importance: Importance.high,
      priority: Priority.high,
      color: await _notificationAccentColor(),
    );
    final notificationDetails = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      id: 0,
      title: 'Update Available',
      body: 'Version $version ($channel) is ready to install',
      notificationDetails: notificationDetails,
    );
  }

  static Future<void> checkAndShowAlerts(LedgerState state) async {
    if (!_initialized) return;
    
    final notifications = buildNotificationInbox(state);
    if (notifications.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final deliveredIds = prefs.getStringList(_deliveredKey) ?? [];
    final newDeliveredIds = List<String>.from(deliveredIds);
    var showedAny = false;

    for (final notification in notifications) {
      if (!deliveredIds.contains(notification.id)) {
        await showAppNotification(notification);
        newDeliveredIds.add(notification.id);
        showedAny = true;
      }
    }

    if (showedAny) {
      await prefs.setStringList(_deliveredKey, newDeliveredIds);
    }
  }

  static Future<void> showAppNotification(AppNotification notification) async {
    await requestPermissions();

    final androidDetails = AndroidNotificationDetails(
      'alerts',
      'Alerts',
      channelDescription: 'Important wallet alerts',
      importance: Importance.high,
      priority: Priority.high,
      color: await _notificationAccentColor(),
      styleInformation: BigTextStyleInformation(notification.body),
    );
    final notificationDetails = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      id: notification.id.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: notificationDetails,
      payload: notification.actionRoute,
    );
  }

  static Future<Color> _notificationAccentColor() async {
    final preferences = await SharedPreferences.getInstance();
    final accent = preferences.getString(
      'one_wallet_flutter.accent.preference.v1',
    );
    if (accent != null && accent.length == 7 && accent.startsWith('#')) {
      final intValue = int.tryParse(accent.substring(1), radix: 16);
      if (intValue != null) return Color(intValue | 0xFF000000);
    }
    return AppColors.primary;
  }
}
