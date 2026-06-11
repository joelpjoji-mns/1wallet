import 'package:flutter/material.dart';

import '../../auth/auth_user.dart';
import '../../data/ledger_models.dart';
import '../../design/tokens.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/user_identity_widgets.dart';

class SettingsProfileSection extends StatelessWidget {
  const SettingsProfileSection({
    required this.user,
    required this.onOpenSync,
    required this.onSignOut,
    super.key,
  });

  final AuthUser? user;
  final VoidCallback onOpenSync;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: 'Profile',
      subtitle: 'Current auth mode and account actions.',
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.colorScheme.primaryContainer.withAlpha(210),
                  theme.colorScheme.surfaceContainerHigh,
                  theme.colorScheme.tertiaryContainer.withAlpha(170),
                ],
              ),
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AuthUserAvatar(
                  user: user,
                  radius: 32,
                  fallbackLabel: user?.initials ?? '1W',
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.displayName ?? '1wallet account',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user?.email ?? 'Not signed in',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          AuthProviderChip(user: user),
                          AuthPhotoStatusChip(user: user),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          InfoRow(
            label: 'Signed in as',
            value: user?.email ?? 'Local user',
            icon: Icons.account_circle_outlined,
          ),
          InfoRow(
            label: 'Sync mode',
            value: 'Firebase ${user?.providerLabel ?? 'session'}',
            icon: user?.isGoogleProvider == true
                ? Icons.cloud_done_outlined
                : Icons.cloud_outlined,
            tone: user?.isGoogleProvider == true
                ? MetricTone.positive
                : MetricTone.standard,
          ),
          InfoRow(
            label: 'Profile photo',
            value: user?.photoUrl?.trim().isNotEmpty ?? false
                ? (user?.isGoogleProvider == true
                      ? 'Google profile photo active'
                      : 'Profile photo active')
                : 'Using avatar fallback',
            icon: Icons.photo_camera_front_outlined,
            tone: user?.photoUrl?.trim().isNotEmpty ?? false
                ? MetricTone.positive
                : MetricTone.warning,
          ),
          if (user?.displayName?.trim().isNotEmpty ?? false)
            InfoRow(
              label: 'Profile name',
              value: user!.displayName!.trim(),
              icon: Icons.badge_outlined,
            ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.tonalIcon(
                  onPressed: onOpenSync,
                  icon: const Icon(Icons.cloud_sync_outlined),
                  label: const Text('Open sync'),
                ),
                FilledButton.tonalIcon(
                  onPressed: onSignOut,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsPreferencesSection extends StatelessWidget {
  const SettingsPreferencesSection({
    required this.preferences,
    required this.themeState,
    required this.startDayController,
    required this.startDayValidationError,
    required this.onStartDayChanged,
    required this.onBaseCurrencyTap,
    required this.onLocaleTap,
    required this.onThemeTap,
    required this.onAccentTap,
    required this.localeLabel,
    super.key,
  });

  final LedgerPreferences preferences;
  final AppThemeState themeState;
  final TextEditingController startDayController;
  final String? startDayValidationError;
  final ValueChanged<String> onStartDayChanged;
  final VoidCallback onBaseCurrencyTap;
  final VoidCallback onLocaleTap;
  final VoidCallback onThemeTap;
  final VoidCallback onAccentTap;
  final String localeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: 'Preferences',
      subtitle: 'Used by reports, forms, and dashboard widgets.',
      child: Column(
        children: [
          PremiumRow(
            icon: Icons.currency_exchange_outlined,
            title: 'Base currency',
            subtitle: preferences.baseCurrency,
            meta: 'Default money unit',
            onTap: onBaseCurrencyTap,
          ),
          const SizedBox(height: AppSpacing.sm),
          PremiumRow(
            icon: Icons.language_outlined,
            title: 'Locale',
            subtitle: localeLabel,
            meta: preferences.locale.replaceAll('_', '-'),
            onTap: onLocaleTap,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                color: theme.colorScheme.primary,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Month starts on day',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (startDayValidationError != null)
                      Text(
                        startDayValidationError!,
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: 64,
                child: TextField(
                  controller: startDayController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                  ),
                  onChanged: onStartDayChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          PremiumRow(
            icon: Icons.palette_outlined,
            title: 'Theme',
            subtitle: switch (themeState.preference) {
              AppThemePreference.system => 'System',
              AppThemePreference.light => 'Light',
              AppThemePreference.dark => 'Dark',
              AppThemePreference.amoled => 'AMOLED',
            },
            meta: 'Material You color mode',
            onTap: onThemeTap,
          ),
          const SizedBox(height: AppSpacing.sm),
          PremiumRow(
            icon: Icons.color_lens_outlined,
            title: 'Accent',
            subtitle: themeState.accentColor ?? 'System default',
            meta: 'Drawer, buttons, navigation',
            onTap: onAccentTap,
          ),
        ],
      ),
    );
  }
}

class SettingsFeatureHubSection extends StatelessWidget {
  const SettingsFeatureHubSection({
    required this.links,
    required this.onOpenLink,
    super.key,
  });

  final List<(String, String, IconData, String)> links;
  final ValueChanged<String> onOpenLink;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Feature hub',
      subtitle: 'The overkill surfaces for the finance engine.',
      child: Column(
        children: [
          for (final (index, link) in links.indexed) ...[
            PremiumRow(
              icon: link.$3,
              title: link.$1,
              subtitle: link.$2,
              onTap: () => onOpenLink(link.$4),
            ),
            if (index < links.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class SettingsDataSection extends StatelessWidget {
  const SettingsDataSection({
    required this.state,
    required this.resetDialogVisible,
    required this.onOpenImports,
    required this.onOpenWalletCsv,
    required this.onShowReset,
    required this.onHideReset,
    required this.onConfirmReset,
    super.key,
  });

  final LedgerState state;
  final bool resetDialogVisible;
  final VoidCallback onOpenImports;
  final VoidCallback onOpenWalletCsv;
  final VoidCallback onShowReset;
  final VoidCallback onHideReset;
  final VoidCallback onConfirmReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      title: 'Data',
      subtitle: 'Useful while developing the local ledger.',
      child: Column(
        children: [
          InfoRow(
            label: 'Accounts',
            value: '${state.accounts.length}',
            icon: Icons.account_balance_wallet_outlined,
          ),
          InfoRow(
            label: 'Transactions',
            value: '${state.transactions.length}',
            icon: Icons.swap_horiz_rounded,
          ),
          InfoRow(
            label: 'Categories',
            value: '${state.categories.length}',
            icon: Icons.category_outlined,
          ),
          InfoRow(
            label: 'Budgets',
            value: '${state.budgets.length}',
            icon: Icons.donut_large_outlined,
          ),
          InfoRow(
            label: 'Goals',
            value: '${state.goals.length}',
            icon: Icons.flag_outlined,
          ),
          InfoRow(
            label: 'Capture candidates',
            value: '${state.captureCandidates.length}',
            icon: Icons.fact_check_outlined,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                onPressed: onOpenImports,
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('Import & backup'),
              ),
              FilledButton.tonalIcon(
                onPressed: onOpenWalletCsv,
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('Wallet CSV'),
              ),
              FilledButton.tonalIcon(
                onPressed: onShowReset,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Reset local ledger'),
              ),
            ],
          ),
          if (resetDialogVisible) ...[
            const SizedBox(height: AppSpacing.md),
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Reset local ledger?',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'This removes all accounts, transactions, and settings from local storage.',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: onHideReset,
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        FilledButton(
                          onPressed: onConfirmReset,
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.error,
                            foregroundColor: theme.colorScheme.onError,
                          ),
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
