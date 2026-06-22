import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AppTheme.disableGoogleFonts = true;
  LedgerProvidersConfig.disableAutoBackup = true;
  await testMain();
}
