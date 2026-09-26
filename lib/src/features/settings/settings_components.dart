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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AuthUserAvatar(
                    user: user,
                    radius: 28,
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
                        Text(
                          user?.email ?? 'Not signed in',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            user?.isGoogleProvider == true
                                ? Icons.cloud_done_outlined
                                : Icons.cloud_outlined,
                            size: 14,
                            color: user?.isGoogleProvider == true
                                ? Colors.green
                                : theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            user?.isGoogleProvider == true ? 'Google Sync' : 'Local',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FilledButton.tonal(
                            onPressed: onOpenSync,
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            child: const Text('Sync', style: TextStyle(fontSize: 12)),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          FilledButton.tonal(
                            onPressed: onSignOut,
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            child: const Text('Sign out', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
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
            width: 48,
            height: 32,
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
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(),
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


