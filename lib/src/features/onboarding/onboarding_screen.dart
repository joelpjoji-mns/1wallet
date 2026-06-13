import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../auth/auth_controller.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';
import '../common/full_screen_picker.dart';
import '../launch/brand_widgets.dart';
import 'onboarding_controller.dart';

class _AccountDraft {
  String name;
  String type;
  String currency;
  Color color;
  String opening;
  IconData icon;

  _AccountDraft({
    required this.name,
    required this.type,
    required this.currency,
    required this.color,
    required this.opening,
    required this.icon,
  });
}

enum _OnboardingStep { profile, mainAccount, moreAccounts, extraAccount, permissions }

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  var _step = _OnboardingStep.profile;
  final _displayNameController = TextEditingController();
  final _selectedUseCases = <String>{'daily_spending', 'budgeting'};

  final List<_AccountDraft> _accounts = [];
  late _AccountDraft _currentDraft;

  var _enableAutoCapture = true;
  var _enableReminders = true;
  var _isCompleting = false;

  @override
  void initState() {
    super.initState();
    _initDraft();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authControllerProvider).user;
      if (user?.displayName != null && user!.displayName!.isNotEmpty) {
        _displayNameController.text = user.displayName!;
      }
    });
  }

  void _initDraft() {
    _currentDraft = _AccountDraft(
      name: '',
      type: 'bank',
      currency: 'INR',
      color: AppColors.primary,
      opening: '0',
      icon: Icons.account_balance_outlined,
    );
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Set up 1wallet'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: auth.isSigningIn
                ? null
                : () => ref.read(authControllerProvider.notifier).signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: LaunchBackdrop(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
          children: [
            _ProgressHeader(step: _step),
            const SizedBox(height: AppSpacing.lg),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: _buildStepBody(),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                if (_step != _OnboardingStep.profile)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isCompleting ? null : _back,
                      child: const Text('Back'),
                    ),
                  ),
                if (_step != _OnboardingStep.profile)
                  const SizedBox(width: AppSpacing.sm),
                if (_step != _OnboardingStep.moreAccounts)
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _isCompleting ? null : _nextOrComplete,
                      icon: _isCompleting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.2),
                            )
                          : Icon(
                              _step == _OnboardingStep.permissions
                                  ? Icons.check_rounded
                                  : Icons.arrow_forward_rounded,
                            ),
                      label: Text(_step == _OnboardingStep.permissions ? 'Finish setup' : 'Continue'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildStepBody() {
    return switch (_step) {
      _OnboardingStep.profile => _ProfileStep(
          key: const ValueKey('profile'),
          nameController: _displayNameController,
          selectedUseCases: _selectedUseCases,
          onToggleUseCase: (id) {
            setState(() {
              if (_selectedUseCases.contains(id)) {
                _selectedUseCases.remove(id);
              } else {
                _selectedUseCases.add(id);
              }
            });
          },
        ),
      _OnboardingStep.mainAccount => _AccountStep(
          key: const ValueKey('mainAccount'),
          isMain: true,
          draft: _currentDraft,
          onCurrency: _chooseCurrency,
          onColor: _chooseColor,
          onType: _chooseType,
          onNameChanged: (val) => setState(() => _currentDraft.name = val),
          onOpeningChanged: (val) => setState(() => _currentDraft.opening = val),
        ),
      _OnboardingStep.moreAccounts => _MoreAccountsStep(
          key: const ValueKey('moreAccounts'),
          accounts: _accounts,
          isCompleting: _isCompleting,
          onAddAnother: () {
            _initDraft();
            setState(() => _step = _OnboardingStep.extraAccount);
          },
          onFinish: _nextOrComplete,
        ),
      _OnboardingStep.extraAccount => _AccountStep(
          key: const ValueKey('extraAccount'),
          isMain: false,
          draft: _currentDraft,
          onCurrency: _chooseCurrency,
          onColor: _chooseColor,
          onType: _chooseType,
          onNameChanged: (val) => setState(() => _currentDraft.name = val),
          onOpeningChanged: (val) => setState(() => _currentDraft.opening = val),
        ),
      _OnboardingStep.permissions => _PermissionsStep(
          key: const ValueKey('permissions'),
          enableAutoCapture: _enableAutoCapture,
          enableReminders: _enableReminders,
          onAutoCaptureChanged: (value) =>
              setState(() => _enableAutoCapture = value),
          onRemindersChanged: (value) =>
              setState(() => _enableReminders = value),
        ),
    };
  }

  Future<void> _chooseType() async {
    final next = await showFullScreenPicker<String>(
      context: context,
      title: 'Choose account type',
      searchable: false,
      selectedValue: _currentDraft.type,
      options: const [
        PickerOption(value: 'bank', title: 'Bank account', icon: Icons.account_balance_outlined),
        PickerOption(value: 'cash', title: 'Cash', icon: Icons.money_outlined),
        PickerOption(value: 'credit_card', title: 'Credit Card', icon: Icons.credit_card_outlined),
        PickerOption(value: 'loan', title: 'Loan', icon: Icons.real_estate_agent_outlined),
        PickerOption(value: 'wallet', title: 'Digital Wallet', icon: Icons.account_balance_wallet_outlined),
      ],
    );
    if (next != null) {
      setState(() {
        _currentDraft.type = next;
        if (next == 'bank') {
          _currentDraft.icon = Icons.account_balance_outlined;
        } else if (next == 'cash') {
          _currentDraft.icon = Icons.money_outlined;
        } else if (next == 'credit_card') {
          _currentDraft.icon = Icons.credit_card_outlined;
        } else if (next == 'loan') {
          _currentDraft.icon = Icons.real_estate_agent_outlined;
        } else if (next == 'wallet') {
          _currentDraft.icon = Icons.account_balance_wallet_outlined;
        }
      });
    }
  }

  Future<void> _chooseCurrency() async {
    final next = await showFullScreenPicker<String>(
      context: context,
      title: 'Choose currency',
      searchHint: 'Search currencies',
      selectedValue: _currentDraft.currency,
      options: const [
        PickerOption(value: 'INR', title: 'Indian Rupee', subtitle: 'INR · ₹'),
        PickerOption(value: 'USD', title: 'US Dollar', subtitle: 'USD · \$'),
        PickerOption(value: 'EUR', title: 'Euro', subtitle: 'EUR · €'),
        PickerOption(value: 'GBP', title: 'British Pound', subtitle: 'GBP · £'),
        PickerOption(value: 'AED', title: 'UAE Dirham', subtitle: 'AED'),
        PickerOption(value: 'JPY', title: 'Japanese Yen', subtitle: 'JPY · ¥'),
      ],
    );
    if (next == null) return;
    setState(() => _currentDraft.currency = next);
  }

  Future<void> _chooseColor() async {
    final next = await showFullScreenPicker<Color>(
      context: context,
      title: 'Choose account color',
      searchable: false,
      selectedValue: _currentDraft.color,
      options: [
        for (final (index, color) in AppColors.accountPalette.indexed)
          PickerOption(
            value: color,
            title: 'Color ${index + 1}',
            subtitle:
                '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
            icon: Icons.circle,
            iconColor: color,
          ),
      ],
    );
    if (next == null) return;
    setState(() => _currentDraft.color = next);
  }

  void _back() {
    switch (_step) {
      case _OnboardingStep.profile:
        break;
      case _OnboardingStep.mainAccount:
        setState(() => _step = _OnboardingStep.profile);
        break;
      case _OnboardingStep.moreAccounts:
        if (_accounts.isNotEmpty) {
          _currentDraft = _accounts.removeLast();
          if (_accounts.isEmpty) {
            setState(() => _step = _OnboardingStep.mainAccount);
          } else {
            setState(() => _step = _OnboardingStep.extraAccount);
          }
        } else {
          setState(() => _step = _OnboardingStep.mainAccount);
        }
        break;
      case _OnboardingStep.extraAccount:
        setState(() => _step = _OnboardingStep.moreAccounts);
        break;
      case _OnboardingStep.permissions:
        setState(() => _step = _OnboardingStep.moreAccounts);
        break;
    }
  }

  Future<void> _nextOrComplete() async {
    if (_step == _OnboardingStep.profile) {
      if (_displayNameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your name.')));
        return;
      }
      if (_selectedUseCases.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least one use case.')));
        return;
      }
      setState(() => _step = _OnboardingStep.mainAccount);
      return;
    } 
    
    if (_step == _OnboardingStep.mainAccount || _step == _OnboardingStep.extraAccount) {
      if (_currentDraft.name.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter an account name.')));
        return;
      }
      _accounts.add(_AccountDraft(
        name: _currentDraft.name.trim(),
        type: _currentDraft.type,
        currency: _currentDraft.currency,
        color: _currentDraft.color,
        opening: _currentDraft.opening.trim(),
        icon: _currentDraft.icon,
      ));
      setState(() => _step = _OnboardingStep.moreAccounts);
      return;
    }

    if (_step == _OnboardingStep.moreAccounts) {
      setState(() => _step = _OnboardingStep.permissions);
      return;
    }

    final authUser = ref.read(authControllerProvider).user;
    if (authUser == null) {
      context.go('/login');
      return;
    }

    setState(() => _isCompleting = true);
    try {
      final currentLedger = ref.read(ledgerProvider);
      final hasExistingWallet = currentLedger.accounts.isNotEmpty || currentLedger.transactions.isNotEmpty;

      if (!hasExistingWallet && _accounts.isNotEmpty) {
        final baseAccount = _accounts.first;
        await ref.read(ledgerProvider.notifier).createStarterWallet(
              userId: authUser.id,
              accountName: baseAccount.name,
              currency: baseAccount.currency,
              accountColor: baseAccount.color,
              accountType: baseAccount.type,
              openingBalanceMinor: (double.tryParse(baseAccount.opening) ?? 0).toInt() * 100,
            );

        for (var i = 1; i < _accounts.length; i++) {
          final account = _accounts[i];
          await ref.read(ledgerProvider.notifier).upsertAccount(
                name: account.name,
                type: account.type,
                currency: account.currency,
                color: account.color,
                openingBalanceMinor: (double.tryParse(account.opening) ?? 0).toInt() * 100,
              );
        }
      }

      await ref
          .read(onboardingControllerProvider.notifier)
          .setCompleted(authUser.id, true);
      if (!mounted) return;
      context.go('/');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to finish setup: $error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCompleting = false);
    }
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.step});

  final _OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labels = ['Profile', 'Accounts', 'Permissions'];
    int displayStep = step == _OnboardingStep.profile ? 0 : (step == _OnboardingStep.permissions ? 2 : 1);
    
    return Row(
      children: [
        for (final (index, label) in labels.indexed) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: index <= displayStep
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppRadii.pill),
                border: Border.all(
                  color: index <= displayStep ? scheme.primary : scheme.outlineVariant,
                ),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: index <= displayStep
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          if (index != labels.length - 1) const SizedBox(width: AppSpacing.xs),
        ],
      ],
    );
  }
}

