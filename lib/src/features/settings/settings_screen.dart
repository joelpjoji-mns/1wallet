import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../auth/auth_controller.dart';
import '../../auth/auth_session_teardown.dart';
import '../../data/ledger_providers.dart';
import '../../data/ledger_models.dart';
import '../../design/tokens.dart';
import '../../theme/theme_controller.dart';
import '../../security/app_lock.dart';
import '../../widgets/app_kit.dart';
import '../common/full_screen_picker.dart';
import '../common/route_scaffold.dart';
import '../onboarding/onboarding_controller.dart';
import 'account_deletion_controller.dart';
import 'offline_mode_section.dart';
import 'permission_setup_controller.dart';
import 'settings_components.dart';
import 'glass_effect_screen.dart';
import 'theme_mode_screen.dart';
import '../updates/app_update_provider.dart';
import '../updates/play_store_update_service.dart';

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
                    onEditName: () => _editProfileName(
                      context,
                      ref,
                      auth.profileUser?.displayName ?? auth.localDisplayName,
                    ),
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
                    onThemeTap: () {
                      if (GoRouter.maybeOf(context) != null) {
                        context.push('/settings/theme');
                      } else {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ThemeModeScreen(),
                          ),
                        );
                      }
                    },
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

                  // ── Glass appearance ──
                  AppGroupedSection(
                    header: 'Glass appearance',
                    children: [
                      AppGroupedTile(
                        leading: const Icon(Icons.opacity_outlined),
                        title: const Text('Glass effect'),
                        subtitle: Text(
                          '${state.preferences.glassFinish.label} · ${_glassIntensityLabel(state.preferences.glassIntensity)}',
                        ),
                        showChevron: true,
                        onTap: () {
                          if (GoRouter.maybeOf(context) != null) {
                            context.push('/settings/glass');
                          } else {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const GlassEffectScreen(),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // ── Notifications ──
                  AppGroupedSection(
                    header: 'Notifications',
                    children: [
                      AppGroupedTile.toggle(
                        title: const Text('Notification inbox'),
                        subtitle: const Text('Active reminder alerts.'),
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
                      const GlassDivider(),
                      AppGroupedTile.toggle(
                        title: const Text('Device notifications'),
                        subtitle: const Text(
                          'Allow scheduled-payment reminders on this device.',
                        ),
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
                      const GlassDivider(),
                      AppGroupedTile.toggle(
                        leading: const Icon(Icons.event_repeat_outlined),
                        title: const Text('Scheduled records'),
                        subtitle: const Text(
                          'Upcoming and overdue payments, transfers, bills, and income.',
                        ),
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
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),

                  AppGroupedSection(
                    header: 'Account visibility',
                    children: [
                      AppGroupedTile.toggle(
                        title: const Text('Show excluded accounts'),
                        subtitle: const Text(
                          'Include accounts excluded from totals in the account list.',
                        ),
                        value: state.preferences.showExcludedAccounts,
                        onChanged: (value) => ref
                            .read(ledgerProvider.notifier)
                            .updatePreferencesWith(
                              (livePreferences) => livePreferences.copyWith(
                                showExcludedAccounts: value,
                              ),
                            ),
                      ),
                      const GlassDivider(),
                      AppGroupedTile.toggle(
                        title: const Text('Show archived accounts'),
                        subtitle: const Text(
                          'Include archived accounts in the account list.',
                        ),
                        value: state.preferences.showArchivedAccounts,
                        onChanged: (value) => ref
                            .read(ledgerProvider.notifier)
                            .updatePreferencesWith(
                              (livePreferences) => livePreferences.copyWith(
                                showArchivedAccounts: value,
                              ),
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // ── Security & Privacy ──
                  AppGroupedSection(
                    header: 'Security & privacy',
                    children: [
                      AppGroupedTile.toggle(
                        title: const Text('Biometric lock'),
                        subtitle: Text(
                          appLock.message ??
                              'Require biometrics or your device credential when opening the app.',
                        ),
                        value: appLock.enabled,
                        onChanged: appLock.busy
                            ? null
                            : (value) async {
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
                      const GlassDivider(),
                      AppGroupedTile(
                        leading: const Icon(Icons.security_outlined),
                        title: const Text('Device permissions'),
                        subtitle: const Text(
                          'Manage camera, photos, and notification access.',
                        ),
                        showChevron: true,
                        onTap: () => context.push('/device-permissions'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // ── App updates & version ──
                  const _AppUpdatesSection(),
                  const SizedBox(height: AppSpacing.md),

                  // ── Feedback & Support ──
                  AppGroupedSection(
                    header: 'Feedback & Support',
                    children: [
                      AppGroupedTile(
                        leading: const Icon(Icons.chat_bubble_outline_rounded),
                        title: const Text('Send Feedback & Diagnostics'),
                        subtitle: const Text(
                          'Report an issue, request features, or send logs to Joel',
                        ),
                        showChevron: true,
                        onTap: () => context.push('/settings/feedback'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // ── Danger zone ──
                  AppGroupedSection(
                    header: 'Danger zone',
                    destructive: true,
                    children: [
                      if (auth.isLocalOnly)
                        AppGroupedTile(
                          leading: const Icon(Icons.delete_sweep_rounded),
                          title: const Text('Clear all data'),
                          subtitle: const Text(
                            'Permanently erase this device\'s offline ledger, accounts, and transactions.',
                          ),
                          destructive: true,
                          showChevron: true,
                          onTap: _showClearOfflineDataDialog,
                        )
                      else
                        AppGroupedTile(
                          leading: const Icon(Icons.delete_forever_rounded),
                          title: const Text('Delete account'),
                          subtitle: const Text(
                            'Delete this account\'s cloud data and its wallet on this device.',
                          ),
                          destructive: true,
                          showChevron: true,
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

  Future<void> _showClearOfflineDataDialog() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Clear all wallet data?',
      message:
          'This will permanently erase all local accounts, transactions, and categories from this device. '
          'This action cannot be undone. Export a backup first from Data backup if you want to keep your records.',
      confirmLabel: 'Clear all data',
      destructive: true,
    );

    if (!mounted) return;
    if (confirmed == true) {
      await ref.read(ledgerProvider.notifier).purgeAllLocalData();
      ref.read(onboardingControllerProvider.notifier).clear();
      ref.read(permissionSetupControllerProvider.notifier).clear();
      await ref.read(authControllerProvider.notifier).setLocalDisplayName('');
      if (!mounted) return;
      _showMessage('All local wallet data has been cleared.');
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

  Future<void> _editProfileName(
    BuildContext context,
    WidgetRef ref,
    String? currentName,
  ) async {
    final controller = TextEditingController(text: currentName ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'Enter your name',
          ),
          onSubmitted: (val) => Navigator.of(ctx).pop(val),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != null) {
      final trimmed = saved.trim();
      if (trimmed.isNotEmpty) {
        await ref
            .read(authControllerProvider.notifier)
            .updateDisplayName(trimmed);
        if (!mounted) return;
        _showMessage('Name updated.');
      }
    }
  }

  bool _isSigningOut = false;

  Future<void> _signOut(WidgetRef ref) async {
    // Signing out clears the device wallet; offline mode has no other copy.
    if (_isSigningOut) return;
    if (ref.read(authControllerProvider).isLocalOnly) return;
    setState(() => _isSigningOut = true);
    try {
      await signOutAppSession(ref);
      if (!mounted) return;
      context.go('/login');
    } finally {
      if (mounted) {
        setState(() => _isSigningOut = false);
      }
    }
  }

  void _showMessage(String message) => showAppSnackBar(context, message);

  String _localeLabel(String locale) {
    return switch (locale) {
      'en_IN' => 'English (India)',
      'en_US' => 'English (United States)',
      'en_GB' => 'English (United Kingdom)',
      _ => locale,
    };
  }

  String _glassIntensityLabel(GlassIntensity intensity) {
    return switch (intensity) {
      GlassIntensity.light => 'Light',
      GlassIntensity.medium => 'Medium',
      GlassIntensity.heavy => 'Heavy',
    };
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
              child: AppGroupedSection(
                children: [
                  AppGroupedTile.toggle(
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
                    value: enabled,
                    onChanged: onChanged,
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
      icon: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
      title: const Text('Delete account & data?'),
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
              Text(
                'Type DELETE below to confirm:',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _confirmationController,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'DELETE'),
              ),
            ],
            if (isBusy) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  const AppInlineSpinner(size: 20),
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
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
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
          style: AppButtonStyles.destructiveFilled(context),
          child: const Text('Delete everything'),
        ),
      ],
    );
  }
}

class _AppUpdatesSection extends ConsumerWidget {
  const _AppUpdatesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final updateState = ref.watch(playStoreUpdateProvider);
    final packageInfo = ref.watch(packageInfoProvider).valueOrNull;

    final version = packageInfo?.version ?? '1.0.14';
    final buildNumber = packageInfo?.buildNumber ?? '14';

    Widget leadingIcon;
    String statusSubtitle;
    Widget? trailingWidget;
    VoidCallback? onUpdateTap;

    switch (updateState.status) {
      case PlayStoreUpdateStatus.checking:
        leadingIcon = const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
        statusSubtitle = 'Checking Google Play for updates...';
        trailingWidget = null;
        onUpdateTap = null;
        break;
      case PlayStoreUpdateStatus.downloading:
        leadingIcon = const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
        statusSubtitle = 'Downloading update from Google Play...';
        trailingWidget = null;
        onUpdateTap = null;
        break;
      case PlayStoreUpdateStatus.readyToInstall:
        leadingIcon = Icon(
          Icons.system_update_rounded,
          color: theme.colorScheme.primary,
        );
        statusSubtitle = 'Update downloaded and ready to install';
        trailingWidget = FilledButton.tonal(
          onPressed: () => ref
              .read(playStoreUpdateProvider.notifier)
              .completeFlexibleUpdate(),
          child: const Text('Restart'),
        );
        onUpdateTap = () => ref
            .read(playStoreUpdateProvider.notifier)
            .completeFlexibleUpdate();
        break;
      case PlayStoreUpdateStatus.updateAvailable:
        leadingIcon = Icon(
          Icons.new_releases_outlined,
          color: theme.colorScheme.primary,
        );
        statusSubtitle = 'New update available on Google Play';
        trailingWidget = FilledButton(
          onPressed: () => ref
              .read(playStoreUpdateProvider.notifier)
              .startFlexibleUpdate(),
          child: const Text('Update'),
        );
        onUpdateTap = () => ref
            .read(playStoreUpdateProvider.notifier)
            .startFlexibleUpdate();
        break;
      case PlayStoreUpdateStatus.upToDate:
        leadingIcon = Icon(
          Icons.check_circle_outline_rounded,
          color: theme.brightness == Brightness.dark
              ? AppColors.positiveDark
              : AppColors.positiveLight,
        );
        statusSubtitle = 'App is up to date';
        trailingWidget = TextButton(
          onPressed: () => ref
              .read(playStoreUpdateProvider.notifier)
              .checkForUpdate(autoTrigger: true),
          child: const Text('Check'),
        );
        onUpdateTap = () => ref
            .read(playStoreUpdateProvider.notifier)
            .checkForUpdate(autoTrigger: true);
        break;
      case PlayStoreUpdateStatus.failed:
        leadingIcon = Icon(
          Icons.sync_problem_rounded,
          color: theme.colorScheme.error,
        );
        statusSubtitle = 'Check failed. Tap to retry.';
        trailingWidget = TextButton(
          onPressed: () => ref
              .read(playStoreUpdateProvider.notifier)
              .checkForUpdate(autoTrigger: true),
          child: const Text('Retry'),
        );
        onUpdateTap = () => ref
            .read(playStoreUpdateProvider.notifier)
            .checkForUpdate(autoTrigger: true);
        break;
      case PlayStoreUpdateStatus.notSupported:
        leadingIcon = const Icon(Icons.info_outline_rounded);
        statusSubtitle = 'Google Play in-app updates available on Android';
        trailingWidget = null;
        onUpdateTap = null;
        break;
      case PlayStoreUpdateStatus.idle:
        leadingIcon = const Icon(Icons.system_update_alt_rounded);
        statusSubtitle = 'Check Google Play for updates';
        trailingWidget = TextButton(
          onPressed: () => ref
              .read(playStoreUpdateProvider.notifier)
              .checkForUpdate(autoTrigger: true),
          child: const Text('Check'),
        );
        onUpdateTap = () => ref
            .read(playStoreUpdateProvider.notifier)
            .checkForUpdate(autoTrigger: true);
        break;
    }

    return AppGroupedSection(
      header: 'App updates & version',
      children: [
        AppGroupedTile(
          leading: leadingIcon,
          title: Text('1Wallet v$version ($buildNumber)'),
          subtitle: Text(statusSubtitle),
          trailing: trailingWidget,
          onTap: onUpdateTap,
        ),
        const GlassDivider(),
        AppGroupedTile(
          leading: const Icon(Icons.auto_awesome_outlined),
          title: const Text("What's new"),
          subtitle: const Text('View release notes and recent improvements'),
          showChevron: true,
          onTap: () => _showWhatsNewSheet(context),
        ),
        const GlassDivider(),
        AppGroupedTile(
          leading: const Icon(Icons.shop_outlined),
          title: const Text('Google Play Store'),
          subtitle: const Text('View store listing, ratings, and reviews'),
          showChevron: true,
          onTap: () =>
              ref.read(playStoreUpdateProvider.notifier).openStoreListing(),
        ),
      ],
    );
  }
}

void _showWhatsNewSheet(BuildContext context) {
  showAppSheet<void>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final releases = kBuiltInReleaseHistory.take(4).toList();

      return AppSheetSurface(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: theme.colorScheme.onPrimaryContainer,
                    size: 22,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "What's New in 1Wallet",
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Recent releases & improvements',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            for (var i = 0; i < releases.length; i++) ...[
              _ReleaseCard(
                release: releases[i],
                isLatest: i == 0,
              ),
              if (i < releases.length - 1)
                const SizedBox(height: AppSpacing.md),
            ],
          ],
        ),
      );
    },
  );
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({
    required this.release,
    required this.isLatest,
  });

  final AppUpdateRelease release;
  final bool isLatest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changelog = release.changelog;

    return AppPanel(
      glass: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'v${release.versionName}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              if (isLatest)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    'Latest',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const Spacer(),
              Text(
                'Build ${release.versionCode}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (changelog.newFeatures.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '✨ New Features',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            for (final feature in changelog.newFeatures)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Text(
                        feature,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (changelog.bugFixes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '🛠️ Improvements & Fixes',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            for (final fix in changelog.bugFixes)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Text(
                        fix,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (changelog.notes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            for (final note in changelog.notes)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: Text(
                  note,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
