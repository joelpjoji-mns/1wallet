import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../auth/auth_controller.dart';
import '../../design/tokens.dart';
import '../../features/launch/brand_widgets.dart';
import '../../features/settings/permission_setup_controller.dart';
import '../../widgets/app_kit.dart';
import '../common/route_scaffold.dart';

class PermissionsSetupScreen extends ConsumerStatefulWidget {
  const PermissionsSetupScreen({super.key});

  @override
  ConsumerState<PermissionsSetupScreen> createState() =>
      _PermissionsSetupScreenState();
}

class _PermissionsSetupScreenState
    extends ConsumerState<PermissionsSetupScreen> {
  bool _finishing = false;
  String? _errorMessage;

  Future<void> _finishSetup({required bool requestPermissions}) async {
    if (_finishing) return;
    final ownerId = ref.read(authControllerProvider).ownerId;
    if (ownerId == null) {
      context.go('/login');
      return;
    }

    setState(() {
      _finishing = true;
      _errorMessage = null;
    });
    var requesting = requestPermissions;
    try {
      var allGranted = false;
      if (requestPermissions) {
        final permissions = [
          Permission.notification,
          Permission.camera,
          if (!kIsWeb) Permission.photos,
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
            Permission.storage,
            Permission.sms,
          ],
        ];
        final statuses = await permissions.request();
        allGranted = permissions.every(
          (permission) => statuses[permission]?.isGranted ?? false,
        );
      }
      requesting = false;

      if (!mounted) return;
      if (ref.read(authControllerProvider).ownerId != ownerId) {
        context.go('/login');
        return;
      }
      await ref
          .read(permissionSetupControllerProvider.notifier)
          .setCompleted(ownerId, true);

      if (!mounted) return;
      if (ref.read(authControllerProvider).ownerId != ownerId) {
        context.go('/login');
        return;
      }
      showAppSnackBar(
        context,
        !requestPermissions
            ? 'You can manage permissions later in Settings.'
            : allGranted
            ? 'Permissions are ready.'
            : 'Some permissions were not granted. Change them later in Settings.',
      );
      context.go('/');
    } catch (error, stack) {
      debugPrint('Could not finish permission setup: ${error.runtimeType}');
      debugPrintStack(stackTrace: stack);
      if (mounted) {
        setState(() {
          _errorMessage = requesting
              ? 'Could not request permissions. Try again or choose Not now.'
              : 'Could not save setup. Check device storage and try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return RouteScaffold(
      title: 'Setup',
      scrollView: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              primary: false,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StaggeredFadeIn(
                    child: Text(
                      'Almost\nthere.',
                      textAlign: TextAlign.left,
                      style:
                          (MediaQuery.textScalerOf(context).scale(14) > 20
                                  ? theme.textTheme.headlineLarge
                                  : theme.textTheme.displayMedium)
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                height: 1.1,
                                letterSpacing: -1,
                              ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  StaggeredFadeIn(
                    delay: const Duration(milliseconds: 100),
                    child: Text(
                      'These permissions are optional. Allow them now or set them up later in Settings.',
                      textAlign: TextAlign.left,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  StaggeredFadeIn(
                    delay: const Duration(milliseconds: 200),
                    child: AppPanel(
                      glass: true,
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          if (!kIsWeb &&
                              defaultTargetPlatform ==
                                  TargetPlatform.android) ...[
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
                          ],
                          _buildPermissionItem(
                            context,
                            icon: Icons.notifications_active_rounded,
                            title: 'Notifications',
                            description:
                                'Get timely reminders for upcoming bills.',
                          ),
                          Divider(
                            height: 1,
                            color: scheme.outlineVariant.withValues(alpha: 0.3),
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
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: StaggeredFadeIn(
              delay: const Duration(milliseconds: 300),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_errorMessage != null) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _errorMessage!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  FilledButton.icon(
                    onPressed: _finishing
                        ? null
                        : () => _finishSetup(requestPermissions: true),
                    style: AppButtonStyles.cta,
                    icon: _finishing
                        ? const AppInlineSpinner()
                        : const Icon(Icons.check_circle_outline_rounded),
                    label: Text(_finishing ? 'Please wait...' : 'Allow access'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(
                    onPressed: _finishing
                        ? null
                        : () => _finishSetup(requestPermissions: false),
                    style: AppButtonStyles.cta,
                    child: const Text('Not now'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: scheme.primary.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Icon(icon, color: scheme.primary, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
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
