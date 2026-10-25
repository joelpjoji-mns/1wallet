import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../design/tokens.dart';
import '../../utils/app_reload.dart';
import '../../widgets/app_kit.dart';
import '../common/route_scaffold.dart';
import 'app_update_provider.dart';

/// Update screen inspired by the Morphe Manager update experience, featuring
/// an expressive hero status banner, version transition indicators, a vertical
/// timeline changelog with categorized change badges, inline code formatting,
/// and a circular download progress ring.
class UpdatesScreen extends ConsumerStatefulWidget {
  const UpdatesScreen({super.key});

  @override
  ConsumerState<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends ConsumerState<UpdatesScreen> {
  final Set<String> _expandedSections = <String>{};

  bool _isSectionExpanded(String sectionKey) =>
      _expandedSections.contains(sectionKey);

  void _toggleSectionExpanded(String sectionKey) {
    setState(() {
      if (_expandedSections.contains(sectionKey)) {
        _expandedSections.remove(sectionKey);
      } else {
        _expandedSections.add(sectionKey);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appUpdateProvider);
    final provider = ref.read(appUpdateProvider.notifier);
    final hasUpdate = state.latestRelease != null;

    return RouteScaffold(
      title: 'Updates',
      actions: [
        Tooltip(
          message: 'Check for updates',
          child: HeaderIconButton(
            icon: Icons.refresh_rounded,
            onPressed: state.status == UpdateStatus.checking
                ? null
                : () => provider.checkForUpdates(force: true),
            semanticLabel: 'Check for updates',
          ),
        ),
      ],
      child: GlassIsolationScope(
        defaultQuality: GlassQuality.standard,
        child: Column(
          children: [
            _buildHeroCard(context, state),
            if (state.status == UpdateStatus.downloading) ...[
              const SizedBox(height: AppSpacing.lg),
              _buildMorpheDownloadProgress(context, state),
            ],
            if (hasUpdate) ...[
              const SizedBox(height: AppSpacing.md),
              _buildReleaseInfoCard(context, state.latestRelease!),
              const SizedBox(height: AppSpacing.md),
              _buildTimelineChangelogCard(
                context,
                state.latestRelease!.changelog,
                release: state.latestRelease!,
                title: "What's new in ${state.latestRelease!.versionName}",
                isLatest: true,
              ),
            ],
            if (state.currentRelease != null && !hasUpdate) ...[
              const SizedBox(height: AppSpacing.md),
              _buildTimelineChangelogCard(
                context,
                state.currentRelease!.changelog,
                release: state.currentRelease!,
                title: 'Current build changelog',
                isLatest: false,
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            _buildActionButtons(context, state, provider),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // HERO CARD (Morphe status header & version comparison)
  // ===========================================================================

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
        color = const Color(0xFF2E7D32);
      }
    } else if (state.status == UpdateStatus.error) {
      statusTitle = 'Update check unavailable';
      statusSubtitle = state.errorMessage ?? 'Could not reach update server';
      icon = Icons.error_outline_rounded;
      color = scheme.error;
    } else if (state.status == UpdateStatus.downloading) {
      statusTitle = 'Downloading update…';
      statusSubtitle = 'Fetching version ${state.latestRelease?.versionName ?? ''}';
      icon = Icons.downloading_rounded;
      color = scheme.primary;
    } else if (state.status == UpdateStatus.downloaded) {
      statusTitle = 'Update Ready to Install';
      statusSubtitle =
          'Version ${state.latestRelease?.versionName ?? ''} is downloaded';
      icon = Icons.download_done_rounded;
      color = const Color(0xFF2E7D32);
    } else {
      statusTitle = 'Opening installer…';
      statusSubtitle = 'Confirm prompt to finish updating';
      icon = Icons.install_mobile_rounded;
      color = scheme.primary;
    }

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(alpha: 0.32),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Icon(icon, color: color, size: 26),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        statusSubtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // Morphe version transition indicator
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: hasUpdate
                  ? Row(
                      children: [
                        _buildVersionPill(
                          context,
                          version: 'v$versionName',
                          badgeText: 'INSTALLED',
                          badgeColor: const Color(0xFF2E7D32),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            size: 16,
                            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                        _buildVersionPill(
                          context,
                          version: 'v${state.latestRelease!.versionName}',
                          badgeText: 'LATEST',
                          badgeColor: scheme.primary,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        _buildVersionPill(
                          context,
                          version: 'v$versionName',
                          badgeText: 'INSTALLED',
                          badgeColor: const Color(0xFF2E7D32),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'You have the latest version installed.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVersionPill(
    BuildContext context, {
    required String version,
    required String badgeText,
    required Color badgeColor,
  }) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          version,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: badgeColor.withValues(alpha: 0.3),
              width: 0.8,
            ),
          ),
          child: Text(
            badgeText,
            style: theme.textTheme.labelSmall?.copyWith(
              color: badgeColor,
              fontWeight: FontWeight.w800,
              fontSize: 9,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // RELEASE DETAILS CARD
  // ===========================================================================

  Widget _buildReleaseInfoCard(
    BuildContext context,
    AppUpdateRelease release,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final publishedDate = _formatReleaseDate(release.publishedAt);

    return SectionCard(
      title: 'Release Details',
      compact: true,
      child: Column(
        children: [
          _buildDetailRow(
            context,
            icon: Icons.tag_rounded,
            title: 'Version Code',
            value: '${release.versionCode}',
          ),
          const Divider(height: 1),
          _buildDetailRow(
            context,
            icon: Icons.calendar_today_rounded,
            title: 'Published',
            value: publishedDate,
          ),
          if (release.apk != null) ...[
            const Divider(height: 1),
            _buildDetailRow(
              context,
              icon: Icons.sd_storage_rounded,
              title: 'Download size',
              value:
                  '${(release.apk!.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB',
            ),
            if (release.apk!.architecture.isNotEmpty) ...[
              const Divider(height: 1),
              _buildDetailRow(
                context,
                icon: Icons.memory_rounded,
                title: 'Architecture',
                value: release.apk!.architecture,
              ),
            ],
          ],
          if (release.channel.isNotEmpty) ...[
            const Divider(height: 1),
            _buildDetailRow(
              context,
              icon: Icons.alt_route_rounded,
              title: 'Channel',
              value: release.channel.toUpperCase(),
              valueColor: scheme.primary,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    Color? valueColor,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor ?? scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // MORPHE TIMELINE CHANGELOG CARD
  // ===========================================================================

  Widget _buildTimelineChangelogCard(
    BuildContext context,
    Changelog changelog, {
    required AppUpdateRelease release,
    required String title,
    required bool isLatest,
  }) {
    if (changelog.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final totalChanges =
        changelog.newFeatures.length + changelog.bugFixes.length + changelog.notes.length;

    return SectionCard(
      title: title,
      compact: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline header with release badge, date, and changes count
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                _MorpheTimelineNodeIcon(
                  isLatest: isLatest,
                  accentColor: scheme.primary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'v${release.versionName}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isLatest
                        ? scheme.primary.withValues(alpha: 0.15)
                        : const Color(0xFF2E7D32).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isLatest ? 'LATEST' : 'INSTALLED',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isLatest ? scheme.primary : const Color(0xFF2E7D32),
                      fontWeight: FontWeight.w800,
                      fontSize: 9,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    '$totalChanges changes',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Categorized change sections on the timeline
          CustomPaint(
            painter: _MorpheTimelineRailPainter(
              railColor: scheme.outlineVariant.withValues(alpha: 0.4),
              accentColor: scheme.primary,
            ),
            child: Padding(
              padding: const EdgeInsets.only(left: 20, top: AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (changelog.newFeatures.isNotEmpty) ...[
                    _buildMorpheCategorySection(
                      context,
                      sectionKey: '${release.id}_features',
                      categoryTitle: 'New Features',
                      items: changelog.newFeatures,
                      icon: Icons.auto_awesome_rounded,
                      accentColor: scheme.primary,
                    ),
                  ],
                  if (changelog.bugFixes.isNotEmpty) ...[
                    _buildMorpheCategorySection(
                      context,
                      sectionKey: '${release.id}_fixes',
                      categoryTitle: 'Bug Fixes',
                      items: changelog.bugFixes,
                      icon: Icons.bug_report_rounded,
                      accentColor: const Color(0xFFE57373),
                    ),
                  ],
                  if (changelog.notes.isNotEmpty) ...[
                    _buildMorpheCategorySection(
                      context,
                      sectionKey: '${release.id}_notes',
                      categoryTitle: 'Improvements & Notes',
                      items: changelog.notes,
                      icon: Icons.tune_rounded,
                      accentColor: const Color(0xFF64B5F6),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMorpheCategorySection(
    BuildContext context, {
    required String sectionKey,
    required String categoryTitle,
    required List<String> items,
    required IconData icon,
    required Color accentColor,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isExpanded = _isSectionExpanded(sectionKey);
    const previewLimit = 5;
    final hasOverflow = items.length > previewLimit;
    final displayedItems =
        hasOverflow && !isExpanded ? items.take(previewLimit).toList() : items;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category header chip in Morphe style
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(icon, size: 14, color: accentColor),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  categoryTitle,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  '(${items.length})',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // Change items with scope badge and inline code chip rendering
          ...displayedItems.asMap().entries.map((entry) {
            final isLast = entry.key == displayedItems.length - 1 && !hasOverflow;
            return _buildMorpheChangelogItem(
              context,
              text: entry.value,
              accentColor: accentColor,
              showDivider: !isLast,
            );
          }),
          if (hasOverflow)
            InkWell(
              onTap: () => _toggleSectionExpanded(sectionKey),
              borderRadius: BorderRadius.circular(AppRadii.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 16,
                      color: accentColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isExpanded
                          ? 'Show fewer changes'
                          : '+${items.length - previewLimit} more changes',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: accentColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMorpheChangelogItem(
    BuildContext context, {
    required String text,
    required Color accentColor,
    bool showDivider = true,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Check for scope prefix like `**scope:**` or `[scope]`
    String? scope;
    String body = text;

    final scopeRegex = RegExp(r'^(?:\*\*(.+?):\*\*|\[(.+?)\])\s*(.*)$');
    final match = scopeRegex.firstMatch(text);
    if (match != null) {
      scope = match.group(1) ?? match.group(2);
      body = match.group(3) ?? '';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Subtle bullet dot
              Container(
                margin: const EdgeInsets.only(top: 7, right: 8),
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (scope != null) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.3),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          scope,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                    _MorpheInlineText(
                      text: body.isNotEmpty ? body : text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showDivider)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Divider(
                height: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // MORPHE DOWNLOAD PROGRESS RING
  // ===========================================================================

  Widget _buildMorpheDownloadProgress(
    BuildContext context,
    AppUpdateState state,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = state.progress.clamp(0.0, 1.0);
    final percent = (progress * 100).toStringAsFixed(0);
    final writtenMb = (state.bytesWritten / 1024 / 1024).toStringAsFixed(1);
    final totalMb = (state.bytesExpected / 1024 / 1024).toStringAsFixed(1);

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.lg,
        ),
        child: Column(
          children: [
            SizedBox(
              width: 190,
              height: 190,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer glowing ring
                  Container(
                    width: 190,
                    height: 190,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.12),
                          blurRadius: 28,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  // Background circular track
                  SizedBox(
                    width: 170,
                    height: 170,
                    child: CircularProgressIndicator(
                      value: 1.0,
                      strokeWidth: 8,
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    ),
                  ),
                  // Foreground animated progress
                  SizedBox(
                    width: 170,
                    height: 170,
                    child: CircularProgressIndicator(
                      value: progress > 0 ? progress : null,
                      strokeWidth: 8,
                      strokeCap: StrokeCap.round,
                      color: scheme.primary,
                    ),
                  ),
                  // Center percentage & size
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$percent%',
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        state.bytesExpected > 0
                            ? '$writtenMb / $totalMb MB'
                            : '$writtenMb MB downloaded',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Downloading update package…',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // ACTION BUTTONS (Morphe glass buttons)
  // ===========================================================================

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
            const GlassButton(
              icon: Icon(Icons.refresh_rounded),
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
        if (state.status == UpdateStatus.downloading)
          GlassButton(
            icon: const Icon(Icons.close_rounded),
            label: 'Cancel Download',
            onTap: () => provider.cancelDownload(),
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
        if (state.status == UpdateStatus.error)
          GlassButton(
            icon: const Icon(Icons.refresh_rounded),
            label: 'Try Again',
            onTap: () => provider.checkForUpdates(),
          ),
      ],
    );
  }

  static String _formatReleaseDate(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inDays == 0) {
        if (diff.inHours == 0) {
          if (diff.inMinutes <= 1) return 'Just now';
          return '${diff.inMinutes} minutes ago';
        }
        return '${diff.inHours} hours ago';
      } else if (diff.inDays == 1) {
        return 'Yesterday';
      } else if (diff.inDays < 7) {
        return '${diff.inDays} days ago';
      } else {
        return isoString.split('T').first;
      }
    } catch (_) {
      return isoString.split('T').first;
    }
  }
}

// =============================================================================
// MORPHE TIMELINE PAINTER & NODE WIDGETS
// =============================================================================

class _MorpheTimelineNodeIcon extends StatelessWidget {
  const _MorpheTimelineNodeIcon({
    required this.isLatest,
    required this.accentColor,
  });

  final bool isLatest;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    if (isLatest) {
      return Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: accentColor,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accentColor, width: 2.5),
      ),
    );
  }
}

class _MorpheTimelineRailPainter extends CustomPainter {
  _MorpheTimelineRailPainter({
    required this.railColor,
    required this.accentColor,
  });

  final Color railColor;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = railColor
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // Draw rail line along x = 8
    canvas.drawLine(
      const Offset(8, 0),
      Offset(8, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _MorpheTimelineRailPainter oldDelegate) =>
      oldDelegate.railColor != railColor || oldDelegate.accentColor != accentColor;
}

// =============================================================================
// MORPHE INLINE TEXT PARSER (Backticks code chips & markdown bold)
// =============================================================================

class _MorpheInlineText extends StatelessWidget {
  const _MorpheInlineText({
    required this.text,
    this.style,
  });

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    // If the text has no backticks or bold formatting, output plain Text
    // so tests like find.text('Feature A') match exactly.
    if (!text.contains('`') && !text.contains('**')) {
      return Text(text, style: style);
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final effectiveStyle = style ?? theme.textTheme.bodyMedium!;

    final spans = <InlineSpan>[];
    // Regex matching either `code` or **bold**
    final regex = RegExp(r'`([^`]+)`|\*\*(.+?)\*\*');
    int lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: effectiveStyle,
        ));
      }

      final code = match.group(1);
      final bold = match.group(2);

      if (code != null) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
                width: 0.8,
              ),
            ),
            child: Text(
              code,
              style: effectiveStyle.copyWith(
                fontFamily: 'monospace',
                fontSize: (effectiveStyle.fontSize ?? 14) * 0.9,
                fontWeight: FontWeight.w600,
                color: scheme.primary,
              ),
            ),
          ),
        ));
      } else if (bold != null) {
        spans.add(TextSpan(
          text: bold,
          style: effectiveStyle.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ));
      }

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: effectiveStyle,
      ));
    }

    return Text.rich(
      TextSpan(children: spans),
    );
  }
}
