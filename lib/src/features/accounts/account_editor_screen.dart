import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../common/route_scaffold.dart';

class AccountEditorScreen extends ConsumerStatefulWidget {
  const AccountEditorScreen({super.key, this.accountId});

  final String? accountId;

  @override
  ConsumerState<AccountEditorScreen> createState() =>
      _AccountEditorScreenState();
}

class _AccountEditorScreenState extends ConsumerState<AccountEditorScreen> {
  final _nameController = TextEditingController();
  final _institutionController = TextEditingController();
  final _last4Controller = TextEditingController();
  String? _loadedAccountId;
  var _includeInTotals = true;
  var _includeInReports = true;
  var _includeInNetWorth = true;
  var _showOnHome = true;
  var _isArchived = false;
  Color? _selectedColor;

  @override
  void dispose() {
    _nameController.dispose();
    _institutionController.dispose();
    _last4Controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerProvider);
    final account = accountById(state, widget.accountId);
    _syncForm(account);
    final isNew = account == null;
    final selectedColor =
      _selectedColor ?? account?.color ?? Theme.of(context).colorScheme.primary;
    final selectedForeground = selectedColor.computeLuminance() > 0.5
      ? Theme.of(context).colorScheme.onSurface
      : Theme.of(context).colorScheme.surface;
    return RouteScaffold(
      title: isNew ? 'New account' : account.name,
      actions: [
        if (account != null)
          IconButton(
            tooltip: 'Delete account',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _confirmDeleteAccount(state, account),
          ),
        IconButton(
          icon: const Icon(Icons.check_rounded),
          onPressed: () => _saveAccount(state, account),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: isNew ? 'Account setup' : 'Account profile',
            subtitle:
                'Name, institution, icon, color, currency and visibility.',
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: selectedColor,
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                      ),
                      child: Icon(
                        account == null
                            ? Icons.account_balance_wallet_outlined
                            : accountIcon(account),
                        color: selectedForeground,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Account name',
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          TextFormField(
                            controller: _institutionController,
                            decoration: const InputDecoration(
                              labelText: 'Institution',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: _DetailField(
                        icon: Icons.category_outlined,
                        label: accountTypeLabel(account?.type ?? 'bank'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _DetailField(
                        icon: Icons.currency_exchange_outlined,
                        label:
                            account?.currency ?? state.preferences.baseCurrency,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final color in AppColors.accountPalette)
                      Tooltip(
                        message: 'Use account color',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          onTap: () => setState(() => _selectedColor = color),
                          child: CircleAvatar(
                            backgroundColor: color,
                            radius: 16,
                            child: color == selectedColor
                                ? Icon(
                                    Icons.check,
                                    size: 16,
                                    color: color.computeLuminance() > 0.5
                                        ? Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                        : Theme.of(context)
                                            .colorScheme
                                            .surface,
                                  )
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Balance and reporting',
            child: Column(
              children: [
                InfoRow(
                  label: 'Current balance',
                  value: account == null
                      ? '—'
                      : formatMoney(
                          accountBalance(state, account),
                          state.preferences.locale,
                        ),
                  icon: Icons.account_balance_wallet_outlined,
                ),
                LiquidGlassSwitchListTile(
                  value: _includeInTotals,
                  onChanged: (value) =>
                      setState(() => _includeInTotals = value),
                  title: const Text('Include in totals'),
                ),
                LiquidGlassSwitchListTile(
                  value: _includeInReports,
                  onChanged: (value) =>
                      setState(() => _includeInReports = value),
                  title: const Text('Include in reports'),
                ),
                LiquidGlassSwitchListTile(
                  value: _includeInNetWorth,
                  onChanged: (value) =>
                      setState(() => _includeInNetWorth = value),
                  title: const Text('Include in net worth'),
                ),
                LiquidGlassSwitchListTile(
                  value: _showOnHome,
                  onChanged: (value) => setState(() => _showOnHome = value),
                  title: const Text('Show on home'),
                ),
                if (!isNew)
                  LiquidGlassSwitchListTile(
                    value: _isArchived,
                    onChanged: (value) => setState(() => _isArchived = value),
                    title: const Text('Archive account'),
                  ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Automation identifiers',
            subtitle:
                'Used to match incoming SMS alerts to this account automatically.',
            child: Column(
              children: [
                if (account?.type != 'cash') ...[
                  TextFormField(
                    controller: _last4Controller,
                    decoration: InputDecoration(
                      labelText:
                          account?.displayLast4Label ?? 'Account last 4 digits',
                      hintText: 'e.g. 1234',
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                  ),
                ] else ...[
                  const Text(
                    'Cash accounts do not have account numbers.',
                    style: TextStyle(fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
          if (account != null) ...[
            const Gap(AppSpacing.lg),
            SectionCard(
              title: 'Delete account',
              subtitle: _accountHasLinkedTransactions(state, account)
                  ? 'Linked records are kept, so this account will be archived and synced.'
                  : 'Unused accounts are removed from this wallet and synced.',
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _confirmDeleteAccount(state, account),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete account'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _syncForm(Account? account) {
    final key = account?.id ?? '__new__';
    if (_loadedAccountId == key) return;
    _loadedAccountId = key;
    _nameController.text = account?.name ?? '';
    _institutionController.text = account?.institution ?? '';
    _last4Controller.text = account?.displayLast4 ?? '';
    _includeInTotals = account?.includeInTotals ?? true;
    _includeInReports = account?.includeInReports ?? true;
    _includeInNetWorth = account?.includeInNetWorth ?? true;
    _showOnHome = account?.showOnHome ?? true;
    _isArchived = account?.isArchived ?? false;
    _selectedColor = account?.color;
  }

  Future<void> _saveAccount(LedgerState state, Account? account) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showAccountMessage('Enter an account name before saving.');
      return;
    }
    try {
      await ref
          .read(ledgerProvider.notifier)
          .upsertAccount(
            id: account?.id,
            name: name,
            type: account?.type ?? 'bank',
            currency: account?.currency ?? state.preferences.baseCurrency,
            color: _selectedColor,
            institution: _institutionController.text,
            cardLast4: (account?.type == 'card') ? _last4Controller.text : '',
            accountLast4: (account?.type != 'card' && account?.type != 'cash')
                ? _last4Controller.text
                : '',
            includeInTotals: _includeInTotals,
            includeInReports: _includeInReports,
            includeInNetWorth: _includeInNetWorth,
            showOnHome: _showOnHome,
            isArchived: _isArchived,
          );
      if (!mounted) return;
      _showAccountMessage(
        account == null ? 'Account created.' : 'Account saved.',
      );
      if (context.canPop()) {
        context.pop();
      } else {
        context.push('/');
      }
    } catch (error) {
      if (!mounted) return;
      _showAccountMessage(error.toString());
    }
  }

  Future<void> _confirmDeleteAccount(LedgerState state, Account account) async {
    final hasLinkedTransactions = _accountHasLinkedTransactions(state, account);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          hasLinkedTransactions ? 'Archive account?' : 'Delete account?',
        ),
        content: Text(
          hasLinkedTransactions
              ? '“${account.name}” has linked records, so it will be archived instead of permanently deleted. This change will sync with your wallet.'
              : 'This permanently removes “${account.name}” from your wallet. This deletion will sync with your wallet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(hasLinkedTransactions ? 'Archive' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(ledgerProvider.notifier).deleteAccount(account.id);
      if (!mounted) return;
      _showAccountMessage(
        hasLinkedTransactions
            ? 'Account archived. Sync will update shortly.'
            : 'Account deleted. Sync will update shortly.',
      );
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    } catch (error) {
      if (!mounted) return;
      _showAccountMessage(error.toString());
    }
  }

  bool _accountHasLinkedTransactions(LedgerState state, Account account) {
    return state.transactions.any(
      (transaction) =>
          transaction.accountId == account.id ||
          transaction.counterAccountId == account.id,
    );
  }

  void _showAccountMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
