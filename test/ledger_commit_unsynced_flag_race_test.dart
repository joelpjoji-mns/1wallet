import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';

/// Records, at the moment `save()` is invoked, whether `has_unsynced_changes`
/// was already durably persisted — i.e. whether `LedgerController._commit()`
/// flips that flag *before* handing the new state to the repository, rather
/// than after.
class _RecordingLedgerRepository extends LedgerRepository {
  const _RecordingLedgerRepository(this._onSave);

  final void Function({required bool? hasUnsyncedChangesWhenSaveStarts})
  _onSave;

  @override
  Future<LedgerState?> load() async => null;

  @override
  Future<void> save(LedgerState state) async {
    final prefs = await SharedPreferences.getInstance();
    _onSave(
      hasUnsyncedChangesWhenSaveStarts: prefs.getBool('has_unsynced_changes'),
    );
  }

  @override
  Future<void> clear() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LedgerProvidersConfig.disableAutoBackup = true;
  });

  test('regression: has_unsynced_changes is already true by the time '
      '_repository.save() is called for a local edit — closing the window '
      'where a concurrent cloud-sync realtime update could see `state` '
      'already reflecting this edit but the unsynced flag still false, and '
      'wrongly treat overwriting it as safe', () async {
    bool? observedFlagWhenSaveStarted;

    final repository = _RecordingLedgerRepository(({
      required hasUnsyncedChangesWhenSaveStarts,
    }) {
      observedFlagWhenSaveStarted = hasUnsyncedChangesWhenSaveStarts;
    });

    final controller = LedgerController(
      repository,
      setLoadState: (_) {},
      initialState: emptyLedgerState(),
    );
    addTearDown(controller.dispose);

    // Let the constructor's own unawaited `_loadPersistedLedger()` (which
    // sets `state` directly, bypassing `_commit()`/the unsynced flag
    // entirely, since there's nothing to restore from this fake
    // repository's `load()` returning null) settle first so it can't be
    // mistaken for the edit below.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // Before the edit: no unsynced changes recorded yet.
    final prefsBefore = await SharedPreferences.getInstance();
    expect(prefsBefore.getBool('has_unsynced_changes'), isNot(isTrue));

    await controller.setHomeWidgetPreferences(order: const ['accountGrid']);

    expect(
      observedFlagWhenSaveStarted,
      isTrue,
      reason:
          '_commit() must persist has_unsynced_changes=true before '
          'calling _repository.save() (and before mutating `state`), not '
          'after — otherwise a concurrent cloud-sync listener reading the '
          'flag in that window would wrongly see "no unsynced changes" '
          'against an already-edited in-memory ledger.',
    );
  });
}
