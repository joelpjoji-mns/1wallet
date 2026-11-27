import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/theme_controller.dart';
import 'discovery_cloud_store.dart';
import 'discovery_feature_guides.dart';

enum DiscoveryStatus { dormant, welcome, active, paused, completion, finished }

const discoveryChapters = <String, Set<int>>{
  'Home': {0},
  'Getting started': {1},
  'Activity': {2, 3},
  'Accounts': {4},
  'Personalization': {5},
};

@immutable
class DiscoveryIntroCheckpoint {
  const DiscoveryIntroCheckpoint({
    required this.status,
    required this.step,
    required this.completed,
    required this.skipped,
  });

  final DiscoveryStatus status;
  final int step;
  final Set<int> completed;
  final Set<int> skipped;

  factory DiscoveryIntroCheckpoint.fromMap(Map<String, dynamic> json) {
    final step = json['step'] as int;
    if (step < 0 || step >= discoveryStepCount) {
      throw const FormatException('Invalid discovery checkpoint.');
    }
    return DiscoveryIntroCheckpoint(
      status: DiscoveryStatus.values.byName(json['status'] as String),
      step: step,
      completed: (json['completed'] as List<dynamic>).cast<int>().toSet(),
      skipped: (json['skipped'] as List<dynamic>).cast<int>().toSet(),
    );
  }

  Map<String, dynamic> toMap() => {
    'status': status.name,
    'step': step,
    'completed': completed.toList()..sort(),
    'skipped': skipped.toList()..sort(),
  };
}

@immutable
class DiscoveryProgress {
  const DiscoveryProgress({
    this.status = DiscoveryStatus.dormant,
    this.step = 0,
    this.startStep = 0,
    this.endStep = discoveryStepCount - 1,
    this.completed = const {},
    this.skipped = const {},
    this.isRestoring = false,
    this.syncError,
    this.introFinished = false,
    this.introduced = const {},
    this.isReplay = false,
    this.introCheckpoint,
    this.replayHintsDismissed = const {},
    this.requestedHint,
    this.guideStep = 0,
    this.guideJourney = false,
    this.automaticTourEligible = false,
    this.guideActive = false,
  });

  final DiscoveryStatus status;
  final int step;
  final int startStep;
  final int endStep;
  final Set<int> completed;
  final Set<int> skipped;
  final bool isRestoring;
  final String? syncError;
  final bool introFinished;
  final Set<String> introduced;
  final bool isReplay;
  final DiscoveryIntroCheckpoint? introCheckpoint;
  final Set<String> replayHintsDismissed;
  final String? requestedHint;
  final int guideStep;
  final bool guideJourney;
  final bool automaticTourEligible;
  final bool guideActive;

  Set<String> get completedChapters => {
    for (final entry in discoveryChapters.entries)
      if (completed.containsAll(entry.value)) entry.key,
  };

  DiscoveryProgress copyWith({
    DiscoveryStatus? status,
    int? step,
    int? startStep,
    int? endStep,
    Set<int>? completed,
    Set<int>? skipped,
    bool? isRestoring,
    String? syncError,
    bool clearSyncError = false,
    bool? introFinished,
    Set<String>? introduced,
    bool? isReplay,
    DiscoveryIntroCheckpoint? introCheckpoint,
    bool clearIntroCheckpoint = false,
    Set<String>? replayHintsDismissed,
    String? requestedHint,
    bool clearRequestedHint = false,
    int? guideStep,
    bool? guideJourney,
    bool? automaticTourEligible,
    bool? guideActive,
  }) => DiscoveryProgress(
    status: status ?? this.status,
    step: step ?? this.step,
    startStep: startStep ?? this.startStep,
    endStep: endStep ?? this.endStep,
    completed: completed ?? this.completed,
    skipped: skipped ?? this.skipped,
    isRestoring: isRestoring ?? this.isRestoring,
    syncError: clearSyncError ? null : syncError ?? this.syncError,
    introFinished: introFinished ?? this.introFinished,
    introduced: introduced ?? this.introduced,
    isReplay: isReplay ?? this.isReplay,
    introCheckpoint: clearIntroCheckpoint
        ? null
        : introCheckpoint ?? this.introCheckpoint,
    replayHintsDismissed: replayHintsDismissed ?? this.replayHintsDismissed,
    requestedHint: clearRequestedHint
        ? null
        : requestedHint ?? this.requestedHint,
    guideStep: guideStep ?? this.guideStep,
    guideJourney: guideJourney ?? this.guideJourney,
    automaticTourEligible: automaticTourEligible ?? this.automaticTourEligible,
    guideActive: guideActive ?? this.guideActive,
  );
}

