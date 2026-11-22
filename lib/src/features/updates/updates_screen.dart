import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../design/tokens.dart';
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

  @override
  void initState() {
    super.initState();
  }

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
    final releases = _resolveReleases(state);

    return RouteScaffold(
      title: 'Changelog',
      child: GlassIsolationScope(
        defaultQuality: GlassQuality.standard,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildChangelogHeader(context, state),
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

    if (state.latestRelease != null &&
        seen.add(state.latestRelease!.versionName)) {
      list.add(state.latestRelease!);
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
  // CHANGELOG HEADER (Current version & release history banner)
  // ===========================================================================

  Widget _buildChangelogHeader(
    BuildContext context,
    AppUpdateState state,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final versionName = state.currentVersionName.isEmpty
        ? 'Unknown'
        : state.currentVersionName;
    final displayBuild = AppUpdateProvider.formatDisplayBuild(
      state.currentVersionName,
      state.currentVersionCode,
    );

    return AppPanel(
      glass: true,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.16),
                shape: BoxShape.circle,
                border: Border.all(
                  color: scheme.primary.withValues(alpha: 0.32),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.history_edu_rounded,
                  color: scheme.primary,
                  size: 26,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.xs,
                    children: [
                      Text(
                        'Version $versionName',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      _buildVersionPill(
                        context,
                        version: 'v$versionName',
                        badgeText: 'INSTALLED',
                        badgeColor: scheme.positive,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxxs),
                  Text(
                    'Build $displayBuild · Release History',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
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
        Flexible(
          child: Text(
            version,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFamily: AppFonts.mono,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxs,
            vertical: AppSpacing.xxxs,
          ),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppRadii.xs),
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
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
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
                            ? scheme.positive
                            : scheme.onSurfaceVariant),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          'v${release.versionName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
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
                          color: scheme.positive,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxxs,
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
              padding: const EdgeInsets.only(
                left: AppSpacing.lg,
                top: AppSpacing.xs,
              ),
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
                      accentColor: scheme.error,
                    ),
                  ],
                  if (changelog.notes.isNotEmpty) ...[
                    _buildMorpheCategorySection(
                      context,
                      sectionKey: '${release.id}_notes',
                      categoryTitle: 'Improvements & Notes',
                      items: changelog.notes,
                      icon: Icons.tune_rounded,
                      accentColor: scheme.tertiary,
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
                      ? scheme.positive
                      : scheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'v${release.versionName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (isInstalled) ...[
                            const SizedBox(width: AppSpacing.xs),
                            _buildBadgePill(
                              context,
                              label: 'INSTALLED',
                              color: scheme.positive,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxxs),
                      Text(
                        publishedDate,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxxs,
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
              left: AppSpacing.xl,
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
                    accentColor: scheme.error,
                  ),
                ],
                if (changelog.notes.isNotEmpty) ...[
                  _buildMorpheCategorySection(
                    context,
                    sectionKey: '${release.id}_older_notes',
                    categoryTitle: 'Improvements & Notes',
                    items: changelog.notes,
                    icon: Icons.tune_rounded,
                    accentColor: scheme.tertiary,
                  ),
                ],
                if (changelog.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xxs,
                    ),
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs,
        vertical: AppSpacing.xxxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadii.xs),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
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
                  padding: const EdgeInsets.all(AppSpacing.xxs),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppRadii.xs),
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
                    const SizedBox(width: AppSpacing.xxs),
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
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 7, right: AppSpacing.xs),
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
                        margin: const EdgeInsets.only(bottom: AppSpacing.xxxs),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xxs,
                          vertical: AppSpacing.xxxs,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(
                            alpha: 0.8,
                          ),
                          borderRadius: BorderRadius.circular(AppRadii.xs),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.3),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          scope,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
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
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Divider(
                height: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
        ],
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
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxs),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xxs,
                vertical: AppSpacing.xxxs,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(AppRadii.xs),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                  width: 0.8,
                ),
              ),
              child: Text(
                code,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: AppFonts.mono,
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
