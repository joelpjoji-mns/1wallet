import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/firebase_env.dart';
import '../../data/ledger_providers.dart';

class DeletionOperation {
  const DeletionOperation({
    required this.owner,
    required this.receipt,
    this.remoteConfirmed = false,
  });
  final LedgerUserIdentity owner;
  final String receipt;
  final bool remoteConfirmed;
  static const _key = 'onewallet.deletion.receipt.v1';
  static const _storage = FlutterSecureStorage();

  static DeletionOperation create(LedgerUserIdentity owner) {
    final random = Random.secure();
    return DeletionOperation(
      owner: owner,
      receipt: base64UrlEncode(
        List.generate(32, (_) => random.nextInt(256)),
      ).replaceAll('=', ''),
    );
  }

  Future<void> persist() => _storage.write(
    key: _key,
    value: jsonEncode({
      'uid': owner.userId,
      'email': owner.email,
      'name': owner.displayName,
      'receipt': receipt,
      'remoteConfirmed': remoteConfirmed,
    }),
  );
  static Future<DeletionOperation?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    final data = jsonDecode(raw);
    if (data is! Map || data['uid'] is! String || data['receipt'] is! String) {
      throw const FormatException('The deletion recovery receipt is invalid.');
    }
    return DeletionOperation(
      owner: LedgerUserIdentity(
        userId: data['uid'] as String,
        email: data['email'] as String?,
        displayName: data['name'] as String?,
      ),
      receipt: data['receipt'] as String,
      remoteConfirmed: data['remoteConfirmed'] == true,
    );
  }

  static Future<void> clear() => _storage.delete(key: _key);
}

abstract interface class AccountDeletionApi {
  Future<void> request(String receipt, String idToken);
  Future<bool> isRemoteComplete(String receipt);
}

final accountDeletionApiProvider = Provider<AccountDeletionApi>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  ref.onDispose(() => dio.close());
  return HttpAccountDeletionApi(dio);
});

class HttpAccountDeletionApi implements AccountDeletionApi {
  HttpAccountDeletionApi(this._dio) {
    _endpoint('requestAccountDeletion');
  }
  final Dio _dio;
  Uri _endpoint(String name) {
    final configured = FirebaseEnv.accountDeletionBaseUrl;
    if (configured == null) {
      throw StateError(
        'The account deletion backend is not configured. No data was deleted.',
      );
    }
    final uri = Uri.parse(configured);
    if (!uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError(
        'The deletion endpoint must be a host URL without credentials, query, or fragment.',
      );
    }
    if (uri.scheme != 'https' &&
        !(kDebugMode &&
            FirebaseEnv.useFirebaseEmulator &&
            uri.scheme == 'http')) {
      throw StateError('The deletion endpoint must use HTTPS.');
    }
    return Uri.parse('${configured.replaceFirst(RegExp(r'/+$'), '')}/$name');
  }

  @override
  Future<void> request(String receipt, String idToken) async {
    await _dio.postUri<Object?>(
      _endpoint('requestAccountDeletion'),
      data: {'receipt': receipt},
      options: Options(headers: {'Authorization': 'Bearer $idToken'}),
    );
  }

  @override
  Future<bool> isRemoteComplete(String receipt) async {
    final response = await _dio.postUri<Object?>(
      _endpoint('accountDeletionStatus'),
      data: {'receipt': receipt},
    );
    final data = response.data;
    if (data is! Map ||
        data['status'] is! String ||
        data['remoteComplete'] is! bool ||
        !{
          'queued',
          'firestore',
          'auth',
          'failed',
          'complete',
        }.contains(data['status']) ||
        (data['remoteComplete'] == true) != (data['status'] == 'complete')) {
      throw const FormatException('Invalid deletion status response.');
    }
    if (data['status'] == 'failed') {
      throw StateError(
        'Remote deletion needs retry. Your operation receipt was retained.',
      );
    }
    return data['remoteComplete'] == true;
  }
}
