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
            actionLabel: 'Add',
            onAction: () => _addCurrency(context, ref, state),
            child: Column(
              children: [
                for (final currency in currencies) ...[
                  Dismissible(
                    key: ValueKey(currency),
                    direction: currency == state.preferences.baseCurrency
                        ? DismissDirection.none
                        : DismissDirection.endToStart,
                    onDismissed: (_) {
                      ref.read(ledgerProvider.notifier).removeEnabledCurrency(currency);
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(content: Text('$currency removed from explicitly enabled list.'), behavior: SnackBarBehavior.floating),
                        );
                    },
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error,
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                      ),
                      child: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.onError),
                    ),
                    child: PremiumRow(
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
                for (final currency in currencies)
                  if (currency != state.preferences.baseCurrency) ...[
                    PremiumRow(
                      icon: Icons.swap_horiz_rounded,
                      title: '$currency to ${state.preferences.baseCurrency}',
                      subtitle: _rateSubtitle(state, currency),
                      onTap: () => _editRate(context, ref, state, currency),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                if (currencies.length <= 1)
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Text('Add another currency to set exchange rates.'),
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

  Future<void> _addCurrency(BuildContext context, WidgetRef ref, LedgerState state) async {
    final next = await showFullScreenPicker<String>(
      context: context,
      title: 'Add Currency',
      searchHint: 'Search currencies',
      options: [
        for (final currency in {
          'USD', 'EUR', 'GBP', 'INR', 'JPY', 'CAD', 'AUD', 'SGD', 'CHF', 'CNY', 'NZD', 'ZAR'
        }.where((c) => !state.preferences.enabledCurrencies.contains(c)).toList()..sort())
          PickerOption(
            value: currency,
            title: currency,
            icon: Icons.add_circle_outline,
          ),
      ],
    );
    if (next != null) {
      await ref.read(ledgerProvider.notifier).addEnabledCurrency(next);
    }
  }

  String _rateSubtitle(LedgerState state, String currency) {
    final rate = latestExchangeRate(state, currency, state.preferences.baseCurrency);
    if (rate != null) return '1 $currency = ${rate.rate} ${state.preferences.baseCurrency}';
    final inferred = rateBetween(state, currency, state.preferences.baseCurrency);
    if (inferred != null) {
      return 'Inferred: 1 $currency = ${inferred.toStringAsFixed(4)} ${state.preferences.baseCurrency}';
    }
    return 'Not set. Tap to set explicit rate.';
  }

  Future<void> _editRate(BuildContext context, WidgetRef ref, LedgerState state, String currency) async {
    final controller = TextEditingController();
    final rate = latestExchangeRate(state, currency, state.preferences.baseCurrency);
    if (rate != null) controller.text = rate.rate.toString();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set rate for $currency'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: '1 $currency = ? ${state.preferences.baseCurrency}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final value = double.tryParse(result);
      if (value != null && value > 0) {
        await ref.read(ledgerProvider.notifier).setExchangeRate(
          base: currency,
          quote: state.preferences.baseCurrency,
          rate: value,
        );
      }
    }
  }
}
