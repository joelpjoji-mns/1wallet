import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ledger_models.dart';
import '../data/ledger_providers.dart';

/// Replaces every digit in [formatted] with a bullet ('•'), while preserving
/// currency symbols, grouping separators, decimal points, signs and suffixes
/// (e.g. K/L/Cr). This masks the actual figures for Privacy mode while still
/// reflecting the number of digits, so the mask looks uniform everywhere:
///
///   `$1,234.56`  ->  `$•,•••.••`
///   `-₹1,20,000` ->  `-₹•,••,•••`
///   `€1.2K`      ->  `€•.•K`
String maskAmountDigits(String formatted) {
  final buffer = StringBuffer();
  for (final unit in formatted.codeUnits) {
    // Mask ASCII digits 0-9; leave everything else (symbols, separators,
    // signs, letters) intact so the value keeps its recognizable shape.
    if (unit >= 0x30 && unit <= 0x39) {
      buffer.write('•');
    } else {
      buffer.writeCharCode(unit);
    }
  }
  return buffer.toString();
}

/// Returns [formatted] normally, or a digit-masked version when the user has
/// enabled Privacy mode. Use this for string-based UI (e.g. `PremiumRow.meta`)
/// where a [PrivacyText] widget can't be inserted. Pass [mask] to force a fixed
/// mask string instead of the per-digit mask.
String maskMoneyIfPrivate(
  LedgerState state,
  String formatted, {
  String? mask,
}) =>
    state.preferences.privacyModeEnabled
        ? (mask ?? maskAmountDigits(formatted))
        : formatted;

/// Displays a (usually monetary) string that is hidden when the user enables
/// Privacy mode (`preferences.privacyModeEnabled`). When privacy is on the
/// digits are replaced with bullets (see [maskAmountDigits]) so sensitive
/// balances/amounts are not shown, while preserving the surrounding layout and
/// text style. Pass [mask] to force a fixed mask string instead.
class PrivacyText extends ConsumerWidget {
  const PrivacyText(
    this.text, {
    this.style,
    this.textAlign,
    this.overflow,
    this.maxLines,
    this.mask,
    super.key,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextOverflow? overflow;
  final int? maxLines;
  final String? mask;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(
      ledgerProvider.select((state) => state.preferences.privacyModeEnabled),
    );
    return Text(
      hidden ? (mask ?? maskAmountDigits(text)) : text,
      style: style,
      textAlign: textAlign,
      overflow: overflow,
      maxLines: maxLines,
    );
  }
}
