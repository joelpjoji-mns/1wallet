import 'package:flutter/material.dart';
import '../common/route_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_controller.dart';
import '../../data/ledger_providers.dart';
import '../../data/ledger_models.dart';
import '../../design/tokens.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/color_picker_dialog.dart';
import '../common/full_screen_picker.dart';
import '../../widgets/bottom_island_nav.dart';
import 'settings_components.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _startDayController = TextEditingController();
  var _startDayTouched = false;
  var _resetDialogVisible = false;

  static const _localeOptions = [
    ('en_IN', 'English (India)', 'Dates and money formatted for India'),
    (
      'en_US',
      'English (United States)',
      'US date, number, and currency formatting',
    ),
    (
      'en_GB',
      'English (United Kingdom)',
      'UK date, number, and currency formatting',
    ),
  ];

  static const _accentOptions = [
    ('system', 'System themed', 'Use your phone Material You accent'),
    ('custom', 'Custom color', 'Pick a wallet accent color'),
  ];

  static const _notificationChannels = [
    (
      'scheduled',
      'Scheduled records',
      'Upcoming and overdue payments, transfers, bills, and income.',
      Icons.event_repeat_outlined,
    ),
    (
      'budgets',
      'Budgets',
      'Threshold and over-budget alerts.',
      Icons.donut_large_outlined,
    ),
    (
      'goals',
      'Goals',
      'Goal deadline and progress warnings.',
      Icons.flag_outlined,
    ),
  ];

  static const _managementLinks = [
    (
      'Sync',
      'Google sign-in, cloud restore, background upload, and sync status.',
      Icons.cloud_sync_outlined,
      '/sync',
    ),
    (
      'Device permissions',
      'Camera and photos access with a clear reason for each prompt.',
      Icons.security_outlined,
      '/device-permissions',
    ),
    (
      'Notifications',
      'Review work, reminders, budgets, accounts, cards, and import alerts.',
      Icons.notifications_outlined,
      '/notifications',
    ),
    (
      'Currencies',
      'Default currency, enabled currencies, exchange rates, and refresh status.',
      Icons.currency_exchange_outlined,
      '/currencies',
    ),
    (
      'Categories',
      'Expense and income trees, hidden stats, archive controls.',
      Icons.category_outlined,
      '/categories',
    ),
    (
      'Widgets',
      'Add, restore, and review Home tiles for cashflow, trends, budgets, goals, and accounts.',
      Icons.widgets_outlined,
      '/widgets',
    ),
    (
      'Import & backup',
      'CSV, Wallet exports, native backups, notification captures, and duplicate checks.',
      Icons.file_upload_outlined,
      '/imports',
    ),
    (
      'Cards',
      'Statement cycle, dues, utilization, and payment flows.',
      Icons.credit_card_outlined,
      '/cards',
    ),
    (
      'Loans & EMI',
      'Payoff calculator, schedules, and loan account tracking.',
      Icons.account_balance_outlined,
      '/loans',
    ),
    (
      'Recurring',
      'Bills, subscriptions, expected income, and reminders.',
      Icons.event_repeat_outlined,
      '/recurring',
    ),
  ];

  @override
  void initState() {
    super.initState();
    final state = ref.read(ledgerProvider);
    _startDayController.text = '${state.preferences.startDayOfMonth}';
  }

  @override
  void dispose() {
    _startDayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(ledgerProvider);
    final auth = ref.watch(authControllerProvider);
    final themeState = ref.watch(themeControllerProvider);
    final user = auth.user;
    final pendingCaptures = state.captureCandidates
        .where((c) => c.status == 'pending')
        .length;

    return RouteScaffold(
      title: 'Settings',
      actions: [
        IconButton(
          tooltip: 'Review queue',
          onPressed: () => context.push('/review'),
          icon: const Icon(Icons.fact_check_outlined),
        ),
      ],
      child: Column(
        children: [
          // ── Profile ──
          SettingsProfileSection(
            user: user,
            onOpenSync: () => context.push('/sync'),
            onSignOut: () => _signOut(ref),
          ),
          const Gap(AppSpacing.lg),

          // ── Privacy (prominent quick access) ──
          _PrivacyQuickCard(
            enabled: state.preferences.privacyModeEnabled,
            onChanged: (value) {
              ref
                  .read(ledgerProvider.notifier)
                  .updatePreferences(
                    state.preferences.copyWith(privacyModeEnabled: value),
                  );
              _showMessage(
                value ? 'Privacy mode enabled' : 'Privacy mode disabled',
              );
            },
          ),
          const Gap(AppSpacing.lg),

          // ── Preferences ──
          SettingsPreferencesSection(
            preferences: state.preferences,
            themeState: themeState,
            startDayController: _startDayController,
            startDayValidationError: _startDayValidationError,
            onStartDayChanged: (value) {
              _startDayTouched = true;
              _autoSaveStartDay(value);
            },
            onBaseCurrencyTap: () => context.push('/currencies'),
            onLocaleTap: () => _showLocalePicker(state),
            onThemeTap: () => _showThemePicker(ref, themeState.preference),
            onAccentTap: _showAccentPicker,
            localeLabel: _localeLabel(state.preferences.locale),
          ),
          const Gap(AppSpacing.lg),

          // ── Feature hub ──
          SettingsFeatureHubSection(
            links: _managementLinks,
            onOpenLink: (route) => context.push(route),
          ),
          const Gap(AppSpacing.lg),

          // ── Capture & automation ──
          SectionCard(
            title: 'Capture & automation',
            subtitle:
                'Manual review stays in control before automation posts anything.',
            child: Column(
              children: [
                InfoRow(
                  label: 'Pending review',
                  value: '$pendingCaptures',
                  icon: Icons.fact_check_outlined,
                  tone: pendingCaptures > 0
                      ? MetricTone.warning
                      : MetricTone.standard,
                ),
                const InfoRow(
                  label: 'Auto capture',
                  value: 'SMS ready',
                  icon: Icons.sms_outlined,
                  tone: MetricTone.positive,
                ),
                const InfoRow(
                  label: 'CSV imports',
                  value: 'Ready',
                  icon: Icons.table_chart_outlined,
                  tone: MetricTone.positive,
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => context.push('/review'),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Review queue'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => context.push('/notifications'),
                      icon: const Icon(Icons.notifications_outlined),
                      label: const Text('Notifications'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => context.push('/auto-capture'),
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: const Text('Auto capture'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),

          // ── Liquid Glass Appearance ──
          SectionCard(
            title: 'Liquid glass appearance',
            subtitle: 'Configure the glassmorphism blur and opacity levels.',
            child: Column(
              children: [
                const Gap(AppSpacing.md),
                // Liquid Glass Preview
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: 140,
                        width: double.infinity,
                        color: theme.colorScheme.surface,
                        child: ListView(
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(AppSpacing.md),
                          children: [
                            Container(
                              height: 60,
                              margin: const EdgeInsets.only(
                                bottom: AppSpacing.sm,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainer,
                                borderRadius: BorderRadius.circular(
                                  AppRadii.md,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const SizedBox(width: 16),
                                  CircleAvatar(
                                    backgroundColor: theme.colorScheme.primary
                                        .withAlphaFactor(0.2),
                                    radius: 16,
                                  ),
                                  const SizedBox(width: 16),
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        height: 10,
                                        width: 100,
                                        color: theme.colorScheme.onSurface
                                            .withAlphaFactor(0.2),
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        height: 8,
                                        width: 60,
                                        color: theme.colorScheme.onSurface
                                            .withAlphaFactor(0.1),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              height: 60,
                              margin: const EdgeInsets.only(
                                bottom: AppSpacing.sm,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainer,
                                borderRadius: BorderRadius.circular(
                                  AppRadii.md,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const SizedBox(width: 16),
                                  CircleAvatar(
                                    backgroundColor: theme.colorScheme.error
                                        .withAlphaFactor(0.2),
                                    radius: 16,
                                  ),
                                  const SizedBox(width: 16),
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        height: 10,
                                        width: 120,
                                        color: theme.colorScheme.onSurface
                                            .withAlphaFactor(0.2),
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        height: 8,
                                        width: 50,
                                        color: theme.colorScheme.onSurface
                                            .withAlphaFactor(0.1),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              height: 60,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainer,
                                borderRadius: BorderRadius.circular(
                                  AppRadii.md,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: BottomIslandNavBar(
                          items: const [
                            IslandTabItem(
                              title: 'Home',
                              icon: Icons.grid_view,
                              activeIcon: Icons.grid_view_rounded,
                            ),
                            IslandTabItem(
                              title: 'Records',
                              icon: Icons.receipt_long_outlined,
                              activeIcon: Icons.receipt_long_rounded,
                            ),
                            IslandTabItem(
                              title: 'Budgets',
                              icon: Icons.donut_small_outlined,
                              activeIcon: Icons.donut_small_rounded,
                            ),
                            IslandTabItem(
                              title: 'Accounts',
                              icon: Icons.account_balance_wallet_outlined,
                              activeIcon: Icons.account_balance_wallet,
                            ),
                          ],
                          selectedIndex: 0,
                          onSelected: (i) {},
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap(AppSpacing.lg),
                _SliderRow(
                  label: 'Specular opacity',
                  value: state.preferences.glassSpecularOpacity,
                  min: 0.0,
                  max: 1.0,
                  onChanged: (v) => ref
                      .read(ledgerProvider.notifier)
                      .updatePreferences(
                        state.preferences.copyWith(glassSpecularOpacity: v),
                      ),
                ),
                _SliderRow(
                  label: 'Specular saturation',
                  value: state.preferences.glassSpecularSaturation,
                  min: 0.0,
                  max: 2.0,
                  onChanged: (v) => ref
                      .read(ledgerProvider.notifier)
                      .updatePreferences(
                        state.preferences.copyWith(glassSpecularSaturation: v),
                      ),
                ),
                _SliderRow(
                  label: 'Refraction level',
                  value: state.preferences.glassRefractionLevel,
                  min: 0.0,
                  max: 1.0,
                  onChanged: (v) => ref
                      .read(ledgerProvider.notifier)
                      .updatePreferences(
                        state.preferences.copyWith(glassRefractionLevel: v),
                      ),
                ),
                _SliderRow(
                  label: 'Blur level',
                  value: state.preferences.glassBlurLevel,
                  min: 0.0,
                  max: 100.0,
                  onChanged: (v) => ref
                      .read(ledgerProvider.notifier)
                      .updatePreferences(
                        state.preferences.copyWith(glassBlurLevel: v),
                      ),
                ),
                _SliderRow(
                  label: 'Prog. blur strength',
                  value: state.preferences.glassProgressiveBlurStrength,
                  min: 0.0,
                  max: 1.0,
                  onChanged: (v) => ref
                      .read(ledgerProvider.notifier)
                      .updatePreferences(
                        state.preferences.copyWith(
                          glassProgressiveBlurStrength: v,
                        ),
                      ),
                ),
                _SliderRow(
                  label: 'Bg opacity',
                  value: state.preferences.glassBackgroundOpacity,
                  min: 0.0,
                  max: 1.0,
                  onChanged: (v) => ref
                      .read(ledgerProvider.notifier)
                      .updatePreferences(
                        state.preferences.copyWith(glassBackgroundOpacity: v),
                      ),
                ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),

          // ── Notifications ──
          SectionCard(
            title: 'Notifications',
            subtitle:
                'Actionable native alerts for updates and time-sensitive wallet items.',
            child: Column(
              children: [
                LiquidGlassSwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: state.preferences.notificationInboxEnabled,
                  onChanged: (value) {
                    ref
                        .read(ledgerProvider.notifier)
                        .updatePreferences(
                          state.preferences.copyWith(
                            notificationInboxEnabled: value,
                          ),
                        );
                    _showMessage(
                      value
                          ? 'Notification inbox enabled.'
                          : 'Notification inbox paused.',
                    );
                  },
                  title: const Text('Notification inbox'),
                  subtitle: Text(
                    'Active reminder, budget, or goal alerts.',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Divider(height: 1),
                LiquidGlassSwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: state.preferences.deviceNotificationsEnabled,
                  onChanged: (value) {
                    ref
                        .read(ledgerProvider.notifier)
                        .updatePreferences(
                          state.preferences.copyWith(
                            deviceNotificationsEnabled: value,
                          ),
                        );
                    _showMessage(
                      value
                          ? 'Device notifications enabled.'
                          : 'Device notifications disabled.',
                    );
                  },
                  title: const Text('Device notifications'),
                  subtitle: Text(
                    'Updates use native alerts when permission is granted.',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Divider(height: 1),
                LiquidGlassSwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: state.preferences.quietHoursEnabled,
                  onChanged: (value) {
                    ref
                        .read(ledgerProvider.notifier)
                        .updatePreferences(
                          state.preferences.copyWith(quietHoursEnabled: value),
                        );
                    _showMessage(
                      value ? 'Quiet hours enabled' : 'Quiet hours disabled',
                    );
                  },
                  title: const Text('Quiet hours'),
                  subtitle: Text(
                    '22:00 to 07:00',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Divider(height: 1),
                for (final channel in _notificationChannels) ...[
                  LiquidGlassSwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: channel.$1 == 'scheduled'
                        ? state.preferences.channelScheduledEnabled
                        : channel.$1 == 'budgets'
                        ? state.preferences.channelBudgetsEnabled
                        : state.preferences.channelGoalsEnabled,
                    onChanged: (value) {
                      final prefs = state.preferences;
                      if (channel.$1 == 'scheduled') {
                        ref
                            .read(ledgerProvider.notifier)
                            .updatePreferences(
                              prefs.copyWith(channelScheduledEnabled: value),
                            );
                      } else if (channel.$1 == 'budgets') {
                        ref
                            .read(ledgerProvider.notifier)
                            .updatePreferences(
                              prefs.copyWith(channelBudgetsEnabled: value),
                            );
                      } else {
                        ref
                            .read(ledgerProvider.notifier)
                            .updatePreferences(
                              prefs.copyWith(channelGoalsEnabled: value),
                            );
                      }
                      _showMessage(
                        value
                            ? '${channel.$2} enabled'
                            : '${channel.$2} paused',
                      );
                    },
                    title: Row(
                      children: [
                        Icon(
                          channel.$4,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            channel.$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(left: 28),
                      child: Text(
                        channel.$3,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  if (channel != _notificationChannels.last)
                    const Divider(height: 1),
                ],
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () => context.push('/notifications'),
                    icon: const Icon(Icons.notifications_outlined),
                    label: const Text('Open notification inbox'),
                  ),
                ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),

          // ── Security & Privacy ──
          SectionCard(
            title: 'Security & privacy',
            subtitle: 'Privacy mode is available up top and in the sidebar.',
            child: Column(
              children: [
                LiquidGlassSwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: state.preferences.biometricLockEnabled,
                  onChanged: (value) {
                    ref
                        .read(ledgerProvider.notifier)
                        .updatePreferences(
                          state.preferences.copyWith(
                            biometricLockEnabled: value,
                          ),
                        );
                    _showMessage(
                      value
                          ? 'Biometric lock enabled'
                          : 'Biometric lock disabled',
                    );
                  },
                  title: const Text('Biometric lock'),
                  subtitle: Text(
                    'Requires a native security slice after the app shell is stable.',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),

          // ── Data ──
          SettingsDataSection(
            state: state,
            resetDialogVisible: _resetDialogVisible,
            onOpenImports: () => context.push('/imports'),
            onOpenWalletCsv: () => context.push('/import-wallet-csv'),
            onShowReset: () => setState(() => _resetDialogVisible = true),
            onHideReset: () => setState(() => _resetDialogVisible = false),
            onConfirmReset: () => _resetLedger(ref),
          ),
        ],
      ),
    );
  }

  String? get _startDayValidationError {
    if (!_startDayTouched) return null;
    final parsed = int.tryParse(_startDayController.text.trim());
    if (parsed == null) return 'Enter a number';
    if (parsed < 1 || parsed > 28) return 'Must be 1 – 28';
    return null;
  }

  void _autoSaveStartDay(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed < 1 || parsed > 28) {
      setState(() {});
      return;
    }
    ref.read(ledgerProvider.notifier).setStartDayOfMonth(parsed);
    setState(() {});
    _showMessage('Month start day updated.');
  }

  Future<void> _showLocalePicker(LedgerState state) async {
    final next = await showFullScreenPicker<String>(
      context: context,
      title: 'Locale',
      searchable: false,
      selectedValue: state.preferences.locale,
      options: [
        for (final locale in _localeOptions)
          PickerOption(
            value: locale.$1,
            title: locale.$2,
            subtitle: locale.$3,
            icon: Icons.language_outlined,
          ),
      ],
    );
    if (next == null) return;
    await ref.read(ledgerProvider.notifier).setLocale(next);
    if (!mounted) return;
    _showMessage('Locale updated.');
  }

  Future<void> _showThemePicker(
    WidgetRef ref,
    AppThemePreference selected,
  ) async {
    final next = await showFullScreenPicker<AppThemePreference>(
      context: context,
      title: 'Theme mode',
      searchable: false,
      selectedValue: selected,
      options: [
        for (final preference in AppThemePreference.values)
          PickerOption(
            value: preference,
            title: _themePreferenceLabel(preference),
            subtitle: switch (preference) {
              AppThemePreference.system => 'Follow device light/dark mode',
              AppThemePreference.light => 'Bright Material 3 surfaces',
              AppThemePreference.dark => 'Dark navy surfaces',
              AppThemePreference.amoled => 'True-black OLED surfaces',
            },
            icon: switch (preference) {
              AppThemePreference.system => Icons.brightness_auto_outlined,
              AppThemePreference.light => Icons.light_mode_outlined,
              AppThemePreference.dark => Icons.dark_mode_outlined,
              AppThemePreference.amoled => Icons.brightness_2_outlined,
            },
          ),
      ],
    );
    if (next == null) return;
    await ref.read(themeControllerProvider.notifier).setPreference(next);
    if (!mounted) return;
    _showMessage('Theme preference saved.');
  }

  Future<void> _showAccentPicker() async {
    final next = await showFullScreenPicker<String>(
      context: context,
      title: 'Accent source',
      searchable: false,
      selectedValue: ref.read(themeControllerProvider).accentColor == null
          ? 'system'
          : 'custom',
      options: [
        for (final accent in _accentOptions)
          PickerOption(
            value: accent.$1,
            title: accent.$2,
            subtitle: accent.$3,
            icon: accent.$1 == 'system'
                ? Icons.smartphone_outlined
                : Icons.palette_outlined,
          ),
      ],
    );
    if (next == null || !mounted) return;
    if (next == 'custom') {
      final currentColor = ref.read(themeControllerProvider).accentColor;
      Color initialColor = Theme.of(context).colorScheme.primary;
      if (currentColor != null &&
          currentColor.length == 7 &&
          currentColor.startsWith('#')) {
        final intValue = int.tryParse(currentColor.substring(1), radix: 16);
        if (intValue != null) {
          initialColor = Color(intValue | 0xFF000000);
        }
      }

      final color = await showAppColorPicker(
        context: context,
        initialColor: initialColor,
        title: 'Custom accent',
      );
      if (color != null && mounted) {
        final hex =
            '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
        await ref.read(themeControllerProvider.notifier).setAccentColor(hex);
        if (!mounted) return;
        _showMessage('Custom accent saved: $hex');
      }
    } else {
      await ref.read(themeControllerProvider.notifier).setAccentColor(null);
      if (!mounted) return;
      _showMessage('System accent enabled.');
    }
  }

  Future<void> _signOut(WidgetRef ref) async {
    await ref.read(authControllerProvider.notifier).signOut();
    if (!mounted) return;
    context.go('/login');
  }

  Future<void> _resetLedger(WidgetRef ref) async {
    setState(() => _resetDialogVisible = false);
    await ref.read(ledgerProvider.notifier).resetLedger();
    if (!mounted) return;
    _showMessage('Local ledger reset.');
    context.go('/');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  String _themePreferenceLabel(AppThemePreference preference) {
    return switch (preference) {
      AppThemePreference.system => 'System',
      AppThemePreference.light => 'Light',
      AppThemePreference.dark => 'Dark',
      AppThemePreference.amoled => 'AMOLED',
    };
  }

  String _localeLabel(String locale) {
    return switch (locale) {
      'en_IN' => 'English (India)',
      'en_US' => 'English (United States)',
      'en_GB' => 'English (United Kingdom)',
      _ => locale,
    };
  }
}

class _PrivacyQuickCard extends StatelessWidget {
  const _PrivacyQuickCard({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        onTap: () => onChanged(!enabled),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.xl),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: enabled
                  ? [
                      scheme.primaryContainer,
                      scheme.tertiaryContainer.withAlpha(160),
                    ]
                  : [
                      scheme.surfaceContainerHigh,
                      scheme.surfaceContainerLow,
                    ],
            ),
            border: Border.all(
              color: enabled
                  ? scheme.primary.withAlpha(120)
                  : scheme.outlineVariant.withAlpha(160),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primary.withAlpha(enabled ? 60 : 30),
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                ),
                child: Icon(
                  enabled
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_outlined,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Privacy mode',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      enabled
                          ? 'Balances and amounts are hidden across the app.'
                          : 'Hide balances and amounts across the app.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IgnorePointer(
                child: Switch(value: enabled, onChanged: onChanged),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              max == 1.0 ? '${(value * 100).round()}%' : '${value.round()}',
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
