import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/observability/analytics_service.dart';
import 'package:one_wallet_flutter/src/observability/app_logger.dart';
import 'package:one_wallet_flutter/src/observability/crash_reporter.dart';
import 'package:one_wallet_flutter/src/observability/perf_tracer.dart';

void main() {
  group('Observability & Production Quality', () {
    setUp(() {
      AppLogger.memorySink.clear();
      AppLogger.minLevel = LogLevel.trace;
    });

    group('AppLogger & Redaction', () {
      test('scrubs currency symbols and monetary amounts from log messages', () {
        const rawMessage =
            'User transferred \$1,500.50 from bank to cash. Balance: ₹45,000. Minor: 150000 minorUnits.';
        final redacted = AppLogger.redact(rawMessage);

        expect(redacted, isNot(contains('\$1,500.50')));
        expect(redacted, isNot(contains('₹45,000')));
        expect(redacted, contains('[REDACTED]'));
      });

      test('scrubs bearer tokens and API keys from log messages', () {
        const rawMessage =
            'Request Authorization: Bearer eyJhbGciOiJIUzI1Ni. Secret: apiKey=super_secret_key_123';
        final redacted = AppLogger.redact(rawMessage);

        expect(redacted, isNot(contains('eyJhbGciOiJIUzI1Ni')));
        expect(redacted, isNot(contains('super_secret_key_123')));
        expect(redacted, contains('[REDACTED]'));
      });

      test('redacts sensitive metadata keys and nested maps', () {
        final rawMeta = {
          'user_id': 'user-123',
          'amount': 25000,
          'accountBalance': '500.00 USD',
          'authToken': 'xyz987',
          'safe_key': 'hello_world',
          'nested': {
            'cardLast4': 1234,
            'status': 'success',
          },
        };

        final sanitized = AppLogger.redactMetadata(rawMeta);

        expect(sanitized['user_id'], equals('user-123'));
        expect(sanitized['safe_key'], equals('hello_world'));
        expect(sanitized['amount'], equals('[REDACTED]'));
        expect(sanitized['accountBalance'], equals('[REDACTED]'));
        expect(sanitized['authToken'], equals('[REDACTED]'));
        expect((sanitized['nested'] as Map)['cardLast4'], equals('[REDACTED]'));
        expect((sanitized['nested'] as Map)['status'], equals('success'));
      });

      test('records structured log entry to memory sink with sanitized data', () {
        AppLogger.info(
          'SyncEngine',
          'Pushing update with balance: 5000',
          metadata: {'amountMinor': 5000, 'operation': 'upload'},
        );

        final records = AppLogger.memorySink.records;
        expect(records.length, equals(1));
        final record = records.first;
        expect(record.tag, equals('SyncEngine'));
        expect(record.level, equals(LogLevel.info));
        expect(record.message, contains('[REDACTED]'));
        expect(record.metadata['amountMinor'], equals('[REDACTED]'));
        expect(record.metadata['operation'], equals('upload'));
      });
    });

    group('CrashReporter & Privacy', () {
      test('initializes with app release tags and commit hash', () async {
        final reporter = NoopCrashReporter();
        await reporter.initialize(
          appVersion: '2.2.0',
          buildNumber: '2102200',
          gitCommitSha: 'abcdef1234567890',
        );

        expect(reporter.initialized, isTrue);
        expect(reporter.customKeys['appVersion'], equals('2.2.0'));
        expect(reporter.customKeys['buildNumber'], equals('2102200'));
        expect(reporter.customKeys['gitCommitSha'], equals('abcdef1234567890'));
      });

      test('anonymizes user id using sha-256 hash', () {
        final reporter = NoopCrashReporter();
        reporter.setUserId('user_google_12345@gmail.com');

        expect(reporter.anonymizedUserId, isNotNull);
        expect(reporter.anonymizedUserId, isNot(contains('user_google_12345')));
        expect(reporter.anonymizedUserId, isNot(contains('@gmail.com')));
        expect(reporter.anonymizedUserId!.length, equals(16));
      });

      test('records errors with sanitized custom keys and reasons', () {
        final reporter = NoopCrashReporter();
        reporter.recordError(
          Exception('Database write failed'),
          StackTrace.current,
          reason: 'Failed saving transaction with amount: 2500',
          customKeys: {
            'module': 'ledger',
            'amountMinor': 2500,
          },
        );

        expect(reporter.recordedErrors.length, equals(1));
        final entry = reporter.recordedErrors.first;
        expect(entry['reason'], contains('[REDACTED]'));
        expect((entry['customKeys'] as Map)['amountMinor'], equals('[REDACTED]'));
        expect((entry['customKeys'] as Map)['module'], equals('ledger'));
      });
    });

    group('Performance Budgets & Traces', () {
      test('detects when operation exceeds performance budget and logs warning', () {
        final span = TraceSpan(
          name: 'simulated_slow_sync',
          budget: const Duration(milliseconds: 1),
        );

        // Simulate work
        final stopwatch = Stopwatch()..start();
        while (stopwatch.elapsedMilliseconds < 5) {
          // busy wait 5ms
        }
        stopwatch.stop();

        final elapsed = span.stop();
        expect(elapsed.inMilliseconds, greaterThanOrEqualTo(1));
        expect(span.budgetExceeded, isTrue);

        final warnings = AppLogger.memorySink.records
            .where((r) => r.level == LogLevel.warning && r.tag == 'PerformanceBudget');
        expect(warnings, isNotEmpty);
        expect(warnings.first.message, contains('EXCEEDED budget'));
      });

      test('logs debug info when operation is within budget', () {
        final span = TraceSpan(
          name: 'fast_ledger_load',
          budget: const Duration(seconds: 10),
        );
        span.stop();

        expect(span.budgetExceeded, isFalse);
        final debugLogs = AppLogger.memorySink.records
            .where((r) => r.tag == 'PerformanceBudget');
        expect(debugLogs.last.message, contains('within budget'));
      });
    });

    group('Privacy-Preserving Analytics', () {
      test('drops all events when user has not opted into analytics', () async {
        final service = PrivacyAnalyticsService(initialOptIn: false);
        expect(service.isOptedIn, isFalse);

        await service.logEvent('button_tap', parameters: {'screen': 'home'});
        expect(service.loggedEvents, isEmpty);
      });

      test('logs events with sanitized parameters when opted in', () async {
        final service = PrivacyAnalyticsService(initialOptIn: true);
        expect(service.isOptedIn, isTrue);

        await service.logEvent('backup_exported', parameters: {
          'feature': 'backup',
          'amountMinor': 10000, // forbidden financial key
          'cardLast4': 9876, // forbidden card key
          'notes': 'private user note', // forbidden note key
          'format': 'json_encrypted', // allowed key
        });

        expect(service.loggedEvents.length, equals(1));
        final event = service.loggedEvents.first;
        expect(event['eventName'], equals('backup_exported'));

        final params = event['parameters'] as Map<String, dynamic>;
        expect(params['feature'], equals('backup'));
        expect(params['format'], equals('json_encrypted'));
        expect(params.containsKey('amountMinor'), isFalse);
        expect(params.containsKey('cardLast4'), isFalse);
        expect(params.containsKey('notes'), isFalse);
      });
    });
  });
}
