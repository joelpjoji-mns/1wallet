import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:dynamic_color/dynamic_color.dart';

import '../routing/app_router.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

import '../cloud_sync/cloud_sync_controller.dart';
import '../data/ledger_providers.dart';
import '../features/capture/sms_inbox_reader.dart';
import '../services/notification_service.dart';
import '../startup/startup_state.dart';
import '../security/app_lock.dart';

class OneWalletApp extends ConsumerStatefulWidget {
  const OneWalletApp({super.key});

  @override
  ConsumerState<OneWalletApp> createState() => _OneWalletAppState();
}

class _OneWalletAppState extends ConsumerState<OneWalletApp> {
  late final AppLifecycleListener _listener;

  String? _pendingSmsRoute;
  String? _pendingNotificationRoute;
  bool _processingSpooledForRoute = false;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onStateChange: _onStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      ref.read(ledgerProvider.notifier).processSpooledSms();
      ref.read(ledgerProvider.notifier).processSpooledNotifications();
      ref.read(cloudSyncControllerProvider.notifier).checkAndTriggerSync();
      final route = await getInitialSmsRoute();
      if (route != null && mounted) {
        _pendingSmsRoute = route;
        _tryPushPendingRoute();
      }
      NotificationService.checkPendingNotificationLaunch((route) {
        if (mounted) {
          _pendingNotificationRoute = route;
          _tryPushPendingRoute();
        }
      });
    });
    listenForSmsRoute((route) {
      if (mounted) {
        _pendingSmsRoute = route;
        _tryPushPendingRoute();
      }
    });
    NotificationService.onNotificationTapped = (route) {
      if (mounted) {
        _pendingNotificationRoute = route;
        _tryPushPendingRoute();
      }
    };
  }

  void _tryPushPendingRoute() {
    if (!mounted) return;
    final startup = ref.read(startupStateProvider);
    if (startup.isPending || startup.destination != StartupDestination.home) {
      return;
    }

    if (_pendingNotificationRoute != null) {
      final route = _pendingNotificationRoute!;
      _pendingNotificationRoute = null;
      ref.read(appRouterProvider).push(route);
    }

    if (_pendingSmsRoute != null) {
      final route = _pendingSmsRoute!;
      _pendingSmsRoute = null;
      // Process any spooled notifications/SMS first so the review queue is
      // populated *before* we navigate to it. Without this await the route
      // arrives before the candidates are committed and the queue looks empty.
      _processPendingSpoolThenPush(route);
    }
  }

  Future<void> _processPendingSpoolThenPush(String route) async {
    if (_processingSpooledForRoute) return;
    _processingSpooledForRoute = true;
    try {
      await ref.read(ledgerProvider.notifier).processSpooledSms();
      await ref.read(ledgerProvider.notifier).processSpooledNotifications();
    } finally {
      _processingSpooledForRoute = false;
    }
    if (!mounted) return;
    ref.read(appRouterProvider).push(route);
  }

  @override
  void dispose() {
    NotificationService.onNotificationTapped = null;
    _listener.dispose();
    super.dispose();
  }

  void _onStateChanged(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // If there's a pending navigation route (e.g. tapping the auto-capture
      // notification), _processPendingSpoolThenPush already handles spool
      // processing + navigation atomically. Only fire background processing
      // here when there is no pending route, to avoid double-processing.
      if (_pendingSmsRoute == null) {
        ref.read(ledgerProvider.notifier).processSpooledSms();
        ref.read(ledgerProvider.notifier).processSpooledNotifications();
      }
      ref
          .read(cloudSyncControllerProvider.notifier)
          .checkAndTriggerSync(fromResume: true);
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
    final glass = ref.watch(
      ledgerProvider.select(
        (state) => (
          blur: state.preferences.glassBlurLevel,
          progressiveBlur: state.preferences.glassProgressiveBlurStrength,
          fill: state.preferences.glassBackgroundOpacity,
          visibility: state.preferences.glassSpecularOpacity,
          saturation: state.preferences.glassSpecularSaturation,
          refraction: state.preferences.glassRefractionLevel,
          interaction: state.preferences.glassInteractionStrength,
        ),
      ),
    );
    final blur = (glass.blur + glass.progressiveBlur * 8).clamp(0.0, 24.0);
    final fill = glass.fill.clamp(0.0, 0.5);
    final interaction = glass.interaction.clamp(0.0, 1.0);

    return LiquidGlassWidgets.wrap(
      theme: GlassThemeData(
        light: GlassThemeVariant(
          settings: GlassThemeSettings(
            thickness: 20,
            blur: blur,
            glassColor: Color.fromRGBO(255, 255, 255, fill),
            visibility: glass.visibility.clamp(0.15, 1.0),
            saturation: glass.saturation.clamp(0.0, 2.0),
            refractiveIndex: 1.0 + glass.refraction.clamp(0.0, 1.0) * 0.25,
            fresnelStrength: 0.4,
            ambientStrength: 0.10,
            chromaticAberration: 0.01,
          ),
          quality: GlassQuality.standard,
        ),
        dark: GlassThemeVariant(
          settings: GlassThemeSettings(
            thickness: 20,
            blur: blur,
            glassColor: Color.fromRGBO(16, 16, 16, (fill * 0.75).clamp(0.12, 0.45)),
            visibility: glass.visibility.clamp(0.15, 1.0),
            saturation: glass.saturation.clamp(0.0, 2.0),
            refractiveIndex: 1.0 + glass.refraction.clamp(0.0, 1.0) * 0.25,
            lightIntensity: 0.08,
            ambientStrength: 0.06,
            fresnelStrength: 0.30,
            edgeAbsorption: 0.14,
            chromaticAberration: 0.01,
          ),
          quality: GlassQuality.standard,
        ),
        interaction: GlassInteractionSettings(
          stretch: 0.55 * interaction,
          interactionScale: 1.0 + 0.14 * interaction,
          resistance: 0.06 - 0.035 * interaction,
        ),
      ),
      // Keep one predictable quality tier instead of runtime benchmarking
      // and repeatedly changing the glass implementation during navigation.
      adaptiveQuality: false,
      brightnessResolver: (context) {
        if (themeState.themeMode == ThemeMode.light) return Brightness.light;
        if (themeState.themeMode == ThemeMode.dark) return Brightness.dark;
        try {
          return MediaQuery.platformBrightnessOf(context);
        } catch (_) {
          return WidgetsBinding.instance.platformDispatcher.platformBrightness;
        }
      },
      child: DynamicColorBuilder(
        builder: (lightDynamic, darkDynamic) => MaterialApp.router(
          title: '1Wallet',
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          theme: AppTheme.light(systemColorScheme: lightDynamic),
          darkTheme: AppTheme.amoled(systemColorScheme: darkDynamic),
          themeMode: themeState.themeMode,
          builder: (context, child) {
            if (child == null) return const SizedBox.shrink();
            return AppLockGate(child: child);
          },
        ),
      ),
    );
  }
}