const discoveryStepCount = 6;

final discoveryControllerProvider =
    StateNotifierProvider.family<
      DiscoveryController,
      DiscoveryProgress,
      String
    >(
      (ref, ownerId) => DiscoveryController(
        ref.watch(sharedPreferencesProvider),
        ownerId,
        completionStore: ref.watch(discoveryCompletionStoreProvider(ownerId)),
      ),
    );

class DiscoveryController extends StateNotifier<DiscoveryProgress> {
  DiscoveryController(this._prefs, String ownerId, {this.completionStore})
    : _key = 'one_wallet_flutter.discovery.v1.$ownerId',
      super(const DiscoveryProgress()) {
    final stored = _prefs.getString(_key);
    if (stored != null) {
      try {
        final json = jsonDecode(stored) as Map<String, dynamic>;
        final status = DiscoveryStatus.values.byName(json['status'] as String);
        final step = json['step'] as int;
        final startStep = json['startStep'] as int? ?? 0;
        final endStep = json['endStep'] as int? ?? discoveryStepCount - 1;
        final requestedHint = json['requestedHint'] as String?;
        final guideStep = json['guideStep'] as int? ?? 0;
        final featureGuide = discoveryFeatureGuide(requestedHint ?? '');
        if (startStep < 0 ||
            endStep >= discoveryStepCount ||
            startStep > endStep ||
            step < startStep ||
            step > endStep) {
          throw const FormatException('Invalid discovery step');
        }
        if (guideStep < 0 ||
            (featureGuide != null && guideStep >= featureGuide.steps.length)) {
          throw const FormatException('Invalid feature guide step');
        }
        state = DiscoveryProgress(
          // A restart should offer to resume, not reopen an active overlay.
          status: switch (status) {
            DiscoveryStatus.active => DiscoveryStatus.paused,
            DiscoveryStatus.welcome => DiscoveryStatus.paused,
            DiscoveryStatus.completion when json['introCheckpoint'] != null =>
              DiscoveryStatus.paused,
            DiscoveryStatus.completion => DiscoveryStatus.finished,
            _ => status,
          },
          step: step,
          startStep: startStep,
          endStep: endStep,
          introFinished:
              json['introFinished'] as bool? ??
              (status == DiscoveryStatus.finished &&
                  startStep == 0 &&
                  endStep == discoveryStepCount - 1),
          completed: (json['completed'] as List<dynamic>).cast<int>().toSet(),
          skipped: (json['skipped'] as List<dynamic>).cast<int>().toSet(),
          introduced: (json['introduced'] as List<dynamic>? ?? const [])
              .cast<String>()
              .toSet(),
          isReplay: json['isReplay'] as bool? ?? false,
          requestedHint: requestedHint,
          guideStep: guideStep,
          guideJourney: json['guideJourney'] as bool? ?? false,
          automaticTourEligible:
              json['automaticTourEligible'] as bool? ?? false,
          replayHintsDismissed:
              (json['replayHintsDismissed'] as List<dynamic>? ?? const [])
                  .cast<String>()
                  .toSet(),
          introCheckpoint: json['introCheckpoint'] == null
              ? null
              : DiscoveryIntroCheckpoint.fromMap(
                  json['introCheckpoint'] as Map<String, dynamic>,
                ),
        );
      } on FormatException catch (error) {
        debugPrint('Could not read discovery progress: $error');
      } on TypeError catch (error) {
        debugPrint('Could not read discovery progress: $error');
      } on ArgumentError catch (error) {
        debugPrint('Could not read discovery progress: $error');
      }
    }
    if (completionStore != null) {
      state = state.copyWith(isRestoring: stored == null);
      unawaited(refreshCloudCompletion());
    }
  }