class _ProfileStep extends StatelessWidget {
  const _ProfileStep({
    required this.nameController,
    required this.selectedUseCases,
    required this.onToggleUseCase,
    super.key,
  });

  final TextEditingController nameController;
  final Set<String> selectedUseCases;
  final ValueChanged<String> onToggleUseCase;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const AnimatedBrandScene(
          message: 'Shape the first screen around how you handle money',
          compact: true,
        ),
        const SizedBox(height: AppSpacing.xl),
        SectionCard(
          title: 'Your profile',
          subtitle: 'Pick what matters most right now.',
          child: Column(
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              GridView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: AppSpacing.sm,
                  mainAxisSpacing: AppSpacing.sm,
                  childAspectRatio: 1.1,
                ),
                itemCount: _useCases.length,
                itemBuilder: (context, index) {
                  final item = _useCases[index];
                  final isSelected = selectedUseCases.contains(item.id);
                  return _UseCaseCard(
                    item: item,
                    selected: isSelected,
                    onTap: () => onToggleUseCase(item.id),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UseCaseCard extends StatelessWidget {
  const _UseCaseCard({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _UseCase item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant.withAlphaFactor(0.4),
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                item.icon,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
                size: 28,
              ),
              const Spacer(),
              Text(
                item.title,
                maxLines: 2,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: selected ? scheme.primary : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountStep extends StatelessWidget {
  const _AccountStep({
    required this.isMain,
    required this.draft,
    required this.onCurrency,
    required this.onColor,
    required this.onType,
    required this.onNameChanged,
    required this.onOpeningChanged,
    super.key,
  });

  final bool isMain;
  final _AccountDraft draft;
  final VoidCallback onCurrency;
  final VoidCallback onColor;
  final VoidCallback onType;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onOpeningChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String symbol = draft.currency;
    try {
      symbol = NumberFormat.simpleCurrency(name: draft.currency).currencySymbol;
    } catch (_) {}

    return Column(
      children: [
        _AccountPreviewCard(draft: draft),
        const SizedBox(height: AppSpacing.lg),
        SectionCard(
          title: isMain ? 'Main account' : 'Add account',
          subtitle: isMain 
              ? 'Start with the account you use most.' 
              : 'Create another wallet, card, cash, or loan account.',
          child: Column(
            children: [
              TextFormField(
                initialValue: draft.name,
                onChanged: onNameChanged,
                decoration: const InputDecoration(
                  labelText: 'Account name',
                  prefixIcon: Icon(Icons.drive_file_rename_outline),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _GridActionCard(
                      icon: draft.icon,
                      iconColor: draft.color,
                      label: 'Account type',
                      value: draft.type.toUpperCase(),
                      onTap: onType,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _GridActionCard(
                      icon: Icons.palette_outlined,
                      iconColor: draft.color,
                      label: 'Account color',
                      value: 'Selected',
                      onTap: onColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Card(
                elevation: 0,
                margin: EdgeInsets.zero,
                color: scheme.surfaceContainerHigh,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  side: BorderSide(color: scheme.outlineVariant.withAlphaFactor(0.4)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  onTap: onCurrency,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            symbol,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isMain ? 'Base Currency' : 'Currency',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                draft.currency,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                  color: scheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                initialValue: draft.opening,
                onChanged: onOpeningChanged,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: draft.type == 'loan' ? 'Outstanding principal' : 'Opening balance',
                  prefixIcon: Container(
                    padding: const EdgeInsets.only(top: 14, left: 14, right: 10),
                    child: Text(
                      symbol,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GridActionCard extends StatelessWidget {
  const _GridActionCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        side: BorderSide(color: scheme.outlineVariant.withAlphaFactor(0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: iconColor),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountPreviewCard extends StatelessWidget {
  const _AccountPreviewCard({required this.draft});

  final _AccountDraft draft;

  @override
  Widget build(BuildContext context) {
    String symbol = draft.currency;
    try {
      symbol = NumberFormat.simpleCurrency(name: draft.currency).currencySymbol;
    } catch (_) {}

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: draft.color,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: [
          BoxShadow(
            color: draft.color.withAlphaFactor(0.3),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(draft.icon, color: Colors.white, size: 32),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withAlphaFactor(0.2),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Text(
                  draft.type.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text(
            draft.name.isEmpty ? 'Account Name' : draft.name,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$symbol ${draft.opening.isEmpty ? '0.00' : draft.opening}',
            style: TextStyle(
              color: Colors.white.withAlphaFactor(0.8),
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreAccountsStep extends StatelessWidget {
  const _MoreAccountsStep({
    required this.accounts,
    required this.isCompleting,
    required this.onAddAnother,
    required this.onFinish,
    super.key,
  });

  final List<_AccountDraft> accounts;
  final bool isCompleting;
  final VoidCallback onAddAnother;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Your wallets',
      subtitle: 'Keep going now or finish setup.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final acc in accounts) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: acc.color.withAlphaFactor(0.1),
                border: Border.all(color: acc.color.withAlphaFactor(0.3)),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Row(
                children: [
                  Icon(acc.icon, color: acc.color),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          acc.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          acc.type.toUpperCase(),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Builder(
                    builder: (context) {
                      String symbol = acc.currency;
                      try {
                        symbol = NumberFormat.simpleCurrency(name: acc.currency).currencySymbol;
                      } catch (_) {}
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$symbol ${acc.opening.isEmpty ? '0.00' : acc.opening}',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            acc.currency,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(Icons.check_circle, color: acc.color, size: 20),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: isCompleting ? null : onAddAnother,
            icon: const Icon(Icons.add),
            label: const Text('Add another account'),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(
            onPressed: isCompleting ? null : onFinish,
            child: const Text('Finish setup'),
          ),
        ],
      ),
    );
  }
}

class _PermissionsStep extends StatelessWidget {
  const _PermissionsStep({
    required this.enableAutoCapture,
    required this.enableReminders,
    required this.onAutoCaptureChanged,
    required this.onRemindersChanged,
    super.key,
  });

  final bool enableAutoCapture;
  final bool enableReminders;
  final ValueChanged<bool> onAutoCaptureChanged;
  final ValueChanged<bool> onRemindersChanged;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Automation preferences',
      subtitle:
          'Choose which helpers to prepare. We ask for device permissions only when a feature needs them.',
      child: Column(
        children: [
          LiquidGlassSwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: enableAutoCapture,
            onChanged: onAutoCaptureChanged,
            icon: Icons.auto_awesome_outlined,
            title: const Text('Prepare auto-capture'),
            subtitle: const Text(
              'SMS, receipt, and notification review queues',
            ),
          ),
          LiquidGlassSwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: enableReminders,
            onChanged: onRemindersChanged,
            icon: Icons.notifications_active_outlined,
            title: const Text('Prepare reminders'),
            subtitle: const Text('Bills, review nudges, and update alerts'),
          ),
          const SizedBox(height: AppSpacing.sm),
          const InfoRow(
            icon: Icons.security_outlined,
            label: 'Permission requests',
            value: 'Later',
          ),
        ],
      ),
    );
  }
}

class _UseCase {
  const _UseCase(this.id, this.title, this.subtitle, this.icon);

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
}

const _useCases = [
  _UseCase('daily_spending', 'Daily spending', 'Track money moving in and out every day', Icons.account_balance_wallet_outlined),
  _UseCase('budgeting', 'Budgeting', 'Keep categories and limits visible', Icons.pie_chart_outline),
  _UseCase('bills_subscriptions', 'Bills and subscriptions', 'Plan repeat payments before they hit', Icons.calendar_today_outlined),
  _UseCase('cards_loans', 'Cards and loans', 'Watch dues, EMI, balances, and repayments', Icons.credit_card_outlined),
  _UseCase('business_self_employed', 'Business/self-employed', 'Separate income, expenses, and accounts', Icons.work_outline),
  _UseCase('investments_net_worth', 'Investments/net worth', 'See assets and liabilities together', Icons.trending_up_rounded),
];
