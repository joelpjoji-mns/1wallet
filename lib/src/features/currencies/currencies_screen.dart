import 'package:flutter/material.dart';
import '../common/route_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../common/full_screen_picker.dart';

class CurrenciesScreen extends ConsumerWidget {
  const CurrenciesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ledgerProvider);
    final currencies = availableCurrencies(state);
    final total = totalBalance(state);
    return RouteScaffold(
      title: 'Currencies',
      actions: [
        IconButton(
          tooltip: 'Choose display currency',
          icon: const Icon(Icons.currency_exchange_rounded),
          onPressed: () => _chooseDisplayCurrency(context, ref, state),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: 'Display currency',
            subtitle:
                'Totals and approximate secondary values use this currency.',
            actionLabel: 'Change',
            onAction: () => _chooseDisplayCurrency(context, ref, state),
            child: Row(
              children: [
                Expanded(
                  child: MetricTile(
                    label: 'Current',
                    value: state.preferences.displayCurrency,
                    icon: Icons.currency_exchange_outlined,
                    compact: true,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: MetricTile(
                    label: 'Total',
                    value: formatMoney(total, state.preferences.locale),
                    icon: Icons.account_balance_wallet_outlined,
                    compact: true,
                  ),
                ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Available currencies',
            subtitle:
                'Collected from preferences, accounts, transactions, original amounts, and rates.',
            child: Column(
              children: [
                for (final currency in currencies) ...[
                  PremiumRow(
                    icon: currency == state.preferences.baseCurrency
                        ? Icons.flag_outlined
                        : Icons.currency_exchange_outlined,
                    title: currency,
                    subtitle: _currencySubtitle(state, currency),
                    selected: currency == state.preferences.displayCurrency,
                    onTap: () => ref
                        .read(ledgerProvider.notifier)
                        .setDisplayCurrency(currency),
                  ),
                  if (currency != currencies.last)
                    const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Rates',
            subtitle: state.exchangeRates.isEmpty
                ? 'No explicit rates saved; inferred ledger rates are used when possible.'
                : '${state.exchangeRates.length} explicit rate records saved.',
            child: Column(
              children: [
                InfoRow(
                  label: 'Base currency',
                  value: state.preferences.baseCurrency,
                  icon: Icons.flag_outlined,
                ),
                InfoRow(
                  label: 'Enabled',
                  value: state.preferences.enabledCurrencies.join(', '),
                  icon: Icons.check_circle_outline,
                ),
                InfoRow(
                  label: 'Ledger currencies',
                  value: currencies.join(', '),
                  icon: Icons.account_tree_outlined,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseDisplayCurrency(
    BuildContext context,
    WidgetRef ref,
    LedgerState state,
  ) async {
    final next = await showFullScreenPicker<String>(
      context: context,
      title: 'Display currency',
      searchHint: 'Search currencies',
      selectedValue: state.preferences.displayCurrency,
      options: [
        for (final currency in availableCurrencies(state))
          PickerOption(
            value: currency,
            title: currency,
            subtitle: _currencySubtitle(state, currency),
            icon: currency == state.preferences.baseCurrency
                ? Icons.flag_outlined
                : Icons.currency_exchange_outlined,
          ),
      ],
    );
    if (next == null) return;
    await ref.read(ledgerProvider.notifier).setDisplayCurrency(next);
  }

  String _currencySubtitle(LedgerState state, String currency) {
    final parts = <String>[];
    if (currency == state.preferences.baseCurrency) parts.add('Base');
    if (currency == state.preferences.displayCurrency) parts.add('Display');
    if (state.preferences.enabledCurrencies.contains(currency)) {
      parts.add('Enabled');
    }
    final accountCount = state.accounts
        .where((account) => account.currency.toUpperCase() == currency)
        .length;
    if (accountCount > 0) parts.add('$accountCount account(s)');
    final movementCount = state.transactions
        .where(
          (transaction) =>
              transaction.amount.currency.toUpperCase() == currency ||
              transaction.baseAmount.currency.toUpperCase() == currency ||
              transaction.originalAmount?.currency.toUpperCase() == currency ||
              transaction.counterAmount?.currency.toUpperCase() == currency,
        )
        .length;
    if (movementCount > 0) parts.add('$movementCount movement(s)');
    return parts.isEmpty ? 'Available for display' : parts.join(' · ');
  }
}
