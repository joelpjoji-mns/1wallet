import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../auth/auth_controller.dart';
import '../../data/ledger_providers.dart';
import '../../data/ledger_models.dart';
import '../../design/tokens.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/color_picker_dialog.dart';
import '../common/full_screen_picker.dart';
import 'settings_components.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _startDayController = TextEditingController();
  var _startDayTouched = false;

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
      'Add, restore, and review Home tiles for cashflow, trends, and accounts.',
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

    return GlassScaffold(
      appBar: GlassAppBar(
        title: const Text('Settings'),
        actions: [
          GlassIconButton(size: 52, iconSize: 26,
            
            onPressed: () => context.push('/review'),
            icon: const Icon(Icons.fact_check_outlined),
          ),
        ],
      ),
      body: GlassIsolationScope(
        isolated: true,
        child: ListView(
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top + kToolbarHeight + AppSpacing.md,
            bottom: MediaQuery.paddingOf(context).bottom + AppSpacing.xl,
            left: AppSpacing.md,
            right: AppSpacing.md,
          ),
          children: [
            // ── Profile ──
            SettingsProfileSection(
              user: user,
              onOpenSync: () => context.push('/sync'),
              onSignOut: () => _signOut(ref),
            ),
            const SizedBox(height: AppSpacing.lg),

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
            const SizedBox(height: AppSpacing.lg),

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
              onHideSkippedChanged: (value) {
                ref
                    .read(ledgerProvider.notifier)
                    .updatePreferences(
                      state.preferences.copyWith(hideSkippedInHistory: value),
                    );
                _showMessage(
                  value
                      ? 'Skipped records hidden from history.'
                      : 'Skipped records shown in history.',
                );
              },
              localeLabel: _localeLabel(state.preferences.locale),
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Feature hub ──
            SettingsFeatureHubSection(
              links: _managementLinks,
              onOpenLink: (route) => context.push(route),
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Capture & automation ──
            GlassGroupedSection(header: const Text('Capture & automation'),
              children: [
                GlassListTile(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: const Text('Pending review'),
                  trailing: Text(
                    '$pendingCaptures',
                    style: TextStyle(
                      color: pendingCaptures > 0
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const GlassDivider(),
                const GlassListTile(
                  leading: Icon(Icons.sms_outlined),
                  title: Text('Auto capture'),
                  trailing: Text('SMS ready'),
                ),
                const GlassDivider(),
                const GlassListTile(
                  leading: Icon(Icons.table_chart_outlined),
                  title: Text('CSV imports'),
                  trailing: Text('Ready'),
                ),
                const GlassDivider(),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Wrap(
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
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Notifications ──
            GlassGroupedSection(header: const Text('Notifications'),
              children: [
                GlassListTile(
                  title: const Text('Notification inbox'),
                  subtitle: const Text('Active reminder alerts.'),
                  trailing: GlassSwitch(
                    quality: GlassQuality.standard,
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
                  ),
                ),
                const GlassDivider(),
                GlassListTile(
                  title: const Text('Device notifications'),
                  subtitle: const Text('Updates use native alerts when permission is granted.'),
                  trailing: GlassSwitch(
                    quality: GlassQuality.standard,
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
                  ),
                ),
                const GlassDivider(),
                GlassListTile(
                  title: const Text('Quiet hours'),
                  subtitle: const Text('22:00 to 07:00'),
                  trailing: GlassSwitch(
                    quality: GlassQuality.standard,
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
                  ),
                ),
                const GlassDivider(),
                for (final channel in _notificationChannels) ...[
                  GlassListTile(
                    leading: Icon(
                      channel.$4,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(channel.$2),
                    subtitle: Text(channel.$3),
                    trailing: GlassSwitch(
                      quality: GlassQuality.standard,
                      value: state.preferences.channelScheduledEnabled,
                      onChanged: (value) {
                        final prefs = state.preferences;
                        if (channel.$1 == 'scheduled') {
                          ref
                              .read(ledgerProvider.notifier)
                              .updatePreferences(
                                prefs.copyWith(channelScheduledEnabled: value),
                              );
                        }
                        _showMessage(
                          value
                              ? '${channel.$2} enabled'
                              : '${channel.$2} paused',
                        );
                      },
                    ),
                  ),
                  if (channel != _notificationChannels.last)
                    const GlassDivider(),
                ],
                const GlassDivider(),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () => context.push('/notifications'),
                      icon: const Icon(Icons.notifications_outlined),
                      label: const Text('Open notification inbox'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Security & Privacy ──
            GlassGroupedSection(header: const Text('Security & privacy'),
              children: [
                GlassListTile(
                  title: const Text('Biometric lock'),
                  subtitle: const Text('Requires a native security slice after the app shell is stable.'),
                  trailing: GlassSwitch(
                    quality: GlassQuality.standard,
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
                  ),
                ),
              ],
            ),
          ],
        ),
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
              AppThemePreference.amoled => 'True-black OLED surfaces',
            },
            icon: switch (preference) {
              AppThemePreference.system => Icons.brightness_auto_outlined,
              AppThemePreference.light => Icons.light_mode_outlined,
              AppThemePreference.amoled => Icons.dark_mode_outlined,
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
      AppThemePreference.amoled => 'Dark',
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
    return MergeSemantics(
      child: GlassCard(
        quality: GlassQuality.premium,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.xl),
          onTap: () => onChanged(!enabled),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
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
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
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
                ExcludeFocus(
                  child: IgnorePointer(
                    child: Switch(value: enabled, onChanged: onChanged),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



