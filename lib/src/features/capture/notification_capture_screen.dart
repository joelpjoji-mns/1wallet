import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../capture/capture_pipeline.dart';
import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/privacy_text.dart';
import '../common/route_scaffold.dart';
import 'notification_apps_screen.dart';
import 'sms_inbox_reader.dart'; // we put the native methods here

class NotificationCaptureScreen extends ConsumerStatefulWidget {
  const NotificationCaptureScreen({super.key});

  @override
  ConsumerState<NotificationCaptureScreen> createState() =>
      _NotificationCaptureScreenState();
}

class _NotificationCaptureScreenState
    extends ConsumerState<NotificationCaptureScreen> {
  final _testController = TextEditingController();
  CaptureImportResult? _preview;
  bool _permissionGranted = false;
  bool _checkedPermission = false;
  bool _isScanning = false;
  bool _scanOnlyTargetApps = true;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    if (_isAndroid) _refreshPermission();
  }

  @override
  void dispose() {
    _testController.dispose();
    super.dispose();
  }

  Future<void> _refreshPermission() async {
    final granted = await getAndroidNotificationPermissionState();
    if (!mounted) return;
    setState(() {
      _permissionGranted = granted;
      _checkedPermission = true;
    });
  }

  void _updatePrefs(LedgerPreferences next) {
    ref.read(ledgerProvider.notifier).updatePreferences(next);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerProvider);
    final prefs = state.preferences;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pending = state.captureCandidates
        .where((c) => c.status == 'pending')
        .length;

    final preview =
        _preview ??
        ref
            .read(ledgerProvider.notifier)
            .previewNotificationMessage(_testController.text);
    final parsed = preview.parsed;

    return RouteScaffold(
      title: 'Notification Capture',
      actions: [
        HeaderIconButton(
          icon: Icons.bug_report_outlined,
          semanticLabel: 'Capture diagnostics',
          onPressed: () => context.push('/auto-capture/debug'),
        ),
        HeaderIconButton(
          icon: Icons.fact_check_outlined,
          semanticLabel: 'Review queue',
          onPressed: () => context.push('/review'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Scan active notifications (kept up top for quick access) ──
          if (_isAndroid) ...[
            _scanNotificationsCard(scheme, prefs),
            const Gap(AppSpacing.lg),
          ] else ...[
            SectionCard(
              title: 'Platform availability',
              subtitle:
                  'Automatic notification listener is supported on Android. On iOS and Web, system security prevents reading notifications from other apps. You can test notification formats using the tester below or import bank statements directly.',
              child: OutlinedButton.icon(
                onPressed: () => context.push('/sync'),
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('Go to Statement Imports'),
              ),
            ),
            const Gap(AppSpacing.lg),
          ],
          SectionCard(
            title: 'Automatic capture',
            subtitle:
                'Turn incoming notifications into review-queue candidates automatically.',
            child: Column(
              children: [
                AppSwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: prefs.notificationCaptureEnabled,
                  onChanged: (value) {
                    _updatePrefs(
                      prefs.copyWith(notificationCaptureEnabled: value),
                    );
                  },
                  title: const Text('Enable notification capture'),
                  subtitle: Text(
                    prefs.notificationCaptureEnabled
                        ? 'A review candidate is created when a real transaction is detected.'
                        : 'Notifications are ignored.',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (pending > 0) ...[
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () => context.push('/review'),
                      icon: const Icon(Icons.inbox_outlined),
                      label: Text('Review $pending pending'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Gap(AppSpacing.lg),

          if (_isAndroid) ...[
            SectionCard(
              title: 'Permission',
              subtitle:
                  'Reading notifications requires Notification Access permission.',
              child: Column(
                children: [
                  InfoRow(
                    label: 'Notification Access',
                    value: !_checkedPermission
                        ? 'Checking…'
                        : (_permissionGranted ? 'Granted' : 'Not granted'),
                    icon: _permissionGranted
                        ? Icons.verified_user_outlined
                        : Icons.gpp_maybe_outlined,
                    tone: _permissionGranted
                        ? MetricTone.positive
                        : MetricTone.warning,
                  ),
                  if (!_permissionGranted) ...[
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          await requestAndroidNotificationPermission();
                          // Permission settings requires navigating away, so we just check on resume,
                          // but for now we'll do a delayed check.
                          Future.delayed(
                            const Duration(seconds: 3),
                            _refreshPermission,
                          );
                        },
                        icon: const Icon(Icons.settings_suggest_outlined),
                        label: const Text('Open Settings to Grant'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Gap(AppSpacing.lg),

            PremiumRow(
              icon: Icons.apps_outlined,
              title: 'Target Apps',
              subtitle:
                  '${prefs.notificationTargetPackages.length} apps selected for monitoring',
              onTap: () => context.push('/notification-capture/apps'),
            ),
            const Gap(AppSpacing.lg),
          ],

          _WordEditor(
            title: 'Trigger words',
            subtitle:
                'Any of these signals a real transaction. Add words your bank uses.',
            words: prefs.notificationTriggerWords,
            accent: scheme.primary,
            onChanged: (words) =>
                _updatePrefs(prefs.copyWith(notificationTriggerWords: words)),
            onReset: () => _updatePrefs(
              prefs.copyWith(notificationTriggerWords: kDefaultSmsTriggerWords),
            ),
          ),
          const Gap(AppSpacing.lg),

          _WordEditor(
            title: 'Ignore words',
            subtitle:
                'If any of these appear the notification is never queued.',
            words: prefs.notificationIgnoreWords,
            accent: scheme.error,
            onChanged: (words) =>
                _updatePrefs(prefs.copyWith(notificationIgnoreWords: words)),
            onReset: () => _updatePrefs(
              prefs.copyWith(notificationIgnoreWords: kDefaultSmsIgnoreWords),
            ),
          ),
          const Gap(AppSpacing.lg),

          SectionCard(
            title: 'Test a notification text',
            subtitle:
                'Paste any notification text to see exactly how it would be handled.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppGlassTextField(
                  controller: _testController,
                  minLines: 3,
                  maxLines: 6,
                  onChanged: (_) => setState(() => _preview = null),
                  decoration: const InputDecoration(
                    labelText: 'Notification text',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.notifications_outlined),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InfoRow(
                      label: 'Outcome',
                      value: _previewOutcome(preview),
                      icon: preview.queued
                          ? Icons.fact_check_outlined
                          : (preview.duplicate
                                ? Icons.library_add_check_outlined
                                : Icons.visibility_off_outlined),
                      tone: preview.queued
                          ? MetricTone.positive
                          : MetricTone.warning,
                    ),
                  ],
                ),
                InfoRow(
                  label: 'Amount',
                  value: parsed.amount == null
                      ? 'Not detected'
                      : maskMoneyIfPrivate(
                          state,
                          formatMoney(parsed.amount!, prefs.locale),
                        ),
                  icon: Icons.payments_outlined,
                ),
                InfoRow(
                  label: 'Direction',
                  value: parsed.transactionType == null
                      ? 'Needs review'
                      : transactionTypeLabel(parsed.transactionType!),
                  icon: Icons.swap_vert_rounded,
                ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton.tonalIcon(
                  onPressed: preview.queued ? _queueTestMessage : null,
                  icon: const Icon(Icons.playlist_add_check_outlined),
                  label: const Text('Add to review queue'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scanNotificationsCard(ColorScheme scheme, LedgerPreferences prefs) {
    final targetCount = prefs.notificationTargetPackages.length;
    return SectionCard(
      title: 'Scan active notifications',
      subtitle:
          'Find transactions in notifications currently waiting in your status bar or notification shade.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (targetCount > 0) ...[
            AppSwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _scanOnlyTargetApps,
              onChanged: _isScanning
                  ? null
                  : (val) => setState(() => _scanOnlyTargetApps = val),
              title: const Text('Limit to target apps'),
              subtitle: Text(
                _scanOnlyTargetApps
                    ? 'Scanning $targetCount monitored app${targetCount == 1 ? '' : 's'}'
                    : 'Scanning all apps with active notifications',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ] else ...[
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                'No target apps selected. Will scan all active notifications.',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
          ],
          FilledButton.icon(
            onPressed: _isScanning ? null : _startNotificationScan,
            icon: _isScanning
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.manage_search_rounded),
            label: Text(_isScanning ? 'Scanning…' : 'Scan active notifications'),
          ),
        ],
      ),
    );
  }

  Future<void> _startNotificationScan() async {
    final granted = await getAndroidNotificationPermissionState();
    if (!granted) {
      _showMessage('Notification Access permission is required to scan.');
      await requestAndroidNotificationPermission();
      await _refreshPermission();
      return;
    }

    setState(() => _isScanning = true);
    try {
      final targetPkgs =
          ref.read(ledgerProvider).preferences.notificationTargetPackages;
      final filterPackages = (_scanOnlyTargetApps && targetPkgs.isNotEmpty)
          ? targetPkgs
          : null;

      final notifications = await readActiveAndroidNotifications(
        packageNames: filterPackages,
      );

      if (notifications.isEmpty) {
        if (!mounted) return;
        final scopeMsg = (_scanOnlyTargetApps && targetPkgs.isNotEmpty)
            ? 'No active notifications found from monitored apps.'
            : 'No active notifications found in notification drawer.';
        _showMessage(scopeMsg);
        return;
      }

      final items = notifications
          .map(
            (n) => (
              text: n.body,
              receivedAt: DateTime.tryParse(n.receivedAt) ?? DateTime.now(),
              sender: n.appName.isNotEmpty ? n.appName : n.title,
            ),
          )
          .toList();

      final results = await ref
          .read(ledgerProvider.notifier)
          .importNotificationsBatchDetailed(items);

      final queued = results.where((r) => r.queued).length;
      final duplicates = results.where((r) => r.duplicate).length;
      final ignored = results.where((r) => r.ignored).length;

      if (!mounted) return;

      final interestingResults =
          results.where((r) => r.queued || r.duplicate).toList();

      if (interestingResults.isEmpty) {
        _showMessage(
          'Scanned ${notifications.length} active notification${notifications.length == 1 ? '' : 's'} · no transactions found.',
        );
      } else {
        _showScanResultsSheet(
          totalScanned: notifications.length,
          queued: queued,
          duplicates: duplicates,
          ignored: ignored,
          results: interestingResults,
          notifications: notifications,
        );
      }
    } catch (e) {
      _showMessage('Could not scan notifications: $e');
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  void _showScanResultsSheet({
    required int totalScanned,
    required int queued,
    required int duplicates,
    required int ignored,
    required List<CaptureImportResult> results,
    required List<AndroidActiveNotification> notifications,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final state = ref.watch(ledgerProvider);
        final theme = Theme.of(sheetContext);
        final scheme = theme.colorScheme;
        final txMap = {for (final tx in state.transactions) tx.id: tx};
        final candidateMap = {
          for (final c in state.captureCandidates) c.id: c,
        };

        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: theme.scaffoldBackgroundColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadii.lg),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(40),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.onSurfaceVariant.withAlpha(60),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Scan results',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => Navigator.of(sheetContext).pop(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Scanned $totalScanned notification${totalScanned == 1 ? '' : 's'} · $queued queued · $duplicates duplicate${duplicates == 1 ? '' : 's'}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (queued > 0) ...[
                          const SizedBox(height: AppSpacing.sm),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonalIcon(
                              onPressed: () {
                                Navigator.of(sheetContext).pop();
                                context.push('/review');
                              },
                              icon: const Icon(Icons.fact_check_outlined),
                              label: Text('Open review queue ($queued queued)'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      itemCount: results.length,
                      separatorBuilder: (context, _) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) {
                        final item = results[index];
                        final isDuplicate = item.duplicate;
                        final parsed = item.parsed;
                        final dupId = item.duplicateOfId;
                        final dupType = item.duplicateOfType;

                        AndroidActiveNotification? matchingNotif;
                        for (final n in notifications) {
                          if (n.body == parsed.rawText) {
                            matchingNotif = n;
                            break;
                          }
                        }

                        TransactionRecord? matchedTx;
                        CaptureCandidate? matchedCandidate;
                        if (dupId != null) {
                          if (dupType == 'transaction') {
                            matchedTx = txMap[dupId];
                          } else if (dupType == 'candidate') {
                            matchedCandidate = candidateMap[dupId];
                          }
                        }

                        final amountText = parsed.amount != null
                            ? formatMoney(
                                parsed.amount!,
                                state.preferences.locale,
                              )
                            : null;

                        final appTitle =
                            (matchingNotif?.appName.isNotEmpty ?? false)
                            ? matchingNotif!.appName
                            : (parsed.merchant ??
                                (parsed.transactionType == 'income'
                                    ? 'Incoming payment'
                                    : 'Payment'));

                        return Card(
                          margin: EdgeInsets.zero,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.md),
                            side: BorderSide(
                              color: isDuplicate
                                  ? scheme.tertiary.withAlpha(70)
                                  : scheme.outlineVariant.withAlpha(50),
                            ),
                          ),
                          color: isDuplicate
                              ? scheme.tertiaryContainer.withAlpha(25)
                              : scheme.surfaceContainerHighest.withAlpha(40),
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (matchingNotif?.packageName.isNotEmpty ??
                                        false)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: AppSpacing.sm,
                                        ),
                                        child: SizedBox(
                                          width: 32,
                                          height: 32,
                                          child: AppIconWidget(
                                            packageName:
                                                matchingNotif!.packageName,
                                          ),
                                        ),
                                      )
                                    else
                                      Icon(
                                        isDuplicate
                                            ? Icons.copy_rounded
                                            : Icons.notifications_active_outlined,
                                        size: 20,
                                        color: isDuplicate
                                            ? scheme.tertiary
                                            : scheme.primary,
                                      ),
                                    const SizedBox(width: AppSpacing.xs),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  appTitle,
                                                  style: theme
                                                      .textTheme.titleSmall
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (amountText != null)
                                                Text(
                                                  amountText,
                                                  style: theme
                                                      .textTheme.titleSmall
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        parsed.transactionType ==
                                                            'income'
                                                        ? scheme.primary
                                                        : scheme.error,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Container(
                                            padding: const EdgeInsets
                                                .symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isDuplicate
                                                  ? scheme.tertiary.withAlpha(
                                                      35,
                                                    )
                                                  : scheme.primary.withAlpha(
                                                      30,
                                                    ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              isDuplicate
                                                  ? (item.reason ==
                                                          CaptureBlockReason
                                                              .duplicatePosted
                                                      ? 'Duplicate: already entered'
                                                      : 'Duplicate: already in review')
                                                  : 'Added to review',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: isDuplicate
                                                    ? scheme.tertiary
                                                    : scheme.primary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  parsed.rawText,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                if (isDuplicate && dupId != null) ...[
                                  const SizedBox(height: AppSpacing.sm),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(
                                      AppRadii.sm,
                                    ),
                                    onTap: () {
                                      Navigator.of(sheetContext).pop();
                                      if (dupType == 'transaction') {
                                        context.push('/transaction/$dupId');
                                      } else {
                                        context.push('/review');
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: scheme.tertiary.withAlpha(20),
                                        borderRadius: BorderRadius.circular(
                                          AppRadii.sm,
                                        ),
                                        border: Border.all(
                                          color: scheme.tertiary.withAlpha(60),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.link_rounded,
                                            size: 16,
                                            color: scheme.tertiary,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              dupType == 'transaction'
                                                  ? (matchedTx != null
                                                      ? 'View transaction: ${matchedTx.name ?? formatMoney(matchedTx.amount, state.preferences.locale)}'
                                                      : 'View matched transaction')
                                                  : (matchedCandidate != null &&
                                                          matchedCandidate
                                                                  .merchant !=
                                                              null
                                                      ? 'View candidate: ${matchedCandidate.merchant}'
                                                      : 'View in review queue'),
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: scheme.tertiary,
                                              ),
                                            ),
                                          ),
                                          Icon(
                                            Icons.chevron_right_rounded,
                                            size: 18,
                                            color: scheme.tertiary,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _queueTestMessage() async {
    final result = await ref
        .read(ledgerProvider.notifier)
        .importNotificationMessageDetailed(
          _testController.text,
          stage: 'test-notification',
        );
    if (!mounted) return;
    _showMessage(result.userMessage);
    setState(() => _preview = null);
  }

  String _previewOutcome(CaptureImportResult preview) {
    final parsed = preview.parsed;
    if (preview.queued) return 'Would be queued';
    if (preview.duplicate) return 'Duplicate (already in ledger)';
    if (parsed.matchedIgnoreWord != null) {
      return 'Ignored (matched ignore: "${parsed.matchedIgnoreWord}")';
    }
    if (preview.reason == CaptureBlockReason.missingAmount) {
      return 'Ignored (no amount detected)';
    }
    return 'Ignored (no trigger word matched)';
  }
}

class _WordEditor extends StatefulWidget {
  const _WordEditor({
    required this.title,
    required this.subtitle,
    required this.words,
    required this.accent,
    required this.onChanged,
    required this.onReset,
  });

  final String title;
  final String subtitle;
  final List<String> words;
  final Color accent;
  final ValueChanged<List<String>> onChanged;
  final VoidCallback onReset;

  @override
  State<_WordEditor> createState() => _WordEditorState();
}

class _WordEditorState extends State<_WordEditor> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final value = _controller.text.trim().toLowerCase();
    if (value.isEmpty) return;
    if (widget.words.map((w) => w.toLowerCase()).contains(value)) {
      _controller.clear();
      return;
    }
    widget.onChanged([...widget.words, value]);
    _controller.clear();
  }

  void _remove(String word) {
    widget.onChanged(widget.words.where((w) => w != word).toList());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sorted = [...widget.words]..sort();
    return SectionCard(
      title: widget.title,
      subtitle: widget.subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                'No words yet.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          else
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final word in sorted)
                  InputChip(
                    label: Text(word),
                    onDeleted: () => _remove(word),
                    backgroundColor: widget.accent.withAlpha(24),
                    side: BorderSide(color: widget.accent.withAlpha(70)),
                  ),
              ],
            ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: AppGlassTextField(
                  controller: _controller,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _add(),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Add a word',
                    prefixIcon: Icon(Icons.add_rounded),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(onPressed: _add, child: const Text('Add')),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: widget.onReset,
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Reset to defaults'),
            ),
          ),
        ],
      ),
    );
  }
}
