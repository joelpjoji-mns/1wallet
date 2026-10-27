import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/auth/app_mode.dart';
import 'package:one_wallet_flutter/src/data/backup_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/utils/secure_key_store.dart';

import 'fixtures/sample_ledger.dart';
import 'offline_mode_fakes.dart';

const _cardNumber = '4111 1111 1111 1111';
final _cardContext = SecureKeyStore.fieldContext('acc-card', 'number');

Future<LedgerState> _walletWithSecret(String owner) async {
  final secret = await SecureKeyStore.encrypt(
    _cardNumber,
    userId: owner,
    context: _cardContext,
  );
  final base = sampleLedgerState();
  return base.copyWith(
    userId: owner,
    accounts: [
      for (final account in base.accounts)
        account.id == 'acc-card'
            ? account.copyWith(encryptedDetails: {'number': secret})
            : account,
    ],
  );
}

Future<LedgerController> _offlineLedger(LedgerState? seed) async {
  final ledger = LedgerController(
    MemoryLedgerRepository(seed),
    initialState: seed,
    initialUser: LedgerUserIdentity.localOwner,
  );
  addTearDown(ledger.dispose);
  await ledger.flushPendingWrites();
  return ledger;
}

Map<String, int> _amounts(LedgerState ledger) => {
  for (final tx in ledger.transactions) tx.id: tx.amount.amountMinor,
};

Future<String> _readCard(LedgerState ledger, String owner) {
  final card = ledger.accounts.firstWhere((a) => a.id == 'acc-card');
  return SecureKeyStore.decrypt(
    card.encryptedDetails!['number']!,
    userId: owner,
    context: _cardContext,
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SecureKeyStore.clear();
  });

  test('offline wallet survives export → wipe → import intact', () async {
    final ledger = await _offlineLedger(await _walletWithSecret(localOwnerId));
    final before = ledger.state;

    final backup = await ledger.exportPortableBackup('correct horse battery');
    expect(backup, contains('onewallet.encrypted.backup'));
    expect(backup, isNot(contains('4111')), reason: 'secrets stay encrypted');

    await ledger.clearLocalWallet();
    expect(ledger.state.accounts, isEmpty);
    expect(ledger.state.transactions, isEmpty);
    expect(ledger.state.userId, localOwnerId);

    await ledger.importArchive(backup, passphrase: 'correct horse battery');
    final after = ledger.state;
    expect(after.userId, localOwnerId);
    expect(
      after.accounts.map((a) => a.id).toSet(),
      before.accounts.map((a) => a.id).toSet(),
    );
    expect(_amounts(after), _amounts(before));
    expect(await _readCard(after, localOwnerId), _cardNumber);
  });

  test('a wrong passphrase leaves the offline wallet untouched', () async {
    final ledger = await _offlineLedger(await _walletWithSecret(localOwnerId));
    final backup = await ledger.exportPortableBackup('right');
    final before = _amounts(ledger.state);

    await expectLater(
      ledger.importArchive(backup, passphrase: 'wrong', force: true),
      throwsA(isA<FormatException>()),
    );
    expect(_amounts(ledger.state), before);
    expect(ledger.state.userId, localOwnerId);
  });

  test(
    'importing a Google account backup offline re-owns it to the device',
    () async {
      final accountWallet = await _walletWithSecret('google-uid-9');
      final backup = await encodePortableBackup(accountWallet, 'pass');
      final ledger = await _offlineLedger(null);

      await ledger.importArchive(backup, passphrase: 'pass');

      expect(ledger.state.userId, localOwnerId);
      expect(ledger.state.transactions, isNotEmpty);
      expect(await _readCard(ledger.state, localOwnerId), _cardNumber);
    },
  );

  test(
    'an on-device automatic backup restores into the offline wallet',
    () async {
      final wallet = await _walletWithSecret(localOwnerId);
      final deviceBackup = await encodeDeviceBackup(wallet);
      final ledger = await _offlineLedger(null);

      await ledger.importArchive(deviceBackup);

      expect(ledger.state.userId, localOwnerId);
      expect(_amounts(ledger.state), _amounts(wallet));
      expect(await _readCard(ledger.state, localOwnerId), _cardNumber);
    },
  );

  test('online accounts keep the existing import ownership rules', () async {
    final accountWallet = await _walletWithSecret('google-uid-9');
    final backup = await encodePortableBackup(accountWallet, 'pass');
    final ledger = LedgerController(
      MemoryLedgerRepository(),
      initialUser: const LedgerUserIdentity(userId: 'google-uid-1'),
      initialState: sampleLedgerState().copyWith(
        userId: 'google-uid-1',
        transactions: const [],
        accounts: const [],
      ),
    );
    addTearDown(ledger.dispose);
    await ledger.flushPendingWrites();

    await expectLater(
      ledger.importArchive(backup, passphrase: 'pass'),
      throwsA(predicate((error) => '$error'.contains('different account'))),
    );
    expect(ledger.state.userId, 'google-uid-1');
  });
}
