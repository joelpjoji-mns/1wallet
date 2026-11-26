import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_controller.dart';
import '../../capture/message_parser.dart';
import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';
import 'discovery_coach_mark.dart';
import 'discovery_controller.dart';
import 'discovery_feature_guides.dart';

class DiscoveryGuideTargets extends InheritedWidget {
  const DiscoveryGuideTargets({
    required this.targets,
    required super.child,
    super.key,
  });
  final Map<String, GlobalKey> targets;
  GlobalKey keyFor(String id) => targets.putIfAbsent(id, () => GlobalKey());

  static DiscoveryGuideTargets? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DiscoveryGuideTargets>();

  @override
  bool updateShouldNotify(DiscoveryGuideTargets oldWidget) =>
      !identical(targets, oldWidget.targets);
}

typedef _GuideTargets = DiscoveryGuideTargets;

class DiscoveryGuideAnchor extends StatelessWidget {
  const DiscoveryGuideAnchor({
    required this.id,
    required this.child,
    super.key,
  });
  final String id;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final targets = _GuideTargets.of(context);
    return targets == null
        ? child
        : KeyedSubtree(key: targets.keyFor(id), child: child);
  }
}

class FeatureDiscoverySurface extends StatefulWidget {
  const FeatureDiscoverySurface({
    required this.feature,
    required this.child,
    super.key,
  });
  final String feature;
  final Widget child;

  @override
  State<FeatureDiscoverySurface> createState() =>
      _FeatureDiscoverySurfaceState();
}

class _FeatureDiscoverySurfaceState extends State<FeatureDiscoverySurface> {
  final _targets = <String, GlobalKey>{};

  @override
  Widget build(BuildContext context) => _GuideTargets(
    targets: _targets,
    child: Stack(
      children: [
        widget.child,
        Positioned.fill(child: _FeatureCoach(feature: widget.feature)),
      ],
    ),
  );
}

String? discoveryFeatureRoute(String route, LedgerState ledger) {
  if (!route.startsWith('@')) return route;
  final accounts = ledger.accounts.where(
    (account) =>
        !account.isDeleted &&
        !account.isArchived &&
        const ['bank', 'card', 'credit_card'].contains(account.type),
  );
  if (accounts.isEmpty) return null;
  final id = Uri.encodeComponent(accounts.first.id);
  return route == '@secure' ? '/account/$id/secure' : '/account/$id';
}

class _FeatureCoach extends ConsumerWidget {
  const _FeatureCoach({required this.feature});
  final String feature;

