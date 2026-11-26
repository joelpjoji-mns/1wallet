import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/ledger_models.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart' show minorUnits, accountTypeLabel;
import '../../auth/auth_controller.dart';
import '../launch/brand_widgets.dart';
import 'onboarding_controller.dart';
import 'discovery_controller.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:uuid/uuid.dart';
import '../../cloud_sync/cloud_sync_controller.dart';
import '../../data/ledger_providers.dart';
import '../../widgets/color_picker_dialog.dart';
import '../../widgets/currency_picker.dart';
import '../../widgets/privacy_text.dart';
import '../../widgets/app_kit.dart';
import '../../utils/currency_utils.dart' show getCurrencyInfo, iconForCurrency;
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
  final String id = const Uuid().v4();
  String name;
  String institution;
  String type;
  String currency;
  Color color;
  String opening;
  int openingBalanceMinor = 0;
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
  final _accountNameController = TextEditingController();
  final _openingBalanceController = TextEditingController();
  final _institutionController = TextEditingController();
  final _accountNameFocus = FocusNode();
  final _openingBalanceFocus = FocusNode();
  final _accountNameKey = GlobalKey();
  final _openingBalanceKey = GlobalKey();

  String _baseCurrency = kDefaultCurrency;
  final _accounts = <_AccountDraft>[];
  final _attemptedAccountIds = <String>{};
  late _AccountDraft _currentDraft;

  bool _enableAutoCapture = true;
  bool _enableReminders = true;
  bool _isFinishing = false;
  String? _accountNameError;
  String? _openingBalanceError;

  @override
  void initState() {
    super.initState();
    _resetDraft();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = ref.read(authControllerProvider);
      final name = auth.user?.displayName ?? auth.localDisplayName;
      if (name != null && name.isNotEmpty) {
        _displayNameController.text = name;
      }
    });
  }

  void _resetDraft() {
    _accountNameController.clear();
    _openingBalanceController.clear();
    _institutionController.clear();
    _accountNameError = null;
    _openingBalanceError = null;
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
    if (selected != null && mounted) {
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
    _accountNameController.dispose();
    _openingBalanceController.dispose();
    _institutionController.dispose();
    _accountNameFocus.dispose();
    _openingBalanceFocus.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_isFinishing) return;
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
    if (!_isFinishing && _currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _focusAccountField(GlobalKey key, FocusNode focus) {
    final fieldContext = key.currentContext;
    if (fieldContext != null) {
      unawaited(
        Scrollable.ensureVisible(
          fieldContext,
          alignment: 0.15,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
    }
    focus.requestFocus();
  }

  void _saveAccountDraft() {
    final name = _accountNameController.text.trim();
    final balance = parseDecimalMinorUnits(
      _openingBalanceController.text,
      minorUnits(_currentDraft.currency),
    );
    setState(() {
      _accountNameError = name.isEmpty
          ? 'Enter an account name before saving.'
          : null;
      _openingBalanceError = balance == null
          ? 'Enter a valid balance within the supported range.'
          : null;
    });
    if (name.isEmpty) {
      _focusAccountField(_accountNameKey, _accountNameFocus);
      return;
    }
    if (balance == null) {
      _focusAccountField(_openingBalanceKey, _openingBalanceFocus);
      return;
    }
    setState(() {
      _currentDraft.name = name;
      _currentDraft.openingBalanceMinor = balance;
      _accounts.add(_currentDraft);
      _resetDraft();
    });
    _nextPage();
  }

  void _toggleOpeningBalanceSign() {
    final value = _openingBalanceController.text;
    final next = value.startsWith('-') ? value.substring(1) : '-$value';
    _openingBalanceController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    setState(() {
      _currentDraft.opening = next;
      _openingBalanceError = null;
    });
    _openingBalanceFocus.requestFocus();
  }

  Future<void> _finishOnboarding() async {
    if (_isFinishing) return;
    if (_accounts.isEmpty) {
      showAppSnackBar(context, 'Add at least one account to finish setup.');
      _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    final auth = ref.read(authControllerProvider);
    final ownerId = auth.ownerId;
    if (ownerId == null) {
      showAppSnackBar(
        context,
        'Your session ended. Sign in again to finish setup.',
      );
      return;
    }
    final offline = auth.isLocalOnly;
    setState(() => _isFinishing = true);
    try {
      final displayName = _displayNameController.text.trim();
      if (displayName.isNotEmpty) {
        if (offline) {
          await ref
              .read(authControllerProvider.notifier)
              .setLocalDisplayName(displayName);
        } else {
          final user = firebase_auth.FirebaseAuth.instance.currentUser;
          if (user == null || user.uid != ownerId) {
            throw StateError('The signed-in session changed during setup.');
          }
          await user.updateDisplayName(displayName);
        }
      }

      if (!mounted) return;
      if (ref.read(authControllerProvider).ownerId != ownerId) {
        throw StateError('The wallet owner changed during setup.');
      }
      if (ref.read(cloudSyncControllerProvider).hasCloudWallet) {
        showAppSnackBar(
          context,
          'Existing cloud wallet found. Restoring your wallet instead of creating a new account.',
        );
        ref.read(cloudSyncControllerProvider.notifier).retryBootstrap();
        context.go('/launch');
        return;
      }

      final ledgerNotifier = ref.read(ledgerProvider.notifier);
      final discoveryNotifier = ref.read(
        discoveryControllerProvider(ownerId).notifier,
      );
      _attemptedAccountIds.addAll(_accounts.map((draft) => draft.id));
      final accounts = [
        for (var index = 0; index < _accounts.length; index++)
          Account(
            id: _accounts[index].id,
            name: _accounts[index].name,
            type: _accounts[index].type,
            currency: _accounts[index].currency,
            openingBalance: Money(
              amountMinor: _accounts[index].openingBalanceMinor,
              currency: _accounts[index].currency,
            ),
            institution: _accounts[index].institution.trim().isEmpty
                ? null
                : _accounts[index].institution.trim(),
            color: _accounts[index].color,
            sortOrder: index + 1,
          ),
      ];
      final initialized = await ledgerNotifier.initializeOnboardingWallet(
        ownerId: ownerId,
        accounts: accounts,
        attemptedAccountIds: Set.of(_attemptedAccountIds),
        updatePreferences: (preferences) => preferences.copyWith(
          baseCurrency: _baseCurrency,
          displayCurrency: _baseCurrency,
          enabledCurrencies: {_baseCurrency, kDefaultCurrency}.toList(),
          notificationInboxEnabled: _enableReminders,
          smsCaptureEnabled: _enableAutoCapture,
          notificationCaptureEnabled: _enableAutoCapture,
        ),
      );
      if (!initialized) {
        await ledgerNotifier.flushPendingWrites();
      }

      if (initialized && discoveryNotifier.mounted) {
        await discoveryNotifier.prepareWelcome();
      }
      if (!mounted) return;
      if (ref.read(authControllerProvider).ownerId != ownerId) {
        throw StateError('The wallet owner changed during setup.');
      }
      await ref
          .read(onboardingControllerProvider.notifier)
          .setCompleted(ownerId, true);

      if (!mounted) return;
      if (initialized && !offline) {
        unawaited(
          ref
              .read(cloudSyncControllerProvider.notifier)
              .uploadSnapshot(reason: 'onboarding'),
        );
      }
      if (!initialized && accounts.isNotEmpty) {
        showAppSnackBar(
          context,
          'Your existing wallet was kept. Add these accounts from Accounts.',
        );
      }

      context.go('/permissions-setup');
    } catch (error, stack) {
      debugPrint('Could not finish setup: ${error.runtimeType}');
      debugPrintStack(stackTrace: stack);
      if (mounted) {
        showAppSnackBar(
          context,
          'Could not finish setup. Check your connection or device storage and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isFinishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cloudSync = ref.watch(cloudSyncControllerProvider);
    if (cloudSync.hasCloudWallet) {
      return Scaffold(
        body: LaunchBackdrop(
          child: SafeArea(
            child: BrandPageViewport(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Center(
                child: BrandFrostedPanel(
                  borderRadius: AppRadii.xl,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.15),
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
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'We detected an existing wallet for your Google account. Your data is safe in Firebase.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                        label: const Text(
                          'Restore',
                          semanticsLabel: 'Restore my wallet',
                        ),
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
                        onPressed: _isFinishing ? null : _prevPage,
                        semanticLabel: 'Back',
                        tooltip: 'Back',
                      )
                    else
                      const SizedBox(width: 48),
                    Expanded(
                      child: Align(
                        child: AppPanel(
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
                                    borderRadius: BorderRadius.circular(
                                      AppRadii.pill,
                                    ),
                                  ),
                                ),
                                if (i < 3) const SizedBox(width: 4),
                              ],
                              const SizedBox(width: AppSpacing.xs),
                              Flexible(
                                child: Text(
                                  'Step ${_currentPage + 1} of 4',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.7),
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
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
      primary: false,
      physics: const ClampingScrollPhysics(),
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
                  icon: iconForCurrency(_baseCurrency),
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
                child: Icon(
                  _currentDraft.icon,
                  color: _currentDraft.color,
                  size: 22,
                ),
              ),
              Flexible(
                child: Tooltip(
                  message: badgeLabel,
                  excludeFromSemantics: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.35,
                      ),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      badgeLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
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
    // These names correspond to the first eight colors in accountPalette.
    const colorNames = [
      'Blue',
      'Forest green',
      'Taupe',
      'Bright violet',
      'Teal',
      'Terracotta',
      'Violet',
      'Olive green',
    ];
    final colors = AppColors.accountPalette.take(colorNames.length).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Account accent color',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (index, color) in colors.indexed)
                Tooltip(
                  message: '${colorNames[index]} account color',
                  excludeFromSemantics: true,
                  child: Semantics(
                    label: '${colorNames[index]} account color',
                    button: true,
                    selected: _currentDraft.color == color,
                    child: InkWell(
                      onTap: () => setState(() => _currentDraft.color = color),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _currentDraft.color == color
                                    ? Colors.white
                                    : Colors.transparent,
                                width: 2.5,
                              ),
                              boxShadow: [
                                if (_currentDraft.color == color)
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.45),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                              ],
                            ),
                            child: _currentDraft.color == color
                                ? const Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Tooltip(
                message: 'Choose custom account color',
                excludeFromSemantics: true,
                child: Semantics(
                  label: 'Choose custom account color',
                  button: true,
                  selected: !colors.contains(_currentDraft.color),
                  child: InkWell(
                    onTap: () async {
                      final picked = await showAppColorPicker(
                        context: context,
                        initialColor: _currentDraft.color,
                        title: 'Choose account color',
                      );
                      if (picked != null && mounted) {
                        setState(() => _currentDraft.color = picked);
                      }
                    },
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
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
    return SingleChildScrollView(
      primary: false,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          const SizedBox(height: AppSpacing.md),
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
                    key: _accountNameKey,
                    controller: _accountNameController,
                    focusNode: _accountNameFocus,
                    onChanged: (v) => setState(() {
                      _currentDraft.name = v;
                      _accountNameError = null;
                    }),
                    decoration: InputDecoration(
                      hintText: 'Account name (e.g. Cash)',
                      errorText: _accountNameError,
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
                    subtitle: 'Tap to change',
                    onTap: () => _chooseAccountType(context),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'Current balance',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppGlassTextField(
                    key: _openingBalanceKey,
                    controller: _openingBalanceController,
                    focusNode: _openingBalanceFocus,
                    onChanged: (v) => setState(() {
                      _currentDraft.opening = v;
                      _openingBalanceError = null;
                    }),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    inputFormatters: [
                      ThousandsSeparatorInputFormatter.signed(
                        ref.read(ledgerProvider).preferences.locale,
                      ),
                    ],
                    decoration: InputDecoration(
                      hintText: 'Current balance',
                      suffixText: _currentDraft.currency,
                      helperText:
                          'Use a negative balance for debts. Extra decimals are rounded.',
                      errorText: _openingBalanceError,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: _toggleOpeningBalanceSign,
                      child: const Text('Change sign'),
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
                    icon: iconForCurrency(_currentDraft.currency),
                    title: _currentDraft.currency,
                    subtitle: getCurrencyInfo(_currentDraft.currency).name,
                    onTap: () async {
                      final curr = await showCurrencyPicker(
                        context: context,
                        state: ref.read(ledgerProvider),
                        selectedValue: _currentDraft.currency,
                      );
                      if (curr != null && mounted) {
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
                    controller: _institutionController,
                    onChanged: (v) =>
                        setState(() => _currentDraft.institution = v),
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
              onPressed: _saveAccountDraft,
              style: AppButtonStyles.cta,
              child: const Text('Save account'),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton(onPressed: _nextPage, child: const Text('Skip for now')),
        ],
      ),
    );
  }

  Widget _buildReviewAccountsStep() {
    return ListView(
      primary: false,
      physics: const ClampingScrollPhysics(),
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
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.6),
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
                    'Add your first cash, bank or card account before finishing setup.',
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
                    child: Icon(
                      _accounts[i].icon,
                      color: _accounts[i].color,
                      size: 20,
                    ),
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
      primary: false,
      physics: const ClampingScrollPhysics(),
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
                  onChanged: _isFinishing
                      ? null
                      : (v) => setState(() => _enableAutoCapture = v),
                ),
                AppSwitchListTile(
                  title: const Text('Reminders'),
                  subtitle: const Text(
                    'Get notified for upcoming bills and EMIs.',
                  ),
                  value: _enableReminders,
                  onChanged: _isFinishing
                      ? null
                      : (v) => setState(() => _enableReminders = v),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl + AppSpacing.md),
        StaggeredFadeIn(
          delay: const Duration(milliseconds: 200),
          child: FilledButton(
            onPressed: _isFinishing ? null : _nextPage,
            style: AppButtonStyles.cta,
            child: Text(_isFinishing ? 'Finishing...' : 'Finish Setup'),
          ),
        ),
      ],
    );
  }
}
