import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';

class HomeWidgetCard extends StatelessWidget {
  const HomeWidgetCard({
    required this.title,
    required this.icon,
    required this.child,
    super.key,
    this.subtitle,
    this.iconColor,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color? iconColor;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolvedIconColor = iconColor ?? scheme.primary;
    final reorderScope = HomeWidgetCardReorderScope.maybeOf(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              HomeWidgetReorderableIcon(
                icon: icon,
                iconColor: resolvedIconColor,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              if (reorderScope?.reorderMode ?? false) ...[
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  tooltip: 'Move up ${reorderScope!.label}',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  onPressed: reorderScope.canMoveUp
                      ? reorderScope.onMoveUp
                      : null,
                ),
                IconButton(
                  tooltip: 'Move down ${reorderScope.label}',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  onPressed: reorderScope.canMoveDown
                      ? reorderScope.onMoveDown
                      : null,
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(width: AppSpacing.xs),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class HomeWidgetReorderableIcon extends StatelessWidget {
  const HomeWidgetReorderableIcon({
    required this.icon,
    required this.iconColor,
    super.key,
    this.size = 42,
    this.iconSize = 24,
    this.borderRadius = AppRadii.md,
  });

  final IconData icon;
  final Color iconColor;
  final double size;
  final double iconSize;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reorderScope = HomeWidgetCardReorderScope.maybeOf(context);
    Widget leadingIcon = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: iconColor.withAlphaFactor(0.24),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(icon, color: iconColor, size: iconSize),
    );
    if (reorderScope == null) return leadingIcon;

    if (reorderScope.reorderMode) {
      return ReorderableDelayedDragStartListener(
        index: reorderScope.index,
        child: Tooltip(
          message: 'Drag ${reorderScope.label}',
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              leadingIcon,
              Positioned(
                right: -4,
                bottom: -4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    color: scheme.onPrimary,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Tooltip(
      message: 'Long press ${reorderScope.label} to reorder widgets',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: reorderScope.onEnterReorderMode,
        child: leadingIcon,
      ),
    );
  }
}

class HomeWidgetCardReorderScope extends InheritedWidget {
  const HomeWidgetCardReorderScope({
    required this.reorderMode,
    required this.index,
    required this.label,
    required this.onEnterReorderMode,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
    required super.child,
    super.key,
  });

  final bool reorderMode;
  final int index;
  final String label;
  final VoidCallback onEnterReorderMode;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  static HomeWidgetCardReorderScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<HomeWidgetCardReorderScope>();
  }

  @override
  bool updateShouldNotify(HomeWidgetCardReorderScope oldWidget) {
    return reorderMode != oldWidget.reorderMode ||
        index != oldWidget.index ||
        label != oldWidget.label ||
        canMoveUp != oldWidget.canMoveUp ||
        canMoveDown != oldWidget.canMoveDown;
  }
}

class HomeMetricTile extends StatelessWidget {
  const HomeMetricTile({
    required this.label,
    required this.value,
    required this.icon,
    super.key,
    this.tone = MetricTone.standard,
  });

  final String label;
  final String value;
  final IconData icon;
  final MetricTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (tone) {
      MetricTone.positive =>
        Theme.of(context).brightness == Brightness.dark
            ? AppColors.positiveDark
            : AppColors.positiveLight,
      MetricTone.danger => scheme.error,
      MetricTone.warning => scheme.secondary,
      MetricTone.standard => scheme.primary,
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withAlphaFactor(0.24),
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class HomeDetailRow extends StatelessWidget {
  const HomeDetailRow({
    required this.icon,
    required this.title,
    required this.trailing,
    super.key,
    this.subtitle,
    this.iconColor,
    this.tone = MetricTone.standard,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String trailing;
  final Color? iconColor;
  final MetricTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolvedIconColor = iconColor ?? scheme.primary;
    final trailingColor = switch (tone) {
      MetricTone.positive =>
        Theme.of(context).brightness == Brightness.dark
            ? AppColors.positiveDark
            : AppColors.positiveLight,
      MetricTone.danger => scheme.error,
      MetricTone.warning => scheme.secondary,
      MetricTone.standard => scheme.onSurface,
    };
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: resolvedIconColor.withAlphaFactor(0.22),
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          child: Icon(icon, color: resolvedIconColor, size: 19),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          trailing,
          textAlign: TextAlign.end,
          style: TextStyle(color: trailingColor, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class MiniLineChart extends StatelessWidget {
  const MiniLineChart({
    required this.values,
    super.key,
    this.color,
    this.xAxisLabels = const [],
    this.yAxisLabels = const [],
  });

  final List<num> values;
  final Color? color;
  final List<String> xAxisLabels;
  final List<String> yAxisLabels;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 150,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: CustomPaint(
        painter: _MiniLineChartPainter(
          values: values.map((value) => value.toDouble()).toList(),
          lineColor: color ?? scheme.primary,
          gridColor: scheme.outlineVariant,
          xAxisLabels: xAxisLabels,
          yAxisLabels: yAxisLabels,
          textColor: scheme.onSurfaceVariant,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}


class _MiniLineChartPainter extends CustomPainter {
  const _MiniLineChartPainter({
    required this.values,
    required this.lineColor,
    required this.gridColor,
    required this.xAxisLabels,
    required this.yAxisLabels,
    required this.textColor,
  });

  final List<double> values;
  final Color lineColor;
  final Color gridColor;
  final List<String> xAxisLabels;
  final List<String> yAxisLabels;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    final hasYLabels = yAxisLabels.isNotEmpty;
    final hasXLabels = xAxisLabels.isNotEmpty;

    final labelStyle = TextStyle(
      color: textColor,
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );

    // Calculate chart area
    final chartWidth = hasYLabels ? size.width - 55 : size.width;
    final chartHeight = hasXLabels ? size.height - 20 : size.height;

    final paintGrid = Paint()
      ..color = gridColor.withAlphaFactor(0.55)
      ..strokeWidth = 0.7;

    // Draw Y labels and grid
    if (hasYLabels) {
      for (var index = 0; index < yAxisLabels.length; index += 1) {
        final y = chartHeight * index / (yAxisLabels.length - 1);
        canvas.drawLine(Offset(0, y), Offset(chartWidth, y), paintGrid);

        final tp = TextPainter(
          text: TextSpan(text: yAxisLabels[index], style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 50);

        tp.paint(canvas, Offset(chartWidth + 5, y - tp.height / 2));
      }
    } else {
      for (var index = 1; index < 4; index += 1) {
        final y = chartHeight * index / 4;
        canvas.drawLine(Offset(0, y), Offset(chartWidth, y), paintGrid);
      }
    }

    // Draw X labels
    if (hasXLabels) {
      for (var index = 0; index < xAxisLabels.length; index += 1) {
        final tp = TextPainter(
          text: TextSpan(text: xAxisLabels[index], style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();

        double x;
        if (index == 0) {
          x = 0;
        } else if (index == xAxisLabels.length - 1) {
          x = chartWidth - tp.width;
        } else {
          x = (chartWidth * index / (xAxisLabels.length - 1)) - (tp.width / 2);
        }

        tp.paint(canvas, Offset(x, chartHeight + 5));
      }
    }

    if (values.length < 2) return;

    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    final span = (maxValue - minValue).abs() < 0.01 ? 1.0 : maxValue - minValue;
    final path = Path();
    for (var index = 0; index < values.length; index += 1) {
      final x = chartWidth * index / (values.length - 1);
      final normalized = (values[index] - minValue) / span;
      final y = chartHeight - normalized * chartHeight;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final shadowPaint = Paint()
      ..color = lineColor.withAlphaFactor(0.18)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, shadowPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _MiniLineChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.xAxisLabels != xAxisLabels ||
        oldDelegate.yAxisLabels != yAxisLabels ||
        oldDelegate.textColor != textColor;
  }
}
