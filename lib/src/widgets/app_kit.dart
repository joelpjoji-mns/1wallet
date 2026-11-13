import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart' show CupertinoTextField;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:g1455/g1455.dart' as g1455;

export 'package:g1455/g1455.dart'
    hide
        GlassButton,
        GlassCard,
        GlassSwitch,
        GlassSlider,
        GlassSegmentedControl,
        GlassTextField,
        GlassSearchBar,
        GlassTabBar,
        GlassMenuItem,
        GlassBadge,
        GlassBlendGroup;

import '../design/tokens.dart';

/// Liquid Rounded Superellipse shape border compatible with iOS continuous curves.
class LiquidRoundedSuperellipse extends OutlinedBorder {
  const LiquidRoundedSuperellipse({
    this.borderRadius = 0.0,
    super.side,
  });

  final double borderRadius;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  ShapeBorder scale(double t) => LiquidRoundedSuperellipse(
    borderRadius: borderRadius * t,
    side: side.scale(t),
  );

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is LiquidRoundedSuperellipse) {
      return LiquidRoundedSuperellipse(
        borderRadius: ui.lerpDouble(a.borderRadius, borderRadius, t) ?? borderRadius,
        side: BorderSide.lerp(a.side, side, t),
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is LiquidRoundedSuperellipse) {
      return LiquidRoundedSuperellipse(
        borderRadius: ui.lerpDouble(borderRadius, b.borderRadius, t) ?? borderRadius,
        side: BorderSide.lerp(side, b.side, t),
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()..addRRect(
      RRect.fromRectAndRadius(
        rect.deflate(side.width),
        Radius.circular(math.max(0.0, borderRadius - side.width)),
      ),
    );
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return Path()..addRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(borderRadius)),
    );
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    final paint = side.toPaint();
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.deflate(side.width / 2),
        Radius.circular(math.max(0.0, borderRadius - side.width / 2)),
      ),
      paint,
    );
  }

  @override
  OutlinedBorder copyWith({BorderSide? side}) {
    return LiquidRoundedSuperellipse(
      borderRadius: borderRadius,
      side: side ?? this.side,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is LiquidRoundedSuperellipse &&
        other.borderRadius == borderRadius &&
        other.side == side;
  }

  @override
  int get hashCode => Object.hash(borderRadius, side);
}

/// Compatibility alias for LiquidRoundedRectangle.
typedef LiquidRoundedRectangle = LiquidRoundedSuperellipse;

/// Glass button styles for styling hints.
enum GlassButtonStyle { filled, prominent, outlined, flat }

/// Glass quality tier hint for backward compatibility.
enum GlassQuality { minimal, standard, premium }

/// Glass isolation boundary ensuring isolated paint/capture passes.
class GlassIsolationScope extends StatelessWidget {
  const GlassIsolationScope({
    required this.child,
    this.defaultQuality,
    super.key,
  });

  final Widget child;
  final GlassQuality? defaultQuality;

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: child);
}

/// Fuses adjacent glass surfaces fluidly into one liquid silhouette.
class GlassBlendGroup extends StatelessWidget {
  const GlassBlendGroup({
    required this.child,
    this.spacing = 16.0,
    this.finish,
    this.labelled = true,
    super.key,
  });

  final Widget child;
  final double spacing;
  final g1455.GlassFinish? finish;
  final bool labelled;

  @override
  Widget build(BuildContext context) {
    return g1455.GlassGroup(
      spacing: spacing,
      finish: finish,
      labelled: labelled,
      child: child,
    );
  }
}

/// The canonical glass card for 1Wallet, featuring backdrop blur, subtle
/// inner rim highlight, and continuous superellipse corners.
class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    this.borderRadius,
    this.shape,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.finish,
    this.quality,
    this.clipBehavior = Clip.none,
    super.key,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final ShapeBorder? shape;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final g1455.GlassFinish? finish;
  final GlassQuality? quality;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    BorderRadius effectiveRadius =
        borderRadius ?? const BorderRadius.all(Radius.circular(24));
    if (shape is LiquidRoundedSuperellipse) {
      effectiveRadius = BorderRadius.all(
        Radius.circular((shape as LiquidRoundedSuperellipse).borderRadius),
      );
    } else if (shape is RoundedRectangleBorder) {
      effectiveRadius = (shape as RoundedRectangleBorder)
          .borderRadius
          .resolve(Directionality.maybeOf(context));
    } else if (shape is ContinuousRectangleBorder) {
      effectiveRadius = (shape as ContinuousRectangleBorder)
          .borderRadius
          .resolve(Directionality.maybeOf(context));
    }

    Widget content = g1455.GlassCard(
      borderRadius: effectiveRadius,
      padding: padding ?? EdgeInsets.zero,
      finish: finish,
      child: child,
    );

    if (margin != null && margin != EdgeInsets.zero) {
      content = Padding(padding: margin!, child: content);
    }
    return content;
  }
}

/// Interactive liquid glass button with iOS spring compression response (`GlassPress`).
class GlassButton extends StatelessWidget {
  const GlassButton({
    this.child,
    this.onPressed,
    this.onTap,
    this.icon,
    this.label,
    this.iconColor,
    this.width,
    this.height,
    this.iconSize,
    this.borderRadius = g1455.kGlassCapsule,
    this.padding = EdgeInsets.zero,
    this.minSize = Size.zero,
    this.pressedOverlay,
    this.press = const g1455.GlassPress(),
    this.finish,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
    this.settings,
    this.quality,
    this.useOwnLayer,
    this.stretch,
    this.interactionScale,
    this.resistance,
    this.shape,
    this.enabled,
    this.style,
    super.key,
  });

  const GlassButton.custom({
    this.child,
    this.onPressed,
    this.onTap,
    this.icon,
    this.label,
    this.iconColor,
    this.width,
    this.height,
    this.iconSize,
    this.borderRadius = g1455.kGlassCapsule,
    this.padding = EdgeInsets.zero,
    this.minSize = Size.zero,
    this.pressedOverlay,
    this.press = const g1455.GlassPress(),
    this.finish,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
    this.settings,
    this.quality,
    this.useOwnLayer,
    this.stretch,
    this.interactionScale,
    this.resistance,
    this.shape,
    this.enabled,
    this.style,
    super.key,
  });

  final Widget? child;
  final VoidCallback? onPressed;
  final VoidCallback? onTap;
  final Widget? icon;
  final String? label;
  final Color? iconColor;
  final double? width;
  final double? height;
  final double? iconSize;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final Size minSize;
  final Color? pressedOverlay;
  final g1455.GlassPress? press;
  final g1455.GlassFinish? finish;
  final String? semanticLabel;
  final FocusNode? focusNode;
  final bool autofocus;
  final dynamic settings;
  final GlassQuality? quality;
  final bool? useOwnLayer;
  final double? stretch;
  final double? interactionScale;
  final double? resistance;
  final ShapeBorder? shape;
  final bool? enabled;
  final dynamic style;

  @override
  Widget build(BuildContext context) {
    BorderRadius effectiveRadius = borderRadius;
    if (shape is LiquidRoundedSuperellipse) {
      effectiveRadius = BorderRadius.all(
        Radius.circular((shape as LiquidRoundedSuperellipse).borderRadius),
      );
    } else if (shape is RoundedRectangleBorder) {
      effectiveRadius = (shape as RoundedRectangleBorder)
          .borderRadius
          .resolve(Directionality.maybeOf(context));
    } else if (shape is ContinuousRectangleBorder) {
      effectiveRadius = (shape as ContinuousRectangleBorder)
          .borderRadius
          .resolve(Directionality.maybeOf(context));
    }

    Widget content = child ??
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              if (iconColor != null)
                IconTheme(
                  data: IconThemeData(color: iconColor, size: iconSize),
                  child: icon!,
                )
              else
                icon!,
              if (label != null) const SizedBox(width: 8),
            ],
            if (label != null)
              Text(label!, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        );

    if (width != null || height != null) {
      content = SizedBox(
        width: width,
        height: height,
        child: Center(child: content),
      );
    }

    final effectiveOnPressed = (enabled ?? true) ? (onPressed ?? onTap) : null;

    return g1455.GlassButton(
      onPressed: effectiveOnPressed,
      borderRadius: effectiveRadius,
      padding: padding,
      minSize: Size(width ?? minSize.width, height ?? minSize.height),
      pressedOverlay: pressedOverlay,
      press: press,
      finish: finish,
      semanticLabel: semanticLabel ?? label,
      focusNode: focusNode,
      autofocus: autofocus,
      child: content,
    );
  }
}

