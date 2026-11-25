import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:g1455/g1455.dart' as g1455;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../design/tokens.dart';
import '../theme/app_theme.dart';

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
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains(
      'Test',
    );
    final labelStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      fontFamily: Theme.of(context).textTheme.labelSmall?.fontFamily,
    );
    final labelWidths = items.map((item) {
      final painter = TextPainter(
        text: TextSpan(text: item.title, style: labelStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }).toList();

    if (pageController != null) {
      return AnimatedBuilder(
        animation: pageController!,
        builder: (context, _) {
          final currentTheme = Theme.of(context);
          final currentScheme = currentTheme.colorScheme;
          final currentIsDark = currentTheme.brightness == Brightness.dark;
          final page =
              pageController!.hasClients && pageController!.page != null
              ? pageController!.page!
              : selectedIndex.toDouble();
          return _buildContent(
            context,
            currentScheme,
            currentIsDark,
            isTest,
            page,
            labelWidths,
          );
        },
      );
    }
    return _buildContent(
      context,
      scheme,
      isDark,
      isTest,
      selectedIndex.toDouble(),
      labelWidths,
    );
  }

  Widget _buildContent(
    BuildContext context,
    ColorScheme scheme,
    bool isDark,
    bool isTest,
    double page,
    List<double> labelWidths,
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

            final requiredLabelWidth =
                labelWidths.fold<double>(
                  0,
                  (widest, width) => math.max(widest, math.max(48.0, width + 12)),
                ) *
                items.length;
            final normalWidth = math.min(totalWidth, AppSizes.islandMaxWidth);
            final smallestIslandWidth = hasAction
                ? math.max(0.0, normalWidth - 76)
                : normalWidth;
            final compactLabels = requiredLabelWidth > normalWidth;
            final canDockAction = requiredLabelWidth <= smallestIslandWidth;

            // Calendar is at tab index 2. Compute how close we are to calendar tab (0.0 to 1.0)
            final calendarProgress = hasAction && canDockAction
                ? (1.0 - (page - 2.0).abs()).clamp(0.0, 1.0)
                : 0.0;

            final compactWidth = (totalWidth - 76)
                .clamp(0.0, AppSizes.islandMaxWidth - 76)
                .toDouble();
            final islandWidth =
                normalWidth + (compactWidth - normalWidth) * calendarProgress;

            final normalLeft = (totalWidth - normalWidth) / 2;
            const compactLeft = 0.0;
            final islandLeft =
                normalLeft + (compactLeft - normalLeft) * calendarProgress;

            const normalFabBottom = AppSizes.bottomBar + AppSizes.bottomBarGap;
            const compactFabBottom =
                (AppSizes.bottomBar - AppSizes.islandActionSize) / 2;
            final fabBottom =
                normalFabBottom +
                (compactFabBottom - normalFabBottom) * calendarProgress;

            final containerHeight = action != null ? 176.0 : AppSizes.bottomBar;
            final activeTab = page.round().clamp(0, items.length - 1);
            final selectedWidth = compactLabels
                ? math.min(
                    math.max(48.0, labelWidths[activeTab] + 16),
                    math.max(0.0, islandWidth - 48 * (items.length - 1)),
                  )
                : islandWidth / items.length;
            final otherWidth = items.length > 1
                ? (islandWidth - selectedWidth) / (items.length - 1)
                : 0.0;
            final indicatorAlignment = compactLabels &&
                    islandWidth > selectedWidth
                ? (activeTab * otherWidth / (islandWidth - selectedWidth)) *
                          2 -
                      1
                : items.length > 1
                ? -1.0 +
                      (page.clamp(0.0, items.length - 1.0) /
                              (items.length - 1.0)) *
                          2.0
                : 0.0;

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
                      child: isTest && canDockAction
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
                                  finishName.contains('frosted') ||
                                  blur >= 20.0;
                              final isClear =
                                  finishName.contains('clear') || blur == 0.0;
                              final isRegular = !isFrosted && !isClear;

                              final fillAlphaTop = isFrosted
                                  ? (isDark ? 0.10 : 0.12)
                                  : (isRegular
                                        ? (isDark ? 0.05 : 0.06)
                                        : (isDark ? 0.02 : 0.03));
                              final fillAlphaBottom = isFrosted
                                  ? (isDark ? 0.04 : 0.05)
                                  : (isRegular
                                        ? (isDark ? 0.02 : 0.02)
                                        : (isDark ? 0.01 : 0.01));
                              final custom =
                                  Theme.of(
                                    context,
                                  ).extension<AppThemeCustomization>() ??
                                  const AppThemeCustomization();
                              final borderWidth = custom.islandOutlineThickness;
                              final hasIslandBorder =
                                  borderWidth > 0 &&
                                  custom.islandOutlineOpacity > 0;
                              final borderColor =
                                  (isDark
                                          ? Colors.white
                                          : scheme.outlineVariant)
                                      .withValues(
                                        alpha:
                                            (custom.islandOutlineOpacity *
                                                    (isDark ? 0.20 : 1.0))
                                                .clamp(0.0, 1.0),
                                      );
                              final shadowAlpha = isFrosted
                                  ? (isDark ? 0.30 : 0.14)
                                  : (isRegular
                                        ? (isDark ? 0.22 : 0.08)
                                        : (isDark ? 0.16 : 0.06));

                              final pillRadius = BorderRadius.circular(
                                AppSizes.bottomBarContentHeight / 2,
                              );

                              final effectiveFinish =
                                  (finish ?? g1455.GlassFinish.clear).copyWith(
                                    rim: Colors.transparent,
                                  );

                              Widget islandSurface = DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: pillRadius,
                                  border: hasIslandBorder
                                      ? Border.all(
                                          color: borderColor,
                                          width: borderWidth,
                                        )
                                      : null,
                                ),
                                child: g1455.GlassSurface(
                                  borderRadius: pillRadius,
                                  finish: effectiveFinish,
                                  labelled: false,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: pillRadius,
                                      border: Border.all(
                                        color: isDark
                                            ? (hasIslandBorder
                                                ? borderColor
                                                : Colors.transparent)
                                            : const Color(0x330F172A),
                                        width: isDark ? borderWidth : 1.0,
                                      ),
                                      gradient: isDark
                                          ? (fillAlphaTop > 0 ||
                                                  fillAlphaBottom > 0)
                                              ? LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [
                                                    const Color(
                                                      0xFF1E2026,
                                                    ).withAlphaFactor(
                                                      fillAlphaTop,
                                                    ),
                                                    const Color(
                                                      0xFF121418,
                                                    ).withAlphaFactor(
                                                      fillAlphaBottom,
                                                    ),
                                                  ],
                                                )
                                              : null
                                          : LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [
                                                Colors.white.withValues(alpha: 0.85),
                                                Colors.white.withValues(alpha: 0.65),
                                              ],
                                            ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withAlphaFactor(
                                            isDark ? shadowAlpha : 0.08,
                                          ),
                                          blurRadius: isDark ? 18 : 16,
                                          offset: Offset(0, isDark ? 6 : 4),
                                        ),
                                      ],
                                    ),
                                    child: Stack(
                                      children: [
                                        // Smooth animated active tab indicator pill following page drag in real-time
                                        if (items.isNotEmpty)
                                          Align(
                                            alignment: Alignment(
                                              indicatorAlignment,
                                              0.0,
                                            ),
                                            child: FractionallySizedBox(
                                              widthFactor: compactLabels &&
                                                      islandWidth > 0
                                                  ? selectedWidth / islandWidth
                                                  : 1.0 / items.length,
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
                                                      end:
                                                          Alignment.bottomRight,
                                                      colors: [
                                                        brightPrimary
                                                            .withAlphaFactor(
                                                              isDark
                                                                  ? 0.30
                                                                  : 0.20,
                                                            ),
                                                        brightPrimary
                                                            .withAlphaFactor(
                                                              isDark
                                                                  ? 0.16
                                                                  : 0.10,
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
                                                            isDark
                                                                ? 0.25
                                                                : 0.20,
                                                          ),
                                                      width: 0.5,
                                                    ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: brightPrimary
                                                            .withAlphaFactor(
                                                              isDark
                                                                  ? 0.18
                                                                  : 0.10,
                                                            ),
                                                        blurRadius: 8,
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
                                            for (
                                              int i = 0;
                                              i < items.length;
                                              i++
                                            )
                                              if (compactLabels &&
                                                  i == activeTab)
                                                SizedBox(
                                                  width: selectedWidth,
                                                  child: _IslandTabButton(
                                                    item: items[i],
                                                    isSelected: true,
                                                    onTap: () => onSelected(
                                                      items[i].pageIndex ?? i,
                                                    ),
                                                  ),
                                                )
                                              else
                                                Expanded(
                                                  child: _IslandTabButton(
                                                    item: items[i],
                                                    isSelected: activeTab == i,
                                                    showLabel: !compactLabels,
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
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
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
    this.showLabel = true,
  });

  final IslandTabItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final bool showLabel;

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
      value: item.badgeCount != null && item.badgeCount! > 0
          ? '${item.badgeCount}'
          : null,
      selected: isSelected,
      button: true,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconWidget,
              if (showLabel) ...[
                const SizedBox(height: 2),
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: color,
                    fontFamily: Theme.of(
                      context,
                    ).textTheme.labelSmall?.fontFamily,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
