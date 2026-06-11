import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';

class HomeBalancePill extends StatelessWidget {
  const HomeBalancePill({
    required this.label,
    super.key,
    this.icon,
    this.showChevron = false,
  });

  final String label;
  final IconData? icon;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: scheme.error.withAlphaFactor(0.72),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: scheme.onError),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: scheme.onError,
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
            ),
          ),
          if (showChevron) ...[
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 15, color: scheme.onError),
          ],
        ],
      ),
    );
  }
}

class HomeFlowPanel extends StatelessWidget {
  const HomeFlowPanel({
    required this.label,
    required this.value,
    required this.tone,
    super.key,
  });

  final String label;
  final String value;
  final MetricTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (tone) {
      MetricTone.positive =>
        Theme.of(context).brightness == Brightness.dark
            ? AppColors.positiveDark
            : AppColors.positiveLight,
      MetricTone.danger => scheme.error,
      MetricTone.warning => scheme.secondary,
      MetricTone.standard => scheme.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class HomeProgressRow extends StatelessWidget {
  const HomeProgressRow({
    required this.label,
    required this.value,
    required this.progress,
    required this.color,
    super.key,
  });

  final String label;
  final String value;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: progress.clamp(0, 1).toDouble(),
            color: color,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

class AddAccountHomeRow extends StatelessWidget {
  const AddAccountHomeRow({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.md),
      onTap: onTap,
      child: Container(
        height: 60,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: scheme.primary.withAlpha(60)),
          color: scheme.primary.withAlpha(24),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, color: scheme.primary),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'Add account',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
