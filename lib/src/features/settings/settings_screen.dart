import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../auth/auth_controller.dart';
import '../../cloud_sync/cloud_sync_controller.dart';
import '../../data/ledger_providers.dart';
import '../../data/ledger_models.dart';
import '../../design/tokens.dart';
import '../../theme/theme_controller.dart';
import '../../security/app_lock.dart';
import '../common/full_screen_picker.dart';
import '../common/route_scaffold.dart';
import '../onboarding/onboarding_controller.dart';
import 'account_deletion_controller.dart';
import 'offline_mode_section.dart';
import 'permission_setup_controller.dart';
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
    final appLock = ref.watch(appLockProvider);

    return RouteScaffold(
      title: 'Settings',
      child: GlassIsolationScope(
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
                    user: auth.profileUser,
                    offline: auth.isLocalOnly,
                    onSignOut: () => _signOut(ref),
                    onUpgrade: () => showOfflineUpgradeSheet(context),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  if (auth.isLocalOnly) ...[
                    const OfflineModeCard(),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // ── Privacy (prominent quick access) ──
                  _PrivacyQuickCard(
                    enabled: state.preferences.privacyModeEnabled,
                    onChanged: (value) {
                      ref
                          .read(ledgerProvider.notifier)
                          .updatePreferencesWith(
                            (livePreferences) => livePreferences.copyWith(
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
                          .updatePreferencesWith(
                            (livePreferences) => livePreferences.copyWith(
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
                        .updatePreferencesWith(preferences),
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
                                .updatePreferencesWith(
                                  (livePreferences) => livePreferences.copyWith(
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
                          'Allow scheduled-payment reminders on this device.',
                        ),
                        trailing: GlassSwitch(
                          quality: GlassQuality.standard,
                          value: state.preferences.deviceNotificationsEnabled,
                          onChanged: (value) {
                            ref
                                .read(ledgerProvider.notifier)
                                .updatePreferencesWith(
                                  (livePreferences) => livePreferences.copyWith(
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
                        leading: Icon(
                          Icons.event_repeat_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        title: const Text('Scheduled records'),
                        subtitle: const Text(
                          'Upcoming and overdue payments, transfers, bills, and income.',
                        ),
                        trailing: GlassSwitch(
                          quality: GlassQuality.standard,
                          value: state.preferences.channelScheduledEnabled,
                          onChanged: (value) {
                            ref
                                .read(ledgerProvider.notifier)
                                .updatePreferencesWith(
                                  (current) => current.copyWith(
                                    channelScheduledEnabled: value,
                                  ),
                                );
                            _showMessage(
                              value
                                  ? 'Scheduled records enabled'
                                  : 'Scheduled records paused',
                            );
                          },
                        ),
                      ),
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
                              .updatePreferencesWith(
                                (livePreferences) => livePreferences.copyWith(
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
                              .updatePreferencesWith(
                                (livePreferences) => livePreferences.copyWith(
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
                  const SizedBox(height: AppSpacing.md),

                  // ── Danger zone ──
                  // Offline mode has no account to delete; its wallet is
                  // managed through backups and Data backup instead.
                  if (!auth.isLocalOnly)
                    GlassGroupedSection(
                      header: Text(
                        'Danger zone',
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      children: [
                        GlassListTile(
                          leading: Icon(
                            Icons.delete_forever_rounded,
                            color: theme.colorScheme.error,
                          ),
                          title: Text(
                            'Delete account',
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: const Text(
                            'Delete this account\'s cloud data and its wallet on this device.',
                          ),
                          trailing: Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: theme.colorScheme.error,
                          ),
                          onTap: _showDeleteAccountDialog,
                        ),
                      ],
                    ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDeleteAccountDialog() async {
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _DeleteAccountDialog(),
    );

    if (!mounted) return;
    if (deleted == true) {
      _showMessage('Verified cloud and device account data were deleted.');
      context.go('/login');
    }
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
    // Signing out clears the device wallet; offline mode has no other copy.
    if (ref.read(authControllerProvider).isLocalOnly) return;
    await ref.read(ledgerProvider.notifier).flushAutoBackupBeforeSignOut();
    await ref.read(cloudSyncControllerProvider.notifier).handleSignOut();
    await ref.read(ledgerProvider.notifier).clearSessionOnSignOut();
    ref.read(onboardingControllerProvider.notifier).clear();
    ref.read(permissionSetupControllerProvider.notifier).clear();
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
  final ValueChanged<LedgerPreferences Function(LedgerPreferences)> onSave;

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

  void _save() {
    final blur = _blur;
    final fill = _fill;
    final refraction = _refraction;
    final interaction = _interaction;
    final shine = _shine;
    widget.onSave(
      (livePreferences) => livePreferences.copyWith(
        glassBlurLevel: blur,
        glassBackgroundOpacity: fill,
        glassRefractionLevel: refraction,
        glassInteractionStrength: interaction,
        glassSpecularOpacity: shine,
      ),
    );
  }

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
        _slider('Frosting', '${_blur.round()}', _blur, 18, (value) {
          setState(() => _blur = value);
          _save();
        }),
        _slider('Tint strength', '${(_fill * 100).round()}%', _fill, .5, (
          value,
        ) {
          setState(() => _fill = value);
          _save();
        }),
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
        _slider('Bounce', '${(_interaction * 100).round()}%', _interaction, 1, (
          value,
        ) {
          setState(() => _interaction = value);
          _save();
        }),
        _slider('Highlight', '${(_shine * 100).round()}%', _shine, 1, (value) {
          setState(() => _shine = value);
          _save();
        }),
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

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final _confirmationController = TextEditingController();
  bool _canDelete = false;

  @override
  void initState() {
    super.initState();
    _confirmationController.addListener(() {
      final matches =
          _confirmationController.text.trim().toUpperCase() == 'DELETE';
      if (matches != _canDelete) {
        setState(() => _canDelete = matches);
      }
    });
  }

  @override
  void dispose() {
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _onConfirmDelete() async {
    final success = await ref
        .read(accountDeletionControllerProvider.notifier)
        .deleteAccountAndAllData();
    if (success && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deletionState = ref.watch(accountDeletionControllerProvider);
    final isBusy = deletionState.isBusy;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: theme.colorScheme.error,
            size: 28,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Delete account & data?',
              style: TextStyle(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This action is irreversible. It deletes this account and verifies cleanup of its data:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text('• Local ledger, accounts, and transactions'),
            const Text('• All cloud backups and synced data in Firebase'),
            const Text('• This account\'s device backups and encryption keys'),
            const Text('• Account login credentials and profile'),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Other accounts, device-wide settings, older unassigned diagnostic history, '
              'exported copies, and disconnected devices are not erased by this operation. '
              'Unassigned history can be cleared explicitly in Capture diagnostics.',
            ),
            const SizedBox(height: AppSpacing.md),
            if (!isBusy) ...[
              const Text(
                'Type DELETE below to confirm:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _confirmationController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'DELETE',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                ),
              ),
            ],
            if (isBusy) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      deletionState.statusMessage,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ],
            if (deletionState.errorMessage != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Text(
                  deletionState.errorMessage!,
                  style: TextStyle(
                    color: theme.colorScheme.onErrorContainer,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: isBusy
              ? null
              : () {
                  ref.read(accountDeletionControllerProvider.notifier).reset();
                  Navigator.of(context).pop(false);
                },
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_canDelete && !isBusy) ? _onConfirmDelete : null,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          child: const Text('Delete everything'),
        ),
      ],
    );
  }
}
