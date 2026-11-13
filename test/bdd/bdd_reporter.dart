import 'dart:convert';
import 'dart:io';

class StepExecutionRecord {
  StepExecutionRecord({
    required this.keyword,
    required this.name,
    required this.status,
    required this.durationNanos,
    this.errorMessage,
  });

  final String keyword;
  final String name;
  final String status; // 'passed' | 'failed'
  final int durationNanos;
  final String? errorMessage;

  Map<String, dynamic> toJson() => {
        'keyword': '$keyword ',
        'name': name,
        'result': {
          'status': status,
          'duration': durationNanos,
          if (errorMessage != null) 'error_message': errorMessage,
        },
      };
}

class ScenarioExecutionRecord {
  ScenarioExecutionRecord({
    required this.name,
    required this.steps,
    required this.status,
  });

  final String name;
  final List<StepExecutionRecord> steps;
  final String status;

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': 'scenario',
        'keyword': 'Scenario',
        'steps': steps.map((s) => s.toJson()).toList(),
      };
}

class FeatureExecutionRecord {
  FeatureExecutionRecord({
    required this.name,
    required this.uri,
    required this.description,
    required this.scenarios,
  });

  final String name;
  final String uri;
  final String description;
  final List<ScenarioExecutionRecord> scenarios;

  Map<String, dynamic> toJson() => {
        'uri': uri,
        'id': name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'),
        'name': name,
        'description': description,
        'keyword': 'Feature',
        'elements': scenarios.map((s) => s.toJson()).toList(),
      };
}

class BddReporter {
  final List<FeatureExecutionRecord> features = [];

  void addFeature(FeatureExecutionRecord record) {
    features.add(record);
  }

  void writeReports({String outputDir = 'build/reports'}) {
    final dir = Directory(outputDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final jsonFile = File('${dir.path}/bdd_report.json');
    final jsonContent =
        const JsonEncoder.withIndent('  ').convert(features.map((f) => f.toJson()).toList());
    jsonFile.writeAsStringSync(jsonContent);

    final summaryFile = File('${dir.path}/bdd_summary.txt');
    final buffer = StringBuffer();
    buffer.writeln('====================================================');
    buffer.writeln('          1WALLET BDD EXECUTABLE SPECS SUMMARY      ');
    buffer.writeln('====================================================\n');

    var totalScenarios = 0;
    var passedScenarios = 0;
    var failedScenarios = 0;
    var totalSteps = 0;
    var passedSteps = 0;
    var failedSteps = 0;

    for (final feature in features) {
      buffer.writeln('Feature: ${feature.name}');
      for (final scenario in feature.scenarios) {
        totalScenarios++;
        final icon = scenario.status == 'passed' ? '✔' : '✖';
        buffer.writeln('  $icon Scenario: ${scenario.name}');
        if (scenario.status == 'passed') {
          passedScenarios++;
        } else {
          failedScenarios++;
        }

        for (final step in scenario.steps) {
          totalSteps++;
          final sIcon = step.status == 'passed' ? '  ✔' : '  ✖';
          final durMs = (step.durationNanos / 1000000).toStringAsFixed(2);
          buffer.writeln('    $sIcon ${step.keyword}${step.name} (${durMs}ms)');
          if (step.status == 'passed') {
            passedSteps++;
          } else {
            failedSteps++;
            if (step.errorMessage != null) {
              buffer.writeln('        Error: ${step.errorMessage}');
            }
          }
        }
      }
      buffer.writeln();
    }

    buffer.writeln('----------------------------------------------------');
    buffer.writeln('Scenarios: $passedScenarios passed, $failedScenarios failed, $totalScenarios total');
    buffer.writeln('Steps:     $passedSteps passed, $failedSteps failed, $totalSteps total');
    buffer.writeln('Status:    ${failedScenarios == 0 ? "PASSED" : "FAILED"}');
    buffer.writeln('====================================================');

    summaryFile.writeAsStringSync(buffer.toString());
  }
}
