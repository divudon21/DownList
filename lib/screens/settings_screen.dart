import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../services/update_service.dart';
import '../widgets/settings_components.dart';
import 'settings/about_settings_screen.dart';
import 'settings/notification_settings_screen.dart';
import 'settings/server_settings_screen.dart';
import 'settings/update_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.settings, required this.api, required this.updates});

  final SettingsService settings;
  final ApiService api;
  final UpdateService updates;

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
        children: [
          SettingsGroup(children: [
            SettingsRow(
              icon: Icons.dns_outlined,
              title: 'Server',
              subtitle: 'Server URL and connection',
              onTap: () => _open(context, ServerSettingsScreen(settings: settings, api: api)),
            ),
            SettingsRow(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              subtitle: 'Transfer progress and alerts',
              onTap: () => _open(context, const NotificationSettingsScreen()),
            ),
            SettingsRow(
              icon: Icons.system_update_rounded,
              title: 'Updates',
              subtitle: 'Check for new versions',
              onTap: () => _open(context, UpdateSettingsScreen(updates: updates)),
            ),
            SettingsRow(
              icon: Icons.info_outline_rounded,
              title: 'About',
              subtitle: 'App information and licenses',
              onTap: () => _open(context, const AboutSettingsScreen()),
            ),
          ]),
        ],
      ),
    );
  }
}
