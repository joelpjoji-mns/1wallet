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

  /// Hook other layers (e.g. the app's router/navigator setup) can assign to
  /// receive the `route` payload carried by a tapped notification. This file
  /// intentionally does not depend on the app's navigator/router directly —
  /// wire navigation up wherever a navigator/router is available, e.g.:
  ///
  /// ```dart
  /// NotificationService.onNotificationTapped = (route) {
  ///   rootNavigatorKey.currentState?.context.push(route);
  /// };
  /// ```
  static void Function(String route)? onNotificationTapped;

  /// If a notification is tapped before [onNotificationTapped] has been
  /// wired up (e.g. a cold app launch), the route is stashed here so callers
  /// can consume it once the router/navigator becomes available.
  static String? pendingNotificationRoute;

  static void _handleNotificationTap(String? route) {
    if (route == null || route.trim().isEmpty) return;
    final callback = onNotificationTapped;
    if (callback != null) {
      callback(route);
    } else {
      pendingNotificationRoute = route;
    }
  }

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

    await _notificationsPlugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _handleNotificationTap(response.payload);
      },
    );

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

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
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

    // Respect the "Device notifications" master toggle and the "Scheduled"
    // channel toggle — both gate this entirely native/OS-level reminder
    // flow. The in-app inbox (buildNotificationInbox) is unaffected.
    if (!state.preferences.deviceNotificationsEnabled ||
        !state.preferences.channelScheduledEnabled) {
      return;
    }

    final scheduled = scheduledTransactions(state).where((t) => t.status != 'paused').toList();
    
    int idCounter = 1000;
    final now = DateTime.now();

    for (final transaction in scheduled) {
      final targetDate = transaction.occurredAt;
      final today = DateTime(now.year, now.month, now.day);
      final targetDay = DateTime(targetDate.year, targetDate.month, targetDate.day);
      final daysUntil = targetDay.difference(today).inDays;
      final isTodayOrTomorrow = daysUntil == 0 || daysUntil == 1;

      // Calculate 10 AM on the day
      var dayOf = DateTime(targetDate.year, targetDate.month, targetDate.day, 10, 0);
      // Construct the day-before date fresh from its own year/month/day
      // components (instead of `dayOf.subtract(Duration(days: 1))`) so DST
      // transitions don't shift the wall-clock hour away from 10:00.
      final dayBeforeDate = DateTime(targetDate.year, targetDate.month, targetDate.day - 1);
      var dayBefore = DateTime(dayBeforeDate.year, dayBeforeDate.month, dayBeforeDate.day, 10, 0);

      if (dayBefore.isAfter(now)) {
        await _scheduleTimezoned(
          id: idCounter++,
          title: 'Upcoming: ${transaction.notes ?? transactionTypeLabel(transaction.type)}',
          body: _dueBody(state: state, amount: transaction.amount, when: 'tomorrow'),
          scheduledDate: dayBefore,
          route: '/recurring/${transaction.id}',
        );
      } else if (isTodayOrTomorrow) {
        // The 10:00 reminder time already passed, but the event is still
        // today/tomorrow — fire an immediate fallback instead of silently
        // dropping the reminder.
        await _scheduleTimezoned(
          id: idCounter++,
          title: 'Upcoming: ${transaction.notes ?? transactionTypeLabel(transaction.type)}',
          body: _dueBody(state: state, amount: transaction.amount, when: 'tomorrow'),
          scheduledDate: now.add(const Duration(seconds: 5)),
          route: '/recurring/${transaction.id}',
        );
      }

      if (dayOf.isAfter(now)) {
        await _scheduleTimezoned(
          id: idCounter++,
          title: 'Due Today: ${transaction.notes ?? transactionTypeLabel(transaction.type)}',
          body: _dueBody(state: state, amount: transaction.amount, when: 'today'),
          scheduledDate: dayOf,
          route: '/recurring/${transaction.id}',
        );
      } else if (isTodayOrTomorrow) {
        // Same fallback for the "due today" reminder when 10:00 has passed.
        await _scheduleTimezoned(
          id: idCounter++,
          title: 'Due Today: ${transaction.notes ?? transactionTypeLabel(transaction.type)}',
          body: _dueBody(state: state, amount: transaction.amount, when: 'today'),
          scheduledDate: now.add(const Duration(seconds: 5)),
          route: '/recurring/${transaction.id}',
        );
      }
    }
  }

  /// Builds a scheduled-payment reminder body. When privacy mode is enabled
  /// the exact amount is omitted in favor of a generic message.
  static String _dueBody({
    required LedgerState state,
    required Money amount,
    required String when,
  }) {
    if (state.preferences.privacyModeEnabled) {
      return 'A scheduled payment is due $when.';
    }
    return '${formatMoney(amount, state.preferences.locale)} is due $when.';
  }

  /// Fixed 22:00–07:00 quiet-hours window, matching the range shown in
  /// Settings. Only gates immediate/native alert delivery — the in-app
  /// inbox is unaffected.
  static bool _isQuietHours(LedgerState state) {
    if (!state.preferences.quietHoursEnabled) return false;
    final hour = DateTime.now().hour;
    return hour >= 22 || hour < 7;
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
    // Native alerts are gated by the "Device notifications" master toggle;
    // the in-app inbox (buildNotificationInbox) already reflects the
    // per-channel toggles and is unaffected by this early return.
    if (!state.preferences.deviceNotificationsEnabled) return;

    final notifications = buildNotificationInbox(state);
    if (notifications.isEmpty) return;

    // During quiet hours, hold off on native alerts entirely. Notifications
    // are not marked delivered here, so they can still fire the next time
    // this runs after quiet hours end.
    if (_isQuietHours(state)) return;

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
