import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/app_kit.dart';
import '../capture/sms_inbox_reader.dart';
import '../common/route_scaffold.dart';

class PermissionsSetupScreen extends StatefulWidget {
  const PermissionsSetupScreen({super.key});

  @override
  State<PermissionsSetupScreen> createState() => _PermissionsSetupScreenState();
}

class _PermissionsSetupScreenState extends State<PermissionsSetupScreen> {
  var _loading = true;
  var _requestingSms = false;
  var _smsAvailable = false;
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
                'Camera/photos access is requested only when you scan or attach receipts.',
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
            title: '3. Review and finish',
            subtitle: 'You can revisit these permissions anytime in Settings.',
            child: Column(
              children: [
                InfoRow(
                  icon: Icons.check_circle_outline,
                  label: 'Setup status',
                  value: _setupReady ? 'Ready' : 'Needs SMS access',
                  tone: _setupReady ? MetricTone.positive : MetricTone.warning,
                ),
                const Gap(10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: () => context.go('/'),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Continue'),
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
