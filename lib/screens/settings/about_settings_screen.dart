import 'package:flutter/material.dart';

import '../../services/platform_service.dart';
import '../../widgets/settings_components.dart';

class AboutSettingsScreen extends StatefulWidget {
  const AboutSettingsScreen({super.key});

  @override
  State<AboutSettingsScreen> createState() => _AboutSettingsScreenState();
}

class _AboutSettingsScreenState extends State<AboutSettingsScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final version = await PlatformService.instance.getAppVersion();
      if (mounted) setState(() => _version = version);
    } catch (_) {
      // Version may be unavailable outside Android.
    }
  }

  Future<void> _openProject() async {
    try {
      await PlatformService.instance.openUrl('https://github.com/divudon21/DownList');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the project page.')));
    }
  }

  void _openLicenses() {
    showLicensePage(
      context: context,
      applicationName: 'DownList',
      applicationVersion: _version.isEmpty ? null : _version,
      applicationIcon: Padding(
        padding: const EdgeInsets.all(16),
        child: ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.asset('assets/images/downlist_logo.png', width: 64, height: 64)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SettingsPage(
      title: 'About',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colors.primaryContainer, colors.tertiaryContainer],
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset('assets/images/downlist_logo.png', width: 52, height: 52, filterQuality: FilterQuality.high)),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('DownList', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(_version.isEmpty ? 'App information' : 'Version $_version', style: TextStyle(color: colors.onSurfaceVariant)),
                ])),
              ]),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(child: FilledButton.tonalIcon(style: FilledButton.styleFrom(minimumSize: const Size(0, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), onPressed: _openLicenses, icon: const Icon(Icons.library_books_outlined, size: 19), label: const Text('Libraries'))),
                const SizedBox(width: 8),
                Expanded(child: FilledButton.icon(style: FilledButton.styleFrom(minimumSize: const Size(0, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), onPressed: _openProject, icon: const Icon(Icons.open_in_new_rounded, size: 19), label: const Text('GitHub'))),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        const SettingsSectionTitle('App'),
        SettingsGroup(children: [
          SettingsRow(
            icon: Icons.code_rounded,
            title: 'Source code',
            subtitle: 'View the DownList project',
            onTap: _openProject,
          ),
          SettingsRow(
            icon: Icons.description_outlined,
            title: 'Open-source licenses',
            subtitle: 'Libraries used by DownList',
            onTap: _openLicenses,
          ),
        ]),
      ]),
    );
  }
}
