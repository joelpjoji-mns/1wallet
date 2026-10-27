import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../auth/auth_user.dart';
import '../../data/ledger_models.dart';
import '../../design/tokens.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/user_identity_widgets.dart';

class SettingsProfileSection extends StatelessWidget {
  const SettingsProfileSection({
    required this.user,
    required this.onSignOut,
    this.offline = false,
    this.onUpgrade,
    super.key,
  });

  final AuthUser? user;
  final VoidCallback onSignOut;

  /// Offline mode: shows the device-only badge and offers the Google upgrade
  /// instead of "Sign out" (which would strand the device-only wallet).
  final bool offline;
  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppPanel(
      glass: true,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            Row(
              children: [
                AuthUserAvatar(
                  user: user,
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
                          offline
                              ? Icons.phonelink_lock_outlined
                              : user?.isGoogleProvider == true
                              ? Icons.cloud_done_outlined
                              : Icons.cloud_outlined,
                          size: 14,
                          color: !offline && user?.isGoogleProvider == true
                              ? Colors.green
                              : theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          offline
                              ? 'Offline'
                              : user?.isGoogleProvider == true
                              ? 'Google Sync'
                              : 'Local',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton.tonal(
                          onPressed: offline ? onUpgrade : onSignOut,
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          child: Text(
                            offline ? 'Sync with Google' : 'Sign out',
                            style: const TextStyle(fontSize: 12),
                          ),
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
    return AppGroupedSection(
      header: 'Preferences',
      children: [
        AppGroupedTile(
          leading: const Icon(Icons.currency_exchange_outlined),
          title: const Text('Base currency'),
          subtitle: Text(preferences.baseCurrency),
          showChevron: true,
          onTap: onBaseCurrencyTap,
        ),
        const GlassDivider(),
        AppGroupedTile(
          leading: const Icon(Icons.language_outlined),
          title: const Text('Locale'),
          subtitle: Text(localeLabel),
          showChevron: true,
          onTap: onLocaleTap,
        ),
        const GlassDivider(),
        AppGroupedTile(
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
        AppGroupedTile(
          leading: const Icon(Icons.palette_outlined),
          title: const Text('Theme'),
          subtitle: Text(switch (themeState.preference) {
            AppThemePreference.system => 'System',
            AppThemePreference.light => 'Light',
            AppThemePreference.amoled => 'Dark',
          }),
          showChevron: true,
          onTap: onThemeTap,
        ),
        const GlassDivider(),
        AppGroupedTile.toggle(
          title: const Text('Hide skipped in history'),
          subtitle: const Text(
            'Hide skipped plan records from the main transaction history.',
          ),
          value: preferences.hideSkippedInHistory,
          onChanged: onHideSkippedChanged,
        ),
      ],
    );
  }
}
