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
import '../common/full_screen_picker.dart';
import '../common/route_scaffold.dart';
import 'sms_inbox_reader.dart';

/// One clean home for SMS auto-capture: enable it, grant permission, tune the
/// trigger/ignore words that decide what becomes a transaction, test a message,
/// and scan the existing inbox. The word lists here are the single source of
/// truth shared with the native Android receiver.
class SmsCaptureScreen extends ConsumerStatefulWidget {
  const SmsCaptureScreen({super.key, this.title = 'SMS auto-capture'});

  final String title;

  @override
  ConsumerState<SmsCaptureScreen> createState() => _SmsCaptureScreenState();
}

class _SmsCaptureScreenState extends ConsumerState<SmsCaptureScreen> {
  final _testController = TextEditingController();
  CaptureImportResult? _preview;
  String _scanTimeframe = '24h';
  bool _isScanning = false;
  bool _permissionGranted = false;
  bool _checkedPermission = false;

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
    final state = await getAndroidSmsPermissionState();
    if (!mounted) return;
    setState(() {
      _permissionGranted = state.overall == 'granted';
      _checkedPermission = true;
    });
  }

  LedgerPreferences get _prefs => ref.read(ledgerProvider).preferences;

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

    final preview = _preview ??
        ref
            .read(ledgerProvider.notifier)
            .previewSmsMessage(_testController.text);
    final parsed = preview.parsed;

    return RouteScaffold(
      title: widget.title,
      actions: [
        HeaderIconButton(
          icon: Icons.bug_report_outlined,
          onPressed: () => context.push('/auto-capture/debug'),
        ),
        HeaderIconButton(
          icon: Icons.fact_check_outlined,
          onPressed: () => context.push('/review'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Scan existing inbox (kept up top for quick access) ──
          if (_isAndroid) ...[
            _scanInboxCard(scheme),
            const Gap(AppSpacing.lg),
          ],
          // ── Master toggle ──
          SectionCard(
            title: 'Automatic capture',
            subtitle:
                'Turn incoming bank SMS into review-queue candidates automatically.',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: prefs.smsCaptureEnabled,
                  onChanged: (value) {
                    _updatePrefs(prefs.copyWith(smsCaptureEnabled: value));
                  },
                  title: const Text('Enable SMS capture'),
                  subtitle: Text(
                    prefs.smsCaptureEnabled
                        ? 'A notification is raised only when a real transaction is found.'
                        : 'Incoming SMS are ignored.',
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

          // ── Permission (Android only) ──
          if (_isAndroid) ...[
            SectionCard(
              title: 'Permission',
              subtitle:
                  'Reading SMS requires the Android SMS permission. It never leaves your device.',
              child: Column(
                children: [
                  InfoRow(
                    label: 'SMS permission',
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
                          await requestAndroidSmsPermission();
                          await _refreshPermission();
                        },
                        icon: const Icon(Icons.lock_open_outlined),
                        label: const Text('Grant SMS permission'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Gap(AppSpacing.lg),
          ],

          // ── How it works ──
          const SectionCard(
            title: 'How it works',
            subtitle:
                'The same checks power live capture, Scan Inbox, Test message, notifications, and Review.',
            child: Column(
              children: [
                _RuleRow(
                  icon: Icons.payments_outlined,
                  text: 'It contains an amount (e.g. ₹1,250 or \$40).',
                ),
                _RuleRow(
                  icon: Icons.check_circle_outline,
                  text:
                      'It contains a trigger word (debited, credited, spent…).',
                ),
                _RuleRow(
                  icon: Icons.block_outlined,
                  text:
                      'It has no ignore word (OTP, offer, reminder, request…).',
                ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),

          // ── Trigger words ──
          _WordEditor(
            title: 'Trigger words',
            subtitle:
                'Any of these signals a real transaction. Add words your bank uses.',
            words: prefs.smsTriggerWords,
            accent: scheme.primary,
            onChanged: (words) =>
                _updatePrefs(prefs.copyWith(smsTriggerWords: words)),
            onReset: () => _updatePrefs(
              prefs.copyWith(smsTriggerWords: kDefaultSmsTriggerWords),
            ),
          ),
          const Gap(AppSpacing.lg),

          // ── Ignore words ──
          _WordEditor(
            title: 'Ignore words',
            subtitle:
                'If any of these appear the message is never queued or notified.',
            words: prefs.smsIgnoreWords,
            accent: scheme.error,
            onChanged: (words) =>
                _updatePrefs(prefs.copyWith(smsIgnoreWords: words)),
            onReset: () => _updatePrefs(
              prefs.copyWith(smsIgnoreWords: kDefaultSmsIgnoreWords),
            ),
          ),
          const Gap(AppSpacing.lg),

          // ── Test a message ──
          SectionCard(
            title: 'Test a message',
            subtitle: 'Paste any SMS to see exactly how it would be handled.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _testController,
                  minLines: 3,
                  maxLines: 6,
                  onChanged: (_) => setState(() => _preview = null),
                  decoration: const InputDecoration(
                    labelText: 'SMS text',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.sms_outlined),
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
                        : preview.duplicate
                        ? Icons.library_add_check_outlined
                        : Icons.visibility_off_outlined,
                      tone: preview.queued
                        ? MetricTone.positive
                        : MetricTone.warning,
                    ),
                    if (parsed.ignored && parsed.matchedIgnoreWord != null) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () {
                            final word = parsed.matchedIgnoreWord!;
                            final nextIgnores = prefs.smsIgnoreWords
                                .where((w) => w.toLowerCase() != word.toLowerCase())
                                .toList();
                            _updatePrefs(prefs.copyWith(smsIgnoreWords: nextIgnores));
                            _showMessage('Removed "$word" from ignore words.');
                          },
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: Text('Remove "${parsed.matchedIgnoreWord}" from ignore list'),
                          style: TextButton.styleFrom(
                            foregroundColor: scheme.error,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(50, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ],
                    if (!parsed.ignored && parsed.matchedTriggerWord != null) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () {
                            final word = parsed.matchedTriggerWord!;
                            final nextTriggers = prefs.smsTriggerWords
                                .where((w) => w.toLowerCase() != word.toLowerCase())
                                .toList();
                            _updatePrefs(prefs.copyWith(smsTriggerWords: nextTriggers));
                            _showMessage('Removed "$word" from trigger words.');
                          },
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: Text('Remove "${parsed.matchedTriggerWord}" from triggers'),
                          style: TextButton.styleFrom(
                            foregroundColor: scheme.error,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(50, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                    ],
                    if (parsed.ignored && parsed.matchedIgnoreWord == null) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Select a word from the SMS to add to triggers:',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final word in _extractCandidateWords(_testController.text))
                            ActionChip(
                              label: Text(word),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                final nextTriggers = [...prefs.smsTriggerWords, word];
                                _updatePrefs(prefs.copyWith(smsTriggerWords: nextTriggers));
                                _showMessage('Added "$word" to trigger words.');
                              },
                            ),
                        ],
                      ),
                    ],
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
                InfoRow(
                  label: 'Merchant',
                  value: parsed.merchant ?? 'Not detected',
                  icon: Icons.storefront_outlined,
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

  Widget _scanInboxCard(ColorScheme scheme) {
    return SectionCard(
      title: 'Scan existing inbox',
      subtitle: 'Find transactions already sitting in your SMS inbox.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PremiumRow(
            icon: Icons.history_rounded,
            title: 'Timeframe',
            subtitle: _scanTimeframeLabel(_scanTimeframe),
            onTap: _isScanning ? () {} : _showScanTimeframePicker,
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: _isScanning ? null : _startBatchScan,
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
            label: Text(_isScanning ? 'Scanning…' : 'Scan inbox'),
          ),
        ],
      ),
    );
  }

  Future<void> _queueTestMessage() async {
    final result = await ref
        .read(ledgerProvider.notifier)
        .importSmsMessageDetailed(_testController.text, stage: 'test-message');
    if (!mounted) return;
    _showMessage(result.userMessage);
    setState(() => _preview = null);
  }

  Future<void> _startBatchScan() async {
    final status = await requestAndroidSmsPermission();
    if (status != AndroidSmsPermissionStatus.granted) {
      _showMessage('SMS permission is required to scan the inbox.');
      await _refreshPermission();
      return;
    }
    setState(() => _isScanning = true);
    try {
      final now = DateTime.now();
      final minDate = switch (_scanTimeframe) {
        'today' => DateTime(now.year, now.month, now.day),
        '7d' => now.subtract(const Duration(days: 7)),
        '30d' => now.subtract(const Duration(days: 30)),
        _ => now.subtract(const Duration(hours: 24)),
      };

      final messages = await readAndroidSmsInbox(
        maxCount: 0,
        minDate: minDate.millisecondsSinceEpoch,
      );
      if (messages.isEmpty) {
        _showMessage('No messages found in that timeframe.');
        return;
      }

      final texts = messages
          .map((m) => (
                text: m.body,
                receivedAt: DateTime.tryParse(m.receivedAt) ?? DateTime.now(),
              ))
          .toList();

      final results = await ref
          .read(ledgerProvider.notifier)
          .importSmsMessagesBatchDetailed(texts);
      final queued = results.where((result) => result.queued).length;
      final duplicates = results.where((result) => result.duplicate).length;
      final ignored = results.where((result) => result.ignored).length;

      _showMessage(
        'Scanned ${messages.length} messages · queued $queued · duplicates $duplicates · ignored $ignored.',
      );
    } catch (e) {
      _showMessage('Could not scan inbox: $e');
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  String _previewOutcome(CaptureImportResult preview) {
    final parsed = preview.parsed;
    if (preview.queued) {
      return 'Would be queued${parsed.matchedTriggerWord != null ? ' (matched trigger: "${parsed.matchedTriggerWord}")' : ''}';
    }
    if (preview.duplicate) {
      return preview.reason == CaptureBlockReason.duplicatePosted
          ? 'Duplicate (already posted)'
          : 'Duplicate (already in Review)';
    }
    if (parsed.matchedIgnoreWord != null) {
      return 'Ignored (matched ignore: "${parsed.matchedIgnoreWord}")';
    }
    if (preview.reason == CaptureBlockReason.missingAmount) {
      return 'Ignored (no amount detected)';
    }
    return 'Ignored (no trigger word matched)';
  }

  String _scanTimeframeLabel(String value) {
    return switch (value) {
      'today' => 'Today',
      '24h' => 'Last 1 day',
      '7d' => 'Last 7 days',
      '30d' => 'Last 30 days',
      _ => 'Last 1 day',
    };
  }

  Future<void> _showScanTimeframePicker() async {
    final next = await showFullScreenPicker<String>(
      context: context,
      title: 'Scan range',
      subtitle:
          'Scan every SMS in the selected range with the same engine used for live capture.',
      searchable: false,
      selectedValue: _scanTimeframe,
      options: const [
        PickerOption(
          value: '24h',
          title: 'Last 1 day',
          subtitle: 'Default · best for quick reliable scans',
          icon: Icons.today_outlined,
        ),
        PickerOption(
          value: 'today',
          title: 'Today',
          subtitle: 'From midnight today',
          icon: Icons.calendar_today_outlined,
        ),
        PickerOption(
          value: '7d',
          title: 'Last 7 days',
          icon: Icons.date_range_outlined,
        ),
        PickerOption(
          value: '30d',
          title: 'Last 30 days',
          icon: Icons.calendar_month_outlined,
        ),
      ],
    );
    if (next == null || next == _scanTimeframe || !mounted) return;
    setState(() => _scanTimeframe = next);
  }

  List<String> _extractCandidateWords(String text) {
    if (text.trim().isEmpty) return [];
    final words = text
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .split(RegExp(r'\s+'));
    final seen = <String>{};
    final result = <String>[];

    final currentTriggers = _prefs.smsTriggerWords.map((w) => w.toLowerCase()).toSet();
    final currentIgnores = _prefs.smsIgnoreWords.map((w) => w.toLowerCase()).toSet();

    for (final raw in words) {
      final clean = raw.trim().toLowerCase();
      if (clean.length < 3) continue;
      if (double.tryParse(clean) != null) continue;
      if (seen.contains(clean)) continue;
      seen.add(clean);
      if (currentTriggers.contains(clean) || currentIgnores.contains(clean)) continue;
      result.add(raw.trim());
    }
    return result.take(8).toList();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
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
