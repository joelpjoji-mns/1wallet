import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:g1455/g1455.dart' as g1455;
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../auth/app_mode.dart';
import '../data/ledger_defaults.dart';
import '../data/ledger_models.dart';
import '../data/ledger_providers.dart';
import '../routing/app_router.dart';
import '../startup/startup_state.dart';
import '../theme/theme_controller.dart';
import 'one_wallet_app.dart';
import 'prototype_sample.dart';

/// Separate web-only entrypoint. Never initializes Firebase or reads a real wallet.
Future<void> main() async {
  if (!kIsWeb) throw UnsupportedError('Screen Studio is a web-only runtime.');
  WidgetsFlutterBinding.ensureInitialized();
  final empty = Uri.base.queryParameters['state'] == 'empty';
  SharedPreferencesStorePlatform.instance =
      InMemorySharedPreferencesStore.empty();
  FlutterSecureStoragePlatform.instance = PrototypeSecureStorage();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(AppModeStore.storageKey, AppMode.offline.name);
  await prefs.setString(AppModeStore.localDisplayNameKey, 'Demo wallet');
  await prefs.setString(
    'one_wallet_flutter.theme.preference.v1',
    Uri.base.queryParameters['theme'] == 'light' ? 'light' : 'amoled',
  );
  LedgerProvidersConfig.disableAutoBackup = true;
  await Future.wait([
    initializeDateFormatting(),
    LiquidGlassWidgets.initialize(),
    g1455.GlassHost.precache(),
  ]);
  final router = createPrototypeRouter();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ledgerRepositoryProvider.overrideWithValue(
          PrototypeLedgerRepository(
            empty ? emptyLedgerState() : prototypeSample(DateTime.now()),
          ),
        ),
        startupStateProvider.overrideWithValue(
          const StartupState.ready(destination: StartupDestination.home),
        ),
        appRouterProvider.overrideWith((ref) {
          ref.onDispose(router.dispose);
          return router;
        }),
      ],
      child: const OneWalletApp(),
    ),
  );
  FlutterNativeSplash.remove();
}

GoRouter createPrototypeRouter({String? initialLocation}) {
  // Reuse the production route builders and aliases without startup redirects,
  // so the design workspace can inspect gated screens as well.
  final source = ProviderContainer(
    overrides: [
      startupStateProvider.overrideWithValue(
        const StartupState.ready(destination: StartupDestination.home),
      ),
    ],
  );
  final routes = source.read(appRouterProvider).configuration.routes;
  source.dispose();
  return GoRouter(
    routes: routes,
    initialLocation: initialLocation,
    errorBuilder: (context, state) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: Text('Prototype route not found: ${state.uri.path}'),
      ),
    ),
  );
}

class PrototypeLedgerRepository extends LedgerRepository {
  PrototypeLedgerRepository(this.saved);

  LedgerState? saved;

  @override
  LedgerState? loadSync(SharedPreferences preferences) => saved;

  @override
  Future<LedgerState?> load() async => saved;

  @override
  Future<void> save(LedgerState state) async => saved = state;

  @override
  Future<void> clear() async => saved = null;
}

class PrototypeSecureStorage extends FlutterSecureStoragePlatform {
  final _values = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => _values[key];

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _values[key] = value;
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => _values.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    _values.clear();
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => Map.of(_values);
}
