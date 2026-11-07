import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/ledger_models.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart' show minorUnits, accountTypeLabel;
import '../../auth/auth_controller.dart';
import '../launch/brand_widgets.dart';
import 'onboarding_controller.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:uuid/uuid.dart';
import '../../cloud_sync/cloud_sync_controller.dart';
import '../../data/ledger_providers.dart';
import '../../widgets/color_picker_dialog.dart';
import '../../widgets/currency_picker.dart';
import '../../widgets/privacy_text.dart';
import '../../widgets/app_kit.dart';
import '../../utils/currency_utils.dart' show getCurrencyInfo;
import '../../utils/number_formatter.dart';
import '../common/full_screen_picker.dart';

IconData _iconForType(String type) {
  return switch (type) {
    'cash' => Icons.payments_outlined,
    'bank' => Icons.account_balance_outlined,
    'credit_card' || 'card' => Icons.credit_card_outlined,
    'savings' => Icons.savings_outlined,
    'digital' || 'wallet' => Icons.account_balance_wallet_outlined,
    'loan' || 'overdraft' => Icons.account_balance_outlined,
    'investment' => Icons.trending_up_rounded,
    _ => Icons.wallet_outlined,
  };
}

class _AccountDraft {
  String name;
  String institution;
  String type;
  String currency;
  Color color;
  String opening;
  IconData icon;

