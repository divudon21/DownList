import 'package:flutter/material.dart';

import '../../services/appearance_service.dart';
import '../../widgets/settings_components.dart';

class AppearanceSettingsScreen extends StatelessWidget {
  const AppearanceSettingsScreen({super.key, required this.appearance});
  final AppearanceService appearance;

  String _themeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'System default',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  Future<void> _chooseTheme(BuildContext context) async {
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('App theme'),
        contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final mode in ThemeMode.values)
            ListTile(
              title: Text(_themeLabel(mode)),
              leading: Icon(mode == ThemeMode.system ? Icons.brightness_auto_outlined : mode == ThemeMode.light ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
              trailing: appearance.themeMode == mode ? Icon(Icons.check_rounded, color: Theme.of(context).colorScheme.primary) : null,
              selected: appearance.themeMode == mode,
              onTap: () => Navigator.pop(context, mode),
            ),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
      ),
    );
    if (selected != null) await appearance.setThemeMode(selected);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: appearance,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      return SettingsPage(title: 'Appearance', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SettingsSectionTitle('Theme'),
        SettingsGroup(children: [
          SettingsRow(
            icon: Icons.brightness_6_outlined,
            title: 'App theme',
            subtitle: _themeLabel(appearance.themeMode),
            onTap: () => _chooseTheme(context),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
            secondary: Icon(Icons.contrast_rounded, color: colors.onSurfaceVariant),
            title: const Text('High contrast dark theme', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Use darker surfaces in dark mode'),
            value: appearance.highContrastDark,
            onChanged: appearance.setHighContrastDark,
          ),
        ]),
        const SizedBox(height: 20),
        const SettingsSectionTitle('App colour'),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          decoration: BoxDecoration(color: colors.surfaceContainerLowest, borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Choose your accent', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('${appearance.accent.name} · Applied throughout the app', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth < 290 ? 3 : 4;
              return GridView.builder(
                itemCount: appAccents.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, mainAxisExtent: 76, crossAxisSpacing: 4, mainAxisSpacing: 8),
                itemBuilder: (context, index) {
                  final accent = appAccents[index];
                  final selected = accent.id == appearance.accent.id;
                  return Semantics(
                    label: '${accent.name} accent',
                    selected: selected,
                    button: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => appearance.setAccent(accent),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Container(
                          width: 42, height: 42,
                          decoration: BoxDecoration(color: accent.color, shape: BoxShape.circle, border: Border.all(color: selected ? colors.onSurface : Colors.transparent, width: 2)),
                          child: selected ? Icon(Icons.check_rounded, color: accent.color.computeLuminance() > 0.35 ? Colors.black : Colors.white, size: 22) : null,
                        ),
                        const SizedBox(height: 5),
                        Text(accent.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
                      ]),
                    ),
                  );
                },
              );
            }),
          ]),
        ),
      ]));
    },
  );
}
