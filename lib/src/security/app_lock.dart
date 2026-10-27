import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/theme_controller.dart';

abstract interface class AppAuthenticator {
  Future<bool> isDeviceSupported();
  Future<bool> authenticate();
}

class LocalAppAuthenticator implements AppAuthenticator {
  LocalAppAuthenticator([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();
  final LocalAuthentication _auth;

  @override
  Future<bool> isDeviceSupported() => _auth.isDeviceSupported();

  @override
  Future<bool> authenticate() =>
      _auth.authenticate(localizedReason: 'Unlock 1Wallet');
}

final appAuthenticatorProvider = Provider<AppAuthenticator>(
  (ref) => LocalAppAuthenticator(),
);
final appLockProvider = StateNotifierProvider<AppLockController, AppLockState>(
  (ref) => AppLockController(
    ref.watch(sharedPreferencesProvider),
    ref.watch(appAuthenticatorProvider),
  ),
);

class AppLockState {
  const AppLockState({
    required this.enabled,
    this.locked = false,
    this.busy = false,
    this.message,
  });
  final bool enabled;
  final bool locked;
  final bool busy;
  final String? message;
  AppLockState copyWith({
    bool? enabled,
    bool? locked,
    bool? busy,
    String? message,
    bool clearMessage = false,
  }) => AppLockState(
    enabled: enabled ?? this.enabled,
    locked: locked ?? this.locked,
    busy: busy ?? this.busy,
    message: clearMessage ? null : message ?? this.message,
  );
}

class AppLockController extends StateNotifier<AppLockState> {
  AppLockController(this._preferences, this._auth)
    : super(
        AppLockState(
          enabled: _preferences.getBool(_key) ?? false,
          locked: _preferences.getBool(_key) ?? false,
        ),
      );
  static const _key = 'one_wallet.device.app_lock.enabled.v1';
  final SharedPreferences _preferences;
  final AppAuthenticator _auth;
  bool _launchAttempted = false;
  int _authenticationGeneration = 0;
  int? _activeAttempt;
  bool _foreground = true;

  void lockForBackground() {
    if (!mounted) return;
    _foreground = false;
    _authenticationGeneration++;
    _launchAttempted = false;
    if (state.enabled) state = state.copyWith(locked: true, clearMessage: true);
  }

  Future<void> resume() async {
    if (!mounted) return;
    _foreground = true;
    await unlockAtLaunch();
  }

  void _finishAttempt(int attempt) {
    if (!mounted || _activeAttempt != attempt) return;
    _activeAttempt = null;
    if (state.busy) state = state.copyWith(busy: false);
    if (attempt != _authenticationGeneration &&
        _foreground &&
        state.enabled &&
        state.locked) {
      _launchAttempted = false;
      unawaited(unlockAtLaunch());
    }
  }

  Future<void> enable() async {
    if (!mounted || state.busy) return;
    final generation = ++_authenticationGeneration;
    _activeAttempt = generation;
    state = state.copyWith(busy: true, clearMessage: true);
    try {
      if (!await _auth.isDeviceSupported()) {
        if (!mounted || generation != _authenticationGeneration) return;
        state = state.copyWith(
          busy: false,
          message: 'This device does not support biometrics or a screen lock.',
        );
        return;
      }
      final ok = await _auth.authenticate();
      if (!mounted || generation != _authenticationGeneration) return;
      if (!ok) {
        state = state.copyWith(
          busy: false,
          message: 'Authentication was cancelled. App lock remains off.',
        );
        return;
      }
      if (!await _preferences.setBool(_key, true)) {
        throw StateError('Could not persist app lock.');
      }
      if (!mounted || generation != _authenticationGeneration) return;
      state = state.copyWith(
        enabled: true,
        locked: false,
        busy: false,
        clearMessage: true,
      );
    } catch (_) {
      if (!mounted || generation != _authenticationGeneration) return;
      state = state.copyWith(
        busy: false,
        message: 'Could not enable app lock on this device.',
      );
    } finally {
      _finishAttempt(generation);
    }
  }

  Future<void> disable() async {
    if (!mounted) return;
    final generation = ++_authenticationGeneration;
    _activeAttempt = null;
    state = state.copyWith(busy: false);
    if (!await _preferences.setBool(_key, false)) {
      throw StateError('Could not disable app lock.');
    }
    if (!mounted || generation != _authenticationGeneration) return;
    _launchAttempted = false;
    state = state.copyWith(
      enabled: false,
      locked: false,
      busy: false,
      clearMessage: true,
    );
  }

  Future<void> unlockAtLaunch() async {
    if (!mounted || !_foreground) return;
    if (_launchAttempted || !state.enabled || !state.locked || state.busy) {
      return;
    }
    _launchAttempted = true;
    final generation = _authenticationGeneration;
    _activeAttempt = generation;
    state = state.copyWith(busy: true, clearMessage: true);
    try {
      final ok = await _auth.authenticate();
      if (!mounted || generation != _authenticationGeneration) return;
      state = state.copyWith(
        locked: !ok,
        busy: false,
        message: ok ? null : 'Unlock was cancelled. Try again to open 1Wallet.',
        clearMessage: ok,
      );
    } catch (_) {
      if (!mounted || generation != _authenticationGeneration) return;
      state = state.copyWith(
        busy: false,
        message: 'Authentication failed. Try again to open 1Wallet.',
      );
    } finally {
      _finishAttempt(generation);
    }
  }

  Future<void> retryUnlock() async {
    _launchAttempted = false;
    await unlockAtLaunch();
  }
}

class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(appLockProvider.notifier).unlockAtLaunch();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (!mounted) return;
    final controller = ref.read(appLockProvider.notifier);
    if (lifecycle == AppLifecycleState.resumed) {
      setState(() => _obscured = false);
      controller.resume();
    } else {
      setState(() => _obscured = true);
      if (lifecycle == AppLifecycleState.paused ||
          lifecycle == AppLifecycleState.hidden) {
        controller.lockForBackground();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    if (!lock.locked && !(_obscured && lock.enabled)) return widget.child;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 48),
              const SizedBox(height: 16),
              Text(
                '1Wallet is locked',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (lock.message != null) ...[
                const SizedBox(height: 12),
                Text(lock.message!, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: lock.busy
                    ? null
                    : () => ref.read(appLockProvider.notifier).retryUnlock(),
                icon: lock.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fingerprint),
                label: Text(lock.busy ? 'Authenticating…' : 'Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
