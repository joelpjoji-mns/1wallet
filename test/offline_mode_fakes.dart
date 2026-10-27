import 'dart:async';

import 'package:one_wallet_flutter/src/auth/auth_controller.dart';
import 'package:one_wallet_flutter/src/auth/auth_user.dart';
import 'package:one_wallet_flutter/src/cloud_sync/cloud_sync_controller.dart';
import 'package:one_wallet_flutter/src/cloud_sync/cloud_sync_write_guard.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/offline_mode/offline_mode_controller.dart';

/// Auth backend double: no Firebase, fully scripted.
class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository({
    this.available = true,
    this.signInUser,
    AuthUser? currentUser,
  }) : _current = currentUser;

  bool available;
  AuthUser? signInUser;
  Object? signInError;
  AuthUser? _current;
  int signInCalls = 0;
  int signOutCalls = 0;
  final _changes = StreamController<AuthUser?>.broadcast();

  @override
  AuthAvailability get availability => available
      ? const AuthAvailability.available()
      : const AuthAvailability.unavailable('Firebase is not configured.');

  @override
  AuthUser? get currentUser => _current;

  @override
  Stream<AuthUser?> get authStateChanges async* {
    yield _current;
    yield* _changes.stream;
  }

  @override
  Future<AuthUser?> signInWithGoogle() async {
    signInCalls++;
    final error = signInError;
    if (error != null) throw error;
    _current = signInUser;
    return signInUser;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _current = null;
  }
}

/// In-memory wallet store that records what was persisted.
class MemoryLedgerRepository extends LedgerRepository {
  MemoryLedgerRepository([this.saved]);

  LedgerState? saved;
  int clears = 0;

  @override
  Future<LedgerState?> load() async => saved;

  @override
  Future<void> save(LedgerState state) async => saved = state;

  @override
  Future<void> clear() async {
    clears++;
    saved = null;
  }
}

/// Firestore stand-in for the offline → Google upgrade.
class FakeUpgradeGateway implements OfflineUpgradeCloudGateway {
  CloudWalletProbe probeResult = const CloudWalletProbe(
    exists: false,
    live: CloudWriteState.unknown,
  );
  Object? probeError;
  CloudWalletSnapshot? snapshot;
  int probeCalls = 0;
  int fetchCalls = 0;
  final primed = <(String, CloudWriteState?)>[];

  @override
  Future<CloudWalletProbe> probe(String userId) async {
    probeCalls++;
    final error = probeError;
    if (error != null) throw error;
    return probeResult;
  }

  @override
  Future<CloudWalletSnapshot> fetchSnapshot(String userId) async {
    fetchCalls++;
    return snapshot!;
  }

  @override
  Future<void> primeOwner(String userId, {CloudWriteState? baseline}) async {
    primed.add((userId, baseline));
  }
}
