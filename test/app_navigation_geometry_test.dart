import 'package:flutter/material.dart';
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
}

void _ignoreIndex(int _) {}
