import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/liquid_progress_indicator.dart';
import '../../widgets/app_kit.dart';
import '../transactions/transactions_components.dart';

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({required this.onMenuPressed, super.key});

  final VoidCallback onMenuPressed;

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  var _query = '';
  var _showExcluded = true;
  var _showArchived = false;
  List<String>? _order;
  double _liquidValue = 0.5;
  final _inputController = TextEditingController(text: '0.5');

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerProvider);
    
    // Initialize or update _order
    _order ??= [];
    final currentIds = state.accounts.map((a) => a.id).toSet();
    _order!.removeWhere((id) => !currentIds.contains(id));
    final existingIds = _order!.toSet();
    
    final sortedAccounts = state.accounts.toList()
      ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    for (final acc in sortedAccounts) {
      if (!existingIds.contains(acc.id)) {
        _order!.add(acc.id);
      }
    }

    final rows = _filteredRows(state);

    return AppScreen(
      title: 'Accounts',
      onMenuPressed: widget.onMenuPressed,
      scrollable: false,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        0,
      ),
      actions: [
        HeaderIconButton(
          icon: Icons.credit_card_outlined,
          onPressed: () => context.push('/cards'),
        ),
        HeaderIconButton(
          icon: Icons.account_balance_outlined,
          onPressed: () => context.push('/loans'),
        ),
      ],
      child: Column(
        children: [
          SizedBox(
            height: 100,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: LiquidProgressIndicator(
                value: _liquidValue,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: TextField(
              controller: _inputController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Liquid Progress (0.0 - 1.0)'),
              onChanged: (val) {
                final parsed = double.tryParse(val);
                if (parsed != null && parsed >= 0 && parsed <= 1) {
                  setState(() => _liquidValue = parsed);
                }
              },
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CompactSearchField(
                    value: _query,
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterPill(
                          icon: Icons.balance_outlined,
                          label: _showExcluded ? 'Include excluded' : 'Totals only',
                          active: _showExcluded,
                          onTap: () => setState(() => _showExcluded = !_showExcluded),
                        ),
                        FilterPill(
                          icon: Icons.archive_outlined,
                          label: _showArchived ? 'All accounts' : 'Active only',
                          active: _showArchived,
                          onTap: () => setState(() => _showArchived = !_showArchived),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _CurrencySummaryHeader(state: state, accounts: rows),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Accounts\n${rows.length} in current order',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => context.push('/account/new'),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add account'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: rows.isEmpty
                ? const EmptyState(
                    icon: Icons.wallet_outlined,
                    title: 'No accounts found',
                    body:
                        'Add a cash, bank, card, loan, or wallet account to start tracking.',
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.only(
                      bottom: AppSizes.bottomBarClearance + AppSpacing.xl,
                    ),
                    itemCount: rows.length,
                    onReorderItem: (oldIndex, newIndex) {
                      setState(() {
                        if (oldIndex == newIndex) return;

                        final ids = _order!.toList();
                        final moved = rows[oldIndex].id;
                        final target = rows[newIndex].id;
                        ids.remove(moved);
                        final targetIndex = ids.indexOf(target);
                        if (targetIndex != -1) {
                          if (oldIndex < newIndex) {
                            ids.insert(targetIndex + 1, moved);
                          } else {
                            ids.insert(targetIndex, moved);
                          }
                        } else {
                          ids.add(moved);
                        }
                        _order = ids;
                        ref.read(ledgerProvider.notifier).reorderAccounts(ids);
                      });
                    },
                    itemBuilder: (context, index) {
                      final account = rows[index];
                      return Padding(
                        key: ValueKey(account.id),
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: _AccountRow(state: state, account: account),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<Account> _filteredRows(LedgerState state) {
    final query = _query.trim().toLowerCase();
    final order = _order ?? const <String>[];
    final byId = {for (final account in state.accounts) account.id: account};
    return order.map((id) => byId[id]).whereType<Account>().where((account) {
      if (!_showArchived && account.isArchived) return false;
      if (!_showExcluded && !account.includeInTotals) return false;
      if (query.isEmpty) return true;
      return [
        account.name,
        account.type,
        account.institution,
        account.groupName,
      ].whereType<String>().join(' ').toLowerCase().contains(query);
    }).toList();
  }
}


class _CurrencySummaryHeader extends StatelessWidget {
  const _CurrencySummaryHeader({
    required this.state,
    required this.accounts,
  });

  final LedgerState state;
  final List<Account> accounts;

  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) return const SizedBox.shrink();

    final balancesMap = accountBalanceMap(state);
    final totalsByCurrency = <String, int>{};

    for (final account in accounts) {
      final currency = account.currency.toUpperCase();
      final balance = accountBalanceFromMap(balancesMap, account);
      totalsByCurrency.update(
        currency,
        (value) => value + balance.amountMinor,
        ifAbsent: () => balance.amountMinor,
      );
    }

    final currencyEntries = totalsByCurrency.entries.toList()
      ..sort((a, b) {
        if (a.key == state.preferences.baseCurrency) return -1;
        if (b.key == state.preferences.baseCurrency) return 1;
        return b.value.abs().compareTo(a.value.abs());
      });

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(100),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withAlpha(100),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in currencyEntries)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      entry.key == state.preferences.baseCurrency ? '${entry.key} (Base)' : entry.key,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: entry.key == state.preferences.baseCurrency ? FontWeight.bold : FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      formatMoney(Money(amountMinor: entry.value, currency: entry.key), state.preferences.locale),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: entry.value < 0 ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.state, required this.account});

  final LedgerState state;
  final Account account;

  @override
  Widget build(BuildContext context) {
    final balance = accountBalance(state, account);
    final displayCurrency = state.preferences.displayCurrency;
    final displayBalance = convertMoneyForDisplay(state, balance, displayCurrency);
    final isDifferentCurrency = account.currency.toUpperCase() != displayCurrency.toUpperCase();
    
    return PremiumRow(
      icon: accountIcon(account),
      title: account.name,
      subtitle: [
        accountTypeLabel(account.type),
        if (account.displayLast4 != null)
          '${account.displayLast4Label} •••• ${account.displayLast4}',
        account.currency,
        account.institution,
        account.groupName,
      ].whereType<String>().join(' · '),
      meta: formatMoney(balance, state.preferences.locale),
      metaSubtitle: isDifferentCurrency ? formatMoney(displayBalance, state.preferences.locale) : null,
      iconColor: accountDisplayColor(account),
      onTap: () => context.push('/account/${account.id}'),
    );
  }
}
