import 'dart:math' as math;
import 'package:flutter/material.dart';

class LiquidProgressIndicator extends StatefulWidget {
  final double value;
  final Color color;
  final Color backgroundColor;

  const LiquidProgressIndicator({
    super.key,
    required this.value,
    this.color = Colors.blue,
    this.backgroundColor = Colors.transparent,
  });

  @override
  State<LiquidProgressIndicator> createState() =>
      _LiquidProgressIndicatorState();
}

class _LiquidProgressIndicatorState extends State<LiquidProgressIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _LiquidPainter(
            value: widget.value,
            color: widget.color,
            phase: _controller.value * 2 * math.pi,
          ),
        );
      },
    );
  }
}

class _LiquidPainter extends CustomPainter {
  final double value;
  final Color color;
  final double phase;

  _LiquidPainter({
    required this.value,
    required this.color,
    required this.phase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    final waveHeight = size.height * 0.1;
    final yOffset = size.height * (1 - value);

    path.moveTo(0, size.height);
    path.lineTo(0, yOffset);

    for (double i = 0; i <= size.width; i++) {
      path.lineTo(
        i,
        yOffset + math.sin((i / size.width * 2 * math.pi) + phase) * waveHeight,
      );
    }

    path.lineTo(size.width, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_LiquidPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.phase != phase;
}