  _AccountDraft({
    required this.name,
    this.institution = '',
    required this.type,
    required this.currency,
    required this.color,
    required this.opening,
    required this.icon,
  });
}

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  final _displayNameController = TextEditingController();


  String _baseCurrency = kDefaultCurrency;
  final _accounts = <_AccountDraft>[];
  late _AccountDraft _currentDraft;

  bool _enableAutoCapture = true;
  bool _enableReminders = true;

  @override
  void initState() {
    super.initState();
    _resetDraft();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = ref.read(authControllerProvider);
      final name = auth.user?.displayName ?? auth.localDisplayName;
      if (name != null && name.isNotEmpty) {
        _displayNameController.text = name;
      }
    });
  }

  void _resetDraft() {
    _currentDraft = _AccountDraft(
      name: '',
      institution: '',
      type: 'bank',
      currency: _baseCurrency,
      color: AppColors.defaultAccountColor,
      opening: '',
      icon: _iconForType('bank'),
    );
  }

  Future<void> _chooseAccountType(BuildContext context) async {
    const types = [
      'bank',
      'cash',
      'credit_card',
      'digital',
      'savings',
      'loan',
      'investment',
    ];
    final selected = await showFullScreenPicker<String>(
      context: context,
      title: 'Account Type',
      searchHint: 'Search account types',
      selectedValue: _currentDraft.type,
      options: [
        for (final t in types)
          PickerOption(
            value: t,
            title: accountTypeLabel(t),
            icon: _iconForType(t),
            iconColor: _currentDraft.color,
          ),
      ],
    );
    if (selected != null) {
      setState(() {
        _currentDraft.type = selected;
        _currentDraft.icon = _iconForType(selected);
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finishOnboarding();
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _finishOnboarding() async {
    final auth = ref.read(authControllerProvider);
    final ownerId = auth.ownerId;
    if (ownerId == null) return;
    final offline = auth.isLocalOnly;

    final displayName = _displayNameController.text.trim();
    if (displayName.isNotEmpty) {
      if (offline) {
        // Offline mode keeps the name on this device only.
        await ref
            .read(authControllerProvider.notifier)
            .setLocalDisplayName(displayName);
      } else {
        await firebase_auth.FirebaseAuth.instance.currentUser
            ?.updateDisplayName(displayName);
      }
    }

    // Save preferences to ledger
    final ledgerNotifier = ref.read(ledgerProvider.notifier);
    final currentState = ref.read(ledgerProvider);

    var newPrefs = currentState.preferences.copyWith(
      baseCurrency: _baseCurrency,
      displayCurrency: _baseCurrency,
      enabledCurrencies: {_baseCurrency, kDefaultCurrency}.toList(),
    );
    if (!_enableReminders) {
      newPrefs = newPrefs.copyWith(notificationInboxEnabled: false);
    }
    // The "Auto-capture transactions" switch was previously read into
    // _enableAutoCapture but never written back to preferences, so opting
    // out during onboarding had no effect and SMS capture stayed on by
    // default. Honor an explicit opt-out here.
    if (!_enableAutoCapture) {
      newPrefs = newPrefs.copyWith(
        smsCaptureEnabled: false,
        notificationCaptureEnabled: false,
      );
    }
    await ledgerNotifier.updatePreferences(newPrefs);

    final cloudSync = ref.read(cloudSyncControllerProvider);
    if (cloudSync.hasCloudWallet) {
      // Guard: strictly refuse to overwrite cloud wallet from onboarding
      if (mounted) {
        showAppSnackBar(
          context,
          'Existing cloud wallet found. Restoring your wallet instead of creating a new account.',
        );
        ref.read(cloudSyncControllerProvider.notifier).retryBootstrap();
        context.go('/launch');
      }
      return;
    }

    // Guard: if wallet data already arrived (e.g. cloud restored while the
    // user was stepping through onboarding), skip creating new accounts to
    // prevent duplicates being pushed back over the real cloud backup.
    final ledgerAfterPrefs = ref.read(ledgerProvider);
    final hasExistingData =
        ledgerAfterPrefs.accounts.isNotEmpty ||
        ledgerAfterPrefs.transactions.isNotEmpty;

    if (!hasExistingData) {
      // Save accounts to ledger — only when we know there is no existing
      // wallet data; an empty ledger means this really is a fresh setup.
      for (final draft in _accounts) {
        final parsedOpening =
            double.tryParse(draft.opening.replaceAll(RegExp(r'[^0-9.]'), '')) ??
            0;
        final openingBalanceMinor =
            (parsedOpening * math.pow(10, minorUnits(draft.currency))).round();
        await ledgerNotifier.upsertAccount(
          id: const Uuid().v4(),
          name: draft.name,
          institution: draft.institution.trim().isEmpty ? null : draft.institution.trim(),
          type: draft.type,
          currency: draft.currency,
          openingBalanceMinor: openingBalanceMinor,
          color: draft.color,
        );
      }
    }

    await ref
        .read(onboardingControllerProvider.notifier)
        .setCompleted(ownerId, true);

    // Force an immediate cloud upload so the brand-new wallet reaches
    // Firebase right away, before the user can clear app data or background
    // the app within the normal 2500ms upload debounce window.
    // Only needed for genuinely new wallets — if existing cloud data was
    // already restored, the sync controller handles uploads automatically.
    // Offline mode never uploads.
    if (!hasExistingData && !offline) {
      unawaited(
        ref
            .read(cloudSyncControllerProvider.notifier)
            .uploadSnapshot(reason: 'onboarding'),
      );
    }

    if (!mounted) return;
    context.go('/permissions-setup');
  }

  @override
  Widget build(BuildContext context) {
    final cloudSync = ref.watch(cloudSyncControllerProvider);
    if (cloudSync.hasCloudWallet) {
      return Scaffold(
        body: LaunchBackdrop(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: BrandFrostedPanel(
                  borderRadius: AppRadii.xl,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.cloud_done_rounded,
                          size: 48,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Cloud Wallet Found',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'We detected an existing wallet for your Google account. Your data is safe in Firebase.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              height: 1.4,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      FilledButton.icon(
                        onPressed: () {
                          ref
                              .read(cloudSyncControllerProvider.notifier)
                              .retryBootstrap();
                          context.go('/launch');
                        },
                        style: AppButtonStyles.cta,
                        icon: const Icon(Icons.restore_rounded),
                        label: const Text('Restore My Wallet'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: LaunchBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Row(
                  children: [
                    if (_currentPage > 0)
                      HeaderIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onPressed: _prevPage,
                        semanticLabel: 'Back',
                        tooltip: 'Back',
                      )
                    else
                      const SizedBox(width: 48),
                    const Spacer(),
                    AppPanel(
                      glass: true,
                      radius: AppRadii.pill,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (int i = 0; i < 4; i++) ...[
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: i == _currentPage ? 16 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: i == _currentPage
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(AppRadii.pill),
                              ),
                            ),
                            if (i < 3) const SizedBox(width: 4),
                          ],
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            'Step ${_currentPage + 1} of 4',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  children: [
                    _buildProfileStep(),
                    _buildAccountStep(),
                    _buildReviewAccountsStep(),
                    _buildPermissionsStep(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileStep() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        StaggeredFadeIn(
          child: Text(
            'Welcome.\nLet\'s set you up.',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.1,
              letterSpacing: -1,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        StaggeredFadeIn(
          delay: const Duration(milliseconds: 100),
          child: BrandFrostedPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'What should we call you?',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppSpacing.xs),
                AppGlassTextField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(
                    hintText: 'Your name',
                    filled: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                const Text(
                  'Main currency',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppSpacing.xs),
                PremiumRow(
                  glass: true,
                  icon: Icons.currency_exchange_outlined,
                  title: _baseCurrency,
                  subtitle: getCurrencyInfo(_baseCurrency).name,
                  onTap: () async {
                    final curr = await showCurrencyPicker(
                      context: context,
                      state: ref.read(ledgerProvider),
                      selectedValue: _baseCurrency,
                    );
                    if (curr != null) {
                      setState(() {
                        _baseCurrency = curr;
                        _currentDraft.currency = curr;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        StaggeredFadeIn(
          delay: const Duration(milliseconds: 200),
          child: FilledButton(
            onPressed: _nextPage,
            style: AppButtonStyles.cta,
            child: const Text('Continue'),
          ),
        ),
      ],
    );
  }

  Widget _buildAccountPreviewCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = _currentDraft.name.trim().isEmpty
        ? 'Account Name'
        : _currentDraft.name.trim();
    final balance = _currentDraft.opening.trim().isEmpty
        ? '0.00'
        : _currentDraft.opening.trim();
    final typeLabel = accountTypeLabel(_currentDraft.type).toUpperCase();
    final badgeLabel = _currentDraft.institution.trim().isNotEmpty
        ? '${_currentDraft.institution.trim().toUpperCase()} • $typeLabel'
        : typeLabel;

    return AppPanel(
      glass: true,
      radius: AppRadii.lg,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _currentDraft.color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _currentDraft.color.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
                child: Icon(_currentDraft.icon, color: _currentDraft.color, size: 22),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  badgeLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: _currentDraft.name.trim().isEmpty
                  ? scheme.onSurface.withValues(alpha: 0.4)
                  : scheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '$balance ${_currentDraft.currency}',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorPicker() {
    final colors = AppColors.accountPalette.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Account accent color',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final c in colors)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: InkWell(
                    onTap: () => setState(() => _currentDraft.color = c),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _currentDraft.color == c
                              ? Colors.white
                              : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: [
                          if (_currentDraft.color == c)
                            BoxShadow(
                              color: c.withValues(alpha: 0.45),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                        ],
                      ),
                      child: _currentDraft.color == c
                          ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                          : null,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: InkWell(
                  onTap: () async {
                    final picked = await showAppColorPicker(
                      context: context,
                      initialColor: _currentDraft.color,
                      title: 'Choose account color',
                    );
                    if (picked != null) {
                      setState(() => _currentDraft.color = picked);
                    }
                  },
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .withValues(alpha: 0.5),
                      ),
                    ),
                    child: Icon(
                      Icons.colorize_rounded,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurface,
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

  Widget _buildAccountStep() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        StaggeredFadeIn(
          child: Text(
            'Add your first\naccount.',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.1,
              letterSpacing: -1,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        StaggeredFadeIn(
          delay: const Duration(milliseconds: 60),
          child: _buildAccountPreviewCard(),
        ),
        StaggeredFadeIn(
          delay: const Duration(milliseconds: 120),
          child: BrandFrostedPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Account name',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppSpacing.xs),
                AppGlassTextField(
                  onChanged: (v) => setState(() => _currentDraft.name = v),
                  decoration: const InputDecoration(
                    hintText: 'Account name (e.g. Cash, Savings)',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Account type',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppSpacing.xs),
                PremiumRow(
                  glass: true,
                  icon: _currentDraft.icon,
                  iconColor: _currentDraft.color.withValues(alpha: 0.25),
                  title: accountTypeLabel(_currentDraft.type),
                  subtitle: 'Tap to change account type',
                  onTap: () => _chooseAccountType(context),
                ),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Current balance',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppSpacing.xs),
                AppGlassTextField(
                  onChanged: (v) => setState(() => _currentDraft.opening = v),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [ThousandsSeparatorInputFormatter()],
                  decoration: InputDecoration(
                    hintText: 'Current balance',
                    suffixText: _currentDraft.currency,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Currency',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppSpacing.xs),
                PremiumRow(
                  glass: true,
                  icon: Icons.currency_exchange_outlined,
                  title: _currentDraft.currency,
                  subtitle: '${getCurrencyInfo(_currentDraft.currency).name} • Tap to change',
                  onTap: () async {
                    final curr = await showCurrencyPicker(
                      context: context,
                      state: ref.read(ledgerProvider),
                      selectedValue: _currentDraft.currency,
                    );
                    if (curr != null) {
                      setState(() {
                        _currentDraft.currency = curr;
                      });
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Institution / Bank name (optional)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppSpacing.xs),
                AppGlassTextField(
                  onChanged: (v) => setState(() => _currentDraft.institution = v),
                  decoration: const InputDecoration(
                    hintText: 'e.g. Chase, Revolut, Cash in wallet',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _buildColorPicker(),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        StaggeredFadeIn(
          delay: const Duration(milliseconds: 200),
          child: FilledButton(
            onPressed: () {
              if (_currentDraft.name.isNotEmpty) {
                setState(() {
                  _accounts.add(_currentDraft);
                  _resetDraft();
                });
                _nextPage();
              }
            },
            style: AppButtonStyles.cta,
            child: const Text('Save account'),
          ),
        ),
        TextButton(onPressed: _nextPage, child: const Text('Skip for now')),
      ],
    );
  }

  Widget _buildReviewAccountsStep() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        StaggeredFadeIn(
          child: Text(
            'Your accounts',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.1,
              letterSpacing: -1,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        if (_accounts.isEmpty)
          StaggeredFadeIn(
            delay: const Duration(milliseconds: 100),
            child: AppPanel(
              glass: true,
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 48,
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'No accounts added yet',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'You can always create accounts later from the Accounts tab.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          )
        else ...[
          for (int i = 0; i < _accounts.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppPanel(
                glass: true,
                padding: const EdgeInsets.all(AppSpacing.xxs),
                child: AppGroupedTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _accounts[i].color.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_accounts[i].icon, color: _accounts[i].color, size: 20),
                  ),
                  title: Text(_accounts[i].name),
                  subtitle: PrivacyText(
                    '${_accounts[i].opening.isEmpty ? '0.00' : _accounts[i].opening} ${_accounts[i].currency} • ${accountTypeLabel(_accounts[i].type)}${_accounts[i].institution.isNotEmpty ? ' (${_accounts[i].institution})' : ''}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Remove',
                    onPressed: () => setState(() => _accounts.removeAt(i)),
                  ),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: TextButton.icon(
              onPressed: () {
                _resetDraft();
                _pageController.animateToPage(
                  1,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                );
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add another account'),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        StaggeredFadeIn(
          delay: const Duration(milliseconds: 200),
          child: FilledButton(
            onPressed: _nextPage,
            style: AppButtonStyles.cta,
            child: const Text('Looks good'),
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionsStep() {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        StaggeredFadeIn(
          child: Text(
            'Just one last\nthing.',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w900,
              height: 1.1,
              letterSpacing: -1,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        StaggeredFadeIn(
          delay: const Duration(milliseconds: 100),
          child: BrandFrostedPanel(
            child: Column(
              children: [
                AppSwitchListTile(
                  title: const Text('Auto-capture transactions'),
                  subtitle: const Text(
                    'Scan SMS and notifications for expenses.',
                  ),
                  value: _enableAutoCapture,
                  onChanged: (v) => setState(() => _enableAutoCapture = v),
                ),
                AppSwitchListTile(
                  title: const Text('Reminders'),
                  subtitle: const Text(
                    'Get notified for upcoming bills and EMIs.',
                  ),
                  value: _enableReminders,
                  onChanged: (v) => setState(() => _enableReminders = v),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl + AppSpacing.md),
        StaggeredFadeIn(
          delay: const Duration(milliseconds: 200),
          child: FilledButton(
            onPressed: _nextPage,
            style: AppButtonStyles.cta,
            child: const Text('Finish Setup'),
          ),
        ),
      ],
    );
  }
}
