import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/features/capture/notification_apps_screen.dart';
import 'package:one_wallet_flutter/src/features/capture/review_queue_screen.dart';
import 'package:one_wallet_flutter/src/features/updates/updates_screen.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart' show AppBackAction;

import 'test_harness.dart';

// NotificationAppsScreen calls this native channel from initState (see
// routes_smoke_test.dart for the full explanation): without a mock handler,
// invokeMethod never completes under `testWidgets`, hanging pumpAndSettle
// behind an indeterminate loading spinner.
const _nativeCaptureChannel = MethodChannel('com.joelpjoji.one.wallet/sms');

/// Pumps [target] pushed on top of a root route so `Navigator.canPop()` is
/// true inside it — matching how all three screens are actually reached in
/// the app (always via `context.push`, never as a root/tab destination).
Future<void> _pumpPushed(
  WidgetTester tester,
  Widget target, {
  List<Override> overrides = const [],
}) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        navigatorKey: navigatorKey,
        home: const Scaffold(body: SizedBox()),
      ),
    ),
  );
  navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => target));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_nativeCaptureChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_nativeCaptureChannel, null);
  });

  testWidgets(
    'ReviewQueueScreen uses GlassAppBar nav chrome, preserving the back '
    'action and every action-button tooltip',
    (tester) async {
      await _pumpPushed(
        tester,
        const ReviewQueueScreen(),
        overrides: authenticatedSampleOverrides(),
      );

      expect(find.byType(GlassAppBar), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(AppBackAction), findsOneWidget);
      expect(find.text('Review & Inbox'), findsOneWidget);
      expect(find.byTooltip('Auto-capture settings'), findsOneWidget);
    },
  );

  testWidgets(
    'UpdatesScreen uses GlassAppBar nav chrome, preserving the back action '
    'and the refresh tooltip',
    (tester) async {
      await _pumpPushed(tester, const UpdatesScreen());

      expect(find.byType(GlassAppBar), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(AppBackAction), findsOneWidget);
      expect(find.text('Updates'), findsOneWidget);
      expect(find.byTooltip('Check for updates'), findsOneWidget);
    },
  );

  testWidgets(
    'NotificationAppsScreen uses GlassAppBar nav chrome, preserving the '
    'back action',
    (tester) async {
      await _pumpPushed(
        tester,
        const NotificationAppsScreen(),
        overrides: authenticatedSampleOverrides(),
      );

      expect(find.byType(GlassAppBar), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(AppBackAction), findsOneWidget);
      expect(find.text('Target Apps'), findsOneWidget);
    },
  );
}
