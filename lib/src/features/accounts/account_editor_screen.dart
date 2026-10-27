import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../utils/currency_utils.dart';
import '../../utils/secure_key_store.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/currency_picker.dart';
import '../../widgets/credit_card_view.dart';
import '../../widgets/color_picker_dialog.dart';
import '../../widgets/privacy_text.dart';
import '../../utils/number_formatter.dart';
import '../common/full_screen_picker.dart';
import '../common/route_scaffold.dart';

class AccountEditorScreen extends ConsumerStatefulWidget {
  const AccountEditorScreen({super.key, this.accountId, this.initialType});

  final String? accountId;

  /// Pre-selects the account type when creating a brand-new account (e.g.
  /// jumping in from the Cards screen should default to "Credit card"
  /// instead of forcing the user to change the type manually). Ignored when
  /// editing an existing account.
  final String? initialType;

  @override
  ConsumerState<AccountEditorScreen> createState() =>
      _AccountEditorScreenState();
}

class _CashOpeningDraft {
  _CashOpeningDraft({required this.currency, required String amount})
    : controller = TextEditingController(text: amount);

  String currency;
  final TextEditingController controller;
}

class _AccountEditorScreenState extends ConsumerState<AccountEditorScreen> {
  final _nameController = TextEditingController();
  final _institutionController = TextEditingController();
  final _creditLimitController = TextEditingController();
  final _openingBalanceController = TextEditingController();
  final _notifyDaysController = TextEditingController();
  final List<_CashOpeningDraft> _cashOpenings = [];
  int? _statementDay;
  int? _dueDay;
  String? _loadedAccountId;
  var _includeInTotals = true;
  var _includeInReports = true;
  var _includeInNetWorth = true;
  var _showOnHome = true;
  var _isArchived = false;
  Color? _selectedColor;
  String? _selectedType;
  String? _selectedCurrency;
  bool _isSaving = false;

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
    _openingBalanceController.dispose();
    _notifyDaysController.dispose();
    for (final draft in _cashOpenings) {
      draft.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerProvider);
    final account = accountById(state, widget.accountId);
    _syncForm(state, account);
    final isNew = account == null;
    final selectedColor =
        _selectedColor ??
        account?.color ??
        Theme.of(context).colorScheme.primary;
    final selectedForeground = selectedColor.computeLuminance() > 0.5
        ? Theme.of(context).colorScheme.onSurface
        : Theme.of(context).colorScheme.surface;

    final currentType =
        _selectedType ?? account?.type ?? widget.initialType ?? 'bank';
    final isCash = currentType == 'cash';
    final isCardType = currentType == 'card' || currentType == 'credit_card';

