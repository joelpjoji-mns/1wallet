import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app/one_wallet_app.dart';
import 'src/config/firebase_env.dart';
import 'src/services/notification_service.dart';
import 'src/theme/theme_controller.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  final sharedPreferencesWarmup = SharedPreferences.getInstance();
  final dateFormattingWarmup = initializeDateFormatting();
  final notificationWarmup = NotificationService.initialize();
  await FirebaseEnv.load();
  FirebaseEnv.assertProductionReady();
  final firebaseOptions = FirebaseEnv.firebaseOptions;
  if (firebaseOptions != null) {
    await Firebase.initializeApp(options: firebaseOptions);
    if (FirebaseEnv.useFirebaseEmulator) {
      await FirebaseAuth.instance.useAuthEmulator(
        FirebaseEnv.firebaseEmulatorHost,
        FirebaseEnv.firebaseAuthEmulatorPort,
      );
      FirebaseFirestore.instance.useFirestoreEmulator(
        FirebaseEnv.firebaseEmulatorHost,
        FirebaseEnv.firebaseFirestoreEmulatorPort,
      );
    }
  }
  await Future.wait([sharedPreferencesWarmup, dateFormattingWarmup, notificationWarmup]);
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
    child: const OneWalletApp(),
  ));
  FlutterNativeSplash.remove();
}
