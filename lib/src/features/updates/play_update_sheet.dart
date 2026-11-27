import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../routing/app_router.dart';
import '../../widgets/app_kit.dart';
import 'play_store_update_service.dart';

/// Presents the custom update sheet whenever [PlayStoreUpdateService] asks for
/// it. Lives inside the app lock gate, so it never shows over a locked wallet;
/// a prompt raised while locked waits until the gate is unlocked.
class PlayUpdatePromptHost extends ConsumerStatefulWidget {
  const PlayUpdatePromptHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PlayUpdatePromptHost> createState() =>
      _PlayUpdatePromptHostState();
}

class _PlayUpdatePromptHostState extends ConsumerState<PlayUpdatePromptHost> {
  bool _sheetOpen = false;
  int _attempts = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  void _maybeShow() {
    if (!mounted || _sheetOpen) return;
    if (!ref.read(playStoreUpdateProvider).promptPending) return;
    final navigatorContext = ref
        .read(appRouterProvider)
        .routerDelegate
        .navigatorKey
        .currentContext;
    if (navigatorContext == null || !navigatorContext.mounted) {
      // The router may still be building its first page after unlock.
      if (_attempts++ < 20) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
      }
      return;
    }
    _attempts = 0;
    _sheetOpen = true;
    ref.read(playStoreUpdateProvider.notifier).consumePrompt();
    showPlayUpdateSheet(navigatorContext).whenComplete(() {
      _sheetOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PlayStoreUpdateState>(playStoreUpdateProvider, (prev, next) {
      if (next.promptPending && !(prev?.promptPending ?? false)) {
        _maybeShow();
      }
      final becameReady =
          next.status == PlayStoreUpdateStatus.readyToInstall &&
          prev?.status != PlayStoreUpdateStatus.readyToInstall;
      if (becameReady && !_sheetOpen && !next.promptPending) {
        rootScaffoldMessengerKey.currentState?.showAppSnackBar(
          'Update downloaded. 1Wallet restarts to install it.',
          duration: const Duration(seconds: 4),
        );
      }
    });
    return widget.child;
  }
}

Future<void> showPlayUpdateSheet(BuildContext context) {
  return showAppSheet<void>(
    context: context,
    maxWidth: 520,
    builder: (_) => const PlayUpdateSheet(),
  );
}

enum _SheetPhase { available, downloading, ready, installing, failed, upToDate }

_SheetPhase _phaseFor(PlayStoreUpdateStatus status) => switch (status) {
  PlayStoreUpdateStatus.downloading => _SheetPhase.downloading,
  PlayStoreUpdateStatus.readyToInstall => _SheetPhase.ready,
  PlayStoreUpdateStatus.installing => _SheetPhase.installing,
  PlayStoreUpdateStatus.failed => _SheetPhase.failed,
  PlayStoreUpdateStatus.upToDate ||
  PlayStoreUpdateStatus.notSupported => _SheetPhase.upToDate,
  _ => _SheetPhase.available,
};

String formatUpdateBytes(int bytes) {
  if (bytes <= 0) return '0 MB';
  final mb = bytes / (1024 * 1024);
  if (mb < 0.1) return '${(bytes / 1024).ceil()} KB';
  return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
}

/// Content-sized "half sheet" that owns everything except Google Play's own
/// one-tap confirmation dialog (which Play always shows itself).
class PlayUpdateSheet extends ConsumerWidget {
  const PlayUpdateSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final update = ref.watch(playStoreUpdateProvider);
    final notifier = ref.read(playStoreUpdateProvider.notifier);
    final current = ref.watch(packageInfoProvider).valueOrNull;
    final phase = _phaseFor(update.status);
    final positive = theme.brightness == Brightness.dark
        ? AppColors.positiveDark
        : AppColors.positiveLight;

    final availableCode = update.updateInfo?.availableVersionCode;
    final versionLine = [
      if (availableCode != null) 'Build $availableCode',
      if (current != null) 'you have v${current.version}',
    ].join(' · ');

    final (IconData icon, String title, String subtitle) = switch (phase) {
      _SheetPhase.available => (
        Icons.system_update_rounded,
        'A new 1Wallet is ready',
        versionLine.isEmpty ? 'Available on Google Play' : versionLine,
      ),
      _SheetPhase.downloading => (
        Icons.downloading_rounded,
        'Downloading update',
        'Keep using 1Wallet while it downloads',
      ),
      _SheetPhase.ready => (
        Icons.check_circle_outline_rounded,
        'Update downloaded',
        'Restarting automatically to install',
      ),
      _SheetPhase.installing => (
        Icons.restart_alt_rounded,
        'Installing…',
        '1Wallet will reopen on the new version',
      ),
      _SheetPhase.failed => (
        Icons.cloud_off_rounded,
        'Update paused',
        'Check your connection and try again',
      ),
      _SheetPhase.upToDate => (
        Icons.verified_outlined,
        "You're up to date",
        current == null
            ? 'Latest version'
            : 'v${current.version} is the latest',
      ),
    };
    final accent = switch (phase) {
      _SheetPhase.ready || _SheetPhase.upToDate => positive,
      _SheetPhase.failed => scheme.error,
      _ => scheme.primary,
    };

