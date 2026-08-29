import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/app_reload.dart';
import 'app_update_provider.dart';

class UpdatesScreen extends ConsumerWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateProvider);
    final provider = ref.read(appUpdateProvider.notifier);

    final hasUpdate = state.latestRelease != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Updates'),
        actions: [
          IconButton(
            tooltip: 'Check for updates',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: state.status == UpdateStatus.checking
                ? null
                : () => provider.checkForUpdates(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeroCard(context, state, provider),
          if (hasUpdate) ...[
            const SizedBox(height: 16),
            _buildReleaseInfoCard(context, state.latestRelease!),
            const SizedBox(height: 16),
            _buildChangelogCard(
              context,
              state.latestRelease!.changelog,
              title: 'What\'s new in ${state.latestRelease!.versionName}',
            ),
          ],
          if (state.currentRelease != null && !hasUpdate) ...[
            const SizedBox(height: 16),
            _buildChangelogCard(
              context,
              state.currentRelease!.changelog,
              title: 'Current build changelog',
            ),
          ],
          if (state.status == UpdateStatus.downloading) ...[
            const SizedBox(height: 20),
            _buildDownloadProgress(context, state),
          ],
          const SizedBox(height: 24),
          _buildActionButtons(context, state, provider),
        ],
      ),
    );
  }

  Widget _buildHeroCard(
    BuildContext context,
    AppUpdateState state,
    AppUpdateProvider provider,
  ) {
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
      statusTitle = 'Checking for updates...';
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
      statusSubtitle = 'Version ${state.latestRelease?.versionName ?? ''} is downloaded';
      icon = Icons.download_done_rounded;
      color = scheme.primary;
    } else {
      statusTitle = 'Opening installer...';
      statusSubtitle = 'Confirm prompt to finish updating';
      icon = Icons.install_mobile_rounded;
      color = scheme.primary;
    }

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 24,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(icon, color: color, size: 24),
              ),
              title: Text(
                statusTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(statusSubtitle),
            ),
            if (hasUpdate) ...[
              const Divider(height: 24),
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
      ),
    );
  }

  Widget _buildReleaseInfoCard(BuildContext context, AppUpdateRelease release) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Release Details',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.info_outline),
              title: const Text('Version Code'),
              trailing: Text('${release.versionCode}'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: const Text('Published At'),
              trailing: Text(release.publishedAt.split('T').first),
            ),
            if (release.apk != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sd_storage),
                title: const Text('Size'),
                trailing: Text(
                  '${(release.apk!.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChangelogCard(
    BuildContext context,
    Changelog changelog, {
    required String title,
  }) {
    if (changelog.isEmpty) {
      return const SizedBox();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (changelog.newFeatures.isNotEmpty) ...[
              Text(
                'New Features',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              ...changelog.newFeatures.map(
                (f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(child: Text(f)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (changelog.bugFixes.isNotEmpty) ...[
              Text(
                'Bug Fixes',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              ...changelog.bugFixes.map(
                (f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(child: Text(f)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (changelog.notes.isNotEmpty) ...[
              Text(
                'Notes',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
              ...changelog.notes.map(
                (f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(child: Text(f)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadProgress(BuildContext context, AppUpdateState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Downloading...'),
            Text('${(state.progress * 100).toStringAsFixed(1)}%'),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: state.progress),
        const SizedBox(height: 4),
        Text(
          '${(state.bytesWritten / 1024 / 1024).toStringAsFixed(1)} / ${(state.bytesExpected / 1024 / 1024).toStringAsFixed(1)} MB',
          style: Theme.of(context).textTheme.bodySmall,
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'To apply this update, please use the button below to hard refresh the application. If that does not work, close the app entirely and reopen it.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, height: 1.5),
              ),
            ),
          const SizedBox(height: 16),
          if (state.latestRelease != null)
            FilledButton.icon(
              onPressed: reloadWebPage,
              icon: const Icon(Icons.refresh),
              label: const Text('Reload App'),
            ),
          if (state.latestRelease == null && state.status == UpdateStatus.idle)
            OutlinedButton.icon(
              onPressed: () => provider.checkForUpdates(),
              icon: const Icon(Icons.refresh),
              label: const Text('Check for Updates'),
            ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (state.latestRelease != null && state.status == UpdateStatus.idle)
          FilledButton.icon(
            onPressed: () => provider.downloadUpdate(),
            icon: const Icon(Icons.download),
            label: const Text('Download Update'),
          ),
        if (state.status == UpdateStatus.downloaded)
          FilledButton.icon(
            onPressed: () => provider.installUpdate(),
            icon: const Icon(Icons.install_mobile),
            label: const Text('Install Update'),
          ),
        if (state.latestRelease == null && state.status == UpdateStatus.idle)
          OutlinedButton.icon(
            onPressed: () => provider.checkForUpdates(),
            icon: const Icon(Icons.refresh),
            label: const Text('Check for Updates'),
          ),
      ],
    );
  }
}
