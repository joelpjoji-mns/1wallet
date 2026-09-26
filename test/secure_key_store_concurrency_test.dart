// Regression tests for SecureKeyStore's device-key initialization.
//
// Bug: `_getOrCreateKey()` used to `read()` the stored key, and if absent,
// generate+`write()` a brand new random key with no guard against concurrent
// callers. Two callers racing before either write completed would each
// generate a *different* key and both believe they succeeded; whichever
// write landed last silently became the only key left in storage, leaving
// data encrypted under the other (now-lost) key permanently undecryptable.
//
// The fix memoizes the read-or-create operation behind a single shared
// `Future`, so every concurrent caller awaits the same key resolution.
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/utils/secure_key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'concurrent encrypt calls share one device key instead of racing to '
    'create two',
    () async {
      FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
        <String, String>{},
      );

      // Fire both encryptions "simultaneously" (before either has resolved
      // its read-or-create-key step) to reproduce the race window.
      final results = await Future.wait([
        SecureKeyStore.encrypt('first-secret'),
        SecureKeyStore.encrypt('second-secret'),
      ]);

      // Both values must decrypt correctly under whatever single key ended
      // up persisted — if the two calls had raced to independently create
      // different keys, only one ciphertext (at most) would still decrypt.
      final decrypted = await Future.wait(
        results.map(SecureKeyStore.decrypt),
      );
      expect(decrypted, ['first-secret', 'second-secret']);
    },
  );
}
