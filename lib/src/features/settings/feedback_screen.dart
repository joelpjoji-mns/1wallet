import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/app_kit.dart';
import '../common/route_scaffold.dart';

/// Screen allowing the user to send bug reports, feature requests, or general
/// feedback directly to Joel P Joji (joelpjoji1222@gmail.com), complete with
/// auto-collected device diagnostics, theme information, and ledger configuration.
class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key});

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

enum FeedbackCategory {
  bug('Bug Report', Icons.bug_report_rounded),
  feature('Feature Request', Icons.lightbulb_rounded),
  theme('Theme & Optics Polish', Icons.palette_rounded),
  ledger('Ledger & Accounting', Icons.account_balance_wallet_rounded),
  performance('Performance & Smoothness', Icons.speed_rounded),
  general('General Feedback', Icons.chat_bubble_outline_rounded);

  const FeedbackCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  final _messageController = TextEditingController();
  final _subjectController = TextEditingController();
  FeedbackCategory _selectedCategory = FeedbackCategory.bug;

  String _appVersion = 'Loading...';
  String _buildNumber = '';
  bool _includeDiagnostics = true;

  static const String _recipientEmail = 'joelpjoji1222@gmail.com';

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    _updateDefaultSubject();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _subjectController.dispose();
    super.dispose();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = info.version;
          _buildNumber = info.buildNumber;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _appVersion = '2.2.89';
          _buildNumber = '89';
        });
      }
    }
  }

  void _updateDefaultSubject() {
    _subjectController.text =
        '[1Wallet Feedback - ${_selectedCategory.label}] ';
  }

  String _buildDiagnosticsText() {
    final themeState = ref.read(themeControllerProvider);
    final ledger = ref.read(ledgerProvider);

    final platformStr = kIsWeb
        ? 'Web'
        : Platform.isAndroid
        ? 'Android'
        : Platform.isIOS
        ? 'iOS'
        : Platform.isWindows
        ? 'Windows'
        : Platform.isMacOS
        ? 'macOS'
        : Platform.isLinux
        ? 'Linux'
        : 'Unknown';

    final buffer = StringBuffer();
    buffer.writeln('=== Device & App Diagnostics ===');
    buffer.writeln('App Version: $_appVersion (Build $_buildNumber)');
    buffer.writeln('Platform: $platformStr');
    buffer.writeln('Theme Mode: ${themeState.preference.name}');
    buffer.writeln(
      'Color Intensity: ${(themeState.colorIntensity * 100).round()}%',
    );
    buffer.writeln(
      'Surface Contrast: ${(themeState.surfaceContrast * 100).round()}%',
    );
    buffer.writeln(
      'Outline Thickness: ${themeState.outlineThickness.toStringAsFixed(1)} px',
    );
    buffer.writeln(
      'Outline Opacity: ${(themeState.outlineOpacity * 100).round()}%',
    );
    buffer.writeln('Base Currency: ${ledger.preferences.baseCurrency}');
    buffer.writeln('Display Currency: ${ledger.preferences.displayCurrency}');
    buffer.writeln('Active Locale: ${ledger.preferences.locale}');
    buffer.writeln('Accounts Count: ${ledger.accounts.length}');
    buffer.writeln('================================');
    return buffer.toString();
  }

  String _buildFullEmailBody() {
    final buffer = StringBuffer();
    buffer.writeln('Issue / Feedback:');
    buffer.writeln(
      _messageController.text.trim().isEmpty
          ? '(No additional notes provided)'
          : _messageController.text.trim(),
    );
    buffer.writeln();
    if (_includeDiagnostics) {
      buffer.writeln(_buildDiagnosticsText());
    }
    return buffer.toString();
  }

  Future<void> _sendEmail() async {
    final subject = _subjectController.text.trim().isEmpty
        ? '[1Wallet Feedback] ${_selectedCategory.label}'
        : _subjectController.text.trim();
    final body = _buildFullEmailBody();

    final uri = Uri(
      scheme: 'mailto',
      path: _recipientEmail,
      query:
          'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
    );

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        // Fallback: copy to clipboard
        await Clipboard.setData(
          ClipboardData(
            text: 'To: $_recipientEmail\nSubject: $subject\n\n$body',
          ),
        );
        if (!mounted) return;
        showAppSnackBar(
          context,
          'Could not launch email app. Message copied to clipboard!',
        );
      }
    } catch (_) {
      if (mounted) {
        await Clipboard.setData(
          ClipboardData(
            text: 'To: $_recipientEmail\nSubject: $subject\n\n$body',
          ),
        );
        if (!mounted) return;
        showAppSnackBar(
          context,
          'Copied feedback to clipboard. Send to $_recipientEmail',
        );
      }
    }
  }

  Future<void> _copyToClipboard() async {
    HapticFeedback.selectionClick();
    final subject = _subjectController.text.trim();
    final body = _buildFullEmailBody();
    final fullText = 'To: $_recipientEmail\nSubject: $subject\n\n$body';
    await Clipboard.setData(ClipboardData(text: fullText));
    if (!mounted) return;
    showAppSnackBar(context, 'Feedback & diagnostics copied to clipboard!');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return RouteScaffold(
      title: 'Feedback & Support',
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header Card ──
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      scheme.primary.withAlphaFactor(isDark ? 0.22 : 0.12),
                      scheme.surfaceContainerHigh,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AppRadii.xl),
                  border: Border.all(
                    color: scheme.primary.withAlphaFactor(0.30),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: scheme.primary.withAlphaFactor(0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.mail_outline_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Connect with Joel',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Have an issue, feature idea, or visual bug? Send an email straight to $_recipientEmail.',
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
              const SizedBox(height: AppSpacing.md),

              // ── Category Selector ──
              AppGroupedSection(
                header: 'Category',
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: FeedbackCategory.values.map((cat) {
                        final isSelected = cat == _selectedCategory;
                        return ChoiceChip(
                          selected: isSelected,
                          avatar: Icon(
                            cat.icon,
                            size: 16,
                            color: isSelected
                                ? scheme.onPrimary
                                : scheme.primary,
                          ),
                          label: Text(cat.label),
                          selectedColor: scheme.primary,
                          labelStyle: theme.textTheme.labelMedium?.copyWith(
                            color: isSelected
                                ? scheme.onPrimary
                                : scheme.onSurface,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                          onSelected: (val) {
                            if (val) {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _selectedCategory = cat;
                                _updateDefaultSubject();
                              });
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Subject & Description Fields ──
              AppGroupedSection(
                header: 'Feedback Details',
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: TextField(
                      controller: _subjectController,
                      decoration: const InputDecoration(
                        labelText: 'Subject',
                        prefixIcon: Icon(Icons.title_rounded),
                      ),
                    ),
                  ),
                  const GlassDivider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: TextField(
                      controller: _messageController,
                      maxLines: 5,
                      minLines: 3,
                      decoration: const InputDecoration(
                        labelText:
                            'What happened or what would you like to see?',
                        hintText:
                            'Describe the issue or share your thoughts...',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Diagnostics Preview ──
              AppGroupedSection(
                header: 'Diagnostics & Device Details',
                children: [
                  AppGroupedTile.toggle(
                    leading: const Icon(Icons.phonelink_setup_rounded),
                    title: const Text('Include device & app logs'),
                    subtitle: const Text(
                      'Attaches app version, platform, theme, and currency settings to speed up fixes.',
                    ),
                    value: _includeDiagnostics,
                    onChanged: (val) {
                      HapticFeedback.selectionClick();
                      setState(() => _includeDiagnostics = val);
                    },
                  ),
                  if (_includeDiagnostics) ...[
                    const GlassDivider(),
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withAlphaFactor(
                            0.4,
                          ),
                          borderRadius: BorderRadius.circular(AppRadii.md),
                          border: Border.all(
                            color: scheme.outlineVariant.withAlphaFactor(0.3),
                          ),
                        ),
                        child: Text(
                          _buildDiagnosticsText(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: AppFonts.mono,
                            color: scheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Action Buttons ──
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copyToClipboard,
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copy to clipboard'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.lg),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _sendEmail,
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text('Send Email'),
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.primary,
                        foregroundColor: scheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.lg),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
