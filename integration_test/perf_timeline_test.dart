import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Performance & Jank Benchmark (Timeline Traces)', () {
    testWidgets('captures frame timeline and verifies rendering performance', (
      tester,
    ) async {
      await binding.traceAction(() async {
        final stopwatch = Stopwatch()..start();

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
        final duration = stopwatch.elapsed;

        expect(
          duration.inMilliseconds,
          lessThan(const Duration(seconds: 2).inMilliseconds),
          reason: 'Cold start rendering exceeded performance budget',
        );

        // Scroll test for jank detection
        await tester.fling(find.byType(ListView), const Offset(0, -300), 1000);
        await tester.pumpAndSettle();
      }, reportKey: 'perf_timeline_summary');
    });
  });
}