/// Circular/compact glass icon button for app bars and action buttons.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.semanticLabel,
    this.iconSize = 22,
    this.quality,
    super.key,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final String? semanticLabel;
  final double iconSize;
  final GlassQuality? quality;

  @override
  Widget build(BuildContext context) {
    Widget button = g1455.GlassButton(
      onPressed: onPressed,
      semanticLabel: semanticLabel ?? tooltip,
      padding: const EdgeInsets.all(8),
      minSize: const Size(40, 40),
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      child: IconTheme(
        data: IconThemeData(size: iconSize),
        child: icon,
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// Refractive glass navigation app bar matching iOS navigation chrome.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    this.title,
    this.leading,
    this.actions,
    this.centerTitle = false,
    this.backgroundColor,
    this.preferredHeight = 44.0,
    this.finish,
    super.key,
  });

  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool centerTitle;
  final Color? backgroundColor;
  final double preferredHeight;
  final g1455.GlassFinish? finish;

  @override
  Size get preferredSize => Size.fromHeight(preferredHeight);

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    final height = preferredHeight + topPadding;
    final scheme = Theme.of(context).colorScheme;

    Widget navContent = Container(
      height: height,
      padding: EdgeInsets.only(top: topPadding, left: 8, right: 8),
      child: NavigationToolbar(
        leading: leading,
        middle: title != null
            ? DefaultTextStyle(
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ) ??
                    const TextStyle(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                child: title!,
              )
            : null,
        trailing: actions != null && actions!.isNotEmpty
            ? Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: actions!,
              )
            : null,
        centerMiddle: centerTitle,
        middleSpacing: 8,
      ),
    );

    return g1455.GlassBar(
      borderRadius: BorderRadius.zero,
      padding: EdgeInsets.zero,
      finish: finish,
      child: navContent,
    );
  }
}

/// iOS-style glass switch with dynamic spring physics.
class GlassSwitch extends StatelessWidget {
  const GlassSwitch({
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.trackColor,
    this.semanticLabel,
    this.quality,
    this.useOwnLayer,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;
  final Color? trackColor;
  final String? semanticLabel;
  final GlassQuality? quality;
  final bool? useOwnLayer;

  @override
  Widget build(BuildContext context) {
    return g1455.GlassSwitch(
      value: value,
      onChanged: onChanged,
      activeColor: activeColor,
      trackColor: trackColor,
      semanticLabel: semanticLabel,
    );
  }
}

/// iOS-style glass slider with drop motion spring physics.
class GlassSlider extends StatelessWidget {
  const GlassSlider({
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.activeColor,
    this.trackColor,
    this.semanticLabel,
    super.key,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final int? divisions;
  final Color? activeColor;
  final Color? trackColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final range = max - min;
    final normalized =
        range > 0 ? ((value - min) / range).clamp(0.0, 1.0) : 0.0;
    return g1455.GlassSlider(
      value: normalized,
      divisions: divisions,
      activeColor: activeColor,
      trackColor: trackColor,
      semanticLabel: semanticLabel,
      onChanged: onChanged != null ? (v) => onChanged!(min + v * range) : null,
    );
  }
}

/// Segment item representation for GlassSegmentedControl.
class GlassSegment extends StatelessWidget {
  const GlassSegment({
    required this.label,
    this.icon,
    super.key,
  });

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (icon != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Text(label),
        ],
      );
    }
    return Text(label);
  }
}

/// iOS-style segmented control on glass.
class GlassSegmentedControl extends StatelessWidget {
  const GlassSegmentedControl({
    required this.segments,
    required this.selectedIndex,
    this.onSelected,
    this.onSegmentSelected,
    this.trackColor,
    this.thumbColor,
    super.key,
  });

  final List<Widget> segments;
  final int selectedIndex;
  final ValueChanged<int>? onSelected;
  final ValueChanged<int>? onSegmentSelected;
  final Color? trackColor;
  final Color? thumbColor;

  @override
  Widget build(BuildContext context) {
    return g1455.GlassSegmentedControl(
      segments: segments,
      selectedIndex: selectedIndex,
      onSelected: onSelected ?? onSegmentSelected ?? (_) {},
      trackColor: trackColor,
      thumbColor: thumbColor,
    );
  }
}

/// An action item inside a glass menu or pull-down dropdown.
class GlassMenuItem {
  const GlassMenuItem({
    String? title,
    String? label,
    this.icon,
    this.onTap,
    this.onPressed,
    this.isDestructive = false,
    this.isSelected = false,
  }) : title = title ?? label ?? '',
       label = label ?? title ?? '';

  final String title;
  final String label;
  final Widget? icon;
  final VoidCallback? onTap;
  final VoidCallback? onPressed;
  final bool isDestructive;
  final bool isSelected;
}

/// Pull-down glass button opening a native iOS UIMenu-style modal glass popup.
class GlassPullDownButton extends StatelessWidget {
  const GlassPullDownButton({
    required this.items,
    this.icon = const Icon(Icons.more_vert_rounded),
    this.semanticLabel,
    this.menuWidth = 220,
    super.key,
  });

  final List<GlassMenuItem> items;
  final Widget icon;
  final String? semanticLabel;
  final double menuWidth;

  @override
  Widget build(BuildContext context) {
    return g1455.GlassMenuAnchor(
      items: [
        for (final item in items)
          g1455.GlassMenuItem(
            label: item.title.isNotEmpty ? item.title : item.label,
            icon: item.icon,
            onPressed: item.onTap ?? item.onPressed,
            isDestructive: item.isDestructive,
          ),
      ],
      builder: (context, controller) => GlassButton(
        onPressed: controller.open,
        semanticLabel: semanticLabel,
        padding: const EdgeInsets.all(8),
        minSize: const Size(40, 40),
        child: icon,
      ),
    );
  }
}

/// Glass menu popup anchor compatible with legacy GlassMenu.
class GlassMenu extends StatelessWidget {
  const GlassMenu({
    required this.items,
    required this.triggerBuilder,
    this.menuWidth = 220.0,
    this.quality,
    super.key,
  });

  final List<GlassMenuItem> items;
  final Widget Function(BuildContext context, VoidCallback toggleMenu) triggerBuilder;
  final double menuWidth;
  final GlassQuality? quality;

  @override
  Widget build(BuildContext context) {
    return g1455.GlassMenuAnchor(
      width: menuWidth,
      items: [
        for (final item in items)
          g1455.GlassMenuItem(
            label: item.title.isNotEmpty ? item.title : item.label,
            icon: item.icon,
            onPressed: item.onTap ?? item.onPressed,
            isDestructive: item.isDestructive,
          ),
      ],
      builder: (context, controller) => triggerBuilder(context, controller.open),
    );
  }
}

