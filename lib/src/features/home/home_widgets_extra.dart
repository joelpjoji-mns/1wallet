import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/ledger_models.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/privacy_text.dart';
import 'home_widget_card.dart';

class NetWorthHomeWidget extends StatelessWidget {
  const NetWorthHomeWidget({required this.state, super.key});

  final LedgerState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final locale = state.preferences.locale;
    final worth = netWorth(state);
    final assets = worth.assets.amountMinor;
    final liabilities = worth.liabilities.amountMinor.abs();
    final denom = assets + liabilities;
    final assetFlex = denom > 0
        ? (assets / denom * 100).round().clamp(0, 100)
        : 100;
    final liabFlex = 100 - assetFlex;
    final positiveColor = positiveTone(context);

    return HomeWidgetCard(
      title: 'Net worth',
      subtitle: 'What you own minus what you owe',
      icon: Icons.account_balance_outlined,
      actionLabel: 'Trend',
      onAction: () => context.push('/balance-trend'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PrivacyText(
            formatMoney(worth.total, locale),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: worth.total.amountMinor >= 0
                  ? scheme.primary
                  : scheme.error,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (denom > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: Row(
                children: [
                  if (assetFlex > 0)
                    Expanded(
                      flex: assetFlex,
                      child: Container(height: 8, color: positiveColor),
                    ),
                  if (liabFlex > 0)
                    Expanded(
                      flex: liabFlex,
                      child: Container(
                        height: 8,
                        color: scheme.error.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _LabeledAmount(
                  label: 'Assets',
                  money: worth.assets,
                  locale: locale,
                  color: positiveColor,
                ),
              ),
              Expanded(
                child: _LabeledAmount(
                  label: 'You owe',
                  money: Money(
                    amountMinor: liabilities,
                    currency: worth.liabilities.currency,
                  ),
                  locale: locale,
                  color: scheme.error,
                  alignEnd: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LabeledAmount extends StatelessWidget {
  const _LabeledAmount({
    required this.label,
    required this.money,
    required this.locale,
    required this.color,
    this.alignEnd = false,
  });

  final String label;
  final Money money;
  final String locale;
  final Color color;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: scheme.onSurfaceVariant,
          ),
        ),
        PrivacyText(
          formatMoney(money, locale),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
