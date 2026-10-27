import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/privacy_text.dart';
import '../common/route_scaffold.dart';
import 'capture_diagnostics.dart';

final captureDiagnosticEventsProvider = FutureProvider.autoDispose
    .family<List<CaptureDiagnosticEvent>, String>(
      (ref, owner) => CaptureDiagnostics.recentEvents(ownerId: owner),
    );

class CaptureDiagnosticsScreen extends ConsumerStatefulWidget {
  const CaptureDiagnosticsScreen({super.key});

  @override
  ConsumerState<CaptureDiagnosticsScreen> createState() =>
      _CaptureDiagnosticsScreenState();
}

class _CaptureDiagnosticsScreenState
    extends ConsumerState<CaptureDiagnosticsScreen> {
  void _refresh() {
    ref.invalidate(
      captureDiagnosticEventsProvider(ref.read(ledgerProvider).userId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerProvider);
    final history = ref.watch(captureDiagnosticEventsProvider(state.userId));
    return RouteScaffold(
      title: 'Capture diagnostics',
      actions: [
        HeaderIconButton(
          icon: Icons.refresh_rounded,
          semanticLabel: 'Refresh diagnostics',
          onPressed: _refresh,
        ),
        HeaderIconButton(
          icon: Icons.delete_sweep_outlined,
          semanticLabel: 'Clear diagnostics',
          onPressed: () async {
            await CaptureDiagnostics.clear(ownerId: state.userId);
            if (!mounted) return;
            _refresh();
          },
        ),
        HeaderIconButton(
          icon: Icons.history_rounded,
          semanticLabel: 'Clear legacy unassigned diagnostic history',
          onPressed: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Clear unassigned diagnostic history?'),
                content: const Text(
                  'Older diagnostic history has no verified owner and may '
                  'contain alerts from other wallets on this device. This clears only that '
                  'diagnostic history, not ledger records or queued captures.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Clear unassigned history'),
                  ),
                ],
              ),
            );
            if (confirmed != true ||
                !mounted ||
                ref.read(ledgerProvider).userId != state.userId) {
              return;
            }
            try {
              await CaptureDiagnostics.clearLegacy();
              if (mounted && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Unassigned diagnostic history cleared.'),
                  ),
                );
              }
            } catch (error, stack) {
              debugPrint(
                'Could not clear unassigned history: ${error.runtimeType}',
              );
              debugPrintStack(stackTrace: stack);
              if (mounted && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Unassigned history could not be cleared.'),
                  ),
                );
              }
            }
          },
        ),
      ],
      child: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => const EmptyState(
          icon: Icons.error_outline,
          title: 'Could not load diagnostics',
          body:
              'The original history was retained. Refresh or clear this wallet\'s history to retry.',
        ),
        data: (events) {
          if (events.isEmpty) {
            return const EmptyState(
              icon: Icons.bug_report_outlined,
              title: 'No capture diagnostics yet',
              body:
                  'Decisions for this wallet appear here. Older unassigned history is not shown automatically.',
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                title: 'Recent decisions',
                subtitle:
                    'Local-only debug trail for why messages were queued, ignored, duplicated, or notified.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final event in events) ...[
                      _DiagnosticEventTile(event: event, state: state),
                      if (event != events.last)
                        const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DiagnosticEventTile extends StatelessWidget {
  const _DiagnosticEventTile({required this.event, required this.state});

  final CaptureDiagnosticEvent event;
  final LedgerState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final category = categoryById(state, event.categoryId);
    final rawText = event.rawText?.trim();
    final showRaw = rawText != null && rawText.isNotEmpty;
    final decisionColor = switch (event.decision) {
      'queued' => positiveTone(context),
      'duplicate' => scheme.tertiary,
      'error' => scheme.error,
      _ => scheme.onSurfaceVariant,
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: scheme.outlineVariant.withAlpha(150)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBubble(
                icon: _sourceIcon(event.source),
                color: decisionColor,
                compact: true,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${event.source.toUpperCase()} · ${event.decision}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: scheme.onSurface,
                      ),
                    ),
                    Text(
                      '${event.stage} · ${DateFormat.MMMd().add_jms().format(event.timestamp.toLocal())}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _MetaChip(label: event.reason ?? 'no reason'),
              if (event.notificationShown)
                const _MetaChip(label: 'notification shown'),
              if (event.nativeAccepted)
                const _MetaChip(label: 'native accepted'),
              if (event.matchedTriggerWord != null)
                _MetaChip(label: 'trigger: ${event.matchedTriggerWord}'),
              if (event.matchedIgnoreWord != null)
                _MetaChip(label: 'ignore: ${event.matchedIgnoreWord}'),
              if (event.amount != null)
                _MetaChip(
                  label: formatMoney(event.amount!, state.preferences.locale),
                ),
              if (event.merchant != null)
                _MetaChip(label: 'seller: ${event.merchant}'),
              if (category != null)
                _MetaChip(
                  label:
                      'category: ${categoryPath(state, category)}${event.categoryReason == null ? '' : ' · ${event.categoryReason}'}',
                ),
            ],
          ),
          if (event.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              event.errorMessage!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (showRaw) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withAlpha(130),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: PrivacyText(
                rawText,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                  height: 1.35,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _sourceIcon(String source) {
    return switch (source) {
      'sms' => Icons.sms_rounded,
      'notification' => Icons.notifications_active_outlined,
      _ => Icons.auto_awesome_outlined,
    };
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withAlpha(180),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: scheme.outlineVariant.withAlpha(140)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