  Future<void> _run(
    BuildContext context,
    Future<void> Function() operation,
  ) async {
    try {
      await operation();
    } catch (error, stack) {
      debugPrint('Feature guide failed: $error');
      debugPrintStack(stackTrace: stack);
      if (context.mounted) {
        showAppSnackBar(
          context,
          'Could not update this guide. Please try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(
      authControllerProvider.select((auth) => auth.ownerId),
    );
    if (owner == null || !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return const SizedBox.shrink();
    }
    final progress = ref.watch(discoveryControllerProvider(owner));
    final feature =
        this.feature == 'review-inbox' &&
            progress.requestedHint == 'notification-capture'
        ? 'notification-capture'
        : this.feature;
    final guide = discoveryFeatureGuide(feature);
    if (progress.requestedHint != feature ||
        !progress.guideActive ||
        guide == null) {
      return const SizedBox.shrink();
    }
    final controller = ref.read(discoveryControllerProvider(owner).notifier);
    final ledger = ref.watch(ledgerProvider);
    final index = progress.guideStep.clamp(0, guide.steps.length - 1);
    final step = guide.steps[index];
    final route = discoveryFeatureRoute(step.route, ledger);
    final router = GoRouter.maybeOf(context);
    final routes = router?.routerDelegate.currentConfiguration;
    final currentPath = routes == null || routes.isEmpty
        ? null
        : routes.last.matchedLocation;
    final expectedPath = route == null ? null : Uri.parse(route).path;
    if (currentPath != null && currentPath != expectedPath && route != null) {
      final arrived = guide.steps.indexWhere(
        (candidate) =>
            discoveryFeatureRoute(candidate.route, ledger) != null &&
            Uri.parse(discoveryFeatureRoute(candidate.route, ledger)!).path ==
                currentPath,
      );
      if (arrived > index) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted &&
              ref.read(authControllerProvider).ownerId == owner &&
              ref.read(discoveryControllerProvider(owner)).requestedHint ==
                  feature &&
              ref.read(discoveryControllerProvider(owner)).guideStep == index) {
            unawaited(_run(context, () => controller.setGuideStep(arrived)));
          }
        });
        return const SizedBox.shrink();
      }
      if (currentPath == '/account/new') return const SizedBox.shrink();
    }
    final targets = _GuideTargets.of(context)!;
    final returnedFromDraft =
        step.leaveDraft &&
        guide.steps.any((candidate) {
          final candidateRoute = discoveryFeatureRoute(candidate.route, ledger);
          return candidateRoute != null &&
              Uri.parse(candidateRoute).path == currentPath;
        });
    final needsRoute =
        !returnedFromDraft &&
        route != null &&
        currentPath != null &&
        currentPath != expectedPath;
    final prerequisite = route == null;

    Future<void> next() async {
      if (ref.read(authControllerProvider).ownerId != owner) {
        throw StateError('The wallet owner changed.');
      }
      if (prerequisite || needsRoute) {
        if (router == null) throw StateError('Navigation is not available.');
        unawaited(router.push<void>(route ?? '/account/new?type=bank'));
        return;
      }
      if (index + 1 < guide.steps.length) {
        await controller.setGuideStep(index + 1);
        if (!context.mounted) return;
        if (ref.read(authControllerProvider).ownerId != owner) return;
        final nextRoute = discoveryFeatureRoute(
          guide.steps[index + 1].route,
          ledger,
        );
        if (nextRoute != null && Uri.parse(nextRoute).path != currentPath) {
          if (router == null) throw StateError('Navigation is not available.');
          unawaited(router.push<void>(nextRoute));
        }
      } else {
        final nextFeature = await controller.completeFeatureGuide(feature);
        if (!context.mounted) return;
        if (ref.read(authControllerProvider).ownerId != owner) return;
        if (feature == 'calendar-days' && index == 1) {
          Navigator.of(context).pop();
        }
        if (nextFeature != null) {
          final nextGuide = discoveryFeatureGuide(nextFeature)!;
          final nextRoute = discoveryFeatureRoute(
            nextGuide.steps.first.route,
            ledger,
          );
          if (router == null) throw StateError('Navigation is not available.');
          router.go(nextRoute ?? '/accounts');
        } else if (step.leaveDraft) {
          router?.go('/');
        }
      }
    }

    return DiscoveryCoachMark(
      target: targets.keyFor(
        prerequisite || needsRoute ? 'screen' : step.anchor,
      ),
      title: prerequisite ? 'A bank or card account first' : step.title,
      message: prerequisite
          ? 'Cash accounts do not have bank credentials. Add a bank or card account, then return here to continue. Nothing is created automatically.'
          : needsRoute
          ? 'Open the real feature to continue this guide. Your wallet data will not be changed.'
          : step.message,
      counter: '${index + 1} / ${guide.steps.length}',
      onClose: () =>
          unawaited(_run(context, () => controller.dismissHint(feature))),
      actions: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (index > 0)
            IconButton(
              tooltip: 'Previous tip',
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () => unawaited(
                _run(context, () async {
                  await controller.setGuideStep(index - 1);
                  if (!context.mounted) return;
                  if (ref.read(authControllerProvider).ownerId != owner) return;
                  final previousRoute = discoveryFeatureRoute(
                    guide.steps[index - 1].route,
                    ledger,
                  );
                  if (previousRoute != null && router != null) {
                    router.go(previousRoute);
                  }
                }),
              ),
            ),
          if (!step.requiresTap || needsRoute)
            FilledButton(
              onPressed: () => unawaited(_run(context, next)),
              child: Text(
                prerequisite
                    ? 'Add bank account'
                    : needsRoute
                    ? 'Open feature'
                    : step.leaveDraft
                    ? 'Leave draft'
                    : index + 1 == guide.steps.length
                    ? 'Finish guide'
                    : 'Continue',
              ),
            )
          else
            const Text('Tap a date to continue'),
          IconButton(
            tooltip: 'Skip this guide',
            icon: const Icon(Icons.skip_next_rounded),
            onPressed: () => unawaited(
              _run(context, () async {
                final nextFeature = await controller.completeFeatureGuide(
                  feature,
                );
                if (!context.mounted || router == null) return;
                if (ref.read(authControllerProvider).ownerId != owner) return;
                if (nextFeature != null) {
                  router.go(
                    discoveryFeatureRoute(
                          discoveryFeatureGuide(nextFeature)!.steps.first.route,
                          ledger,
                        ) ??
                        '/accounts',
                  );
                }
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// Isolated examples: no controller mutations, capture imports or credentials.
class DiscoveryGuideSample extends ConsumerStatefulWidget {
  const DiscoveryGuideSample({required this.feature, super.key});
  final String feature;

  @override
  ConsumerState<DiscoveryGuideSample> createState() =>
      _DiscoveryGuideSampleState();
}

class _DiscoveryGuideSampleState extends ConsumerState<DiscoveryGuideSample> {
  bool _tried = false;

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(
      authControllerProvider.select((auth) => auth.ownerId),
    );
    final progress = owner == null
        ? null
        : ref.watch(discoveryControllerProvider(owner));
    if (progress == null ||
        !progress.guideActive ||
        (progress.requestedHint != widget.feature &&
            !(widget.feature == 'review-inbox' &&
                progress.requestedHint == 'notification-capture'))) {
      return const SizedBox.shrink();
    }
    final ledger = ref.watch(ledgerProvider);
    final review =
        widget.feature == 'review-inbox' ||
        widget.feature == 'notification-capture';
    String title;
    String detail;
    String action;
    if (review) {
      const message = 'USD 12.50 debited from A/c XX4242 at SAMPLE CAFE.';
      final parsed = parseTransactionMessage(message, fallbackCurrency: 'USD');
      final sample = ledger.copyWith(
        accounts: [
          const Account(
            id: 'sample-bank',
            name: 'Sample Everyday',
            type: 'bank',
            currency: 'USD',
            accountLast4: '4242',
            openingBalance: Money(amountMinor: 0, currency: 'USD'),
          ),
          const Account(
            id: 'sample-other',
            name: 'Sample Travel',
            type: 'bank',
            currency: 'USD',
            accountLast4: '8181',
            openingBalance: Money(amountMinor: 0, currency: 'USD'),
          ),
        ],
      );
      final match = matchAccountToCapturedMessage(sample, parsed);
      title = _tried
          ? 'Suffix ${parsed.last4} → ${match == 'sample-bank' ? 'Sample Everyday' : 'Choose an account'}'
          : 'A captured bank message';
      detail = _tried
          ? 'Amount: USD 12.50. Check the suggested account before approving. This sample was never queued or saved.'
          : message;
      action = _tried ? 'Show message' : 'Show account match';
    } else if (widget.feature == 'loan-forecast') {
      title = _tried ? 'Sample: extra repayments' : 'Sample: normal repayments';
      detail = _tried
          ? 'A larger monthly repayment reduces the example balance faster. The real forecast uses your loan terms.'
          : 'Compare a fictional repayment path without changing saved forecast preferences.';
      action = _tried ? 'Reset example' : 'Try extra payment';
    } else if (widget.feature == 'loans') {
      title = _tried ? 'Sample balance: USD 900' : 'Sample loan: USD 1,000';
      detail = _tried
          ? 'A USD 100 principal repayment lowers the example debt. Real repayments may also include interest.'
          : 'Loan balance + scheduled EMI + actual repayments work together.';
      action = _tried ? 'Reset example' : 'Try a repayment';
    } else {
      title = _tried ? 'Sample: payment posted' : 'Sample: monthly rent';
      detail = _tried
          ? 'Planned USD 500 → actual USD 500. In your wallet, posting a real payment updates history and balances.'
          : 'USD 500 due each month. A schedule forecasts the next occurrence; it is not proof that you paid.';
      action = _tried ? 'Reset example' : 'Show posted payment';
    }
    return DiscoveryGuideAnchor(
      id: 'sample',
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: AppPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SAMPLE · NOT SAVED',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xxs),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
              if (widget.feature == 'loan-forecast')
                SizedBox(
                  height: 56,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _SampleForecastPainter(
                      extra: _tried,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              TextButton(
                onPressed: () => setState(() => _tried = !_tried),
                child: Text(action),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SampleForecastPainter extends CustomPainter {
  const _SampleForecastPainter({required this.extra, required this.color});
  final bool extra;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final normal = [1000, 800, 600, 400, 200, 0];
    final faster = [1000, 650, 300, 0, 0, 0];
    Path curve(List<int> balances) {
      final path = Path();
      for (var i = 0; i < balances.length; i++) {
        final point = Offset(
          i * size.width / (balances.length - 1),
          4 + (1 - balances[i] / 1000) * (size.height - 8),
        );
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      return path;
    }

    canvas.drawPath(
      curve(normal),
      Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawPath(
      curve(extra ? faster : normal),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_SampleForecastPainter oldDelegate) =>
      extra != oldDelegate.extra || color != oldDelegate.color;
}
