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
  Future<bool> authenticate() => _auth.authenticate(
    localizedReason: 'Unlock 1Wallet',
    biometricOnly: false,
  );
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

  Future<void> enable() async {
    state = state.copyWith(busy: true, clearMessage: true);
    try {
      if (!await _auth.isDeviceSupported()) {
        state = state.copyWith(
          busy: false,
          message: 'This device does not support biometrics or a screen lock.',
        );
        return;
      }
      final ok = await _auth.authenticate();
      if (!ok) {
        state = state.copyWith(
          busy: false,
          message: 'Authentication was cancelled. App lock remains off.',
        );
        return;
      }
      await _preferences.setBool(_key, true);
      state = state.copyWith(
        enabled: true,
        locked: false,
        busy: false,
        clearMessage: true,
      );
    } catch (_) {
      state = state.copyWith(
        busy: false,
        message: 'Could not enable app lock on this device.',
      );
    }
  }

  Future<void> disable() async {
    await _preferences.setBool(_key, false);
    state = state.copyWith(
      enabled: false,
      locked: false,
      busy: false,
      clearMessage: true,
    );
  }

  Future<void> unlockAtLaunch() async {
    if (_launchAttempted || !state.enabled || !state.locked || state.busy) {
      return;
    }
    _launchAttempted = true;
    state = state.copyWith(busy: true, clearMessage: true);
    try {
      final ok = await _auth.authenticate();
      state = state.copyWith(
        locked: !ok,
        busy: false,
        message: ok ? null : 'Unlock was cancelled. Try again to open 1Wallet.',
        clearMessage: ok,
      );
    } catch (_) {
      state = state.copyWith(
        busy: false,
        message: 'Authentication failed. Try again to open 1Wallet.',
      );
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

class _AppLockGateState extends ConsumerState<AppLockGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(appLockProvider.notifier).unlockAtLaunch(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    if (!lock.locked) return widget.child;
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
