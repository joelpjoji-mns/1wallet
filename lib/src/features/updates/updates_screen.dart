import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_update_provider.dart';

class UpdatesScreen extends ConsumerWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateProvider);
    final provider = ref.read(appUpdateProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Updates'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatusCard(context, state, provider),
          const SizedBox(height: 16),
          if (state.latestRelease != null)
            _buildReleaseInfoCard(context, state.latestRelease!),
          const SizedBox(height: 16),
          if (state.latestRelease?.changelog != null)
            _buildChangelogCard(context, state.latestRelease!.changelog),
          const SizedBox(height: 24),
          if (state.status == UpdateStatus.downloading)
            _buildDownloadProgress(context, state),
          const SizedBox(height: 24),
          _buildActionButtons(context, state, provider),
        ],
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context, AppUpdateState state, AppUpdateProvider provider) {
    final theme = Theme.of(context);
    String title = 'Checking for updates...';
    String subtitle = '';
    IconData icon = Icons.sync;
    Color color = theme.colorScheme.primary;

    if (state.status == UpdateStatus.idle) {
      if (state.latestRelease != null) {
        title = 'Update Available';
        subtitle = 'Version ${state.latestRelease!.versionName} (${state.latestRelease!.channel})';
        icon = Icons.system_update;
        color = theme.colorScheme.secondary;
      } else {
        title = 'App is up to date';
        subtitle = 'You are on the latest version';
        icon = Icons.check_circle;
        color = theme.colorScheme.tertiary;
      }
    } else if (state.status == UpdateStatus.error) {
      title = 'Error checking for updates';
      subtitle = state.errorMessage ?? '';
      icon = Icons.error;
      color = theme.colorScheme.error;
    } else if (state.status == UpdateStatus.downloaded) {
      title = 'Update Ready to Install';
      subtitle = 'Tap install to apply the update';
      icon = Icons.download_done;
      color = theme.colorScheme.primary;
    }

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: DropdownButton<String>(
          value: state.channel,
          underline: const SizedBox(),
          items: const [
            DropdownMenuItem(value: 'stable', child: Text('Stable Channel')),
            DropdownMenuItem(value: 'beta', child: Text('Beta Channel')),
          ],
          onChanged: (val) {
            if (val != null) provider.setChannel(val);
          },
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
            Text('Release Details', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
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
                trailing: Text('${(release.apk!.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChangelogCard(BuildContext context, Changelog changelog) {
    if (changelog.newFeatures.isEmpty && changelog.bugFixes.isEmpty && changelog.notes.isEmpty) {
      return const SizedBox();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Changelog', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (changelog.newFeatures.isNotEmpty) ...[
              Text('New Features', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
              ...changelog.newFeatures.map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('• '), Expanded(child: Text(f))]),
              )),
              const SizedBox(height: 12),
            ],
            if (changelog.bugFixes.isNotEmpty) ...[
              Text('Bug Fixes', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.error)),
              ...changelog.bugFixes.map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('• '), Expanded(child: Text(f))]),
              )),
              const SizedBox(height: 12),
            ],
            if (changelog.notes.isNotEmpty) ...[
              Text('Notes', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.secondary)),
              ...changelog.notes.map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('• '), Expanded(child: Text(f))]),
              )),
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

  Widget _buildActionButtons(BuildContext context, AppUpdateState state, AppUpdateProvider provider) {
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
