import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';
import '../common/route_scaffold.dart';

/// Full-page About screen showcasing 1Wallet's mission, witty origin story,
/// creator spotlight for Joel P Joji, architectural invariants, and links.
class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  String _version = '2.2.89';
  String _buildNumber = '89';

  static const String _creatorName = 'Joel P Joji';
  static const String _creatorEmail = 'joelpjoji1222@gmail.com';
  static const String _githubRepo = 'https://github.com/joelpjoji/1wallet';

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _version = info.version;
          _buildNumber = info.buildNumber;
        });
      }
    } catch (_) {
      // Fallback
    }
  }

  Future<void> _openEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: _creatorEmail,
      query: 'subject=[1Wallet] Hello Joel!',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        await Clipboard.setData(const ClipboardData(text: _creatorEmail));
        if (mounted) {
          showAppSnackBar(context, 'Email address copied: $_creatorEmail');
        }
      }
    }
  }

  Future<void> _openGitHub() async {
    final uri = Uri.parse(_githubRepo);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        await Clipboard.setData(const ClipboardData(text: _githubRepo));
        if (mounted) {
          showAppSnackBar(context, 'GitHub URL copied: $_githubRepo');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return RouteScaffold(
      title: 'About 1Wallet',
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Hero App Banner ──
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xl,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      scheme.primary.withAlphaFactor(isDark ? 0.30 : 0.16),
                      scheme.surfaceContainerHigh,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AppRadii.xl),
                  border: Border.all(
                    color: scheme.primary.withAlphaFactor(0.35),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withAlphaFactor(
                        isDark ? 0.20 : 0.08,
                      ),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            scheme.primary,
                            Color.lerp(scheme.primary, Colors.black, 0.25)!,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: scheme.primary.withAlphaFactor(0.45),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.account_balance_wallet_rounded,
                          color: Colors.white,
                          size: 44,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      '1Wallet',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your money. Your device. Zero spyware.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary.withAlphaFactor(0.16),
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                        border: Border.all(
                          color: scheme.primary.withAlphaFactor(0.35),
                        ),
                      ),
                      child: Text(
                        'v$_version (Build $_buildNumber) · Release',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── The Story Section ──
              AppGroupedSection(
                header: 'The Origin Story',
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Why build another finance app?',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Because modern personal finance apps have lost their minds.\n\n'
                          'Almost every financial app today requires you to sign up with a cloud account, '
                          'demands a \$12/month subscription just to see your own spending charts, and '
                          'promptly sells your grocery receipts to credit card brokers and advertisers.\n\n'
                          '1Wallet was born out of sheer frustration: what if an expense app was completely offline-first, '
                          'stored your financial data securely encrypted on your physical silicon, never required a login to function, '
                          'and looked as stunning as a native Apple liquid-glass operating system?',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // ── The Core Engineering Invariants ──
              const AppGroupedSection(
                header: 'Engineering Philosophy',
                children: [
                  _FeatureHighlightTile(
                    icon: Icons.calculate_rounded,
                    title: 'Integer Minor Units Only',
                    description:
                        'Floating-point double numbers are great for video game graphics, but terrible for money. Every transaction is computed in integer minor units (cents, pence, paise) to eliminate penny-rounding bugs forever.',
                  ),
                  GlassDivider(),
                  _FeatureHighlightTile(
                    icon: Icons.shield_rounded,
                    title: '100% Offline-First & Encrypted',
                    description:
                        'Zero servers watching your midnight snack runs. Biometric lock, PIN gating, and AES-256 PBKDF2 local backup encryption keep your money strictly between you and your phone.',
                  ),
                  GlassDivider(),
                  _FeatureHighlightTile(
                    icon: Icons.auto_awesome_rounded,
                    title: 'Liquid Glass GPU Shaders',
                    description:
                        'Custom optics shaders calculate backdrop refractions, edge light caustics, and adaptive transmission in real-time at a buttery 120 frames per second.',
                  ),
                  GlassDivider(),
                  _FeatureHighlightTile(
                    icon: Icons.document_scanner_rounded,
                    title: 'On-Device Machine Learning',
                    description:
                        'Google ML Kit OCR recognizes receipts on-device, and smart Android SMS alert spooling categorizes transactions without uploading a single byte to the internet.',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Creator Section ──
              AppGroupedSection(
                header: 'Creator & Craftsman',
                children: [
                  AppGroupedTile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: scheme.primary.withAlphaFactor(0.20),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: scheme.primary.withAlphaFactor(0.40),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'JP',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      _creatorName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: const Text(
                      'Sole developer, designer & coffee enthusiast',
                    ),
                    trailing: Icon(
                      Icons.verified_rounded,
                      size: 20,
                      color: scheme.positive,
                    ),
                  ),
                  const GlassDivider(),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      'Built by $_creatorName with countless late-night hours spent tuning liquid glass refraction math, '
                      'polishing dark AMOLED contrast curves, and making sure your financial peace of mind is never compromised.\n\n'
                      'Have an idea, want to report a bug, or just want to talk about shaders? Drop me a line anytime!',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const GlassDivider(),
                  AppGroupedTile(
                    leading: const Icon(Icons.email_outlined),
                    title: const Text('Email Joel directly'),
                    subtitle: const Text(_creatorEmail),
                    showChevron: true,
                    onTap: _openEmail,
                  ),
                  const GlassDivider(),
                  AppGroupedTile(
                    leading: const Icon(Icons.code_rounded),
                    title: const Text('Source Code on GitHub'),
                    subtitle: const Text(
                      'Star, inspect, or contribute to 1Wallet',
                    ),
                    showChevron: true,
                    onTap: _openGitHub,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Tech Stack ──
              const AppGroupedSection(
                header: 'Technology Stack',
                children: [
                  Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        _TechPill('Flutter 3.x'),
                        _TechPill('Dart 3.x'),
                        _TechPill('Material 3'),
                        _TechPill('Riverpod 2.6'),
                        _TechPill('GoRouter 17'),
                        _TechPill('Liquid Glass'),
                        _TechPill('g1455 Shaders'),
                        _TechPill('Google ML Kit'),
                        _TechPill('AES-256 PBKDF2'),
                        _TechPill('Local Biometrics'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Footer Note ──
              Center(
                child: Text(
                  'Made with ❤️ and pure obsession by Joel P Joji',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant.withAlphaFactor(0.7),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureHighlightTile extends StatelessWidget {
  const _FeatureHighlightTile({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              color: scheme.primary.withAlphaFactor(0.14),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(icon, size: 22, color: scheme.primary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TechPill extends StatelessWidget {
  const _TechPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: scheme.outlineVariant.withAlphaFactor(0.35)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}
