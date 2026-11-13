import 'dart:convert';
import 'package:flutter/foundation.dart';

enum LogLevel {
  trace,
  debug,
  info,
  warning,
  error,
  fatal,
}

class LogRecord {
  LogRecord({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stackTrace,
    this.metadata = const {},
  });

  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toMap() => {
        'timestamp': timestamp.toIso8601String(),
        'level': level.name,
        'tag': tag,
        'message': message,
        if (error != null) 'error': error.toString(),
        if (stackTrace != null) 'stackTrace': stackTrace.toString(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  @override
  String toString() => jsonEncode(toMap());
}

abstract class LogSink {
  void emit(LogRecord record);
}

class MemoryLogSink implements LogSink {
  MemoryLogSink({this.maxEntries = 100});

  final int maxEntries;
  final List<LogRecord> _records = [];

  List<LogRecord> get records => List.unmodifiable(_records);

  @override
  void emit(LogRecord record) {
    if (_records.length >= maxEntries) {
      _records.removeAt(0);
    }
    _records.add(record);
  }

  void clear() => _records.clear();
}

class ConsoleLogSink implements LogSink {
  const ConsoleLogSink();

  @override
  void emit(LogRecord record) {
    if (kDebugMode) {
      final levelIcon = _icon(record.level);
      final metaStr =
          record.metadata.isNotEmpty ? ' ${record.metadata}' : '';
      // ignore: avoid_print
      debugPrint(
        '$levelIcon [${record.timestamp.toIso8601String()}] [${record.tag}] ${record.message}$metaStr',
      );
      if (record.error != null) {
        // ignore: avoid_print
        debugPrint('  Error: ${record.error}');
      }
      if (record.stackTrace != null) {
        // ignore: avoid_print
        debugPrint('  Stack: ${record.stackTrace}');
      }
    }
  }

  String _icon(LogLevel level) {
    switch (level) {
      case LogLevel.trace:
        return '🔍';
      case LogLevel.debug:
        return '🐛';
      case LogLevel.info:
        return 'ℹ️';
      case LogLevel.warning:
        return '⚠️';
      case LogLevel.error:
        return '🛑';
      case LogLevel.fatal:
        return '🔥';
    }
  }
}

/// Central privacy-first structured logging façade.
///
/// Enforces strict PII scrubbing and monetary amount redaction.
class AppLogger {
  static final List<LogSink> _sinks = [const ConsoleLogSink()];
  static final MemoryLogSink memorySink = MemoryLogSink();
  static bool _includeMemorySink = true;
  static LogLevel minLevel = kReleaseMode ? LogLevel.info : LogLevel.debug;

  static void addSink(LogSink sink) {
    _sinks.add(sink);
  }

  static void clearSinks() {
    _sinks.clear();
  }

  static void setMemorySinkEnabled(bool enabled) {
    _includeMemorySink = enabled;
  }

  // Regular expression patterns for sensitive data
  static final List<RegExp> _currencyPatterns = [
    RegExp(r'[\$€£₹¥]\s*[\d,]+(\.\d+)?'),
    RegExp(r'\b\d+(\.\d{2})?\s*(USD|EUR|GBP|INR|JPY|CAD|AUD)\b', caseSensitive: false),
    RegExp(r'\b(amount|balance|openingBalance|minor|minorUnits)\s*[:=]\s*\d+\b', caseSensitive: false),
    RegExp(r'\b(bearer\s+[A-Za-z0-9_\-\.]+)\b', caseSensitive: false),
    RegExp(r"""\b(api[_\-]?key|auth[_\-]?token|secret|password|pin)\s*[:=]\s*["']?[^\s,"'}]+["']?""", caseSensitive: false),
    RegExp(r'\b(cardLast4|accountLast4)\s*[:=]\s*\d{4}\b', caseSensitive: false),
  ];

  static final _sensitiveKeyPatterns = [
    RegExp(r'(amount|balance|money|currency|salary|income|expense)', caseSensitive: false),
    RegExp(r'(token|bearer|secret|password|credential|pin)', caseSensitive: false),
    RegExp(r'\b(api_?key|private_?key|encryption_?key|access_?key)\b', caseSensitive: false),
    RegExp(r'(account_?number|card_?number|last4)', caseSensitive: false),
    RegExp(r'(notes?|memo|description)', caseSensitive: false),
  ];

  /// Scrub raw string messages of sensitive financial amounts, tokens, and PII.
  static String redact(String message) {
    var result = message;
    for (final pattern in _currencyPatterns) {
      result = result.replaceAllMapped(pattern, (m) => '[REDACTED]');
    }
    return result;
  }

  /// Scrub metadata maps recursively.
  static Map<String, dynamic> redactMetadata(Map<String, dynamic> metadata) {
    final sanitized = <String, dynamic>{};
    for (final entry in metadata.entries) {
      final isSensitiveKey = _sensitiveKeyPatterns.any(
        (pattern) => pattern.hasMatch(entry.key),
      );

      if (isSensitiveKey) {
        sanitized[entry.key] = '[REDACTED]';
      } else if (entry.value is String) {
        sanitized[entry.key] = redact(entry.value as String);
      } else if (entry.value is Map<String, dynamic>) {
        sanitized[entry.key] = redactMetadata(entry.value as Map<String, dynamic>);
      } else {
        sanitized[entry.key] = entry.value;
      }
    }
    return sanitized;
  }

  static void log(
    LogLevel level,
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic> metadata = const {},
  }) {
    if (level.index < minLevel.index) return;

    final sanitizedMessage = redact(message);
    final sanitizedMeta = redactMetadata(metadata);

    final record = LogRecord(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: sanitizedMessage,
      error: error,
      stackTrace: stackTrace,
      metadata: sanitizedMeta,
    );

    for (final sink in _sinks) {
      sink.emit(record);
    }
    if (_includeMemorySink) {
      memorySink.emit(record);
    }
  }

  static void trace(String tag, String message, {Map<String, dynamic> metadata = const {}}) =>
      log(LogLevel.trace, tag, message, metadata: metadata);

  static void debug(String tag, String message, {Map<String, dynamic> metadata = const {}}) =>
      log(LogLevel.debug, tag, message, metadata: metadata);

  static void info(String tag, String message, {Map<String, dynamic> metadata = const {}}) =>
      log(LogLevel.info, tag, message, metadata: metadata);

  static void warning(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic> metadata = const {},
  }) =>
      log(
        LogLevel.warning,
        tag,
        message,
        error: error,
        stackTrace: stackTrace,
        metadata: metadata,
      );

  static void error(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic> metadata = const {},
  }) =>
      log(
        LogLevel.error,
        tag,
        message,
        error: error,
        stackTrace: stackTrace,
        metadata: metadata,
      );

  static void fatal(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic> metadata = const {},
  }) =>
      log(
        LogLevel.fatal,
        tag,
        message,
        error: error,
        stackTrace: stackTrace,
        metadata: metadata,
      );
}
