import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

abstract final class FirebaseEnv {
  static const envFile = '.env';

  static const _requiredFirebaseKeys = [
    'FIREBASE_API_KEY',
    'FIREBASE_PROJECT_ID',
    'FIREBASE_APP_ID',
    'FIREBASE_MESSAGING_SENDER_ID',
  ];

  static Future<void> load() async {
    await dotenv.load(fileName: envFile, isOptional: true);
  }

  static FirebaseOptions? get firebaseOptions {
    if (missingFirebaseKeys.isNotEmpty) return null;

    return FirebaseOptions(
      apiKey: _value('FIREBASE_API_KEY')!,
      appId: _value('FIREBASE_APP_ID')!,
      messagingSenderId: _value('FIREBASE_MESSAGING_SENDER_ID')!,
      projectId: _value('FIREBASE_PROJECT_ID')!,
      authDomain: _value('FIREBASE_AUTH_DOMAIN'),
      storageBucket: _value('FIREBASE_STORAGE_BUCKET'),
      iosBundleId: 'com.joelpjoji.one.wallet',
      androidClientId: googleAndroidClientId,
      iosClientId: googleIosClientId,
    );
  }

  static bool get firebaseConfigured => firebaseOptions != null;

  static List<String> get missingFirebaseKeys => [
    for (final key in _requiredFirebaseKeys)
      if (_value(key) == null) key,
  ];

  static String? get googleWebClientId => _value('GOOGLE_WEB_CLIENT_ID');

  static String? get googleAndroidClientId =>
      _value('GOOGLE_ANDROID_CLIENT_ID');

  static String? get googleIosClientId => _value('GOOGLE_IOS_CLIENT_ID');

  static String? get googleClientIdForPlatform {
    if (kIsWeb) return googleWebClientId;
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => googleIosClientId,
      TargetPlatform.android => googleAndroidClientId,
      _ => googleWebClientId,
    };
  }

  static bool get googleSignInConfigured {
    final platformClientId = googleClientIdForPlatform;
    return _hasValue(googleWebClientId) || _hasValue(platformClientId);
  }

  static bool get emailPasswordAuthEnabled {
    return _bool('ONEWALLET_ENABLE_EMAIL_PASSWORD_AUTH');
  }

  static String? get qaEmailPasswordEmail {
    return _value('ONEWALLET_QA_EMAIL');
  }

  static String? get qaEmailPasswordPassword {
    return _value('ONEWALLET_QA_PASSWORD');
  }

  static bool get useFirebaseEmulator => _bool('FIREBASE_USE_EMULATOR');

  static String get firebaseEmulatorHost {
    return _value('FIREBASE_EMULATOR_HOST') ?? '10.0.2.2';
  }

  static int get firebaseAuthEmulatorPort {
    return int.tryParse(_value('FIREBASE_AUTH_EMULATOR_PORT') ?? '') ?? 9099;
  }

  static int get firebaseFirestoreEmulatorPort {
    return int.tryParse(_value('FIREBASE_FIRESTORE_EMULATOR_PORT') ?? '') ??
        8080;
  }

  static String configurationSummary() {
    final missing = [...missingFirebaseKeys];
    if (!googleSignInConfigured) {
      missing.add('GOOGLE_WEB_CLIENT_ID or platform Google client ID');
    }
    if (missing.isEmpty) return 'Firebase and Google sign-in are configured.';
    return 'Missing local sign-in configuration: ${missing.join(', ')}.';
  }

  static void assertProductionReady() {
    if (!kReleaseMode) return;
    final missing = [...missingFirebaseKeys];
    if (!_hasValue(googleWebClientId)) missing.add('GOOGLE_WEB_CLIENT_ID');
    if (useFirebaseEmulator) missing.add('FIREBASE_USE_EMULATOR=false');
    if (missing.isNotEmpty) {
      throw StateError(
        'Production Firebase/Google configuration is missing: '
        '${missing.join(', ')}',
      );
    }
  }

  static String? _value(String key) {
    final direct = _maybeGet(key)?.trim();
    if (_hasValue(direct)) return direct;
    final expo = _maybeGet('EXPO_PUBLIC_$key')?.trim();
    if (_hasValue(expo)) return expo;
    return null;
  }

  static String? _maybeGet(String key) {
    try {
      return dotenv.maybeGet(key);
    } catch (_) {
      return null;
    }
  }

  static bool _bool(String key) {
    final value = _value(key)?.toLowerCase();
    return value == '1' || value == 'true' || value == 'yes' || value == 'on';
  }

  static bool _hasValue(String? value) => value != null && value.isNotEmpty;
}