/// Glass search bar with clear button and smooth Cancel animation.
class GlassSearchBar extends StatelessWidget {
  const GlassSearchBar({
    this.controller,
    this.focusNode,
    this.placeholder = 'Search',
    this.onChanged,
    this.onSubmitted,
    this.onCancel,
    this.showsCancelButton = false,
    this.cancelLabel = 'Cancel',
    this.cancelColor,
    this.cancelDuration = const Duration(milliseconds: 250),
    this.autofocus = false,
    this.finish,
    this.quality,
    this.height,
    this.textStyle,
    this.searchIconColor,
    this.useOwnLayer,
    super.key,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String placeholder;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onCancel;
  final bool showsCancelButton;
  final String cancelLabel;
  final Color? cancelColor;
  final Duration cancelDuration;
  final bool autofocus;
  final g1455.GlassFinish? finish;
  final GlassQuality? quality;
  final double? height;
  final TextStyle? textStyle;
  final Color? searchIconColor;
  final bool? useOwnLayer;

  @override
  Widget build(BuildContext context) {
    Widget bar = g1455.GlassSearchBar(
      controller: controller,
      focusNode: focusNode,
      placeholder: placeholder,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onCancel: onCancel,
      showsCancelButton: showsCancelButton,
      cancelLabel: cancelLabel,
      cancelColor: cancelColor,
      cancelDuration: cancelDuration,
      autofocus: autofocus,
      finish: finish,
    );
    if (height != null) {
      bar = SizedBox(height: height, child: bar);
    }
    return bar;
  }
}

/// Glass badge for counts and indicators.
class GlassBadge extends StatelessWidget {
  const GlassBadge({
    this.count,
    this.label,
    this.backgroundColor,
    this.child,
    super.key,
  });

  final int? count;
  final String? label;
  final Color? backgroundColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (child == null) {
      return g1455.GlassBadge(count: count, label: label);
    }
    if (backgroundColor == null) {
      return g1455.GlassBadge(count: count, label: label, child: child);
    }
    final effectiveCount = count ?? 0;
    if (effectiveCount <= 0 && label == null) return child!;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child!,
        Positioned(
          right: -6,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(
              label ?? (effectiveCount > 99 ? '99+' : '$effectiveCount'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Pill-shaped glass tag/chip.
class GlassChip extends StatelessWidget {
  const GlassChip({
    required this.label,
    this.icon,
    this.selected = false,
    this.isSelected = false,
    this.selectedColor,
    this.labelStyle,
    this.onTap,
    this.quality,
    this.useOwnLayer,
    super.key,
  });

  final String label;
  final dynamic icon;
  final bool selected;
  final bool isSelected;
  final Color? selectedColor;
  final TextStyle? labelStyle;
  final VoidCallback? onTap;
  final GlassQuality? quality;
  final bool? useOwnLayer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isEffectiveSelected = selected || isSelected;
    final activeColor = selectedColor ?? scheme.primary;

    Widget? iconWidget;
    if (icon is Widget) {
      iconWidget = icon as Widget;
    } else if (icon is IconData) {
      iconWidget = Icon(
        icon as IconData,
        size: 14,
        color: isEffectiveSelected
            ? (isDark ? Colors.white : activeColor)
            : scheme.onSurfaceVariant,
      );
    }

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (iconWidget != null) ...[
          iconWidget,
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: (labelStyle ?? theme.textTheme.labelMedium)?.copyWith(
            color: isEffectiveSelected
                ? (isDark ? Colors.white : activeColor)
                : scheme.onSurfaceVariant,
            fontWeight: isEffectiveSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );

    return GlassButton(
      onPressed: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(AppRadii.pill)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      minSize: const Size(32, 32),
      finish: isEffectiveSelected
          ? (isDark ? g1455.GlassFinish.regularDark : g1455.GlassFinish.regularLight)
              .copyWith(tint: activeColor.withAlphaFactor(0.25))
          : null,
      child: content,
    );
  }
}

/// Subtle hairline separator for inset grouped sections.
class GlassDivider extends StatelessWidget {
  const GlassDivider({
    this.height = 1,
    this.thickness = 0.5,
    this.indent = 0,
    this.endIndent = 0,
    this.color,
    super.key,
  });

  final double height;
  final double thickness;
  final double indent;
  final double endIndent;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: Center(
        child: Container(
          margin: EdgeInsetsDirectional.only(start: indent, end: endIndent),
          height: thickness,
          color: color ?? scheme.outlineVariant.withAlphaFactor(0.2),
        ),
      ),
    );
  }
}

/// Glass progress indicator with luminous fill.
class GlassProgressIndicator extends StatelessWidget {
  const GlassProgressIndicator.linear({
    this.value,
    this.trackColor,
    this.fillColor,
    super.key,
  });

  final double? value;
  final Color? trackColor;
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (value == null) {
      return SizedBox(
        height: 6,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            backgroundColor:
                trackColor ?? scheme.surfaceContainerHighest.withAlphaFactor(0.4),
            color: fillColor ?? scheme.primary,
          ),
        ),
      );
    }
    final progress = value!.clamp(0.0, 1.0);
    return SizedBox(
      height: 6,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Stack(
          children: [
            Container(
              color: trackColor ??
                  scheme.surfaceContainerHighest.withAlphaFactor(0.4),
            ),
            FractionallySizedBox(
              widthFactor: progress,
              child: Container(
                decoration: BoxDecoration(
                  color: fillColor ?? scheme.primary,
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: [
                    BoxShadow(
                      color: (fillColor ?? scheme.primary).withAlphaFactor(0.4),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inset grouped table container matching iOS grouped table sections.
class GlassGroupedSection extends StatelessWidget {
  const GlassGroupedSection({
    required this.children,
    this.header,
    this.footer,
    this.margin = EdgeInsets.zero,
    this.shape,
    this.quality,
    super.key,
  });

  final List<Widget> children;
  final Widget? header;
  final Widget? footer;
  final EdgeInsetsGeometry margin;
  final ShapeBorder? shape;
  final GlassQuality? quality;

  @override
  Widget build(BuildContext context) {
    BorderRadius effectiveRadius =
        const BorderRadius.all(Radius.circular(AppRadii.md));
    if (shape is RoundedRectangleBorder) {
      effectiveRadius = (shape as RoundedRectangleBorder)
          .borderRadius
          .resolve(Directionality.maybeOf(context));
    }

    final sectionBody = GlassCard(
      borderRadius: effectiveRadius,
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) const GlassDivider(),
            children[i],
          ],
        ],
      ),
    );

    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: header!,
            ),
          sectionBody,
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: footer!,
            ),
        ],
      ),
    );
  }
}

/// Inset grouped table row matching iOS style.
class GlassListTile extends StatelessWidget {
  const GlassListTile({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.leadingIconColor,
    this.titleStyle,
    this.subtitleStyle,
    this.contentPadding =
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    super.key,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? leadingIconColor;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget leadingWidget = leading ?? const SizedBox.shrink();
    if (leading != null && leadingIconColor != null) {
      leadingWidget = IconTheme(
        data: IconThemeData(color: leadingIconColor, size: 22),
        child: leading!,
      );
    }

    Widget content = Padding(
      padding: contentPadding,
      child: Row(
        children: [
          if (leading != null) ...[
            leadingWidget,
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                DefaultTextStyle(
                  style: titleStyle ??
                      theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ) ??
                      const TextStyle(),
                  child: title,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  DefaultTextStyle(
                    style: subtitleStyle ??
                        theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ) ??
                        const TextStyle(),
                    child: subtitle!,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: content,
        ),
      );
    }
    return content;
  }
}

/// Item definition for GlassTabBar.bottom compatibility.
class GlassTab {
  const GlassTab({
    required this.label,
    required this.icon,
    this.activeIcon,
    this.semanticLabel,
  });

  final String label;
  final Widget icon;
  final Widget? activeIcon;
  final String? semanticLabel;
}

/// iOS glass tab bar dock powered by `g1455`.
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.activeColor,
    this.dropZoom = g1455.kGlassTabDropZoom,
    this.dropMotion,
    this.minimizeBehavior = g1455.GlassTabBarMinimizeBehavior.never,
    this.bottomAccessory,
    this.settings,
    this.barHeight,
    this.verticalPadding,
    super.key,
  }) : tabs = null,
       onTabSelected = null;

  GlassTabBar.bottom({
    required List<GlassTab> this.tabs,
    required this.selectedIndex,
    required ValueChanged<int> this.onTabSelected,
    this.settings,
    dynamic quality,
    dynamic backgroundQuality,
    this.barHeight,
    double? horizontalPadding,
    this.verticalPadding,
    double? spacing,
    Color? indicatorColor,
    Color? selectedIconColor,
    Color? unselectedIconColor,
    Color? selectedLabelColor,
    Color? unselectedLabelColor,
    TextStyle? selectedLabelStyle,
    TextStyle? unselectedLabelStyle,
    super.key,
  }) : items = [
         for (final tab in tabs)
           g1455.GlassTabItem(
             label: tab.label,
             iconBuilder: (context, look) => look.selected
                 ? (tab.activeIcon ?? tab.icon)
                 : tab.icon,
           ),
       ],
       onSelected = onTabSelected,
       activeColor = selectedIconColor,
       dropZoom = g1455.kGlassTabDropZoom,
       dropMotion = null,
       minimizeBehavior = g1455.GlassTabBarMinimizeBehavior.never,
       bottomAccessory = null;

  final List<g1455.GlassTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Color? activeColor;
  final double dropZoom;
  final g1455.GlassDropMotion? dropMotion;
  final g1455.GlassTabBarMinimizeBehavior minimizeBehavior;
  final Widget? bottomAccessory;
  final List<GlassTab>? tabs;
  final ValueChanged<int>? onTabSelected;
  final dynamic settings;
  final double? barHeight;
  final double? verticalPadding;

  @override
  Widget build(BuildContext context) {
    final totalHeight = barHeight != null
        ? barHeight! + ((verticalPadding ?? 12) * 2)
        : (tabs != null ? AppSizes.bottomBar : null);

    Widget result;
    if (items.length < 2) {
      final tab = (tabs != null && tabs!.isNotEmpty) ? tabs!.first : null;
      final item = items.isNotEmpty ? items.first : null;
      final scheme = Theme.of(context).colorScheme;
      result = Center(
        child: g1455.GlassSurface(
          borderRadius: const BorderRadius.all(Radius.circular(AppRadii.pill)),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: verticalPadding ?? 8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tab != null)
                  (tab.activeIcon ?? tab.icon)
                else if (item != null)
                  item.iconBuilder?.call(
                        context,
                        const g1455.GlassTabItemLook(
                          index: 0,
                          selected: true,
                          highlighted: false,
                          inline: false,
                          iconSize: 26,
                          color: Colors.white,
                          labelStyle: TextStyle(),
                        ),
                      ) ??
                      const SizedBox.shrink(),
                if (tab?.label != null || item?.label != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    tab?.label ?? item?.label ?? '',
                    style: TextStyle(
                      color: activeColor ?? scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    } else {
      result = Center(
        child: g1455.GlassTabBar(
          items: items,
          selectedIndex: selectedIndex,
          onSelected: onSelected,
          activeColor: activeColor,
          dropZoom: dropZoom,
          dropMotion: dropMotion,
          minimizeBehavior: minimizeBehavior,
          bottomAccessory: bottomAccessory,
        ),
      );
    }

    if (totalHeight != null) {
      result = SizedBox(
        height: totalHeight,
        child: result,
      );
    }

    return result;
  }
}

/// A horizontal drag gesture recognizer that only claims gestures moving to the right
/// (dx > 0) beyond touch slop. Rejects gestures moving to the left so that
/// parent horizontal navigators (such as PageView) can handle leftward gestures seamlessly.
class RightSwipeGestureRecognizer extends HorizontalDragGestureRecognizer {
  RightSwipeGestureRecognizer({super.debugOwner, super.supportedDevices});

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    final slop = computeHitSlop(pointerDeviceKind, gestureSettings);
    // If moving right (dx > 0) beyond touch slop: declare win in gesture arena
    if (globalDistanceMoved > slop) {
      return true;
    }
    // If moving left (dx < 0), immediately reject so parent PageView wins without delay
    if (globalDistanceMoved < -0.5) {
      resolve(GestureDisposition.rejected);
    }
    return false;
  }
}

/// Wraps widgets to detect a rightward swipe gesture to trigger drawer opening,
/// while letting leftward swipes pass through to parent PageView and vertical
/// scrolls pass through to scrollable lists.
class RightSwipeToOpenDrawer extends StatefulWidget {
  const RightSwipeToOpenDrawer({
    required this.child,
    required this.onOpenDrawer,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final VoidCallback onOpenDrawer;
  final bool enabled;

  @override
  State<RightSwipeToOpenDrawer> createState() => _RightSwipeToOpenDrawerState();
}

class _RightSwipeToOpenDrawerState extends State<RightSwipeToOpenDrawer> {
  double _dragDistance = 0.0;
  bool _triggered = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        RightSwipeGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<RightSwipeGestureRecognizer>(
              () => RightSwipeGestureRecognizer(),
              (RightSwipeGestureRecognizer instance) {
                instance
                  ..onStart = (_) {
                    _dragDistance = 0.0;
                    _triggered = false;
                  }
                  ..onUpdate = (details) {
                    _dragDistance += details.delta.dx;
                    if (!_triggered && _dragDistance > 38.0) {
                      _triggered = true;
                      widget.onOpenDrawer();
                    }
                  }
                  ..onEnd = (details) {
                    if (!_triggered) {
                      final velocity = details.primaryVelocity ?? 0.0;
                      if (velocity > 100.0 || _dragDistance > 24.0) {
                        _triggered = true;
                        widget.onOpenDrawer();
                      }
                    }
                  };
              },
            ),
      },
      child: widget.child,
    );
  }
}

/// A consistent, accessible top-right action for single-screen form saves.
class HeaderSaveAction extends StatefulWidget {
  const HeaderSaveAction({
    required this.onPressed,
    super.key,
    this.isSaving = false,
  });

  final Future<void> Function() onPressed;
  final bool isSaving;

  @override
  State<HeaderSaveAction> createState() => _HeaderSaveActionState();
}

@immutable
class GlassDropdownOption<T> {
  const GlassDropdownOption(this.value, this.label, {this.icon});
  final T value;
  final String label;
  final IconData? icon;
}

/// Compact glass dropdown used for short, non-searchable option lists.
class GlassDropdownPill<T> extends StatelessWidget {
  const GlassDropdownPill({
    required this.value,
    required this.options,
    required this.onChanged,
    this.icon,
    this.semanticLabel,
    this.maxLabelWidth = 148,
    super.key,
  });

  final T value;
  final List<GlassDropdownOption<T>> options;
  final ValueChanged<T> onChanged;
  final IconData? icon;
  final String? semanticLabel;
  final double maxLabelWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final matching = options.where((option) => option.value == value);
    final selected = matching.isEmpty ? null : matching.first;
    final label =
        selected?.label ?? (options.isEmpty ? '' : options.first.label);
    return GlassMenu(
      menuWidth: 220,
      quality: GlassQuality.standard,
      items: [
        for (final option in options)
          GlassMenuItem(
            title: option.label,
            isSelected: option.value == value,
            icon: Icon(
              option.icon ??
                  (option.value == value
                      ? Icons.check_rounded
                      : Icons.circle_outlined),
              size: 18,
              color: option.value == value
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
            ),
            onTap: () => onChanged(option.value),
          ),
      ],
      triggerBuilder: (context, toggleMenu) => GlassButton.custom(
        onTap: toggleMenu,
        label: semanticLabel ?? label,
        quality: GlassQuality.standard,
        shape: const LiquidRoundedSuperellipse(borderRadius: AppRadii.pill),
        useOwnLayer: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: scheme.primary),
                const SizedBox(width: AppSpacing.xxs),
              ],
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxLabelWidth),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xxxs),
              Icon(
                Icons.expand_more_rounded,
                size: 17,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderSaveActionState extends State<HeaderSaveAction> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) => HeaderIconButton(
    icon: Icons.check_rounded,
    loading: widget.isSaving || _busy,
    onPressed: widget.isSaving || _busy
        ? null
        : () async {
            setState(() => _busy = true);
            try {
              await widget.onPressed();
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
    semanticLabel: widget.isSaving || _busy ? 'Saving' : 'Save',
  );
}

class AppResponsiveLayout extends StatelessWidget {
  const AppResponsiveLayout({
    required this.mobile,
    required this.desktop,
    this.desktopBreakpoint = 800,
    super.key,
  });

  final Widget mobile;
  final Widget desktop;
  final double desktopBreakpoint;

  static bool isDesktop(BuildContext context, {double breakpoint = 800}) {
    return MediaQuery.sizeOf(context).width >= breakpoint;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= desktopBreakpoint) {
          return desktop;
        }
        return mobile;
      },
    );
  }
}

