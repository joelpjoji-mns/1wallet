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
    this.headerTrailing,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color? iconColor;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? headerTrailing;
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
              if (headerTrailing != null) ...[
                const SizedBox(width: AppSpacing.xs),
                headerTrailing!,
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
        Flexible(
          child: Text(
            trailing,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: trailingColor, fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class MiniLineChart extends StatefulWidget {
  const MiniLineChart({
    required this.values,
    super.key,
    this.color,
    this.xAxisLabels = const [],
    this.yAxisLabels = const [],
    this.tooltipFormatter,
    this.minY,
    this.maxY,
  });

  final List<num> values;
  final Color? color;
  final List<String> xAxisLabels;
  final List<String> yAxisLabels;
  final String Function(num)? tooltipFormatter;
  final double? minY;
  final double? maxY;

  @override
  State<MiniLineChart> createState() => _MiniLineChartState();
}

class _MiniLineChartState extends State<MiniLineChart> {
  Offset? _touchPosition;

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
      child: GestureDetector(
        onPanDown: (details) =>
            setState(() => _touchPosition = details.localPosition),
        onPanUpdate: (details) =>
            setState(() => _touchPosition = details.localPosition),
        onPanEnd: (details) => setState(() => _touchPosition = null),
        onPanCancel: () => setState(() => _touchPosition = null),
        child: CustomPaint(
          painter: _MiniLineChartPainter(
            values: widget.values.map((value) => value.toDouble()).toList(),
            lineColor: widget.color ?? scheme.primary,
            gridColor: scheme.outlineVariant,
            xAxisLabels: widget.xAxisLabels,
            yAxisLabels: widget.yAxisLabels,
            textColor: scheme.onSurfaceVariant,
            touchPosition: _touchPosition,
            tooltipFormatter: widget.tooltipFormatter,
            minY: widget.minY,
            maxY: widget.maxY,
            context: context,
          ),
          child: const SizedBox.expand(),
        ),
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
    required this.context,
    this.touchPosition,
    this.tooltipFormatter,
    this.minY,
    this.maxY,
  });

  final List<double> values;
  final Color lineColor;
  final Color gridColor;
  final List<String> xAxisLabels;
  final List<String> yAxisLabels;
  final Color textColor;
  final Offset? touchPosition;
  final String Function(num)? tooltipFormatter;
  final double? minY;
  final double? maxY;
  final BuildContext context;

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
    final leftPadding = hasYLabels ? 45.0 : 0.0;
    final chartWidth = size.width - leftPadding;
    final chartHeight = hasXLabels ? size.height - 20 : size.height;

    final paintGrid = Paint()
      ..color = gridColor.withAlphaFactor(0.55)
      ..strokeWidth = 0.7;

    // Draw Y labels and grid
    if (hasYLabels) {
      for (var index = 0; index < yAxisLabels.length; index += 1) {
        final y = chartHeight * index / (yAxisLabels.length - 1);
        canvas.drawLine(
          Offset(leftPadding, y),
          Offset(size.width, y),
          paintGrid,
        );

        final tp = TextPainter(
          text: TextSpan(text: yAxisLabels[index], style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 40);

        tp.paint(canvas, Offset(0, y - tp.height / 2));
      }
    } else {
      for (var index = 1; index < 4; index += 1) {
        final y = chartHeight * index / 4;
        canvas.drawLine(
          Offset(leftPadding, y),
          Offset(size.width, y),
          paintGrid,
        );
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
          x = leftPadding;
        } else if (index == xAxisLabels.length - 1) {
          x = size.width - tp.width;
        } else {
          x =
              leftPadding +
              (chartWidth * index / (xAxisLabels.length - 1)) -
              (tp.width / 2);
        }

        tp.paint(canvas, Offset(x, chartHeight + 5));
      }
    }

    if (values.length < 2) return;

    final actualMin = minY ?? values.reduce(math.min);
    final actualMax = maxY ?? values.reduce(math.max);
    final span = (actualMax - actualMin).abs() < 0.01
        ? 1.0
        : actualMax - actualMin;

    if (actualMin < 0 && actualMax > 0) {
      final normalized0 = (0 - actualMin) / span;
      final y0 = chartHeight - normalized0 * chartHeight;
      final paint0 = Paint()
        ..color = gridColor
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(leftPadding, y0), Offset(size.width, y0), paint0);
    }

    final path = Path();
    for (var index = 0; index < values.length; index += 1) {
      final x = leftPadding + chartWidth * index / (values.length - 1);
      final normalized = (values[index] - actualMin) / span;
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

    if (touchPosition != null &&
        values.isNotEmpty &&
        tooltipFormatter != null) {
      final touchX = touchPosition!.dx.clamp(leftPadding, size.width);
      final progress = (touchX - leftPadding) / chartWidth;
      var nearestIndex = (progress * (values.length - 1)).round();
      nearestIndex = nearestIndex.clamp(0, values.length - 1);

      final x = leftPadding + chartWidth * nearestIndex / (values.length - 1);
      final normalized = (values[nearestIndex] - actualMin) / span;
      final y = chartHeight - normalized * chartHeight;

      final vLinePaint = Paint()
        ..color = textColor.withAlphaFactor(0.5)
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(x, 0), Offset(x, chartHeight), vLinePaint);

      final dotPaint = Paint()..color = lineColor;
      final dotBgPaint = Paint()..color = Theme.of(context).colorScheme.surface;
      canvas.drawCircle(Offset(x, y), 5, dotBgPaint);
      canvas.drawCircle(Offset(x, y), 4, dotPaint);

      final text = tooltipFormatter!(values[nearestIndex]);
      final tpTip = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      var tipX = x - tpTip.width / 2;
      tipX = tipX.clamp(0.0, size.width - tpTip.width);
      var tipY = y - 25;
      if (tipY < 0) tipY = y + 10;

      final bgRect = Rect.fromLTWH(
        tipX - 6,
        tipY - 4,
        tpTip.width + 12,
        tpTip.height + 8,
      );
      final bgRRect = RRect.fromRectAndRadius(bgRect, const Radius.circular(6));
      canvas.drawRRect(
        bgRRect,
        Paint()..color = const Color(0xff1e293b),
      ); // Slate-800

      tpTip.paint(canvas, Offset(tipX, tipY));
    }
  }

  @override
  bool shouldRepaint(covariant _MiniLineChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.xAxisLabels != xAxisLabels ||
        oldDelegate.yAxisLabels != yAxisLabels ||
        oldDelegate.textColor != textColor ||
        oldDelegate.touchPosition != touchPosition;
  }
}