  final SharedPreferences _prefs;
  final String _key;
  final DiscoveryCompletionStore? completionStore;
  Future<void> _writes = Future.value();
  bool _syncingCloud = false;
  int _syncGeneration = 0;
  DiscoveryCloudProgress? _lastSynced;
  DateTime? _lastSyncedAt;

  // Tour progress is local-first; the cloud copy only needs an occasional
  // check, not a round-trip on every step, hint or app resume.
  static const cloudRefreshInterval = Duration(minutes: 10);

  Future<void> _save(DiscoveryProgress progress, {bool sync = true}) {
    state = progress;
    if (sync) _syncGeneration++;
    final payload = jsonEncode({
      'status': progress.status.name,
      'step': progress.step,
      'startStep': progress.startStep,
      'endStep': progress.endStep,
      'introFinished': progress.introFinished,
      'introduced': progress.introduced.toList()..sort(),
      'isReplay': progress.isReplay,
      'requestedHint': progress.requestedHint,
      'guideStep': progress.guideStep,
      'guideJourney': progress.guideJourney,
      'automaticTourEligible': progress.automaticTourEligible,
      'replayHintsDismissed': progress.replayHintsDismissed.toList()..sort(),
      'introCheckpoint': progress.introCheckpoint?.toMap(),
      'completed': progress.completed.toList()..sort(),
      'skipped': progress.skipped.toList()..sort(),
    });
    // Keep rapid taps ordered, even when the previous write failed.
    final write = _writes.then((_) async {
      if (!await _prefs.setString(_key, payload)) {
        throw StateError('Could not save guide progress.');
      }
      if (sync && mounted) unawaited(refreshCloudCompletion());
    });
    _writes = write.then<void>(
      (_) {},
      onError: (Object _, StackTrace stack) {},
    );
    return write;
  }

  Future<void> prepareWelcome() => _save(
    const DiscoveryProgress(
      status: DiscoveryStatus.welcome,
      automaticTourEligible: true,
    ),
  );

  Future<void> start() => _save(state.copyWith(status: DiscoveryStatus.active));

  Future<void> pause() => _save(state.copyWith(status: DiscoveryStatus.paused));

  Future<void> finish() async {
    final checkpoint = state.introCheckpoint;
    if (checkpoint != null && !state.introFinished) {
      await _save(
        state.copyWith(
          status: checkpoint.status,
          step: checkpoint.step,
          startStep: 0,
          endStep: discoveryStepCount - 1,
          completed: checkpoint.completed,
          skipped: checkpoint.skipped,
          isReplay: false,
          clearIntroCheckpoint: true,
        ),
      );
      return;
    }
    final introFinished =
        state.introFinished ||
        (state.startStep == 0 && state.endStep == discoveryStepCount - 1);
    await _save(
      state.copyWith(
        status: DiscoveryStatus.finished,
        introFinished: introFinished,
      ),
    );
  }

