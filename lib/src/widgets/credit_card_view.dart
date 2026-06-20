import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CreditCardView extends StatelessWidget {
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

  void _copyToClipboard(BuildContext context, String text, String label) {
    if (text.isEmpty || text == '***' || text.contains('****')) return;
    Clipboard.setData(ClipboardData(text: text.replaceAll(RegExp(r'\s+'), '')));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Copied $label to clipboard'), behavior: SnackBarBehavior.floating),
      );
  }

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

  Widget _buildCopyButton(BuildContext context, String text, String label, {Color color = Colors.white70}) {
    if (!isUnlocked || text.isEmpty || text == '***' || text.contains('****')) return const SizedBox.shrink();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _copyToClipboard(context, text, label),
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: Icon(Icons.copy, color: color, size: 16),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayExpiry = isUnlocked ? expiry : (expiry.isEmpty ? '' : 'MM/YY');
    final displayCcv = isUnlocked ? ccv : (ccv.isEmpty ? '' : '***');
    final displayRouting = isUnlocked ? routingNumber : (routingNumber.isEmpty ? '' : '***');
    
    final displayNumber = isUnlocked 
        ? _formatCardNumber(cardNumber) 
        : (cardNumber.isNotEmpty 
            ? (type == 'bank' ? '●●●● ●●●● ${cardNumber.substring(math.max(0, cardNumber.length - 4))}' : '**** **** **** ${cardNumber.substring(math.max(0, cardNumber.length - 4))}')
            : (type == 'bank' ? '●●●● ●●●● 0000' : '**** **** **** 0000'));
            
    final Map<String, String> dynamicFields = {};
    if (displayCcv.isNotEmpty) dynamicFields['CVV'] = displayCcv;
    if (displayRouting.isNotEmpty) dynamicFields['ROUTING NO.'] = displayRouting;
    for (final entry in customFields.entries) {
      if (entry.value.isNotEmpty) dynamicFields[entry.key.toUpperCase()] = entry.value;
    }

    return Container(
      width: 400,
      constraints: const BoxConstraints(minHeight: 230),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [gradientStart, gradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5))],
      ),
      child: IntrinsicHeight(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(type == 'bank' ? Icons.account_balance : Icons.credit_card, color: Colors.white, size: 32),
                if (displayExpiry.isNotEmpty)
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('VALID THRU', style: TextStyle(color: Colors.white54, fontSize: 8)),
                          Text(displayExpiry, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(width: 4),
                      _buildCopyButton(context, expiry, 'expiry'),
                    ],
                  ),
              ],
            ),
            const Expanded(child: SizedBox(height: 30)),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (type == 'bank') const Text('ACCOUNT NO.', style: TextStyle(color: Colors.white54, fontSize: 8)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          displayNumber,
                          style: const TextStyle(color: Colors.white, fontSize: 22, letterSpacing: 2, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                _buildCopyButton(context, cardNumber, 'number'),
              ],
            ),
            const SizedBox(height: 15),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.start,
              runSpacing: 15,
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 360),
                  padding: const EdgeInsets.only(right: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(type == 'bank' ? 'ACCOUNT HOLDER' : 'CARD HOLDER', style: const TextStyle(color: Colors.white54, fontSize: 8)),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          cardHolder.isEmpty ? 'YOUR NAME' : cardHolder.toUpperCase(), 
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                if (dynamicFields.isNotEmpty)
                  Wrap(
                    spacing: 16,
                    runSpacing: 10,
                    alignment: WrapAlignment.end,
                    children: [
                      for (final entry in dynamicFields.entries)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(entry.key, style: const TextStyle(color: Colors.white54, fontSize: 8)),
                                Text(entry.value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            const SizedBox(width: 4),
                            _buildCopyButton(context, entry.value, entry.key),
                          ],
                        ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
