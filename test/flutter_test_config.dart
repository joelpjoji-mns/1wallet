import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  AppTheme.disableGoogleFonts = true;
  LedgerProvidersConfig.disableAutoBackup = true;
  await LiquidGlassWidgets.initialize(
    enablePerformanceMonitor: false,
    warmUpMode: GlassWarmUpMode.never,
  );
  await testMain();
}
