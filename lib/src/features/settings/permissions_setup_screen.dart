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
  ConsumerState<PermissionsSetupScreen> createState() => _PermissionsSetupScreenState();
}

class _PermissionsSetupScreenState extends ConsumerState<PermissionsSetupScreen> {
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
      await [
        Permission.notification,
        Permission.camera,
        Permission.photos,
        Permission.storage,
        Permission.sms,
      ].request();
      
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
    return RouteScaffold(
      title: 'Setup',
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const StaggeredFadeIn(
                    child: Text(
                      'Almost\nthere.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -1),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Tap below to grant all necessary permissions and finish setting up.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  StaggeredFadeIn(
                    delay: const Duration(milliseconds: 200),
                    child: FilledButton.icon(
                      onPressed: _requestingAll ? null : _finishSetup,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(_requestingAll ? 'Requesting...' : 'Finish Setup'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
