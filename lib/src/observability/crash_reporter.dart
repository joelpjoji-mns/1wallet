import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'app_logger.dart';

abstract class CrashReporter {
  Future<void> initialize({
    required String appVersion,
    required String buildNumber,
    required String gitCommitSha,
  });

  void recordError(
    dynamic exception,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
    Map<String, dynamic>? customKeys,
  });

  void setUserId(String? userId);

  void setCustomKey(String key, dynamic value);
}

class NoopCrashReporter implements CrashReporter {
  final List<Map<String, dynamic>> recordedErrors = [];
  final Map<String, dynamic> customKeys = {};
  String? anonymizedUserId;
  bool initialized = false;

  @override
  Future<void> initialize({
    required String appVersion,
    required String buildNumber,
    required String gitCommitSha,
  }) async {
    initialized = true;
    customKeys['appVersion'] = appVersion;
    customKeys['buildNumber'] = buildNumber;
    customKeys['gitCommitSha'] = gitCommitSha;
  }

  @override
  void recordError(
    dynamic exception,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
    Map<String, dynamic>? customKeys,
  }) {
    final sanitizedKeys = customKeys != null
        ? AppLogger.redactMetadata(customKeys)
        : <String, dynamic>{};

    recordedErrors.add({
      'exception': exception.toString(),
      'stack': stack?.toString(),
      'reason': reason != null ? AppLogger.redact(reason) : null,
      'fatal': fatal,
      'customKeys': sanitizedKeys,
    });
  }

  @override
  void setUserId(String? userId) {
    if (userId == null || userId.isEmpty) {
      anonymizedUserId = null;
      return;
    }
    // Anonymize user ID using SHA-256 so raw Google uid or email never touches telemetry
    final bytes = utf8.encode(userId);
    anonymizedUserId = sha256.convert(bytes).toString().substring(0, 16);
  }

  @override
  void setCustomKey(String key, dynamic value) {
    final sanitized = AppLogger.redactMetadata({key: value});
    customKeys.addAll(sanitized);
  }
}

class CrashReporterProvider {
  static CrashReporter instance = NoopCrashReporter();

  static void setReporter(CrashReporter reporter) {
    instance = reporter;
  }
}
