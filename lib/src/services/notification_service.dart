import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/ledger_models.dart';
import '../design/tokens.dart';
import '../features/notifications/notification_engine.dart';
import '../ledger/ledger_selectors.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static const _deliveredKey = 'one_wallet_flutter.native_delivered_ids.v1';

  static Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
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

    tz.initializeTimeZones();
    try {
      final TimezoneInfo timeZoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneInfo.identifier));
    } catch (_) {
      // Fallback
    }

    _initialized = true;
  }

  static Future<void> requestPermissions() async {
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  static Future<void> showUpdateNotification(String version) async {
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
      body: 'Version $version is ready to install',
      notificationDetails: notificationDetails,
    );
  }

  static Future<void> syncScheduledNotifications(LedgerState state) async {
    if (!_initialized) return;

    // Clear old schedules
    await _notificationsPlugin.cancelAll();

    final scheduled = scheduledTransactions(state).where((t) => t.status != 'paused').toList();
    
    int idCounter = 1000;
    final now = DateTime.now();

    for (final transaction in scheduled) {
      final targetDate = transaction.occurredAt;
      
      // Calculate 10 AM on the day
      var dayOf = DateTime(targetDate.year, targetDate.month, targetDate.day, 10, 0);
      var dayBefore = dayOf.subtract(const Duration(days: 1));

      if (dayBefore.isAfter(now)) {
        await _scheduleTimezoned(
          id: idCounter++,
          title: 'Upcoming: ${transaction.notes ?? transactionTypeLabel(transaction.type)}',
          body: '${formatMoney(transaction.amount, state.preferences.locale)} is due tomorrow.',
          scheduledDate: dayBefore,
          route: '/recurring/${transaction.id}',
        );
      }

      if (dayOf.isAfter(now)) {
        await _scheduleTimezoned(
          id: idCounter++,
          title: 'Due Today: ${transaction.notes ?? transactionTypeLabel(transaction.type)}',
          body: '${formatMoney(transaction.amount, state.preferences.locale)} is due today.',
          scheduledDate: dayOf,
          route: '/recurring/${transaction.id}',
        );
      }
    }
  }

  static Future<void> _scheduleTimezoned({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required String route,
  }) async {
    await requestPermissions();

    final androidDetails = AndroidNotificationDetails(
      'scheduled_alerts',
      'Scheduled Alerts',
      channelDescription: 'Notifications for upcoming payments',
      importance: Importance.high,
      priority: Priority.high,
      color: await _notificationAccentColor(),
    );
    final notificationDetails = NotificationDetails(android: androidDetails);

    final tzDate = tz.TZDateTime.from(scheduledDate, tz.local);

    await _notificationsPlugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tzDate,
      notificationDetails: notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: route,
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
