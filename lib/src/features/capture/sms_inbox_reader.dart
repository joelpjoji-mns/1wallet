import 'dart:convert';
import 'package:flutter/services.dart';

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
    final result = await _channel.invokeMapMethod<String, String>(
      'getPermissionState',
    );
    if (result == null) {
      return const AndroidSmsPermissionState(
        read: AndroidSmsPermissionStatus.unavailable,
        receive: AndroidSmsPermissionStatus.unavailable,
        overall: 'unavailable',
      );
    }

    final read = _parsePermissionStatus(result['read']);
    final receive = _parsePermissionStatus(result['receive']);

    String overall;
    if (read == AndroidSmsPermissionStatus.granted &&
        receive == AndroidSmsPermissionStatus.granted) {
      overall = 'granted';
    } else if (read == receive) {
      overall = 'denied';
    } else {
      overall = 'partial';
    }

    return AndroidSmsPermissionState(
      read: read,
      receive: receive,
      overall: overall,
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
    final result = await _channel.invokeMethod<String>('requestPermissions');
    return _parsePermissionStatus(result);
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
                : '\$receivedAt:\${body.substring(0, body.length < 32 ? body.length : 32)}',
            sender: item['address']?.toString(),
            body: body,
            receivedAt: receivedAt,
          );
        })
        .whereType<AndroidSmsInboxMessage>()
        .toList();
  } catch (e) {
    throw Exception('Could not read SMS inbox: \$e');
  }
}

AndroidSmsPermissionStatus _parsePermissionStatus(String? status) {
  switch (status) {
    case 'granted':
      return AndroidSmsPermissionStatus.granted;
    case 'denied':
      return AndroidSmsPermissionStatus.denied;
    case 'blocked':
      return AndroidSmsPermissionStatus.blocked;
    default:
      return AndroidSmsPermissionStatus.unavailable;
  }
}
