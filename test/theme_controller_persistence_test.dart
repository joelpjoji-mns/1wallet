import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:one_wallet_flutter/src/theme/theme_controller.dart';

/// An in-memory preferences store whose writes can be made to fail on
/// demand, so we can exercise `ThemeController`'s rollback-on-persistence-
/// failure path without needing a real disk/platform-channel failure.
///
/// Writes can also be gated with [addGate] to control completion order,
/// so overlapping calls can be made to resolve out of order (an older call
/// finishing after a newer one) deterministically in a test.
class _FlakyStore extends InMemorySharedPreferencesStore {
  _FlakyStore() : super.empty();

  bool failWrites = false;

  final List<Completer<void>> _gates = [];

  /// Returns a completer that the *next* write call to reach this store
  /// will await before proceeding. Call sites hand these out in the order
  /// their corresponding writes are expected to arrive, then complete them
  /// in whatever order the test wants to simulate.
  Completer<void> addGate() {
    final completer = Completer<void>();
    _gates.add(completer);
    return completer;
  }

  Future<void> _awaitNextGate() async {
    if (_gates.isEmpty) return;
    await _gates.removeAt(0).future;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    await _awaitNextGate();
    if (failWrites) throw Exception('simulated persistence failure');
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    await _awaitNextGate();
    if (failWrites) throw Exception('simulated persistence failure');
    return super.remove(key);
  }
}

void main() {
  late _FlakyStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = _FlakyStore();
    SharedPreferencesStorePlatform.instance = store;
  });

  test(
    'setPreference rolls back the optimistic update and rethrows when '
    'persistence fails, instead of leaving an unpersisted value live',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final controller = ThemeController(prefs);

      await controller.setPreference(AppThemePreference.amoled);
      expect(controller.state.preference, AppThemePreference.amoled);

      store.failWrites = true;
      await expectLater(
        controller.setPreference(AppThemePreference.light),
        throwsException,
      );

      // Rolled back to the last value that was actually persisted, instead
      // of silently keeping the failed "light" preference live in memory —
      // which would otherwise just as silently revert on the next launch.
      expect(controller.state.preference, AppThemePreference.amoled);
    },
  );

  test('an older setPreference call failing after a newer overlapping call '
      'already succeeded does not clobber the newer preference', () async {
    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController(prefs);
    expect(controller.state.preference, AppThemePreference.amoled);

    // Gate the two writes so call A's completes *after* call B's, even
    // though A was started first — simulating a slow older request that
    // finishes after a faster newer one.
    final gateA = store.addGate();
    final gateB = store.addGate();

    final futureA = controller.setPreference(AppThemePreference.amoled);
    final futureB = controller.setPreference(AppThemePreference.light);
    // Both calls have applied their optimistic update by now; B (started
    // second) is the current value.
    expect(controller.state.preference, AppThemePreference.light);

    // Let B's write land first and succeed.
    gateB.complete();
    await futureB;
    expect(controller.state.preference, AppThemePreference.light);

    // Now let A's (older) write land and fail.
    store.failWrites = true;
    gateA.complete();
    await expectLater(futureA, throwsException);

    // A must not roll back to its own "previous" (amoled, the default
    // from before either call started) — that would silently clobber B's
    // newer, already-persisted "light" selection.
    expect(controller.state.preference, AppThemePreference.light);
  });

  test('setUseSystemColor persists and rolls back on failure', () async {
    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController(prefs);
    expect(controller.state.useSystemColor, true);

    await controller.setUseSystemColor(false);
    expect(controller.state.useSystemColor, false);
    expect(
      prefs.getBool('one_wallet_flutter.theme.use_system_color.v1'),
      false,
    );

    store.failWrites = true;
    await expectLater(controller.setUseSystemColor(true), throwsException);
    expect(controller.state.useSystemColor, false);
  });

  test(
    'setCustomAccentColor persists, disables useSystemColor, and rolls back on failure',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final controller = ThemeController(prefs);

      const testColor = Color(0xFF007AFF);
      await controller.setCustomAccentColor(testColor);

      expect(controller.state.customAccentColor, testColor);
      expect(controller.state.useSystemColor, false);
      expect(
        prefs.getInt('one_wallet_flutter.theme.accent_color.v1'),
        testColor.toARGB32(),
      );
      expect(
        prefs.getBool('one_wallet_flutter.theme.use_system_color.v1'),
        false,
      );

      store.failWrites = true;
      const anotherColor = Color(0xFF10B981);
      await expectLater(
        controller.setCustomAccentColor(anotherColor),
        throwsException,
      );
      expect(controller.state.customAccentColor, testColor);
    },
  );

  test(
    'setColorIntensity clamps, persists, and rolls back on failure',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final controller = ThemeController(prefs);
      expect(controller.state.colorIntensity, 1.0);

      await controller.setColorIntensity(1.5);
      expect(controller.state.colorIntensity, 1.5);
      expect(
        prefs.getDouble('one_wallet_flutter.theme.color_intensity.v1'),
        1.5,
      );

      // Clamps out-of-bounds values
      await controller.setColorIntensity(3.0);
      expect(controller.state.colorIntensity, 1.8);

      store.failWrites = true;
      await expectLater(controller.setColorIntensity(0.5), throwsException);
      expect(controller.state.colorIntensity, 1.8);
    },
  );

  test(
    'resetToDefaults restores AMOLED, system color, and default intensity',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final controller = ThemeController(prefs);

      await controller.setPreference(AppThemePreference.light);
      await controller.setCustomAccentColor(const Color(0xFF10B981));
      await controller.setColorIntensity(1.4);

      await controller.resetToDefaults();
      expect(controller.state.preference, AppThemePreference.amoled);
      expect(controller.state.useSystemColor, true);
      expect(controller.state.customAccentColor, isNull);
      expect(controller.state.colorIntensity, 1.0);

      // On cold boot with stored values
      final newController = ThemeController(prefs);
      expect(newController.state.preference, AppThemePreference.amoled);
      expect(newController.state.useSystemColor, true);
      expect(newController.state.customAccentColor, isNull);
      expect(newController.state.colorIntensity, 1.0);
    },
  );
}
