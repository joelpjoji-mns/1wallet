import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:one_wallet_flutter/src/observability/app_logger.dart';
import 'package:one_wallet_flutter/src/observability/perf_tracer.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Performance & Jank Benchmark (Timeline Traces)', () {
    testWidgets('captures frame timeline and verifies rendering performance',
        (tester) async {
      AppLogger.info('PerfTest', 'Starting timeline trace benchmark');

      await binding.traceAction(() async {
        final span = PerfTracer.startColdStartTrace();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView.builder(
                itemCount: 100,
                itemBuilder: (context, index) => ListTile(
                  title: Text('Account Item #$index'),
                  subtitle: const Text('Cleared Transaction'),
                  trailing: const Text('Status: OK'),
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        final duration = span.stop();

        expect(
          duration.inMilliseconds,
          lessThan(PerformanceBudgets.coldStart.inMilliseconds),
          reason: 'Cold start rendering exceeded performance budget',
        );

        // Scroll test for jank detection
        await tester.fling(find.byType(ListView), const Offset(0, -300), 1000);
        await tester.pumpAndSettle();
      }, reportKey: 'perf_timeline_summary');

      AppLogger.info('PerfTest', 'Timeline trace completed successfully');
    });
  });
}
