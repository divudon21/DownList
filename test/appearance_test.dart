import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_agent_downloader/screens/settings/appearance_settings_screen.dart';
import 'package:ai_agent_downloader/services/appearance_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Preferences persist and invalid values fall back safely', () async {
    SharedPreferences.setMockInitialValues({'appearance_theme': 'invalid', 'appearance_accent': 'invalid', 'appearance_font': 'invalid'});
    final appearance = AppearanceService();
    await appearance.initialize();
    expect(appearance.themeMode, ThemeMode.system);
    expect(appearance.accent.id, 'indigo');
    expect(appearance.font.id, 'system');
    await appearance.setThemeMode(ThemeMode.dark);
    await appearance.setHighContrastDark(true);
    await appearance.setAccent(appAccents[3]);
    await appearance.setFont(appFonts[2]);
    final restored = AppearanceService();
    await restored.initialize();
    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.highContrastDark, isTrue);
    expect(restored.accent.id, 'teal');
    expect(restored.font.id, 'nunito');
    expect(restored.theme(Brightness.dark).textTheme.bodyMedium!.fontFamily, 'Nunito');
    expect(restored.theme(Brightness.dark).colorScheme.surface, Colors.black);
    expect(restored.theme(Brightness.light).colorScheme.surface, isNot(Colors.black));
    await restored.setFont(appFonts.first);
    expect(restored.theme(Brightness.light).textTheme.bodyMedium!.fontFamily, isNot('Nunito'));
    appearance.dispose();
    restored.dispose();
  });

  test('Manrope selection persists and applies app-wide', () async {
    SharedPreferences.setMockInitialValues({});
    final appearance = AppearanceService();
    await appearance.setFont(appFonts.singleWhere((font) => font.id == 'manrope'));
    final restored = AppearanceService();
    await restored.initialize();
    expect(restored.font.id, 'manrope');
    expect(restored.theme(Brightness.light).textTheme.bodyMedium!.fontFamily, 'Manrope');
    appearance.dispose();
    restored.dispose();
  });

  test('All 15 accents and six text choices are present', () async {
    SharedPreferences.setMockInitialValues({});
    final appearance = AppearanceService();
    final light = <Color>{};
    final dark = <Color>{};
    for (final accent in appAccents) {
      await appearance.setAccent(accent);
      light.add(appearance.theme(Brightness.light).colorScheme.primary);
      dark.add(appearance.theme(Brightness.dark).colorScheme.primary);
    }
    expect(appAccents.length, 15);
    expect(light.length, 15);
    expect(dark.length, 15);
    expect(appFonts.length, 6);
    expect(appFonts.last.id, 'manrope');
    expect(appFonts.first.family, isNull);
    appearance.dispose();
  });

  testWidgets('Expandable controls, text and effective light/dark behaviour', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final appearance = AppearanceService();
    await appearance.initialize();
    await tester.pumpWidget(ListenableBuilder(
      listenable: appearance,
      builder: (_, __) => MaterialApp(
        themeMode: appearance.themeMode,
        theme: appearance.theme(Brightness.light),
        darkTheme: appearance.theme(Brightness.dark),
        home: AppearanceSettingsScreen(appearance: appearance),
      ),
    ));
    for (final tile in tester.widgetList<ExpansionTile>(find.byType(ExpansionTile))) {
      expect(tile.shape, const Border());
      expect(tile.collapsedShape, const Border());
    }
    expect(find.byKey(const ValueKey('theme-dark')), findsNothing);
    expect(find.text('Teal'), findsNothing);
    expect(find.text('Nunito'), findsNothing);
    final toggle = find.byType(SwitchListTile);
    expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
    await tester.tap(find.text('High contrast dark theme'));
    await tester.pumpAndSettle();
    expect(appearance.highContrastDark, isFalse);
    await tester.tap(find.text('App theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('theme-dark')));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).onChanged, isNotNull);
    await tester.tap(find.text('High contrast dark theme'));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('App theme'))).colorScheme.surface, Colors.black);
    final oldColor = Theme.of(tester.element(find.text('App theme'))).colorScheme.primary;
    await tester.ensureVisible(find.text('App colour'));
    await tester.tap(find.text('App colour'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Teal'));
    await tester.tap(find.text('Teal'));
    await tester.pumpAndSettle();
    expect(appearance.accent.id, 'teal');
    expect(Theme.of(tester.element(find.text('App theme'))).colorScheme.primary, isNot(oldColor));
    await tester.ensureVisible(find.text('App text'));
    await tester.tap(find.text('App text'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('font-nunito')));
    await tester.tap(find.byKey(const ValueKey('font-nunito')));
    await tester.pumpAndSettle();
    expect(appearance.font.id, 'nunito');
    expect(Theme.of(tester.element(find.text('App theme'))).textTheme.bodyMedium!.fontFamily, 'Nunito');
    await tester.ensureVisible(find.byKey(const ValueKey('font-manrope')));
    await tester.tap(find.byKey(const ValueKey('font-manrope')));
    await tester.pumpAndSettle();
    expect(appearance.font.id, 'manrope');
    expect(Theme.of(tester.element(find.text('App theme'))).textTheme.bodyMedium!.fontFamily, 'Manrope');
    await tester.ensureVisible(find.text('App theme'));
    await tester.ensureVisible(find.byKey(const ValueKey('theme-light')));
    await tester.tap(find.byKey(const ValueKey('theme-light')));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
    expect(appearance.highContrastDark, isTrue); // Restored when dark mode becomes active again.
    await tester.pumpWidget(const SizedBox());
    appearance.dispose();
  });
}
