import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../routing/app_router.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

class OneWalletApp extends ConsumerWidget {
  const OneWalletApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeState = ref.watch(themeControllerProvider);

    return MaterialApp.router(
      title: '1Wallet',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light(accentColor: themeState.accentColor),
      darkTheme: themeState.preference == AppThemePreference.amoled
          ? AppTheme.amoled(accentColor: themeState.accentColor)
          : AppTheme.dark(accentColor: themeState.accentColor),
      themeMode: themeState.themeMode,
    );
  }
}
