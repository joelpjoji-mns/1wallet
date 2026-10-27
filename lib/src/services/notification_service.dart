import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/ledger_models.dart';
import '../design/tokens.dart';
import '../ledger/ledger_selectors.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static const androidSmallIcon = 'ic_notification';
  static const androidLargeIcon = 'ic_launcher_foreground';

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

    const androidSettings = AndroidInitializationSettings(androidSmallIcon);
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

    final launchDetails = await _notificationsPlugin
        .getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final payload = launchDetails?.notificationResponse?.payload;
      if (payload != null && payload.trim().isNotEmpty) {
        pendingNotificationRoute = payload;
      }
    }

    tz.initializeTimeZones();
    try {
      final TimezoneInfo timeZoneInfo =
          await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneInfo.identifier));
    } catch (_) {
      // Fallback
    }

    _initialized = true;
  }

  static void checkPendingNotificationLaunch(
    void Function(String route) onRoute,
  ) {
    final route = pendingNotificationRoute;
    if (route != null) {
      pendingNotificationRoute = null;
      onRoute(route);
    }
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
    await initialize();
    await requestPermissions();

    final androidDetails = AndroidNotificationDetails(
      'app_updates',
      'App Updates',
      channelDescription: 'Notifications for new app versions',
      importance: Importance.high,
      priority: Priority.high,
      icon: androidSmallIcon,
      largeIcon: const DrawableResourceAndroidBitmap(androidLargeIcon),
      color: await _notificationAccentColor(),
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _notificationsPlugin.show(
      id: 0,
      title: 'Update Available',
      body: 'Version $version is ready to install',
      notificationDetails: notificationDetails,
      payload: '/updates',
    );
  }

  static Future<void> cancelAll() async {
    if (!_initialized) return;
    try {
      await _notificationsPlugin.cancelAll().timeout(
        const Duration(milliseconds: 500),
      );
    } catch (_) {}
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

    final scheduled = scheduledTransactions(
      state,
    ).where((t) => t.status != 'paused').toList();
    if (scheduled.isEmpty) return;

    await requestPermissions();
    final accentColor = await _notificationAccentColor();

    int idCounter = 1000;
    final now = DateTime.now();

    for (final transaction in scheduled) {
      final targetDate = transaction.occurredAt;
      final today = DateTime(now.year, now.month, now.day);
      final targetDay = DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
      );
      final daysUntil = targetDay.difference(today).inDays;
      final isTodayOrTomorrow = daysUntil == 0 || daysUntil == 1;

      // Calculate 10 AM on the day
      var dayOf = DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
        10,
      );
      // Construct the day-before date fresh from its own year/month/day
      // components (instead of `dayOf.subtract(Duration(days: 1))`) so DST
      // transitions don't shift the wall-clock hour away from 10:00.
      final dayBeforeDate = DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day - 1,
      );
      var dayBefore = DateTime(
        dayBeforeDate.year,
        dayBeforeDate.month,
        dayBeforeDate.day,
        10,
      );

      if (dayBefore.isAfter(now)) {
        await _scheduleTimezoned(
          id: idCounter++,
          title:
              'Upcoming: ${transaction.notes ?? transactionTypeLabel(transaction.type)}',
          body: _dueBody(
            state: state,
            amount: transaction.amount,
            when: 'tomorrow',
          ),
          scheduledDate: dayBefore,
          route: '/recurring/${transaction.id}',
          accentColor: accentColor,
        );
      } else if (isTodayOrTomorrow) {
        // The 10:00 reminder time already passed, but the event is still
        // today/tomorrow — fire an immediate fallback instead of silently
        // dropping the reminder.
        await _scheduleTimezoned(
          id: idCounter++,
          title:
              'Upcoming: ${transaction.notes ?? transactionTypeLabel(transaction.type)}',
          body: _dueBody(
            state: state,
            amount: transaction.amount,
            when: 'tomorrow',
          ),
          scheduledDate: now.add(const Duration(seconds: 5)),
          route: '/recurring/${transaction.id}',
          accentColor: accentColor,
        );
      }

      if (dayOf.isAfter(now)) {
        await _scheduleTimezoned(
          id: idCounter++,
          title:
              'Due Today: ${transaction.notes ?? transactionTypeLabel(transaction.type)}',
          body: _dueBody(
            state: state,
            amount: transaction.amount,
            when: 'today',
          ),
          scheduledDate: dayOf,
          route: '/recurring/${transaction.id}',
          accentColor: accentColor,
        );
      } else if (isTodayOrTomorrow) {
        // Same fallback for the "due today" reminder when 10:00 has passed.
        await _scheduleTimezoned(
          id: idCounter++,
          title:
              'Due Today: ${transaction.notes ?? transactionTypeLabel(transaction.type)}',
          body: _dueBody(
            state: state,
            amount: transaction.amount,
            when: 'today',
          ),
          scheduledDate: now.add(const Duration(seconds: 5)),
          route: '/recurring/${transaction.id}',
          accentColor: accentColor,
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

  static Future<void> _scheduleTimezoned({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required String route,
    Color? accentColor,
  }) async {
    final resolvedAccent = accentColor ?? await _notificationAccentColor();

    final androidDetails = AndroidNotificationDetails(
      'scheduled_alerts',
      'Scheduled Alerts',
      channelDescription: 'Notifications for upcoming payments',
      importance: Importance.high,
      priority: Priority.high,
      icon: androidSmallIcon,
      largeIcon: const DrawableResourceAndroidBitmap(androidLargeIcon),
      color: resolvedAccent,
    );
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

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
