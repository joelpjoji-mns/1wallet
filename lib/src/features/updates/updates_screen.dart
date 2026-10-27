import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../design/tokens.dart';
import '../../utils/app_reload.dart';
import '../../widgets/app_kit.dart';
import '../common/route_scaffold.dart';
import 'app_update_provider.dart';

/// Update screen matching the Morphe Manager update experience.
///
/// Features:
/// - Prominent Morphe hero status header with launcher avatar, version transition pill,
///   and full-width update action button right on top
/// - Scrollable changelogs with release details and older releases history
/// - Dedicated download progress screen with 220px animated circular ring
/// - Automatic installation prompt upon download completion
/// - Top right labeled action button ("Check for update" / "Install" / "Update")
/// - Interactive, expandable Older Releases with full historical changelogs
/// - Categorized sections (New Features, Bug Fixes, Improvements & Notes)
/// - Scope tag detection (`[scope]`) and inline code chips (`` `code` ``)
/// - Pull-to-refresh anywhere across the screen
class UpdatesScreen extends ConsumerStatefulWidget {
  const UpdatesScreen({super.key});

  @override
  ConsumerState<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends ConsumerState<UpdatesScreen> {
  final Set<String> _expandedReleases = <String>{};
  final Set<String> _expandedSections = <String>{};

  bool _isReleaseExpanded(String releaseId) =>
      _expandedReleases.contains(releaseId);

  void _toggleReleaseExpanded(String releaseId) {
    setState(() {
      if (_expandedReleases.contains(releaseId)) {
        _expandedReleases.remove(releaseId);
      } else {
        _expandedReleases.add(releaseId);
      }
    });
  }

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

    final releases = _resolveReleases(state);

    // Dedicated download screen while downloading
    if (state.status == UpdateStatus.downloading) {
      return RouteScaffold(
        title: 'Downloading Update',
        actions: [
          Tooltip(
            message: 'Cancel download',
            child: GlassHeaderButton(
              icon: Icons.close_rounded,
              onPressed: () => provider.cancelDownload(),
              semanticLabel: 'Cancel download',
            ),
          ),
        ],
        child: _buildDedicatedDownloadView(context, state, provider),
      );
    }

    return RouteScaffold(
      title: 'Updates',
      actions: [
        Tooltip(
          message: 'Check for updates',
          child: HeaderIconButton(
            icon: Icons.refresh_rounded,
            loading: state.status == UpdateStatus.checking,
            onPressed: state.status == UpdateStatus.checking
                ? null
                : () => provider.checkForUpdates(force: true),
            semanticLabel: 'Check for updates',
          ),
        ),
      ],
      child: GlassIsolationScope(
        defaultQuality: GlassQuality.standard,
        child: RefreshIndicator(
          onRefresh: () => provider.checkForUpdates(force: true),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Section: Hero Card with Version Transition & Update Action Button
              _buildHeroCard(context, state, provider),
              if (state.notificationWarning != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    state.notificationWarning!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
              if (hasUpdate) ...[
                const SizedBox(height: AppSpacing.md),
                _buildReleaseInfoCard(context, state.latestRelease!),
              ],
              const SizedBox(height: AppSpacing.md),
              _buildFullMorpheTimeline(context, state, releases),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  List<AppUpdateRelease> _resolveReleases(AppUpdateState state) {
    final list = <AppUpdateRelease>[];
    final seen = <String>{};

    if (state.latestRelease != null) {
      list.add(state.latestRelease!);
      seen.add(state.latestRelease!.versionName);
    }

    if (state.currentRelease != null &&
        seen.add(state.currentRelease!.versionName)) {
      list.add(state.currentRelease!);
    }

    final pool = <AppUpdateRelease>[
      ...state.allReleases,
      ...kBuiltInReleaseHistory,
    ];

    final sortedPool = List<AppUpdateRelease>.from(pool)
      ..sort((a, b) {
        final dateA = DateTime.tryParse(a.publishedAt) ?? DateTime(1970);
        final dateB = DateTime.tryParse(b.publishedAt) ?? DateTime(1970);
        final cmp = dateB.compareTo(dateA);
        if (cmp != 0) return cmp;
        return b.versionCode.compareTo(a.versionCode);
      });

    for (final rel in sortedPool) {
      if (seen.add(rel.versionName)) {
        list.add(rel);
      }
    }

    return list;
  }

  // ===========================================================================
  // HERO CARD (Morphe status header, version comparison, and update button on top)
  // ===========================================================================

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
    final displayBuild = AppUpdateProvider.formatDisplayBuild(
      state.currentVersionName,
      state.currentVersionCode,
    );

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
        statusSubtitle = 'Version $versionName (Build $displayBuild)';
        icon = Icons.check_circle_rounded;
        color = const Color(0xFF2E7D32);
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(alpha: 0.32),
                      width: 1.5,
                    ),
                  ),
                  child: Center(child: Icon(icon, color: color, size: 26)),
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
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: 0.7,
                            ),
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
            if (hasUpdate || state.status == UpdateStatus.downloaded) ...[
              const SizedBox(height: AppSpacing.md),
              // Full-width update button right on top
              _buildTopActionButton(context, state, provider),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopActionButton(
    BuildContext context,
    AppUpdateState state,
    AppUpdateProvider provider,
  ) {
    if (kIsWeb) {
      if (state.latestRelease != null) {
        return _buildMorpheTextButton(
          context,
          label: 'Reload App',
          onTap: reloadWebPage,
        );
      }
      return const SizedBox.shrink();
    }

    if (state.status == UpdateStatus.downloaded) {
      return _buildMorpheTextButton(
        context,
        label: 'Install Update',
        onTap: () => provider.installUpdate(),
        prominent: true,
      );
    }

    if (state.latestRelease != null && state.status == UpdateStatus.idle) {
      final sizeStr = state.latestRelease!.apk?.sizeBytes != null
          ? ' (${(state.latestRelease!.apk!.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB)'
          : '';
      return _buildMorpheTextButton(
        context,
        label: 'Install Update$sizeStr',
        onTap: () => provider.downloadUpdate(),
        prominent: true,
      );
    }

    if (state.status == UpdateStatus.error) {
      return _buildMorpheTextButton(
        context,
        label: 'Try Again',
        onTap: () => provider.checkForUpdates(force: true),
        prominent: false,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildMorpheTextButton(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
    bool prominent = true,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final bg = prominent
        ? scheme.primary
        : scheme.surfaceContainerHighest.withValues(alpha: 0.65);
    final fg = prominent ? scheme.onPrimary : scheme.primary;

    return SizedBox(
      width: double.infinity,
      child: GlassButton.custom(
        label: label,
        onTap: onTap,
        height: 50,
        shape: const LiquidRoundedRectangle(borderRadius: AppRadii.pill),
        useOwnLayer: true,
        quality: GlassQuality.standard,
        style: prominent ? GlassButtonStyle.prominent : GlassButtonStyle.filled,
        child: Container(
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
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

  Widget _buildReleaseInfoCard(BuildContext context, AppUpdateRelease release) {
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
            title: 'Build Number',
            value: AppUpdateProvider.formatDisplayBuild(
              release.versionName,
              release.versionCode,
            ),
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
          Expanded(child: Text(title, style: theme.textTheme.bodyMedium)),
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
  // MORPHE CONTINUOUS TIMELINE CHANGELOG (Primary + Older releases)
  // ===========================================================================

  Widget _buildFullMorpheTimeline(
    BuildContext context,
    AppUpdateState state,
    List<AppUpdateRelease> releases,
  ) {
    if (releases.isEmpty) {
      return const SizedBox.shrink();
    }

    final hasUpdate = state.latestRelease != null;
    final primaryRelease = releases.first;
    final olderReleases = releases.skip(1).toList();

    final primaryTitle = hasUpdate
        ? "What's new in ${primaryRelease.versionName}"
        : 'Changelog: v${primaryRelease.versionName}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildReleaseTimelineCard(
          context,
          release: primaryRelease,
          title: primaryTitle,
          isLatest: hasUpdate,
          isInstalled: !hasUpdate,
          isExpandedByDefault: true,
        ),
        if (olderReleases.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _buildOlderReleasesSection(context, state, olderReleases),
        ],
      ],
    );
  }

  Widget _buildReleaseTimelineCard(
    BuildContext context, {
    required AppUpdateRelease release,
    required String title,
    required bool isLatest,
    required bool isInstalled,
    bool isExpandedByDefault = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final changelog = release.changelog;
    final totalChanges =
        changelog.newFeatures.length +
        changelog.bugFixes.length +
        changelog.notes.length;

    return SectionCard(
      title: title,
      compact: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                _MorpheTimelineNodeIcon(
                  isLatest: isLatest,
                  isInstalled: isInstalled,
                  accentColor: isLatest
                      ? scheme.primary
                      : (isInstalled
                            ? const Color(0xFF2E7D32)
                            : scheme.onSurfaceVariant),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'v${release.versionName}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                if (isLatest)
                  _buildBadgePill(
                    context,
                    label: 'LATEST',
                    color: scheme.primary,
                  )
                else if (isInstalled)
                  _buildBadgePill(
                    context,
                    label: 'INSTALLED',
                    color: const Color(0xFF2E7D32),
                  ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.6,
                    ),
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
                  if (changelog.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: Text(
                        'General performance improvements and maintenance.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
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

  // ===========================================================================
  // OLDER RELEASES SECTION (Expandable version history along the timeline)
  // ===========================================================================

  Widget _buildOlderReleasesSection(
    BuildContext context,
    AppUpdateState state,
    List<AppUpdateRelease> olderReleases,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final currentVersion = state.currentVersionName;

    return SectionCard(
      title: 'Older Releases',
      subtitle:
          '${olderReleases.length} previous versions available to explore',
      compact: true,
      child: Column(
        children: [
          for (int i = 0; i < olderReleases.length; i++) ...[
            _buildOlderReleaseTile(
              context,
              release: olderReleases[i],
              isInstalled: olderReleases[i].versionName == currentVersion,
              isLast: i == olderReleases.length - 1,
            ),
            if (i < olderReleases.length - 1)
              Divider(
                height: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.25),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildOlderReleaseTile(
    BuildContext context, {
    required AppUpdateRelease release,
    required bool isInstalled,
    required bool isLast,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isExpanded = _isReleaseExpanded(release.id);
    final changelog = release.changelog;
    final totalChanges =
        changelog.newFeatures.length +
        changelog.bugFixes.length +
        changelog.notes.length;
    final publishedDate = _formatReleaseDate(release.publishedAt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => _toggleReleaseExpanded(release.id),
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                _MorpheTimelineNodeIcon(
                  isLatest: false,
                  isInstalled: isInstalled,
                  accentColor: isInstalled
                      ? const Color(0xFF2E7D32)
                      : scheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                const SizedBox(width: AppSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'v${release.versionName}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (isInstalled) ...[
                          const SizedBox(width: AppSpacing.xs),
                          _buildBadgePill(
                            context,
                            label: 'INSTALLED',
                            color: const Color(0xFF2E7D32),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      publishedDate,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    '$totalChanges changes',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: scheme.onSurfaceVariant,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(
              left: 28,
              right: AppSpacing.xs,
              bottom: AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (changelog.newFeatures.isNotEmpty) ...[
                  _buildMorpheCategorySection(
                    context,
                    sectionKey: '${release.id}_older_features',
                    categoryTitle: 'New Features',
                    items: changelog.newFeatures,
                    icon: Icons.auto_awesome_rounded,
                    accentColor: scheme.primary,
                  ),
                ],
                if (changelog.bugFixes.isNotEmpty) ...[
                  _buildMorpheCategorySection(
                    context,
                    sectionKey: '${release.id}_older_fixes',
                    categoryTitle: 'Bug Fixes',
                    items: changelog.bugFixes,
                    icon: Icons.bug_report_rounded,
                    accentColor: const Color(0xFFE57373),
                  ),
                ],
                if (changelog.notes.isNotEmpty) ...[
                  _buildMorpheCategorySection(
                    context,
                    sectionKey: '${release.id}_older_notes',
                    categoryTitle: 'Improvements & Notes',
                    items: changelog.notes,
                    icon: Icons.tune_rounded,
                    accentColor: const Color(0xFF64B5F6),
                  ),
                ],
                if (changelog.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'Bug fixes and stability improvements.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBadgePill(
    BuildContext context, {
    required String label,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 9,
          letterSpacing: 0.4,
        ),
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
    final displayedItems = hasOverflow && !isExpanded
        ? items.take(previewLimit).toList()
        : items;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          ...displayedItems.asMap().entries.map((entry) {
            final isLast =
                entry.key == displayedItems.length - 1 && !hasOverflow;
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
                          color: scheme.surfaceContainerHighest.withValues(
                            alpha: 0.8,
                          ),
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
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
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
  // DEDICATED MORPHE DOWNLOAD VIEW (Progress Ring Screen)
  // ===========================================================================

  Widget _buildDedicatedDownloadView(
    BuildContext context,
    AppUpdateState state,
    AppUpdateProvider provider,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = state.progress.clamp(0.0, 1.0);
    final percent = (progress * 100).toStringAsFixed(0);
    final writtenMb = (state.bytesWritten / 1024 / 1024).toStringAsFixed(1);
    final totalMb = (state.bytesExpected / 1024 / 1024).toStringAsFixed(1);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.xxl,
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        width: 220,
                        height: 220,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 220,
                              height: 220,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: scheme.primary.withValues(
                                      alpha: 0.16,
                                    ),
                                    blurRadius: 36,
                                    spreadRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 195,
                              height: 195,
                              child: CircularProgressIndicator(
                                value: 1.0,
                                strokeWidth: 10,
                                color: scheme.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            SizedBox(
                              width: 195,
                              height: 195,
                              child: CircularProgressIndicator(
                                value: progress > 0 ? progress : null,
                                strokeWidth: 10,
                                strokeCap: StrokeCap.round,
                                color: scheme.primary,
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$percent%',
                                  style: theme.textTheme.displayMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -1.5,
                                        color: scheme.onSurface,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  state.bytesExpected > 0
                                      ? '$writtenMb / $totalMb MB'
                                      : '$writtenMb MB downloaded',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      Text(
                        'Downloading Update Package',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'v${state.latestRelease?.versionName ?? ''} · Please keep the app open',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: GlassButton.custom(
                  label: 'Cancel Download',
                  onTap: () => provider.cancelDownload(),
                  height: 48,
                  shape: const LiquidRoundedRectangle(
                    borderRadius: AppRadii.pill,
                  ),
                  useOwnLayer: true,
                  quality: GlassQuality.standard,
                  style: GlassButtonStyle.filled,
                  child: Container(
                    width: double.infinity,
                    height: 48,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.65,
                      ),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: scheme.error,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          'Cancel Download',
                          style: TextStyle(
                            color: scheme.error,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
    this.isInstalled = false,
  });

  final bool isLatest;
  final bool isInstalled;
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
    if (isInstalled) {
      return Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: accentColor, width: 2.5),
        ),
      );
    }
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle),
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
    canvas.drawLine(const Offset(8, 0), Offset(8, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _MorpheTimelineRailPainter oldDelegate) =>
      oldDelegate.railColor != railColor ||
      oldDelegate.accentColor != accentColor;
}

// =============================================================================
// MORPHE INLINE TEXT PARSER (Backticks code chips & markdown bold)
// =============================================================================

class _MorpheInlineText extends StatelessWidget {
  const _MorpheInlineText({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (!text.contains('`') && !text.contains('**')) {
      return Text(text, style: style);
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final effectiveStyle = style ?? theme.textTheme.bodyMedium!;

    final spans = <InlineSpan>[];
    final regex = RegExp(r'`([^`]+)`|\*\*(.+?)\*\*');
    int lastEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastEnd, match.start),
            style: effectiveStyle,
          ),
        );
      }

      final code = match.group(1);
      final bold = match.group(2);

      if (code != null) {
        spans.add(
          WidgetSpan(
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
          ),
        );
      } else if (bold != null) {
        spans.add(
          TextSpan(
            text: bold,
            style: effectiveStyle.copyWith(fontWeight: FontWeight.w700),
          ),
        );
      }

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd), style: effectiveStyle));
    }

    return Text.rich(TextSpan(children: spans));
  }
}
