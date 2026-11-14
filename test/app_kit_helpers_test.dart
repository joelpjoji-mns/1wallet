import 'dart:ui' show Tristate;

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
