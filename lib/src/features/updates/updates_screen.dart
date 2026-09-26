import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../../design/tokens.dart';
import '../../utils/app_reload.dart';
import '../../widgets/app_kit.dart';
import 'app_update_provider.dart';

class UpdatesScreen extends ConsumerWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateProvider);
    final provider = ref.read(appUpdateProvider.notifier);

    final hasUpdate = state.latestRelease != null;

    return GlassScaffold(
        appBar: GlassAppBar(
          title: Text(
            'Updates',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          leading: Navigator.of(context).canPop()
              ? const AppBackAction()
              : null,
          centerTitle: false,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: GlassIconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: state.status == UpdateStatus.checking
                    ? null
                    : () => provider.checkForUpdates(),
                size: 44,
                iconSize: 22,
                
                semanticLabel: 'Check for updates',
              ),
            ),
          ],
        ),
        body: GlassIsolationScope(isolated: true, defaultQuality: GlassQuality.standard, child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          children: [
            _buildHeroCard(context, state),
            if (hasUpdate) ...[
              const SizedBox(height: AppSpacing.md),
              _buildReleaseInfoCard(context, state.latestRelease!),
              const SizedBox(height: AppSpacing.md),
              _buildChangelogCard(
                context,
                state.latestRelease!.changelog,
                title: "What's new in ${state.latestRelease!.versionName}",
              ),
            ],
            if (state.currentRelease != null && !hasUpdate) ...[
              const SizedBox(height: AppSpacing.md),
              _buildChangelogCard(
                context,
                state.currentRelease!.changelog,
                title: 'Current build changelog',
              ),
            ],
            if (state.status == UpdateStatus.downloading) ...[
              const SizedBox(height: AppSpacing.lg),
              _buildDownloadProgress(context, state),
            ],
            const SizedBox(height: AppSpacing.xl),
            _buildActionButtons(context, state, provider),
            // Bottom clearance so last button isn't hidden by bottom nav
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context, AppUpdateState state) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasUpdate = state.latestRelease != null;

    final versionName = state.currentVersionName.isEmpty
        ? 'Unknown'
        : state.currentVersionName;
    final versionCode = state.currentVersionCode == 0
        ? 'Unknown'
        : state.currentVersionCode.toString();

    String statusTitle;
    String statusSubtitle;
    IconData icon;
    Color color;

    if (state.status == UpdateStatus.checking) {
      statusTitle = 'Checking for updates…';
      statusSubtitle = 'Connecting to update servers';
      icon = Icons.sync_rounded;
      color = scheme.primary;
    } else if (state.status == UpdateStatus.idle) {
      if (hasUpdate) {
        statusTitle = 'Update Available';
        statusSubtitle = 'Version ${state.latestRelease!.versionName}';
        icon = Icons.system_update_rounded;
        color = scheme.primary;
      } else {
        statusTitle = 'App is up to date';
        statusSubtitle = 'Version $versionName (Build $versionCode)';
        icon = Icons.check_circle_rounded;
        color = scheme.primary;
      }
    } else if (state.status == UpdateStatus.error) {
      statusTitle = 'Update check unavailable';
      statusSubtitle = state.errorMessage ?? 'Could not reach update server';
      icon = Icons.error_outline_rounded;
      color = scheme.error;
    } else if (state.status == UpdateStatus.downloaded) {
      statusTitle = 'Update Ready to Install';
      statusSubtitle =
          'Version ${state.latestRelease?.versionName ?? ''} is downloaded';
      icon = Icons.download_done_rounded;
      color = scheme.primary;
    } else {
      statusTitle = 'Opening installer…';
      statusSubtitle = 'Confirm prompt to finish updating';
      icon = Icons.install_mobile_rounded;
      color = scheme.primary;
    }

    // Hero summary panel — static (non-scrolling within itself), so
    // GlassCard with standard quality is appropriate here.
    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(AppSpacing.md),
      shape: LiquidRoundedSuperellipse(
        borderRadius: AppRadii.lg,
      ),
      
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 24,
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(icon, color: color, size: 24),
            ),
            title: Text(
              statusTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              statusSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (hasUpdate) ...[
            Divider(
              height: AppSpacing.xl,
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Installed version',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '$versionName ($versionCode)',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReleaseInfoCard(
    BuildContext context,
    AppUpdateRelease release,
  ) {
    return GlassGroupedSection(
      header: Text('Release Details'),
      children: [
        GlassListTile(
          leading: Icon(
            Icons.tag_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: const Text('Version Code'),
          trailing: Text(
            '${release.versionCode}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        GlassDivider(),
        GlassListTile(
          leading: Icon(
            Icons.calendar_today_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: const Text('Published'),
          trailing: Text(
            release.publishedAt.split('T').first,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (release.apk != null) ...[
          GlassDivider(),
          GlassListTile(
            leading: Icon(
              Icons.sd_storage_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('Download size'),
            trailing: Text(
              '${(release.apk!.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildChangelogCard(
    BuildContext context,
    Changelog changelog, {
    required String title,
  }) {
    if (changelog.isEmpty) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;

    return GlassGroupedSection(
      header: Text(title),
      children: [
        if (changelog.newFeatures.isNotEmpty) ...[
          // Sub-section label for new features
          _ChangelogSectionLabel(label: 'New Features', color: scheme.primary),
          ...changelog.newFeatures.asMap().entries.map((entry) {
            final isLast = entry.key == changelog.newFeatures.length - 1 &&
                changelog.bugFixes.isEmpty &&
                changelog.notes.isEmpty;
            return _changelogItem(
              context,
              text: entry.value,
              icon: Icons.fiber_new_rounded,
              iconColor: scheme.primary,
              showDivider: !isLast,
            );
          }),
        ],
        if (changelog.bugFixes.isNotEmpty) ...[
          _ChangelogSectionLabel(label: 'Bug Fixes', color: scheme.error),
          ...changelog.bugFixes.asMap().entries.map((entry) {
            final isLast = entry.key == changelog.bugFixes.length - 1 &&
                changelog.notes.isEmpty;
            return _changelogItem(
              context,
              text: entry.value,
              icon: Icons.bug_report_outlined,
              iconColor: scheme.error,
              showDivider: !isLast,
            );
          }),
        ],
        if (changelog.notes.isNotEmpty) ...[
          _ChangelogSectionLabel(label: 'Notes', color: scheme.secondary),
          ...changelog.notes.asMap().entries.map((entry) {
            final isLast = entry.key == changelog.notes.length - 1;
            return _changelogItem(
              context,
              text: entry.value,
              icon: Icons.info_outline_rounded,
              iconColor: scheme.secondary,
              showDivider: !isLast,
            );
          }),
        ],
      ],
    );
  }

  Widget _changelogItem(
    BuildContext context, {
    required String text,
    required IconData icon,
    required Color iconColor,
    bool showDivider = true,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassListTile(
          leading: Icon(icon, size: 20, color: iconColor),
          title: Text(text),
        ),
        if (showDivider) GlassDivider(),
      ],
    );
  }

  Widget _buildDownloadProgress(BuildContext context, AppUpdateState state) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Downloading…',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${(state.progress * 100).toStringAsFixed(1)}%',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        LinearProgressIndicator(
          value: state.progress,
          
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          '${(state.bytesWritten / 1024 / 1024).toStringAsFixed(1)} / '
          '${(state.bytesExpected / 1024 / 1024).toStringAsFixed(1)} MB',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    AppUpdateState state,
    AppUpdateProvider provider,
  ) {
    if (kIsWeb) {
      return Column(
        children: [
          if (state.latestRelease != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(
                'To apply this update, please use the button below to hard '
                'refresh the application. If that does not work, close the '
                'app entirely and reopen it.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  height: 1.5,
                ),
              ),
            ),
          if (state.latestRelease != null) const SizedBox(height: AppSpacing.md),
          if (state.latestRelease != null)
            GlassButton(
              icon: const Icon(Icons.refresh_rounded),
              label: 'Reload App',
              onTap: reloadWebPage,
              
            ),
          if (state.latestRelease == null && state.status == UpdateStatus.idle)
            GlassButton(
              icon: const Icon(Icons.refresh_rounded),
              label: 'Check for Updates',
              onTap: () => provider.checkForUpdates(),
              
            ),
          if (state.status == UpdateStatus.error)
            GlassButton(
              icon: const Icon(Icons.refresh_rounded),
              label: 'Try Again',
              onTap: () => provider.checkForUpdates(),
              
            ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (state.latestRelease != null && state.status == UpdateStatus.idle)
          GlassButton(
            icon: const Icon(Icons.download_rounded),
            label: 'Download Update',
            onTap: () => provider.downloadUpdate(),
            
          ),
        if (state.status == UpdateStatus.downloaded)
          GlassButton(
            icon: const Icon(Icons.install_mobile_rounded),
            label: 'Install Update',
            onTap: () => provider.installUpdate(),
            
          ),
        if (state.latestRelease == null && state.status == UpdateStatus.idle)
          GlassButton(
            icon: const Icon(Icons.refresh_rounded),
            label: 'Check for Updates',
            onTap: () => provider.checkForUpdates(),
            
          ),
        // Errors previously left the action row empty, forcing users to find
        // the small app-bar refresh icon to retry a failed update check.
        if (state.status == UpdateStatus.error)
          GlassButton(
            icon: const Icon(Icons.refresh_rounded),
            label: 'Try Again',
            onTap: () => provider.checkForUpdates(),
            
          ),
      ],
    );
  }
}

/// An inlined sub-section label inside a [GlassGroupedSection].
///
/// Renders as a non-tappable [GlassListTile] styled as a compact heading,
/// so it blends naturally into the grouped glass surface without needing a
/// separate card or divider.
class _ChangelogSectionLabel extends StatelessWidget {
  const _ChangelogSectionLabel({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassListTile(
      title: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}


