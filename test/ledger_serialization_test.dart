import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';

class _Repository extends LedgerRepository {
  LedgerState? saved;
  @override
  Future<LedgerState?> load() async => null;
  @override
  Future<void> save(LedgerState state) async {
    saved = state;
  }

  @override
  Future<void> clear() async {
    saved = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LedgerProvidersConfig.disableAutoBackup = true;
  });
  Future<LedgerController> controller() async {
    final value = LedgerController(_Repository());
    addTearDown(value.dispose);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    return value;
  }

  test(
    'concurrent account writes survive publication and persistence',
    () async {
      final ledger = await controller();
      await Future.wait([
        ledger.upsertAccount(id: 'a', name: 'A', type: 'bank'),
        ledger.upsertAccount(id: 'b', name: 'B', type: 'bank'),
      ]);
      expect(ledger.state.accounts.map((a) => a.id), containsAll(['a', 'b']));
      expect(ledger.changeVersion, 2);
    },
  );
  test(
    'queued old-session writes are cancelled before sign-out clearing',
    () async {
      final ledger = await controller();
      final pending = ledger.upsertAccount(id: 'a', name: 'A', type: 'bank');
      final rejected = expectLater(
        pending,
        throwsA(isA<StaleLedgerSessionException>()),
      );
      await ledger.clearSessionOnSignOut();
      await rejected;
      expect(ledger.state.accounts, isEmpty);
    },
  );
  test('preference publication is dirty before listeners run', () async {
    final ledger = await controller();
    final prefs = await SharedPreferences.getInstance();
    bool? observed;
    final remove = ledger.addListener((_) {
      observed = prefs.getBool('has_unsynced_changes');
    }, fireImmediately: false);
    addTearDown(remove);
    await ledger.updatePreferences(
      ledger.state.preferences.copyWith(privacyModeEnabled: true),
    );
    expect(observed, isTrue);
    expect(ledger.changeVersion, 1);
    expect(await ledger.acknowledgeUploadedVersion(0), isFalse);
    expect(prefs.getBool('has_unsynced_changes'), isTrue);
  });

  test(
    'concurrent field reducers preserve distinct preference edits',
    () async {
      final ledger = await controller();
      await Future.wait([
        ledger.updatePreferencesWith(
          (current) => current.copyWith(locale: 'fr_FR'),
        ),
        ledger.updatePreferencesWith(
          (current) => current.copyWith(privacyModeEnabled: true),
        ),
      ]);
      expect(ledger.state.preferences.locale, 'fr_FR');
      expect(ledger.state.preferences.privacyModeEnabled, isTrue);
      expect(ledger.changeVersion, 2);
    },
  );
}
