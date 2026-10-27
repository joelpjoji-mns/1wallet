import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/theme_controller.dart';

/// Device-scoped choice of how 1Wallet stores the wallet.
///
/// [online] is the default (and the only mode that existed before offline
/// mode shipped), so a device without a stored value keeps the
/// Google-sign-in + cloud-sync behaviour it always had.
enum AppMode { online, offline }

/// Owner id used for wallets that live only on this device. Reuses the
/// long-standing ledger sentinel so codecs, backups and ownership checks keep
/// working unchanged.
const localOwnerId = 'local-user';

class AppModeStore {
  AppModeStore([this._prefs]);

  final SharedPreferences? _prefs;

  static const storageKey = 'one_wallet.app_mode.v1';
  static const localDisplayNameKey = 'one_wallet.app_mode.local_name.v1';

  AppMode get mode {
    final raw = _prefs?.getString(storageKey);
    return raw == AppMode.offline.name ? AppMode.offline : AppMode.online;
  }

  String? get localDisplayName {
    final value = _prefs?.getString(localDisplayNameKey)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> setMode(AppMode mode) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    if (!await prefs.setString(storageKey, mode.name)) {
      throw StateError('Could not save the wallet storage mode.');
    }
  }

  Future<void> setLocalDisplayName(String? name) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final trimmed = name?.trim() ?? '';
    final ok = trimmed.isEmpty
        ? await prefs.remove(localDisplayNameKey)
        : await prefs.setString(localDisplayNameKey, trimmed);
    if (!ok) throw StateError('Could not save the wallet name.');
  }
}

final appModeStoreProvider = Provider<AppModeStore>((ref) {
  SharedPreferences? prefs;
  try {
    prefs = ref.watch(sharedPreferencesProvider);
  } catch (_) {}
  return AppModeStore(prefs);
});
