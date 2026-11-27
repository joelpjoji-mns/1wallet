import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';

class DiscoveryCloudProgress {
  const DiscoveryCloudProgress({
    this.welcomeSeen = false,
    this.started = false,
    this.finished = false,
    this.step = 0,
    this.completed = const {},
    this.skipped = const {},
    this.introduced = const {},
  });

  final bool welcomeSeen;
  final bool started;
  final bool finished;
  final int step;
  final Set<int> completed;
  final Set<int> skipped;
  final Set<String> introduced;

  DiscoveryCloudProgress merge(DiscoveryCloudProgress other) {
    final completedSteps = {...completed, ...other.completed};
    return DiscoveryCloudProgress(
      welcomeSeen: welcomeSeen || other.welcomeSeen,
      started: started || other.started,
      finished: finished || other.finished,
      step: math.max(step, other.step),
      completed: completedSteps,
      skipped: {...skipped, ...other.skipped}.difference(completedSteps),
      introduced: {...introduced, ...other.introduced},
    );
  }

  /// Whether merging [other] into this progress would change nothing.
  bool covers(DiscoveryCloudProgress other) =>
      (welcomeSeen || !other.welcomeSeen) &&
      (started || !other.started) &&
      (finished || !other.finished) &&
      step >= other.step &&
      completed.containsAll(other.completed) &&
      skipped.containsAll(other.skipped.difference(completed)) &&
      introduced.containsAll(other.introduced);

  factory DiscoveryCloudProgress.fromMap(Map<String, dynamic> data) {
    if (data['completed'] is! bool) {
      throw const FormatException('Invalid cloud discovery progress.');
    }
    if (!data.containsKey('step')) {
      if (data['completed'] != true) {
        throw const FormatException('Invalid legacy tour completion.');
      }
      return const DiscoveryCloudProgress(
        welcomeSeen: true,
        started: true,
        finished: true,
      );
    }
    final step = data['step'];
    if (step is! int || step < 0 || step >= 6) {
      throw const FormatException('Invalid cloud discovery step.');
    }
    final completed = (data['completedSteps'] as List<dynamic>).cast<int>();
    final skipped = (data['skippedSteps'] as List<dynamic>).cast<int>();
    if ([...completed, ...skipped].any((step) => step < 0 || step >= 6)) {
      throw const FormatException('Invalid cloud discovery steps.');
    }
    return DiscoveryCloudProgress(
      welcomeSeen: data['welcomeSeen'] as bool,
      started: data['started'] as bool,
      finished: data['completed'] as bool,
      step: step,
      completed: completed.toSet(),
      skipped: skipped.toSet(),
      introduced: (data['introduced'] as List<dynamic>).cast<String>().toSet(),
    );
  }

  Map<String, dynamic> toMap() => {
    'welcomeSeen': welcomeSeen,
    'started': started,
    'completed': finished,
    'step': step,
    'completedSteps': completed.toList()..sort(),
    'skippedSteps': skipped.toList()..sort(),
    'introduced': introduced.toList()..sort(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

abstract class DiscoveryCompletionStore {
  Future<DiscoveryCloudProgress?> readProgress();
  Future<DiscoveryCloudProgress> mergeProgress(DiscoveryCloudProgress progress);
}

final discoveryCompletionStoreProvider =
    Provider.family<DiscoveryCompletionStore?, String>((ref, ownerId) {
      final activeOwner = ref.watch(
        authControllerProvider.select(
          (auth) => auth.isAuthenticated ? auth.user?.id : null,
        ),
      );
      if (activeOwner != ownerId || Firebase.apps.isEmpty) return null;
      return _FirestoreDiscoveryCompletionStore(
        FirebaseFirestore.instance,
        ownerId,
        () => ref.read(authControllerProvider).user?.id == ownerId,
      );
    });

// Transactions need the server; give cold starts and app resumes time to
// reconnect instead of failing after a few seconds.
const _cloudTimeout = Duration(seconds: 20);

class _FirestoreDiscoveryCompletionStore implements DiscoveryCompletionStore {
  _FirestoreDiscoveryCompletionStore(
    this.firestore,
    this.ownerId,
    this.isCurrentOwner,
  );

  final FirebaseFirestore firestore;
  final String ownerId;
  final bool Function() isCurrentOwner;

  DocumentReference<Map<String, dynamic>> get _document =>
      firestore.doc('users/$ownerId/discovery/intro');

  void _checkOwner() {
    if (!isCurrentOwner()) throw StateError('The signed-in account changed.');
  }

  @override
  Future<DiscoveryCloudProgress?> readProgress() async {
    _checkOwner();
    final snapshot = await _document
        .get(const GetOptions(source: Source.server))
        .timeout(_cloudTimeout);
    _checkOwner();
    final data = snapshot.data();
    return data == null ? null : DiscoveryCloudProgress.fromMap(data);
  }

  @override
  Future<DiscoveryCloudProgress> mergeProgress(
    DiscoveryCloudProgress progress,
  ) async {
    _checkOwner();
    final result = await firestore
        .runTransaction((transaction) async {
          _checkOwner();
          final snapshot = await transaction.get(_document);
          _checkOwner();
          final data = snapshot.data();
          final merged = data == null
              ? progress
              : DiscoveryCloudProgress.fromMap(data).merge(progress);
          transaction.set(_document, merged.toMap());
          return merged;
        })
        .timeout(_cloudTimeout);
    _checkOwner();
    return result;
  }
}
