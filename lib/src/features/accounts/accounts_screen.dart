import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
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
        AppSpacing.md,
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
