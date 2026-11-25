import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:one_wallet_flutter/src/design/tokens.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';
import 'package:one_wallet_flutter/src/widgets/bottom_island_nav.dart';
import 'package:one_wallet_flutter/src/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('island and floating action keep a consistent safe-area gap', (
    tester,
  ) async {
    const size = Size(400, 800);
    const bottomInset = 24.0;
    await tester.binding.setSurfaceSize(size);

    final fabKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.amoled(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: size,
            padding: EdgeInsets.only(bottom: bottomInset),
            viewPadding: EdgeInsets.only(bottom: bottomInset),
          ),
          child: Scaffold(
            body: Stack(
              children: [
                AppScreen(
                  title: 'Geometry',
                  scrollable: false,
                  padding: EdgeInsets.zero,
                  floatingActionButton: SizedBox(
                    key: fabKey,
                    width: 64,
                    height: 64,
                  ),
                  child: const SizedBox.expand(),
                ),
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: BottomIslandNavBar(
                    items: [
                      IslandTabItem(
                        title: 'Home',
                        icon: Icons.home_outlined,
                        activeIcon: Icons.home,
                      ),
                    ],
                    selectedIndex: 0,
                    onSelected: _ignoreIndex,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final islandRect = tester.getRect(find.byType(GlassTabBar));
    final fabRect = tester.getRect(find.byKey(fabKey));
    expect(
      islandRect.bottom,
      size.height - bottomInset - AppSizes.bottomBarOuterVerticalPadding,
    );
    expect(islandRect.height, AppSizes.bottomBar);
    expect(islandRect.top - fabRect.bottom, AppSizes.bottomBarGap);
  });

  testWidgets('top-right save action exposes disabled saving state', (
    tester,
  ) async {
    var completeSave = false;
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.amoled(),
        home: Scaffold(
          appBar: AppBar(
            actions: [
              HeaderSaveAction(
                onPressed: () async {
                  await Future<void>.delayed(const Duration(milliseconds: 100));
                  completeSave = true;
                },
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Save'));
    await tester.pump();
    expect(find.bySemanticsLabel('Saving'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();
    expect(completeSave, isTrue);
    expect(find.bySemanticsLabel('Save'), findsOneWidget);
    handle.dispose();
  });

  testWidgets(
    'large-text navigation keeps the selected label and all targets',
    (tester) async {
      final fontLoader = FontLoader('Inter');
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        fontLoader.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
      }
      await fontLoader.load();
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final handle = tester.ensureSemantics();
      var selected = 2;
      final actionKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: StatefulBuilder(
                builder: (context, setState) => BottomIslandNavBar(
                  items: const [
                    IslandTabItem(
                      title: 'Home',
                      icon: Icons.home_outlined,
                      activeIcon: Icons.home,
                    ),
                    IslandTabItem(
                      title: 'History',
                      icon: Icons.receipt_long_outlined,
                      activeIcon: Icons.receipt_long,
                    ),
                    IslandTabItem(
                      title: 'Calendar',
                      icon: Icons.calendar_month_outlined,
                      activeIcon: Icons.calendar_month,
                    ),
                    IslandTabItem(
                      title: 'Accounts',
                      icon: Icons.wallet_outlined,
                      activeIcon: Icons.wallet,
                      badgeCount: 3,
                    ),
                  ],
                  selectedIndex: selected,
                  onSelected: (index) => setState(() => selected = index),
                  action: SizedBox(key: actionKey, width: 64, height: 64),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final title in ['Home', 'History', 'Calendar', 'Accounts']) {
        final tab = find.bySemanticsLabel(title);
        expect(tab, findsOneWidget);
        expect(tester.getSemantics(tab).label, title);
        final size = tester.getSize(tab);
        expect(size.width, greaterThanOrEqualTo(48), reason: title);
        expect(size.height, greaterThanOrEqualTo(48), reason: title);
        expect(
          tester.getRect(tab).overlaps(tester.getRect(find.byKey(actionKey))),
          isFalse,
          reason: '$title overlaps the action',
        );
      }
      expect(tester.getSemantics(find.bySemanticsLabel('Accounts')).value, '3');
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('Calendar'))
            .didExceedMaxLines,
        isFalse,
        reason: 'selected label is truncated',
      );
      await tester.tap(find.bySemanticsLabel('Accounts'));
      await tester.pumpAndSettle();
      expect(selected, 3);
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('Accounts'))
            .didExceedMaxLines,
        isFalse,
      );
      tester.view.physicalSize = const Size(426, 800);
      await tester.pumpAndSettle();
      for (final title in ['Home', 'History', 'Calendar', 'Accounts']) {
        expect(find.bySemanticsLabel(title), findsOneWidget);
      }
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('Accounts'))
            .didExceedMaxLines,
        isFalse,
      );
      expect(tester.takeException(), isNull);
      handle.dispose();
    },
  );
}

void _ignoreIndex(int _) {}