/// Dissolves the top of scrollable content with mathematical smootherstep easing
/// using an alpha mask. Prevents hard cutoffs, bands, and step jumps.
class AppTopFadeMask extends StatelessWidget {
  const AppTopFadeMask({
    required this.child,
    this.fadeHeight = 20.0,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final double fadeHeight;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final surfaceColor = Theme.of(context).colorScheme.surface;

    return Stack(
      fit: StackFit.passthrough,
      alignment: Alignment.center,
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: fadeHeight,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [surfaceColor, surfaceColor.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class AppScreen extends StatelessWidget {
  const AppScreen({
    required this.title,
    required this.child,
    super.key,
    this.onMenuPressed,
    this.menuIndicator = false,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.xs,
      AppSpacing.md,
      AppSpacing.md,
    ),
    this.scrollable = true,
    this.floatingActionButton,
    this.maxWidth = 800,
  });

  final String title;
  final Widget child;
  final VoidCallback? onMenuPressed;
  final bool menuIndicator;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;
  final bool scrollable;
  final Widget? floatingActionButton;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final isDesktop = AppResponsiveLayout.isDesktop(context);

    // Adjust bottom clearance to account for bottom navigation bar on mobile
    final contentPadding = scrollable && !isDesktop
        ? padding.add(
            EdgeInsets.only(
              bottom:
                  AppSizes.bottomBarClearance +
                  MediaQuery.paddingOf(context).bottom +
                  AppSizes.bottomBarGap,
            ),
          )
        : padding;

    Widget body = scrollable
        ? AppTopFadeMask(
            child: ListView(padding: contentPadding, children: [child]),
          )
        : Padding(padding: contentPadding, child: child);

    // Apply width constraint but preserve tight vertical constraints
    body = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: body,
        ),
      ),
    );

    // A transparent Material gives text and ink a Material ancestor even
    // when the page is used outside the MainShell scaffold (e.g. the
    // stand-alone /accounts route); without it Text falls back to the
    // framework's debug style.
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: AppHeader(
                      title: title,
                      onMenuPressed: isDesktop
                          ? null
                          : onMenuPressed, // Hide menu button on desktop since drawer is persistent
                      menuIndicator: menuIndicator,
                      actions: actions,
                    ),
                  ),
                ),
                Expanded(child: body),
              ],
            ),
          ),
          if (floatingActionButton != null)
            Positioned(
              right: isDesktop ? AppSpacing.xl : AppSpacing.lg,
              bottom: isDesktop
                  ? AppSpacing.xl
                  : AppSizes.bottomBar +
                        AppSizes.bottomBarOuterVerticalPadding +
                        MediaQuery.paddingOf(context).bottom +
                        AppSizes.bottomBarGap,
              child: floatingActionButton!,
            ),
        ],
      ),
    );
  }
}