  Future<void> replay({
    int startStep = 0,
    int endStep = discoveryStepCount - 1,
  }) {
    if (startStep < 0 || endStep >= discoveryStepCount || startStep > endStep) {
      throw RangeError('Invalid discovery guide range.');
    }
    final fullTour = startStep == 0 && endStep == discoveryStepCount - 1;
    final checkpoint = fullTour || state.introFinished
        ? null
        : state.introCheckpoint ??
              DiscoveryIntroCheckpoint(
                status: state.status == DiscoveryStatus.active
                    ? DiscoveryStatus.paused
                    : state.status,
                step: state.step,
                completed: state.completed,
                skipped: state.skipped,
              );
    return _save(
      DiscoveryProgress(
        status: DiscoveryStatus.active,
        step: startStep,
        startStep: startStep,
        endStep: endStep,
        introFinished: state.introFinished,
        introduced: state.introduced,
        isReplay: true,
        introCheckpoint: checkpoint,
        completed: fullTour
            ? const {}
            : (state.completed.toSet()
                ..removeWhere((step) => step >= startStep && step <= endStep)),
        skipped: fullTour
            ? const {}
            : (state.skipped.toSet()
                ..removeWhere((step) => step >= startStep && step <= endStep)),
      ),
    );
  }

  Future<void> previous() => _save(
    state.copyWith(
      step: (state.step - 1).clamp(state.startStep, state.endStep),
    ),
  );

  Future<void> dismissHint(String feature) => _save(
    state.copyWith(
      introduced: {...state.introduced, feature},
      clearRequestedHint: state.requestedHint == feature,
      guideStep: 0,
      guideJourney: false,
      guideActive: false,
      replayHintsDismissed: state.isReplay
          ? {...state.replayHintsDismissed, feature}
          : state.replayHintsDismissed,
    ),
  );

  Future<void> replayHint(String feature) => _save(
    state.copyWith(
      status: switch (state.status) {
        DiscoveryStatus.active ||
        DiscoveryStatus.welcome ||
        DiscoveryStatus.completion => DiscoveryStatus.paused,
        _ => state.status,
      },
      requestedHint: feature,
      guideStep: 0,
      guideJourney: false,
      guideActive: true,
    ),
  );

  Future<void> resumeFeatureGuide() => _save(state.copyWith(guideActive: true));

  Future<void> startWorkflowTour() => _save(
    state.copyWith(
      status: DiscoveryStatus.finished,
      requestedHint: discoveryFeatureGuides.first.id,
      guideStep: 0,
      guideJourney: true,
      guideActive: true,
    ),
  );

  Future<void> setGuideStep(int step) {
    final guide = discoveryFeatureGuide(state.requestedHint ?? '');
    if (guide == null || step < 0 || step >= guide.steps.length) {
      throw ArgumentError.value(step, 'step', 'Invalid feature guide step');
    }
    return _save(state.copyWith(guideStep: step));
  }

  Future<String?> completeFeatureGuide(String feature) async {
    if (state.requestedHint != feature) return null;
    final guides = availableDiscoveryFeatureGuides.toList();
    final index = guides.indexWhere((guide) => guide.id == feature);
    final next = state.guideJourney && index >= 0 && index + 1 < guides.length
        ? guides[index + 1].id
        : null;
    await _save(
      state.copyWith(
        introduced: {...state.introduced, feature},
        requestedHint: next,
        clearRequestedHint: next == null,
        guideStep: 0,
        guideJourney: next != null,
        guideActive: next != null,
      ),
    );
    return next;
  }

  Future<void> clearLocal() {
    state = const DiscoveryProgress();
    _syncGeneration++;
    final clear = _writes.then((_) async {
      if (!await _prefs.remove(_key)) {
        throw StateError('Could not clear guide progress.');
      }
    });
    _writes = clear.then<void>(
      (_) {},
      onError: (Object _, StackTrace stack) {},
    );
    return clear;
  }

  Future<void> advance({bool skipped = false}) async {
    final completed = {...state.completed};
    final skippedSteps = {...state.skipped};
    if (skipped) {
      skippedSteps.add(state.step);
      completed.remove(state.step);
    } else {
      completed.add(state.step);
      skippedSteps.remove(state.step);
    }
    final completesGuide = state.step == state.endStep;
    final completesIntro =
        completesGuide &&
        state.startStep == 0 &&
        state.endStep == discoveryStepCount - 1;
    await _save(
      state.copyWith(
        status: state.step == state.endStep
            ? DiscoveryStatus.completion
            : DiscoveryStatus.active,
        step: (state.step + 1).clamp(state.startStep, state.endStep),
        completed: completed,
        skipped: skippedSteps,
        introFinished: state.introFinished || completesIntro,
      ),
    );
  }