    return RouteScaffold(
      title: isNew ? 'New account' : account.name,
      actions: [
        if (account != null)
          HeaderIconButton(
            tooltip: 'Delete account',
            semanticLabel: 'Delete account',
            icon: Icons.delete_outline_rounded,
            onPressed: _isSaving
                ? null
                : () => _confirmDeleteAccount(state, account),
          ),
        HeaderSaveAction(
          isSaving: _isSaving,
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
                        .withValues(alpha: 0.59),
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
                        label: accountTypeLabel(currentType),
                        onTap: () => _chooseAccountType(context),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    if (isCash)
                      const Expanded(
                        child: _DetailField(
                          icon: Icons.all_inclusive_rounded,
                          label: 'Multi-currency',
                          onTap: null,
                        ),
                      )
                    else
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
                if (isCash)
                  AppPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Opening balances',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Initial cash in each currency you hold',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _addCashCurrency(context, state),
                              icon: const Icon(Icons.add_rounded, size: 18),
                              label: const Text('Add currency'),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                  vertical: AppSpacing.xs,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        for (var i = 0; i < _cashOpenings.length; i++) ...[
                          if (i > 0) const SizedBox(height: AppSpacing.xs),
                          _buildCashOpeningRow(context, state, i),
                        ],
                      ],
                    ),
                  )
                else
                  TextFormField(
                    controller: _openingBalanceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Opening balance',
                      prefixIcon: Icon(Icons.savings_outlined),
                      helperText:
                          'Use a negative amount if this account already '
                          'carries a balance you owe (e.g. credit card or '
                          'loan debt).',
                      helperMaxLines: 2,
                    ),
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
          if (isCardType) ...[
            const Gap(AppSpacing.lg),
            SectionCard(
              title: 'Card Billing & Due Date',
              subtitle:
                  'Statement bill date, payment due date and credit limit.',
              child: Column(
                children: [
                  TextFormField(
                    controller: _creditLimitController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      ThousandsSeparatorInputFormatter(
                        state.preferences.locale,
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Credit limit',
                      prefixIcon: Icon(Icons.credit_score_outlined),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int?>(
                          initialValue: _statementDay,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Bill date',
                            prefixIcon: Icon(Icons.receipt_outlined),
                          ),
                          selectedItemBuilder: (context) {
                            return [
                              const Text(
                                'Not set',
                                style: TextStyle(color: Colors.grey),
                              ),
                              for (int d = 1; d <= 31; d++)
                                Text(
                                  'Day $d',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                            ];
                          },
                          items: [
                            const DropdownMenuItem(child: Text('Not set')),
                            for (int d = 1; d <= 31; d++)
                              DropdownMenuItem(
                                value: d,
                                child: Text(
                                  'Day $d (${daySuffix(d)} of month)',
                                ),
                              ),
                          ],
                          onChanged: (val) =>
                              setState(() => _statementDay = val),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: DropdownButtonFormField<int?>(
                          initialValue: _dueDay,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Due date',
                            prefixIcon: Icon(Icons.event_outlined),
                          ),
                          selectedItemBuilder: (context) {
                            return [
                              const Text(
                                'Not set',
                                style: TextStyle(color: Colors.grey),
                              ),
                              for (int d = 1; d <= 31; d++)
                                Text(
                                  'Day $d',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                            ];
                          },
                          items: [
                            const DropdownMenuItem(child: Text('Not set')),
                            for (int d = 1; d <= 31; d++)
                              DropdownMenuItem(
                                value: d,
                                child: Text(
                                  'Day $d (${daySuffix(d)} of month)',
                                ),
                              ),
                          ],
                          onChanged: (val) => setState(() => _dueDay = val),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _notifyDaysController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Notify days before due',
                      hintText: 'e.g. 3',
                      prefixIcon: Icon(Icons.notifications_active_outlined),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
                AppSwitchListTile(
                  value: _includeInTotals,
                  onChanged: (value) =>
                      setState(() => _includeInTotals = value),
                  title: const Text('Include in totals'),
                ),
                AppSwitchListTile(
                  value: _includeInReports,
                  onChanged: (value) =>
                      setState(() => _includeInReports = value),
                  title: const Text('Include in reports'),
                ),
                AppSwitchListTile(
                  value: _includeInNetWorth,
                  onChanged: (value) =>
                      setState(() => _includeInNetWorth = value),
                  title: const Text('Include in net worth'),
                ),
                AppSwitchListTile(
                  value: _showOnHome,
                  onChanged: (value) => setState(() => _showOnHome = value),
                  title: const Text('Show on home'),
                ),
              ],
            ),
          ),

          if (account != null) ...[
            const Gap(AppSpacing.lg),
            SectionCard(
              title: 'Danger Zone',
              subtitle: 'Manage account closure or permanent deletion.',
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  children: [
                    if (account.isArchived)
                      OutlinedButton.icon(
                        onPressed: () => _reopenAccount(state, account),
                        icon: const Icon(Icons.unarchive_outlined),
                        label: const Text('Reopen account'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: () => _closeAccount(state, account),
                        icon: const Icon(Icons.archive_outlined),
                        label: const Text('Close account'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    OutlinedButton.icon(
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
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _unlockCardInline(Account account) async {
    final owner = ref.read(ledgerProvider).userId;
    final auth = LocalAuthentication();
    try {
      final authenticated = await auth.authenticate(
        localizedReason: 'Authenticate to view secure details',
      );
      if (authenticated &&
          mounted &&
          ref.read(ledgerProvider).userId == owner) {
        final latest = accountById(ref.read(ledgerProvider), account.id);
        if (latest == null) throw StateError('The account no longer exists.');
        if (latest.encryptedDetails != null) {
          String uNum = '';
          String uExp = '';
          String uCcv = '';
          final Map<String, String> uCustom = {};

          final details = latest.encryptedDetails!;
          for (final entry in details.entries) {
            if (statementMetadataKeys.contains(entry.key)) continue;
            final versioned = entry.value.startsWith('v2:');
            final decrypted = await SecureKeyStore.decrypt(
              entry.value,
              userId: versioned ? owner : null,
              context: versioned
                  ? SecureKeyStore.fieldContext(latest.id, entry.key)
                  : null,
            );
            if (!mounted || ref.read(ledgerProvider).userId != owner) return;
            final k = entry.key;
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
          }

          if (mounted) {
            setState(() {
              _unlockedNumber = uNum;
              _unlockedExpiry = uExp;
              _unlockedCcv = uCcv;
              _unlockedCustomFields = uCustom;
              _isCardUnlocked = true;
            });
          }
        } else {
          // If no details exist, just unlock to show empty fields
          setState(() {
            _isCardUnlocked = true;
          });
        }
      }
    } catch (e, stack) {
      debugPrint('Secure card access failed: ${e.runtimeType}');
      debugPrintStack(stackTrace: stack);
      if (mounted && ref.read(ledgerProvider).userId == owner) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Secure details could not be unlocked. Original data was preserved.',
            ),
          ),
        );
      }
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

  void _syncForm(LedgerState state, Account? account) {
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
    final isCardType =
        (account?.type ?? widget.initialType) == 'card' ||
        (account?.type ?? widget.initialType) == 'credit_card';
    _statementDay = account?.statementDay;
    _dueDay = account?.dueDay;
    _notifyDaysController.text =
        account?.notifyDaysBeforeDue?.toString() ?? (isCardType ? '3' : '');
    final openingBalance = account?.openingBalance;
    if (openingBalance != null && openingBalance.amountMinor != 0) {
      final amt =
          openingBalance.amountMinor /
          math.pow(10, minorUnits(openingBalance.currency));
      _openingBalanceController.text = amt.toStringAsFixed(
        minorUnits(openingBalance.currency),
      );
    } else {
      _openingBalanceController.text = '';
    }

    for (final draft in _cashOpenings) {
      draft.controller.dispose();
    }
    _cashOpenings.clear();
    final baseCurr = account?.currency ?? state.preferences.baseCurrency;
    if (account != null && account.effectiveOpeningBalances.isNotEmpty) {
      for (final op in account.effectiveOpeningBalances) {
        final amt = op.amountMinor / math.pow(10, minorUnits(op.currency));
        final text = amt == 0
            ? ''
            : amt.toStringAsFixed(minorUnits(op.currency));
        _cashOpenings.add(
          _CashOpeningDraft(currency: op.currency, amount: text),
        );
      }
    }
    if (_cashOpenings.isEmpty) {
      _cashOpenings.add(_CashOpeningDraft(currency: baseCurr, amount: ''));
    }

    _includeInTotals = account?.includeInTotals ?? true;
    _includeInReports = account?.includeInReports ?? true;
    _includeInNetWorth = account?.includeInNetWorth ?? true;
    _showOnHome = account?.showOnHome ?? true;
    _isArchived = account?.isArchived ?? false;
    _selectedColor = account?.color;
    _selectedType = account?.type ?? widget.initialType ?? 'bank';
    _selectedCurrency = account?.currency;

    // Reset unlock state on account change
    _isCardUnlocked = false;
    _unlockedNumber = '';
    _unlockedExpiry = '';
    _unlockedCcv = '';
  }

  Future<void> _saveAccount(LedgerState state, Account? account) async {
    if (_isSaving) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showAccountMessage('Enter an account name before saving.');
      return;
    }
    final type = _selectedType ?? account?.type ?? 'bank';
    final isCashType = type == 'cash';
    final isCardType = type == 'card' || type == 'credit_card';

    List<Money>? openingBalancesList;
    int openingBalanceMinor = 0;
    String currency =
        _selectedCurrency ??
        account?.currency ??
        state.preferences.baseCurrency;

    if (isCashType) {
      openingBalancesList = <Money>[];
      for (final entry in _cashOpenings) {
        final text = entry.controller.text.trim();
        if (text.isEmpty) continue;
        final isNeg = text.contains('-') || text.contains('(');
        final digits = text.replaceAll(RegExp(r'[^0-9.]'), '');
        final mag = double.tryParse(digits) ?? 0;
        if (mag == 0 && !text.contains('0')) continue;
        final minor =
            ((isNeg ? -1 : 1) * mag * math.pow(10, minorUnits(entry.currency)))
                .round();
        openingBalancesList.add(
          Money(amountMinor: minor, currency: entry.currency),
        );
      }
      if (openingBalancesList.isNotEmpty) {
        currency = openingBalancesList.first.currency;
        openingBalanceMinor = openingBalancesList.first.amountMinor;
      } else {
        currency = account?.currency ?? state.preferences.baseCurrency;
        openingBalanceMinor = 0;
      }
    } else {
      final openingBalanceText = _openingBalanceController.text.trim();
      final openingBalanceIsNegative =
          openingBalanceText.contains('-') || openingBalanceText.contains('(');
      final openingBalanceDigits = openingBalanceText.replaceAll(
        RegExp(r'[^0-9.]'),
        '',
      );
      final openingBalanceMagnitude =
          double.tryParse(openingBalanceDigits) ?? 0;
      openingBalanceMinor =
          ((openingBalanceIsNegative ? -1 : 1) *
                  openingBalanceMagnitude *
                  math.pow(10, minorUnits(currency)))
              .round();
    }

    Money? parsedCreditLimit;
    int? statementDay;
    int? dueDay;
    int? notifyDays;
    if (isCardType) {
      if (_creditLimitController.text.trim().isNotEmpty) {
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
      statementDay = _statementDay;
      dueDay = _dueDay;
      final nVal = int.tryParse(_notifyDaysController.text.trim());
      if (nVal != null) notifyDays = nVal.clamp(1, 30);
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(ledgerProvider.notifier)
          .upsertAccount(
            id: account?.id,
            name: name,
            type: type,
            currency: currency,
            openingBalanceMinor: openingBalanceMinor,
            openingBalances: openingBalancesList,
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
            statementDay: statementDay,
            dueDay: dueDay,
            notifyDaysBeforeDue: notifyDays,
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
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmDeleteAccount(LedgerState state, Account account) async {
    // 1. Check if the account is currently tied to any active plans / scheduled transactions
    final activePlans = state.transactions
        .where(
          (transaction) =>
              (transaction.accountId == account.id ||
                  transaction.counterAccountId == account.id) &&
              (transaction.status == 'scheduled' ||
                  transaction.status == 'paused'),
        )
        .toList();

    if (activePlans.isNotEmpty) {
      final planCount = activePlans.length;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cannot delete account'),
          content: Text(
            '“${account.name}” is currently linked to $planCount planned payment${planCount == 1 ? '' : 's'}.\n\nPlease edit or delete those planned payments first before deleting this account.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final hasLinkedTransactions = _accountHasLinkedTransactions(state, account);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: Text(
          hasLinkedTransactions
              ? 'This will delete “${account.name}” from your active accounts. All previous transactions under this account will remain safely preserved in your history.'
              : 'This permanently removes “${account.name}” from your wallet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
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
            ? 'Account deleted. Historical transactions preserved.'
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
          'savings',
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
      setState(() {
        _selectedType = next;
        if (next == 'cash') {
          if (_cashOpenings.isEmpty) {
            _cashOpenings.add(
              _CashOpeningDraft(
                currency: _selectedCurrency ?? 'USD',
                amount: _openingBalanceController.text.trim(),
              ),
            );
          }
        } else {
          if (_cashOpenings.isNotEmpty) {
            _selectedCurrency = _cashOpenings.first.currency;
            if (_cashOpenings.first.controller.text.trim().isNotEmpty) {
              _openingBalanceController.text = _cashOpenings
                  .first
                  .controller
                  .text
                  .trim();
            }
          }
        }
      });
    }
  }

  Future<void> _addCashCurrency(BuildContext context, LedgerState state) async {
    final next = await showCurrencyPicker(
      context: context,
      state: state,
      selectedValue: state.preferences.baseCurrency,
    );
    if (next != null) {
      if (_cashOpenings.any((e) => e.currency == next)) {
        _showAccountMessage('$next is already in the list.');
        return;
      }
      setState(() {
        _cashOpenings.add(_CashOpeningDraft(currency: next, amount: ''));
      });
    }
  }

  Widget _buildCashOpeningRow(
    BuildContext context,
    LedgerState state,
    int index,
  ) {
    final entry = _cashOpenings[index];
    final currencyInfo = getCurrencyInfo(entry.currency);
    final symbol = NumberFormat.simpleCurrency(
      name: entry.currency,
    ).currencySymbol;

    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(AppRadii.md),
          onTap: () async {
            final next = await showCurrencyPicker(
              context: context,
              state: state,
              selectedValue: entry.currency,
            );
            if (next != null && next != entry.currency) {
              if (_cashOpenings.any((e) => e.currency == next)) {
                _showAccountMessage('$next is already in the list.');
                return;
              }
              setState(() => entry.currency = next);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (currencyInfo.flag.isNotEmpty) ...[
                  Text(currencyInfo.flag, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: AppSpacing.xs),
                ] else ...[
                  Icon(
                    Icons.currency_exchange_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Text(
                  entry.currency,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down_rounded, size: 16),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: TextFormField(
            controller: entry.controller,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
            ],
            decoration: InputDecoration(
              isDense: true,
              hintText: '0.00',
              prefixText: '$symbol ',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
            ),
          ),
        ),
        if (_cashOpenings.length > 1) ...[
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.8),
            tooltip: 'Remove ${entry.currency}',
            onPressed: () {
              setState(() {
                final removed = _cashOpenings.removeAt(index);
                removed.controller.dispose();
              });
            },
          ),
        ],
      ],
    );
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

  Future<void> _closeAccount(LedgerState state, Account account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close account?'),
        content: const Text(
          'This account will be closed and hidden from your active wallet balances, but its history will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Close account'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _updateArchiveState(account, true, 'Account closed and archived.');
  }

  Future<void> _reopenAccount(LedgerState state, Account account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reopen account?'),
        content: const Text(
          'This account will be visible in your active wallet again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reopen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _updateArchiveState(account, false, 'Account reopened.');
  }

  Future<void> _updateArchiveState(
    Account account,
    bool isArchived,
    String message,
  ) async {
    try {
      await ref
          .read(ledgerProvider.notifier)
          .upsertAccount(
            id: account.id,
            name: account.name,
            type: account.type,
            currency: account.currency,
            openingBalanceMinor: account.openingBalance.amountMinor,
            color: account.color,
            institution: account.institution,
            groupName: account.groupName,
            cardLast4: account.cardLast4,
            accountLast4: account.accountLast4,
            loanDetails: account.loanDetails,
            encryptedDetails: account.encryptedDetails,
            creditLimit: account.creditLimit,
            includeInTotals: account.includeInTotals,
            includeInReports: account.includeInReports,
            includeInNetWorth: account.includeInNetWorth,
            showOnHome: account.showOnHome,
            isArchived: isArchived,
          );
      if (!mounted) return;
      _showAccountMessage(message);
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
}

class _DetailField extends StatelessWidget {
  const _DetailField({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      onTap: onTap,
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

Future<int?> showDayOfMonthPicker({
  required BuildContext context,
  required String title,
  int? initialDay,
}) async {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final isAmoled = AppSurfaces.isAmoled(context);
  final isDesktop = AppResponsiveLayout.isDesktop(context);

  Widget buildPickerContent(BuildContext pickerContext) {
    final inner = Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.calendar_month_rounded,
                  color: scheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Choose day of each month (1 - 31)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (initialDay != null)
                TextButton.icon(
                  onPressed: () => Navigator.of(pickerContext).pop(0),
                  icon: const Icon(Icons.clear_rounded, size: 16),
                  label: const Text('Clear'),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.error,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              if (isDesktop) ...[
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(pickerContext).pop(),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Weekday header
          Row(
            children: [
              for (final d in ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: 31,
            itemBuilder: (context, index) {
              final day = index + 1;
              final isSelected = day == initialDay;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.of(pickerContext).pop(day),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? scheme.primary
                          : (isAmoled
                                ? AppColors.amoledBackground
                                : scheme.surfaceContainerHighest.withValues(
                                    alpha: 0.5,
                                  )),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? scheme.primary
                            : (isAmoled
                                  ? Colors.white.withValues(alpha: 0.09)
                                  : scheme.outlineVariant.withValues(
                                      alpha: 0.5,
                                    )),
                        width: isSelected ? 2.0 : 1.0,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: scheme.primary.withValues(alpha: 0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$day',
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.w900
                            : FontWeight.w600,
                        color: isSelected ? scheme.onPrimary : scheme.onSurface,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );

    // Modal surface: keeps the dialog radius (xl) of the theme's dialogs.
    return AppPanel(glass: true, radius: AppRadii.xl, child: inner);
  }

  if (isDesktop) {
    return showDialog<int?>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: buildPickerContent(dialogContext),
        ),
      ),
    );
  }

  return showModalBottomSheet<int?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    constraints: const BoxConstraints(maxWidth: 460),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        child: buildPickerContent(sheetContext),
      ),
    ),
  );
}