class IslandFloatingActionButton extends StatelessWidget {
  const IslandFloatingActionButton({
    required this.icon,
    required this.onPressed,
    super.key,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget button = GlassButton(
      icon: Icon(icon),
      onPressed: onPressed,
      width: 64,
      height: 64,
      iconSize: 30,
      iconColor: Theme.of(context).colorScheme.primary,
      quality: GlassQuality.standard,
    );

    final tooltipMessage = tooltip;
    if (tooltipMessage != null && tooltipMessage.isNotEmpty) {
      button = Tooltip(message: tooltipMessage, child: button);
    }
    return button;
  }
}

class AppHeader extends StatelessWidget {
  const AppHeader({
    required this.title,
    super.key,
    this.onMenuPressed,
    this.menuIndicator = false,
    this.actions = const [],
  });

  final String title;
  final VoidCallback? onMenuPressed;
  final bool menuIndicator;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final header = GlassAppBar(
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      leading: onMenuPressed != null
          ? AppMenuAction(
              onPressed: onMenuPressed!,
              showIndicator: menuIndicator,
            )
          : canPop
          ? const AppBackAction()
          : null,
      actions: actions,
    );

    return GlassIsolationScope(
      defaultQuality: GlassQuality.premium,
      child: onMenuPressed != null
          ? RightSwipeToOpenDrawer(onOpenDrawer: onMenuPressed!, child: header)
          : header,
    );
  }
}

/// Combines a base accessibility label with a pending-badge count so screen
/// readers announce e.g. "Open menu, 3 pending" instead of leaving the badge
/// number as a disconnected, context-less text node.
String? _headerButtonSemanticLabel(
  String? label,
  int? badge, {
  bool showIndicator = false,
}) {
  final count = badge ?? 0;
  if (label == null) return null;
  if (count <= 0) {
    if (showIndicator) return '$label, update available';
    return label;
  }
  return '$label, $count pending';
}

class GlassHeaderButton extends StatelessWidget {
  const GlassHeaderButton({
    required this.icon,
    required this.onPressed,
    this.badge,
    this.showIndicator = false,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final int? badge;
  final bool showIndicator;

  /// Accessibility label announced by screen readers (e.g. "Open menu").
  /// Without this, `GlassIconButton` exposes an empty label and the button
  /// is announced with no description of its action.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => HeaderIconButton(
    icon: icon,
    onPressed: onPressed,
    badge: badge,
    showIndicator: showIndicator,
    semanticLabel: semanticLabel,
  );
}

class AppMenuAction extends StatelessWidget {
  const AppMenuAction({
    required this.onPressed,
    this.badge,
    this.showIndicator = false,
    super.key,
  });

  final VoidCallback onPressed;
  final int? badge;
  final bool showIndicator;

  @override
  Widget build(BuildContext context) {
    return GlassHeaderButton(
      icon: Icons.menu_rounded,
      onPressed: onPressed,
      badge: badge,
      showIndicator: showIndicator,
      semanticLabel: 'Open menu',
    );
  }
}

class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    required this.icon,
    required this.onPressed,
    super.key,
    this.badge,
    this.showIndicator = false,
    this.semanticLabel,
    this.tooltip,
    this.loading = false,
    this.destructive = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final int? badge;
  final bool showIndicator;
  final bool loading;

  /// Tints the icon with the error colour (e.g. delete-selection actions).
  final bool destructive;

  /// Accessibility label announced by screen readers. Without this,
  /// `GlassIconButton` exposes an empty label and the button is announced
  /// with no description of its action.
  final String? semanticLabel;

  /// Optional long-press/hover tooltip (usually the same as
  /// [semanticLabel]).
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final message = tooltip;
    if (message != null && message.isNotEmpty) {
      return Tooltip(message: message, child: _buildButton(context));
    }
    return _buildButton(context);
  }

  Widget _buildButton(BuildContext context) {
    final badgeCount = badge ?? 0;
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xxs),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          UnconstrainedBox(
            child: GlassIconButton(
              icon: loading
                  ? const AppInlineSpinner()
                  : Icon(
                      icon,
                      color: destructive
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
              iconSize: 22,
              quality: GlassQuality.standard,
              onPressed: onPressed,
              semanticLabel: _headerButtonSemanticLabel(
                semanticLabel,
                badgeCount,
                showIndicator: showIndicator,
              ),
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              right: 8,
              top: 8,
              // Badge count is folded into the semanticLabel above; exclude
              // this visual duplicate so screen readers don't announce it
              // twice, disconnected from context.
              child: ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    badgeCount > 9 ? '9+' : '$badgeCount',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onError,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
            )
          else if (showIndicator)
            Positioned(
              right: 10,
              top: 10,
              child: ExcludeSemantics(
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shared cross-platform action control backed by Liquid Glass.
class AppActionButton extends StatelessWidget {
  const AppActionButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.enabled = true,
    this.prominent = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool enabled;
  final bool prominent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = prominent
        ? scheme.primary
        : scheme.surfaceContainerHighest.withValues(alpha: 0.65);
    final fg = prominent ? scheme.onPrimary : scheme.primary;

    final content = Container(
      height: compact ? 36 : 48,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.sm : AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: enabled && onPressed != null ? bg : bg.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 16 : 18, color: fg),
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  (compact
                          ? Theme.of(context).textTheme.labelMedium
                          : Theme.of(context).textTheme.labelLarge)
                      ?.copyWith(color: fg, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    return GlassButton.custom(
      label: label,
      onTap: onPressed ?? () {},
      enabled: enabled && onPressed != null,
      height: compact ? 36 : 48,
      shape: const LiquidRoundedRectangle(borderRadius: AppRadii.pill),
      useOwnLayer: true,
      quality: GlassQuality.standard,
      style: prominent ? GlassButtonStyle.prominent : GlassButtonStyle.filled,
      child: content,
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.title,
    required this.child,
    super.key,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.compact = false,
    this.glass = true,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;
  final Widget child;

  /// Uses the package's refractive glass surface when true. Set false when
  /// this section is already placed on another glass surface.
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final content = Material(
      color: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xxxs),
                          child: Text(
                            subtitle!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
                if (actionLabel != null && onAction != null)
                  AppActionButton(
                    label: actionLabel!,
                    onPressed: onAction,
                    compact: true,
                  ),
              ],
            ),
            if (child is! SizedBox ||
                ((child as SizedBox).height != null &&
                    (child as SizedBox).height! > 0) ||
                ((child as SizedBox).width != null &&
                    (child as SizedBox).width! > 0)) ...[
              SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
              child,
            ],
          ],
        ),
      ),
    );

    if (glass) {
      return GlassCard(
        margin: EdgeInsets.zero,
        padding: EdgeInsets.zero,
        shape: const LiquidRoundedSuperellipse(borderRadius: AppRadii.md),
        quality: GlassQuality.standard,
        child: content,
      );
    }

    return DecoratedBox(decoration: AppSurfaces.panel(context), child: content);
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    super.key,
    this.tone = MetricTone.standard,
    this.compact = false,
    this.onTap,
    this.glass = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final MetricTone tone;
  final bool compact;
  final VoidCallback? onTap;

  /// Opts this tile into a refractive `GlassCard` surface instead of the
  /// default opaque background.
  ///
  /// `MetricTile` is almost always used two-to-four at a time inside a
  /// `SectionCard`'s summary row — defaulting to glass here meant nesting
  /// one refractive `GlassCard` inside another, which the package
  /// explicitly calls an anti-pattern (double-refraction, wasted fill-rate).
  /// Defaults to `false`; only flip it on for a standalone tile that isn't
  /// nested in another glass surface.
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = tone.resolve(scheme);

    final content = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? AppSpacing.sm : AppSpacing.md,
            vertical: compact ? AppSpacing.xs : AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              IconBubble(icon: icon, color: color, compact: true),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );

    if (glass) {
      return GlassCard(
        margin: EdgeInsets.zero,
        padding: EdgeInsets.zero,
        shape: const LiquidRoundedSuperellipse(borderRadius: AppRadii.md),
        quality: GlassQuality.standard,
        clipBehavior: Clip.antiAlias,
        child: content,
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: AppSurfaces.panel(context),

      child: content,
    );
  }
}

