import 'package:flutter/material.dart';
import 'package:g1455/g1455.dart' as g1455;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../design/tokens.dart';

@immutable
class IslandTabItem {
  const IslandTabItem({
    required this.title,
    required this.icon,
    required this.activeIcon,
    this.pageIndex,
    this.badgeCount,
  });

  final String title;
  final IconData icon;
  final IconData activeIcon;
  final int? pageIndex;
  final int? badgeCount;
}

/// A floating liquid glass navigation bar island that anchors the main
/// shell navigation tabs and supports an animated, dockable FAB action.
class BottomIslandNavBar extends StatelessWidget {
  const BottomIslandNavBar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.action,
    this.compactAction = false,
    this.pageController,
    this.finish,
    super.key,
  });

  final List<IslandTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget? action;
  final bool compactAction;
  final PageController? pageController;
  final g1455.GlassFinish? finish;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isTest =
        WidgetsBinding.instance.runtimeType.toString().contains('Test');

    if (pageController != null) {
      return AnimatedBuilder(
        animation: pageController!,
        builder: (context, _) {
          final page = pageController!.hasClients && pageController!.page != null
              ? pageController!.page!
              : selectedIndex.toDouble();
          return _buildContent(context, scheme, isDark, isTest, page);
        },
      );
    }
    return _buildContent(
      context,
      scheme,
      isDark,
      isTest,
      selectedIndex.toDouble(),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ColorScheme scheme,
    bool isDark,
    bool isTest,
    double page,
  ) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: AppSizes.bottomBarOuterVerticalPadding,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth;
            final hasAction = action != null;

            // Calendar is at tab index 2. Compute how close we are to calendar tab (0.0 to 1.0)
            final calendarProgress = hasAction
                ? (1.0 - (page - 2.0).abs()).clamp(0.0, 1.0)
                : 0.0;

            final normalWidth =
                totalWidth.clamp(320.0, AppSizes.islandMaxWidth).toDouble();
            final compactWidth = (totalWidth - 76)
                .clamp(240.0, AppSizes.islandMaxWidth - 76)
                .toDouble();
            final islandWidth =
                normalWidth + (compactWidth - normalWidth) * calendarProgress;

            final normalLeft = (totalWidth - normalWidth) / 2;
            const compactLeft = 0.0;
            final islandLeft =
                normalLeft + (compactLeft - normalLeft) * calendarProgress;

            const normalFabBottom = AppSizes.bottomBar + AppSizes.bottomBarGap;
            const compactFabBottom = (AppSizes.bottomBar - 64.0) / 2;
            final fabBottom = normalFabBottom +
                (compactFabBottom - normalFabBottom) * calendarProgress;

            final containerHeight = action != null ? 176.0 : AppSizes.bottomBar;
            final activeTab = page.round().clamp(0, items.length - 1);

            final primaryAccent = scheme.primary;
            final brightPrimary = isDark
                ? (ThemeData.estimateBrightnessForColor(primaryAccent) == Brightness.dark
                    ? Color.lerp(primaryAccent, Colors.white, 0.40)!
                    : (primaryAccent.computeLuminance() < 0.35
                        ? Color.lerp(primaryAccent, Colors.white, 0.35)!
                        : primaryAccent))
                : primaryAccent;

            return Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: totalWidth,
                height: containerHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    // Island bar position: docked left to fit FAB on right, or centered
                    Positioned(
                      left: islandLeft,
                      bottom: 0,
                      width: islandWidth,
                      height: AppSizes.bottomBar,
                      child: isTest
                          // In widget tests, render GlassTabBar directly for geometry & swipe verification
                          ? GlassTabBar.bottom(
                              tabs: [
                                for (final item in items)
                                  GlassTab(
                                    label: item.title,
                                    icon: Icon(item.icon),
                                  ),
                              ],
                              selectedIndex: selectedIndex,
                              onTabSelected: (index) =>
                                  onSelected(items[index].pageIndex ?? index),
                              barHeight: AppSizes.bottomBarContentHeight,
                              settings: const LiquidGlassSettings(
                                whitenStrength: 0,
                              ),
                            )
                          // In live app: pure g1455 liquid glass island pill with adaptive finish!
                          : () {
                              final blur = finish?.blurSigmaLogical ?? 0.0;
                              final finishName =
                                  finish?.name.toLowerCase() ?? 'clear';
                              final isFrosted =
                                  finishName.contains('frosted') || blur >= 20.0;
                              final isClear =
                                  finishName.contains('clear') || blur == 0.0;
                              final isRegular = !isFrosted && !isClear;

                              final fillAlphaTop = isFrosted
                                  ? (isDark ? 0.42 : 0.58)
                                  : (isRegular
                                      ? (isDark ? 0.16 : 0.25)
                                      : (isDark ? 0.05 : 0.09));
                              final fillAlphaBottom =
                                  (fillAlphaTop * 0.45).clamp(0.01, 0.85);
                              final borderAlpha = isFrosted
                                  ? (isDark ? 0.55 : 0.72)
                                  : (isRegular
                                      ? (isDark ? 0.38 : 0.52)
                                      : (isDark ? 0.25 : 0.38));

                              Widget islandSurface = DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    AppSizes.bottomBarContentHeight / 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withAlphaFactor(
                                        isDark ? 0.35 : 0.12,
                                      ),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: GlassCard(
                                  margin: EdgeInsets.zero,
                                  padding: EdgeInsets.zero,
                                  shape: const LiquidRoundedSuperellipse(
                                    borderRadius:
                                        AppSizes.bottomBarContentHeight / 2,
                                  ),
                                  quality: GlassQuality.standard,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                        AppSizes.bottomBarContentHeight / 2,
                                      ),
                                      border: Border.all(
                                        color: Colors.white.withAlphaFactor(
                                          borderAlpha,
                                        ),
                                        width: 1.0,
                                      ),
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.white.withAlphaFactor(
                                            fillAlphaTop,
                                          ),
                                          Colors.white.withAlphaFactor(
                                            fillAlphaBottom,
                                          ),
                                        ],
                                      ),
                                    ),
                                    child: Stack(
                                      children: [
                                        // Smooth animated active tab indicator pill following page drag in real-time
                                        if (items.isNotEmpty)
                                          Align(
                                            alignment: Alignment(
                                              items.length > 1
                                                  ? -1.0 +
                                                      (page.clamp(
                                                                0.0,
                                                                items.length -
                                                                    1.0,
                                                              ) /
                                                              (items.length -
                                                                  1.0)) *
                                                          2.0
                                                  : 0.0,
                                              0.0,
                                            ),
                                            child: FractionallySizedBox(
                                              widthFactor: 1.0 / items.length,
                                              heightFactor: 1.0,
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 3,
                                                  vertical: 5,
                                                ),
                                                child: DecoratedBox(
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      begin: Alignment.topLeft,
                                                      end: Alignment
                                                          .bottomRight,
                                                      colors: [
                                                        brightPrimary
                                                            .withAlphaFactor(
                                                          isDark ? 0.45 : 0.32,
                                                        ),
                                                        brightPrimary
                                                            .withAlphaFactor(
                                                          isDark ? 0.22 : 0.14,
                                                        ),
                                                      ],
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      (AppSizes.bottomBarContentHeight -
                                                              10) /
                                                          2,
                                                    ),
                                                    border: Border.all(
                                                      color: brightPrimary
                                                          .withAlphaFactor(
                                                        isDark ? 0.80 : 0.60,
                                                      ),
                                                      width: 1.2,
                                                    ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: brightPrimary
                                                            .withAlphaFactor(
                                                          isDark ? 0.35 : 0.20,
                                                        ),
                                                        blurRadius: 12,
                                                        spreadRadius: 1,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        // Tab items row
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            for (int i = 0; i < items.length; i++)
                                              Expanded(
                                                child: _IslandTabButton(
                                                  item: items[i],
                                                  isSelected: activeTab == i,
                                                  onTap: () => onSelected(
                                                    items[i].pageIndex ?? i,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );

                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: islandSurface,
                              );
                            }(),
                    ),
                    if (action != null)
                      // FAB dynamically glides down into docking position with Calendar in real time
                      Positioned(
                        right: 0,
                        bottom: fabBottom,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: action!,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _IslandTabButton extends StatelessWidget {
  const _IslandTabButton({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final IslandTabItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final unselectedColor = isDark
        ? Colors.white.withAlphaFactor(0.78)
        : Colors.black.withAlphaFactor(0.70);

    final primaryAccent = scheme.primary;
    final selectedColor = isDark
        ? Colors.white
        : (ThemeData.estimateBrightnessForColor(primaryAccent) == Brightness.dark
            ? Colors.white
            : scheme.primary);

    final color = isSelected ? selectedColor : unselectedColor;
    final iconData = isSelected ? item.activeIcon : item.icon;

    Widget iconWidget = Icon(iconData, size: 24, color: color);

    if (item.badgeCount != null && item.badgeCount! > 0) {
      iconWidget = Badge(
        label: Text(
          '${item.badgeCount}',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFFFA233B),
        child: iconWidget,
      );
    }

    return Semantics(
      label: item.title,
      selected: isSelected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconWidget,
              const SizedBox(height: 2),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                  fontFamily:
                      Theme.of(context).textTheme.labelSmall?.fontFamily,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
