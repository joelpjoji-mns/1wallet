import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/ledger_models.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart' show minorUnits;
import '../../auth/auth_controller.dart';
import '../launch/brand_widgets.dart';
import 'onboarding_controller.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:uuid/uuid.dart';
import '../../cloud_sync/cloud_sync_controller.dart';
import '../../data/ledger_providers.dart';
import '../../widgets/currency_picker.dart';
import '../../widgets/app_kit.dart';
import '../../utils/number_formatter.dart';

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

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  final _displayNameController = TextEditingController();
  final _selectedUseCases = <String>{'daily_spending'};

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
      if (auth.user?.displayName != null &&
          auth.user!.displayName!.isNotEmpty) {
        _displayNameController.text = auth.user!.displayName!;
      }
    });
  }

  void _resetDraft() {
    _currentDraft = _AccountDraft(
      name: '',
      type: 'bank',
      currency: _baseCurrency,
      color: Colors.blueAccent,
      opening: '',
      icon: Icons.account_balance_rounded,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 4) {
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
    final authUser = ref.read(authControllerProvider).user;
    if (authUser == null) return;

    // Save display name to Firebase Auth
    if (_displayNameController.text.trim().isNotEmpty) {
      await firebase_auth.FirebaseAuth.instance.currentUser?.updateDisplayName(
        _displayNameController.text.trim(),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Existing cloud wallet found. Restoring your wallet instead of creating a new account.',
            ),
          ),
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
            double.tryParse(
              draft.opening.replaceAll(RegExp(r'[^0-9.]'), ''),
            ) ??
            0;
        final openingBalanceMinor =
            (parsedOpening * math.pow(10, minorUnits(draft.currency))).round();
        await ledgerNotifier.upsertAccount(
          id: const Uuid().v4(),
          name: draft.name,
          type: draft.type,
          currency: draft.currency,
          openingBalanceMinor: openingBalanceMinor,
          color: draft.color,
        );
      }
    }

    await ref
        .read(onboardingControllerProvider.notifier)
        .setCompleted(authUser.id, true);

    // Force an immediate cloud upload so the brand-new wallet reaches
    // Firebase right away, before the user can clear app data or background
    // the app within the normal 2500ms upload debounce window.
    // Only needed for genuinely new wallets — if existing cloud data was
    // already restored, the sync controller handles uploads automatically.
    if (!hasExistingData) {
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
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.cloud_done_rounded,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Cloud Wallet Found',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We detected an existing wallet for your Google account. Your data is safe in Firebase.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () {
                      ref
                          .read(cloudSyncControllerProvider.notifier)
                          .retryBootstrap();
                      context.go('/launch');
                    },
                    icon: const Icon(Icons.restore_rounded),
                    label: const Text('Restore My Wallet'),
                  ),
                ],
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
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  children: [
                    if (_currentPage > 0)
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                        onPressed: _prevPage,
                      )
                    else
                      const SizedBox(width: 48),
                    const Spacer(),
                    Text(
                      'Step ${_currentPage + 1} of 5',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
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
                    _buildUseCasesStep(),
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
      padding: const EdgeInsets.all(24),
      children: [
        const StaggeredFadeIn(
          child: Text(
            'Welcome.\nLet\'s set you up.',
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w900,
              height: 1.1,
              letterSpacing: -1,
            ),
          ),
        ),
        const SizedBox(height: 32),
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
                const SizedBox(height: 8),
                AppGlassTextField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(
                    hintText: 'Your name',
                    filled: true,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Main currency',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                // Wrapped in its own transparent Material so ink splashes
                // paint above this row's background instead of being hidden
                // beneath BrandFrostedPanel's own DecoratedBox (Flutter
                // flags this combination as "background color or ink
                // splashes may be invisible" otherwise).
                Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    title: Text(_baseCurrency),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    tileColor: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
        StaggeredFadeIn(
          delay: const Duration(milliseconds: 200),
          child: FilledButton(
            onPressed: _nextPage,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            child: const Text('Continue'),
          ),
        ),
      ],
    );
  }

  Widget _buildUseCasesStep() {
    final useCases = [
      {
        'id': 'daily_spending',
        'title': 'Daily spending',
        'icon': Icons.coffee_rounded,
      },

      {
        'id': 'net_worth',
        'title': 'Net worth tracking',
        'icon': Icons.trending_up_rounded,
      },
      {
        'id': 'loans',
        'title': 'Loan EMIs',
        'icon': Icons.real_estate_agent_rounded,
      },
    ];

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const StaggeredFadeIn(
          child: Text(
            'What do you want\nto track?',
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w900,
              height: 1.1,
              letterSpacing: -1,
            ),
          ),
        ),
        const SizedBox(height: 32),
        StaggeredFadeIn(
          delay: const Duration(milliseconds: 100),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: useCases.map((uc) {
              final isSelected = _selectedUseCases.contains(uc['id']);
              return ChoiceChip(
                label: Text(uc['title'] as String),
                selected: isSelected,
                avatar: Icon(uc['icon'] as IconData, size: 18),
                onSelected: (v) {
                  setState(() {
                    if (v) {
                      _selectedUseCases.add(uc['id'] as String);
                    } else {
                      _selectedUseCases.remove(uc['id'] as String);
                    }
                  });
                },
                padding: const EdgeInsets.all(12),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 48),
        StaggeredFadeIn(
          delay: const Duration(milliseconds: 200),
          child: FilledButton(
            onPressed: _nextPage,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            child: const Text('Continue'),
          ),
        ),
      ],
    );
  }

  Widget _buildAccountStep() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const StaggeredFadeIn(
          child: Text(
            'Add your first\naccount.',
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w900,
              height: 1.1,
              letterSpacing: -1,
            ),
          ),
        ),
        const SizedBox(height: 32),
        StaggeredFadeIn(
          delay: const Duration(milliseconds: 100),
          child: BrandFrostedPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppGlassTextField(
                  onChanged: (v) => setState(() => _currentDraft.name = v),
                  decoration: const InputDecoration(
                    hintText: 'Account name (e.g. Cash, Savings)',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue:
                      const [
                        'bank',
                        'cash',
                        'credit_card',
                        'digital',
                        'savings',
                        'loan',
                        'investment',
                      ].contains(_currentDraft.type)
                      ? _currentDraft.type
                      : 'bank',
                  decoration: const InputDecoration(hintText: 'Account type'),
                  items:
                      [
                        'bank',
                        'cash',
                        'credit_card',
                        'digital',
                        'savings',
                        'loan',
                        'investment',
                      ].map((t) {
                        return DropdownMenuItem(
                          value: t,
                          child: Text(t.toUpperCase().replaceAll('_', ' ')),
                        );
                      }).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _currentDraft.type = v);
                  },
                ),
                const SizedBox(height: 16),
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
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
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
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            child: const Text('Save account'),
          ),
        ),
        TextButton(onPressed: _nextPage, child: const Text('Skip for now')),
      ],
    );
  }

  Widget _buildReviewAccountsStep() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const StaggeredFadeIn(
          child: Text(
            'Your accounts',
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w900,
              height: 1.1,
              letterSpacing: -1,
            ),
          ),
        ),
        const SizedBox(height: 32),
        if (_accounts.isEmpty)
          const Text('No accounts added yet.')
        else
          ..._accounts.map(
            (a) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlassCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.all(4),
                shape: LiquidRoundedSuperellipse(borderRadius: AppRadii.md),
                quality: GlassQuality.standard,
                child: ListTile(
                  leading: Icon(a.icon, color: a.color),
                  title: Text(
                    a.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('${a.opening} ${a.currency}'),
                ),
              ),
            ),
          ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: _nextPage,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          child: const Text('Looks good'),
        ),
      ],
    );
  }

  Widget _buildPermissionsStep() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const StaggeredFadeIn(
          child: Text(
            'Just one last\nthing.',
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w900,
              height: 1.1,
              letterSpacing: -1,
            ),
          ),
        ),
        const SizedBox(height: 32),
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
        const SizedBox(height: 48),
        StaggeredFadeIn(
          delay: const Duration(milliseconds: 200),
          child: FilledButton(
            onPressed: _nextPage,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            child: const Text('Finish Setup'),
          ),
        ),
      ],
    );
  }
}
