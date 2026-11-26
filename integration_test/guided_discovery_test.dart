import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:one_wallet_flutter/src/features/login/login_screen.dart';
import 'package:one_wallet_flutter/src/features/login/offline_mode_sheet.dart';
import 'package:one_wallet_flutter/src/features/onboarding/feature_discovery_guide.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';
import 'package:one_wallet_flutter/main.dart' as app;

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var frame = 0; frame < 240; frame++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _waitFor(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fresh offline setup and real-screen guided workflows', (
    tester,
  ) async {
    app.main();
    await _tap(tester, find.byKey(LoginScreen.offlineButtonKey));
    await _tap(tester, find.byKey(OfflineModeSheet.acknowledgeKey));
    await _tap(tester, find.byKey(OfflineModeSheet.confirmKey));

    await _tap(tester, find.widgetWithText(FilledButton, 'Continue').first);
    final fields = find.byType(AppGlassTextField);
    await _waitFor(tester, fields);
    await tester.enterText(fields.at(0), 'Emulator test wallet');
    await tester.enterText(fields.at(1), '100');
    FocusManager.instance.primaryFocus?.unfocus();
    await _tap(tester, find.text('Save account'));
    await _tap(tester, find.text('Looks good'));
    await _tap(tester, find.text('Finish Setup'));

    await _waitFor(tester, find.text('Your wallet is ready'));
    await _tap(tester, find.text('Show me'));
    await _waitFor(tester, find.text('Your money, at a glance'));
    await _tap(tester, find.text('Continue'));
    await _waitFor(tester, find.text('Make your first record'));
    await _tap(tester, find.byTooltip('Add record'));
    await _tap(tester, find.text('Try it yourself'));
    await tester.binding.handlePopRoute();

    for (final (title, tab) in [
      ('Find any record', 'History'),
      ('Pick a day', 'Calendar'),
      ('Your accounts', 'Accounts'),
      ('Make it yours', 'Home'),
    ]) {
      await _waitFor(tester, find.text(title));
      await _tap(tester, find.text('Show $tab'));
      await _tap(
        tester,
        find.text(tab == 'Home' ? 'Finish basics' : 'Continue'),
      );
    }

    await _tap(tester, find.text('Explore workflows'));
    await _waitFor(tester, find.text('Plan ahead'));
    await _tap(tester, find.text('Continue'));
    await _waitFor(tester, find.text('Build a real plan'));
    await _tap(tester, find.text('Continue'));
    await _tap(tester, find.text('Leave draft'));
    await _waitFor(tester, find.text('Track what you owe'));
    await _tap(tester, find.text('Continue'));
    await _waitFor(tester, find.text('Set the loan terms'));
    await _tap(tester, find.text('Continue'));
    await _tap(tester, find.text('Leave draft'));
    await _waitFor(tester, find.text('What if you paid extra?'));
    await _tap(tester, find.text('Continue'));
    await _tap(tester, find.text('Finish guide'));

    await _waitFor(tester, find.text('Open an account'));
    await _tap(tester, find.text('Continue'));
    await _waitFor(tester, find.text('A bank or card account first'));
    await _tap(tester, find.byTooltip('Skip this guide'));
    await _waitFor(tester, find.text('Message to account'));
    await _tap(tester, find.text('Show account match'));
    await _waitFor(tester, find.text('Suffix 4242 → Sample Everyday'));
    await _tap(tester, find.text('Continue'));
    await _tap(tester, find.text('Continue'));
    await _tap(tester, find.text('Finish guide'));

    await _waitFor(tester, find.text('Choose what to capture'));
    await _tap(tester, find.text('Continue'));
    await _waitFor(tester, find.text('Match, then review'));
    await _waitFor(tester, find.text('Show account match'));
    await _tap(tester, find.text('Finish guide'));

    await _waitFor(tester, find.text('Tap the highlighted date'));
    await _tap(
      tester,
      find.byWidgetPredicate(
        (widget) =>
            widget is DiscoveryGuideAnchor && widget.id == 'calendar-day',
      ),
    );
    await _waitFor(tester, find.text('A day in detail'));
    await _tap(tester, find.text('Finish guide'));
    for (final title in [
      'Import with a review',
      'Build your dashboard',
      'Your preferences',
    ]) {
      await _waitFor(tester, find.text(title));
      await _tap(tester, find.text('Finish guide'));
    }
    expect(find.byTooltip('Close guide'), findsNothing);
  });
}
