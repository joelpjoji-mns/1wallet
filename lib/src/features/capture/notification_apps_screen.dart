import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import 'sms_inbox_reader.dart'; // we put the native methods here

class NotificationAppsScreen extends ConsumerStatefulWidget {
  const NotificationAppsScreen({super.key});

  @override
  ConsumerState<NotificationAppsScreen> createState() => _NotificationAppsScreenState();
}

class _NotificationAppsScreenState extends ConsumerState<NotificationAppsScreen> {
  List<AndroidInstalledApp>? _apps;
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    final apps = await getAndroidInstalledApps();
    if (mounted) {
      setState(() {
        _apps = apps;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerProvider);
    final prefs = state.preferences;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final targetPackages = prefs.notificationTargetPackages.map((e) => e.toLowerCase()).toSet();

    List<AndroidInstalledApp> filteredApps = [];
    if (_apps != null) {
      if (_searchQuery.isEmpty) {
        filteredApps = _apps!;
      } else {
        filteredApps = _apps!.where((app) =>
            app.appName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            app.packageName.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Target Apps')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search apps...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
                if (_isLoading)
                  const Expanded(child: Center(child: CircularProgressIndicator()))
                else if (_apps == null || _apps!.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text('No apps found or unsupported platform.'),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: filteredApps.length,
                      itemBuilder: (context, index) {
                        final app = filteredApps[index];
                        final isEnabled = targetPackages.contains(app.packageName.toLowerCase());

                        return SwitchListTile(
                          secondary: AppIconWidget(packageName: app.packageName),
                          title: Text(app.appName, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(app.packageName, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                          value: isEnabled,
                          onChanged: (val) {
                            final next = Set<String>.from(prefs.notificationTargetPackages);
                            if (val) {
                              next.add(app.packageName.toLowerCase());
                            } else {
                              next.remove(app.packageName.toLowerCase());
                            }
                            ref.read(ledgerProvider.notifier).updatePreferences(
                                  prefs.copyWith(notificationTargetPackages: next.toList()),
                                );
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AppIconWidget extends StatefulWidget {
  final String packageName;
  const AppIconWidget({required this.packageName, super.key});

  @override
  State<AppIconWidget> createState() => _AppIconWidgetState();
}

class _AppIconWidgetState extends State<AppIconWidget> {
  static final Map<String, dynamic> _iconCache = {};
  
  @override
  void initState() {
    super.initState();
    if (!_iconCache.containsKey(widget.packageName)) {
      _loadIcon();
    }
  }
  
  Future<void> _loadIcon() async {
    final iconData = await getAndroidAppIcon(widget.packageName);
    if (mounted) {
      setState(() {
        _iconCache[widget.packageName] = iconData;
      });
    } else {
      _iconCache[widget.packageName] = iconData;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_iconCache.containsKey(widget.packageName)) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    
    final iconData = _iconCache[widget.packageName];
    if (iconData == null) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Icon(Icons.android, size: 32),
      );
    }
    
    return Image.memory(
      iconData,
      width: 40,
      height: 40,
      fit: BoxFit.contain,
    );
  }
}
