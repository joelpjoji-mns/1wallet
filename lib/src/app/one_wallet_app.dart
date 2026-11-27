import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g1455/g1455.dart' as g1455;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:dynamic_color/dynamic_color.dart';

import '../routing/app_router.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

import '../cloud_sync/cloud_sync_controller.dart';
import '../data/ledger_providers.dart';
import '../features/capture/sms_inbox_reader.dart';
import '../services/notification_service.dart';
import '../services/native_widget_sync_service.dart';
import '../startup/startup_state.dart';
import '../security/app_lock.dart';
import '../features/updates/play_store_update_service.dart';
import '../features/updates/play_update_sheet.dart';

class OneWalletApp extends ConsumerStatefulWidget {
  const OneWalletApp({super.key});

  @override
  ConsumerState<OneWalletApp> createState() => _OneWalletAppState();
}

class _OneWalletAppState extends ConsumerState<OneWalletApp> {
  late final AppLifecycleListener _listener;
  late final void Function() _cancelSmsRoute;
  late final void Function(String) _notificationRouteHandler;

  String? _pendingSmsRoute;
  String? _pendingNotificationRoute;
  bool _processingSpooledForRoute = false;

  @override
  void initState() {
    super.initState();
    _notificationRouteHandler = (route) {
      if (mounted) {
        _pendingNotificationRoute = route;
        _tryPushPendingRoute();
      }
    };
    NotificationService.onNotificationTapped = _notificationRouteHandler;
    NotificationService.checkPendingNotificationLaunch((route) {
      if (mounted) {
        _pendingNotificationRoute = route;
        _tryPushPendingRoute();
      }
    });

    _listener = AppLifecycleListener(onStateChange: _onStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final route = await getInitialSmsRoute();
      if (!mounted) return;
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
      await ref
          .read(cloudSyncControllerProvider.notifier)
          .checkAndTriggerSync();
      if (mounted &&
          ref.read(startupStateProvider).destination ==
              StartupDestination.home) {
        NativeWidgetSyncService.syncWidgets(ref.read(ledgerProvider));
      }
    });
    _cancelSmsRoute = listenForSmsRoute((route) {
      if (mounted) {
        _pendingSmsRoute = route;
        _tryPushPendingRoute();
      }
    });
  }

  void _tryPushPendingRoute() {
    if (!mounted) return;
    final startup = ref.read(startupStateProvider);
    if (startup.isPending || startup.destination != StartupDestination.home) {
      return;
    }

    final route = _pendingNotificationRoute ?? _pendingSmsRoute;
    if (route != null) {
      _pendingNotificationRoute = null;
      _pendingSmsRoute = null;
      final isCaptureRoute =
          route == '/review' ||
          route == '/auto-capture' ||
          route.startsWith('/import-sms') ||
          route.startsWith('/capture');
      if (isCaptureRoute) {
        // Process any spooled notifications/SMS first so the review queue is
        // populated *before* we navigate to it.
        _processPendingSpoolThenPush(route);
      } else {
        _pushRoute(route);
      }
    }
  }

  Future<void> _pushRoute(String route) async {
    if (!mounted) return;
    final startup = ref.read(startupStateProvider);
    if (startup.isPending || startup.destination != StartupDestination.home) {
      _pendingNotificationRoute = route;
      return;
    }
    final router = ref.read(appRouterProvider);
    final currentLoc = router.routerDelegate.currentConfiguration.uri.path;
    if (currentLoc != route) {
      await router.push(route);
    }
  }

  Future<void> _processPendingSpoolThenPush(String route) async {
    if (_processingSpooledForRoute) {
      await _pushRoute(route);
      return;
    }
    _processingSpooledForRoute = true;
    try {
      final ledger = ref.read(ledgerProvider.notifier);
      await ledger.processSpooledSms();
      await ledger.processSpooledNotifications();
    } catch (_) {
      // Ignore spool errors so route navigation is never dropped
    } finally {
      _processingSpooledForRoute = false;
    }
    await _pushRoute(route);
  }

  @override
  void dispose() {
    _cancelSmsRoute();
    if (identical(
      NotificationService.onNotificationTapped,
      _notificationRouteHandler,
    )) {
      NotificationService.onNotificationTapped = null;
    }
    _listener.dispose();
    super.dispose();
  }

  void _onStateChanged(AppLifecycleState state) {
    if (ref.read(ledgerProvider.notifier).isDeletionPending) return;
    if (state == AppLifecycleState.resumed) {
      ref.read(ledgerProvider.notifier).resumeSpoolPolling();
      // If there's a pending navigation route (e.g. tapping the auto-capture
      // notification), _processPendingSpoolThenPush already handles spool
      // processing + navigation atomically. Only fire background processing
      // here when there is no pending route, to avoid double-processing.
      if (_pendingSmsRoute == null && _pendingNotificationRoute == null) {
        ref.read(ledgerProvider.notifier).processSpooledSms();
        ref.read(ledgerProvider.notifier).processSpooledNotifications();
      }
      ref
          .read(cloudSyncControllerProvider.notifier)
          .checkAndTriggerSync(fromResume: true);
      // Coming back to a backgrounded app on a new day counts as an open.
      final startup = ref.read(startupStateProvider);
      if (!startup.isPending &&
          startup.destination == StartupDestination.home) {
        ref.read(playStoreUpdateProvider.notifier).checkOnAppOpen();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      ref.read(ledgerProvider.notifier).pauseSpoolPolling();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeControllerProvider);
    final activeTheme = themeState.themeMode == ThemeMode.light
        ? AppTheme.light(
            customAccentColor: themeState.customAccentColor,
            colorIntensity: themeState.colorIntensity,
            useSystemColor: themeState.useSystemColor,
            surfaceContrast: themeState.surfaceContrast,
            outlineThickness: themeState.outlineThickness,
            outlineOpacity: themeState.outlineOpacity,
            islandOutlineThickness: themeState.islandOutlineThickness,
            islandOutlineOpacity: themeState.islandOutlineOpacity,
            fabOutlineThickness: themeState.fabOutlineThickness,
            fabOutlineOpacity: themeState.fabOutlineOpacity,
          )
        : AppTheme.amoled(
            customAccentColor: themeState.customAccentColor,
            colorIntensity: themeState.colorIntensity,
            useSystemColor: themeState.useSystemColor,
            surfaceContrast: themeState.surfaceContrast,
            outlineThickness: themeState.outlineThickness,
            outlineOpacity: themeState.outlineOpacity,
            islandOutlineThickness: themeState.islandOutlineThickness,
            islandOutlineOpacity: themeState.islandOutlineOpacity,
            fabOutlineThickness: themeState.fabOutlineThickness,
            fabOutlineOpacity: themeState.fabOutlineOpacity,
          );

    ref.listen(startupStateProvider, (prev, next) {
      if (!next.isPending && next.destination == StartupDestination.home) {
        _tryPushPendingRoute();
        NativeWidgetSyncService.syncWidgets(
          ref.read(ledgerProvider),
          theme: activeTheme,
        );
        ref.read(playStoreUpdateProvider.notifier).checkOnAppOpen();
      }
    });

    ref.listen(ledgerProvider, (prev, next) {
      NativeWidgetSyncService.syncWidgets(next, theme: activeTheme);
    });

    ref.listen(themeControllerProvider, (prev, next) {
      final newTheme = next.themeMode == ThemeMode.light
          ? AppTheme.light(
              customAccentColor: next.customAccentColor,
              colorIntensity: next.colorIntensity,
              useSystemColor: next.useSystemColor,
              surfaceContrast: next.surfaceContrast,
              outlineThickness: next.outlineThickness,
              outlineOpacity: next.outlineOpacity,
              islandOutlineThickness: next.islandOutlineThickness,
              islandOutlineOpacity: next.islandOutlineOpacity,
              fabOutlineThickness: next.fabOutlineThickness,
              fabOutlineOpacity: next.fabOutlineOpacity,
            )
          : AppTheme.amoled(
              customAccentColor: next.customAccentColor,
              colorIntensity: next.colorIntensity,
              useSystemColor: next.useSystemColor,
              surfaceContrast: next.surfaceContrast,
              outlineThickness: next.outlineThickness,
              outlineOpacity: next.outlineOpacity,
              islandOutlineThickness: next.islandOutlineThickness,
              islandOutlineOpacity: next.islandOutlineOpacity,
              fabOutlineThickness: next.fabOutlineThickness,
              fabOutlineOpacity: next.fabOutlineOpacity,
            );
      NativeWidgetSyncService.syncWidgets(
        ref.read(ledgerProvider),
        theme: newTheme,
      );
    });

    final router = ref.watch(appRouterProvider);
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

    final scaledContrast = themeState.surfaceContrast * 0.30;
    final darkSurfaceGrey = Color.lerp(
      const Color(0xFF000000),
      const Color(0xFF383A44),
      scaledContrast,
    )!;
    final darkGlassAlpha = (fill * 0.75 * scaledContrast.clamp(0.0, 1.5)).clamp(
      0.0,
      0.55,
    );
    final effectiveDarkGlassColor = darkSurfaceGrey.withValues(
      alpha: darkGlassAlpha,
    );

    return LiquidGlassWidgets.wrap(
      theme: GlassThemeData(
        light: GlassThemeVariant(
          settings: GlassThemeSettings(
            thickness: 8,
            blur: (blur > 0 ? blur : 10.0).clamp(4.0, 14.0),
            glassColor: const Color(0x08FFFFFF),
            visibility: 1.0,
            saturation: 1.0,
            refractiveIndex: 1.01,
            lightIntensity: 0.04,
            ambientStrength: 0.02,
            fresnelStrength: 0.05,
            edgeAbsorption: 0.02,
            chromaticAberration: 0.0,
          ),
          quality: GlassQuality.standard,
        ),
        dark: GlassThemeVariant(
          settings: GlassThemeSettings(
            thickness: 20,
            blur: blur,
            glassColor: effectiveDarkGlassColor,
            visibility: 1.0,
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
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          debugShowCheckedModeBanner: false,
          routerConfig: router,
          theme: AppTheme.light(
            systemColorScheme: themeState.useSystemColor ? lightDynamic : null,
            customAccentColor: themeState.customAccentColor,
            colorIntensity: themeState.colorIntensity,
            useSystemColor: themeState.useSystemColor,
            surfaceContrast: themeState.surfaceContrast,
            outlineThickness: themeState.outlineThickness,
            outlineOpacity: themeState.outlineOpacity,
            islandOutlineThickness: themeState.islandOutlineThickness,
            islandOutlineOpacity: themeState.islandOutlineOpacity,
            fabOutlineThickness: themeState.fabOutlineThickness,
            fabOutlineOpacity: themeState.fabOutlineOpacity,
          ),
          darkTheme: AppTheme.amoled(
            systemColorScheme: themeState.useSystemColor ? darkDynamic : null,
            customAccentColor: themeState.customAccentColor,
            colorIntensity: themeState.colorIntensity,
            useSystemColor: themeState.useSystemColor,
            surfaceContrast: themeState.surfaceContrast,
            outlineThickness: themeState.outlineThickness,
            outlineOpacity: themeState.outlineOpacity,
            islandOutlineThickness: themeState.islandOutlineThickness,
            islandOutlineOpacity: themeState.islandOutlineOpacity,
            fabOutlineThickness: themeState.fabOutlineThickness,
            fabOutlineOpacity: themeState.fabOutlineOpacity,
          ),
          themeMode: themeState.themeMode,
          builder: (context, child) {
            if (child == null) return const SizedBox.shrink();
            final isTest = WidgetsBinding.instance.runtimeType
                .toString()
                .contains('Test');
            final appLock = AppLockGate(
              child: PlayUpdatePromptHost(child: child),
            );
            final isDark =
                themeState.themeMode == ThemeMode.dark ||
                (themeState.themeMode == ThemeMode.system &&
                    (MediaQuery.maybePlatformBrightnessOf(context) ??
                            WidgetsBinding
                                .instance
                                .platformDispatcher
                                .platformBrightness) ==
                        Brightness.dark);
            if (isTest) {
              return appLock;
            }
            final glassFinish = ref.watch(glassFinishProvider);
            return g1455.GlassHost(
              key: ValueKey(
                'glass_host_${themeState.themeMode}_${themeState.preference}_${themeState.customAccentColor?.toARGB32()}_${themeState.colorIntensity}_${themeState.useSystemColor}_${themeState.surfaceContrast}_${themeState.outlineThickness}_${themeState.outlineOpacity}_${themeState.islandOutlineThickness}_${themeState.islandOutlineOpacity}_${themeState.fabOutlineThickness}_${themeState.fabOutlineOpacity}_${isDark}_${glassFinish.name}',
              ),
              content: g1455.GlassContentDeclaration.undeclared,
              finish: glassFinish,
              appearance: isDark ? Brightness.dark : Brightness.light,
              backdrop: isDark
                  ? const Color(0xFF000000)
                  : const Color(0xFFF8FAFC),
              richBackdrop: false,
              child: appLock,
            );
          },
        ),
      ),
    );
  }
}
