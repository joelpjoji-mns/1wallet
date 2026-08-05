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
                        children: [AuthProviderChip(user: user)],
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
            value: user?.isGoogleProvider == true ? 'Google' : 'Local',
            icon: user?.isGoogleProvider == true
                ? Icons.cloud_done_outlined
                : Icons.cloud_outlined,
            tone: user?.isGoogleProvider == true
                ? MetricTone.positive
                : MetricTone.standard,
          ),
          const SizedBox(height: AppSpacing.md),
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
            subtitle: themeState.accentColor ?? 'System Material You',
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
      subtitle: 'Advanced tools and detailed feature settings.',
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
