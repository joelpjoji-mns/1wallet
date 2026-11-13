import 'app_logger.dart';

abstract class AnalyticsService {
  bool get isOptedIn;
  Future<void> setOptIn(bool enabled);
  Future<void> logEvent(String eventName, {Map<String, dynamic>? parameters});
}

class PrivacyAnalyticsService implements AnalyticsService {
  PrivacyAnalyticsService({bool initialOptIn = false})
    : _optedIn = initialOptIn;

  bool _optedIn;
  final List<Map<String, dynamic>> loggedEvents = [];

  @override
  bool get isOptedIn => _optedIn;

  @override
  Future<void> setOptIn(bool enabled) async {
    _optedIn = enabled;
    AppLogger.info(
      'AnalyticsService',
      'Analytics opt-in status updated: $_optedIn',
    );
  }

  static final _forbiddenParamPatterns = [
    RegExp(
      r'(amount|balance|money|salary|income|expense)',
      caseSensitive: false,
    ),
    RegExp(r'(account_?num|card_?last4|iban|routing)', caseSensitive: false),
    RegExp(r'(notes?|memo|description|merchant|payee)', caseSensitive: false),
    RegExp(r'(token|auth|secret|password|pin)', caseSensitive: false),
  ];

  @override
  Future<void> logEvent(
    String eventName, {
    Map<String, dynamic>? parameters,
  }) async {
    if (!_optedIn) {
      AppLogger.debug(
        'AnalyticsService',
        'Event "$eventName" dropped: User has not opted into analytics.',
      );
      return;
    }

    final sanitizedParams = <String, dynamic>{};
    if (parameters != null) {
      for (final entry in parameters.entries) {
        final isForbidden = _forbiddenParamPatterns.any(
          (p) => p.hasMatch(entry.key),
        );
        if (isForbidden) {
          AppLogger.warning(
            'AnalyticsService',
            'Dropped forbidden financial/PII parameter "${entry.key}" from event "$eventName"',
          );
          continue;
        }
        sanitizedParams[entry.key] = entry.value;
      }
    }

    loggedEvents.add({
      'eventName': eventName,
      'timestamp': DateTime.now().toIso8601String(),
      'parameters': sanitizedParams,
    });

    AppLogger.debug(
      'AnalyticsService',
      'Event logged: "$eventName" with sanitized params: $sanitizedParams',
    );
  }

  void clear() => loggedEvents.clear();
}

class AnalyticsServiceProvider {
  static AnalyticsService instance = PrivacyAnalyticsService();

  static void setService(AnalyticsService service) {
    instance = service;
  }
}
