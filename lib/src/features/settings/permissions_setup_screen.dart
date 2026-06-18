import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../auth/auth_controller.dart';

import '../../widgets/app_kit.dart';
import '../launch/brand_widgets.dart';
import '../capture/sms_inbox_reader.dart';
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
  var _requestingMedia = false;
  var _requestingAlerts = false;
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

  Future<void> _grantAll() async {
    if (_requestingAll) return;
    setState(() => _requestingAll = true);
    try {
      if (_smsAvailable && !_smsReady) {
        await requestAndroidSmsPermission();
      }
      await [
        Permission.notification,
        Permission.camera,
        Permission.photos,
        Permission.storage,
      ].request();
      await _refresh();
    } finally {
      if (mounted) setState(() => _requestingAll = false);
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
      await [
        Permission.notification,
        Permission.camera,
        Permission.photos,
        Permission.storage,
      ].request();
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

  Future<void> _requestMedia() async {
    if (_requestingMedia) return;
    setState(() => _requestingMedia = true);
    try {
      await [
        Permission.camera,
        Permission.photos,
        Permission.storage,
      ].request();
      await _refresh();
    } finally {
      if (mounted) setState(() => _requestingMedia = false);
    }
  }

  Future<void> _requestAlerts() async {
    if (_requestingAlerts) return;
    setState(() => _requestingAlerts = true);
    try {
      await Permission.notification.request();
      await _refresh();
    } finally {
      if (mounted) setState(() => _requestingAlerts = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final smsStatusLabel = !_smsAvailable
        ? 'Android only'
        : _smsReady
        ? 'Granted'
        : 'Needed';

    return Scaffold(
      body: LaunchBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      onPressed: () => context.pop(),
                    ),
                    const Spacer(),
                    Text(
                      'Permissions',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const StaggeredFadeIn(
                      child: Text(
                        'Almost\nthere.',
                        style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -1),
                      ),
                    ),
                    const SizedBox(height: 32),
                    StaggeredFadeIn(
                      delay: const Duration(milliseconds: 50),
                      child: OutlinedButton.icon(
                        onPressed: _requestingAll ? null : _grantAll,
                        icon: const Icon(Icons.flash_on_outlined),
                        label: Text(_requestingAll ? 'Requesting...' : 'Grant all permissions at once'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    StaggeredFadeIn(
                      delay: const Duration(milliseconds: 100),
                      child: GlassCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('1. Auto Capture', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            const SizedBox(height: 4),
                            Text('SMS access powers transaction-alert parsing.', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
                            const SizedBox(height: 16),
                            if (_loading) const Text('Checking SMS availability...') else ...[
                              InfoRow(icon: Icons.sms_outlined, label: 'SMS permission', value: smsStatusLabel, tone: _smsReady ? MetricTone.positive : MetricTone.warning),
                              if (!_smsReady && _smsAvailable) ...[
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _requestingSms ? null : _allowSms,
                                  icon: const Icon(Icons.shield_outlined),
                                  label: Text(_requestingSms ? 'Requesting...' : 'Allow SMS'),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    StaggeredFadeIn(
                      delay: const Duration(milliseconds: 200),
                      child: GlassCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('2. Receipts and media', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            const SizedBox(height: 4),
                            Text('Camera, photos, and files power receipt scanning.', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
                            const SizedBox(height: 16),
                            InfoRow(icon: Icons.camera_alt_outlined, label: 'Camera', value: _permissionLabel(_cameraStatus), tone: _permissionTone(_cameraStatus)),
                            InfoRow(icon: Icons.photo_library_outlined, label: 'Photos', value: _permissionLabel(_photosStatus), tone: _permissionTone(_photosStatus)),
                            InfoRow(icon: Icons.file_upload_outlined, label: 'Files', value: _filePermissionLabel(_storageStatus), tone: _permissionTone(_storageStatus)),
                            if (!_cameraStatus.isGranted || !_photosStatus.isGranted || !_storageStatus.isGranted) ...[
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: _requestingMedia ? null : _requestMedia,
                                icon: const Icon(Icons.shield_outlined),
                                label: Text(_requestingMedia ? 'Requesting...' : 'Allow media'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    StaggeredFadeIn(
                      delay: const Duration(milliseconds: 300),
                      child: GlassCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('3. Alerts and updates', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            const SizedBox(height: 4),
                            Text('Notifications support update alerts.', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7))),
                            const SizedBox(height: 16),
                            InfoRow(icon: Icons.notifications_active_outlined, label: 'Notifications', value: _permissionLabel(_notificationStatus), tone: _permissionTone(_notificationStatus)),
                            InfoRow(icon: Icons.install_mobile_outlined, label: 'Install updates', value: _permissionLabel(_installStatus), tone: _permissionTone(_installStatus)),
                            if (!_notificationStatus.isGranted || !_installStatus.isGranted) ...[
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: _requestingAlerts ? null : _requestAlerts,
                                icon: const Icon(Icons.shield_outlined),
                                label: Text(_requestingAlerts ? 'Requesting...' : 'Allow alerts'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 48),
                    StaggeredFadeIn(
                      delay: const Duration(milliseconds: 400),
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
            ],
          ),
        ),
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
