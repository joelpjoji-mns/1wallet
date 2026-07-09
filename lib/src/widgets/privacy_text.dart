import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ledger_models.dart';
import '../data/ledger_providers.dart';

/// Returns [formatted] normally, or a neutral mask when the user has enabled
/// Privacy mode. Use this for string-based UI (e.g. `PremiumRow.meta`) where a
/// [PrivacyText] widget can't be inserted.
String maskMoneyIfPrivate(
  LedgerState state,
  String formatted, {
  String mask = '••••',
}) =>
    state.preferences.privacyModeEnabled ? mask : formatted;

/// Displays a (usually monetary) string that is hidden when the user enables
/// Privacy mode (`preferences.privacyModeEnabled`). When privacy is on the
/// value is replaced with a neutral mask so sensitive balances/amounts are not
/// shown, while preserving the surrounding layout and text style.
class PrivacyText extends ConsumerWidget {
  const PrivacyText(
    this.text, {
    this.style,
    this.textAlign,
    this.overflow,
    this.maxLines,
    this.mask = '••••',
    super.key,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextOverflow? overflow;
  final int? maxLines;
  final String mask;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(
      ledgerProvider.select((state) => state.preferences.privacyModeEnabled),
    );
    return Text(
      hidden ? mask : text,
      style: style,
      textAlign: textAlign,
      overflow: overflow,
      maxLines: maxLines,
    );
  }
}
