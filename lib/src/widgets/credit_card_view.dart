import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CreditCardView extends StatefulWidget {
  final String cardNumber;
  final String expiry;
  final String ccv;
  final String cardHolder;
  final Color gradientStart;
  final Color gradientEnd;

  const CreditCardView({
    super.key,
    required this.cardNumber,
    required this.expiry,
    required this.ccv,
    required this.cardHolder,
    this.gradientStart = const Color(0xFF111111),
    this.gradientEnd = const Color(0xFF555555),
  });

  @override
  State<CreditCardView> createState() => _CreditCardViewState();
}

class _CreditCardViewState extends State<CreditCardView>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isFront = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  void _flipCard() {
    if (_isFront) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    _isFront = !_isFront;
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied $text to clipboard')),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _flipCard,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final angle = _controller.value * math.pi;
          final transform = Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle);
          
          return Transform(
            transform: transform,
            alignment: Alignment.center,
            child: angle < math.pi / 2
                ? _buildFront()
                : Transform(
                    transform: Matrix4.identity()..rotateY(math.pi),
                    alignment: Alignment.center,
                    child: _buildBack(),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildFront() {
    return Container(
      width: 400,
      height: 250,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        gradient: LinearGradient(
          colors: [widget.gradientStart, widget.gradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Icon(Icons.credit_card, color: Colors.white),
                IconButton(
                  icon: const Icon(Icons.copy, color: Colors.white, size: 16),
                  onPressed: () => _copyToClipboard(widget.cardNumber),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(widget.cardNumber, style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 2)),
            const Spacer(),
            Text(widget.cardHolder, style: const TextStyle(color: Colors.white, fontSize: 16)),
            Text('EXP: ${widget.expiry}', style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildBack() {
    return Container(
      width: 400,
      height: 250,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        color: Colors.grey[700],
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(height: 50, color: Colors.black),
          const SizedBox(height: 20),
          Container(
            height: 40,
            width: 350,
            color: Colors.white,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(widget.ccv, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.copy, color: Colors.black, size: 16),
                  onPressed: () => _copyToClipboard(widget.ccv),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