enum MetricTone { standard, positive, danger, warning }

/// The single tone -> colour mapping used by every status surface.
extension MetricToneColors on MetricTone {
  /// [standard] is what the neutral tone resolves to (primary by default;
  /// pass `scheme.onSurface` for plain text values).
  Color resolve(ColorScheme scheme, {Color? standard}) => switch (this) {
    MetricTone.positive => scheme.positive,
    MetricTone.danger => scheme.error,
    MetricTone.warning => scheme.warning,
    MetricTone.standard => standard ?? scheme.primary,
  };
}

class IconBubble extends StatelessWidget {
  const IconBubble({
    required this.icon,
    super.key,
    this.color,
    this.compact = false,
  });

  final IconData icon;
  final Color? color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = color ?? scheme.primary;
    final size = compact ? 26.0 : 34.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: iconColor.withAlphaFactor(
          Theme.of(context).brightness == Brightness.dark ? 0.22 : 0.12,
        ),
        borderRadius: BorderRadius.circular(
          compact ? AppRadii.sm : AppRadii.md,
        ),
      ),
      child: Icon(icon, color: iconColor, size: compact ? 16 : 20),
    );
  }
}

class PremiumSearchInput extends StatefulWidget {
  const PremiumSearchInput({
    required this.hintText,
    required this.onChanged,
    super.key,
    this.value = '',
    this.height = 48,
  });

  final String hintText;
  final String value;
  final ValueChanged<String> onChanged;
  final double height;

  @override
  State<PremiumSearchInput> createState() => _PremiumSearchInputState();
}

class _PremiumSearchInputState extends State<PremiumSearchInput> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(PremiumSearchInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && _controller.text != widget.value) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassSearchBar(
      controller: _controller,
      placeholder: widget.hintText,
      onChanged: widget.onChanged,
      height: widget.height,
      textStyle: TextStyle(
        color: scheme.onSurface,
        fontFamily: theme.textTheme.bodyLarge?.fontFamily,
        fontSize: theme.textTheme.bodyLarge?.fontSize,
      ),
      searchIconColor: scheme.primary,
      quality: GlassQuality.standard,
      useOwnLayer: true,
    );
  }
}

/// iOS glass text field with backdrop blur, specular edge highlight, and Material form support.
class GlassTextField extends StatelessWidget {
  const GlassTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.placeholder,
    this.prefixIcon,
    this.leading,
    this.suffixIcon,
    this.trailing,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.textStyle,
    this.style,
    this.textAlign = TextAlign.start,
    this.quality,
    this.finish,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? placeholder;
  final Widget? prefixIcon;
  final Widget? leading;
  final Widget? suffixIcon;
  final Widget? trailing;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final int? minLines;
  final int maxLines;
  final int? maxLength;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextStyle? textStyle;
  final TextStyle? style;
  final TextAlign textAlign;
  final GlassQuality? quality;
  final g1455.GlassFinish? finish;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = textStyle ?? style ?? Theme.of(context).textTheme.bodyMedium;
    final scheme = Theme.of(context).colorScheme;

    return g1455.GlassSurface(
      borderRadius: const BorderRadius.all(Radius.circular(AppRadii.md)),
      finish: finish,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
        child: CupertinoTextField(
          controller: controller,
          focusNode: focusNode,
          placeholder: placeholder,
          placeholderStyle: TextStyle(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          prefix: prefixIcon ?? leading,
          suffix: suffixIcon ?? trailing,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          inputFormatters: inputFormatters,
          minLines: minLines,
          maxLines: maxLines,
          maxLength: maxLength,
          obscureText: obscureText,
          enabled: enabled,
          readOnly: readOnly,
          autofocus: autofocus,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          textAlign: textAlign,
          style: effectiveStyle?.copyWith(
            color: scheme.onSurface,
          ),
          decoration: null,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        ),
      ),
    );
  }
}

/// Material-compatible input API backed by the package's glass text field.
/// This lets existing form flows migrate without changing validation or
/// controllers while keeping input surfaces consistent across routes.
class AppGlassTextField extends StatelessWidget {
  const AppGlassTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.textAlign = TextAlign.start,
    this.style,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final int? minLines;
  final int maxLines;
  final int? maxLength;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextAlign textAlign;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final decorationEnabled = decoration.enabled;
    final effectiveEnabled = enabled && decorationEnabled;
    Widget? suffix = decoration.suffixIcon;
    if (suffix == null && decoration.suffixText != null) {
      suffix = Padding(
        padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
        child: Center(widthFactor: 1, child: Text(decoration.suffixText!)),
      );
    }

    return GlassTextField(
      controller: controller,
      focusNode: focusNode,
      placeholder: decoration.hintText ?? decoration.labelText,
      prefixIcon: decoration.prefixIcon,
      suffixIcon: suffix,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      obscureText: obscureText,
      enabled: effectiveEnabled,
      readOnly: readOnly,
      autofocus: autofocus,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textStyle: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontFamily: Theme.of(context).textTheme.bodyLarge?.fontFamily,
      ).merge(style),
      quality: GlassQuality.standard,
    );
  }
}

class PremiumRow extends StatelessWidget {
  const PremiumRow({
    required this.icon,
    required this.title,
    required this.onTap,
    super.key,
    this.subtitle,
    this.meta,
    this.metaSubtitle,
    this.iconColor,
    this.selected = false,
    this.trailing,
    this.onLongPress,
    this.glass = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? meta;
  final String? metaSubtitle;
  final Color? iconColor;
  final bool selected;
  final Widget? trailing;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Opts this row into a refractive `GlassCard` surface instead of the
  /// default opaque background.
  ///
  /// `PremiumRow` is the app's general-purpose row for scrolling
  /// lists/pickers (accounts, categories, currencies, transactions, ...),
  /// often rendering dozens of instances at once. Per the
  /// `g1455` package guidance, liquid glass is reserved for
  /// navigation/control chrome — dense list rows and scrolling content
  /// should stay opaque, so this defaults to `false`. Only flip it on for a
  /// genuinely standalone/highlighted row rendered a handful of times, not
  /// for list items rendered in bulk.
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final content = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor ?? scheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: scheme.onSurface, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.xxxs),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (meta != null || metaSubtitle != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xxxs,
                        children: [
                          if (meta != null)
                            Text(
                              meta!,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: selected
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          if (metaSubtitle != null)
                            Text(
                              metaSubtitle!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant
                                        .withAlphaFactor(0.8),
                                  ),
                            ),
                        ],
                      ),
                    ],
                    if (trailing != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      trailing!,
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              if (selected)
                Icon(Icons.check_circle_rounded, color: scheme.primary)
              else
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );

