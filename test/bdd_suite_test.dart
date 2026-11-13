import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import 'bdd/bdd_context.dart';
import 'bdd/bdd_parser.dart';
import 'bdd/bdd_reporter.dart';
import 'bdd/step_definitions/offline_steps.dart';

void main() {
  final reporter = BddReporter();
  final featuresDir = Directory('test/bdd/features');

  tearDownAll(() {
    reporter.writeReports();
  });

  group('BDD Executable Specifications', () {
    if (!featuresDir.existsSync()) {
      test('Features directory exists', () {
        fail('Features directory not found: test/bdd/features');
      });
      return;
    }

    final featureFiles =
        featuresDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.feature'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in featureFiles) {
      final feature = BddParser.parseFile(file.path);
      final featureRecord = FeatureExecutionRecord(
        name: feature.name,
        uri: file.path.replaceAll('\\', '/'),
        description: feature.description,
        scenarios: [],
      );
      reporter.addFeature(featureRecord);

      group('Feature: ${feature.name}', () {
        for (final scenario in feature.scenarios) {
          test(scenario.name, () async {
            final context = BddContext();
            registerOfflineSteps(context);

            final stepRecords = <StepExecutionRecord>[];
            var scenarioPassed = true;

            for (final step in scenario.steps) {
              final stopwatch = Stopwatch()..start();
              try {
                await context.executeStep(step.type, step.text);
                stopwatch.stop();
                stepRecords.add(
                  StepExecutionRecord(
                    keyword: step.rawType,
                    name: step.text,
                    status: 'passed',
                    durationNanos: stopwatch.elapsedMicroseconds * 1000,
                  ),
                );
              } catch (e) {
                stopwatch.stop();
                scenarioPassed = false;
                stepRecords.add(
                  StepExecutionRecord(
                    keyword: step.rawType,
                    name: step.text,
                    status: 'failed',
                    durationNanos: stopwatch.elapsedMicroseconds * 1000,
                    errorMessage: e.toString(),
                  ),
                );
                featureRecord.scenarios.add(
                  ScenarioExecutionRecord(
                    name: scenario.name,
                    steps: stepRecords,
                    status: 'failed',
                  ),
                );
                rethrow;
              }
            }

            featureRecord.scenarios.add(
              ScenarioExecutionRecord(
                name: scenario.name,
                steps: stepRecords,
                status: scenarioPassed ? 'passed' : 'failed',
              ),
            );
          });
        }
      });
    }
  });
}
