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
    _listener = AppLifecycleListener(onStateChange: _onStateChanged);
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
          builder: (context, child) {
            if (child == null) return const SizedBox.shrink();
            // On wide screens (web PWA / tablets / desktop) keep the app at a
            // comfortable phone-like width, centered, rather than stretching
            // controls edge-to-edge. Phones (<=600px) are unaffected.
            final media = MediaQuery.of(context);
            if (media.size.width <= 600) return child;
            // Cap the reported size too, so MediaQuery-based responsive logic
            // (chart widths, isDesktop checks, etc.) matches the real 600px
            // render box and never overflows the frame.
            final capped = media.copyWith(
              size: Size(600, media.size.height),
            );
            return ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Center(
                child: ClipRect(
                  child: SizedBox(
                    width: 600,
                    child: MediaQuery(data: capped, child: child),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
