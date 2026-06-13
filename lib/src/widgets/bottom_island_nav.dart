import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/tokens.dart';
import 'app_kit.dart';

@immutable
class IslandTabItem {
  const IslandTabItem({
    required this.title,
    required this.icon,
    required this.activeIcon,
    this.pageIndex,
  });

  final String title;
  final IconData icon;
  final IconData activeIcon;
  final int? pageIndex;
}

class BottomIslandNavBar extends StatelessWidget {
  const BottomIslandNavBar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.pageController,
    super.key,
  });

  final List<IslandTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final PageController? pageController;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 390;
            final islandWidth = math.min(constraints.maxWidth, 430.0);
            final navHeight = compact ? 72.0 : 76.0;
            const navPadding = 6.0;
            final indicatorHeight = navHeight - navPadding * 2;
            final tabWidth = (islandWidth - navPadding * 2) / items.length;

            final pillWidth = compact ? 76.0 : 80.0;

            return Align(
              alignment: Alignment.bottomCenter,
              child: LiquidGlassContainer(
                width: islandWidth,
                height: navHeight,
                borderRadius: BorderRadius.circular(AppRadii.pill),
                child: AnimatedBuilder(
                  animation:
                      pageController ?? const AlwaysStoppedAnimation(0.0),
                  builder: (context, child) {
                    double page = selectedIndex.toDouble();
                    if (pageController != null && pageController!.hasClients) {
                      page = pageController!.page ?? selectedIndex.toDouble();
                    }

                    final tabCenter = navPadding + tabWidth * (page + 0.5);
                    final left = tabCenter - pillWidth / 2;

                    return Stack(
                      children: [
                        Positioned(
                          left: left,
                          top: navPadding,
                          width: pillWidth,
                          height: indicatorHeight,
                          child: const _SelectedIslandBubble(),
                        ),
                        // Tab buttons
                        Align(
                          alignment: Alignment.center,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6.0,
                            ),
                            child: Row(
                              children: [
                                for (
                                  var index = 0;
                                  index < items.length;
                                  index++
                                )
                                  Expanded(
                                    child: _IslandButton(
                                      item: items[index],
                                      selected:
                                          (items[index].pageIndex ?? index) ==
                                          selectedIndex,
                                      compact: compact,
                                      onTap: () => onSelected(
                                        items[index].pageIndex ?? index,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SelectedIslandBubble extends StatelessWidget {
  const _SelectedIslandBubble();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        color: scheme.primary.withAlphaFactor(isDark ? 0.25 : 0.15),
      ),
    );
  }
}

class _IslandButton extends StatefulWidget {
  const _IslandButton({
    required this.item,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final IslandTabItem item;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  State<_IslandButton> createState() => _IslandButtonState();
}

class _IslandButtonState extends State<_IslandButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 0.88,
    ).animate(CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  void _onTapDown(_) {
    _scaleCtrl.forward();
  }

  void _onTapUp(_) {
    _scaleCtrl.reverse();
  }

  void _onTapCancel() {
    _scaleCtrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final activeColor = scheme.primary;
    final inactiveColor = isDark
        ? scheme.onSurface.withAlphaFactor(0.55)
        : scheme.onSurface.withAlphaFactor(0.45);
    final color = widget.selected ? activeColor : inactiveColor;

    final iconSize = widget.selected
        ? (widget.compact ? 24.0 : 26.0)
        : (widget.compact ? 22.0 : 24.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: _onTapDown,
      onTapCancel: _onTapCancel,
      onTapUp: _onTapUp,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 200),
          scale: widget.selected ? 1.04 : 1.0,
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                duration: const Duration(milliseconds: 200),
                scale: widget.selected ? 1.08 : 1.0,
                curve: Curves.easeOutBack,
                child: Icon(
                  widget.selected ? widget.item.activeIcon : widget.item.icon,
                  size: iconSize,
                  color: color,
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: widget.compact ? 2 : 3),
                child: Text(
                  widget.item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: widget.compact ? 10.5 : 11.5,
                    height: 1.0,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
