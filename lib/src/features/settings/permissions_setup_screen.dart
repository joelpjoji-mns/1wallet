import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../auth/auth_controller.dart';
import '../../services/notification_service.dart';
import '../../widgets/app_kit.dart';
import '../capture/sms_inbox_reader.dart';
import '../common/route_scaffold.dart';
import 'permission_setup_controller.dart';

class PermissionsSetupScreen extends ConsumerStatefulWidget {
  const PermissionsSetupScreen({super.key});

  @override
  ConsumerState<PermissionsSetupScreen> createState() =>
      _PermissionsSetupScreenState();
}

class _PermissionsSetupScreenState extends ConsumerState<PermissionsSetupScreen> {
  var _loading = true;
  var _requestingSms = false;
  var _requestingAll = false;
  var _smsAvailable = false;
  PermissionStatus _notificationStatus = PermissionStatus.denied;
  PermissionStatus _cameraStatus = PermissionStatus.denied;
  PermissionStatus _photosStatus = PermissionStatus.denied;
  PermissionStatus _storageStatus = PermissionStatus.denied;
  PermissionStatus _installStatus = PermissionStatus.denied;
  AndroidSmsPermissionState _smsState = const AndroidSmsPermissionState(
    read: AndroidSmsPermissionStatus.unavailable,
    receive: AndroidSmsPermissionStatus.unavailable,
    overall: 'unavailable',
  );

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  bool get _smsReady {
    if (!_smsAvailable) return true;
    return _smsState.overall == 'granted';
  }

