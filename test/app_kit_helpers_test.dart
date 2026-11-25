import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:one_wallet_flutter/src/theme/app_theme.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

Widget _host(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? AppTheme.light(),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('action groups align odd rows and retain their actions', (
    tester,
  ) async {
    var selected = -1;
    await tester.pumpWidget(
      _host(
        Center(
          child: SizedBox(
            width: 400,
            child: AppActionGroup(
              children: [
                for (var index = 0; index < 3; index++)
                  OutlinedButton(
                    onPressed: () => selected = index,
                    child: Text('Action $index'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    final buttons = find.byType(OutlinedButton);
    final first = tester.getRect(buttons.at(0));
    final second = tester.getRect(buttons.at(1));
    final last = tester.getRect(buttons.at(2));
    expect(first.top, second.top);
    expect(first.width, second.width);
    expect(last.left, first.left);
    expect(last.right, second.right);
    await tester.tap(buttons.last);
    expect(selected, 2);
  });

  testWidgets('compact actions have one accessible 48dp tap target', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    for (final label in ['Manage', 'Go']) {
      await tester.pumpWidget(
        _host(
          Center(
            child: AppActionButton(
              label: label,
              compact: true,
              onPressed: () => taps++,
            ),
          ),
        ),
      );
      final action = find.byType(AppActionButton);
      final data = tester.getSemantics(action).getSemanticsData();
      expect(data.label, label);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      final bounds = tester.getRect(action);
      expect(bounds.width, greaterThanOrEqualTo(48));
      expect(bounds.height, greaterThanOrEqualTo(48));
      await tester.tapAt(bounds.topLeft + const Offset(2, 2));
    }
    expect(taps, 2);
    semantics.dispose();
  });

  testWidgets('PremiumRow is a separate accessible button', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            const TextField(decoration: InputDecoration(hintText: 'Your name')),
            PremiumRow(
              icon: Icons.attach_money_rounded,
              title: 'USD',
              subtitle: 'United States Dollar',
              onTap: () {},
            ),
          ],
        ),
      ),
    );
    final data = tester
        .getSemantics(find.bySemanticsLabel(RegExp('USD')))
        .getSemanticsData();
    expect(data.label, contains('USD'));
    expect(data.label, isNot(contains('Your name')));
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.flagsCollection.isButton, isTrue);
    semantics.dispose();
  });

  group('showAppSnackBar', () {
    testWidgets('shows a floating snackbar and replaces the visible one', (
      tester,
    ) async {
      late BuildContext captured;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      showAppSnackBar(captured, 'First');
      await tester.pump();
      showAppSnackBar(captured, 'Second');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));

      expect(find.text('Second'), findsOneWidget);
      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.behavior, SnackBarBehavior.floating);
    });

    testWidgets('is a no-op without a ScaffoldMessenger', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      showAppSnackBar(captured, 'Nowhere');
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    for (final (name, theme) in [
      ('light', AppTheme.light()),
      ('dark', AppTheme.amoled()),
    ]) {
      testWidgets('feedback is visible and readable in $name mode', (
        tester,
      ) async {
        late BuildContext captured;
        await tester.pumpWidget(
          _host(
            Builder(
              builder: (context) {
                captured = context;
                return const SizedBox.shrink();
              },
            ),
            theme: theme,
          ),
        );
        showAppSnackBar(
          captured,
          'Could not save',
          action: SnackBarAction(label: 'Retry', onPressed: () {}),
        );
        await tester.pumpAndSettle();

        final richText = tester.widget<RichText>(
          find.descendant(
            of: find.text('Could not save'),
            matching: find.byType(RichText),
          ),
        );
        final foreground = richText.text.style!.color!;
        final background = theme.snackBarTheme.backgroundColor!;
        final foregroundLuminance = foreground.computeLuminance();
        final backgroundLuminance = background.computeLuminance();
        final lighter = foregroundLuminance > backgroundLuminance
            ? foregroundLuminance
            : backgroundLuminance;
        final darker = foregroundLuminance < backgroundLuminance
            ? foregroundLuminance
            : backgroundLuminance;
        expect(foreground.a, 1);
        expect(background.a, 1);
        expect(richText.text.style!.fontSize, greaterThanOrEqualTo(12));
        expect((lighter + 0.05) / (darker + 0.05), greaterThanOrEqualTo(4.5));
        final actionColor = theme.snackBarTheme.actionTextColor!;
        final actionLuminance = actionColor.computeLuminance();
        final actionLighter = actionLuminance > backgroundLuminance
            ? actionLuminance
            : backgroundLuminance;
        final actionDarker = actionLuminance < backgroundLuminance
            ? actionLuminance
            : backgroundLuminance;
        expect(actionColor.a, 1);
        expect(
          (actionLighter + 0.05) / (actionDarker + 0.05),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });

  group('showAppConfirmDialog', () {
    Future<Future<bool>> open(
      WidgetTester tester, {
      bool destructive = false,
    }) async {
      late BuildContext captured;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final result = showAppConfirmDialog(
        captured,
        title: 'Delete plan?',
        message: 'This cannot be undone.',
        confirmLabel: 'Delete',
        destructive: destructive,
      );
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('resolves true when confirmed', (tester) async {
      final result = await open(tester);
      expect(find.text('Delete plan?'), findsOneWidget);
      expect(find.text('This cannot be undone.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });

    testWidgets('resolves false when cancelled or dismissed', (tester) async {
      final cancelled = await open(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(await cancelled, isFalse);

      final dismissed = await open(tester);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(await dismissed, isFalse);
    });

    testWidgets('destructive confirm uses the error colour', (tester) async {
      await open(tester, destructive: true);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Delete'),
      );
      final scheme = AppTheme.light().colorScheme;
      expect(
        button.style?.backgroundColor?.resolve(<WidgetState>{}),
        scheme.error,
      );
      expect(
        button.style?.foregroundColor?.resolve(<WidgetState>{}),
        scheme.onError,
      );
    });
  });

  testWidgets('showAppSheet presents a transparent, width-capped sheet', (
    tester,
  ) async {
    late BuildContext captured;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    showAppSheet<void>(
      context: captured,
      builder: (_) => const SizedBox(
        height: 200,
        child: AppSheetSurface(child: Text('Sheet body')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sheet body'), findsOneWidget);
    expect(find.byType(AppSheetHandle), findsOneWidget);
    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(sheet.backgroundColor, Colors.transparent);
    expect(sheet.constraints?.maxWidth, 640);
  });

  testWidgets('AppLoadingState shows a spinner and optional message', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const AppLoadingState(message: 'Loading apps')),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading apps'), findsOneWidget);
  });

  testWidgets('EmptyState danger tone tints the icon with the error colour', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not load',
          body: 'Try again later.',
          tone: MetricTone.danger,
        ),
      ),
    );
    final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline_rounded));
    expect(icon.color, AppTheme.light().colorScheme.error);
  });

  group('AppGroupedSection / AppGroupedTile', () {
    testWidgets('use the app font for header, title and subtitle', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const AppGroupedSection(
            header: 'Preferences',
            children: [
              AppGroupedTile(
                title: Text('Theme'),
                subtitle: Text('System'),
                showChevron: true,
              ),
            ],
          ),
        ),
      );
      for (final label in ['Preferences', 'Theme', 'System']) {
        final text = tester.widget<RichText>(
          find.descendant(
            of: find.text(label),
            matching: find.byType(RichText),
          ),
        );
        expect(text.text.style?.fontFamily, 'Inter', reason: label);
      }
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });

    testWidgets('toggle tile flips on row tap and merges switch semantics', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      var value = false;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) => AppGroupedSection(
              children: [
                AppGroupedTile.toggle(
                  title: const Text('Device notifications'),
                  subtitle: const Text('Reminders on this device'),
                  value: value,
                  onChanged: (next) => setState(() => value = next),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(GlassSwitch), findsOneWidget);
      await tester.tap(find.text('Device notifications'));
      await tester.pumpAndSettle();
      expect(value, isTrue);

      final node = tester.getSemantics(find.byType(AppGroupedTile));
      final data = node.getSemanticsData();
      expect(data.label, contains('Device notifications'));
      expect(data.label, contains('Reminders on this device'));
      expect(data.flagsCollection.isToggled, Tristate.isTrue);
      handle.dispose();
    });
  });

  testWidgets('HeaderIconButton exposes an optional tooltip', (tester) async {
    await tester.pumpWidget(
      _host(
        HeaderIconButton(
          icon: Icons.refresh_rounded,
          semanticLabel: 'Refresh',
          tooltip: 'Refresh',
          onPressed: () {},
        ),
      ),
    );
    expect(find.byTooltip('Refresh'), findsOneWidget);
  });
}
