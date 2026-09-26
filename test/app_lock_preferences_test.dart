import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/security/app_lock.dart';
import 'fixtures/sample_ledger.dart';

class _FakeAuthenticator implements AppAuthenticator {
  bool supported = true;
  final List<bool> answers = [];
  int calls = 0;

  @override
  Future<bool> isDeviceSupported() async => supported;

  @override
  Future<bool> authenticate() async {
    calls++;
    return answers.isEmpty ? true : answers.removeAt(0);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'account visibility preferences default and sync through wallet codec',
    () {
      const defaults = LedgerPreferences();
      expect(defaults.showExcludedAccounts, isTrue);
      expect(defaults.showArchivedAccounts, isFalse);

      final ledger = sampleLedgerState().copyWith(
        preferences: defaults.copyWith(
          showExcludedAccounts: false,
          showArchivedAccounts: true,
        ),
      );
      final restored = decodeLedgerState(encodeLedgerState(ledger));
      expect(restored.preferences.showExcludedAccounts, isFalse);
      expect(restored.preferences.showArchivedAccounts, isTrue);
    },
  );

  test(
    'app lock requires confirmation before enabling and persists locally',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final auth = _FakeAuthenticator()..answers.add(false);
      final lock = AppLockController(prefs, auth);

      await lock.enable();
      expect(lock.state.enabled, isFalse);
      expect(lock.state.locked, isFalse);
      expect(prefs.getBool('one_wallet.device.app_lock.enabled.v1'), isNull);

      auth.answers.add(true);
      await lock.enable();
      expect(lock.state.enabled, isTrue);
      expect(lock.state.locked, isFalse);
      expect(prefs.getBool('one_wallet.device.app_lock.enabled.v1'), isTrue);
    },
  );

  test('unsupported device keeps app lock off with an explanation', () async {
    final prefs = await SharedPreferences.getInstance();
    final auth = _FakeAuthenticator()..supported = false;
    final lock = AppLockController(prefs, auth);

    await lock.enable();
    expect(lock.state.enabled, isFalse);
    expect(lock.state.message, contains('does not support'));
    expect(auth.calls, 0);
  });

  test(
    'cold launch stays locked after cancellation and retry unlocks',
    () async {
      SharedPreferences.setMockInitialValues({
        'one_wallet.device.app_lock.enabled.v1': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final auth = _FakeAuthenticator()..answers.addAll([false, true]);
      final lock = AppLockController(prefs, auth);

      expect(lock.state.locked, isTrue);
      await lock.unlockAtLaunch();
      expect(lock.state.locked, isTrue);
      expect(lock.state.message, contains('cancelled'));

      await lock.retryUnlock();
      expect(lock.state.locked, isFalse);
      expect(auth.calls, 2);

      await lock.unlockAtLaunch();
      expect(auth.calls, 2);
    },
  );
}
