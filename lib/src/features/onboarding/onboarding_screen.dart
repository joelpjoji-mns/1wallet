import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/ledger_models.dart';
import '../../auth/auth_controller.dart';
import '../common/full_screen_picker.dart';
import '../launch/brand_widgets.dart';
import 'onboarding_controller.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:uuid/uuid.dart';
import '../../data/ledger_providers.dart';
import '../../data/ledger_providers.dart';
import '../../widgets/currency_picker.dart';
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
  final _selectedUseCases = <String>{'daily_spending', 'budgeting'};

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
      if (auth.user?.displayName != null && auth.user!.displayName!.isNotEmpty) {
        _displayNameController.text = auth.user!.displayName!;
      }
    });
  }

  void _resetDraft() {
    _currentDraft = _AccountDraft(
      name: '',
      type: 'checking',
      currency: _baseCurrency,
      color: Colors.blueAccent,
      opening: '',
      icon: Icons.account_balance_rounded,
    );
  }

  void _nextPage() {
    if (_currentPage < 4) {
      _pageController.nextPage(duration: const Duration(milliseconds: 600), curve: Curves.easeOutCubic);
    } else {
      _finishOnboarding();
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(duration: const Duration(milliseconds: 600), curve: Curves.easeOutCubic);
    }
  }

  Future<void> _finishOnboarding() async {
    final authUser = ref.read(authControllerProvider).user;
    if (authUser == null) return;
    
    // Save display name to Firebase Auth
    if (_displayNameController.text.trim().isNotEmpty) {
      await firebase_auth.FirebaseAuth.instance.currentUser?.updateDisplayName(_displayNameController.text.trim());
    }

    // Save preferences to ledger
    final ledgerNotifier = ref.read(ledgerProvider.notifier);
    final currentState = ref.read(ledgerProvider);
    
    var newPrefs = currentState.preferences.copyWith(
      baseCurrency: _baseCurrency,
      displayCurrency: _baseCurrency,
      enabledCurrencies: { _baseCurrency, kDefaultCurrency }.toList(),
    );
    if (!_enableReminders) {
      newPrefs = newPrefs.copyWith(notificationInboxEnabled: false);
    }
    await ledgerNotifier.updatePreferences(newPrefs);

    // Save accounts to ledger
    for (final draft in _accounts) {
      final parsedOpening = int.tryParse(draft.opening.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
      await ledgerNotifier.upsertAccount(
        id: const Uuid().v4(),
        name: draft.name,
        type: draft.type,
        currency: draft.currency,
        openingBalanceMinor: parsedOpening * 100,
        color: draft.color,
      );
    }
    
    await ref.read(onboardingControllerProvider.notifier).setCompleted(authUser.id, true);
    
    if (!mounted) return;
    context.go('/permissions-setup');
  }

  @override
  Widget build(BuildContext context) {
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
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
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
            style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -1),
          ),
        ),
        const SizedBox(height: 32),
        StaggeredFadeIn(
          delay: const Duration(milliseconds: 100),
          child: GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('What should we call you?', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(hintText: 'Your name', filled: true),
                ),
                const SizedBox(height: 24),
                const Text('Main currency', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ListTile(
                  title: Text(_baseCurrency),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  tileColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () async {
                    final curr = await showCurrencyPicker(
                      context: context,
                      state: ref.read(ledgerProvider),
                      selectedValue: _baseCurrency,
                    );
                    if (curr != null) setState(() => _baseCurrency = curr);
                  },
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
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            child: const Text('Continue'),
          ),
        ),
      ],
    );
  }

  Widget _buildUseCasesStep() {
    final useCases = [
      {'id': 'daily_spending', 'title': 'Daily spending', 'icon': Icons.coffee_rounded},
      {'id': 'budgeting', 'title': 'Budgeting', 'icon': Icons.pie_chart_rounded},
      {'id': 'net_worth', 'title': 'Net worth tracking', 'icon': Icons.trending_up_rounded},
      {'id': 'loans', 'title': 'Loan EMIs', 'icon': Icons.real_estate_agent_rounded},
    ];

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const StaggeredFadeIn(
          child: Text(
            'What do you want\nto track?',
            style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -1),
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
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
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
            'Add your first\nwallet.',
            style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -1),
          ),
        ),
        const SizedBox(height: 32),
        StaggeredFadeIn(
          delay: const Duration(milliseconds: 100),
          child: GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  onChanged: (v) => setState(() => _currentDraft.name = v),
                  decoration: const InputDecoration(hintText: 'Account name (e.g. Cash, Chase)'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _currentDraft.type,
                  decoration: const InputDecoration(hintText: 'Account Type'),
                  items: ['bank', 'cash', 'credit_card', 'digital', 'savings', 'loan', 'investment'].map((t) {
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
                TextField(
                  onChanged: (v) => setState(() => _currentDraft.opening = v),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [ThousandsSeparatorInputFormatter()],
                  decoration: InputDecoration(hintText: 'Current balance', suffixText: _currentDraft.currency),
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
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            child: const Text('Save Wallet'),
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
            'Your wallets',
            style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -1),
          ),
        ),
        const SizedBox(height: 32),
        if (_accounts.isEmpty)
          const Text('No accounts added yet.')
        else
          ..._accounts.map((a) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GlassCard(
              padding: const EdgeInsets.all(16),
              child: ListTile(
                leading: Icon(a.icon, color: a.color),
                title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${a.opening} ${a.currency}'),
              ),
            ),
          )),
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
            style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -1),
          ),
        ),
        const SizedBox(height: 32),
        StaggeredFadeIn(
          delay: const Duration(milliseconds: 100),
          child: GlassCard(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Auto-capture transactions'),
                  subtitle: const Text('Scan SMS and notifications for expenses.'),
                  value: _enableAutoCapture,
                  onChanged: (v) => setState(() => _enableAutoCapture = v),
                ),
                SwitchListTile(
                  title: const Text('Reminders'),
                  subtitle: const Text('Get notified for upcoming bills and EMIs.'),
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
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            child: const Text('Finish Setup'),
          ),
        ),
      ],
    );
  }
}
