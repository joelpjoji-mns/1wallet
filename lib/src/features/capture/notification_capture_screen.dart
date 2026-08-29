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
import 'sms_inbox_reader.dart'; // we put the native methods here

class NotificationCaptureScreen extends ConsumerStatefulWidget {
  const NotificationCaptureScreen({super.key});

  @override
  ConsumerState<NotificationCaptureScreen> createState() => _NotificationCaptureScreenState();
}

class _NotificationCaptureScreenState extends ConsumerState<NotificationCaptureScreen> {
  final _testController = TextEditingController();
  CaptureImportResult? _preview;
  bool _permissionGranted = false;
  bool _checkedPermission = false;

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

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
    final pending = state.captureCandidates.where((c) => c.status == 'pending').length;

    final preview = _preview ??
        ref.read(ledgerProvider.notifier).previewSmsMessage(_testController.text);
    final parsed = preview.parsed;

    return RouteScaffold(
      title: 'Notification Capture',
      actions: [
        HeaderIconButton(
          icon: Icons.fact_check_outlined,
          onPressed: () => context.push('/review'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: 'Automatic capture',
            subtitle: 'Turn incoming notifications into review-queue candidates automatically.',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: prefs.notificationCaptureEnabled,
                  onChanged: (value) {
                    _updatePrefs(prefs.copyWith(notificationCaptureEnabled: value));
                  },
                  title: const Text('Enable notification capture'),
                  subtitle: Text(
                    prefs.notificationCaptureEnabled
                        ? 'A review candidate is created when a real transaction is detected.'
                        : 'Notifications are ignored.',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
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
              subtitle: 'Reading notifications requires Notification Access permission.',
              child: Column(
                children: [
                  InfoRow(
                    label: 'Notification Access',
                    value: !_checkedPermission ? 'Checking…' : (_permissionGranted ? 'Granted' : 'Not granted'),
                    icon: _permissionGranted ? Icons.verified_user_outlined : Icons.gpp_maybe_outlined,
                    tone: _permissionGranted ? MetricTone.positive : MetricTone.warning,
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
                          Future.delayed(const Duration(seconds: 3), _refreshPermission);
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
              subtitle: '${prefs.notificationTargetPackages.length} apps selected for monitoring',
              onTap: () => context.push('/notification-capture/apps'),
            ),
            const Gap(AppSpacing.lg),
          ],

          _WordEditor(
            title: 'Trigger words',
            subtitle: 'Any of these signals a real transaction. Add words your bank uses.',
            words: prefs.notificationTriggerWords,
            accent: scheme.primary,
            onChanged: (words) => _updatePrefs(prefs.copyWith(notificationTriggerWords: words)),
            onReset: () => _updatePrefs(prefs.copyWith(notificationTriggerWords: kDefaultSmsTriggerWords)),
          ),
          const Gap(AppSpacing.lg),

          _WordEditor(
            title: 'Ignore words',
            subtitle: 'If any of these appear the notification is never queued.',
            words: prefs.notificationIgnoreWords,
            accent: scheme.error,
            onChanged: (words) => _updatePrefs(prefs.copyWith(notificationIgnoreWords: words)),
            onReset: () => _updatePrefs(prefs.copyWith(notificationIgnoreWords: kDefaultSmsIgnoreWords)),
          ),
          const Gap(AppSpacing.lg),

          SectionCard(
            title: 'Test a notification text',
            subtitle: 'Paste any notification text to see exactly how it would be handled.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
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
                      icon: preview.queued ? Icons.fact_check_outlined : (preview.duplicate ? Icons.library_add_check_outlined : Icons.visibility_off_outlined),
                      tone: preview.queued ? MetricTone.positive : MetricTone.warning,
                    ),
                  ],
                ),
                InfoRow(
                  label: 'Amount',
                  value: parsed.amount == null ? 'Not detected' : maskMoneyIfPrivate(state, formatMoney(parsed.amount!, prefs.locale)),
                  icon: Icons.payments_outlined,
                ),
                InfoRow(
                  label: 'Direction',
                  value: parsed.transactionType == null ? 'Needs review' : transactionTypeLabel(parsed.transactionType!),
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

  Future<void> _queueTestMessage() async {
    final result = await ref.read(ledgerProvider.notifier).importSmsMessageDetailed(_testController.text, stage: 'test-notification');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.userMessage)));
    setState(() => _preview = null);
  }

  String _previewOutcome(CaptureImportResult preview) {
    final parsed = preview.parsed;
    if (preview.queued) return 'Would be queued';
    if (preview.duplicate) return 'Duplicate (already in ledger)';
    if (parsed.matchedIgnoreWord != null) return 'Ignored (matched ignore: "${parsed.matchedIgnoreWord}")';
    if (preview.reason == CaptureBlockReason.missingAmount) return 'Ignored (no amount detected)';
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
              child: Text('No words yet.', style: TextStyle(color: scheme.onSurfaceVariant)),
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
                child: TextField(
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
