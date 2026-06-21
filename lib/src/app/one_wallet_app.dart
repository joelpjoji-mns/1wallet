import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dynamic_color/dynamic_color.dart';

import '../routing/app_router.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

import '../data/ledger_providers.dart';
import '../features/capture/sms_inbox_reader.dart';
import '../startup/startup_state.dart';

class OneWalletApp extends ConsumerStatefulWidget {
  const OneWalletApp({super.key});

  @override
  ConsumerState<OneWalletApp> createState() => _OneWalletAppState();
}

class _OneWalletAppState extends ConsumerState<OneWalletApp> {
  late final AppLifecycleListener _listener;

  String? _pendingSmsRoute;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onStateChange: _onStateChanged,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.read(ledgerProvider.notifier).processSpooledSms();
      final route = await getInitialSmsRoute();
      if (route != null && mounted) {
        _pendingSmsRoute = route;
        _tryPushPendingRoute();
      }
    });
    listenForSmsRoute((route) {
      if (mounted) {
        _pendingSmsRoute = route;
        _tryPushPendingRoute();
      }
    });
  }

  void _tryPushPendingRoute() {
    if (_pendingSmsRoute == null || !mounted) return;
    final startup = ref.read(startupStateProvider);
    if (!startup.isPending && startup.destination == StartupDestination.home) {
      ref.read(appRouterProvider).push(_pendingSmsRoute!);
      _pendingSmsRoute = null;
    }
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  void _onStateChanged(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(ledgerProvider.notifier).processSpooledSms();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(startupStateProvider, (prev, next) {
      if (!next.isPending && next.destination == StartupDestination.home) {
        _tryPushPendingRoute();
      }
    });

    final router = ref.watch(appRouterProvider);
    final themeState = ref.watch(themeControllerProvider);

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final useSystemAccent = themeState.accentColor == null;
        return MaterialApp.router(
          title: '1Wallet',
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          theme: AppTheme.light(
            accentColor: themeState.accentColor,
            systemColorScheme: useSystemAccent ? lightDynamic : null,
          ),
          darkTheme: themeState.preference == AppThemePreference.amoled
              ? AppTheme.amoled(
                  accentColor: themeState.accentColor,
                  systemColorScheme: useSystemAccent ? darkDynamic : null,
                )
              : AppTheme.dark(
                  accentColor: themeState.accentColor,
                  systemColorScheme: useSystemAccent ? darkDynamic : null,
                ),
          themeMode: themeState.themeMode,
        );
      },
    );
  }
}
