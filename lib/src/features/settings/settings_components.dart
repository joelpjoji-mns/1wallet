import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../auth/auth_user.dart';
import '../../data/ledger_models.dart';
import '../../design/tokens.dart';
import '../../theme/theme_controller.dart';
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
    return GlassCard(
      quality: GlassQuality.premium,
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              Row(
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
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Icon(
                    Icons.account_circle_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Text('Signed in as'),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      user?.email ?? 'Local user',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Icon(
                    user?.isGoogleProvider == true
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_outlined,
                    size: 20,
                    color: user?.isGoogleProvider == true
                        ? Colors.green
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Text('Sync mode'),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      user?.isGoogleProvider == true ? 'Google' : 'Local',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
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
        ),
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
    required this.onHideSkippedChanged,
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
  final ValueChanged<bool> onHideSkippedChanged;
  final String localeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassGroupedSection(
      header: const Text('Preferences'),
      children: [
        GlassListTile(
          leading: const Icon(Icons.currency_exchange_outlined),
          title: const Text('Base currency'),
          subtitle: Text(preferences.baseCurrency),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: onBaseCurrencyTap,
        ),
        const GlassDivider(),
        GlassListTile(
          leading: const Icon(Icons.language_outlined),
          title: const Text('Locale'),
          subtitle: Text(localeLabel),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: onLocaleTap,
        ),
        const GlassDivider(),
        GlassListTile(
          leading: const Icon(Icons.calendar_today_outlined),
          title: const Text('Month starts on day'),
          subtitle: startDayValidationError != null
              ? Text(
                  startDayValidationError!,
                  style: TextStyle(color: theme.colorScheme.error),
                )
              : null,
          trailing: SizedBox(
            width: 64,
            child: Semantics(
              label: 'Month start day, 1 to 28',
              child: TextField(
                controller: startDayController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
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
          ),
        ),
        const GlassDivider(),
        GlassListTile(
          leading: const Icon(Icons.palette_outlined),
          title: const Text('Theme'),
          subtitle: Text(switch (themeState.preference) {
            AppThemePreference.system => 'System',
            AppThemePreference.light => 'Light',
            AppThemePreference.amoled => 'Dark',
          }),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: onThemeTap,
        ),
        const GlassDivider(),
        GlassListTile(
          leading: const Icon(Icons.color_lens_outlined),
          title: const Text('Accent'),
          subtitle: Text(themeState.accentColor ?? 'System Material You'),
          trailing: const Icon(Icons.chevron_right, size: 20),
          onTap: onAccentTap,
        ),
        const GlassDivider(),
        GlassListTile(
          title: const Text('Hide skipped in history'),
          subtitle: const Text(
            'Hide skipped plan records from the main transaction history.',
          ),
          trailing: GlassSwitch(
            quality: GlassQuality.standard,
            value: preferences.hideSkippedInHistory,
            onChanged: onHideSkippedChanged,
          ),
        ),
      ],
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
    return GlassGroupedSection(
      header: const Text('Feature hub'),
      children: [
        for (final (index, link) in links.indexed) ...[
          GlassListTile(
            leading: Icon(link.$3),
            title: Text(link.$1),
            subtitle: Text(link.$2),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => onOpenLink(link.$4),
          ),
          if (index < links.length - 1) const GlassDivider(),
        ],
      ],
    );
  }
}