    Widget body;
    switch (phase) {
      case _SheetPhase.available:
        body = const Column(
          key: ValueKey('play-update-highlights'),
          children: [
            _Highlight(
              icon: Icons.bolt_rounded,
              text: 'Downloads while you keep using the app',
            ),
            _Highlight(
              icon: Icons.lock_outline_rounded,
              text: 'Your wallet data is never touched',
            ),
            _Highlight(
              icon: Icons.restart_alt_rounded,
              text: "One quick restart when it's ready",
            ),
          ],
        );
      case _SheetPhase.downloading:
      case _SheetPhase.ready:
      case _SheetPhase.installing:
        final progress = update.progress;
        final fraction = phase == _SheetPhase.downloading
            ? progress?.fraction
            : (phase == _SheetPhase.ready ? 1.0 : null);
        final total = progress?.totalBytes ?? 0;
        final done = progress?.bytesDownloaded ?? 0;
        final leftLabel = switch (phase) {
          _SheetPhase.ready => 'Downloaded',
          _SheetPhase.installing => 'Installing',
          _ => fraction == null ? 'Starting…' : '${(fraction * 100).floor()}%',
        };
        final rightLabel = total > 0
            ? phase == _SheetPhase.downloading
                  ? '${formatUpdateBytes(done)} of ${formatUpdateBytes(total)}'
                  : formatUpdateBytes(total)
            : '';
        body = Column(
          key: const ValueKey('play-update-progress'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: fraction ?? 0),
                duration: const Duration(milliseconds: 280),
                builder: (context, value, _) => LinearProgressIndicator(
                  minHeight: 10,
                  value: fraction == null ? null : value,
                  color: accent,
                  backgroundColor: accent.withValues(alpha: 0.14),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Text(
                  leftLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const Spacer(),
                Text(
                  rightLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (phase == _SheetPhase.downloading) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                "You can close this. 1Wallet restarts on its own when it's ready.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        );
      case _SheetPhase.failed:
        body = Text(
          'Google Play could not finish the update. Nothing on your device '
          'changed.',
          key: const ValueKey('play-update-error'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        );
      case _SheetPhase.upToDate:
        body = const SizedBox.shrink();
    }

    void close() => Navigator.of(context).maybePop();

    final (
      String? secondary,
      String? primary,
      VoidCallback? onPrimary,
    ) = switch (phase) {
      _SheetPhase.available => (null, 'Update now', notifier.startUpdate),
      _SheetPhase.downloading => ('Hide', null, null),
      _SheetPhase.ready => (null, null, null),
      _SheetPhase.installing => (null, null, null),
      _SheetPhase.failed => ('Close', 'Try again', notifier.startUpdate),
      _SheetPhase.upToDate => ('Done', null, null),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadii.xl),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [
            Color.alphaBlend(
              accent.withValues(alpha: 0.12),
              theme.scaffoldBackgroundColor,
            ),
            theme.scaffoldBackgroundColor,
          ],
        ),
        border: Border(top: BorderSide(color: accent.withValues(alpha: 0.28))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            key: const ValueKey('play-update-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppSheetHandle(),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  _HeroBadge(icon: icon, accent: accent),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PlayPill(accent: accent),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: body,
              ),
              if (secondary != null || primary != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    if (secondary != null)
                      Expanded(
                        child: OutlinedButton(
                          key: const ValueKey('play-update-secondary'),
                          onPressed: close,
                          child: Text(secondary, maxLines: 1),
                        ),
                      ),
                    if (secondary != null && primary != null)
                      const SizedBox(width: AppSpacing.sm),
                    if (primary != null)
                      Expanded(
                        child: FilledButton(
                          key: const ValueKey('play-update-primary'),
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: scheme.surface,
                          ),
                          onPressed: onPrimary,
                          child: Text(primary, maxLines: 1),
                        ),
                      ),
                  ],
                ),
              ],
              if (phase == _SheetPhase.available) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Google Play asks you to confirm once.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.icon, required this.accent});

  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.95),
            accent.withValues(alpha: 0.55),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(icon, size: 32, color: Theme.of(context).colorScheme.surface),
    );
  }
}

class _PlayPill extends StatelessWidget {
  const _PlayPill({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxxs,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        'GOOGLE PLAY UPDATE',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: accent,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _Highlight extends StatelessWidget {
  const _Highlight({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
