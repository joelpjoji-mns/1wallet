import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:one_wallet_flutter/src/data/ledger_providers.dart';
import 'package:one_wallet_flutter/src/features/capture/capture_queue.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  LedgerProvidersConfig.disableAutoBackup = true;
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});
  CaptureQueue.client = MemoryCaptureQueue();
  await LiquidGlassWidgets.initialize(
    enablePerformanceMonitor: false,
    warmUpMode: GlassWarmUpMode.never,
  );
  await testMain();
}
