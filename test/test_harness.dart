import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/startup/startup_state.dart';

import 'fixtures/sample_ledger.dart';

List<Override> authenticatedSampleOverrides({LedgerState? ledger}) {
  return [
    startupStateProvider.overrideWithValue(
      const StartupState.ready(destination: StartupDestination.home),
    ),
    ledgerRepositoryProvider.overrideWithValue(
      StaticLedgerRepository(ledger ?? sampleLedgerState()),
    ),
  ];
}

class StaticLedgerRepository extends LedgerRepository {
  StaticLedgerRepository(this._seed);

  final LedgerState _seed;
  LedgerState? _saved;

  @override
  Future<LedgerState?> load() async => _saved ?? _seed;

  @override
  Future<void> save(LedgerState state) async {
    _saved = state;
  }

  @override
  Future<void> clear() async {
    _saved = null;
  }
}
