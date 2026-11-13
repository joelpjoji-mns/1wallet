import 'dart:io';

class BddStep {
  BddStep({required this.type, required this.rawType, required this.text});

  final String type; // 'Given', 'When', or 'Then'
  final String rawType; // 'Given', 'When', 'Then', 'And', 'But'
  final String text;
}

class BddScenario {
  BddScenario({required this.name, required this.steps});

  final String name;
  final List<BddStep> steps;
}

class BddFeature {
  BddFeature({
    required this.name,
    required this.description,
    required this.scenarios,
    required this.filePath,
  });

  final String name;
  final String description;
  final List<BddScenario> scenarios;
  final String filePath;
}

class BddParser {
  static BddFeature parseFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw ArgumentError('Feature file not found: $path');
    }
    return parseString(file.readAsStringSync(), path);
  }

  static BddFeature parseString(String content, [String path = 'in_memory']) {
    final lines = content.split(RegExp(r'\r?\n'));
    String featureName = 'Unnamed Feature';
    final descriptionLines = <String>[];
    final scenarios = <BddScenario>[];

    String? currentScenarioName;
    List<BddStep> currentSteps = [];
    String lastStepType = 'Given';

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }

      if (line.startsWith('Feature:')) {
        featureName = line.substring('Feature:'.length).trim();
      } else if (line.startsWith('Scenario:')) {
        if (currentScenarioName != null) {
          scenarios.add(
            BddScenario(name: currentScenarioName, steps: currentSteps),
          );
        }
        currentScenarioName = line.substring('Scenario:'.length).trim();
        currentSteps = [];
        lastStepType = 'Given';
      } else if (line.startsWith('Given ') ||
          line.startsWith('When ') ||
          line.startsWith('Then ') ||
          line.startsWith('And ') ||
          line.startsWith('But ')) {
        final spaceIndex = line.indexOf(' ');
        final rawType = line.substring(0, spaceIndex);
        final stepText = line.substring(spaceIndex + 1).trim();

        String effectiveType = rawType;
        if (rawType == 'And' || rawType == 'But') {
          effectiveType = lastStepType;
        } else {
          lastStepType = rawType;
        }

        currentSteps.add(
          BddStep(type: effectiveType, rawType: rawType, text: stepText),
        );
      } else if (currentScenarioName == null) {
        descriptionLines.add(line);
      }
    }

    if (currentScenarioName != null) {
      scenarios.add(
        BddScenario(name: currentScenarioName, steps: currentSteps),
      );
    }

    return BddFeature(
      name: featureName,
      description: descriptionLines.join('\n'),
      scenarios: scenarios,
      filePath: path,
    );
  }
}