    if (glass) {
      return GlassCard(
        margin: EdgeInsets.zero,
        padding: EdgeInsets.zero,
        shape: const LiquidRoundedSuperellipse(borderRadius: AppRadii.md),
        // GlassQuality.standard is the package's own recommended tier for
        // scrollable list rows (lightweight shader, 5-10x faster than
        // BackdropFilter, "works correctly during scrolling"). Reserve
        // `premium` for static, non-scrolling hero surfaces instead.
        quality: GlassQuality.standard,
        clipBehavior: Clip.antiAlias,
        child: content,
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: AppSurfaces.panel(context),

      child: content,
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({
    required this.label,
    required this.value,
    super.key,
    this.icon,
    this.tone = MetricTone.standard,
  });

  final String label;
  final String value;
  final IconData? icon;
  final MetricTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = tone.resolve(scheme, standard: scheme.onSurface);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.xs),
          ],
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppSwitchListTile extends StatelessWidget {
  const AppSwitchListTile({
    required this.title,
    required this.value,
    required this.onChanged,
    super.key,
    this.subtitle,
    this.icon,
    this.secondary,
    this.contentPadding,
  });

  final Widget title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  final Widget? secondary;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    // MergeSemantics combines the title/subtitle text and the Switch's
    // "toggled" state into a single semantics node, matching the platform's
    // own SwitchListTile behavior. Without it, screen readers (TalkBack /
    // VoiceOver) expose the title, subtitle, and switch as separate,
    // disconnected stops instead of one coherent on/off control.
    return MergeSemantics(
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Padding(
          padding:
              contentPadding ??
              const EdgeInsets.symmetric(
                vertical: AppSpacing.sm,
                horizontal: AppSpacing.xs,
              ),
          child: Row(
            children: [
              if (secondary != null) ...[
                secondary!,
                const SizedBox(width: AppSpacing.sm),
              ],
              if (icon != null) ...[
                IconBubble(icon: icon!, compact: true),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextStyle(
                      style: Theme.of(context).textTheme.titleMedium!.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      child: title,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.xxxs),
                      DefaultTextStyle(
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        child: subtitle!,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // ExcludeFocus keeps the switch from claiming its own
              // independent keyboard-focus stop. Without it, the switch's
              // own focusability blocks MergeSemantics from absorbing its
              // toggled/enabled flags into the single merged node below,
              // leaving screen readers without the on/off state — matching
              // the workaround Flutter's own SwitchListTile applies.
              //
              // Use the shared Liquid Glass switch on every platform.
              ExcludeFocus(
                child: IgnorePointer(
                  ignoring: !enabled,
                  child: Opacity(
                    opacity: enabled ? 1 : 0.38,
                    child: GlassSwitch(
                      value: value,
                      onChanged: onChanged ?? (_) {},
                      activeColor: Theme.of(context).colorScheme.primary,
                      useOwnLayer: true,
                      quality: GlassQuality.standard,
                      semanticLabel: '',
                    ),
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

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.tone = MetricTone.standard,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;

  /// [MetricTone.danger] renders the canonical error state (error-tinted
  /// icon bubble). Every other tone keeps the primary-tinted empty state.
  final MetricTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = tone == MetricTone.danger ? scheme.error : scheme.primary;
    final lowerAction = actionLabel?.toLowerCase() ?? '';
    final defaultActionIcon =
        lowerAction.contains('clear') || lowerAction.contains('reset')
        ? Icons.filter_alt_off_rounded
        : (lowerAction.contains('back') || lowerAction.contains('home')
              ? Icons.arrow_back_rounded
              : Icons.add_rounded);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconBubble(icon: icon, color: iconColor),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.md),
                AppActionButton(
                  label: actionLabel!,
                  onPressed: onAction,
                  icon: actionIcon ?? defaultActionIcon,
                  prominent: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class Gap extends StatelessWidget {
  const Gap(this.size, {super.key});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(height: size, width: size);
}

class AppBackAction extends StatelessWidget {
  const AppBackAction({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassHeaderButton(
      icon: Icons.arrow_back_rounded,
      onPressed: () => Navigator.of(context).maybePop(),
      semanticLabel: 'Back',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Canonical helpers. Feature screens use these instead of building their own
// snackbars, confirmation dialogs, sheets, loading states, destructive button
// styles and grouped settings rows. See lib/src/widgets/AGENTS.md.
// ─────────────────────────────────────────────────────────────────────────

/// Canonical transient feedback: floating, and replaces any visible snackbar
/// so rapid actions never queue stale messages.
///
/// `AppTheme.snackBarTheme` deliberately renders snackbars visually
/// suppressed (no floating popups over the bottom island); the message is
/// still exposed to assistive technologies.
void showAppSnackBar(
  BuildContext context,
  String message, {
  SnackBarAction? action,
  Duration? duration,
}) {
  ScaffoldMessenger.maybeOf(
    context,
  )?.showAppSnackBar(message, action: action, duration: duration);
}

extension AppSnackBarMessenger on ScaffoldMessengerState {
  /// Messenger-based variant of [showAppSnackBar] for call sites that capture
  /// the messenger before an `await`.
  void showAppSnackBar(
    String message, {
    SnackBarAction? action,
    Duration? duration,
  }) {
    this
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          action: action,
          duration: duration ?? const Duration(milliseconds: 4000),
        ),
      );
  }
}

/// Canonical button styles for destructive actions at each button level.
/// Use with the Material button that matches the action's hierarchy:
/// `FilledButton` (primary), `OutlinedButton` (secondary), `TextButton`
/// (tertiary).
/// Canonical opaque surface: the surface of `SectionCard(glass: false)`, the
/// opaque `PremiumRow`/`MetricTile` and every untitled panel. Use it instead
/// of re-stating colour/radius/border values.
abstract final class AppSurfaces {
  static Color panelBorderColor(BuildContext context) =>
      Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.55);

  static BoxDecoration panel(
    BuildContext context, {
    double radius = AppRadii.md,
    Color? color,
  }) {
    return BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: panelBorderColor(context)),
    );
  }

  static ShapeBorder panelShape(
    BuildContext context, {
    double radius = AppRadii.md,
  }) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: panelBorderColor(context)),
    );
  }

  /// True on the pure-black AMOLED theme, where refractive glass has nothing
  /// to refract and panels fall back to the opaque surface.
  static bool isAmoled(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor == AppColors.amoledBackground;
}

/// Canonical untitled panel. Opaque by default (dense/scrolling content and
/// anything placed on another glass surface). With [glass] it renders the
/// canonical `GlassCard` instead — except on AMOLED, where it stays opaque.
/// When [onTap]/[onLongPress] are set the ink ripple is clipped to the shape.
class AppPanel extends StatelessWidget {
  const AppPanel({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.onLongPress,
    this.color,
    this.radius = AppRadii.md,
    this.glass = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Overrides the opaque fill (e.g. a status tint). Ignored for glass.
  final Color? color;
  final double radius;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final interactive = onTap != null || onLongPress != null;
    Widget content = Padding(padding: padding, child: child);
    if (glass && !AppSurfaces.isAmoled(context)) {
      if (interactive) {
        content = Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(radius),
            child: content,
          ),
        );
      }
      return GlassCard(
        margin: EdgeInsets.zero,
        padding: EdgeInsets.zero,
        shape: LiquidRoundedSuperellipse(borderRadius: radius),
        quality: GlassQuality.standard,
        clipBehavior: Clip.antiAlias,
        child: content,
      );
    }
    return Material(
      color: color ?? Theme.of(context).colorScheme.surfaceContainerLow,
      shape: AppSurfaces.panelShape(context, radius: radius),
      clipBehavior: Clip.antiAlias,
      child: interactive
          ? InkWell(onTap: onTap, onLongPress: onLongPress, child: content)
          : content,
    );
  }
}

abstract final class AppButtonStyles {
  /// Full-width primary call to action (onboarding, setup, form submit).
  /// Works with any Material button; keeps the theme's stadium shape.
  static const ButtonStyle cta = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size.fromHeight(AppSizes.ctaHeight)),
  );

  /// Dense inline action, e.g. inside a profile card or a list row.
  static ButtonStyle compact(BuildContext context) => ButtonStyle(
    visualDensity: VisualDensity.compact,
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    ),
    textStyle: WidgetStatePropertyAll(Theme.of(context).textTheme.labelMedium),
  );

  static ButtonStyle destructiveFilled(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton.styleFrom(
      backgroundColor: scheme.error,
      foregroundColor: scheme.onError,
    );
  }

  static ButtonStyle destructiveOutlined(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton.styleFrom(
      foregroundColor: scheme.error,
      side: BorderSide(color: scheme.error.withValues(alpha: 0.6)),
    );
  }

  static ButtonStyle destructiveText(BuildContext context) {
    return TextButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.error,
    );
  }
}

/// Authentic iOS-style liquid glass dialog with continuous superellipse corners,
/// blurred glass backdrop refraction, and Cupertino-style action dividers.
class GlassDialog extends StatelessWidget {
  const GlassDialog({
    required this.title,
    super.key,
    this.message,
    this.content,
    this.actions,
    this.icon,
    this.finish,
    this.maxWidth = 320,
    this.scrollable = true,
  });

  final Widget title;
  final Widget? message;
  final Widget? content;
  final List<Widget>? actions;
  final Widget? icon;
  final g1455.GlassFinish? finish;
  final double maxWidth;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dividerColor = theme.dividerColor.withValues(alpha: 0.2);

    Widget innerContent = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          icon!,
          const SizedBox(height: 12),
        ],
        DefaultTextStyle.merge(
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
          child: title,
        ),
        if (message != null) ...[
          const SizedBox(height: 8),
          DefaultTextStyle.merge(
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
            child: message!,
          ),
        ],
        if (content != null) ...[
          const SizedBox(height: 12),
          content!,
        ],
      ],
    );

