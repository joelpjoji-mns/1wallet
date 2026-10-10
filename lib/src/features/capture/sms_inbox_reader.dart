import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

enum AndroidSmsPermissionStatus { granted, denied, blocked, unavailable }

class AndroidSmsPermissionState {
  final AndroidSmsPermissionStatus read;
  final AndroidSmsPermissionStatus receive;
  final String overall; // 'granted' | 'partial' | 'denied' | 'unavailable'

  const AndroidSmsPermissionState({
    required this.read,
    required this.receive,
    required this.overall,
  });
}

class AndroidSmsInboxMessage {
  final String id;
  final String? sender;
  final String body;
  final String receivedAt;

  const AndroidSmsInboxMessage({
    required this.id,
    this.sender,
    required this.body,
    required this.receivedAt,
  });
}

const _channel = MethodChannel('com.joelpjoji.one.wallet/sms');

Future<bool> isAndroidSmsInboxAvailable() async {
  try {
    final result = await _channel.invokeMethod<bool>('isAvailable');
    return result ?? false;
  } catch (e) {
    return false;
  }
}

Future<AndroidSmsPermissionState> getAndroidSmsPermissionState() async {
  try {
    final status = await Permission.sms.status;
    final parsed = status.isGranted
        ? AndroidSmsPermissionStatus.granted
        : (status.isPermanentlyDenied
              ? AndroidSmsPermissionStatus.blocked
              : AndroidSmsPermissionStatus.denied);

    return AndroidSmsPermissionState(
      read: parsed,
      receive: parsed,
      overall: status.isGranted ? 'granted' : 'denied',
    );
  } catch (e) {
    return const AndroidSmsPermissionState(
      read: AndroidSmsPermissionStatus.unavailable,
      receive: AndroidSmsPermissionStatus.unavailable,
      overall: 'unavailable',
    );
  }
}

Future<AndroidSmsPermissionStatus> requestAndroidSmsPermission() async {
  try {
    final status = await Permission.sms.request();
    if (status.isGranted) return AndroidSmsPermissionStatus.granted;
    if (status.isDenied) return AndroidSmsPermissionStatus.denied;
    if (status.isPermanentlyDenied) return AndroidSmsPermissionStatus.blocked;
    return AndroidSmsPermissionStatus.unavailable;
  } catch (e) {
    return AndroidSmsPermissionStatus.unavailable;
  }
}

Future<List<AndroidSmsInboxMessage>> readAndroidSmsInbox({
  int maxCount = 200,
  int? minDate,
  int? maxDate,
}) async {
  try {
    final result = await _channel.invokeMethod<String>('readInbox', {
      'maxCount': maxCount,
      'minDate': minDate,
      'maxDate': maxDate,
    });

    if (result == null) return [];

    final List<dynamic> parsed = jsonDecode(result);
    return parsed
        .map((item) {
          final body = item['body']?.toString().trim() ?? '';
          if (body.isEmpty) return null;

          final idValue = item['_id'] ?? item['id'];
          final dateValue = item['date'] != null
              ? num.tryParse(item['date'].toString())
              : null;

          final receivedAt =
              dateValue != null && dateValue.isFinite && dateValue > 0
              ? DateTime.fromMillisecondsSinceEpoch(
                  dateValue.toInt(),
                ).toUtc().toIso8601String()
              : DateTime.now().toUtc().toIso8601String();

          return AndroidSmsInboxMessage(
            id: idValue != null
                ? idValue.toString()
                : '$receivedAt:${body.substring(0, body.length < 32 ? body.length : 32)}',
            sender: item['address']?.toString(),
            body: body,
            receivedAt: receivedAt,
          );
        })
        .whereType<AndroidSmsInboxMessage>()
        .toList();
  } catch (e) {
    throw Exception('Could not read SMS inbox: $e');
  }
}

Future<String?> getInitialSmsRoute() async {
  try {
    return await _channel.invokeMethod<String>('getInitialRoute');
  } catch (e) {
    return null;
  }
}

void listenForSmsRoute(void Function(String route) onRoute) {
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'onRoute') {
      onRoute(call.arguments as String);
    }
  });
}

Future<bool> getAndroidNotificationPermissionState() async {
  try {
    final result = await _channel.invokeMethod<bool>(
      'checkNotificationPermission',
    );
    return result ?? false;
  } catch (e) {
    return false;
  }
}

Future<bool> requestAndroidNotificationPermission() async {
  try {
    final result = await _channel.invokeMethod<bool>(
      'requestNotificationPermission',
    );
    return result ?? false;
  } catch (e) {
    return false;
  }
}

class AndroidInstalledApp {
  final String packageName;
  final String appName;

  const AndroidInstalledApp({required this.packageName, required this.appName});
}

Future<List<AndroidInstalledApp>> getAndroidInstalledApps() async {
  try {
    final result = await _channel.invokeMethod<String>('getInstalledApps');
    if (result == null) return [];

    final List<dynamic> parsed = jsonDecode(result);
    return parsed.map((item) {
      return AndroidInstalledApp(
        packageName: item['packageName'].toString(),
        appName: item['appName'].toString(),
      );
    }).toList()..sort(
      (a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()),
    );
  } catch (e) {
    return [];
  }
}

Future<Uint8List?> getAndroidAppIcon(String packageName) async {
  try {
    final result = await _channel.invokeMethod<Uint8List>('getAppIcon', {
      'packageName': packageName,
    });
    return result;
  } catch (e) {
    return null;
  }
}

class AndroidActiveNotification {
  final String id;
  final String packageName;
  final String appName;
  final String title;
  final String text;
  final String bigText;
  final String subText;
  final String body;
  final String receivedAt;

  const AndroidActiveNotification({
    required this.id,
    required this.packageName,
    required this.appName,
    required this.title,
    required this.text,
    this.bigText = '',
    this.subText = '',
    required this.body,
    required this.receivedAt,
  });
}

Future<List<AndroidActiveNotification>> readActiveAndroidNotifications({
  List<String>? packageNames,
}) async {
  try {
    final result = await _channel.invokeMethod<String>(
      'readActiveNotifications',
      {
        if (packageNames != null && packageNames.isNotEmpty)
          'packageNames': packageNames,
      },
    );
    if (result == null) return [];

    final List<dynamic> parsed = jsonDecode(result);
    return parsed
        .map((item) {
          final body = item['body']?.toString().trim() ?? '';
          if (body.isEmpty) return null;

          final idValue = item['id'];
          final dateValue = item['date'] != null
              ? num.tryParse(item['date'].toString())
              : null;

          final receivedAt =
              dateValue != null && dateValue.isFinite && dateValue > 0
              ? DateTime.fromMillisecondsSinceEpoch(
                  dateValue.toInt(),
                ).toUtc().toIso8601String()
              : DateTime.now().toUtc().toIso8601String();

          return AndroidActiveNotification(
            id: idValue?.toString() ?? '$receivedAt:$body',
            packageName: item['packageName']?.toString() ?? '',
            appName: item['appName']?.toString() ?? '',
            title: item['title']?.toString() ?? '',
            text: item['text']?.toString() ?? '',
            bigText: item['bigText']?.toString() ?? '',
            subText: item['subText']?.toString() ?? '',
            body: body,
            receivedAt: receivedAt,
          );
        })
        .whereType<AndroidActiveNotification>()
        .toList();
  } catch (e) {
    throw Exception('Could not read active notifications: $e');
  }
}

