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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: appearance,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return SettingsPage(title: 'Appearance', child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SettingsSectionTitle('Theme'),
        SettingsGroup(children: [
          ExpansionTile(
            key: const PageStorageKey('appearance-theme'),
            shape: const Border(),
            collapsedShape: const Border(),
            leading: Icon(Icons.brightness_6_outlined, color: colors.onSurfaceVariant),
            title: const Text('App theme', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(_themeLabel(appearance.themeMode)),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            children: [
              for (final mode in ThemeMode.values)
                ListTile(
                  key: ValueKey('theme-${mode.name}'),
                  leading: Icon(mode == ThemeMode.system ? Icons.brightness_auto_outlined : mode == ThemeMode.light ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
                  title: Text(_themeLabel(mode)),
                  trailing: appearance.themeMode == mode ? Icon(Icons.check_circle_rounded, color: colors.primary) : null,
                  selected: appearance.themeMode == mode,
                  onTap: () => appearance.setThemeMode(mode),
                ),
            ],
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
            secondary: Icon(Icons.contrast_rounded, color: isDark ? colors.onSurfaceVariant : colors.onSurface.withValues(alpha: 0.38)),
            title: const Text('High contrast dark theme', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(isDark ? 'Use darker surfaces in dark mode' : 'Available when dark mode is active'),
            value: appearance.highContrastDark,
            onChanged: isDark ? appearance.setHighContrastDark : null,
          ),
        ]),
        const SizedBox(height: 20),
        const SettingsSectionTitle('Personalisation'),
        SettingsGroup(children: [
          ExpansionTile(
            key: const PageStorageKey('appearance-colours'),
            shape: const Border(),
            collapsedShape: const Border(),
            leading: Icon(Icons.palette_outlined, color: colors.onSurfaceVariant),
            title: const Text('App colour', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${appearance.accent.name} · ${appAccents.length} colours'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              LayoutBuilder(builder: (context, constraints) {
                final columns = constraints.maxWidth < 290 ? 3 : 5;
                return GridView.builder(
                  key: const PageStorageKey('accent-grid-scroll'),
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
            ],
          ),
          ExpansionTile(
            key: const PageStorageKey('appearance-fonts'),
            shape: const Border(),
            collapsedShape: const Border(),
            leading: Icon(Icons.text_fields_rounded, color: colors.onSurfaceVariant),
            title: const Text('App text', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(appearance.font.name),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            children: [
              for (final font in appFonts)
                ListTile(
                  key: ValueKey('font-${font.id}'),
                  title: Text(font.name, style: TextStyle(fontFamily: font.family, fontWeight: FontWeight.w600)),
                  subtitle: Text(font.description, style: TextStyle(fontFamily: font.family)),
                  trailing: appearance.font.id == font.id ? Icon(Icons.check_circle_rounded, color: colors.primary) : null,
                  selected: appearance.font.id == font.id,
                  onTap: () => appearance.setFont(font),
                ),
            ],
          ),
        ]),
      ]));
    },
  );
}
