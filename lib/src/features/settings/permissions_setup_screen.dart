import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../auth/auth_controller.dart';
import '../../features/common/route_scaffold.dart';
import '../../features/launch/brand_widgets.dart';
import '../../features/settings/permission_setup_controller.dart';

class PermissionsSetupScreen extends ConsumerStatefulWidget {
  const PermissionsSetupScreen({super.key});

  @override
  ConsumerState<PermissionsSetupScreen> createState() =>
      _PermissionsSetupScreenState();
}

class _PermissionsSetupScreenState
    extends ConsumerState<PermissionsSetupScreen> {
  bool _requestingAll = false;

  Future<void> _finishSetup() async {
    if (_requestingAll) return;
    final user = ref.read(authControllerProvider).user;
    if (user == null) {
      context.go('/login');
      return;
    }

    setState(() => _requestingAll = true);
    try {
      if (!kIsWeb) {
        await [
          Permission.notification,
          Permission.camera,
          Permission.photos,
          Permission.storage,
          Permission.sms,
        ].request();
      } else {
        try {
          await Permission.notification.request();
        } catch (_) {}
        try {
          await Permission.camera.request();
        } catch (_) {}
      }

      await ref
          .read(permissionSetupControllerProvider.notifier)
          .setCompleted(user.id, true);

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Permissions setup complete.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      context.go('/');
    } finally {
      if (mounted) setState(() => _requestingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Setup')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const StaggeredFadeIn(
                      child: Text(
                        'Almost\nthere.',
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    StaggeredFadeIn(
                      delay: const Duration(milliseconds: 100),
                      child: Text(
                        'To get the most out of 1Wallet, we need a few permissions to automate your expense tracking.',
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.7),
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    StaggeredFadeIn(
                      delay: const Duration(milliseconds: 200),
                      child: Container(
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh.withValues(
                            alpha: 0.4,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Column(
                          children: [
                            _buildPermissionItem(
                              context,
                              icon: Icons.sms_rounded,
                              title: 'Auto-Capture (SMS)',
                              description:
                                  'Automatically track expenses from bank messages.',
                            ),
                            Divider(
                              height: 1,
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.3,
                              ),
                              indent: 64,
                            ),
                            _buildPermissionItem(
                              context,
                              icon: Icons.notifications_active_rounded,
                              title: 'Notifications',
                              description:
                                  'Get timely reminders for upcoming bills and budgets.',
                            ),
                            Divider(
                              height: 1,
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.3,
                              ),
                              indent: 64,
                            ),
                            _buildPermissionItem(
                              context,
                              icon: Icons.camera_alt_rounded,
                              title: 'Attachments',
                              description:
                                  'Attach receipts and documents to your transactions.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: StaggeredFadeIn(
                delay: const Duration(milliseconds: 300),
                child: FilledButton.icon(
                  onPressed: _requestingAll ? null : _finishSetup,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(
                    _requestingAll ? 'Requesting...' : 'Finish Setup',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: scheme.onPrimaryContainer, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 14,
                    height: 1.3,
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
