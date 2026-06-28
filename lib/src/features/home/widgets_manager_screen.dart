import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';
import '../common/full_screen_picker.dart';
import '../common/route_scaffold.dart';
import 'home_widget_models.dart';
import 'home_widgets.dart';

class WidgetsManagerScreen extends ConsumerWidget {
  const WidgetsManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ledgerProvider);
    final theme = Theme.of(context);
    final visibleOrder = resolveHomeWidgetOrder(
      state.preferences.homeWidgetOrder,
      hidden: state.preferences.homeWidgetHidden,
    ).map((item) => item.storageKey).toList();

    return RouteScaffold(
      title: 'Widgets Gallery',
      actions: [
        IconButton(
          tooltip: 'Home',
          icon: const Icon(Icons.home_outlined),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${visibleOrder.length} active on Home',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${HomeDashboardWidgetId.values.length - visibleOrder.length} available to add',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () {
                    ref.read(ledgerProvider.notifier).resetHomeWidgetOrder();
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(
                          content: Text('Home widgets reset'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                  },
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Reset order'),
                ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          Text(
            'Live Widget Previews',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Widgets are rendered live with your current data. Toggle them on or off for your Home screen.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          const Gap(AppSpacing.md),
          for (final widgetId in HomeDashboardWidgetId.values) ...[
            _LiveWidgetPreview(
              widgetId: widgetId,
              isVisible: visibleOrder.contains(widgetId.storageKey),
              preferences: state.preferences,
            ),
            if (widgetId != HomeDashboardWidgetId.values.last)
              const SizedBox(height: AppSpacing.lg),
          ],
        ],
      ),
    );
  }
}

class _LiveWidgetPreview extends ConsumerWidget {
  const _LiveWidgetPreview({
    required this.widgetId,
    required this.isVisible,
    required this.preferences,
  });

  final HomeDashboardWidgetId widgetId;
  final bool isVisible;
  final LedgerPreferences preferences;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(ledgerProvider);
    final datePreset = preferences.homeWidgetFilters[widgetId.storageKey] ??
        defaultDatePresetForHomeWidget(widgetId.storageKey);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The overlay actions
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: isVisible ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
          ),
          child: Row(
            children: [
              Icon(
                isVisible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                size: 20,
                color: isVisible ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  isVisible ? 'Added to Home' : 'Hidden',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isVisible ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.calendar_month, size: 16),
                label: Text(homeWidgetDateLabel(datePreset)),
                onPressed: () => _chooseDatePreset(context, ref, datePreset),
              ),
              const SizedBox(width: AppSpacing.sm),
              Switch.adaptive(
                value: isVisible,
                onChanged: (value) {
                  if (value) {
                    _restoreWidget(context, ref);
                  } else {
                    _hideWidget(ref);
                  }
                },
              ),
            ],
          ),
        ),
        // The actual widget preview
        Opacity(
          opacity: isVisible ? 1.0 : 0.4,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: isVisible ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHigh,
                width: 2,
              ),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadii.lg)),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(AppRadii.lg - 2)),
              child: IgnorePointer(
                child: buildHomeDashboardWidget(
                  context: context,
                  id: widgetId,
                  state: state,
                  onTabSelected: (_) {}, // no-op in preview
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _chooseDatePreset(BuildContext context, WidgetRef ref, String datePreset) async {
    final next = await showFullScreenPicker<String>(
      context: context,
      title: 'Widget period',
      searchable: false,
      selectedValue: datePreset,
      options: [
        for (final preset in allowedDatePresetsForHomeWidget(widgetId.storageKey))
          PickerOption(
            value: preset,
            title: homeWidgetDateLabel(preset),
            subtitle: null,
          ),
      ],
    );
    if (next != null && next != datePreset) {
      final filters = Map<String, String>.from(preferences.homeWidgetFilters);
      filters[widgetId.storageKey] = next;
      ref.read(ledgerProvider.notifier).updatePreferences(
            preferences.copyWith(homeWidgetFilters: filters),
          );
    }
  }

  void _restoreWidget(BuildContext context, WidgetRef ref) {
    final hidden = preferences.homeWidgetHidden.toList();
    hidden.remove(widgetId.storageKey);

    final order = restoreHomeWidgetStorageKey(
      preferences.homeWidgetOrder,
      widgetId.storageKey,
    );
    ref.read(ledgerProvider.notifier).updatePreferences(
          preferences.copyWith(
            homeWidgetHidden: hidden,
            homeWidgetOrder: order,
          ),
        );
  }

  void _hideWidget(WidgetRef ref) {
    final hidden = preferences.homeWidgetHidden.toList();
    if (!hidden.contains(widgetId.storageKey)) {
      hidden.add(widgetId.storageKey);
    }
    ref.read(ledgerProvider.notifier).updatePreferences(
          preferences.copyWith(homeWidgetHidden: hidden),
        );
  }
}
