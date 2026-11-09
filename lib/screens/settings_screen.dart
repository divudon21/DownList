import 'package:flutter/material.dart';
import 'package:liquid_glass_bottom_nav/liquid_glass_bottom_nav.dart';

import '../services/api_service.dart';
import '../services/appearance_service.dart';
import '../services/settings_service.dart';
import '../services/update_service.dart';
import '../widgets/settings_components.dart';
import 'settings/about_settings_screen.dart';
import 'settings/appearance_settings_screen.dart';
import 'settings/notification_settings_screen.dart';
import 'settings/home_settings_screen.dart';
import 'settings/server_settings_screen.dart';
import 'settings/update_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.settings, required this.api, required this.updates, required this.appearance});

  final SettingsService settings;
  final ApiService api;
  final UpdateService updates;
  final AppearanceService appearance;

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 32 + LiquidGlassNavBar.contentBottomInset),
        children: [
          SettingsGroup(children: [
            SettingsRow(
              icon: Icons.home_outlined,
              title: 'Home',
              subtitle: 'Download panel on startup',
              onTap: () => _open(context, HomeSettingsScreen(settings: settings)),
            ),
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
              icon: Icons.palette_outlined,
              title: 'Appearance',
              subtitle: 'Theme and app colour',
              onTap: () => _open(context, AppearanceSettingsScreen(appearance: appearance)),
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
