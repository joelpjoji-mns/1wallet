import 'app_logger.dart';

class PerformanceBudgets {
  static const Duration coldStart = Duration(milliseconds: 1500);
  static const Duration ledgerLoad = Duration(milliseconds: 500);
  static const Duration cloudSync = Duration(milliseconds: 800);
  static const Duration backupEncryption = Duration(milliseconds: 300);
  static const Duration frameRaster = Duration(milliseconds: 16); // 60 FPS
}

class TraceSpan {
  TraceSpan({required this.name, this.budget, this.onCompleted})
    : _stopwatch = Stopwatch()..start();

  final String name;
  final Duration? budget;
  final void Function(TraceSpan span)? onCompleted;
  final Stopwatch _stopwatch;
  Duration? _duration;
  bool _stopped = false;

  bool get isStopped => _stopped;
  Duration get duration => _duration ?? _stopwatch.elapsed;
  bool get budgetExceeded => budget != null && duration > budget!;

  Duration stop() {
    if (_stopped) return duration;
    _stopwatch.stop();
    _duration = _stopwatch.elapsed;
    _stopped = true;

    final durMs = _duration!.inMilliseconds;
    if (budget != null) {
      final budgetMs = budget!.inMilliseconds;
      if (budgetExceeded) {
        AppLogger.warning(
          'PerformanceBudget',
          'Trace "$name" EXCEEDED budget: ${durMs}ms > ${budgetMs}ms',
          metadata: {
            'trace': name,
            'durationMs': durMs,
            'budgetMs': budgetMs,
            'exceededByMs': durMs - budgetMs,
          },
        );
      } else {
        AppLogger.debug(
          'PerformanceBudget',
          'Trace "$name" within budget: ${durMs}ms <= ${budgetMs}ms',
          metadata: {'trace': name, 'durationMs': durMs, 'budgetMs': budgetMs},
        );
      }
    } else {
      AppLogger.debug(
        'PerformanceTrace',
        'Trace "$name" completed in ${durMs}ms',
      );
    }

    onCompleted?.call(this);
    return _duration!;
  }
}

abstract class PerformanceTracker {
  TraceSpan startTrace(String name, {Duration? budget});
  List<TraceSpan> get completedTraces;
  void clear();
}

class DefaultPerformanceTracker implements PerformanceTracker {
  final List<TraceSpan> _completed = [];

  @override
  TraceSpan startTrace(String name, {Duration? budget}) {
    return TraceSpan(
      name: name,
      budget: budget,
      onCompleted: (span) => _completed.add(span),
    );
  }

  @override
  List<TraceSpan> get completedTraces => List.unmodifiable(_completed);

  @override
  void clear() => _completed.clear();
}

class PerfTracer {
  static PerformanceTracker instance = DefaultPerformanceTracker();

  static TraceSpan startColdStartTrace() =>
      instance.startTrace('cold_start', budget: PerformanceBudgets.coldStart);

  static TraceSpan startLedgerLoadTrace() =>
      instance.startTrace('ledger_load', budget: PerformanceBudgets.ledgerLoad);

  static TraceSpan startCloudSyncTrace() =>
      instance.startTrace('cloud_sync', budget: PerformanceBudgets.cloudSync);

  static TraceSpan startBackupEncryptionTrace() => instance.startTrace(
    'backup_encryption',
    budget: PerformanceBudgets.backupEncryption,
  );
}
