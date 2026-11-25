import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_providers.dart';

import 'offline_mode_fakes.dart';

/// A backup Android scoped storage reports as present but refuses to delete
/// (left behind by a previous install of the app).
class _ForeignFile implements File {
  _ForeignFile(this.path);

  @override
  final String path;

  @override
  Future<bool> exists() async => true;

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async =>
      throw PathNotFoundException(
        path,
        const OSError('No such file or directory', 2),
        'Cannot delete file',
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'offline auto-backup purge skips files it can see but cannot delete',
    () async {
      SharedPreferences.setMockInitialValues({});
      final ledger = LedgerController(
        MemoryLedgerRepository(),
        initialUser: LedgerUserIdentity.localOwner,
      );
      addTearDown(ledger.dispose);

      await IOOverrides.runZoned(
        () => expectLater(
          ledger.deleteAllAutoBackupFiles(
            searchDirectoriesOverride: [
              '/storage/emulated/0/Documents/1Wallet',
            ],
          ),
          completes,
        ),
        createFile: _ForeignFile.new,
      );
    },
  );
}
