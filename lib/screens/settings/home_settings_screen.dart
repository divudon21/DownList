import 'package:flutter/material.dart';

import '../../services/settings_service.dart';
import '../../widgets/settings_components.dart';

class HomeSettingsScreen extends StatefulWidget {
  const HomeSettingsScreen({super.key, required this.settings});
  final SettingsService settings;

  @override
  State<HomeSettingsScreen> createState() => _HomeSettingsScreenState();
}

class _HomeSettingsScreenState extends State<HomeSettingsScreen> {
  bool? _expanded;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await widget.settings.getHomeExpandedOnStart();
      if (mounted) setState(() { _expanded = value; _error = null; });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load the preference.');
    }
  }

  Future<void> _setExpanded(bool value) async {
    setState(() { _saving = true; _error = null; });
    try {
      await widget.settings.setHomeExpandedOnStart(value);
      if (mounted) setState(() => _expanded = value);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save the preference.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SettingsPage(title: 'Home', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SettingsSectionTitle('Download panel'),
      SettingsGroup(children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
          secondary: Icon(Icons.unfold_more_rounded, color: colors.onSurfaceVariant),
          title: const Text('Expand on startup', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(_expanded == true ? 'Start with the download controls visible' : 'Start with only the URL box visible'),
          value: _expanded ?? false,
          onChanged: _expanded == null || _saving ? null : _setExpanded,
        ),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
        child: Text('This sets the initial layout when you next open the app. Tap the URL box to expand it at any time.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: TextStyle(color: colors.error)),
        if (_expanded == null) TextButton(onPressed: _load, child: const Text('Retry')),
      ],
    ]));
  }
}
