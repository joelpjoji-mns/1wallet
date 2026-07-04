import 'package:flutter/material.dart';

import '../../data/ledger_models.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';

class TransactionRow extends StatelessWidget {
  const TransactionRow({
    required this.state,
    required this.transaction,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
    this.side = 'single',
    super.key,
    this.selectedAccountId,
  });

  final LedgerState state;
  final TransactionRecord transaction;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final String side;
  final String? selectedAccountId;

  @override
  Widget build(BuildContext context) {
    final account = accountById(state, transaction.accountId);
    final counter = accountById(state, transaction.counterAccountId);
    final category = categoryById(state, transaction.categoryId);
    final inactive =
        transaction.status == 'void' || transaction.status == 'paused';
    final color = inactive
        ? Theme.of(context).colorScheme.outline
        : _rowAmountColor(context);
    final amount = _primaryAmount();
    final secondaryTexts = _secondaryAmounts(amount);
    final title = _title(category, account, counter);
    final details = transaction.notes?.trim() ?? '';

    return RepaintBoundary(
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: selected
            ? Theme.of(context).colorScheme.secondaryContainer
            : Theme.of(context).colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          side: BorderSide(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.md),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                IconBubble(
                  icon: category == null || transaction.type == 'transfer'
                      ? transactionIcon(transaction)
                      : categoryIcon(category),
                  color: categoryColor(category, context),
                  compact: true,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: inactive
                              ? Theme.of(context).colorScheme.outline
                              : null,
                          decoration: transaction.status == 'void'
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      Text(
                        _accountLine(account, counter),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (details.isNotEmpty)
                        Text(
                          details,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatSignedMoney(amount),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        decoration: transaction.status == 'void'
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    for (final text in secondaryTexts)
                      Text(
                        text,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    Text(
                      _dateLabel(transaction.occurredAt),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Money _displayAmount() {
    if (side == 'transferOut') {
      return transaction.amount.copyWith(
        amountMinor: -transaction.amount.amountMinor.abs(),
      );
    }
    if (side == 'transferIn') {
      return transaction.counterAmount ?? transaction.amount;
    }
    if (incomeTypes.contains(transaction.type)) return transaction.amount;
    return transaction.amount.copyWith(
      amountMinor: -transaction.amount.amountMinor.abs(),
    );
  }

  Money _primaryAmount() {
    return _displayAmount();
  }

  List<String> _secondaryAmounts(Money primary) {
    final list = <String>[];
    final displayedCurrencies = <String>{primary.currency.toUpperCase()};

    if (side == 'transferOut') {
      final counterAmt = transaction.counterAmount ?? transaction.amount;
      list.add('To ${_formatSignedMoney(counterAmt)}');
      displayedCurrencies.add(counterAmt.currency.toUpperCase());
    } else if (side == 'transferIn') {
      const sign = -1;
      final fromAmt = transaction.amount.copyWith(
        amountMinor: sign * transaction.amount.amountMinor.abs(),
      );
      list.add('From ${_formatSignedMoney(fromAmt)}');
      displayedCurrencies.add(fromAmt.currency.toUpperCase());
    } else if (transaction.originalAmount != null &&
        transaction.originalAmount!.currency.toUpperCase() !=
            primary.currency.toUpperCase()) {
      final sign = primary.amountMinor < 0 ? -1 : 1;
      final originalAmt = transaction.originalAmount!.copyWith(
        amountMinor: sign * transaction.originalAmount!.amountMinor.abs(),
      );
      list.add('Paid ${_formatSignedMoney(originalAmt)}');
      displayedCurrencies.add(originalAmt.currency.toUpperCase());
    }

    final displayCurrency = state.preferences.displayCurrency.toUpperCase();
    final alreadyHasDisplay = displayedCurrencies.contains(displayCurrency);
    if (!alreadyHasDisplay) {
      final converted = convertMoneyForDisplay(state, primary, displayCurrency);
      if (converted.currency.toUpperCase() != primary.currency.toUpperCase()) {
        list.add('≈ ${_formatSignedMoney(converted)}');
      }
    }
    return list;
  }

  Color _rowAmountColor(BuildContext context) {
    if (side == 'transferOut') {
      return amountColor(context, -1);
    }
    if (side == 'transferIn') {
      return amountColor(context, 1);
    }
    return amountColor(context, _primaryAmount().amountMinor);
  }

  String _title(Category? category, Account? account, Account? counter) {
    if (transaction.type == 'transfer') {
      if (side == 'transferIn') {
        return 'Transfer from ${account?.name ?? 'account'}';
      }
      return 'Transfer to ${counter?.name ?? 'account'}';
    }
    final path = categoryPath(state, category);
    return path.isEmpty ? transactionTypeLabel(transaction.type) : path;
  }

  String _accountLine(Account? account, Account? counter) {
    if (transaction.type == 'transfer') {
      return '${account?.name ?? 'Account'} → ${counter?.name ?? 'Account'}';
    }
    return account?.name ?? 'Missing account';
  }

  String _dateLabel(DateTime date) {
    return formatLedgerDate(date, state.preferences.locale);
  }

  String _formatSignedMoney(Money money) {
    final sign = money.amountMinor > 0
        ? '+'
        : money.amountMinor < 0
        ? '-'
        : '';
    return '$sign${formatMoney(money.copyWith(amountMinor: money.amountMinor.abs()), state.preferences.locale)}';
  }
}
