// Regression test: a failed device-key read/create must not be cached
// forever. `SecureKeyStore._getOrCreateKey()` memoizes the read-or-create
// operation as a shared `Future` so concurrent callers don't race (see
// secure_key_store_concurrency_test.dart) — but if that memoized `Future`
// completed with an error and stayed cached, every subsequent call would
// keep rethrowing the same stale failure even after the underlying storage
// recovered. The fix clears the cached future on error so the next call
// retries from scratch.
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/utils/secure_key_store.dart';

/// Wraps [TestFlutterSecureStoragePlatform] so the first N `read()` calls
/// throw, to simulate a transient secure-storage failure.
class _FlakyPlatform extends FlutterSecureStoragePlatform {
  _FlakyPlatform(this._inner, {this.failReadsRemaining = 0});

  final TestFlutterSecureStoragePlatform _inner;
  int failReadsRemaining;

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    if (failReadsRemaining > 0) {
      failReadsRemaining--;
      throw StateError('simulated secure storage failure');
    }
    return _inner.read(key: key, options: options);
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) => _inner.write(key: key, value: value, options: options);

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) => _inner.containsKey(key: key, options: options);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) => _inner.delete(key: key, options: options);

  @override
  Future<void> deleteAll({required Map<String, String> options}) =>
      _inner.deleteAll(options: options);

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) => _inner.readAll(options: options);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a failed key read/create is not cached, so a later call can retry', () async {
    final inner = TestFlutterSecureStoragePlatform(<String, String>{});
    final flaky = _FlakyPlatform(inner, failReadsRemaining: 1);
    FlutterSecureStoragePlatform.instance = flaky;

    await expectLater(
      () => SecureKeyStore.encrypt('will-fail'),
      throwsA(isA<StateError>()),
    );

    // The next call should succeed (retry), not rethrow a cached failure.
    final cipher = await SecureKeyStore.encrypt('will-succeed');
    expect(await SecureKeyStore.decrypt(cipher), 'will-succeed');
  });
}
