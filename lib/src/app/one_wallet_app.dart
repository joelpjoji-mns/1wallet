import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dynamic_color/dynamic_color.dart';

import '../routing/app_router.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

import '../data/ledger_providers.dart';

class OneWalletApp extends ConsumerStatefulWidget {
  const OneWalletApp({super.key});

  @override
  ConsumerState<OneWalletApp> createState() => _OneWalletAppState();
}

class _OneWalletAppState extends ConsumerState<OneWalletApp> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onStateChange: _onStateChanged,
    );
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