  bool get _setupReady => _smsReady;

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final available = await isAndroidSmsInboxAvailable();
        final notification = await Permission.notification.status;
        final camera = await Permission.camera.status;
        final photos = await Permission.photos.status;
        final storage = await Permission.storage.status;
        final install = await Permission.requestInstallPackages.status;
      final state = available
          ? await getAndroidSmsPermissionState()
          : const AndroidSmsPermissionState(
              read: AndroidSmsPermissionStatus.unavailable,
              receive: AndroidSmsPermissionStatus.unavailable,
              overall: 'unavailable',
            );
      if (!mounted) return;
      setState(() {
        _smsAvailable = available;
        _smsState = state;
        _notificationStatus = notification;
        _cameraStatus = camera;
        _photosStatus = photos;
        _storageStatus = storage;
        _installStatus = install;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _allowSms() async {
    if (_requestingSms || !_smsAvailable) return;
    setState(() => _requestingSms = true);
    try {
      final status = await requestAndroidSmsPermission();
      await _refresh();
      if (!mounted) return;
      final message = switch (status) {
        AndroidSmsPermissionStatus.granted => 'SMS permission granted.',
        AndroidSmsPermissionStatus.blocked =>
          'SMS permission is blocked. Open app settings to allow it.',
        AndroidSmsPermissionStatus.denied => 'SMS permission denied for now.',
        AndroidSmsPermissionStatus.unavailable =>
          'SMS permission is available on Android only.',
      };
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
        );
    } finally {
      if (mounted) setState(() => _requestingSms = false);
    }
  }

  Future<void> _finishSetup() async {
    if (_requestingAll) return;
    final user = ref.read(authControllerProvider).user;
    if (user == null) {
      context.go('/login');
      return;
    }

    setState(() => _requestingAll = true);
    try {
      if (_smsAvailable && !_smsReady) {
        await requestAndroidSmsPermission();
      }
      await NotificationService.requestPermissions();
      await Permission.camera.request();
      await Permission.photos.request();
      await Permission.storage.request();
      await Permission.requestInstallPackages.request();
      await _refresh();
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
    final smsStatusLabel = !_smsAvailable
        ? 'Android only'
        : _smsReady
        ? 'Granted'
        : 'Needed';

    return RouteScaffold(
      title: 'Permissions setup',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: '1. Auto Capture access',
            subtitle:
                'SMS access powers transaction-alert parsing and queue suggestions.',
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Checking SMS availability…'),
                    ),
                  )
                : Column(
                    children: [
                      InfoRow(
                        icon: Icons.sms_outlined,
                        label: 'SMS permission',
                        value: smsStatusLabel,
                        tone: _smsReady
                            ? MetricTone.positive
                            : MetricTone.warning,
                      ),
                      const Gap(10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed:
                                (_smsReady || !_smsAvailable || _requestingSms)
                                ? null
                                : _allowSms,
                            icon: const Icon(Icons.shield_outlined),
                            label: Text(
                              _requestingSms ? 'Requesting…' : 'Allow SMS',
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => context.push('/auto-capture'),
                            icon: const Icon(Icons.auto_awesome_outlined),
                            label: const Text('Open Auto Capture'),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          const Gap(12),
          SectionCard(
            title: '2. Receipts and media',
            subtitle:
                'Camera, photos, and files power receipt scanning and imports.',
            child: Column(
              children: [
                InfoRow(
                  icon: Icons.camera_alt_outlined,
                  label: 'Camera',
                  value: _permissionLabel(_cameraStatus),
                  tone: _permissionTone(_cameraStatus),
                ),
                InfoRow(
                  icon: Icons.photo_library_outlined,
                  label: 'Photos',
                  value: _permissionLabel(_photosStatus),
                  tone: _permissionTone(_photosStatus),
                ),
                InfoRow(
                  icon: Icons.file_upload_outlined,
                  label: 'Files',
                  value: _filePermissionLabel(_storageStatus),
                  tone: _permissionTone(_storageStatus),
                ),
                const Gap(10),
                FilledButton.tonalIcon(
                  onPressed: () => context.push('/add'),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Open Add record'),
                ),
              ],
            ),
          ),
          const Gap(12),
          SectionCard(
            title: '3. Alerts and updates',
            subtitle:
                'Notifications and APK install permission support update alerts and in-app downloads.',
            child: Column(
              children: [
                InfoRow(
                  icon: Icons.notifications_active_outlined,
                  label: 'Notifications',
                  value: _permissionLabel(_notificationStatus),
                  tone: _permissionTone(_notificationStatus),
                ),
                InfoRow(
                  icon: Icons.install_mobile_outlined,
                  label: 'Install updates',
                  value: _permissionLabel(_installStatus),
                  tone: _permissionTone(_installStatus),
                ),
                const Gap(10),
                FilledButton.tonalIcon(
                  onPressed: () => context.push('/updates'),
                  icon: const Icon(Icons.system_update_alt_outlined),
                  label: const Text('Open updates'),
                ),
              ],
            ),
          ),
          const Gap(12),
          SectionCard(
            title: '4. Finish',
            subtitle:
                'Finish asks for the permissions above now. You can change them later in Android settings.',
            child: Column(
              children: [
                InfoRow(
                  icon: Icons.check_circle_outline,
                  label: 'Required setup',
                  value: _setupReady ? 'Ready' : 'Needs SMS access',
                  tone: _setupReady ? MetricTone.positive : MetricTone.warning,
                ),
                const Gap(10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: _requestingAll ? null : _finishSetup,
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(_requestingAll ? 'Requesting…' : 'Finish'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => context.push('/device-permissions'),
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Manage permissions'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _permissionLabel(PermissionStatus status) {
  if (status.isGranted || status.isLimited) return 'Granted';
  if (status.isPermanentlyDenied || status.isRestricted) return 'Blocked';
  if (status.isDenied) return 'Needed';
  return 'Unknown';
}

String _filePermissionLabel(PermissionStatus status) {
  if (status.isGranted || status.isLimited) return 'Granted';
  if (status.isPermanentlyDenied || status.isRestricted) return 'Blocked';
  return 'System picker';
}

MetricTone _permissionTone(PermissionStatus status) {
  if (status.isGranted || status.isLimited) return MetricTone.positive;
  if (status.isDenied) return MetricTone.warning;
  if (status.isPermanentlyDenied || status.isRestricted) {
    return MetricTone.warning;
  }
  return MetricTone.standard;
}
