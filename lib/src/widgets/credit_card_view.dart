import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:g1455/g1455.dart' as g1455;

import '../design/tokens.dart';

class CreditCardView extends StatefulWidget {
  final String cardNumber;
  final String expiry;
  final String ccv;
  final String cardHolder;
  final Color gradientStart;
  final Color gradientEnd;
  final String type;
  final String routingNumber;
  final bool isUnlocked;
  final Map<String, String> customFields;

  const CreditCardView({
    super.key,
    this.type = 'card',
    required this.cardNumber,
    required this.expiry,
    required this.ccv,
    this.routingNumber = '',
    required this.cardHolder,
    this.gradientStart = const Color(0xFF111111),
    this.gradientEnd = const Color(0xFF555555),
    this.isUnlocked = false,
    this.customFields = const {},
  });

  @override
  State<CreditCardView> createState() => _CreditCardViewState();
}

class _CreditCardViewState extends State<CreditCardView> {
  Offset _tilt = Offset.zero;

  void _copyToClipboard(BuildContext context, String text, String label) {
    if (text.isEmpty || text == '***' || text.contains('****')) return;
    Clipboard.setData(ClipboardData(text: text.replaceAll(RegExp(r'\s+'), '')));
  }

  /// Contrast colour for text/icons drawn on the user-chosen card colour.
  Color get _foreground =>
      ThemeData.estimateBrightnessForColor(widget.gradientStart) == Brightness.dark
          ? Colors.white
          : Colors.black;

  String _formatCardNumber(String number) {
    final clean = number.replaceAll(RegExp(r'\s+'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < clean.length; i++) {
      buffer.write(clean[i]);
      if ((i + 1) % 4 == 0 && i != clean.length - 1) {
        buffer.write(' ');
      }
    }
    return buffer.toString();
  }

  Widget _buildCopyButton(
    BuildContext context,
    String text,
    String label, {
    Color? color,
  }) {
    if (!widget.isUnlocked || text.isEmpty || text == '***' || text.contains('****')) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        onTap: () => _copyToClipboard(context, text, label),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxs),
          child: Icon(
            Icons.copy_rounded,
            color: color ?? _foreground.withValues(alpha: 0.7),
            size: 16,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayExpiry = widget.isUnlocked ? widget.expiry : (widget.expiry.isEmpty ? '' : 'MM/YY');
    final displayCcv = widget.isUnlocked ? widget.ccv : (widget.ccv.isEmpty ? '' : '***');
    final displayRouting = widget.isUnlocked
        ? widget.routingNumber
        : (widget.routingNumber.isEmpty ? '' : '***');

    final displayNumber = widget.isUnlocked
        ? _formatCardNumber(widget.cardNumber)
        : (widget.cardNumber.isNotEmpty
              ? (widget.type == 'bank'
                    ? '●●●● ●●●● ${widget.cardNumber.substring(math.max(0, widget.cardNumber.length - 4))}'
                    : '**** **** **** ${widget.cardNumber.substring(math.max(0, widget.cardNumber.length - 4))}')
              : (widget.type == 'bank' ? '●●●● ●●●● 0000' : '**** **** **** 0000'));

    final Map<String, String> dynamicFields = {};
    if (displayCcv.isNotEmpty) dynamicFields['CVV'] = displayCcv;
    if (displayRouting.isNotEmpty) {
      dynamicFields['ROUTING NO.'] = displayRouting;
    }
    for (final entry in widget.customFields.entries) {
      if (entry.value.isNotEmpty) {
        dynamicFields[entry.key.toUpperCase()] = entry.value;
      }
    }
    final foreground = _foreground;
    final mutedForeground = foreground.withValues(alpha: 0.54);

    final cardContent = IntrinsicHeight(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(
                widget.type == 'bank'
                    ? Icons.account_balance_rounded
                    : Icons.credit_card_rounded,
                color: foreground,
                size: 32,
              ),
              if (displayExpiry.isNotEmpty)
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'VALID THRU',
                          style: TextStyle(
                            color: mutedForeground,
                            fontSize: 8,
                          ),
                        ),
                        Text(
                          displayExpiry,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    _buildCopyButton(context, widget.expiry, 'expiry'),
                  ],
                ),
            ],
          ),
          const Expanded(child: SizedBox(height: AppSpacing.xxl)),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.type == 'bank')
                      Text(
                        'ACCOUNT NO.',
                        style: TextStyle(color: mutedForeground, fontSize: 8),
                      ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        displayNumber,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 22,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _buildCopyButton(context, widget.cardNumber, 'number'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: AppSpacing.md,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 360),
                padding: const EdgeInsets.only(right: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.type == 'bank' ? 'ACCOUNT HOLDER' : 'CARD HOLDER',
                      style: TextStyle(color: mutedForeground, fontSize: 8),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.cardHolder.isEmpty
                            ? 'YOUR NAME'
                            : widget.cardHolder.toUpperCase(),
                        style: TextStyle(
                          color: foreground,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (dynamicFields.isNotEmpty)
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.xs,
                  alignment: WrapAlignment.end,
                  children: [
                    for (final entry in dynamicFields.entries)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                entry.key,
                                style: TextStyle(
                                  color: mutedForeground,
                                  fontSize: 8,
                                ),
                              ),
                              Text(
                                entry.value,
                                style: TextStyle(
                                  color: foreground,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          _buildCopyButton(context, entry.value, entry.key),
                        ],
                      ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );

    final transform = Matrix4.identity()
      ..setEntry(3, 2, 0.001)
      ..rotateY(_tilt.dx * 0.1)
      ..rotateX(-_tilt.dy * 0.1);

    final gleamCenter = Alignment(
      _tilt.dx * 0.8,
      _tilt.dy * 0.8,
    );

    return Transform(
      transform: transform,
      alignment: Alignment.center,
      child: GestureDetector(
        onPanUpdate: (details) {
          final box = context.findRenderObject() as RenderBox?;
          if (box != null && box.hasSize) {
            final size = box.size;
            final dx = (details.localPosition.dx / size.width - 0.5) * 2;
            final dy = (details.localPosition.dy / size.height - 0.5) * 2;
            setState(() {
              _tilt = Offset(dx.clamp(-1.0, 1.0), dy.clamp(-1.0, 1.0));
            });
          }
        },
        onPanEnd: (_) => setState(() => _tilt = Offset.zero),
        onPanCancel: () => setState(() => _tilt = Offset.zero),
        child: Container(
          width: 400,
          constraints: const BoxConstraints(minHeight: 230),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [widget.gradientStart, widget.gradientEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.26),
                blurRadius: 16,
                offset: Offset(_tilt.dx * 8, 8 + _tilt.dy * 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                // Specular tilt gleam
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: gleamCenter,
                        radius: 1.2,
                        colors: [
                          Colors.white.withValues(alpha: 0.16),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                // Apple Wallet refractive glass surface
                Positioned.fill(
                  child: g1455.GlassSurface(
                    borderRadius: const BorderRadius.all(Radius.circular(20)),
                    finish: g1455.GlassFinish.clear.copyWith(
                      rim: g1455.kCalibratedRim,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: cardContent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
