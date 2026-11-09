import 'package:flutter/material.dart';

import '../../services/update_service.dart';
import '../../widgets/settings_components.dart';

class UpdateSettingsScreen extends StatelessWidget {
  const UpdateSettingsScreen({super.key, required this.updates});
  final UpdateService updates;

  Future<void> _open(BuildContext context, UpdateRelease release) async {
    try { await updates.openRelease(release); }
    catch (_) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the release page.'))); }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SettingsPage(title: 'Updates', child: ListenableBuilder(
      listenable: updates,
      builder: (context, _) {
        final release = updates.available;
        final build = updates.installed;
        final compatible = release != null && build != null && release.isCompatibleWith(build);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SettingsSectionTitle('App updates'),
          SettingsGroup(children: [
            SettingsRow(
              icon: Icons.refresh_rounded,
              title: 'Check for updates',
              subtitle: updates.checking ? 'Checking…' : 'Find the latest available version',
              trailing: updates.checking ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : null,
              onTap: () { if (!updates.checking && updates.ready) updates.check(); },
            ),
          ]),
          if (updates.error != null) ...[
            const SizedBox(height: 12),
            _message(context, Icons.error_outline_rounded, 'Could not check for updates', updates.error!, colors.errorContainer, colors.onErrorContainer),
          ] else if (updates.checked && release == null) ...[
            const SizedBox(height: 12),
            _message(context, Icons.check_circle_outline_rounded, 'You’re up to date', build == null ? '' : 'Installed: ${build.versionName} (build ${build.versionCode})', colors.secondaryContainer, colors.onSecondaryContainer),
          ] else if (release != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(18)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(compatible ? 'Update available' : 'Reinstall required', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: colors.onPrimaryContainer)),
                const SizedBox(height: 4),
                Text(release.label, style: TextStyle(color: colors.onPrimaryContainer)),
                if (!compatible) ...[
                  const SizedBox(height: 8),
                  Text('This release has a different signing key and cannot be installed over this app. Uninstalling removes local app data. Save important settings first.', style: TextStyle(color: colors.onPrimaryContainer)),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(onPressed: () => _open(context, release), icon: const Icon(Icons.open_in_new_rounded), label: Text(compatible ? 'Update' : 'View release')),
              ]),
            ),
          ],
          const SizedBox(height: 22),
          const SettingsSectionTitle('Preferences'),
          SettingsGroup(children: [
            _toggle(Icons.autorenew_rounded, 'Auto check updates', 'Check when the app opens', updates.autoCheck, updates.ready && !updates.checking, (v) => updates.setOption('auto_check', v)),
            _toggle(Icons.notifications_outlined, 'Update notifications', 'Notify when an update is found', updates.notifications, updates.ready && !updates.checking, (v) => updates.setOption('notifications', v)),
            _toggle(Icons.science_outlined, 'Beta updates', 'Include pre-release versions', updates.includeBeta, updates.ready && !updates.checking, (v) => updates.setOption('include_beta', v)),
            _toggle(Icons.open_in_new_rounded, 'Show pop-up', 'Show available updates when the app opens', updates.popup, updates.ready && !updates.checking, (v) => updates.setOption('popup', v)),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
            child: Text('Automatic checks run when the app opens. Notifications require Android notification permission.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
          ),
        ]);
      },
    ));
  }

  Widget _toggle(IconData icon, String title, String subtitle, bool value, bool enabled, ValueChanged<bool> change) => SwitchListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
    secondary: Icon(icon),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text(subtitle),
    value: value,
    onChanged: enabled ? change : null,
  );

  Widget _message(BuildContext context, IconData icon, String title, String details, Color background, Color foreground) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(18)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: foreground), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: foreground)),
        if (details.isNotEmpty) ...[const SizedBox(height: 4), Text(details, style: TextStyle(color: foreground))],
      ])),
    ]),
  );
}
