import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/tokens.dart';

/// A measured, non-modal coach mark. Only the small card intercepts input.
class DiscoveryCoachMark extends StatefulWidget {
  const DiscoveryCoachMark({
    required this.title,
    required this.message,
    required this.onClose,
    required this.actions,
    this.target,
    this.counter,
    this.sample,
    super.key,
  });

  final GlobalKey? target;
  final String title;
  final String message;
  final String? counter;
  final VoidCallback onClose;
  final Widget actions;
  final Widget? sample;

  @override
  State<DiscoveryCoachMark> createState() => _DiscoveryCoachMarkState();
}

class _DiscoveryCoachMarkState extends State<DiscoveryCoachMark>
    with SingleTickerProviderStateMixin {
  final _overlayKey = GlobalKey();
  final _cardKey = GlobalKey();
  late final AnimationController _motion;
  Timer? _measureTimer;
  Rect? _target;
  Rect? _cardRect;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _measureTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _measure(),
    );
    _reveal();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.stop();
    } else if (!_motion.isAnimating) {
      _motion.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant DiscoveryCoachMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.target != oldWidget.target) _reveal();
  }

  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetContext = widget.target?.currentContext;
      final scrollable = targetContext == null
          ? null
          : Scrollable.maybeOf(targetContext);
      final renderTarget = targetContext?.findRenderObject();
      if (scrollable != null &&
          axisDirectionToAxis(scrollable.axisDirection) == Axis.vertical &&
          renderTarget != null &&
          renderTarget.attached) {
        scrollable.position.ensureVisible(
          renderTarget,
          alignment: 0.35,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
        );
      }
      _measure();
    });
  }

  void _measure() {
    if (!mounted) return;
    final target = widget.target?.currentContext?.findRenderObject();
    final overlay = _overlayKey.currentContext?.findRenderObject();
    Rect? next;
    if (target is RenderBox &&
        target.attached &&
        target.hasSize &&
        overlay is RenderBox &&
        overlay.attached &&
        overlay.hasSize) {
      final offset =
          target.localToGlobal(Offset.zero) -
          overlay.localToGlobal(Offset.zero);
      if (offset.dx.isFinite && offset.dy.isFinite) {
        final rect = (offset & target.size).inflate(AppSpacing.xxs);
        next = rect.intersect(Offset.zero & overlay.size);
        if (next.isEmpty) next = null;
      }
    }
    final card = _cardKey.currentContext?.findRenderObject();
    Rect? cardRect;
    if (card is RenderBox &&
        card.attached &&
        card.hasSize &&
        overlay is RenderBox &&
        overlay.attached &&
        overlay.hasSize) {
      cardRect =
          (card.localToGlobal(Offset.zero) -
              overlay.localToGlobal(Offset.zero)) &
          card.size;
    }
    if (next != _target || cardRect != _cardRect) {
      setState(() {
        _target = next;
        _cardRect = cardRect;
      });
    }
  }

  @override
  void dispose() {
    _measureTimer?.cancel();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    key: _overlayKey,
    builder: (context, constraints) {
      final safe = MediaQuery.paddingOf(context);
      final keyboard = MediaQuery.viewInsetsOf(context).bottom;
      final bounds = Rect.fromLTRB(
        safe.left + AppSpacing.sm,
        safe.top + AppSpacing.sm,
        math.max(
          safe.left + AppSpacing.sm,
          constraints.maxWidth - safe.right - AppSpacing.sm,
        ),
        math.max(
          safe.top + AppSpacing.sm,
          constraints.maxHeight -
              math.max(safe.bottom, keyboard) -
              AppSpacing.sm,
        ),
      );
      if (bounds.isEmpty) return const SizedBox.shrink();
      final target = _target;
      final areas = target == null
          ? <Rect>[]
          : [
              Rect.fromLTRB(
                bounds.left,
                bounds.top,
                bounds.right,
                math.min(bounds.bottom, target.top - AppSpacing.sm),
              ),
              Rect.fromLTRB(
                bounds.left,
                math.max(bounds.top, target.bottom + AppSpacing.sm),
                bounds.right,
                bounds.bottom,
              ),
              Rect.fromLTRB(
                bounds.left,
                bounds.top,
                math.min(bounds.right, target.left - AppSpacing.sm),
                bounds.bottom,
              ),
              Rect.fromLTRB(
                math.max(bounds.left, target.right + AppSpacing.sm),
                bounds.top,
                bounds.right,
                bounds.bottom,
              ),
            ].where((area) => area.width >= 180 && area.height >= 100).toList();
      areas.sort(
        (a, b) => (b.width * math.min(b.height, 260)).compareTo(
          a.width * math.min(a.height, 260),
        ),
      );
      final area = areas.isEmpty ? bounds : areas.first;
      final width = math.min(320.0, area.width);
      final height = math.min(
        area.height,
        math.max(180.0, bounds.height * 0.45),
      );
      final left =
          (target?.center.dx ?? bounds.center.dx).clamp(
            area.left + width / 2,
            area.right - width / 2,
          ) -
          width / 2;
      final top = target != null && area.bottom <= target.top
          ? area.bottom - height
          : area.top;
      final card = Rect.fromLTWH(left, top, width, height);
      final scheme = Theme.of(context).colorScheme;
      return Stack(
        children: [
          if (target != null && areas.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _motion,
                  builder: (context, _) => CustomPaint(
                    painter: _CoachPointer(
                      target: target,
                      card: _cardRect ?? card,
                      color: scheme.primary,
                      scrim: scheme.scrim.withValues(alpha: 0.16),
                      pulse: _motion.value,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: card.left,
            top: card.top,
            width: card.width,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: card.height),
              child: Material(
                key: _cardKey,
                color: scheme.surfaceContainerHigh.withValues(alpha: 0.96),
                elevation: 8,
                shadowColor: scheme.shadow.withValues(alpha: 0.22),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  side: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.pill,
                                  ),
                                ),
                                child: Text(
                                  widget.counter ?? '1Wallet guide',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11,
                                      ),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            padding: EdgeInsets.zero,
                            tooltip: 'Close guide',
                            onPressed: widget.onClose,
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ],
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Semantics(
                            liveRegion: true,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.2,
                                      ),
                                ),
                                const SizedBox(height: AppSpacing.xxs),
                                Text(
                                  widget.message,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                        height: 1.35,
                                      ),
                                ),
                                if (widget.sample != null) ...[
                                  const SizedBox(height: AppSpacing.xs),
                                  widget.sample!,
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      widget.actions,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _CoachPointer extends CustomPainter {
  const _CoachPointer({
    required this.target,
    required this.card,
    required this.color,
    required this.scrim,
    required this.pulse,
  });

  final Rect target;
  final Rect card;
  final Color color;
  final Color scrim;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final shade = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(
        RRect.fromRectAndRadius(target, const Radius.circular(AppRadii.md)),
      )
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(shade, Paint()..color = scrim);

    // Glowing pulsing spotlight ring around target
    final pulseOffset = 1.5 + pulse * 2.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        target.inflate(pulseOffset),
        const Radius.circular(AppRadii.md + 2),
      ),
      Paint()
        ..color = color.withValues(alpha: 0.35 + pulse * 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final Offset from;
    final Offset to;
    if (card.bottom <= target.top || card.top >= target.bottom) {
      final below = card.bottom <= target.top;
      from = Offset(
        target.center.dx.clamp(card.left + 12, card.right - 12),
        below ? card.bottom : card.top,
      );
      to = Offset(
        from.dx.clamp(target.left, target.right),
        below ? target.top : target.bottom,
      );
    } else {
      final right = card.right <= target.left;
      from = Offset(
        right ? card.right : card.left,
        target.center.dy.clamp(card.top + 12, card.bottom - 12),
      );
      to = Offset(
        right ? target.left : target.right,
        from.dy.clamp(target.top, target.bottom),
      );
    }
    final delta = to - from;
    if (delta.distance < 6) return;
    final unit = delta / delta.distance;
    final tip = to - unit * (2 + pulse * 3);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(from, tip, paint);
    final side = Offset(-unit.dy, unit.dx);
    canvas.drawPath(
      Path()
        ..moveTo((tip - unit * 6 + side * 4).dx, (tip - unit * 6 + side * 4).dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(
          (tip - unit * 6 - side * 4).dx,
          (tip - unit * 6 - side * 4).dy,
        ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_CoachPointer oldDelegate) =>
      target != oldDelegate.target ||
      card != oldDelegate.card ||
      color != oldDelegate.color ||
      scrim != oldDelegate.scrim ||
      pulse != oldDelegate.pulse;
}