  DiscoveryCloudProgress _cloudSnapshot(DiscoveryProgress progress) {
    final isIntro =
        !progress.isReplay &&
        progress.startStep == 0 &&
        progress.endStep == discoveryStepCount - 1;
    return DiscoveryCloudProgress(
      welcomeSeen: isIntro && progress.status != DiscoveryStatus.dormant,
      started:
          isIntro &&
          progress.status != DiscoveryStatus.dormant &&
          progress.status != DiscoveryStatus.welcome,
      finished: progress.introFinished,
      step: isIntro ? progress.step : 0,
      completed: isIntro ? progress.completed : const {},
      skipped: isIntro ? progress.skipped : const {},
      introduced: progress.introduced,
    );
  }

  DiscoveryProgress _restoreCloud(
    DiscoveryProgress local,
    DiscoveryCloudProgress remote,
  ) {
    final introduced = {...local.introduced, ...remote.introduced};
    if (local.isReplay ||
        local.status == DiscoveryStatus.active ||
        local.status == DiscoveryStatus.completion) {
      return local.copyWith(introduced: introduced);
    }
    final completed = {...local.completed, ...remote.completed};
    final skipped = {...local.skipped, ...remote.skipped}.difference(completed);
    final status = remote.finished
        ? DiscoveryStatus.finished
        : remote.started
        ? DiscoveryStatus.paused
        : remote.welcomeSeen && local.status == DiscoveryStatus.dormant
        ? DiscoveryStatus.welcome
        : local.status;
    return local.copyWith(
      status: status,
      step: local.step > remote.step ? local.step : remote.step,
      completed: completed,
      skipped: skipped,
      introFinished: local.introFinished || remote.finished,
      introduced: introduced,
    );
  }

  Future<void> refreshCloudCompletion() async {
    final store = completionStore;
    if (store == null || _syncingCloud) return;
    final lastSynced = _lastSynced;
    final lastSyncedAt = _lastSyncedAt;
    if (lastSynced != null &&
        lastSyncedAt != null &&
        DateTime.now().difference(lastSyncedAt) < cloudRefreshInterval &&
        lastSynced.covers(_cloudSnapshot(state))) {
      return;
    }
    _syncingCloud = true;
    var retry = false;
    try {
      final generation = _syncGeneration;
      final progressAtStart = state;
      final remote =
          progressAtStart.status == DiscoveryStatus.dormant &&
              progressAtStart.introduced.isEmpty
          ? await store.readProgress()
          : await store.mergeProgress(_cloudSnapshot(progressAtStart));
      if (!mounted) return;
      _lastSynced = remote ?? _cloudSnapshot(progressAtStart);
      _lastSyncedAt = DateTime.now();
      if (remote != null &&
          generation == _syncGeneration &&
          identical(state, progressAtStart)) {
        await _save(_restoreCloud(state, remote), sync: false);
      }
      if (mounted) {
        state = state.copyWith(isRestoring: false, clearSyncError: true);
      }
      retry = generation != _syncGeneration;
    } catch (error) {
      // Offline or slow networks are expected; progress is already saved on
      // this device and the next resume or tour change retries quietly.
      debugPrint('Could not sync guide progress: $error');
      if (mounted) {
        state = state.copyWith(
          isRestoring: false,
          syncError:
              'Tour progress is saved on this device. Cloud sync is unavailable.',
        );
      }
    } finally {
      _syncingCloud = false;
      if (mounted && retry) unawaited(refreshCloudCompletion());
    }
  }
}
