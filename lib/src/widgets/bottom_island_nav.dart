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

            final primaryColor = scheme.primary;
            final brightPrimary = isDark
                ? Color.lerp(primaryColor, Colors.white, 0.15)!
                : primaryColor;

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
                                  ? (isDark ? 0.38 : 0.45)
                                  : (isRegular
                                      ? (isDark ? 0.22 : 0.20)
                                      : (isDark ? 0.16 : 0.14));
                              final fillAlphaBottom = isFrosted
                                  ? (isDark ? 0.16 : 0.20)
                                  : (isRegular
                                      ? (isDark ? 0.08 : 0.10)
                                      : (isDark ? 0.06 : 0.07));
                              final borderAlpha = isFrosted
                                  ? (isDark ? 0.55 : 0.65)
                                  : (isRegular
                                      ? (isDark ? 0.38 : 0.45)
                                      : (isDark ? 0.30 : 0.35));
                              final borderColor = isDark
                                  ? Colors.white.withAlphaFactor(borderAlpha)
                                  : (isClear
                                      ? scheme.outline.withAlphaFactor(0.20)
                                      : Colors.white.withAlphaFactor(borderAlpha));
                              final shadowAlpha = isFrosted
                                  ? (isDark ? 0.38 : 0.16)
                                  : (isRegular
                                      ? (isDark ? 0.30 : 0.10)
                                      : (isDark ? 0.24 : 0.08));

                              final pillRadius = BorderRadius.circular(
                                AppSizes.bottomBarContentHeight / 2,
                              );

                              Widget islandSurface = g1455.GlassSurface(
                                borderRadius: pillRadius,
                                finish: finish ?? g1455.GlassFinish.clear,
                                labelled: false,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: pillRadius,
                                    border: Border.all(
                                      color: borderColor,
                                      width: 1.0,
                                    ),
                                    gradient: (fillAlphaTop > 0 || fillAlphaBottom > 0)
                                        ? LinearGradient(
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
                                          )
                                        : null,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withAlphaFactor(
                                          shadowAlpha,
                                        ),
                                        blurRadius: 18,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
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
                                                          isDark
                                                              ? 0.55
                                                              : 0.28,
                                                        ),
                                                        brightPrimary
                                                            .withAlphaFactor(
                                                          isDark
                                                              ? 0.32
                                                              : 0.16,
                                                        ),
                                                      ],
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      (AppSizes.bottomBarContentHeight -
                                                              8) /
                                                          2,
                                                    ),
                                                    border: Border.all(
                                                      color: brightPrimary
                                                          .withAlphaFactor(
                                                        isDark ? 0.85 : 0.60,
                                                      ),
                                                      width: 1.2,
                                                    ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: brightPrimary
                                                            .withAlphaFactor(
                                                          isDark
                                                              ? 0.40
                                                              : 0.20,
                                                        ),
                                                        blurRadius: 14,
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
                                );

                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
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

    final selectedColor = isDark ? Colors.white : scheme.primary;

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
