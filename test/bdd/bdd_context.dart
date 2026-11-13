import 'package:one_wallet_flutter/src/data/ledger_models.dart';

typedef StepHandler = Future<void> Function(List<String?> matches);

class BddContext {
  LedgerState? state;
  bool isOffline = true;
  String? signedInUserId;
  int cloudWritesCount = 0;
  bool unsyncedChanges = false;

  final Map<RegExp, StepHandler> _given = {};
  final Map<RegExp, StepHandler> _when = {};
  final Map<RegExp, StepHandler> _then = {};

  void given(RegExp pattern, StepHandler handler) {
    _given[pattern] = handler;
  }

  void when(RegExp pattern, StepHandler handler) {
    _when[pattern] = handler;
  }

  void then(RegExp pattern, StepHandler handler) {
    _then[pattern] = handler;
  }

  void reset() {
    state = null;
    isOffline = true;
    signedInUserId = null;
    cloudWritesCount = 0;
    unsyncedChanges = false;
  }

  Future<void> executeStep(String stepType, String text) async {
    Map<RegExp, StepHandler> stepMap;
    switch (stepType.toLowerCase()) {
      case 'given':
        stepMap = _given;
        break;
      case 'when':
        stepMap = _when;
        break;
      case 'then':
        stepMap = _then;
        break;
      default:
        throw ArgumentError('Unknown step type: $stepType');
    }

    for (final entry in stepMap.entries) {
      final match = entry.key.firstMatch(text);
      if (match != null) {
        final groups = <String?>[
          for (var i = 0; i <= match.groupCount; i++) match.group(i),
        ];
        await entry.value(groups);
        return;
      }
    }

    throw StateError(
      'No step definition found for [$stepType] "$text". Check test/bdd/step_definitions/',
    );
  }
}
