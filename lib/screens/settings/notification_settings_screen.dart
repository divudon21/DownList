import 'package:flutter/material.dart';

import '../../services/platform_service.dart';
import '../../widgets/settings_components.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> with WidgetsBindingObserver {
  bool _uploads = true;
  bool _downloads = true;
  bool _enabled = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final values = await PlatformService.instance.getNotificationSettings();
      if (!mounted) return;
      setState(() {
        _uploads = values['uploads'] ?? true;
        _downloads = values['downloads'] ?? true;
        _enabled = values['enabled'] ?? false;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Could not load notification settings.'; });
    }
  }

  Future<void> _change(String key, bool value) async {
    setState(() => _saving = true);
    try {
      await PlatformService.instance.setNotificationSetting(key, value);
      if (value && !_enabled) await PlatformService.instance.requestNotificationPermission();
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not update notification settings.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openSystemSettings() async {
    try {
      await PlatformService.instance.openNotificationSettings();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open Android notification settings.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final canChange = !_loading && !_saving && _error == null;
    return SettingsPage(
      title: 'Notifications',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SettingsSectionTitle('Transfer details'),
        SettingsGroup(children: [
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
            secondary: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Show upload details', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Device and GoFile uploads'),
            value: _uploads,
            onChanged: canChange ? (value) => _change('uploads', value) : null,
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
            secondary: const Icon(Icons.download_outlined),
            title: const Text('Show download details', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Server downloads'),
            value: _downloads,
            onChanged: canChange ? (value) => _change('downloads', value) : null,
          ),
        ]),
        const SizedBox(height: 22),
        const SettingsSectionTitle('Android'),
        SettingsGroup(children: [
          SettingsRow(
            icon: _enabled ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
            title: 'Notification access',
            subtitle: _loading ? 'Checking…' : _enabled ? 'Allowed' : 'Not allowed',
            onTap: _openSystemSettings,
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
          child: Text('Android may show a basic notification while transfers run in the background.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: colors.error)),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      ]),
    );
  }
}
