import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../auth/auth_controller.dart';
import '../../data/ledger_providers.dart';
import '../../data/ledger_models.dart';
import '../../design/tokens.dart';
import '../../theme/theme_controller.dart';
import '../../security/app_lock.dart';
import '../common/full_screen_picker.dart';
import '../common/route_scaffold.dart';
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

  static const _notificationChannels = [
    (
      'scheduled',
      'Scheduled records',
      'Upcoming and overdue payments, transfers, bills, and income.',
      Icons.event_repeat_outlined,
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
    final appLock = ref.watch(appLockProvider);

    return RouteScaffold(
      title: 'Settings',
      child: GlassIsolationScope(
        isolated: true,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Profile ──
                  SettingsProfileSection(
                    user: user,
                    onSignOut: () => _signOut(ref),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // ── Privacy (prominent quick access) ──
                  _PrivacyQuickCard(
                    enabled: state.preferences.privacyModeEnabled,
                    onChanged: (value) {
                      ref
                          .read(ledgerProvider.notifier)
                          .updatePreferences(
                            state.preferences.copyWith(
                              privacyModeEnabled: value,
                            ),
                          );
                      _showMessage(
                        value
                            ? 'Privacy mode enabled'
                            : 'Privacy mode disabled',
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),

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
                    onThemeTap: () =>
                        _showThemePicker(ref, themeState.preference),
                    onHideSkippedChanged: (value) {
                      ref
                          .read(ledgerProvider.notifier)
                          .updatePreferences(
                            state.preferences.copyWith(
                              hideSkippedInHistory: value,
                            ),
                          );
                      _showMessage(
                        value
                            ? 'Skipped records hidden from history.'
                            : 'Skipped records shown in history.',
                      );
                    },
                    localeLabel: _localeLabel(state.preferences.locale),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  _GlassTuningSection(
                    preferences: state.preferences,
                    onSave: (preferences) => ref
                        .read(ledgerProvider.notifier)
                        .updatePreferences(preferences),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // ── Notifications ──
                  GlassGroupedSection(
                    header: const Text('Notifications'),
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
                        subtitle: const Text(
                          'Updates use native alerts when permission is granted.',
                        ),
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
                                  state.preferences.copyWith(
                                    quietHoursEnabled: value,
                                  ),
                                );
                            _showMessage(
                              value
                                  ? 'Quiet hours enabled'
                                  : 'Quiet hours disabled',
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
                                      prefs.copyWith(
                                        channelScheduledEnabled: value,
                                      ),
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
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),

                  GlassGroupedSection(
                    header: const Text('Account visibility'),
                    children: [
                      GlassListTile(
                        title: const Text('Show excluded accounts'),
                        subtitle: const Text(
                          'Include accounts excluded from totals in the account list.',
                        ),
                        trailing: GlassSwitch(
                          quality: GlassQuality.standard,
                          value: state.preferences.showExcludedAccounts,
                          onChanged: (value) => ref
                              .read(ledgerProvider.notifier)
                              .updatePreferences(
                                state.preferences.copyWith(
                                  showExcludedAccounts: value,
                                ),
                              ),
                        ),
                      ),
                      const GlassDivider(),
                      GlassListTile(
                        title: const Text('Show archived accounts'),
                        subtitle: const Text(
                          'Include archived accounts in the account list.',
                        ),
                        trailing: GlassSwitch(
                          quality: GlassQuality.standard,
                          value: state.preferences.showArchivedAccounts,
                          onChanged: (value) => ref
                              .read(ledgerProvider.notifier)
                              .updatePreferences(
                                state.preferences.copyWith(
                                  showArchivedAccounts: value,
                                ),
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // ── Security & Privacy ──
                  GlassGroupedSection(
                    header: const Text('Security & privacy'),
                    children: [
                      GlassListTile(
                        title: const Text('Biometric lock'),
                        subtitle: Text(
                          appLock.message ??
                              'Require biometrics or your device credential when opening the app.',
                        ),
                        trailing: IgnorePointer(
                          ignoring: appLock.busy,
                          child: GlassSwitch(
                            quality: GlassQuality.standard,
                            value: appLock.enabled,
                            onChanged: (value) async {
                              if (value) {
                                await ref
                                    .read(appLockProvider.notifier)
                                    .enable();
                                final current = ref.read(appLockProvider);
                                _showMessage(
                                  current.enabled
                                      ? 'App lock enabled on this device.'
                                      : current.message ??
                                            'App lock was not enabled.',
                                );
                              } else {
                                await ref
                                    .read(appLockProvider.notifier)
                                    .disable();
                                _showMessage(
                                  'App lock disabled on this device.',
                                );
                              }
                            },
                          ),
                        ),
                      ),
                      const GlassDivider(),
                      GlassListTile(
                        leading: const Icon(Icons.security_outlined),
                        title: const Text('Device permissions'),
                        subtitle: const Text(
                          'Manage camera, photos, and notification access.',
                        ),
                        trailing: const Icon(Icons.chevron_right, size: 20),
                        onTap: () => context.push('/device-permissions'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
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

class _GlassTuningSection extends StatefulWidget {
  const _GlassTuningSection({required this.preferences, required this.onSave});

  final LedgerPreferences preferences;
  final ValueChanged<LedgerPreferences> onSave;

  @override
  State<_GlassTuningSection> createState() => _GlassTuningSectionState();
}

class _GlassTuningSectionState extends State<_GlassTuningSection> {
  late double _blur;
  late double _fill;
  late double _refraction;
  late double _interaction;
  late double _shine;

  @override
  void initState() {
    super.initState();
    _readPreferences();
  }

  @override
  void didUpdateWidget(covariant _GlassTuningSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferences != widget.preferences) _readPreferences();
  }

  void _readPreferences() {
    final preferences = widget.preferences;
    _blur = preferences.glassBlurLevel.clamp(0, 18).toDouble();
    _fill = preferences.glassBackgroundOpacity.clamp(0, .5).toDouble();
    _refraction = preferences.glassRefractionLevel.clamp(0, 1).toDouble();
    _interaction = preferences.glassInteractionStrength.clamp(0, 1).toDouble();
    _shine = preferences.glassSpecularOpacity.clamp(.15, 1).toDouble();
  }

  void _save() => widget.onSave(
    widget.preferences.copyWith(
      glassBlurLevel: _blur,
      glassBackgroundOpacity: _fill,
      glassRefractionLevel: _refraction,
      glassInteractionStrength: _interaction,
      glassSpecularOpacity: _shine,
    ),
  );

  Widget _slider(
    String label,
    String value,
    double current,
    double max,
    ValueChanged<double> update,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(
                value,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          GlassSlider(
            value: current,
            min: 0,
            max: max,
            onChanged: update,
            onChangeEnd: (_) => _save(),
            label: label,
            quality: GlassQuality.standard,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassGroupedSection(
      header: const Text('Glass appearance'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            0,
          ),
          child: Text(
            'Tune the shared glass surfaces and interactions across the app.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        _slider(
          'Frosting',
          '${_blur.round()}',
          _blur,
          18,
          (value) {
            setState(() => _blur = value);
            _save();
          },
        ),
        _slider(
          'Tint strength',
          '${(_fill * 100).round()}%',
          _fill,
          .5,
          (value) {
            setState(() => _fill = value);
            _save();
          },
        ),
        _slider(
          'Refraction',
          '${(_refraction * 100).round()}%',
          _refraction,
          1,
          (value) {
            setState(() => _refraction = value);
            _save();
          },
        ),
        _slider(
          'Bounce',
          '${(_interaction * 100).round()}%',
          _interaction,
          1,
          (value) {
            setState(() => _interaction = value);
            _save();
          },
        ),
        _slider(
          'Highlight',
          '${(_shine * 100).round()}%',
          _shine,
          1,
          (value) {
            setState(() => _shine = value);
            _save();
          },
        ),
      ],
    );
  }
}

class _PrivacyQuickCard extends StatelessWidget {
  const _PrivacyQuickCard({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    void toggle() => onChanged(!enabled);
    return Semantics(
      label: 'Privacy mode',
      toggled: enabled,
      onTap: toggle,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: toggle,
        child: MergeSemantics(
          child: ExcludeFocus(
            child: ExcludeSemantics(
              child: GlassGroupedSection(
                children: [
                  GlassListTile(
                    leading: Icon(
                      enabled
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_outlined,
                    ),
                    title: const Text('Privacy mode'),
                    subtitle: Text(
                      enabled
                          ? 'Balances and amounts are hidden across the app.'
                          : 'Hide balances and amounts across the app.',
                    ),
                    trailing: IgnorePointer(
                      child: GlassSwitch(
                        quality: GlassQuality.standard,
                        value: enabled,
                        onChanged: onChanged,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