    if (scrollable) {
      innerContent = SingleChildScrollView(
        child: innerContent,
      );
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: g1455.GlassSurface(
          borderRadius: const BorderRadius.all(Radius.circular(28)),
          finish: finish,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: innerContent,
              ),
              if (actions != null && actions!.isNotEmpty) ...[
                Divider(height: 1, thickness: 1, color: dividerColor),
                IntrinsicHeight(
                  child: actions!.length == 2
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: actions![0]),
                            VerticalDivider(width: 1, thickness: 1, color: dividerColor),
                            Expanded(child: actions![1]),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < actions!.length; i++) ...[
                              if (i > 0)
                                Divider(height: 1, thickness: 1, color: dividerColor),
                              actions![i],
                            ],
                          ],
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

/// Canonical confirmation dialog: title, message, a `TextButton` cancel and a
/// `FilledButton` confirm (error-coloured when [destructive]), presented inside
/// a liquid [GlassDialog].
class AppConfirmDialog extends StatelessWidget {
  const AppConfirmDialog({
    required this.title,
    super.key,
    this.message,
    this.content,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.destructive = false,
    this.icon,
    this.confirmKey,
    this.cancelKey,
  }) : assert(
         message == null || content == null,
         'Provide either message or content, not both.',
       );

  final String title;
  final String? message;
  final Widget? content;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final IconData? icon;
  final Key? confirmKey;
  final Key? cancelKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassDialog(
      icon: icon == null
          ? null
          : Icon(icon, color: destructive ? scheme.error : scheme.primary),
      title: Text(title),
      message: message == null ? null : Text(message!),
      content: content,
      actions: [
        TextButton(
          key: cancelKey,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          key: confirmKey,
          style: destructive
              ? AppButtonStyles.destructiveFilled(context)
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

/// Shows an [AppConfirmDialog] and resolves to `true` only when confirmed.
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  Widget? content,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
  IconData? icon,
  bool barrierDismissible = true,
  Key? confirmKey,
  Key? cancelKey,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (_) => AppConfirmDialog(
      title: title,
      message: message,
      content: content,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
      icon: icon,
      confirmKey: confirmKey,
      cancelKey: cancelKey,
    ),
  );
  return confirmed ?? false;
}

/// Canonical modal bottom sheet presentation. The sheet content owns its
/// surface ([AppSheetSurface] for draggable sheets, or a card/panel for
/// compact sheets), so the route itself is transparent.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double maxWidth = 640,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    elevation: 0,
    constraints: BoxConstraints(maxWidth: maxWidth),
  );
}

/// Drag handle shown at the top of every draggable sheet.
class AppSheetHandle extends StatelessWidget {
  const AppSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(
          top: AppSpacing.sm,
          bottom: AppSpacing.xxs,
        ),
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
      ),
    );
  }
}

/// iOS liquid glass modal sheet surface with continuous rounded top corners
/// and a native iOS drag handle.
class GlassSheet extends StatelessWidget {
  const GlassSheet({
    required this.child,
    this.showHandle = true,
    this.finish,
    this.borderRadius,
    super.key,
  });

  final Widget child;
  final bool showHandle;
  final g1455.GlassFinish? finish;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = borderRadius ??
        const BorderRadius.vertical(top: Radius.circular(AppRadii.xl));
    return g1455.GlassSurface(
      borderRadius: effectiveRadius,
      finish: finish,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showHandle) const AppSheetHandle(),
          Flexible(child: child),
        ],
      ),
    );
  }
}

typedef GlassModalSheet = GlassSheet;

/// Top-rounded liquid glass surface for draggable/full-height bottom sheets.
class AppSheetSurface extends StatelessWidget {
  const AppSheetSurface({
    required this.child,
    super.key,
    this.showHandle = true,
    this.glass = true,
  });

  final Widget child;
  final bool showHandle;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    if (glass) {
      return GlassSheet(
        showHandle: showHandle,
        child: child,
      );
    }

    final content = Column(
      children: [
        if (showHandle) const AppSheetHandle(),
        Expanded(child: child),
      ],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadii.lg),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: content,
    );
  }
}

/// Canonical small inline spinner for buttons, rows and header actions.
class AppInlineSpinner extends StatelessWidget {
  const AppInlineSpinner({super.key, this.size = 18, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CircularProgressIndicator(strokeWidth: 2, color: color),
    );
  }
}

/// Canonical loading state for a page or section that has no content yet.
class AppLoadingState extends StatelessWidget {
  const AppLoadingState({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Canonical grouped settings list (iOS-style inset group). Use with
/// [AppGroupedTile] rows separated by `GlassDivider`.
///
/// Wraps `GlassGroupedSection` so the header uses the app type scale (the
/// package default replaces the inherited text style and drops the app font).
class AppGroupedSection extends StatelessWidget {
  const AppGroupedSection({
    required this.children,
    super.key,
    this.header,
    this.destructive = false,
    this.margin = EdgeInsets.zero,
  });

  final String? header;
  final List<Widget> children;

  /// Tints the header with the error colour (danger zones).
  final bool destructive;

  /// Outer margin. Defaults to none so grouped lists share the content width
  /// of the cards around them (the page supplies the gutters).
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return GlassGroupedSection(
      margin: margin,
      shape: const LiquidRoundedSuperellipse(borderRadius: AppRadii.md),
      header: header == null
          ? null
          : Text(
              header!,
              style: theme.textTheme.labelLarge?.copyWith(
                color: destructive ? scheme.error : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
      children: children,
    );
  }
}

/// Canonical row inside an [AppGroupedSection]. Wraps `GlassListTile` with
/// the app type scale and colour roles.
///
/// Use [AppGroupedTile.toggle] for on/off settings: it merges the row and its
/// switch into one accessible control and toggles on row tap, matching
/// [AppSwitchListTile].
class AppGroupedTile extends StatelessWidget {
  const AppGroupedTile({
    required this.title,
    super.key,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.showChevron = false,
  }) : value = null,
       onChanged = null;

  const AppGroupedTile.toggle({
    required this.title,
    required bool this.value,
    required this.onChanged,
    super.key,
    this.subtitle,
    this.leading,
    this.destructive = false,
  }) : trailing = null,
       onTap = null,
       showChevron = false;

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  /// Adds the canonical disclosure chevron as trailing widget.
  final bool showChevron;

  final bool? value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isToggle = value != null;
    final toggleEnabled = onChanged != null;

    Widget? effectiveTrailing = trailing;
    if (isToggle) {
      effectiveTrailing = ExcludeFocus(
        child: IgnorePointer(
          ignoring: !toggleEnabled,
          child: Opacity(
            opacity: toggleEnabled ? 1 : 0.38,
            child: GlassSwitch(
              value: value!,
              onChanged: onChanged ?? (_) {},
              activeColor: scheme.primary,
              useOwnLayer: true,
              quality: GlassQuality.standard,
              semanticLabel: '',
            ),
          ),
        ),
      );
    } else if (showChevron) {
      effectiveTrailing = Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: destructive ? scheme.error : scheme.onSurfaceVariant,
      );
    }

    final tile = GlassListTile(
      leading: leading,
      leadingIconColor: destructive ? scheme.error : scheme.primary,
      title: title,
      subtitle: subtitle,
      trailing: effectiveTrailing,
      onTap: isToggle
          ? (toggleEnabled ? () => onChanged!(!value!) : null)
          : onTap,
      titleStyle: theme.textTheme.titleMedium?.copyWith(
        color: destructive ? scheme.error : scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      subtitleStyle: theme.textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    );

    return isToggle ? MergeSemantics(child: tile) : tile;
  }
}
