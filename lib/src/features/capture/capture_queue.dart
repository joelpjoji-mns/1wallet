import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class QueuedCapture {
  const QueuedCapture(this.id, this.payload);
  final String id;
  final Map<String, dynamic> payload;
}

abstract interface class CaptureQueueClient {
  Future<void> configure(String? owner, {Map<String, Object?>? settings});
  Future<List<QueuedCapture>> pending(String owner, String source);
  Future<void> acknowledge(String owner, List<String> ids);
  Future<void> quarantine(String owner, String id, String reason);
  Future<int> unassigned();
  Future<int> quarantineCount(String owner);
  Future<void> assignLegacy(String owner);
  Future<void> purge(String owner);
  Future<void> append(
    String owner,
    String source,
    Map<String, dynamic> payload,
  );
}

abstract final class CaptureQueue {
  static CaptureQueueClient client = NativeCaptureQueue();
}

class NativeCaptureQueue implements CaptureQueueClient {
  static const _channel = MethodChannel(
    'com.joelpjoji.one.wallet/capture_queue',
  );
  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<T?> _call<T>(String method, Map<String, Object?> arguments) =>
      _channel.invokeMethod<T>(method, arguments);
  @override
  Future<void> configure(
    String? owner, {
    Map<String, Object?>? settings,
  }) async {
    if (_supported) {
      await _call<void>('configure', {
        'owner': owner,
        'settings': settings == null ? null : jsonEncode(settings),
      });
    }
  }

  @override
  Future<List<QueuedCapture>> pending(String owner, String source) async {
    if (!_supported) return const [];
    final rows = await _call<List<dynamic>>('pending', {
      'owner': owner,
      'source': source,
    });
    if (rows == null) {
      throw const FormatException('Missing capture queue result.');
    }
    final entries = <QueuedCapture>[];
    for (final row in rows) {
      if (row is! Map || row['id'] is! String || row['payload'] is! String) {
        throw const FormatException('Invalid native queue entry.');
      }
      final id = row['id'] as String;
      try {
        final payload = jsonDecode(row['payload'] as String);
        if (payload is! Map<String, dynamic>) {
          throw const FormatException('Capture must be an object.');
        }
        entries.add(QueuedCapture(id, payload));
      } on FormatException catch (error) {
        await quarantine(owner, id, error.message);
        debugPrint('Capture queue entry $id was quarantined: ${error.message}');
      }
    }
    return entries;
  }

  @override
  Future<void> acknowledge(String owner, List<String> ids) async {
    if (_supported) {
      await _call<void>('acknowledge', {'owner': owner, 'ids': ids});
    }
  }

  @override
  Future<void> quarantine(String owner, String id, String reason) async {
    if (_supported) {
      await _call<void>('quarantine', {
        'owner': owner,
        'id': id,
        'reason': reason,
      });
    }
  }

  @override
  Future<int> unassigned() async {
    if (!_supported) return 0;
    final count = await _call<int>('unassigned', {});
    if (count == null || count < 0) {
      throw const FormatException('Invalid legacy capture count.');
    }
    return count;
  }

  @override
  Future<int> quarantineCount(String owner) async {
    if (!_supported) return 0;
    final count = await _call<int>('quarantined', {'owner': owner});
    if (count == null || count < 0) {
      throw const FormatException('Invalid quarantine count.');
    }
    return count;
  }

  @override
  Future<void> assignLegacy(String owner) async {
    if (_supported) await _call<void>('assignLegacy', {'owner': owner});
  }

  @override
  Future<void> purge(String owner) async {
    if (_supported) await _call<void>('purge', {'owner': owner});
  }

  @override
  Future<void> append(
    String owner,
    String source,
    Map<String, dynamic> payload,
  ) async {
    if (!_supported) {
      throw UnsupportedError('Native background capture requires Android.');
    }
    final saved = await _call<bool>('append', {
      'owner': owner,
      'source': source,
      'payload': jsonEncode(payload),
    });
    if (saved != true) {
      throw StateError('Capture ownership changed before append.');
    }
  }
}

class MemoryCaptureQueue implements CaptureQueueClient {
  String? owner;
  int _next = 0;
  final _entries = <String, (String, String, Map<String, dynamic>)>{};
  final quarantined = <String, String>{};
  @override
  Future<void> configure(
    String? owner, {
    Map<String, Object?>? settings,
  }) async {
    this.owner = owner;
  }

  @override
  Future<void> append(
    String owner,
    String source,
    Map<String, dynamic> payload,
  ) async {
    _entries['capture-${_next++}'] = (owner, source, Map.of(payload));
  }

  @override
  Future<List<QueuedCapture>> pending(String owner, String source) async => [
    for (final entry in _entries.entries)
      if (entry.value.$1 == owner &&
          entry.value.$2 == source &&
          !quarantined.containsKey(entry.key))
        QueuedCapture(entry.key, Map.of(entry.value.$3)),
  ];
  @override
  Future<void> acknowledge(String owner, List<String> ids) async {
    for (final id in ids) {
      if (_entries[id]?.$1 == owner && !quarantined.containsKey(id)) {
        _entries.remove(id);
      }
    }
  }

  @override
  Future<void> quarantine(String owner, String id, String reason) async {
    if (_entries[id]?.$1 == owner) quarantined[id] = reason;
  }

  @override
  Future<int> unassigned() async => 0;
  @override
  Future<int> quarantineCount(String owner) async =>
      quarantined.keys.where((id) => _entries[id]?.$1 == owner).length;
  @override
  Future<void> assignLegacy(String owner) async {}
  @override
  Future<void> purge(String owner) async {
    _entries.removeWhere((_, value) => value.$1 == owner);
  }
}
