import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../widgets/app_kit.dart';
import '../capture/sms_inbox_reader.dart';
import '../common/route_scaffold.dart';

class DevicePermissionsScreen extends StatefulWidget {
  const DevicePermissionsScreen({super.key});

  @override
  State<DevicePermissionsScreen> createState() =>
      _DevicePermissionsScreenState();
}

class _DevicePermissionsScreenState extends State<DevicePermissionsScreen> {
  var _loading = true;
  var _smsAvailable = false;
  var _requestingSms = false;
  var _requestingMedia = false;
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

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final available = await isAndroidSmsInboxAvailable();
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
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _smsAvailable = false;
        _smsState = const AndroidSmsPermissionState(
          read: AndroidSmsPermissionStatus.unavailable,
          receive: AndroidSmsPermissionStatus.unavailable,
          overall: 'unavailable',
        );
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestSms() async {
    if (_requestingSms) return;
    setState(() => _requestingSms = true);
    try {
      final status = await requestAndroidSmsPermission();
      await _refresh();
      if (!mounted) return;
      final message = switch (status) {
        AndroidSmsPermissionStatus.granted => 'SMS permission granted.',
        AndroidSmsPermissionStatus.blocked =>
          'SMS permission is blocked by the OS. Open app settings to allow it.',
        AndroidSmsPermissionStatus.denied => 'SMS permission denied.',
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

  Future<void> _requestMedia() async {
    if (_requestingMedia) return;
    setState(() => _requestingMedia = true);
    try {
      await [
        Permission.camera,
        Permission.photos,
        Permission.storage,
      ].request();
    } finally {
      if (mounted) setState(() => _requestingMedia = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RouteScaffold(
      title: 'Device permissions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: 'SMS capture',
            subtitle:
                'Used for transaction-alert parsing and review queue suggestions.',
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
                        label: 'SMS inbox reader',
                        value: _smsAvailable ? 'Available' : 'Android only',
                        tone: _smsAvailable
                            ? MetricTone.positive
                            : MetricTone.warning,
                      ),
                      InfoRow(
                        icon: Icons.security_outlined,
                        label: 'SMS permission',
                        value: _smsPermissionLabel(_smsState),
                        tone: _smsPermissionTone(_smsState),
                      ),
                      const Gap(10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: (!_smsAvailable || _requestingSms)
                                ? null
                                : _requestSms,
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
            title: 'Camera and photos',
            subtitle:
                'Receipt capture requests camera/photos permission only when you use those flows.',
            child: Column(
              children: [
                const InfoRow(
                  icon: Icons.camera_alt_outlined,
                  label: 'Camera',
                  value: 'Requested on first use',
                ),
                const InfoRow(
                  icon: Icons.photo_library_outlined,
                  label: 'Photos',
                  value: 'Requested on first use',
                ),
                const Gap(10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: _requestingMedia ? null : _requestMedia,
                      icon: const Icon(Icons.shield_outlined),
                      label: Text(
                        _requestingMedia ? 'Requesting…' : 'Allow media',
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => context.push('/add'),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('Open Add record'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => context.push('/imports'),
                      icon: const Icon(Icons.file_upload_outlined),
                      label: const Text('Open imports'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Gap(12),
          SectionCard(
            title: 'Guided setup',
            subtitle:
                'Use the setup flow to walk through access and readiness before using automation.',
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () => context.push('/permissions-setup'),
                icon: const Icon(Icons.checklist_rtl_outlined),
                label: const Text('Open permissions setup'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _smsPermissionLabel(AndroidSmsPermissionState state) {
  return switch (state.overall) {
    'granted' => 'Granted',
    'partial' => 'Partial',
    'blocked' => 'Blocked',
    'denied' => 'Needed',
    'unavailable' => 'Unavailable',
    _ => 'Needed',
  };
}

MetricTone _smsPermissionTone(AndroidSmsPermissionState state) {
  return switch (state.overall) {
    'granted' => MetricTone.positive,
    'partial' => MetricTone.warning,
    'blocked' => MetricTone.warning,
    'denied' => MetricTone.warning,
    'unavailable' => MetricTone.standard,
    _ => MetricTone.warning,
  };
}
