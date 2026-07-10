import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../utils/currency_utils.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/currency_picker.dart';
import '../../widgets/credit_card_view.dart';
import '../../widgets/color_picker_dialog.dart';
import '../../widgets/privacy_text.dart';
import '../../utils/number_formatter.dart';
import '../common/full_screen_picker.dart';
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
  final _creditLimitController = TextEditingController();
  String? _loadedAccountId;
  var _includeInTotals = true;
  var _includeInReports = true;
  var _includeInNetWorth = true;
  var _showOnHome = true;
  var _isArchived = false;
  Color? _selectedColor;
  String? _selectedType;
  String? _selectedCurrency;

  bool _isCardUnlocked = false;
  String _unlockedNumber = '';
  String _unlockedExpiry = '';
  String _unlockedCcv = '';
  Map<String, String> _unlockedCustomFields = {};

  @override
  void dispose() {
    _nameController.dispose();
    _institutionController.dispose();
    _creditLimitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerProvider);
    final account = accountById(state, widget.accountId);
    _syncForm(account);
    final isNew = account == null;
    final selectedColor =
        _selectedColor ??
        account?.color ??
        Theme.of(context).colorScheme.primary;
    final selectedForeground = selectedColor.computeLuminance() > 0.5
        ? Theme.of(context).colorScheme.onSurface
        : Theme.of(context).colorScheme.surface;

    final isCardType =
        _selectedType == 'card' || _selectedType == 'credit_card';

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
          if (account != null) ...[
            GestureDetector(
              onTap: () {
                if (_isCardUnlocked) {
                  setState(() => _isCardUnlocked = false);
                } else {
                  _unlockCardInline(account);
                }
              },
              child: CreditCardView(
                type: isCardType ? 'card' : 'bank',
                cardNumber: _isCardUnlocked
                    ? _unlockedNumber
                    : (account.displayLast4 ?? '0000'),
                expiry: isCardType
                    ? (_isCardUnlocked
                          ? _unlockedExpiry
                          : (account.encryptedDetails != null ? 'MM/YY' : ''))
                    : '',
                ccv: isCardType
                    ? (_isCardUnlocked
                          ? _unlockedCcv
                          : (account.encryptedDetails != null ? '***' : ''))
                    : '',
                cardHolder: account.name,
                gradientStart:
                    _selectedColor ??
                    account.color ??
                    Theme.of(context).colorScheme.primary,
                gradientEnd:
                    (_selectedColor ??
                            account.color ??
                            Theme.of(context).colorScheme.primary)
                        .withAlpha(150),
                isUnlocked: _isCardUnlocked,
                customFields: _unlockedCustomFields,
              ),
            ),
            const Gap(AppSpacing.md),
            OutlinedButton.icon(
              onPressed: () => _handleSecureNavigation(context, account.id),
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('Manage secure details'),
            ),
          ],

          const Gap(AppSpacing.lg),
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
                          if (isCardType) ...[
                            const SizedBox(height: AppSpacing.sm),
                            TextFormField(
                              controller: _creditLimitController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                ThousandsSeparatorInputFormatter(state.preferences.locale),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Credit limit',
                                prefixIcon: Icon(Icons.credit_score_outlined),
                              ),
                            ),
                          ],
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
                        label: accountTypeLabel(
                          _selectedType ?? account?.type ?? 'bank',
                        ),
                        onTap: () => _chooseAccountType(context),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _DetailField(
                        icon: Icons.currency_exchange_outlined,
                        label: getCurrencyInfo(
                          _selectedCurrency ??
                              account?.currency ??
                              state.preferences.baseCurrency,
                        ).shortName,
                        onTap: () => _chooseCurrency(context, state),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: _DetailField(
                        icon: Icons.palette_outlined,
                        label: 'Choose color',
                        onTap: () async {
                          final color = await showAppColorPicker(
                            context: context,
                            initialColor: selectedColor,
                            title: 'Account color',
                          );
                          if (color != null) {
                            setState(() => _selectedColor = color);
                          }
                        },
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
                      : maskMoneyIfPrivate(
                          state,
                          formatMoney(
                            accountBalance(state, account),
                            state.preferences.locale,
                          ),
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

  Future<void> _unlockCardInline(Account account) async {
    final auth = LocalAuthentication();
    try {
      final authenticated = await auth.authenticate(
        localizedReason: 'Authenticate to view secure details',
        biometricOnly: false,
      );
      if (authenticated && mounted) {
        if (account.encryptedDetails != null) {
          final key = encrypt.Key.fromUtf8('my32lengthsupersecretkey12345678');
          final iv = encrypt.IV(Uint8List(16));
          final encrypter = encrypt.Encrypter(encrypt.AES(key));

          String uNum = '';
          String uExp = '';
          String uCcv = '';
          Map<String, String> uCustom = {};

          try {
            final details = account.encryptedDetails!;
            details.forEach((k, v) {
              try {
                final decrypted = encrypter.decrypt64(v, iv: iv);
                if (k == 'number' || k == 'account_number') {
                  uNum = decrypted;
                } else if (k == 'expiry') {
                  uExp = decrypted;
                } else if (k == 'ccv') {
                  uCcv = decrypted;
                } else if (k == 'routing_number') {
                  // Legacy support: convert to custom field
                  uCustom['Routing Number'] = decrypted;
                } else if (k != 'name' && k != 'bank_name') {
                  uCustom[k] = decrypted;
                }
              } catch (e) {
                debugPrint('Decryption error on key $k: $e');
              }
            });
          } catch (e) {
            debugPrint('Decryption error: $e');
          }

          setState(() {
            _unlockedNumber = uNum;
            _unlockedExpiry = uExp;
            _unlockedCcv = uCcv;
            _unlockedCustomFields = uCustom;
            _isCardUnlocked = true;
          });
        } else {
          // If no details exist, just unlock to show empty fields
          setState(() {
            _isCardUnlocked = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Auth error: $e');
    }
  }

  Future<void> _handleSecureNavigation(
    BuildContext context,
    String accountId,
  ) async {
    if (_isCardUnlocked) {
      await context.push('/account/$accountId/secure');
      if (mounted) {
        setState(() {
          _isCardUnlocked = false;
        });
      }
      return;
    }

    final auth = LocalAuthentication();
    try {
      final authenticated = await auth.authenticate(
        localizedReason: 'Authenticate to edit secure details',
        biometricOnly: false,
      );
      if (authenticated && context.mounted) {
        // Since they authenticated successfully, let's also unlock inline.
        setState(() {
          _isCardUnlocked = true;
        });
        await context.push('/account/$accountId/secure');
        // When they return from secure details, lock it again so they can fetch fresh details if they want.
        if (mounted) {
          setState(() {
            _isCardUnlocked = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Auth error: $e');
    }
  }

  void _syncForm(Account? account) {
    final key = account?.id ?? '__new__';
    if (_loadedAccountId == key) return;
    _loadedAccountId = key;
    _nameController.text = account?.name ?? '';
    _institutionController.text = account?.institution ?? '';
    if (account?.creditLimit != null) {
      final amt =
          account!.creditLimit!.amountMinor /
          math.pow(10, minorUnits(account.creditLimit!.currency));
      _creditLimitController.text = amt.toStringAsFixed(
        minorUnits(account.creditLimit!.currency),
      );
    } else {
      _creditLimitController.text = '';
    }
    _includeInTotals = account?.includeInTotals ?? true;
    _includeInReports = account?.includeInReports ?? true;
    _includeInNetWorth = account?.includeInNetWorth ?? true;
    _showOnHome = account?.showOnHome ?? true;
    _isArchived = account?.isArchived ?? false;
    _selectedColor = account?.color;
    _selectedType = account?.type ?? 'bank';
    _selectedCurrency = account?.currency;

    // Reset unlock state on account change
    _isCardUnlocked = false;
    _unlockedNumber = '';
    _unlockedExpiry = '';
    _unlockedCcv = '';
  }

  Future<void> _saveAccount(LedgerState state, Account? account) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showAccountMessage('Enter an account name before saving.');
      return;
    }
    final isCardType =
        _selectedType == 'card' || _selectedType == 'credit_card';
    Money? parsedCreditLimit;
    if (isCardType && _creditLimitController.text.trim().isNotEmpty) {
      final currency =
          _selectedCurrency ??
          account?.currency ??
          state.preferences.baseCurrency;
      final normalized = _creditLimitController.text.replaceAll(
        RegExp(r'[^0-9.]'),
        '',
      );
      final parsed = double.tryParse(normalized) ?? 0;
      parsedCreditLimit = Money(
        amountMinor: (parsed * math.pow(10, minorUnits(currency))).round(),
        currency: currency,
      );
    }

    try {
      await ref
          .read(ledgerProvider.notifier)
          .upsertAccount(
            id: account?.id,
            name: name,
            type: _selectedType ?? account?.type ?? 'bank',
            currency:
                _selectedCurrency ??
                account?.currency ??
                state.preferences.baseCurrency,
            color: _selectedColor,
            institution: _institutionController.text,
            cardLast4: account?.cardLast4,
            accountLast4: account?.accountLast4,
            includeInTotals: _includeInTotals,
            includeInReports: _includeInReports,
            includeInNetWorth: _includeInNetWorth,
            showOnHome: _showOnHome,
            isArchived: _isArchived,
            encryptedDetails: account?.encryptedDetails,
            creditLimit: parsedCreditLimit,
          );
      if (!mounted) return;
      _showAccountMessage(
        account == null ? 'Account created.' : 'Account saved.',
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

  Future<void> _chooseAccountType(BuildContext context) async {
    final next = await showFullScreenPicker<String>(
      context: context,
      title: 'Account type',
      searchHint: 'Search types',
      selectedValue: _selectedType ?? 'bank',
      options: [
        for (final type in [
          'bank',
          'cash',
          'credit_card',
          'wallet',
          'loan',
          'overdraft',
          'investment',
        ])
          PickerOption(
            value: type,
            title: accountTypeLabel(type),
            icon: Icons.category_outlined,
          ),
      ],
    );
    if (next != null) {
      setState(() => _selectedType = next);
    }
  }

  Future<void> _chooseCurrency(BuildContext context, LedgerState state) async {
    final next = await showCurrencyPicker(
      context: context,
      state: state,
      selectedValue: _selectedCurrency ?? state.preferences.baseCurrency,
    );
    if (next != null) {
      setState(() => _selectedCurrency = next);
    }
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
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
      ),
    );
  }
}
